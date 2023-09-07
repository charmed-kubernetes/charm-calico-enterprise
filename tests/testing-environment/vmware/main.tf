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
      tor_sw1_asn        = 65021,
      tor_sw2_asn        = 65031,
      tor_sw1_octet      = "3",
      tor_sw2_octet      = "3",
      switch_network_sw1 = "10.246.154",
      switch_network_sw2 = "10.246.155",
      mgmt_network       = "10.246.153",
      node_final_octet   = 12
      nodes              = range(0, 5)
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
      switch = 1, 
      switch_asn = 65031, 
      switch_network = "10.246.154", 
      stableip_asn = 64512,
      stable_ip = "10.30.30.101",
      switch_final_octet = 23,
      peer_tor_as = 65021,
      switch_backbone_net = "10.246.153"
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
      switch = 1, 
      switch_asn = 65031, 
      switch_network = "10.246.154", 
      stableip_asn = 64512,
      stable_ip = "10.30.30.202",
      switch_final_octet = 23,
      peer_tor_as = 65021,
      switch_backbone_net = "10.246.153"
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
    "VM Network" : data.vsphere_network.vlan_2764.id
  }
}

resource "vsphere_virtual_machine" "k8s_nodes" {
  count                = 5
  name                 = "k8s-test-${count.index}"
  datacenter_id        = data.vsphere_datacenter.datacenter.id
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  num_cpus             = 2
  num_cores_per_socket = 2
  memory               = 16
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
    network_id = data.vsphere_network.vlan_2764.id
  }
  network_interface {
    network_id = data.vsphere_network.vlan_2765.id
  }
  # clone {
  #   template_uuid = data.vsphere_virtual_machine.template.id
  #   customize {
  #     linux_options {
  #       host_name = "k8s-node-${count.index}"
  #       domain    = "local"
  #     }
  #     network_interface {
  #       ipv4_address = "10.246.154.${100+count.index}"
  #       ipv4_netmask = 24
  #     }
  #     network_interface {
  #       ipv4_address = "10.246.155.${100+count.index}"
  #       ipv4_netmask = 24
  #     }
  #   }
  # }
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
  # disk {
  #   label       = "sdb"
  #   size        = 100
  #   unit_number = 1
  # }
  # disk {
  #   label       = "sdc"
  #   size        = 100
  #   unit_number = 2
  # }
  # disk {
  #   label       = "sdb"
  #   size        = 100
  #   unit_number = 3
  # }
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.calico_early.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}

resource "vsphere_virtual_machine" "tor1" {
  name                 = "tor1"
  datacenter_id        = data.vsphere_datacenter.datacenter.id
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  num_cpus             = 1
  num_cores_per_socket = 2
  memory               = 8
  guest_id             = data.vsphere_ovf_vm_template.ubuntu_jammy.guest_id
  firmware             = data.vsphere_ovf_vm_template.ubuntu_jammy.firmware
  scsi_type            = data.vsphere_ovf_vm_template.ubuntu_jammy.scsi_type
  nested_hv_enabled    = data.vsphere_ovf_vm_template.ubuntu_jammy.nested_hv_enabled
  folder               = "fe-crew-root/pjds/manual-machines"
  vapp {
    properties = {
      hostname  = "tor1"
      user-data = data.cloudinit_config.calico_early.rendered
    }
  }
  # TODO: Resolve networking between ToRs and k8s nodes
  network_interface {
    network_id = data.vsphere_network.vlan_2764.id
  }
  network_interface {
    network_id = data.vsphere_network.vlan_2763.id
  }
  # clone {
  #   template_uuid = data.vsphere_virtual_machine.template.id
  #   customize {
  #     linux_options {
  #       host_name = "tor1"
  #       domain    = "local"
  #     }
  #     network_interface {
  #       ipv4_address = "10.246.154.201"
  #       ipv4_netmask = 24
  #     }
  #   }
  # }
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
  # disk {
  #   label       = "sdb"
  #   size        = 100
  #   unit_number = 1
  # }
  # disk {
  #   label       = "sdc"
  #   size        = 100
  #   unit_number = 2
  # }
  # disk {
  #   label       = "sdb"
  #   size        = 100
  #   unit_number = 3
  # }
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.tor1.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.tor1.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
}

resource "vsphere_virtual_machine" "tor2" {
  name                 = "tor2"
  datacenter_id        = data.vsphere_datacenter.datacenter.id
  resource_pool_id     = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id         = data.vsphere_datastore.datastore.id
  host_system_id       = data.vsphere_host.host.id
  num_cpus             = 1
  num_cores_per_socket = 2
  memory               = 8
  guest_id             = data.vsphere_ovf_vm_template.ubuntu_jammy.guest_id
  firmware             = data.vsphere_ovf_vm_template.ubuntu_jammy.firmware
  scsi_type            = data.vsphere_ovf_vm_template.ubuntu_jammy.scsi_type
  nested_hv_enabled    = data.vsphere_ovf_vm_template.ubuntu_jammy.nested_hv_enabled
  folder               = "fe-crew-root/pjds/manual-machines"
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
  # clone {
  #   template_uuid = data.vsphere_virtual_machine.template.id
  #   customize {
  #     linux_options {
  #       host_name = "tor2"
  #       domain    = "local"
  #     }
  #     network_interface {
  #       ipv4_address = "10.246.155.201"
  #       ipv4_netmask = 24
  #     }
  #   }
  # }
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
  # disk {
  #   label       = "sdb"
  #   size        = 100
  #   unit_number = 1
  # }
  # disk {
  #   label       = "sdc"
  #   size        = 100
  #   unit_number = 2
  # }
  # disk {
  #   label       = "sdc"
  #   size        = 100
  #   unit_number = 3
  # }
  
  extra_config = {
    "guestinfo.metadata"          = data.cloudinit_config.tor2.rendered
    "guestinfo.metadata.encoding" = "base64"
    "guestinfo.userdata"          = data.cloudinit_config.tor2.rendered
    "guestinfo.userdata.encoding" = "base64"
  }
  # device {
  #   name = "eth1"
  #   type = "nic"

  #   properties = {
  #     nictype = "bridged"
  #     parent  = "br-vlan20"
  #   }
  # }
  # device {
  #   name = "eth2"
  #   type = "nic"

  #   properties = {
  #     nictype = "bridged"
  #     parent  = "${lxd_network.lxd_ToR_Net2.name}"
  #   }
  # }
}
