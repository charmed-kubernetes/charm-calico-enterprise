import unittest.mock as mock

import pytest
from charm import CalicoEnterpriseCharm


def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "skip_kubectl_mock: mark tests which do not mock out CalicoEnterpriseCharm.kubectl",
    )


@pytest.fixture(autouse=True)
def kubectl(request):
    """Mock out kubectl."""
    if "skip_kubectl_mock" in request.keywords:
        yield CalicoEnterpriseCharm.kubectl
        return
    with mock.patch("charm.CalicoEnterpriseCharm.kubectl", autospec=True) as mocked:
        yield mocked


# @pytest.fixture(autouse=True)
# def conctl():
#     with mock.patch("charm.getContainerRuntimeCtl", autospec=True) as mock_conctl:
#         yield mock_conctl.return_value
