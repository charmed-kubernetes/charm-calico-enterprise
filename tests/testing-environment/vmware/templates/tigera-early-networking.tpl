#cloud-config
package_update: true
package_upgrade: true
packages:
- jq
users:
  - name: ubuntu
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev]
    plain_text_passwd: "ubuntu"
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
    - ${juju_authorized_key}
    sudo:
    - ALL=(ALL) NOPASSWD:ALL
write_files:
- content: |
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y containerd
    sudo ctr image pull --user "${tigera_registry_secret}" quay.io/tigera/cnx-node:v${calico_early_version}
  path: /tmp/setup-env.sh
  permissions: "0744"
  owner: root:root
- content: |
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
    HTTP_PROXY="http://squid.internal:3128"
    HTTPS_PROXY="http://squid.internal:3128"
    http_proxy="http://squid.internal:3128"
    https_proxy="http://squid.internal:3128"
    NO_PROXY="localhost,127.0.0.1,0.0.0.0,ppa.launchpad.net,launchpad.net,10.0.8.0/24,10.152.183.0/24,10.246.153.0/24,10.246.154.0/24,10.246.155.0/24"
    no_proxy="localhost,127.0.0.1,0.0.0.0,ppa.launchpad.net,launchpad.net,10.0.8.0/24,10.152.183.0/24,10.246.153.0/24,10.246.154.0/24,10.246.155.0/24"
  path: /etc/environment
  permissions: "0644"
  owner: root:root
- content: |
    [Unit]
    After=calico-early.service
    Before=snap.kubelet.daemon.service
    Before=jujud-machine-*.service
    [Service]
    Type=oneshot
    ExecStart=/bin/sh -c "while sleep 5; do grep -q 00000000:1FF3 /proc/net/tcp && break; done; sleep 15"
    [Install]
    WantedBy=multi-user.target
  path: /etc/systemd/system/calico-early-wait.service
  owner: root:root
  permissions: '644'
- content: |
    [Unit]
    Wants=network-online.target
    After=network-online.target
    Description=cnx node

    [Service]
    User=root
    Group=root
    # https://bugs.launchpad.net/bugs/1911220
    PermissionsStartOnly=true
    ExecStartPre=-/usr/bin/ctr task kill --all calico-early || true
    ExecStartPre=-/usr/bin/ctr container delete calico-early || true
    # lp:1932052 ensure snapshots are removed on delete
    ExecStartPre=-/usr/bin/ctr snapshot rm calico-early || true
    ExecStart=/usr/bin/ctr run \
      --rm \
      --net-host \
      --privileged \
      --env CALICO_EARLY_NETWORKING=/calico-early/cfg.yaml \
      --mount type=bind,src=/calico-early,dst=/calico-early,options=rbind:rw \
      quay.io/tigera/cnx-node:v${calico_early_version} calico-early
    ExecStop=-/usr/bin/ctr task kill --all calico-early || true
    ExecStop=-/usr/bin/ctr container delete calico-early || true
    # lp:1932052 ensure snapshots are removed on delete
    ExecStop=-/usr/bin/ctr snapshot rm calico-early || true
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target

  path: /etc/systemd/system/calico-early.service
  owner: root:root
  permissions: '644'
- content: |
    Create the file
  path: /calico-early/hello-world
  owner: root:root
  permissions: '644'
- content: |
    apiVersion: projectcalico.org/v3
    kind: EarlyNetworkingConfiguration
    spec:
      nodes:
      - asNumber: 64512
        interfaceAddresses:
        - {{node0_interface1_addr}}
        - {{node0_interface2_addr}}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.12
      - asNumber: 64513
        interfaceAddresses:
        - {{node1_interface1_addr}}
        - {{node1_interface2_addr}}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.13
      - asNumber: 64515
        interfaceAddresses:
        - {{node2_interface1_addr}}
        - {{node2_interface2_addr}}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.15
      - asNumber: 64516
        interfaceAddresses:
        - {{node3_interface1_addr}}
        - {{node3_interface2_addr}}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.16
      - asNumber: 64517
        interfaceAddresses:
        - {{node4_interface1_addr}}
        - {{node4_interface2_addr}}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.17
  path: /tmp/calico_early.tpl
  owner: root:root
  permissions: '644'
- content: |
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
  path: /tmp/reconfigure_netplan.py
  permissions: '744'
  owner: root:root
- content: |
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
  path: /tmp/render_calico_early.py
  permissions: '744'
  owner: root:root
output: {all: '| tee -a /var/log/cloud-init-output.log'}
runcmd:
# - ["/tmp/configure_gateway.py", "--cidr", "10.10.10.0/24", "--gateway", "10.10.10.3"]
- [/tmp/setup-env.sh]
- [/tmp/reconfigure_netplan.py]
- [/tmp/render_calico_early.py]
- sudo systemctl start calico-early
- sudo systemctl start calico-early-wait
- iptables -t nat -A POSTROUTING -s 10.30.30.0/24 ! -d 10.30.30.0/24 -o ens224 -j SNAT --to $(ip -j -4 a | jq -r '.[] | select(.ifname=="ens224") | .addr_info[0].local')
- iptables -t nat -A POSTROUTING -s 10.30.30.0/24 ! -d 10.30.30.0/24 -o ens256 -j SNAT --to $(ip -j -4 a | jq -r '.[] | select(.ifname=="ens256") | .addr_info[0].local')
# power_state:
#   delay: 0
#   mode: reboot
#   timeout: 30
#   condition: true