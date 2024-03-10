"""Define the calico-enterprise peer relation model."""

import logging
import socket
from ipaddress import ip_address
from pathlib import Path
from subprocess import CalledProcessError, check_output
from typing import List, Mapping, Optional, Set

import yaml
from ops.charm import CharmBase, EventBase, EventSource
from ops.framework import Object, ObjectEvents
from pydantic import BaseModel, Field, ValidationError, validator

log = logging.getLogger(__name__)
CALICO_EARLY_SERVICE = Path("/etc/systemd/system/calico-early.service")


def _valid_ip(value: str) -> str:
    assert ip_address(value), "Confirm this is a valid ip-address"
    return value


def _read_file_content(path: Path) -> Optional[str]:
    return path.read_text() if path.exists() else None


def _localhost_ips() -> List[ip_address]:
    try:
        lo_ifc = yaml.safe_load(check_output(["ip", "--json", "addr", "show", "lo"]))
    except (CalledProcessError, yaml.YAMLError):
        log.exception("Couldn't fetch the ip addresses of lo")
        return []
    return [
        ip_address(addr["local"])
        for ifc in lo_ifc
        if ifc["ifname"] == "lo"
        for addr in ifc["addr_info"]
    ]


class BGPPeer(BaseModel):
    """Represents a host interface's bpg peer info."""

    ip: str = Field(alias="peerIP")
    asn: int = Field(alias="peerASNumber")
    _validate_ip = validator("ip", allow_reuse=True)(_valid_ip)


class BGPPeerBinding(BaseModel):
    """Represents the binding of the TOR peer nodes."""

    ip: str
    asn: int
    rack: str
    _validate_ip = validator("ip", allow_reuse=True)(_valid_ip)

    def __hash__(self):
        """Make this hashable based on values."""
        return hash((type(self),) + tuple(self.__dict__.values()))


class BGPLabels(BaseModel):
    """Represents a host's bpg label info."""

    rack: str


class StableAddress(BaseModel):
    """Represents a host's stable address."""

    address: str
    _validate_address = validator("address", allow_reuse=True)(_valid_ip)


class BGPParameters(BaseModel):
    """Represents a host's bpg label info."""

    as_number: int = Field(alias="asNumber")
    interface_addresses: List[str] = Field(alias="interfaceAddresses")
    labels: BGPLabels
    peerings: List[BGPPeer]
    stable_address: StableAddress = Field(alias="stableAddress")
    hostname: str

    @validator("interface_addresses")
    def _each_valid_ip(cls, v):  # noqa: N805
        return [_valid_ip(_) for _ in v]


class BGPLayout(BaseModel):
    """Represents the cluster's bgp layout for all nodes."""

    nodes: List[BGPParameters]


def _early_service_cfg() -> Optional[BGPParameters]:
    """Read calico-early configuration yaml."""
    content = _read_file_content(CALICO_EARLY_SERVICE)

    if content is None:
        log.warning("No calico-early service definition file")
        return None

    yaml_location = ""
    env_token = "CALICO_EARLY_NETWORKING="
    for line in content.splitlines():
        if env_token in line:
            half = line.split(env_token, 1)[1]
            yaml_location, *_ = half.split(maxsplit=1)
            break

    content = _read_file_content(Path(yaml_location))

    if not content:
        log.warning(f"Couldn't find calico early config in {yaml_location}")
        return None

    stable_address = None
    for ip in _localhost_ips():
        if not ip.is_loopback:
            stable_address = ip

    early_cfg = yaml.safe_load(content)
    try:
        for node in early_cfg["spec"]["nodes"]:
            if node["stableAddress"]["address"] == str(stable_address):
                break
        else:
            raise KeyError(f"No node matches {stable_address}")
    except (TypeError, KeyError):
        log.warning(f"Config File didn't contain spec.nodes in config={yaml_location}")
        return None
    hostname = socket.gethostname()

    return BGPParameters(hostname=hostname, **node)


class BGPParametersEvent(EventBase):
    """Event indicating a unit updated its BGPParams."""


class CalicoEnterprisePeerEvents(ObjectEvents):
    """Publish Peer Relation Events."""

    bgp_parameters_changed = EventSource(BGPParametersEvent)


class CalicoEnterprisePeer(Object):
    """Handle Databag among peer CailcoEnterprise units."""

    on = CalicoEnterprisePeerEvents()

    def __init__(self, parent: CharmBase, endpoint="calico-enterprise"):
        super().__init__(parent, f"relation-{endpoint}")
        self.endpoint = endpoint

        events = parent.on[endpoint]
        self.framework.observe(parent.on.upgrade_charm, self.peer_change)
        self.framework.observe(events.relation_joined, self.peer_change)
        self.framework.observe(events.relation_changed, self.peer_change)

    def pubilsh_bgp_parameters(self):
        """Publish bgp parameters to peer relation."""
        if bgp_parameters := _early_service_cfg():
            for relation in self.model.relations[self.endpoint]:
                as_json = bgp_parameters.json(by_alias=True)
                relation.data[self.model.unit]["bgp-parameters"] = as_json

    def peer_change(self, event):
        """Respond to any changes in the peer data."""
        if len(self._computed_bgp_layout(local_only=True).nodes) == 0:
            log.info(f"Sharing bgp params from {self.model.unit.name}")
            self.pubilsh_bgp_parameters()
        self.on.bgp_parameters_changed.emit()

    def quorum_data(self, key: str) -> Optional[str]:
        """Return the agreed data associated with the key from each calico-enterprise unit including self.

        If there isn't unity in the relation, return None.
        """
        joined_data = []
        for relation in self.model.relations[self.endpoint]:
            for unit in relation.units | {self.model.unit}:
                data = relation.data[unit].get(key)
                joined_data.append(data)
        filtered = set(filter(bool, joined_data))
        return filtered.pop() if len(filtered) == 1 else None

    @property
    def service_cidr(self) -> Optional[str]:
        """Unify the service-cidr from each unit."""
        return self.quorum_data("service-cidr")

    def _computed_bgp_layout(self, local_only=False) -> BGPLayout:
        """Generate a BGPLayout from the peer relation."""
        layout = BGPLayout(nodes=[])
        for relation in self.model.relations[self.endpoint]:
            units = {self.model.unit} if local_only else relation.units | {self.model.unit}
            for unit in units:
                raw = relation.data[unit].get("bgp-parameters")
                if not raw:
                    continue
                params = BGPParameters.parse_raw(raw)
                layout.nodes += [params]
        return layout

    def _config_bgp_layout(self) -> Optional[BGPLayout]:
        raw_config = self.model.config["bgp_parameters"]
        if not raw_config:
            return None
        try:
            layout = BGPLayout(nodes=yaml.safe_load(raw_config))
            log.info("bgp_parameters will override computed parameters.")
        except ValidationError as e:
            log.info(f"bgp_parameters is invalid: {e}, falling back to computed parameters.")
            return None
        return layout

    @property
    def bgp_layout(self) -> BGPLayout:
        """Generate BGPLayout from either config or computed values."""
        layout: BGPLayout = None
        if not (layout := self._config_bgp_layout()):
            layout = self._computed_bgp_layout()
        return layout

    @property
    def early_network_config(self) -> Mapping:
        """Generate a full EarlyNetworkConfig for the cluster."""
        if not self.bgp_layout.nodes:
            log.warning("No node map is available yet")
        # hostname metadata is never reflected in the yaml sent to tigera operator
        exclude = {"nodes": {"__all__": {"hostname"}}}
        return {
            "apiVersion": "crd.projectcalico.org/v1",
            "kind": "EarlyNetworkConfiguration",
            "spec": self.bgp_layout.dict(by_alias=True, exclude=exclude),
        }

    @property
    def bgp_configuration(self) -> Mapping:
        """Generate the BGPConfiguration for the cluster."""
        return {
            "apiVersion": "crd.projectcalico.org/v1",
            "kind": "BGPConfiguration",
            "metadata": {"name": "default"},
            "spec": {
                "logSeverityScreen": "Info",
                "nodeToNodeMeshEnabled": False,
                "serviceClusterIPs": [{"cidr": self.service_cidr}],
                "listenPort": 179,
            },
        }

    @property
    def bgp_layout_config_map(self) -> Mapping:
        """Generate the bgp-layout config-map for the cluster."""
        enc = yaml.safe_dump(self.early_network_config)
        return {
            "apiVersion": "v1",
            "kind": "ConfigMap",
            "metadata": {"name": "bgp-layout"},
            "data": {"earlyNetworkConfiguration": enc},
        }

    @property
    def bgp_peer_set(self) -> Set[BGPPeerBinding]:
        """Generate the bgp peers list for the cluster."""
        return {
            BGPPeerBinding(asn=peer.asn, ip=peer.ip, rack=node.labels.rack)
            for node in self.bgp_layout.nodes
            for peer in node.peerings
        }
