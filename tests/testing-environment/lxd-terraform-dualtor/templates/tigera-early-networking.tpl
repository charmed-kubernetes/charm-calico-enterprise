#cloud-config
write_files:
- content: |
    #!/bin/bash
    sudo apt-get update
    sudo docker login quay.io -u "{TIGERA_REGISTRY_USER}" -p "{TIGERA_REGISTRY_PASSWORD}" 
    sudo docker run --network=host --privileged --rm \
    -v /calico-early:/calico-early \
    -e CALICO_EARLY_NETWORKING=/calico-early/cfg.yaml \
    --name calico-early \
    -d \
    quay.io/tigera/cnx-node:v{CALICO_EARLY_VERSION}
    

  path: /tmp/setup-env.sh
  permissions: "0744"
  owner: root:root
- content: |
    apiVersion: projectcalico.org/v3
    kind: EarlyNetworkConfiguration
    spec:
      nodes:
      - interfaceAddresses:
          - ${switch_network_sw1}.${node_final_octet}
          - ${switch_network_sw2}.${node_final_octet}
        stableAddress:
          address: 10.30.30.${node_final_octet}
        asNumber: ${stableip_asn}
        peerings:
          - peerIP: ${switch_network_sw1}.${tor_sw1_octet}
            peerASNumber: ${tor_sw1_asn}
          - peerIP: ${switch_network_sw2}.${tor_sw2_octet}
            peerASNumber: ${tor_sw2_asn}
        labels:
          rack: rack1
  path: /calico-early/cfg.yaml
  owner: root:root
packages:
- bird2
runcmd:
- [/tmp/setup-env.sh]
# TODO:
- [ip, a, add, dev, lo, brd, +, 10.30.30.${node_final_octet}]
# TODO:
# - [iptables', '-t', 'nat', '-A', 'POSTROUTING', '-o', 'eth0', '-j', 'SNAT', '--to', 'TODO']