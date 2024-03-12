#!/usr/bin/env python3
# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.
"""Dispatch logic for the calico-enterprise networking charm."""

import binascii
import ipaddress
import logging
import os
import pathlib
import tempfile
import time
from base64 import b64decode
from dataclasses import dataclass
from subprocess import CalledProcessError, check_output
from typing import Optional, Tuple, cast

import yaml
from jinja2 import Environment, FileSystemLoader
from ops.charm import CharmBase
from ops.framework import StoredState
from ops.main import main
from ops.model import ActiveStatus, BlockedStatus, MaintenanceStatus, StatusBase, WaitingStatus
from peer import CalicoEnterprisePeer

VALID_LOG_LEVELS = ["info", "debug", "warning", "error", "critical"]


TIGERA_DISTRO_VERSIONS = {"1.26": "3.16.1", "1.25": "3.15.2"}
KUBECONFIG_PATH = "/root/.kube/config"
PLUGINS_PATH = "/usr/local/bin"
EE_MANIFESTS = pathlib.Path("upstream/ee")


log = logging.getLogger(__name__)


@dataclass
class RegistrySecret:
    """Holds username and password for registry secret."""

    username: str
    password: str


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


class CalicoEnterpriseCharm(CharmBase):
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
        self.framework.observe(self.on.cni_relation_changed, self.on_cni_relation_changed)
        self.framework.observe(self.on.start, self.on_config_changed)
        self.framework.observe(self.on.upgrade_charm, self.on_config_changed)

        self.stored.set_default(tigera_configured=False)
        self.stored.set_default(pod_restart_needed=False)
        self.stored.set_default(tigera_cni_configured=False)

        self.peers = CalicoEnterprisePeer(self)
        self.framework.observe(self.peers.on.bgp_parameters_changed, self.on_config_changed)

        # try:
        #     self.CTL = getContainerRuntimeCtl()
        # except RuntimeError:
        #     log.error(traceback.format_exc())
        #     raise TigeraCalicoError(0, "K8s and tigera version mismatch")

    #######################
    ### Support Methods ###
    #######################

    def kubectl(self, *args):
        """Kubectl command implementation."""
        cmd = ["kubectl", "--kubeconfig", KUBECONFIG_PATH] + list(args)
        return check_output(cmd).decode("utf-8")

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

    def cni_to_calico_enterprise(self, event):
        """Repeat received CNI relation data to each calico-enterprise unit.

        CNI relation data is received over the cni relation only from
        kubernetes-control-plane units. The calico-enterprise peer relation
        shares the value around to each  unit.
        """
        log.debug("Sending CNI data over relation")
        for key in ["service-cidr", "image-registry"]:
            cni_data = event.relation.data[event.unit].get(key)
            log.debug("CNI data: %s", cni_data)
            if not cni_data:
                continue
            for relation in self.model.relations["calico-enterprise"]:
                relation.data[self.unit][key] = cni_data

    def configure_cni_relation(self):
        """Get."""
        self.unit.status = MaintenanceStatus("Configuring CNI relation")
        cidr = self.model.config["pod_cidr"]
        for relation in self.model.relations["cni"]:
            relation.data[self.unit]["cidr"] = cidr
            relation.data[self.unit]["cni-conf-file"] = "10-calico.conflist"
        self.stored.tigera_cni_configured = True

    def render_template(self, template_file, destination, **kwargs):
        """Render template_file to destination using kwargs."""
        template = self.jinja2_environment.get_template(template_file)
        template.stream(**kwargs).dump(destination)
        return destination

    def get_ip_range(self, n):
        """Return the # of bits that compose its range from an IPAddress."""
        return str(n).split("/")[1]

    def image_registry_secret(self) -> Tuple[Optional[RegistrySecret], str]:
        """Read Image Registry secret to username:password."""
        value = self.model.config["image_registry_secret"]
        if not value:
            return None, "Missing required 'image_registry_secret' config"
        try:
            decoded = b64decode(value).decode()
        except (binascii.Error, UnicodeDecodeError):
            # secret is not b64encoded plaintext, treat as plaintext
            decoded = value
        split = decoded.split(":")
        if len(split) != 2:
            return None, "Registry secret isn't formatted as <user>:<password>"
        return RegistrySecret(*split), ""

    #######################
    ### Tigera  Methods ###
    #######################

    # Following: https://docs.tigera.io/calico-enterprise/latest/getting-started/install-on-clusters/kubernetes/generic-install

    def preflight_checks(self):
        """Series of checks that should be done before any configuration change.

        Returns True if successful on all checks pass, False otherwise.
        """
        if not self.peers.bgp_layout.nodes:
            self.unit.status = BlockedStatus("BGP configuration is required.")
            return False

        val, err = self.image_registry_secret()
        if not val:
            self.unit.status = BlockedStatus(err)
            return False

        if not self.model.config["license"]:
            self.unit.status = BlockedStatus("Missing required 'license' config")
            return False

        try:
            ipaddress.ip_network(self.model.config["pod_cidr"])
        except ValueError:
            self.unit.status = BlockedStatus("'pod_cidr' config is not valid CIDR")
            return False
        try:
            ipaddress.ip_network(self.model.config["stable_ip_cidr"])
        except ValueError:
            self.unit.status = BlockedStatus("'stable_ip_cidr' config is not valid CIDR")
            return False
        # TODO: Fix this logic check.
        # hostname_found = False
        # for hostname, p in self.bgp_parameters:
        #     s = p["stableAddress"]
        #     if ipaddress.ip_address(s) not in stable_ip_cidr:
        #         self.unit.status = BlockedStatus(f"{s} is not present in {stable_ip_cidr}")
        #         return False
        #     if hostname == socket.get_hostname():
        #         hostname_found = True
        # if not hostname_found:
        #     self.unit.status = BlockedStatus("This node has no entry in the bgp_parameters")
        #     return False

        # if self.model.config["addons"] and not self.model.config["addons_storage_class"]:
        #     self.unit.status = BlockedStatus(
        #         "Addons specified but missing addons_storage_class info"
        #     )
        #     return False

        return True

    @property
    def kubernetes_version(self):
        """Returns the k8s version."""
        return ".".join(
            self.kubectl("version", "--short").split("Server Version: v")[1].split(".")[:2]
        )

    @property
    def tigera_version(self):
        """Returns the tigera installation version."""
        return (EE_MANIFESTS / "version").read_text()

    @property
    def manifests(self):
        """Load charm tigera manifests based on supported versions in the charm."""
        return EE_MANIFESTS / "manifests" / self.tigera_version

    def apply_tigera_operator(self):
        """Apply the tigera operator yaml.

        Raises: TigeraCalicoError if tigera distro version is not found
        """
        if not pathlib.Path(KUBECONFIG_PATH).exists():
            self.unit.status = BlockedStatus("Waiting for Kubeconfig to become available")
            return False
        installation_manifest = self.manifests / "tigera-operator.yaml"
        crds_manifest = self.manifests / "custom-resources.yaml"
        try:
            self.kubectl("create", "-f", installation_manifest)
            self.kubectl("create", "-f", crds_manifest)
        except CalledProcessError:
            # TODO implement a check which checks for tigera resources
            log.warning("Kubectl create failed - tigera operator may not be deployed.")
            return True

    def tigera_operator_deployment_status(self) -> StatusBase:
        """Check if tigera operator is ready.

        returns error in the event of a failed state.
        """
        try:
            output = self.kubectl(
                "get",
                "pods",
                "-l",
                "k8s-app=tigera-operator",
                "-n",
                "tigera-operator",
                "-o",
                "jsonpath={.items}",
            )
        except CalledProcessError:
            log.warning("Kubectl get pods failed - tigera operator may not be deployed.")
            output = []
        pods = yaml.safe_load(output)
        if len(pods) == 0:
            return WaitingStatus("tigera-operator POD not found yet")
        elif len(pods) > 1:
            return WaitingStatus(f"Too many tigera-operator PODs (num: {len(pods)})")
        status = pods[0]["status"]
        running = status["phase"] == "Running"
        healthy = all(_["status"] == "True" for _ in status["conditions"])
        if not running:
            return WaitingStatus(f"tigera-operator POD not running (phase: {status['phase']})")
        elif not healthy:
            failed = ", ".join(_["type"] for _ in status["conditions"] if _["status"] != "True")
            return WaitingStatus(
                f"tigera-operator POD conditions not healthy (conditions: {failed})"
            )
        return ActiveStatus("Ready")

    """
    def pull_cnx_node_image(self):
        image = self.model.resources.fetch('cnx-node-image')

        if not image or os.path.getsize(image) == 0:
            self.unit.status = MaintenanceStatus('Pulling cnx-node image')
            image = self.config['cnx-node-image']NamedTemporaryFile
            set_http_proxy()
            self.CTL.pull(image)
        else:
            status.maintenance('Loading calico-node image')
            unzipped = '/tmp/calico-node-image.tar'
            with gzip.open(image, 'rb') as f_in:
                with open(unzipped, 'wb') as f_out:
                    f_out.write(f_in.read())
            self.CTL.load(unzipped)
    """

    def check_tigera_status(self):
        """Check if  tigera operator is ready.

        Returns True if the tigera is ready.
        """
        output = self.kubectl(
            "wait",
            "-n",
            "tigera-operator",
            "--for=condition=ready",
            "pod",
            "-l",
            "k8s-app=tigera-operator",
        )
        return True if "met" in output else False

    def implement_early_network(self):
        """Implement the Early Network.

        The following steps must be executed:
        1) early network: installs the cnx-node container and configures the BGP tunnel
        2) deploy cnx-node systemd
        3) wait until cnx-node is listening on port 8179
        """
        os.makedirs("/calico-early/", exist_ok=True)
        self.peers.bgp_layout  # TODO implement the early_network

    def waiting_for_cni_relation(self):
        """Check if we should wait on CNI relation or all data is available."""
        service_cidr = self.peers.service_cidr
        registry = self.registry
        return not self.is_kubeconfig_available() or not service_cidr or not registry

    def pre_tigera_init_config(self):
        """Create required namespaces and label nodes before creating bgp_layout."""
        if not pathlib.Path(KUBECONFIG_PATH).exists():
            self.unit.status = WaitingStatus("Waiting for Kubeconfig to become available")
            return False
        if not self.peers.bgp_layout.nodes:
            self.unit.status = WaitingStatus("Waiting for BGP data from peers")
            return False

        try:
            self.kubectl("create", "ns", "tigera-operator")
            self.kubectl("create", "ns", "calico-system")
        except CalledProcessError:
            pass
        for node in self.peers.bgp_layout.nodes:
            hostname = node.hostname
            if not hostname:
                continue
            rack = node.labels.rack
            try:
                self.kubectl("label", "node", hostname, f"rack={rack}")
            except CalledProcessError:
                log.warning(f"Node labelling failed. Does {hostname} exist?")
                pass

        with tempfile.NamedTemporaryFile("w") as bgp_layout:
            yaml.safe_dump(self.peers.bgp_layout_config_map, stream=bgp_layout)
            self.kubectl("apply", "-n", "tigera-operator", "-f", bgp_layout.name)

        return True

    def patch_tigera_install(self):
        """Install Tigera operator."""
        nic_regex = self.model.config["nic_regex"]
        self.kubectl(
            "patch",
            "installations.operator.tigera.io",
            "default",
            "--type=merge",
            "-p",
            '{"spec": {"calicoNetwork": { "nodeAddressAutodetectionV4": {"interface": "%s"}}}}'
            % nic_regex,
        )
        return True

    def configure_bgp(self):
        """Configure BGP according to the charm options."""
        self.render_template(
            "bgppeer.yaml.j2",
            "/tmp/bgppeer.yaml",
            peer_set=self.peers.bgp_peer_set,
        )
        self.kubectl("apply", "-n", "tigera-operator", "-f", "/tmp/bgppeer.yaml")
        self.render_template(
            "ippools.yaml.j2",
            "/tmp/ippools.yaml",
            pod_cidr_range=self.model.config["pod_cidr_block_size"],
            pod_cidr=self.model.config["pod_cidr"],
            stable_ip_cidr=self.model.config["stable_ip_cidr"],
        )
        self.kubectl("apply", "-n", "tigera-operator", "-f", "/tmp/ippools.yaml")

    def set_active_status(self):
        """Set active if cni is configured."""
        if cast(bool, self.stored.tigera_cni_configured):
            self.unit.status = ActiveStatus()
            self.unit.set_workload_version(self.tigera_version)
            if self.unit.is_leader():
                self.app.status = ActiveStatus(self.tigera_version)

    ###########################
    ### Charm Event Methods ###
    ###########################

    def on_install(self, event):
        """Installation routine.

        Execute the Early Network stage if requested. The config of Tigera itself depends on k8s
        deployed and should be executed in the config-changed hook.
        """
        if not self.model.config["disable_early_network"]:
            self.implement_early_network()

    def on_update_status(self, event):
        """Update status.

        Unit must be in a configured state before status updates are made.
        """
        if not cast(bool, self.stored.tigera_configured):
            log.info("on_update_status: unit has not been configured yet; skipping status update.")
            return

        self.unit.status = self.tigera_operator_deployment_status()

    def on_cni_relation_changed(self, event):
        """Run CNI relation changed hook."""
        if not cast(bool, self.stored.tigera_configured):
            self.on_config_changed(event)

        self.cni_to_calico_enterprise(event)
        self.configure_cni_relation()

        self.set_active_status()

    def on_remove(self, event):
        """Run Remove hook."""
        return

    def on_upgrade_charm(self, event):
        """Run upgrade-charm hook."""
        return

    def on_config_changed(self, event):  # noqa C901, TODO: consider using reconciler
        """Config changed event processing.

        The leader needs to know the BGP information about every node and only the leader should
        apply the changes in the deployment.
        1) Check if the CNI relation exists
        2) Return if not leader
        3) Apply tigera operator
        """
        self.stored.tigera_configured = False
        if not self.preflight_checks():
            # TODO: Enters a defer loop
            # event.defer()
            return

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

        if not self.pre_tigera_init_config():
            # TODO: Enters a defer loop
            # event.defer()
            return

        self.unit.status = MaintenanceStatus("Configuring image secret")
        secret, err = self.image_registry_secret()
        if self.model.config["image_registry"] and secret:
            try:
                self.kubectl(
                    "delete",
                    "secret",
                    "tigera-pull-secret",
                    "-n",
                    "tigera-operator",
                )
            except CalledProcessError:
                pass
            self.kubectl(
                "create",
                "secret",
                "docker-registry",
                "tigera-pull-secret",
                f"--docker-username={secret.username}",
                f"--docker-password={secret.password}",
                f"--docker-server={self.model.config['image_registry']}",
                "-n",
                "tigera-operator",
            )

        self.unit.status = MaintenanceStatus("Applying Tigera Operator")
        if not self.apply_tigera_operator():
            # TODO: Enters a defer loop
            # event.defer()
            return

        self.unit.status = MaintenanceStatus("Configuring license")
        with tempfile.NamedTemporaryFile("w") as license:
            license.write(b64decode(self.model.config["license"]).rstrip().decode("utf-8"))
            license.flush()
            self.kubectl("apply", "-f", license.name)

        self.unit.status = MaintenanceStatus("Generating bgp yamls...")
        self.configure_bgp()

        self.unit.status = MaintenanceStatus("Applying Installation CRD")

        nic_autodetection = None
        if self.model.config["nic_autodetection_regex"]:
            if self.model.config["nic_autodetection_skip_interface"]:
                nic_autodetection = (
                    f"skipIterface: ${self.model.config['nic_autodetection_regex']}"
                )
            else:
                nic_autodetection = f"interface: {self.model.config['nic_autodetection_regex']}"
        elif self.model.config["nic_autodetection_cidrs"]:
            nic_autodetection = f"cidrs: {self.model.config['nic_autodetection_cidrs'].split(',')}"
        else:
            self.unit.status = BlockedStatus(
                "NIC Autodetection settings are required. (nic_autodetection_* settings.)"
            )
            return

        secret, err = self.image_registry_secret()
        if not secret:
            self.unit.status = BlockedStatus(err)
            return

        self.render_template(
            "calico_enterprise_install.yaml.j2",
            "/tmp/calico_enterprise_install.yaml",
            image_registry=self.model.config["image_registry"],
            image_registry_secret=f"{secret.username}:{secret.password}",
            image_path=self.model.config["image_path"],
            image_prefix=self.model.config["image_prefix"],
            nic_autodetection=nic_autodetection,
        )
        self.kubectl("apply", "-f", "/tmp/calico_enterprise_install.yaml")

        with tempfile.NamedTemporaryFile("w") as bgp_configuration:
            yaml.safe_dump(self.peers.bgp_configuration, stream=bgp_configuration)
            self.kubectl("apply", "-f", bgp_configuration.name)

        if self.model.config["addons"]:
            self.unit.status = MaintenanceStatus("Applying Addons")
            self.render_template(
                "addons.yaml.j2",
                "/tmp/addons.yaml",
                addons_storage_class=self.model.config["addons_storage_class"],
            )
            self.kubectl("apply", "-f", "-", "/tmp/addons.yaml")

        for i in range(0, 10):
            self.unit.status = MaintenanceStatus(f"Wait #{i} for the tigera operator...")
            if self.check_tigera_status():
                break
            time.sleep(24)
        self.unit.status = ActiveStatus("Node Configured")
        self.stored.tigera_configured = True


if __name__ == "__main__":  # pragma: nocover
    main(CalicoEnterpriseCharm)
