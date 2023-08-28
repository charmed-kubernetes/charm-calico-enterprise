#cloud-config
package_update: true
package_upgrade: true
users:
  - name: ubuntu
    ssh_import_id:
    - lp:USER_ID
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
    sudo ctr image pull --user "{TIGERA_REGISTRY_USER}:{TIGERA_REGISTRY_PASSWORD}" quay.io/tigera/cnx-node:v{CALICO_EARLY_VERSION}
    sudo systemctl enable --now calico-early
    sudo systemctl enable --now calico-early-wait
  path: /tmp/setup-env.sh
  permissions: "0744"
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
    apiVersion: projectcalico.org/v3
    kind: EarlyNetworkConfiguration
    spec:
      nodes: %{ for offset in nodes }
      - interfaceAddresses:
          - ${switch_network_sw1}.${12+offset}
          - ${switch_network_sw2}.${12+offset}
        stableAddress:
          address: 10.30.30.${12+offset}
        asNumber: ${65000+offset}
        peerings:
          - peerIP: ${switch_network_sw1}.${tor_sw1_octet}
            peerASNumber: ${tor_sw1_asn}
          - peerIP: ${switch_network_sw2}.${tor_sw2_octet}
            peerASNumber: ${tor_sw2_asn}
        labels:
          rack: rack1 %{~ endfor }
  path: /calico-early/cfg.yaml
  owner: root:root
runcmd:
- ["/tmp/configure_gateway.py", "--cidr", "10.10.10.0/24", "--gateway", "10.10.10.3"]
- [/tmp/setup-env.sh]
