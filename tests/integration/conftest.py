import asyncio
import base64
import binascii
import json
import logging
import os
import shlex
import time
from pathlib import Path
from typing import Iterable, Tuple, Union

import pytest
import pytest_asyncio
import yaml
from lightkube import Client, KubeConfig, codecs
from lightkube.resources.apps_v1 import DaemonSet, Deployment
from lightkube.resources.core_v1 import Namespace, Node, Pod
from lightkube.types import PatchType

log = logging.getLogger(__name__)
KubeCtl = Union[str, Tuple[int, str, str]]


def pytest_addoption(parser):
    parser.addoption(
        "--k8s-cloud",
        action="store",
        help="Juju kubernetes cloud to reuse; if not provided, will generate a new cloud",
    )


@pytest_asyncio.fixture(scope="module")
async def kubeconfig(ops_test):
    kubeconfig_path = ops_test.tmp_path / "kubeconfig"
    rc, stdout, stderr = await ops_test.run(
        "juju", "ssh", "kubernetes-control-plane/leader", "--", "cat", "config"
    )
    if rc != 0:
        log.error(f"retcode: {rc}")
        log.error(f"stdout:\n{stdout.strip()}")
        log.error(f"stderr:\n{stderr.strip()}")
        pytest.fail("Failed to copy kubeconfig from kubernetes-control-plane")
    assert stdout, "kubeconfig file is 0 bytes"
    kubeconfig_path.write_text(stdout)
    yield kubeconfig_path


@pytest_asyncio.fixture(scope="module")
async def client(kubeconfig):
    config = KubeConfig.from_file(kubeconfig)
    client = Client(
        config=config.get(context_name="juju-context"),
        trust_env=False,
    )
    yield client


@pytest.fixture(scope="module")
def worker_node(client):
    # Returns a worker node
    for node in client.list(Node):
        if node.metadata.labels["juju-application"] == "kubernetes-worker":
            return node


@pytest.fixture(scope="module")
async def gateway_server(ops_test):
    cmd = "exec --unit ubuntu/0 -- sudo apt install -y iperf3"
    rc, stdout, stderr = await ops_test.juju(*shlex.split(cmd))
    assert rc == 0, f"Failed to install iperf3: {(stdout or stderr).strip()}"

    iperf3_cmd = "iperf3 -s --daemon"
    cmd = f"juju exec --unit ubuntu/0 -- {iperf3_cmd}"
    rc, stdout, stderr = await ops_test.run(*shlex.split(cmd))
    assert rc == 0, f"Failed to run iperf3 server: {(stdout or stderr).strip()}"

    cmd = "juju show-unit ubuntu/0"
    rc, stdout, stderr = await ops_test.run(*shlex.split(cmd))
    assert rc == 0, f"Failed to get ubuntu/0 unit data: {(stdout or stderr).strip()}"

    unit_data = yaml.safe_load(stdout)
    return unit_data["ubuntu/0"]["public-address"]


@pytest.fixture()
def gateway_client_pod(client, worker_node, subnet_resource):
    log.info("Creating gateway QoS-related resources ...")
    path = Path("tests/data/gateway_qos.yaml")
    for obj in codecs.load_all_yaml(path.read_text()):
        if obj.kind == "Subnet":
            obj.spec["gatewayNode"] = worker_node.metadata.name
        if obj.kind == "Namespace":
            namespace = obj.metadata.name
        if obj.kind == "Pod":
            pod_name = obj.metadata.name
        client.create(obj)

    client_pod = client.get(Pod, name=pod_name, namespace=namespace)
    # wait for pod to come up
    client.wait(
        Pod,
        client_pod.metadata.name,
        for_conditions=["Ready"],
        namespace=namespace,
    )

    yield client_pod

    log.info("Deleting gateway QoS-related resources ...")
    for obj in codecs.load_all_yaml(path.read_text()):
        client.delete(type(obj), obj.metadata.name, namespace=obj.metadata.namespace)


async def wait_pod_ips(client, pods):
    """Return a list of pods which have an ip address assigned."""
    log.info("Waiting for pods...")
    ready = []

    for pod in pods:
        client.wait(
            Pod,
            pod.metadata.name,
            for_conditions=["Ready"],
            namespace=pod.metadata.namespace,
        )
        for _, obj in client.watch(
            Pod,
            namespace=pod.metadata.namespace,
            fields={"metadata.name": pod.metadata.name},
        ):
            if obj.status.podIP:
                ready.append(obj)
                break

    return ready


async def wait_for_removal(client, pods):
    """Wait until listed pods are no longer present in the cluster."""
    for pod in pods:
        namespace = pod.metadata.namespace
        remaining_pods = list(client.list(Pod, namespace=namespace))
        while len(remaining_pods) != 0:
            log.info("Pods still in existence, waiting ...")
            remaining_pods = list(client.list(Pod, namespace=namespace))
            await asyncio.sleep(5)

    for pod in pods:
        namespace = pod.metadata.namespace
        while namespace in list(client.list(Namespace)):
            log.info(f"{namespace} namespace still in existence, waiting ...")
            await asyncio.sleep(5)


@pytest.fixture()
def iperf3_pods(client):
    log.info("Creating iperf3 resources ...")
    path = Path.cwd() / "tests/data/iperf3_daemonset.yaml"
    with open(path) as f:
        for obj in codecs.load_all_yaml(f):
            if obj.kind == "Namespace":
                namespace = obj.metadata.name
            if obj.kind == "DaemonSet":
                ds = obj.metadata.name
            client.create(obj)

    wait_daemonset(client, namespace, ds, 3)
    pods = list(client.list(Pod, namespace=namespace))

    yield pods

    log.info("Deleting iperf3 resources ...")
    with open(path) as f:
        for obj in codecs.load_all_yaml(f):
            client.delete(type(obj), obj.metadata.name, namespace=obj.metadata.namespace)

    # wait for pods to be deleted
    remaining_pods = list(client.list(Pod, namespace=namespace))
    while len(remaining_pods) != 0:
        log.info("iperf3 pods still in existence, waiting ...")
        remaining_pods = list(client.list(Pod, namespace=namespace))
        time.sleep(5)

    while namespace in list(client.list(Namespace)):
        log.info("iperf3 namespace still in existence, waiting ...")
        time.sleep(5)

    log.info("iperf3 cleanup finished")


@pytest.fixture(scope="module")
def tigera_ee_license() -> str:
    """Fetch the Tigera EE license from the environment as either bare string or base64 encoded."""
    if license := os.environ.get("CHARM_TIGERA_EE_LICENSE"):
        try:
            base64.b64decode(license)
        except binascii.Error:
            # missing the b64 encoded, add that here
            as_bytes = license.encode()
            license = base64.b64encode(as_bytes).decode()
        return license
    raise KeyError("Tigera License not found")


@pytest.fixture(scope="module")
def tigera_ee_reg_secret() -> str:
    """Fetch the Tigera EE registry secret."""
    if reg_secret := os.environ.get("CHARM_TIGERA_EE_REG_SECRET"):
        try:
            base64.b64decode(reg_secret)
        except binascii.Error:
            # missing the b64 encoded, add that here
            as_bytes = reg_secret.encode()
            reg_secret = base64.b64encode(as_bytes).decode()
        return reg_secret
    raise KeyError("Tigera Reg Secret not found")


@pytest.fixture(scope="module")
async def nic_autodetection_cidrs(ops_test) -> Iterable[str]:
    rc, stdout, stderr = await ops_test.juju("spaces", "--format=yaml")
    if rc != 0:
        log.error(f"retcode: {rc}")
        log.error(f"stdout:\n{stdout.strip()}")
        log.error(f"stderr:\n{stderr.strip()}")
        pytest.fail("Failed to look up spaces")
    spaces = yaml.safe_load(stdout)
    tor_network, *_ = (_ for _ in spaces["spaces"] if _["name"] == "tor-network")
    yield tor_network["subnets"].keys()


@pytest.fixture(scope="module")
def kubectl(ops_test, kubeconfig):
    """Supports running kubectl exec commands."""

    async def f(*args, **kwargs) -> KubeCtl:
        """Actual callable returned by the fixture.

        :returns: if kwargs[check] is True or undefined, stdout is returned
                  if kwargs[check] is False, Tuple[rc, stdout, stderr] is returned
        """
        cmd = ["kubectl", "--kubeconfig", str(kubeconfig)] + list(args)
        check = kwargs["check"] = kwargs.get("check", True)
        rc, stdout, stderr = await ops_test.run(*cmd, **kwargs)
        if not check:
            return rc, stdout, stderr
        return stdout

    return f


@pytest.fixture(scope="module")
def kubectl_exec(kubectl):
    async def f(name: str, namespace: str, cmd: str, **kwds):
        shcmd = f'exec {name} -n {namespace} -- sh -c "{cmd}"'
        return await kubectl(*shlex.split(shcmd), **kwds)

    return f


@pytest.fixture(scope="module")
def kubectl_get(kubectl):
    async def f(*args, **kwargs):
        args = ["get", "-o", "json"] + list(args)
        output = await kubectl(*args, **kwargs)
        return json.loads(output)

    return f


def wait_daemonset(client: Client, namespace, name, pods_ready):
    for _, obj in client.watch(DaemonSet, namespace=namespace, fields={"metadata.name": name}):
        if obj.status is None:
            continue
        status = obj.status.to_dict()
        if status["numberReady"] == pods_ready:
            return


@pytest_asyncio.fixture(scope="module")
async def nginx(client):
    log.info("Creating Nginx deployment and service ...")
    path = Path("tests/data/nginx.yaml")
    with open(path) as f:
        for obj in codecs.load_all_yaml(f):
            client.create(obj, namespace="default")

    log.info("Waiting for Nginx deployment to be available ...")
    client.wait(Deployment, "nginx", for_conditions=["Available"])
    log.info("Nginx deployment is now available")
    yield "nginx"

    log.info("Deleting Nginx deployment and service ...")
    with open(path) as f:
        for obj in codecs.load_all_yaml(f):
            client.delete(type(obj), obj.metadata.name)


@pytest_asyncio.fixture(scope="module")
async def nginx_pods(client, nginx):
    def f():
        pods = client.list(Pod, namespace="default", labels={"app": nginx})
        return pods

    return f


@pytest.fixture(scope="module")
def annotate(client, ops_test):
    def f(obj, annotation_dict, patch_type=PatchType.STRATEGIC):
        log.info(f"Annotating {type(obj)} {obj.metadata.name} with {annotation_dict} ...")
        obj.metadata.annotations = annotation_dict
        client.patch(
            type(obj),
            obj.metadata.name,
            obj,
            namespace=obj.metadata.namespace,
            patch_type=patch_type,
        )

    return f


@pytest_asyncio.fixture()
async def network_policies(client):
    log.info("Creating network policy resources ...")
    path = Path("tests/data/network-policies.yaml")
    for obj in codecs.load_all_yaml(path.read_text()):
        client.create(obj)

    watch = [
        client.get(Pod, name="blocked-pod", namespace="netpolicy"),
        client.get(Pod, name="allowed-pod", namespace="netpolicy"),
    ]

    pods = await wait_pod_ips(client, watch)

    yield tuple(pods)

    log.info("Deleting network policy resources ...")
    for obj in reversed(codecs.load_all_yaml(path.read_text())):
        client.delete(type(obj), obj.metadata.name, namespace=obj.metadata.namespace)

    await wait_for_removal(client, pods)
