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

# 10.246.153.0/24 
data "vsphere_network" "vlan_2763" {
  name          = "VLAN_2763"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# 10.246.154.0/24 
data "vsphere_network" "vlan_2764" {
  name          = "VLAN_2764"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}
# 10.246.155.0/24 
data "vsphere_network" "vlan_2765" {
  name          = "VLAN_2765"
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
      tor_sw1_asn              = 65021,
      tor_sw2_asn              = 65031,
      tor_sw1_octet            = "3",
      tor_sw2_octet            = "3",
      switch_network_sw1       = vsphere_virtual_machine.tor1.default_ip_address,
      switch_network_sw2       = vsphere_virtual_machine.tor2.default_ip_address,
      mgmt_network             = "10.246.153",
      node_final_octet         = 12
      nodes                    = range(0, 5),
      tigera_registry_secret   = var.tigera_registry_secret,
      calico_early_version     = var.calico_early_version,
      k8s_prefix               = "k8s-node"
      juju_authorized_key      = var.juju_authorized_key
    })
  }
}

data "cloudinit_config" "tor1" {
  gzip          = false
  base64_encode = true
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/templates/sw-cloud-init.tpl", {
      switch              = 1,
      switch_asn          = 65501,
      switch_network      = "10.246.154",
      stableip_asn        = 64512,
      stable_ip           = "10.30.30.101",
      switch_final_octet  = 23,
      peer_tor_as         = 65502,
      switch_backbone_net = "10.246.153"
      juju_authorized_key = var.juju_authorized_key
    })
  }
}

data "cloudinit_config" "tor2" {
  gzip          = false
  base64_encode = true
  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/templates/sw-cloud-init.tpl", {
      switch              = 1,
      switch_asn          = 65502,
      switch_network      = "10.246.155",
      stableip_asn        = 64512,
      stable_ip           = "10.30.30.202",
      switch_final_octet  = 23,
      peer_tor_as         = 65501,
      switch_backbone_net = "10.246.153",
      juju_authorized_key = var.juju_authorized_key
    })
  }
}

data "vsphere_resource_pool" "default" {
  name          = format("%s%s", data.vsphere_compute_cluster.cluster.name, "/Resources")
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_virtual_machine" "template" {
  name          = "juju-ci-root/templates/jammy-test-template"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource "vsphere_folder" "folder" {
  path                 = var.vsphere_folder
  type                 = "vm"
  datacenter_id        = data.vsphere_datacenter.datacenter.id
}

resource "vsphere_virtual_machine" "k8s_nodes" {
  count                = 5
  name                 = "k8s-test-${count.index}"
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  num_cpus             = 2
  num_cores_per_socket = 2
  memory               = 16384
  guest_id             = data.vsphere_virtual_machine.template.guest_id
  scsi_type            = data.vsphere_virtual_machine.template.scsi_type
  nested_hv_enabled    = data.vsphere_virtual_machine.template.nested_hv_enabled
  folder               = vsphere_folder.folder.path
  vapp {
    properties = {
      hostname  = "k8s-node-${count.index}"
      user-data = data.cloudinit_config.calico_early.rendered
    }
  }
  network_interface {
    network_id = data.vsphere_network.vlan_2764.id
  }
  network_interface {
    network_id = data.vsphere_network.vlan_2765.id
  }
  disk {
    label            = "sda"
    size             = 100
    unit_number      = 0
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }
  cdrom {
    client_device = true
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }  
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}

resource "vsphere_virtual_machine" "tor1" {
  name                 = "tor1"
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  num_cpus             = 1
  num_cores_per_socket = 2
  memory               = 8192
  guest_id             = data.vsphere_virtual_machine.template.guest_id
  scsi_type            = data.vsphere_virtual_machine.template.scsi_type
  folder               = vsphere_folder.folder.path
  vapp {
    properties = {
      hostname  = "tor1"
      user-data = data.cloudinit_config.tor1.rendered
    }
  }
  # TODO: Resolve networking between ToRs and k8s nodes
  network_interface {
    network_id = data.vsphere_network.vlan_2764.id
  }
  network_interface {
    network_id = data.vsphere_network.vlan_2763.id
  }
  disk {
    label       = "sda"
    size        = 100
    unit_number = 0
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
  cdrom {
    client_device = true
  }
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.tor1.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.tor1.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}

resource "vsphere_virtual_machine" "tor2" {
  name                 = "tor2"
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  num_cpus             = 1
  num_cores_per_socket = 2
  memory               = 8192
  guest_id             = data.vsphere_virtual_machine.template.guest_id
  scsi_type            = data.vsphere_virtual_machine.template.scsi_type
  folder               = vsphere_folder.folder.path
  vapp {
    properties = {
      hostname  = "tor2"
      user-data = data.cloudinit_config.tor2.rendered
    }
  }
  # TODO: Resolve networking between ToRs and k8s nodes
  network_interface {
    network_id = data.vsphere_network.vlan_2765.id
  }
  network_interface {
    network_id = data.vsphere_network.vlan_2763.id
  }
  disk {
    label       = "sda"
    size        = 100
    unit_number = 0
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
  }
  cdrom {
    client_device = true
  }
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.tor2.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.tor2.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}
