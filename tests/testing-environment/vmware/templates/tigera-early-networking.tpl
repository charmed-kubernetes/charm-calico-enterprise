#cloud-config
package_update: true
package_upgrade: true
network:
  version: 2
  ethernets:
      eth0:
          dhcp4: true
          routes:
          - to: default
            via: {{switch_network_sw1}}
      eth1:
          dhcp4: true
          routes:
          - to: 0.0.0.0/0
            via: {{switch_network_sw2}}
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
    sudo ctr image pull --user "{tigera_registry_user}:{tigera_registry_password}" quay.io/tigera/cnx-node:v{calico_early_version}
    sudo systemctl enable --now calico-early
    sudo systemctl enable --now calico-early-wait
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
      quay.io/tigera/cnx-node:v{CALICO_EARLY_VERSION} calico-early
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
      quay.io/tigera/cnx-node:v{CALICO_EARLY_VERSION} calico-early
    ExecStop=-/usr/bin/ctr task kill --all calico-early || true
    ExecStop=-/usr/bin/ctr container delete calico-early || true
    # lp:1932052 ensure snapshots are removed on delete
    ExecStop=-/usr/bin/ctr snapshot rm calico-early || true
    Restart=always
    RestartSec=10

    [Install]
    WantedBy=multi-user.target

  path: /tmp/render_calico_early.py
  owner: ubuntu:ubuntu
  permissions: '744'
- content: |
    apiVersion: projectcalico.org/v3
    kind: EarlyNetworkingConfiguration
    spec:
      nodes:
      - asNumber: 65001
        interfaceAddresses:
        - {node1_interface1_addr}
        - {node1_interface2_addr}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.{{final_octet}}
      - asNumber: 65002
        interfaceAddresses:
        - {node2_interface1_addr}
        - {node2_interface2_addr}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.{{final_octet}}
        - asNumber: 65003
        interfaceAddresses:
        - {node3_interface1_addr}
        - {node3_interface2_addr}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.{{final_octet}}
        - asNumber: 65004
        interfaceAddresses:
        - {node4_interface1_addr}
        - {node4_interface2_addr}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.{{final_octet}}
      - asNumber: 65005
        interfaceAddresses:
        - {node5_interface1_addr}
        - {node5_interface2_addr}
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.{{final_octet}}
      
  path: /calico-early/cfg.yaml
  owner: root:root
runcmd:
- ["/tmp/configure_gateway.py", "--cidr", "10.10.10.0/24", "--gateway", "10.10.10.3"]
- [/tmp/setup-env.sh]
