terraform {
  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "2.3.1"
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
      tor_sw1_asn        = 65021,
      tor_sw2_asn        = 65031,
      tor_sw1_octet      = "3",
      tor_sw2_octet      = "3",
      switch_network_sw1 = "10.10.10",
      switch_network_sw2 = "10.10.20",
      mgmt_network       = "10.10.32",
      node_final_octet   = 12
      nodes              = range(0, 5)
    })
  }
}

data "vsphere_virtual_machine" "template" {
  name          = "ubuntu-jammy-larger-var"
  datacenter_id = data.vsphere_datacenter.datacenter.id

}

data "vsphere_resource_pool" "default" {
  name          = format("%s%s", data.vsphere_compute_cluster.cluster.name, "/Resources")
  datacenter_id = data.vsphere_datacenter.datacenter.id
}


data "vsphere_host" "host" {
  name          = "eyerok.internal"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_ovf_vm_template" "ubuntu_jammy" {
  name              = "ubuntu-ovf-deploy"
  disk_provisioning = "thin"
  resource_pool_id  = data.vsphere_resource_pool.default.id
  datastore_id      = data.vsphere_datastore.datastore.id
  host_system_id    = data.vsphere_host.host.id
  remote_ovf_url    = "http://cloud-images.ubuntu.com/daily/server/jammy/current/jammy-server-cloudimg-amd64.ova"
  ovf_network_map = {
    "VM Network" : data.vsphere_network.network.id
  }
}

resource "vsphere_virtual_machine" "k8s_nodes" {
  count                = 5
  name                 = "k8s-test-${count.index}"
  datacenter_id        = data.vsphere_datacenter.datacenter.id
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  num_cpus             = data.vsphere_ovf_vm_template.ubuntu_jammy.num_cpus
  num_cores_per_socket = data.vsphere_ovf_vm_template.ubuntu_jammy.num_cores_per_socket
  memory               = data.vsphere_ovf_vm_template.ubuntu_jammy.memory
  guest_id             = data.vsphere_ovf_vm_template.ubuntu_jammy.guest_id
  firmware             = data.vsphere_ovf_vm_template.ubuntu_jammy.firmware
  scsi_type            = data.vsphere_ovf_vm_template.ubuntu_jammy.scsi_type
  nested_hv_enabled    = data.vsphere_ovf_vm_template.ubuntu_jammy.nested_hv_enabled
  folder               = "fe-crew-root/pjds/manual-machines"
  vapp {
    properties = {
      hostname  = "k8s-node-${count.index}"
      user-data = data.cloudinit_config.calico_early.rendered
    }
  }
  network_interface {
    network_id = data.vsphere_network.network.id
  }
  cdrom {
    client_device = true
  }
  ovf_deploy {
    allow_unverified_ssl_cert = false
    remote_ovf_url            = data.vsphere_ovf_vm_template.ubuntu_jammy.remote_ovf_url
    disk_provisioning         = data.vsphere_ovf_vm_template.ubuntu_jammy.disk_provisioning
    ovf_network_map           = data.vsphere_ovf_vm_template.ubuntu_jammy.ovf_network_map
  }
  disk {
    label       = "sda"
    size        = 100
    unit_number = 0
  }
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}
