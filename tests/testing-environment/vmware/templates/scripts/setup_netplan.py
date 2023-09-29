#!/bin/env python3
import shlex
import subprocess

import yaml


def get_nics():
    links = subprocess.check_output(shlex.split("ip -j link show"))
    return yaml.safe_load(links)


def nic_addresses(ip_json, ifname):
    for ip in ip_json:
        if ip["ifname"] == ifname:
            for ifc in ip["addr_info"]:
                yield f'{ifc["local"]}/{ifc["prefixlen"]}'


def reconfigure_netplan():
    netplan = None
    links = get_nics()
    for nic in links[2:]:  # update nic2 and nic3
        ifname = nic["ifname"]
        subprocess.check_call(shlex.split(f"sudo dhclient -r {ifname}"))
        subprocess.check_call(shlex.split(f"sudo dhclient {ifname}"))

    with open("/etc/netplan/50-cloud-init.yaml", "r") as fh:
        netplan = yaml.safe_load(fh.read())
    ip_json = yaml.safe_load(subprocess.check_output("ip -j -4 a".split()).decode("utf-8"))
    netplan["network"]["ethernets"].update(
        {
            links[2]["ifname"]: {
                "addresses": list(nic_addresses(ip_json, links[2]["ifname"])),
                "set-name": links[2]["ifname"],
                "match": {"macaddress": links[2]["address"]},
                "routes": [{"to": "default", "via": "10.246.154.12"}],
            },
            links[3]["ifname"]: {
                "addresses": list(nic_addresses(ip_json, links[3]["ifname"])),
                "set-name": links[3]["ifname"],
                "match": {"macaddress": links[3]["address"]},
                "routes": [
                    {"to": "0.0.0.0/1", "via": "10.246.155.158"},
                    {"to": "128.0.0.0/1", "via": "10.246.155.158"},
                ],
            },
        }
    )
    with open("/etc/netplan/50-cloud-init.yaml", "w") as fh:
        fh.write(yaml.dump(netplan))
    print("Wrote updated netplan!")

    subprocess.call("sudo netplan apply".split())


if __name__ == "__main__":
    reconfigure_netplan()
