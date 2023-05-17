# Copyright 2023 pguimaraes
# See LICENSE file for licensing details.
#
# Learn more about testing at: https://juju.is/docs/sdk/testing

import yaml

import unittest.mock as mock
import pytest

import ops.testing
from charm import TigeraCharm
from ops.model import WaitingStatus
from jinja2 import Environment, FileSystemLoader


# from jinja2 import Environment


@pytest.fixture
def harness():
    harness = ops.testing.Harness(TigeraCharm)
    try:
        yield harness
    finally:
        harness.cleanup()


@pytest.fixture
def charm(harness):
    harness.begin_with_initial_hooks()
    yield harness.charm


def test_launch_initial_hooks(charm):
    assert charm.stored.tigera_configured is False, "Unexpected Stored Default"
    assert charm.stored.pod_restart_needed is False, "Unexpected Stored Default"
    assert charm.unit.status == WaitingStatus("Waiting for CNI relation")


@pytest.mark.skip_kubectl_mock
@pytest.mark.usefixtures
@mock.patch("charm.check_output", autospec=True)
def test_kubectl(mock_check_output, charm):
    charm.kubectl("arg1", "arg2")
    mock_check_output.assert_called_with(
        ["kubectl", "--kubeconfig", "/root/.kube/config", "arg1", "arg2"]
    )

@pytest.mark.usefixtures
@mock.patch("charm.Environment.get_template", autospec=True)
def test_configure_bgp(mock_get_template, charm, harness):
    class get_template(object):
        def __init__(self):
            super().__init__()
            self.mock_dump = mock.Mock()

        def stream(self, **kwargs):
            return self.mock_dump
    config_dict = {
        "bgp_parameters": yaml.dump({
            "test": {
                "asn": 1,
                "stableAddress": "10.10.10.10",
                "rack": "r",
                "interfaces": [
                    {"IP": "20.20.20.20", "peerIP": "30.30.30.30", "peerASN": 20}
                ]
            }
        })
    }
    harness.update_config(config_dict)

    mock_get_template.side_effect = [get_template()]

    charm.configure_bgp()
    mock_get_template.side_effect[0].mock_dump.assert_called_with("blabla")
