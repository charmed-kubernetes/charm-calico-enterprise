#!/usr/bin/env python3
# Copyright 2023 pguimaraes
# See LICENSE file for licensing details.
#
# Learn more at: https://juju.is/docs/sdk

"""Charm the service.

Refer to the following post for a quick-start guide that will help you
develop a new k8s charm using the Operator Framework:

https://discourse.charmhub.io/t/4208
"""

import os
import logging
import traceback
from subprocess import CalledProcessError, check_output

from conctl import getContainerRuntimeCtl

from ops.charm import CharmBase
from ops.main import main
from ops.framework import StoredState
from ops.model import ActiveStatus, BlockedStatus, WaitingStatus, MaintenanceStatus

# Log messages can be retrieved using juju debug-log
logger = logging.getLogger(__name__)

VALID_LOG_LEVELS = ["info", "debug", "warning", "error", "critical"]


TIGERA_DISTRO_VERSIONS ={
    "1.26": "3.15.2"
}

PLUGINS_PATH = "/usr/local/bin"
TMP_RENDER_PATH = "/tmp/templates/rendered"


class TigeraCalicoError(Exception):
    """Exception raised for errors in the input salary.

    Attributes:
        code -- numerical code explaining the issue
        message -- explanation of the error
    """
    ####
    # Error code
    # 0 - mismatch of k8s and tigera version
    ####

    def __init__(self, code, message="Error with Tigera"):
        self.code = code
        self.message = message
        super().__init__(self.message)


class TigeraCharm(CharmBase):
    """Charm the Tigera Calico EE."""

    def __init__(self, *args):
        super().__init__(*args)
        self.framework.observe(self.on.install, self.on_install)
        self.framework.observe(self.on.config_changed, self.on_config_changed)
        self.framework.observe(self.on.remove, self.on_remove)
        self.framework.observe(self.on.update_status, self.on_update_status)
        self.framework.observe(self.on.upgrade_charm, self.on_upgrade_charm)
        self.framework.observe(self.on.cni_relation_joined, self.on_cni_relation_joined)
        self.framework.observe(
            self.on.tigera_relation_changed, self.on_tigera_relation_changed
        )
        try:
            self.CTL = getContainerRuntimeCtl()
        except RuntimeError:
            logger.error(traceback.format_exc())
            raise TigeraCalicoError(0, "K8s and tigera version mismatch")            

    #######################
    ### Support Methods ###
    #######################

    def kubectl(self, *args):
        cmd = ["kubectl", "--kubeconfig", "/root/.kube/config"] + list(args)
        return check_output(cmd)

    def is_kubeconfig_available(self):
        for relation in self.model.relations["cni"]:
            for unit in relation.units:
                if relation.data[unit].get("kubeconfig-hash"):
                    return True
        return False

    def get_registry(self):
        registry = self.model.config["image-registry"]
        if not registry:
            registry = self.kube_ovn_peer_data("image-registry")
        return registry

    def configure_cni_relation(self):
        self.unit.status = MaintenanceStatus("Configuring CNI relation")
        cidr = self.model.config["default-cidr"]
        for relation in self.model.relations["cni"]:
            relation.data[self.unit]["cidr"] = cidr
            relation.data[self.unit]["cni-conf-file"] = "01-tigera.conflist"

    def load_manifest(self, name):
        with open("templates/" + name) as f:
            return list(yaml.safe_load_all(f))

    def render_template(self, template_file, destination, **kwargs):
        template = self.jinja2_environment.get_template(template_file)
        template.stream(**kwargs).dump(destination)
        return destination


    #######################
    ### Tigera  Methods ###
    #######################

    # Following: https://docs.tigera.io/calico-enterprise/latest/getting-started/install-on-clusters/kubernetes/generic-install

    @property
    def kubernetes_version(self):
        """Returns the k8s version
        """
        return ".".join(self.kubectl("kubectl", "version", "--server", "--short").\
            split("Server Version: v")[1].split(".")[:2])

    def apply_tigera_operator(self):
        """Applies the tigera operator yaml.

        Raises: TigeraCalicoError if tigera distro version is not found
        """
        version = TIGERA_DISTRO_VERSIONS.get(self.kubernetes_version)
        if not version:
            raise TigeraCalicoError(0, "K8s and tigera version mismatch")
        URL = f"https://downloads.tigera.io/ee/v{version}/manifests/tigera-operator.yaml"
        self.kubectl("apply", "-f", URL)

    def check_tigera_operator_deployment_status(self):
        """Checks if  tigera operator is ready.

        Returns True if the tigera is ready.
        """
        output = self.kubectl(
            "get", "pods", "-l", "app=tigera-operator", "-n", "tigera-operator", "-o",
             """'jsonpath={..status.conditions[?(@.type=="Ready")].status}'""")
        return True if "True" in output else False

    def pull_cnx_node_image(self):
        image = self.model.resources.fetch('cnx-node-image')

        if not image or os.path.getsize(image) == 0:
            self.unit.status = MaintenanceStatus('Pulling cnx-node image')
            image = self.config['cnx-node-image']
            set_http_proxy()
            CTL.pull(image)
        else:
            status.maintenance('Loading calico-node image')
            unzipped = '/tmp/calico-node-image.tar'
            with gzip.open(image, 'rb') as f_in:
                with open(unzipped, 'wb') as f_out:
                    f_out.write(f_in.read())
            CTL.load(unzipped)

    def check_tigera_status(self):
        """Checks if  tigera operator is ready.

        Returns True if the tigera is ready.
        """
        output = self.kubectl(
            "get", "tigerastatuses.operator.tigera.io",
            "calico", """-o=jsonpath='{.status.conditions[?(@.type=="Available")].status}'""")
        return True if "True" in output else False

    def implement_early_network(self):
        ## TODO: implement the early_network
        ## ...
        os.makedirs("/calico-early/", exist_ok=True)
        self.render_template(
            "templates/calico_bgp_layout.yaml.j2", "/calico-early/cfg.yaml", **self.config["bgp_parameters"])


    ###########################
    ### Charm Event Methods ###
    ###########################

    def on_install(self, event):
        """Installation routine.

        The following steps must be executed:
        1) early network: installs the cnx-node container and configures the BGP tunnel
        2) deploy cnx-node systemd
        3) wait until cnx-node is listening on port 8179
        """
        if self.config(self.config("disable_early_network")):
            return
        self.implement_early_network()

    def on_config_changed(self, event):
        """Config changed event processing
        """
        if not self.is_kubeconfig_available() or not service_cidr or not registry:
            self.unit.status = WaitingStatus("Waiting for CNI relation")
            return



if __name__ == "__main__":  # pragma: nocover
    main(TigeraCharm)
