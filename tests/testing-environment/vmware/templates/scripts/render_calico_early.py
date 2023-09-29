#!/bin/env python3
import argparse
import subprocess
import time

import jinja2
import yaml

parser = argparse.ArgumentParser("Calico Early Renderer")


def get_ips():
    return yaml.safe_load(subprocess.check_output("ip -j -4 a".split()))


def render_calico_early(args):
    calico_early_template = None

    with open("/tmp/calico_early.tpl", "r") as fh:
        calico_early_template = jinja2.Template(fh.read())

    ips = get_ips()
    if len(ips) < 4:
        time.sleep(5)
        ips = get_ips()
        print("Waiting for all nics")

    ip_2, ip_3 = [ips[nic]["addr_info"][0]["local"] for nic in (2, 3)]
    hostname = yaml.safe_load(subprocess.check_output("hostnamectl status --json short".split()))[
        "StaticHostname"
    ]
    node_info = {
        f"node{hostname.split('-')[2]}_interface1_addr": ip_2,
        f"node{hostname.split('-')[2]}_interface2_addr": ip_3,
    }

    with open("/calico-early/cfg.yaml", "w") as fh:
        fh.write(calico_early_template.render(**node_info))

    print("Rendered calico early")


if __name__ == "__main__":
    args = parser.parse_args()
    render_calico_early(args)
