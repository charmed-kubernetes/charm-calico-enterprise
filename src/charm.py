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

import ipaddress
import logging
import os
import socket
import time
import traceback
from base64 import b64decode
from subprocess import check_output

import yaml
from conctl import getContainerRuntimeCtl
from jinja2 import Environment, FileSystemLoader
from ops.charm import CharmBase
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, BlockedStatus, MaintenanceStatus, WaitingStatus

# Log messages can be retrieved using juju debug-log
logger = logging.getLogger(__name__)

VALID_LOG_LEVELS = ["info", "debug", "warning", "error", "critical"]


TIGERA_DISTRO_VERSIONS = {"1.26": "3.15.2"}
KUBECONFIG_PATH = "/root/.kube/config"
PLUGINS_PATH = "/usr/local/bin"


log = logging.getLogger(__name__)


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

    stored = StoredState()

    def __init__(self, *args):
        super().__init__(*args)
        self.jinja2_environment = Environment(loader=FileSystemLoader("templates/"))
        self.framework.observe(self.on.install, self.on_install)
        self.framework.observe(self.on.config_changed, self.on_config_changed)
        self.framework.observe(self.on.remove, self.on_remove)
        self.framework.observe(self.on.update_status, self.on_update_status)
        self.framework.observe(self.on.upgrade_charm, self.on_upgrade_charm)
        self.framework.observe(self.on.cni_relation_joined, self.on_cni_relation_joined)
        self.framework.observe(self.on.tigera_relation_changed, self.on_config_changed)

        self.stored.set_default(tigera_configured=False)
        self.stored.set_default(pod_restart_needed=False)

        try:
            self.CTL = getContainerRuntimeCtl()
        except RuntimeError:
            logger.error(traceback.format_exc())
            raise TigeraCalicoError(0, "K8s and tigera version mismatch")

    #######################
    ### Support Methods ###
    #######################

    def kubectl(self, *args):
        """Kubectl command implementation."""
        cmd = ["kubectl", "--kubeconfig", KUBECONFIG_PATH] + list(args)
        return check_output(cmd)

    def is_kubeconfig_available(self):
        """Check if CNI relation exists and if kubeconfig is available."""
        for relation in self.model.relations["cni"]:
            for unit in relation.units:
                # Do not render the kubeconfig-hash as we share the node with either worker
                # or control nodes. They will render the kubeconfig.
                # We need this entry solely to check if k8s cluster is ready.
                if relation.data[unit].get("kubeconfig-hash"):
                    return True
        return False

    @property
    def registry(self):
        """Return image registry from config."""
        return self.model.config["image_registry"]

    def configure_cni_relation(self):
        """Get."""
        self.unit.status = MaintenanceStatus("Configuring CNI relation")
        cidr = self.model.config["default-cidr"]
        for relation in self.model.relations["cni"]:
            relation.data[self.unit]["cidr"] = cidr
            relation.data[self.unit]["cni-conf-file"] = "01-tigera.conflist"

    def render_template(self, template_file, destination, **kwargs):
        """Render template_file to destination using kwargs."""
        template = self.jinja2_environment.get_template(template_file)
        template.stream(**kwargs).dump(destination)
        return destination

    def tigera_peer_data(self, key):
        """Return the agreed data associated with the key from each tigera unit including self.

        If there isn't unity in the relation, return None.
        """
        joined_data = set()
        for relation in self.model.relations["tigera"]:
            for unit in relation.units | {self.unit}:
                data = relation.data[unit].get(key)
                joined_data.add(data)
        filtered = set(filter(bool, joined_data))
        return filtered.pop() if len(filtered) == 1 else None

    def get_ip_range(self, n):
        """Return the # of bits that compose its range from an IPAddress."""
        return str(n).split("/")[1]

    @property
    def bgp_parameters(self):
        """Return bgp parameter as a dict."""
        return yaml.safe_load(self.model.config["bgp_parameters"])

    #######################
    ### Tigera  Methods ###
    #######################

    # Following: https://docs.tigera.io/calico-enterprise/latest/getting-started/install-on-clusters/kubernetes/generic-install

    def preflight_checks(self):
        """Series of checks that should be done before any configuration change.

        Returns True if successful on all checks pass, False otherwise.
        """
        if not self.model.config["license"]:
            self.unit.status = BlockedStatus("Missing license config")
            return False

        try:
            ipaddress.ip_network(self.model.config["pod_cidr"])
        except ValueError:
            self.unit.status = BlockedStatus("Pod-to-Pod configuration is not valid CIDR")
            return False
        try:
            stable_ip_cidr = ipaddress.ip_network(self.model.config["stable_ip_cidr"])
        except ValueError:
            self.unit.status = BlockedStatus("Stable IP network is not valid CIDR")
            return False

        hostname_found = False
        for hostname, p in self.model.config["bgp_parameters"].items():
            s = p["stableAddress"]
            if ipaddress.ip_address(s) not in stable_ip_cidr:
                self.unit.status = BlockedStatus(f"{s} is not present in {stable_ip_cidr}")
                return False
            if hostname == socket.get_hostname():
                hostname_found = True
        if not hostname_found:
            self.unit.status = BlockedStatus("This node has no entry in the bgp_parameters")
            return False

        if self.model.config["addons"] and not self.model.config["addons_storage_class"]:
            self.unit.status = BlockedStatus(
                "Addons specified but missing addons_storage_class info"
            )
            return False

        return True

    @property
    def kubernetes_version(self):
        """Returns the k8s version."""
        return ".".join(
            self.kubectl("kubectl", "version", "--server", "--short")
            .split("Server Version: v")[1]
            .split(".")[:2]
        )

    def apply_tigera_operator(self):
        """Apply the tigera operator yaml.

        Raises: TigeraCalicoError if tigera distro version is not found
        """
        version = TIGERA_DISTRO_VERSIONS.get(self.kubernetes_version)
        if not version:
            raise TigeraCalicoError(0, "K8s and tigera version mismatch")
        url = f"https://downloads.tigera.io/ee/v{version}/manifests/tigera-operator.yaml"
        self.kubectl("apply", "-f", url)

    def check_tigera_operator_deployment_status(self):
        """Check if  tigera operator is ready.

        Returns True if the tigera is ready.
        """
        output = self.kubectl(
            "get",
            "pods",
            "-l",
            "app=tigera-operator",
            "-n",
            "tigera-operator",
            "-o",
            """'jsonpath={..status.conditions[?(@.type=="Ready")].status}'""",
        )
        return True if "True" in output else False

    """
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
    """

    def check_tigera_status(self):
        """Check if  tigera operator is ready.

        Returns True if the tigera is ready.
        """
        output = self.kubectl(
            "get",
            "tigerastatuses.operator.tigera.io",
            "calico",
            """-o=jsonpath='{.status.conditions[?(@.type=="Available")].status}'""",
        )
        return True if "True" in output else False

    def implement_early_network(self):
        """Implement the Early Network.

        The following steps must be executed:
        1) early network: installs the cnx-node container and configures the BGP tunnel
        2) deploy cnx-node systemd
        3) wait until cnx-node is listening on port 8179
        """
        ## TODO: implement the early_network
        ## ...
        os.makedirs("/calico-early/", exist_ok=True)
        self.render_template(
            "templates/calico_bgp_layout.yaml.j2",
            "/calico-early/cfg.yaml",
            **self.config["bgp_parameters"],
        )

    def waiting_for_cni_relation(self):
        """Check if we should wait on CNI relation or all data is available."""
        service_cidr = self.tigera_peer_data("service-cidr")
        registry = self.registry
        return not self.is_kubeconfig_available() or not service_cidr or not registry

    def configure_bgp(self):
        """Configure BGP according to the charm options."""
        bgp_parameters = self.model.config["bgp_parameters"]
        if not bgp_parameters:
            return
        self.render_template(
            "bgp_layout.yaml.j2",
            "/tmp/bgp_layout.yaml",
            bgp_parameters=self.bgp_parameters,
        )
        self.kubectl("apply", "-f", "-", "/tmp/bgp_layout.yaml")
        self.render_template(
            "bgppeer.yaml.j2",
            "/tmp/bgppeer.yaml",
            bgp_parameters=self.bgp_parameters,
        )
        self.kubectl("apply", "-f", "-", "/tmp/bgppeer.yaml")
        self.render_template(
            "ippools.yaml.j2",
            "/tmp/ippools.yaml",
            pod_cidr_range=self.get_ip_range(self.model.config["pod_cidr"]),
            pod_cidr=self.model.config["pod_cidr"],
            stable_ip_cidr=self.model.config["stable_ip_cidr"],
        )
        self.kubectl("apply", "-f", "-", "/tmp/ippools.yaml")

    ###########################
    ### Charm Event Methods ###
    ###########################

    def on_install(self, event):
        """Installation routine.

        Execute the Early Network stage if requested. The config of Tigera itself depends on k8s deployed
        and should be executed in the config-changed hook.
        """
        if not self.model.config["disable_early_network"]:
            self.implement_early_network()

    def on_update_status(self, event):
        """State machine of the charm.

        1) Only change the status if in active
        2) If kubeconfig and CNI relation exist
        """
        if isinstance(self.unit.status, ActiveStatus):
            log.info("on_update_status: unit not in active status: {self.unit.status}")
        if self.waiting_for_cni_relation():
            self.unit.status = WaitingStatus("Waiting for CNI relation")
            return

    def on_cni_relation_joined(self, event):
        """Run CNI relation joined hook."""
        self.configure_cni_relation()

    def on_remove(self, event):
        """Run Remove hook."""
        return

    def on_upgrade_charm(self, event):
        """Run upgrade-charm hook."""
        return

    def on_config_changed(self, event):
        """Config changed event processing.

        The leader needs to know the BGP information about every node and only the leader should apply
        the changes in the deployment.
        1) Check if the CNI relation exists
        2) Return if not leader
        3) Apply tigera operator
        """
        self.stored.tigera_configured = False
        if self.preflight_checks():
            return
        service_cidr = self.tigera_peer_data("service-cidr")

        if self.waiting_for_cni_relation():
            self.unit.status = WaitingStatus("Waiting for CNI relation")
            return

        if not self.unit.is_leader():
            # Only the leader should manage the operator setup
            log.info(
                "on_config_changed: detected k8s is up but this unit is not the leader, leaving..."
            )
            self.unit.status = ActiveStatus("Node Configured")
            self.stored.tigera_configured = True
            return

        self.unit.status = MaintenanceStatus("Applying Tigera Operator")
        self.apply_tigera_operator()
        for i in range(0, 10):
            self.unit.status = MaintenanceStatus(f"Wait #{i} for the tigera operator...")
            if self.check_tigera_status():
                break
            time.sleep(24)
        self.unit.status = ActiveStatus("Finished deploying Tigera Operator")

        self.unit.status = MaintenanceStatus("Configuring image secret and license file...")
        if self.model.config["image_registry"] and self.model.config["image_registry_secret"]:
            image_secret = (
                '\'{"auths":{"'
                + self.model.config["image_registry"]
                + '":{"auth":"'
                + self.model.config["image_registry_secret"]
                + '","email":""}}}\''
            )
            self.kubectl(
                "apply",
                "secret",
                "generic",
                "tigera-pull-secret",
                f"--from-literal=.dockerconfigjson={image_secret}",
                "--type=kubernetes.io/dockerconfigjson",
                "-n",
                "tigera-operator",
            )
        self.kubectl("apply", "-f", b64decode(self.model.config["license"]).rstrip())

        self.unit.status = MaintenanceStatus("Generating bgp yamls...")
        self.configure_bgp()

        self.unit.status = MaintenanceStatus("Applying Installation CRD")
        self.render_template(
            "calico_enterprise_install.yaml.j2",
            "/tmp/calico_enterprise_install.yaml",
            {
                "image_registry": self.model.config["image_registry"],
                "image_registry_secret": self.model.config["image_registry_secret"],
                "image_path": self.model.config["image_path"],
                "image_prefix": self.model.config["image_prefix"],
            },
        )
        self.kubectl("apply", "-f", "-", "/tmp/calico_enterprise_install.yaml")

        self.kubectl(
            "patch",
            "bgpconfiguration.projectcalico.org",
            "default",
            "-p",
            '\'{"spec":{"serviceClusterIPs": [{"cidr": "{{' + service_cidr + "}}\"}]}}'",
        )

        if self.model.config["addons"]:
            self.unit.status = MaintenanceStatus("Applying Addons")
            self.render_template(
                "addons.yaml.j2",
                "/tmp/addons.yaml",
                {"addons_storage_class": self.model.config["addons_storage_class"]},
            )
            self.kubectl("apply", "-f", "-", "/tmp/addons.yaml")

        self.unit.status = ActiveStatus("Node Configured")
        self.stored.tigera_configured = True


if __name__ == "__main__":  # pragma: nocover
    main(TigeraCharm)
