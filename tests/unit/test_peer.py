# Copyright 2024 Canonical Ltd.
# See LICENSE file for licensing details.
#
# Learn more about testing at: https://juju.is/docs/sdk/testing

import unittest.mock as mock
from ipaddress import ip_address
from textwrap import indent

import ops.testing
import pytest
from charm import CalicoEnterpriseCharm


def newline_indent(text: str, num_spaces: int) -> str:
    """Indent num_spaces starting on the second line."""
    first_line = text.splitlines(True)[0]
    return indent(text, " " * num_spaces, predicate=lambda _: _ != first_line)


@pytest.fixture
def harness():
    harness = ops.testing.Harness(CalicoEnterpriseCharm)
    try:
        yield harness
    finally:
        harness.cleanup()


@pytest.fixture
def charm(harness):
    harness.begin_with_initial_hooks()
    yield harness.charm


@pytest.fixture
def early_service():
    with mock.patch("peer._read_file_content") as patched:
        patched.side_effect = [
            "\n--env CALICO_EARLY_NETWORKING=/magic.yaml \\\n",
            f"""
spec:
  nodes:
  - {newline_indent(LOCAL_BGP_PARAMS, 4)}
""".strip(),
        ]
        yield patched


@pytest.fixture
def localhost_ips():
    with mock.patch("peer._localhost_ips") as patched:
        patched.return_value = [
            ip_address("127.0.0.1"),
            ip_address("10.10.10.1"),
            ip_address("::1"),
        ]
        yield patched


LOCAL_BGP_PARAMS = """
asNumber: 20001
interfaceAddresses:
- 192.168.1.1
- 192.168.2.1
stableAddress:
  address: 10.10.10.1
peerings:
- peerIP: 192.168.1.254
  peerASNumber: 21254
- peerIP: 192.168.2.254
  peerASNumber: 22254
labels:
  rack: rack-1
""".strip()


REMOTE_BGP_PARAMS = """{
"hostname": "k8s-node-2",
"asNumber": 20002,
"interfaceAddresses": [
    "192.168.1.2",
    "192.168.2.2"
],
"labels": {"rack": "rack-1"},
"peerings": [
    {"peerASNumber": 21254, "peerIP": "192.168.1.254"},
    {"peerASNumber": 22254, "peerIP": "192.168.2.254"}
],
"stableAddress": {"address": "10.10.10.2"}
}"""


def test_peer_relation_data(harness, charm, early_service, localhost_ips):
    rel_id = 0  # peer-relation is always 0
    harness.add_relation_unit(rel_id, "calico-enterprise/0")
    harness.set_leader(True)
    assert charm.peers.service_cidr is None

    harness.update_relation_data(
        rel_id,
        "calico-enterprise/0",
        {"service-cidr": "192.168.0.0/16"},
    )
    assert charm.peers.service_cidr == "192.168.0.0/16"
    assert (
        charm.peers.bgp_configuration["spec"]["serviceClusterIPs"][0]["cidr"] == "192.168.0.0/16"
    )
    assert len(charm.peers.early_network_config["spec"]["nodes"]) == 1

    harness.add_relation_unit(rel_id, "calico-enterprise/1")
    harness.update_relation_data(
        rel_id,
        "calico-enterprise/1",
        {"service-cidr": "172.22.134.0/24", "bgp-parameters": REMOTE_BGP_PARAMS},
    )
    assert charm.peers.service_cidr is None
    assert len(charm.peers.early_network_config["spec"]["nodes"]) == 2

    enc = charm.peers.bgp_layout_config_map["data"]["earlyNetworkConfiguration"]
    assert "asNumber: 20001" in enc
    assert "asNumber: 20002" in enc
    assert "hostname" not in enc


BGP_PARAMETERS_ONE_NODE = f"""
- {newline_indent(REMOTE_BGP_PARAMS,2)}
""".strip()

BGP_PARAMETERS_TWO_NODE = f"""
- hostname: k8s-node-1
  {newline_indent(LOCAL_BGP_PARAMS, 2)}
- {newline_indent(REMOTE_BGP_PARAMS,2)}
""".strip()


@pytest.mark.parametrize(
    "value, node_len",
    [
        ("", 0),
        ("invalid", 0),
        (BGP_PARAMETERS_ONE_NODE, 1),
        (BGP_PARAMETERS_TWO_NODE, 2),
    ],
    ids=[
        "Config Unset",
        "Config Invalid",
        "Config One Node",
        "Config Two Nodes",
    ],
)
def test_configured_bgp_layout(harness, charm, value, node_len):
    harness.disable_hooks()
    harness.update_config({"bgp_parameters": value})
    assert len(charm.peers.bgp_layout.nodes) == node_len


def test_publish_bgp_parameters_no_service(harness, charm):
    harness.disable_hooks()
    with mock.patch("peer.CALICO_EARLY_SERVICE") as patched:
        patched.exists.return_value = False
        charm.peers.publish_bgp_parameters()

    for relation in charm.model.relations["calico-enterprise"]:
        assert relation.data[charm.model.unit].get("bgp-parameters") is None


@pytest.mark.parametrize("failure", ["No Service", "Invalid Service", "Invalid Config"])
def test_publish_bgp_parameters_invalid_calico_early(early_service, harness, charm, failure):
    harness.disable_hooks()

    if failure == "No Service":
        early_service.side_effect = [
            None,
        ]
    elif failure == "Invalid Service":
        early_service.side_effect = ["", None]
    elif failure == "Invalid Config":
        early_service.side_effect = ["CALICO_EARLY_NETWORKING=magic.yaml", "invalid"]

    charm.peers.publish_bgp_parameters()
    for relation in charm.model.relations["calico-enterprise"]:
        assert relation.data[charm.model.unit].get("bgp-parameters") is None


def test_publish_bgp_parameters_json_passthru(harness, charm):
    harness.disable_hooks()
    with mock.patch("peer._early_service_cfg") as patched:
        expected = patched.return_value.json.return_value = "expected"
        charm.peers.publish_bgp_parameters()

    for relation in charm.model.relations["calico-enterprise"]:
        assert relation.data[charm.model.unit]["bgp-parameters"] == expected
