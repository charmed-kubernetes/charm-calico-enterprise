terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}


data "vsphere_datacenter" "datacenter" {
  name = "Bost"
}

data "vsphere_compute_cluster" "cluster" {
  name          = "Development"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  name          = "VLAN_2764"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name          = "vsanDatastore"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "cloudinit_config" "calico_early" {
  gzip          = false
  base64_encode = true
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/templates/tigera-early-networking.tpl", {
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
}


resource "vsphere_virtual_machine" "k8s_nodes" {
  count             = 5
  guest_id         = "other3xLinux64Guest"
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = 4
  memory           = 4096
  vapp {
    properties ={
      hostname = var.hostname
      user-data = cloudinit_config.calico_early.rendered
    }
  }

  disk {
    label = "sda"
    size  = 20
  }
  extra_config = {
    "guestinfo.metadata"          = cloudinit_config.calico_early.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = cloudinit_config.calico_early.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}
