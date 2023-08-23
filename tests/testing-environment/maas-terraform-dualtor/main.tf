terraform {
  required_providers {
    maas = {
      source  = "maas/maas"
      version = "~>1.0"
    }
  }
}

provider "maas" {
  api_version = "2.0"
  api_key = var.maas_api_key
  api_url = var.maas_api_url
}

resource "maas_instance" "juju_mnl" {
  count = 1
  allocate_params {
    pool = "default"
    zone = "default"
    tags = [
      "juju-manual",
    ]
  }
  deploy_params {
    distro_series = "jammy"
  }
  network_interfaces {
        name = "eth0"
        ip_address = "10.10.32.8${0+count.index}"
        subnet_cidr = "10.10.32.0/24"
    }
}

resource "maas_instance" "k8s_nodes" {
  count = 5
  allocate_params {
    hostname = "k8s-hm-${count.index}"
    pool = "default"
    zone = "default"
    tags = [
      "tigera-hm",
    ]
  }
  deploy_params {
    distro_series = "jammy"
    user_data = templatefile("${path.module}/templates/tigera-early-networking.tpl", {
        tor_sw1_asn = 65021,
        tor_sw2_asn = 65031, 
        tor_sw1_octet = "3",
        tor_sw2_octet = "3",
        switch_network_sw1 = "10.10.10",
        switch_network_sw2 = "10.10.20",
        mgmt_network = "10.10.32",
        node_final_octet = 12+count.index
        nodes = range(0, 5)
    })
  }
  network_interfaces {
        name = "eth0"
        ip_address = "10.10.32.${12+count.index}"
        subnet_cidr = "10.10.32.0/24"
    }
  network_interfaces {
        name = "eth1"
        ip_address = "10.10.10.${12+count.index}"
        subnet_cidr = "10.10.10.0/24"
    }
  network_interfaces {
        name = "eth2"
        ip_address = "10.10.20.${12+count.index}"
        subnet_cidr = "10.10.20.0/24"
  }
}

locals {
  nodes = flatten([
    for i, node in maas_instance.k8s_nodes : {
        hostname = "k8s-node-${0+i}",
        stableIP = "10.30.30.${12+i}",
        stableIPASN = "${65000+i}",
        rackName = "rack1",
        sw1Interface = "10.10.10.${12+i}",
        sw1IP = "10.10.10.3",
        sw1ASN = "65021",
        sw2Interface = "10.10.20.${12+i}",
        sw2IP = "10.10.20.3",
        sw2ASN = "65031"
    }
  ])
}

resource "local_file" "generated_bundle" {
  content = templatefile("${path.module}/templates/bundle.tpl", { 
      nodes = local.nodes 
      TIGERA_DEPLOYMENT_MANIFEST = ""
      TIGERA_CRD_MANIFEST = ""
      TIGERA_LICENSE_FILE_PATH = ""
      TIGERA_REGISTRY_USER = "",
      TIGERA_REGISTRY_PASSWORD = "",
      CHARM_PATH = ""
    })
  filename = "${path.module}/generated-bundle.yaml"
}
resource "local_file" "generated_cloud_init" {
  content = templatefile("${path.module}/templates/tigera-early-networking.tpl", {
        tor_sw1_asn = 65021,
        tor_sw2_asn = 65031, 
        tor_sw1_octet = "3",
        tor_sw2_octet = "3",
        switch_network_sw1 = "10.10.10",
        switch_network_sw2 = "10.10.20",
        mgmt_network = "10.10.32",
        nodes = range(0, 5),
        TIGERA_REGISTRY_USER = "",
        TIGERA_REGISTRY_PASSWORD = "",
        CALICO_EARLY_VERSION = ""
        
    })
  filename = "${path.module}/generated-cloudinit.yaml"
}