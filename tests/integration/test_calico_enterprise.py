# from grafana import Grafana
# from prometheus import Prometheus
import json
import logging
import re
import shlex
from pathlib import Path

import pytest
from lightkube.codecs import load_all_yaml
from pytest_operator.plugin import OpsTest
from tenacity import (
    before_log,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    stop_after_delay,
    wait_fixed,
)

log = logging.getLogger(__name__)

LOW_PRIORITY_HTB = "300"
NEW_PRIORITY_HTB = "50"
PING_LATENCY_RE = re.compile(r"(?:(\d+.\d+)\/?)")
PING_LOSS_RE = re.compile(r"(?:([\d\.]+)% packet loss)")


@pytest.mark.abort_on_fail
@pytest.mark.skip_if_deployed
async def test_build_and_deploy(ops_test: OpsTest, tigera_ee_reg_secret, tigera_ee_license):
    log.info("Build charm...")
    charm = next(Path(".").glob("calico-enterprise*.charm"), None)
    if not charm:
        log.info("Building Charm...")
        charm = await ops_test.build_charm(".")

    overlays = [
        ops_test.Bundle("kubernetes-core", channel="edge"),
        Path("tests/data/charm.yaml"),
    ]

    log.info("Rendering overlays...")
    bundle, *overlays = await ops_test.async_render_bundles(
        *overlays,
        charm=charm.resolve(),
        calico_crd_manifest=0,
        calico_install_manifest=0,
        tigera_reg_secret=tigera_ee_reg_secret,
        tigera_ee_license=tigera_ee_license,
    )

    log.info("Deploy charm...")
    # TODO: Undo this
    juju_cmd = (
        f"deploy --map-machines=existing -m {ops_test.model_full_name} {bundle} --trust "
        + " ".join(f"--overlay={f}" for f in overlays)
    )
    print(juju_cmd)

    await ops_test.juju(*shlex.split(juju_cmd), check=True, fail_msg="Bundle deploy failed")
    await ops_test.model.block_until(lambda: "tigera" in ops_test.model.applications, timeout=60)

    await ops_test.model.wait_for_idle(status="active", timeout=60 * 60)


# async def test_pod_icmp_latency(kubectl_exec, client, iperf3_pods, annotate):
#     pinger, pingee, _ = iperf3_pods
#     namespace = pinger.metadata.namespace

#     @retry(
#         retry=retry_if_exception_type(AssertionError),
#         stop=stop_after_delay(600),
#         wait=wait_fixed(1),
#         before=before_log(log, logging.INFO),
#     )
#     async def ping_for_latency(latency):
#         log.info(f"Testing that ping latency == {latency} ...")
#         stdout = await ping(kubectl_exec, pinger, pingee, namespace)
#         average_latency = avg_ping_delay(stdout)
#         assert latency < expected_latency

#     # ping once before the test, as the first ping delay takes a bit,
#     # but subsequent pings work as expected
#     # https://wiki.linuxfoundation.org/networking/netem#how_come_first_ping_takes_longer
#     await ping(kubectl_exec, pinger, pingee, namespace)

#     # latency is in ms
#     expected_latency = 50

#     await ping_for_latency(expected_latency)


# TODO: Can this be converted to Tigera?
# async def test_gateway_qos(
#     kubectl_exec, client, gateway_server, gateway_client_pod, worker_node, annotate
# ):
#     namespace = gateway_client_pod.metadata.namespace

#     rate_annotations = {
#         "ovn.kubernetes.io/ingress_rate": "60",
#         "ovn.kubernetes.io/egress_rate": "30",
#     }

#     annotate(worker_node, rate_annotations)

#     # We need to wait a little bit for OVN to do its thing
#     # after applying the annotations
#     await asyncio.sleep(60)

#     log.info("Testing node-level ingress bandwidth...")
#     ingress_bw = await run_external_bandwidth_test(
#         kubectl_exec,
#         gateway_server,
#         gateway_client_pod,
#         namespace,
#         reverse=True,
#     )
#     assert isclose(ingress_bw, 60, rel_tol=0.10)

#     log.info("Testing node-level egress bandwidth...")
#     egress_bw = await run_external_bandwidth_test(
#         kubectl_exec, gateway_server, gateway_client_pod, namespace
#     )
#     assert isclose(egress_bw, 30, rel_tol=0.10)


# @pytest.fixture()
# async def multi_nic_ipam(kubectl, kubectl_exec):
#     manifest_path = "tests/data/test-multi-nic-ipam.yaml"
#     await kubectl("apply", "-f", manifest_path)

#     @retry(
#         retry=retry_if_exception_type(AssertionError),
#         stop=stop_after_delay(600),
#         wait=wait_fixed(1),
#     )
#     async def pod_ip_addr():
#         pod = "test-multi-nic-ipam"
#         await kubectl_exec(pod, "default", "apt-get update")
#         await kubectl_exec(pod, "default", "apt-get install -y iproute2")
#         return await kubectl_exec(pod, "default", "ip -j addr")

#     ip_addr_output = await pod_ip_addr()

#     try:
#         yield ip_addr_output
#     finally:
#         # net-attach-def needs to be deleted last since tigera-controller
#         # depends on it to properly clean up the pod and subnet
#         await kubectl("delete", "pod", "test-multi-nic-ipam")
#         await kubectl("delete", "subnet", "test-multi-nic-ipam")
#         await kubectl("delete", "net-attach-def", "test-multi-nic-ipam")


class TCPDumpError(Exception):
    pass


@retry(
    retry=retry_if_exception_type(TCPDumpError),
    stop=stop_after_delay(60 * 10),
    wait=wait_fixed(1),
    before=before_log(log, logging.INFO),
)
async def run_tcpdump_test(ops_test, unit, interface, capture_comparator, filter=""):
    juju_cmd = f"ssh --pty=false {unit.name} -- sudo timeout 5 tcpdump -ni {interface} {filter}"
    retcode, stdout, stderr = await ops_test.juju(
        *shlex.split(juju_cmd),
        check=False,
    )

    # In GH actions, the output is in stderr and stdout is empty
    output = stdout + stderr
    # Timeout return code is 124 when command times out
    if retcode == 124:
        # Last 3 lines of stdout look like this:
        # 0 packets captured
        # 0 packets received by filter
        # 0 packets dropped by kernel
        for line in output.split("\n"):
            if "packets captured" in line:
                captured = int(line.split(" ")[0])
                if capture_comparator(captured):
                    log.info(f"Comparison succeeded. Number of packets captured: {captured}")
                    return True
                else:
                    msg = f"Comparison failed. Number of packets captured: {captured}"
                    log.info(msg)
                    raise TCPDumpError(msg)

        msg = "output did not contain the number of packets captured"
        log.info(msg)
        log.info(f"stdout:\n{stdout}")
        log.info(f"stderr:\n{stderr}")
        raise TCPDumpError(msg)
    else:
        msg = f"Failed to execute sudo timeout tcpdump -ni {interface} on {unit.name}"
        log.info(msg)
        raise TCPDumpError(msg)


# async def test_global_mirror(ops_test):
#     kube_ovn_app = ops_test.model.applications["tigera"]
#     worker_app = ops_test.model.applications["kubernetes-worker"]
#     worker_unit = worker_app.units[0]
#     mirror_iface = "mirror0"
#     # Test once before configuring the mirror, 0 packets should be captured
#     assert await run_tcpdump_test(ops_test, worker_unit, mirror_iface, lambda x: x == 0)

#     # Configure and test that traffic is being captured (more than 0 captured)
#     # Note this will be retried a few times, as it takes a bit of time for the newly configured
#     # daemonset to get restarted
#     log.info("Enabling global mirror ...")
#     await kube_ovn_app.set_config(
#         {
#             "enable-global-mirror": "true",
#             "mirror-iface": mirror_iface,
#         }
#     )
#     try:
#         await ops_test.model.wait_for_idle(status="active", timeout=60 * 10)
#         assert await run_tcpdump_test(
#             ops_test, worker_unit, mirror_iface, lambda x: x > 0
#         )
#     finally:
#         log.info("Disabling global mirror ...")
#         await kube_ovn_app.set_config(
#             {
#                 "enable-global-mirror": "false",
#                 "mirror-iface": mirror_iface,
#             }
#         )
#         await ops_test.model.wait_for_idle(status="active", timeout=60 * 10)


# async def test_pod_mirror(ops_test, nginx_pods, annotate):
#     async def repeated_curl(unit, ip_to_curl, wait_time):
#         while True:
#             log.info(f"Curling {ip_to_curl} from {unit.name}")
#             retcode, stdout, stderr = await curl_from_unit(ops_test, unit, ip_to_curl)
#             if retcode != 0:
#                 log.info(f"failed to reach {ip_to_curl} from {unit.name}")
#                 log.info(f"stdout: {stdout}")
#                 log.info(f"stderr: {stderr}")
#             await asyncio.sleep(wait_time)

#     kube_ovn_app = ops_test.model.applications["tigera"]
#     worker_app = ops_test.model.applications["kubernetes-worker"]
#     mirror_iface = "mirror0"

#     # For pod level mirroring, mirror-face must be set, and enable-global-mirror must be false
#     # This is the default config, so resetting after the test is not necessary
#     log.info("Configuring pod level mirroring ...")
#     await kube_ovn_app.set_config(
#         {
#             "enable-global-mirror": "false",
#             "mirror-iface": mirror_iface,
#         }
#     )
#     await ops_test.model.wait_for_idle(status="active", timeout=60 * 10)

#     # Unlike the global test, the pod level test must check the interface of the worker unit
#     # that the pod is running on.
#     for pod in nginx_pods():
#         host_ip = pod.status.hostIP
#         pod_ip = pod.status.podIP
#         # Find unit with corresponding IP
#         for unit in worker_app.units:
#             if await unit.get_public_address() == host_ip:
#                 # Need to repeatedly start curling now
#                 task = asyncio.ensure_future(repeated_curl(unit, pod_ip, 1))
#                 assert await run_tcpdump_test(
#                     ops_test,
#                     unit,
#                     mirror_iface,
#                     lambda x: x == 0,
#                     filter=f"dst {pod_ip} and port 80",
#                 )
#                 annotate(pod, {"ovn.kubernetes.io/mirror": "true"})

#                 # Need to stop curling for at least 11 seconds to allow existing
#                 # flows to expire. Otherwise, the traffic may never start to
#                 # mirror. See https://github.com/kubeovn/kube-ovn/issues/2801
#                 log.warning(
#                     "Working around https://github.com/kubeovn/kube-ovn/issues/2801"
#                 )
#                 task.cancel()
#                 with suppress(asyncio.CancelledError):
#                     await task
#                 await asyncio.sleep(20)
#                 task = asyncio.ensure_future(repeated_curl(unit, pod_ip, 1))

#                 assert await run_tcpdump_test(
#                     ops_test,
#                     unit,
#                     mirror_iface,
#                     lambda x: x > 0,
#                     filter=f"dst {pod_ip} and port 80",
#                 )
#                 # stop curling
#                 task.cancel()
#                 with suppress(asyncio.CancelledError):
#                     await task


# class BGPError(Exception):
#     pass


# @retry(
#     retry=retry_if_exception_type(BGPError),
#     stop=stop_after_delay(60 * 10),
#     wait=wait_fixed(1),
#     before=before_log(log, logging.INFO),
# )
# async def run_bird_curl_test(ops_test, unit, ip_to_curl):
#     retcode, stdout, stderr = await curl_from_unit(ops_test, unit, ip_to_curl)
#     if retcode == 0:
#         return True
#     else:
#         raise BGPError(f"failed to reach {ip_to_curl} from {unit.name}")


# @pytest.mark.usefixtures("bird")
# @pytest.mark.parametrize("scope", ["pod", "subnet"])
# async def test_bgp(ops_test, kubectl, kubectl_get, scope):
#     template_path = Path.cwd() / "tests/data/test-bgp.yaml"
#     template = template_path.read_text()
#     manifest = ops_test.tmp_path / "test-bgp.yaml"
#     manifest_data = template.format(
#         pod_annotations='annotations: {ovn.kubernetes.io/bgp: "true"}'
#         if scope == "pod"
#         else "",
#         subnet_annotations='annotations: {ovn.kubernetes.io/bgp: "true"}'
#         if scope == "subnet"
#         else "",
#     )
#     manifest.write_text(manifest_data)

#     async def cleanup():
#         await kubectl("delete", "--ignore-not-found", "-f", manifest)

#     await cleanup()

#     await kubectl("apply", "-f", manifest)
#     ips_to_curl = []
#     deadline = time.time() + 600

#     while time.time() < deadline:
#         pod = await kubectl_get("po", "-n", "test-bgp", "nginx")
#         pod_ip = pod.get("status", {}).get("podIP")
#         if pod_ip:
#             ips_to_curl.append(pod_ip)
#             break
#         log.info("Waiting for nginx pod IP")
#         await asyncio.sleep(1)

#     while time.time() < deadline:
#         svc = await kubectl_get("svc", "-n", "test-bgp", "nginx")
#         svc_ip = svc.get("spec", {}).get("clusterIP")
#         if svc_ip:
#             ips_to_curl.append(svc_ip)
#             break
#         log.info("Waiting for nginx svc IP")
#         await asyncio.sleep(1)

#     log.info("Verifying the following IPs are reachable from bird units ...")
#     log.info(ips_to_curl)
#     bird_app = ops_test.model.applications["bird"]
#     for unit in bird_app.units:
#         for ip in ips_to_curl:
#             assert await run_bird_curl_test(ops_test, unit, ip)

#     await cleanup()


async def test_network_policies(client, kubectl_exec, network_policies):
    blocked_pod, allowed_pod = network_policies

    @retry(
        retry=retry_if_exception_type(AssertionError),
        stop=stop_after_delay(600),
        wait=wait_fixed(1),
        before=before_log(log, logging.INFO),
    )
    async def check_wget(url, client, msg):
        stdout = await wget(kubectl_exec, client, url)
        assert msg in stdout

    log.info("Checking pods connectivity...")
    for pod in network_policies:
        await check_wget("nginx.netpolicy", pod, "'index.html' saved")

    log.info("Applying NetworkPolicy...")
    path = Path("tests/data/net-policy.yaml")
    policies = load_all_yaml(path.read_text())
    for obj in policies:
        client.create(obj)

    try:
        log.info("Checking NetworkPolicy...")
        await check_wget("nginx.netpolicy", allowed_pod, "'index.html' saved")
        await check_wget("nginx.netpolicy", blocked_pod, "wget: download timed out")
    finally:
        log.info("Removing NetworkPolicy...")
        for obj in policies:
            client.delete(type(obj), obj.metadata.name, namespace=obj.metadata.namespace)


class iPerfError(Exception):  # noqa N801
    pass


def parse_iperf_result(output: str):
    """Parse output from iperf3, raise iPerfError when the data isn't valid."""
    # iperf3 output looks like this:
    # {
    #   start: {...},
    #   intervals: {...},
    #   end: {
    #     sum_sent: {
    #       streams: {...},
    #       sum_sent: {
    #         ...,
    #         bits_per_second: xxx.xxx,
    #         ...
    #       },
    #       sum_received: {...},
    #     }
    #   },
    # }

    try:
        result = json.loads(output)
    except json.decoder.JSONDecodeError as ex:
        raise iPerfError(f"Cannot parse iperf3 json results: '{output}'") from ex
    # Extract the average values in bps and convert into mbps.
    iperf_error = result.get("error")
    if iperf_error:
        raise iPerfError(f"iperf3 encountered a runtime error: {iperf_error}")

    try:
        sum_sent = float(result["end"]["sum_sent"]["bits_per_second"]) / 1e6
        sum_received = float(result["end"]["sum_received"]["bits_per_second"]) / 1e6
    except KeyError as ke:
        raise iPerfError(f"failed to find bps in result {result}") from ke

    return sum_sent, sum_received


@retry(
    retry=retry_if_exception_type(iPerfError),
    stop=stop_after_attempt(3),
    wait=wait_fixed(1),
)
async def run_bandwidth_test(kubectl_exec, server, client, namespace, reverse=False):
    server_ip = server.status.podIP

    log.info("Setup iperf3 internal bw test...")
    iperf3_cmd = "iperf3 -s -p 5101 --daemon"
    args = server.metadata.name, namespace, iperf3_cmd
    stdout = await kubectl_exec(*args, fail_msg="Failed to setup iperf3 server")

    reverse_flag = "-R" if reverse else ""
    iperf3_cmd = f"iperf3 -c {server_ip} {reverse_flag} -p 5101 -JZ"
    args = client.metadata.name, namespace, iperf3_cmd
    stdout = await kubectl_exec(*args, fail_msg="Failed to run iperf3 test")

    _, sum_received = parse_iperf_result(stdout)
    return sum_received


@retry(
    retry=retry_if_exception_type(iPerfError),
    stop=stop_after_attempt(3),
    wait=wait_fixed(1),
)
async def run_external_bandwidth_test(kubectl_exec, server, client, namespace, reverse=False):
    log.info("Setup iperf3 external bw test...")
    reverse_flag = "-R" if reverse else ""
    iperf3_cmd = f"iperf3 -c {server} {reverse_flag} -JZ"
    args = client.metadata.name, namespace, iperf3_cmd
    stdout = await kubectl_exec(*args, fail_msg="Failed to run iperf3 test")
    _, sum_received = parse_iperf_result(stdout)
    return sum_received


async def ping(kubectl_exec, pinger, pingee, namespace):
    pingee_ip = pingee.status.podIP
    ping_cmd = f"ping {pingee_ip} -w 5"
    args = pinger.metadata.name, namespace, ping_cmd
    _, stdout, __ = await kubectl_exec(*args, check=False)
    return stdout


async def wget(kubectl_exec, client, url):
    wget_cmd = f"wget {url} -T 10"
    args = client.metadata.name, client.metadata.namespace, wget_cmd
    rc, stdout, stderr = await kubectl_exec(*args, check=False)
    if rc == 0:
        rm_cmd = "rm index.html"
        args = client.metadata.name, client.metadata.namespace, rm_cmd
        await kubectl_exec(*args, check=False)
    return stdout + stderr


def _ping_parse(stdout: str, line_filter: str, regex: re.Pattern, idx: int):
    # ping output looks like this:
    # PING google.com(dfw28s31-in-x0e.1e100.net (2607:f8b0:4000:818::200e))
    # 56 data bytes
    # 64 bytes from dfw28s31-in-x0e.1e100.net (2607:f8b0:4000:818::200e):
    # icmp_seq=1 ttl=115 time=518 ms
    # 64 bytes from dfw28s31-in-x0e.1e100.net (2607:f8b0:4000:818::200e):
    # icmp_seq=2 ttl=115 time=50.9 ms
    #
    # --- google.com ping statistics ---
    # 2 packets transmitted, 2 received, 0% packet loss, time 1001ms
    # rtt min/avg/max/mdev = 50.860/284.419/517.978/233.559 ms
    lines = [line for line in stdout.splitlines() if line_filter in line]
    assert len(lines) == 1, f"'{line_filter}' not found in ping response: {stdout}"
    matches = regex.findall(lines[0])
    assert len(matches) > idx, f"'{line_filter}' not parsable in ping response: {stdout}"
    return matches[idx]


def avg_ping_delay(stdout: str) -> float:
    return float(_ping_parse(stdout, "min/avg/max", PING_LATENCY_RE, 1))


def ping_loss(stdout: str) -> float:
    return float(_ping_parse(stdout, "packet loss", PING_LOSS_RE, 0))


def parse_ip_link(stdout):
    # ip link output looks like this:
    # 1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode
    # DEFAULT group default qlen 1000
    # link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    # 2: ens192: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode
    # DEFAULT group default qlen 1000
    # link/ether 00:50:56:00:fc:8c brd ff:ff:ff:ff:ff:ff

    lines = stdout.splitlines()
    netem_line = [line for line in lines if "netem" in line][0]
    # Split on @, take left side, split on :, take right side, and trim spaces
    interface = netem_line.split("@", 1)[0].split(":")[1].strip()
    return interface


def parse_tc_show(stdout):
    # tc show output looks similar to this:
    # qdisc netem 1: root refcnt 2 limit 5 delay 1.0s
    # there could be multiple lines if multiple qdiscs are present

    lines = stdout.splitlines()
    netem_line = [line for line in lines if "netem" in line][0]
    netem_split = netem_line.split(" ")
    limit_index = netem_split.index("limit")
    # Limit value directly follows the string limit
    limit_value = netem_split[limit_index + 1]
    return int(limit_value)


async def curl_from_unit(ops_test, unit, ip_to_curl):
    cmd = (
        f"ssh --pty=false -m {ops_test.model_full_name} {unit.name} -- "
        f"curl --connect-timeout 5 {ip_to_curl}"
    )
    return await ops_test.juju(
        *shlex.split(cmd),
    )
