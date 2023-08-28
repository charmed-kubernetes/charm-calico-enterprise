terraform {
  required_providers {
    vsphere = {
      source = "hashicorp/vsphere"
      version = "2.4.2"
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
  name = "Boston"
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
  name          = "Azalea-OS-Disk"
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
        node_final_octet = 12
        nodes = range(0, 5)
    })
  }
}

data "vsphere_virtual_machine" "template" {
  name          = "ubuntu-jammy-22.04-cloudimg"
  datacenter_id = data.vsphere_datacenter.datacenter.id

}

resource "vsphere_virtual_machine" "k8s_nodes" {
  # count             = 5
  name = "k8s-test0"
  guest_id         = "ubuntu64Guest"
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  num_cpus         = 4
  memory           = 4096
  folder           = "fe-crew-root/pjds/manual-machines"
  vapp {
    properties ={
      hostname = "test"
      user-data = data.cloudinit_config.calico_early.rendered
    }
  }
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  cdrom {
    client_device = true
  }
  disk {
    label = "sda"
    size  = 25
    unit_number = 0
  }
  disk {
    label = "sdb"
    size  = 25
    unit_number = 1
  }
  disk {
    label = "sdc"
    size  = 25
    unit_number = 2
  }
  disk {
    label = "sdd"
    size  = 100
    unit_number = 3
  }
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    # customize {
    #   linux_options {
    #     host_name = "hello-world"
    #     domain    = "example.com"
    #   }
    #   network_interface {
    #     ipv4_address = "172.16.11.10"
    #     ipv4_netmask = 24
    #   }
    #   ipv4_gateway = "172.16.11.1"
    # }
  }
}
