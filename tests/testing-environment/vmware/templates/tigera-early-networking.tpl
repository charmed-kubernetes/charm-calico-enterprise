#cloud-config
package_update: true
package_upgrade: true
# network:
#   version: 2
#   ethernets:
#       eth0:
#           dhcp4: true
#           routes:
#           - to: default
#             via: {{switch_network_sw1}}
#       eth1:
#           dhcp4: true
#           routes:
#           - to: 0.0.0.0/0
#             via: {{switch_network_sw2}}
users:
  - name: ubuntu
    ssh_import_id:
    - lp:pjds
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev]
    plain_text_passwd: "ubuntu"
    shell: /bin/bash
    lock_passwd: false
    sudo:
    - ALL=(ALL) NOPASSWD:ALL
write_files:
- content: |
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y containerd
    sudo ctr image pull --user "${tigera_registry_user}:${tigera_registry_password}" quay.io/tigera/cnx-node:v${calico_early_version}
  path: /tmp/setup-env.sh
  permissions: "0744"
  owner: root:root
- content: |
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
    HTTP_PROXY="http://squid.internal:3128"
    HTTPS_PROXY="http://squid.internal:3128"
    http_proxy="http://squid.internal:3128"
    https_proxy="http://squid.internal:3128"
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
    import jinja2
    import json
    import argparse

    parser = argparse.ArgumentParser("Calico Early Renderer")
    parser.add_argument("node_info", dest="node_info", type=str, help="path to json file with node information")

    def render_calico_early(args):
        calico_early_template = None

        with open('/tmp/calico_early.tpl','w') as fh:
            calico_early_template = jinja2.Template(fh.read())

        node_info = None

        with open(args.node_info, 'r') as json_file:
            node_info = json.loads(json_file.read())

        # TODO: Any manipulation of node_info before passing to template.

        with open('/calico-early/cfg.yml', 'w') as fh:
            fh.write(calico_early_template.render(**node_info))

        print("Rendered calico early")
        

    if __name__ == "__main__":
        args = parser.parse_args()
        render_calico_early(args)
  path: /tmp/render_calico_early.py
  owner: root:root
  permissions: '744'
- content: |
    apiVersion: projectcalico.org/v3
    kind: EarlyNetworkingConfiguration
    spec:
      nodes:
      - asNumber: 65001
        interfaceAddresses:
        - \{node1_interface1_addr\}
        - \{node1_interface2_addr\}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.11
      - asNumber: 65002
        interfaceAddresses:
        - \{node2_interface1_addr\}
        - \{node2_interface2_addr\}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.12
      - asNumber: 65003
        interfaceAddresses:
        - \{node3_interface1_addr\}
        - \{node3_interface2_addr\}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.13
      - asNumber: 65004
        interfaceAddresses:
        - \{node4_interface1_addr\}
        - \{node4_interface2_addr\}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.14
      - asNumber: 65005
        interfaceAddresses:
        - \{node5_interface1_addr\}
        - \{node5_interface2_addr\}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: ${switch_network_sw1}
        - peerASNumber: 65502
          peerIP: ${switch_network_sw2}
        stableAddress:
          address: 10.30.30.15
  path: /calico-early/cfg.yaml
  owner: root:root
  permissions: '644'
- content: |
    #!/bin/env python3
    import yaml
    import subprocess
    import json


    def reconfigure_netplan():
        netplan = None
        subprocess.check_call("sudo dhclient".split())

        with open('/etc/netplan/50-cloud-init.yaml', 'r') as fh:
            netplan = yaml.safe_load(fh.read())
        ip_json = json.loads(subprocess.check_output("ip -j -4 a".split()).decode('utf-8'))
        netplan['network']['ethernets'].update({
                "ens192": {
                    "routes": [{
                        "to": "default",
                        "via": "10.246.154.134"
                    }],
                    "addresses": [[ip['addr_info'][0]['local'] for ip in ip_json if ip['ifname'] == "ens192"][0] + "/24"]
                },
                "ens224": {
                    "routes": [{
                        "to": "0.0.0.0/1",
                        "via": "10.246.155.36"
                    }],
                    "addresses": [[ip['addr_info'][0]['local'] for ip in ip_json if ip['ifname'] == "ens224"][0] + "/24"]
                }
            })
        with open('/etc/netplan/50-cloud-init.yaml', 'w') as fh:
            fh.write(yaml.dump(netplan))
        print("Wrote updated netplan!")

        subprocess.call("sudo netplan apply".split())

    if __name__ == "__main__":
        reconfigure_netplan()
  path: /tmp/reconfigre_netplan.py
  permissions: '744'
  owner: root:root
output: {all: '| tee -a /var/log/cloud-init-output.log'}
runcmd:
# - ["/tmp/configure_gateway.py", "--cidr", "10.10.10.0/24", "--gateway", "10.10.10.3"]
- [/tmp/setup-env.sh]
- [/tmp/reconfigre_netplan.py]
- sudo systemctl start calico-early
- sudo systemctl start calico-early-wait
# power_state:
#   delay: 0
#   mode: reboot
#   timeout: 30
#   condition: true