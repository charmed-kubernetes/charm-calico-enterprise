#cloud-config
package_update: true
package_upgrade: true
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
    apiVersion: projectcalico.org/v3
    kind: EarlyNetworkingConfiguration
    spec:
      nodes:
      - asNumber: 65000
        interfaceAddresses:
        - 10.246.153.0
        - 10.246.153.0
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$0
      - asNumber: 65001
        interfaceAddresses:
        - 10.246.153.1
        - 10.246.153.1
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$1
      - asNumber: 65002
        interfaceAddresses:
        - 10.246.153.2
        - 10.246.153.2
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$2
      - asNumber: 65003
        interfaceAddresses:
        - 10.246.153.3
        - 10.246.153.3
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$3
      - asNumber: 65004
        interfaceAddresses:
        - 10.246.153.4
        - 10.246.153.4
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$4
      - asNumber: 65005
        interfaceAddresses:
        - 10.246.153.5
        - 10.246.153.5
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$5
      - asNumber: 65006
        interfaceAddresses:
        - 10.246.153.6
        - 10.246.153.6
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$6
      - asNumber: 65007
        interfaceAddresses:
        - 10.246.153.7
        - 10.246.153.7
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$7
      - asNumber: 65008
        interfaceAddresses:
        - 10.246.153.8
        - 10.246.153.8
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$8
      - asNumber: 65009
        interfaceAddresses:
        - 10.246.153.9
        - 10.246.153.9
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$9
      - asNumber: 65010
        interfaceAddresses:
        - 10.246.153.10
        - 10.246.153.10
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$10
      - asNumber: 65011
        interfaceAddresses:
        - 10.246.153.11
        - 10.246.153.11
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$11
      - asNumber: 65012
        interfaceAddresses:
        - 10.246.153.12
        - 10.246.153.12
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$12
      - asNumber: 65013
        interfaceAddresses:
        - 10.246.153.13
        - 10.246.153.13
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$13
      - asNumber: 65014
        interfaceAddresses:
        - 10.246.153.14
        - 10.246.153.14
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$14
      - asNumber: 65015
        interfaceAddresses:
        - 10.246.153.15
        - 10.246.153.15
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$15
      - asNumber: 65016
        interfaceAddresses:
        - 10.246.153.16
        - 10.246.153.16
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$16
      - asNumber: 65017
        interfaceAddresses:
        - 10.246.153.17
        - 10.246.153.17
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$17
      - asNumber: 65018
        interfaceAddresses:
        - 10.246.153.18
        - 10.246.153.18
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$18
      - asNumber: 65019
        interfaceAddresses:
        - 10.246.153.19
        - 10.246.153.19
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$19
      - asNumber: 65020
        interfaceAddresses:
        - 10.246.153.20
        - 10.246.153.20
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$20
      - asNumber: 65021
        interfaceAddresses:
        - 10.246.153.21
        - 10.246.153.21
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$21
      - asNumber: 65022
        interfaceAddresses:
        - 10.246.153.22
        - 10.246.153.22
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$22
      - asNumber: 65023
        interfaceAddresses:
        - 10.246.153.23
        - 10.246.153.23
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$23
      - asNumber: 65024
        interfaceAddresses:
        - 10.246.153.24
        - 10.246.153.24
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$24
      - asNumber: 65025
        interfaceAddresses:
        - 10.246.153.25
        - 10.246.153.25
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$25
      - asNumber: 65026
        interfaceAddresses:
        - 10.246.153.26
        - 10.246.153.26
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$26
      - asNumber: 65027
        interfaceAddresses:
        - 10.246.153.27
        - 10.246.153.27
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$27
      - asNumber: 65028
        interfaceAddresses:
        - 10.246.153.28
        - 10.246.153.28
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$28
      - asNumber: 65029
        interfaceAddresses:
        - 10.246.153.29
        - 10.246.153.29
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$29
      - asNumber: 65030
        interfaceAddresses:
        - 10.246.153.30
        - 10.246.153.30
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$30
      - asNumber: 65031
        interfaceAddresses:
        - 10.246.153.31
        - 10.246.153.31
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$31
      - asNumber: 65032
        interfaceAddresses:
        - 10.246.153.32
        - 10.246.153.32
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$32
      - asNumber: 65033
        interfaceAddresses:
        - 10.246.153.33
        - 10.246.153.33
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$33
      - asNumber: 65034
        interfaceAddresses:
        - 10.246.153.34
        - 10.246.153.34
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$34
      - asNumber: 65035
        interfaceAddresses:
        - 10.246.153.35
        - 10.246.153.35
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$35
      - asNumber: 65036
        interfaceAddresses:
        - 10.246.153.36
        - 10.246.153.36
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$36
      - asNumber: 65037
        interfaceAddresses:
        - 10.246.153.37
        - 10.246.153.37
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$37
      - asNumber: 65038
        interfaceAddresses:
        - 10.246.153.38
        - 10.246.153.38
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$38
      - asNumber: 65039
        interfaceAddresses:
        - 10.246.153.39
        - 10.246.153.39
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$39
      - asNumber: 65040
        interfaceAddresses:
        - 10.246.153.40
        - 10.246.153.40
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$40
      - asNumber: 65041
        interfaceAddresses:
        - 10.246.153.41
        - 10.246.153.41
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$41
      - asNumber: 65042
        interfaceAddresses:
        - 10.246.153.42
        - 10.246.153.42
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$42
      - asNumber: 65043
        interfaceAddresses:
        - 10.246.153.43
        - 10.246.153.43
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$43
      - asNumber: 65044
        interfaceAddresses:
        - 10.246.153.44
        - 10.246.153.44
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$44
      - asNumber: 65045
        interfaceAddresses:
        - 10.246.153.45
        - 10.246.153.45
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$45
      - asNumber: 65046
        interfaceAddresses:
        - 10.246.153.46
        - 10.246.153.46
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$46
      - asNumber: 65047
        interfaceAddresses:
        - 10.246.153.47
        - 10.246.153.47
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$47
      - asNumber: 65048
        interfaceAddresses:
        - 10.246.153.48
        - 10.246.153.48
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$48
      - asNumber: 65049
        interfaceAddresses:
        - 10.246.153.49
        - 10.246.153.49
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$49
      - asNumber: 65050
        interfaceAddresses:
        - 10.246.153.50
        - 10.246.153.50
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$50
      - asNumber: 65051
        interfaceAddresses:
        - 10.246.153.51
        - 10.246.153.51
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$51
      - asNumber: 65052
        interfaceAddresses:
        - 10.246.153.52
        - 10.246.153.52
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$52
      - asNumber: 65053
        interfaceAddresses:
        - 10.246.153.53
        - 10.246.153.53
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$53
      - asNumber: 65054
        interfaceAddresses:
        - 10.246.153.54
        - 10.246.153.54
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$54
      - asNumber: 65055
        interfaceAddresses:
        - 10.246.153.55
        - 10.246.153.55
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$55
      - asNumber: 65056
        interfaceAddresses:
        - 10.246.153.56
        - 10.246.153.56
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$56
      - asNumber: 65057
        interfaceAddresses:
        - 10.246.153.57
        - 10.246.153.57
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$57
      - asNumber: 65058
        interfaceAddresses:
        - 10.246.153.58
        - 10.246.153.58
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$58
      - asNumber: 65059
        interfaceAddresses:
        - 10.246.153.59
        - 10.246.153.59
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$59
      - asNumber: 65060
        interfaceAddresses:
        - 10.246.153.60
        - 10.246.153.60
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$60
      - asNumber: 65061
        interfaceAddresses:
        - 10.246.153.61
        - 10.246.153.61
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$61
      - asNumber: 65062
        interfaceAddresses:
        - 10.246.153.62
        - 10.246.153.62
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$62
      - asNumber: 65063
        interfaceAddresses:
        - 10.246.153.63
        - 10.246.153.63
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$63
      - asNumber: 65064
        interfaceAddresses:
        - 10.246.153.64
        - 10.246.153.64
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$64
      - asNumber: 65065
        interfaceAddresses:
        - 10.246.153.65
        - 10.246.153.65
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$65
      - asNumber: 65066
        interfaceAddresses:
        - 10.246.153.66
        - 10.246.153.66
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$66
      - asNumber: 65067
        interfaceAddresses:
        - 10.246.153.67
        - 10.246.153.67
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$67
      - asNumber: 65068
        interfaceAddresses:
        - 10.246.153.68
        - 10.246.153.68
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$68
      - asNumber: 65069
        interfaceAddresses:
        - 10.246.153.69
        - 10.246.153.69
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$69
      - asNumber: 65070
        interfaceAddresses:
        - 10.246.153.70
        - 10.246.153.70
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$70
      - asNumber: 65071
        interfaceAddresses:
        - 10.246.153.71
        - 10.246.153.71
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$71
      - asNumber: 65072
        interfaceAddresses:
        - 10.246.153.72
        - 10.246.153.72
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$72
      - asNumber: 65073
        interfaceAddresses:
        - 10.246.153.73
        - 10.246.153.73
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$73
      - asNumber: 65074
        interfaceAddresses:
        - 10.246.153.74
        - 10.246.153.74
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$74
      - asNumber: 65075
        interfaceAddresses:
        - 10.246.153.75
        - 10.246.153.75
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$75
      - asNumber: 65076
        interfaceAddresses:
        - 10.246.153.76
        - 10.246.153.76
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$76
      - asNumber: 65077
        interfaceAddresses:
        - 10.246.153.77
        - 10.246.153.77
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$77
      - asNumber: 65078
        interfaceAddresses:
        - 10.246.153.78
        - 10.246.153.78
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$78
      - asNumber: 65079
        interfaceAddresses:
        - 10.246.153.79
        - 10.246.153.79
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$79
      - asNumber: 65080
        interfaceAddresses:
        - 10.246.153.80
        - 10.246.153.80
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$80
      - asNumber: 65081
        interfaceAddresses:
        - 10.246.153.81
        - 10.246.153.81
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$81
      - asNumber: 65082
        interfaceAddresses:
        - 10.246.153.82
        - 10.246.153.82
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$82
      - asNumber: 65083
        interfaceAddresses:
        - 10.246.153.83
        - 10.246.153.83
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$83
      - asNumber: 65084
        interfaceAddresses:
        - 10.246.153.84
        - 10.246.153.84
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$84
      - asNumber: 65085
        interfaceAddresses:
        - 10.246.153.85
        - 10.246.153.85
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$85
      - asNumber: 65086
        interfaceAddresses:
        - 10.246.153.86
        - 10.246.153.86
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$86
      - asNumber: 65087
        interfaceAddresses:
        - 10.246.153.87
        - 10.246.153.87
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$87
      - asNumber: 65088
        interfaceAddresses:
        - 10.246.153.88
        - 10.246.153.88
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$88
      - asNumber: 65089
        interfaceAddresses:
        - 10.246.153.89
        - 10.246.153.89
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$89
      - asNumber: 65090
        interfaceAddresses:
        - 10.246.153.90
        - 10.246.153.90
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$90
      - asNumber: 65091
        interfaceAddresses:
        - 10.246.153.91
        - 10.246.153.91
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$91
      - asNumber: 65092
        interfaceAddresses:
        - 10.246.153.92
        - 10.246.153.92
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$92
      - asNumber: 65093
        interfaceAddresses:
        - 10.246.153.93
        - 10.246.153.93
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$93
      - asNumber: 65094
        interfaceAddresses:
        - 10.246.153.94
        - 10.246.153.94
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$94
      - asNumber: 65095
        interfaceAddresses:
        - 10.246.153.95
        - 10.246.153.95
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$95
      - asNumber: 65096
        interfaceAddresses:
        - 10.246.153.96
        - 10.246.153.96
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$96
      - asNumber: 65097
        interfaceAddresses:
        - 10.246.153.97
        - 10.246.153.97
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$97
      - asNumber: 65098
        interfaceAddresses:
        - 10.246.153.98
        - 10.246.153.98
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$98
      - asNumber: 65099
        interfaceAddresses:
        - 10.246.153.99
        - 10.246.153.99
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$99
      - asNumber: 65100
        interfaceAddresses:
        - 10.246.153.100
        - 10.246.153.100
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$100
      - asNumber: 65101
        interfaceAddresses:
        - 10.246.153.101
        - 10.246.153.101
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$101
      - asNumber: 65102
        interfaceAddresses:
        - 10.246.153.102
        - 10.246.153.102
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$102
      - asNumber: 65103
        interfaceAddresses:
        - 10.246.153.103
        - 10.246.153.103
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$103
      - asNumber: 65104
        interfaceAddresses:
        - 10.246.153.104
        - 10.246.153.104
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$104
      - asNumber: 65105
        interfaceAddresses:
        - 10.246.153.105
        - 10.246.153.105
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$105
      - asNumber: 65106
        interfaceAddresses:
        - 10.246.153.106
        - 10.246.153.106
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$106
      - asNumber: 65107
        interfaceAddresses:
        - 10.246.153.107
        - 10.246.153.107
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$107
      - asNumber: 65108
        interfaceAddresses:
        - 10.246.153.108
        - 10.246.153.108
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$108
      - asNumber: 65109
        interfaceAddresses:
        - 10.246.153.109
        - 10.246.153.109
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$109
      - asNumber: 65110
        interfaceAddresses:
        - 10.246.153.110
        - 10.246.153.110
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$110
      - asNumber: 65111
        interfaceAddresses:
        - 10.246.153.111
        - 10.246.153.111
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$111
      - asNumber: 65112
        interfaceAddresses:
        - 10.246.153.112
        - 10.246.153.112
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$112
      - asNumber: 65113
        interfaceAddresses:
        - 10.246.153.113
        - 10.246.153.113
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$113
      - asNumber: 65114
        interfaceAddresses:
        - 10.246.153.114
        - 10.246.153.114
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$114
      - asNumber: 65115
        interfaceAddresses:
        - 10.246.153.115
        - 10.246.153.115
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$115
      - asNumber: 65116
        interfaceAddresses:
        - 10.246.153.116
        - 10.246.153.116
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$116
      - asNumber: 65117
        interfaceAddresses:
        - 10.246.153.117
        - 10.246.153.117
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$117
      - asNumber: 65118
        interfaceAddresses:
        - 10.246.153.118
        - 10.246.153.118
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$118
      - asNumber: 65119
        interfaceAddresses:
        - 10.246.153.119
        - 10.246.153.119
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$119
      - asNumber: 65120
        interfaceAddresses:
        - 10.246.153.120
        - 10.246.153.120
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$120
      - asNumber: 65121
        interfaceAddresses:
        - 10.246.153.121
        - 10.246.153.121
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$121
      - asNumber: 65122
        interfaceAddresses:
        - 10.246.153.122
        - 10.246.153.122
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$122
      - asNumber: 65123
        interfaceAddresses:
        - 10.246.153.123
        - 10.246.153.123
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$123
      - asNumber: 65124
        interfaceAddresses:
        - 10.246.153.124
        - 10.246.153.124
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$124
      - asNumber: 65125
        interfaceAddresses:
        - 10.246.153.125
        - 10.246.153.125
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$125
      - asNumber: 65126
        interfaceAddresses:
        - 10.246.153.126
        - 10.246.153.126
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$126
      - asNumber: 65127
        interfaceAddresses:
        - 10.246.153.127
        - 10.246.153.127
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$127
      - asNumber: 65128
        interfaceAddresses:
        - 10.246.153.128
        - 10.246.153.128
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$128
      - asNumber: 65129
        interfaceAddresses:
        - 10.246.153.129
        - 10.246.153.129
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$129
      - asNumber: 65130
        interfaceAddresses:
        - 10.246.153.130
        - 10.246.153.130
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$130
      - asNumber: 65131
        interfaceAddresses:
        - 10.246.153.131
        - 10.246.153.131
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$131
      - asNumber: 65132
        interfaceAddresses:
        - 10.246.153.132
        - 10.246.153.132
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$132
      - asNumber: 65133
        interfaceAddresses:
        - 10.246.153.133
        - 10.246.153.133
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$133
      - asNumber: 65134
        interfaceAddresses:
        - 10.246.153.134
        - 10.246.153.134
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$134
      - asNumber: 65135
        interfaceAddresses:
        - 10.246.153.135
        - 10.246.153.135
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$135
      - asNumber: 65136
        interfaceAddresses:
        - 10.246.153.136
        - 10.246.153.136
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$136
      - asNumber: 65137
        interfaceAddresses:
        - 10.246.153.137
        - 10.246.153.137
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$137
      - asNumber: 65138
        interfaceAddresses:
        - 10.246.153.138
        - 10.246.153.138
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$138
      - asNumber: 65139
        interfaceAddresses:
        - 10.246.153.139
        - 10.246.153.139
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$139
      - asNumber: 65140
        interfaceAddresses:
        - 10.246.153.140
        - 10.246.153.140
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$140
      - asNumber: 65141
        interfaceAddresses:
        - 10.246.153.141
        - 10.246.153.141
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$141
      - asNumber: 65142
        interfaceAddresses:
        - 10.246.153.142
        - 10.246.153.142
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$142
      - asNumber: 65143
        interfaceAddresses:
        - 10.246.153.143
        - 10.246.153.143
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$143
      - asNumber: 65144
        interfaceAddresses:
        - 10.246.153.144
        - 10.246.153.144
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$144
      - asNumber: 65145
        interfaceAddresses:
        - 10.246.153.145
        - 10.246.153.145
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$145
      - asNumber: 65146
        interfaceAddresses:
        - 10.246.153.146
        - 10.246.153.146
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$146
      - asNumber: 65147
        interfaceAddresses:
        - 10.246.153.147
        - 10.246.153.147
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$147
      - asNumber: 65148
        interfaceAddresses:
        - 10.246.153.148
        - 10.246.153.148
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$148
      - asNumber: 65149
        interfaceAddresses:
        - 10.246.153.149
        - 10.246.153.149
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$149
      - asNumber: 65150
        interfaceAddresses:
        - 10.246.153.150
        - 10.246.153.150
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$150
      - asNumber: 65151
        interfaceAddresses:
        - 10.246.153.151
        - 10.246.153.151
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$151
      - asNumber: 65152
        interfaceAddresses:
        - 10.246.153.152
        - 10.246.153.152
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$152
      - asNumber: 65153
        interfaceAddresses:
        - 10.246.153.153
        - 10.246.153.153
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$153
      - asNumber: 65154
        interfaceAddresses:
        - 10.246.153.154
        - 10.246.153.154
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$154
      - asNumber: 65155
        interfaceAddresses:
        - 10.246.153.155
        - 10.246.153.155
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$155
      - asNumber: 65156
        interfaceAddresses:
        - 10.246.153.156
        - 10.246.153.156
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$156
      - asNumber: 65157
        interfaceAddresses:
        - 10.246.153.157
        - 10.246.153.157
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$157
      - asNumber: 65158
        interfaceAddresses:
        - 10.246.153.158
        - 10.246.153.158
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$158
      - asNumber: 65159
        interfaceAddresses:
        - 10.246.153.159
        - 10.246.153.159
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$159
      - asNumber: 65160
        interfaceAddresses:
        - 10.246.153.160
        - 10.246.153.160
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$160
      - asNumber: 65161
        interfaceAddresses:
        - 10.246.153.161
        - 10.246.153.161
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$161
      - asNumber: 65162
        interfaceAddresses:
        - 10.246.153.162
        - 10.246.153.162
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$162
      - asNumber: 65163
        interfaceAddresses:
        - 10.246.153.163
        - 10.246.153.163
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$163
      - asNumber: 65164
        interfaceAddresses:
        - 10.246.153.164
        - 10.246.153.164
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$164
      - asNumber: 65165
        interfaceAddresses:
        - 10.246.153.165
        - 10.246.153.165
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$165
      - asNumber: 65166
        interfaceAddresses:
        - 10.246.153.166
        - 10.246.153.166
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$166
      - asNumber: 65167
        interfaceAddresses:
        - 10.246.153.167
        - 10.246.153.167
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$167
      - asNumber: 65168
        interfaceAddresses:
        - 10.246.153.168
        - 10.246.153.168
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$168
      - asNumber: 65169
        interfaceAddresses:
        - 10.246.153.169
        - 10.246.153.169
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$169
      - asNumber: 65170
        interfaceAddresses:
        - 10.246.153.170
        - 10.246.153.170
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$170
      - asNumber: 65171
        interfaceAddresses:
        - 10.246.153.171
        - 10.246.153.171
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$171
      - asNumber: 65172
        interfaceAddresses:
        - 10.246.153.172
        - 10.246.153.172
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$172
      - asNumber: 65173
        interfaceAddresses:
        - 10.246.153.173
        - 10.246.153.173
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$173
      - asNumber: 65174
        interfaceAddresses:
        - 10.246.153.174
        - 10.246.153.174
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$174
      - asNumber: 65175
        interfaceAddresses:
        - 10.246.153.175
        - 10.246.153.175
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$175
      - asNumber: 65176
        interfaceAddresses:
        - 10.246.153.176
        - 10.246.153.176
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$176
      - asNumber: 65177
        interfaceAddresses:
        - 10.246.153.177
        - 10.246.153.177
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$177
      - asNumber: 65178
        interfaceAddresses:
        - 10.246.153.178
        - 10.246.153.178
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$178
      - asNumber: 65179
        interfaceAddresses:
        - 10.246.153.179
        - 10.246.153.179
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$179
      - asNumber: 65180
        interfaceAddresses:
        - 10.246.153.180
        - 10.246.153.180
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$180
      - asNumber: 65181
        interfaceAddresses:
        - 10.246.153.181
        - 10.246.153.181
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$181
      - asNumber: 65182
        interfaceAddresses:
        - 10.246.153.182
        - 10.246.153.182
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$182
      - asNumber: 65183
        interfaceAddresses:
        - 10.246.153.183
        - 10.246.153.183
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$183
      - asNumber: 65184
        interfaceAddresses:
        - 10.246.153.184
        - 10.246.153.184
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$184
      - asNumber: 65185
        interfaceAddresses:
        - 10.246.153.185
        - 10.246.153.185
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$185
      - asNumber: 65186
        interfaceAddresses:
        - 10.246.153.186
        - 10.246.153.186
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$186
      - asNumber: 65187
        interfaceAddresses:
        - 10.246.153.187
        - 10.246.153.187
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$187
      - asNumber: 65188
        interfaceAddresses:
        - 10.246.153.188
        - 10.246.153.188
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$188
      - asNumber: 65189
        interfaceAddresses:
        - 10.246.153.189
        - 10.246.153.189
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$189
      - asNumber: 65190
        interfaceAddresses:
        - 10.246.153.190
        - 10.246.153.190
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$190
      - asNumber: 65191
        interfaceAddresses:
        - 10.246.153.191
        - 10.246.153.191
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$191
      - asNumber: 65192
        interfaceAddresses:
        - 10.246.153.192
        - 10.246.153.192
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$192
      - asNumber: 65193
        interfaceAddresses:
        - 10.246.153.193
        - 10.246.153.193
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$193
      - asNumber: 65194
        interfaceAddresses:
        - 10.246.153.194
        - 10.246.153.194
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$194
      - asNumber: 65195
        interfaceAddresses:
        - 10.246.153.195
        - 10.246.153.195
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$195
      - asNumber: 65196
        interfaceAddresses:
        - 10.246.153.196
        - 10.246.153.196
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$196
      - asNumber: 65197
        interfaceAddresses:
        - 10.246.153.197
        - 10.246.153.197
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$197
      - asNumber: 65198
        interfaceAddresses:
        - 10.246.153.198
        - 10.246.153.198
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$198
      - asNumber: 65199
        interfaceAddresses:
        - 10.246.153.199
        - 10.246.153.199
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$199
      - asNumber: 65200
        interfaceAddresses:
        - 10.246.153.200
        - 10.246.153.200
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$200
      - asNumber: 65201
        interfaceAddresses:
        - 10.246.153.201
        - 10.246.153.201
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$201
      - asNumber: 65202
        interfaceAddresses:
        - 10.246.153.202
        - 10.246.153.202
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$202
      - asNumber: 65203
        interfaceAddresses:
        - 10.246.153.203
        - 10.246.153.203
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$203
      - asNumber: 65204
        interfaceAddresses:
        - 10.246.153.204
        - 10.246.153.204
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$204
      - asNumber: 65205
        interfaceAddresses:
        - 10.246.153.205
        - 10.246.153.205
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$205
      - asNumber: 65206
        interfaceAddresses:
        - 10.246.153.206
        - 10.246.153.206
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$206
      - asNumber: 65207
        interfaceAddresses:
        - 10.246.153.207
        - 10.246.153.207
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$207
      - asNumber: 65208
        interfaceAddresses:
        - 10.246.153.208
        - 10.246.153.208
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$208
      - asNumber: 65209
        interfaceAddresses:
        - 10.246.153.209
        - 10.246.153.209
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$209
      - asNumber: 65210
        interfaceAddresses:
        - 10.246.153.210
        - 10.246.153.210
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$210
      - asNumber: 65211
        interfaceAddresses:
        - 10.246.153.211
        - 10.246.153.211
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$211
      - asNumber: 65212
        interfaceAddresses:
        - 10.246.153.212
        - 10.246.153.212
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$212
      - asNumber: 65213
        interfaceAddresses:
        - 10.246.153.213
        - 10.246.153.213
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$213
      - asNumber: 65214
        interfaceAddresses:
        - 10.246.153.214
        - 10.246.153.214
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$214
      - asNumber: 65215
        interfaceAddresses:
        - 10.246.153.215
        - 10.246.153.215
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$215
      - asNumber: 65216
        interfaceAddresses:
        - 10.246.153.216
        - 10.246.153.216
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$216
      - asNumber: 65217
        interfaceAddresses:
        - 10.246.153.217
        - 10.246.153.217
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$217
      - asNumber: 65218
        interfaceAddresses:
        - 10.246.153.218
        - 10.246.153.218
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$218
      - asNumber: 65219
        interfaceAddresses:
        - 10.246.153.219
        - 10.246.153.219
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$219
      - asNumber: 65220
        interfaceAddresses:
        - 10.246.153.220
        - 10.246.153.220
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$220
      - asNumber: 65221
        interfaceAddresses:
        - 10.246.153.221
        - 10.246.153.221
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$221
      - asNumber: 65222
        interfaceAddresses:
        - 10.246.153.222
        - 10.246.153.222
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$222
      - asNumber: 65223
        interfaceAddresses:
        - 10.246.153.223
        - 10.246.153.223
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$223
      - asNumber: 65224
        interfaceAddresses:
        - 10.246.153.224
        - 10.246.153.224
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$224
      - asNumber: 65225
        interfaceAddresses:
        - 10.246.153.225
        - 10.246.153.225
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$225
      - asNumber: 65226
        interfaceAddresses:
        - 10.246.153.226
        - 10.246.153.226
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$226
      - asNumber: 65227
        interfaceAddresses:
        - 10.246.153.227
        - 10.246.153.227
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$227
      - asNumber: 65228
        interfaceAddresses:
        - 10.246.153.228
        - 10.246.153.228
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$228
      - asNumber: 65229
        interfaceAddresses:
        - 10.246.153.229
        - 10.246.153.229
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$229
      - asNumber: 65230
        interfaceAddresses:
        - 10.246.153.230
        - 10.246.153.230
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$230
      - asNumber: 65231
        interfaceAddresses:
        - 10.246.153.231
        - 10.246.153.231
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$231
      - asNumber: 65232
        interfaceAddresses:
        - 10.246.153.232
        - 10.246.153.232
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$232
      - asNumber: 65233
        interfaceAddresses:
        - 10.246.153.233
        - 10.246.153.233
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$233
      - asNumber: 65234
        interfaceAddresses:
        - 10.246.153.234
        - 10.246.153.234
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$234
      - asNumber: 65235
        interfaceAddresses:
        - 10.246.153.235
        - 10.246.153.235
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$235
      - asNumber: 65236
        interfaceAddresses:
        - 10.246.153.236
        - 10.246.153.236
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$236
      - asNumber: 65237
        interfaceAddresses:
        - 10.246.153.237
        - 10.246.153.237
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$237
      - asNumber: 65238
        interfaceAddresses:
        - 10.246.153.238
        - 10.246.153.238
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$238
      - asNumber: 65239
        interfaceAddresses:
        - 10.246.153.239
        - 10.246.153.239
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$239
      - asNumber: 65240
        interfaceAddresses:
        - 10.246.153.240
        - 10.246.153.240
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$240
      - asNumber: 65241
        interfaceAddresses:
        - 10.246.153.241
        - 10.246.153.241
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$241
      - asNumber: 65242
        interfaceAddresses:
        - 10.246.153.242
        - 10.246.153.242
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$242
      - asNumber: 65243
        interfaceAddresses:
        - 10.246.153.243
        - 10.246.153.243
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$243
      - asNumber: 65244
        interfaceAddresses:
        - 10.246.153.244
        - 10.246.153.244
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$244
      - asNumber: 65245
        interfaceAddresses:
        - 10.246.153.245
        - 10.246.153.245
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$245
      - asNumber: 65246
        interfaceAddresses:
        - 10.246.153.246
        - 10.246.153.246
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$246
      - asNumber: 65247
        interfaceAddresses:
        - 10.246.153.247
        - 10.246.153.247
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$247
      - asNumber: 65248
        interfaceAddresses:
        - 10.246.153.248
        - 10.246.153.248
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$248
      - asNumber: 65249
        interfaceAddresses:
        - 10.246.153.249
        - 10.246.153.249
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$249
      - asNumber: 65250
        interfaceAddresses:
        - 10.246.153.250
        - 10.246.153.250
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$250
      - asNumber: 65251
        interfaceAddresses:
        - 10.246.153.251
        - 10.246.153.251
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$251
      - asNumber: 65252
        interfaceAddresses:
        - 10.246.153.252
        - 10.246.153.252
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$252
      - asNumber: 65253
        interfaceAddresses:
        - 10.246.153.253
        - 10.246.153.253
        labels:
          rack: rack1
        peerings:
        - peerASNumber: 65501
          peerIP: {{switch_network_sw1}}
        - peerASNumber: 65502
          peerIP: {{switch_network_sw2}}
        stableAddress:
          address: 10.30.30.$253

  path: /calico-early/cfg.yaml
  owner: root:root
runcmd:
- ["/tmp/configure_gateway.py", "--cidr", "10.10.10.0/24", "--gateway", "10.10.10.3"]
- [/tmp/setup-env.sh]
