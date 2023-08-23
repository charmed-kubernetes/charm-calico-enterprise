terraform {
  required_providers {
    lxd = {
      source  = "terraform-lxd/lxd"
      version = "1.9.1"
    }
  }
}


provider "lxd" {
}



resource "lxd_network" "lxd_ToR_Net" {
  name = "lxd_ToR_Net_19"

  config = {
    "ipv4.address" = "10.150.18.1/24"
    "ipv4.nat"     = "true"
    "ipv6.address" = "none"
    "ipv6.nat"     = "false"
    "raw.dnsmasq"  = "port=54"
  }
}
resource "lxd_network" "lxd_ToR_Net2" {
  name = "lxd_ToR_Net_18"

  config = {
    "ipv4.address" = "10.150.19.1/24"
    "ipv4.nat"     = "true"
    "ipv6.address" = "none"
    "ipv6.nat"     = "false"
    "raw.dnsmasq"  = "port=54"
  }
}
resource "lxd_project" "tigeralab" {
  name        = var.lxc_project
  description = "BGP sandbox"
  config = {
    "features.images" = false
  }

}
resource "lxd_profile" "dual_tor_profile" {
  name = "dual_tor_profile"
  project = lxd_project.tigeralab.name
  config = {
    "linux.kernel_modules" = "ip_vs,ip_vs_rr,ip_vs_wrr,ip_vs_sh,ip_tables,ip6_tables,netlink_diag,nf_nat,overlay,br_netfilter"
    "raw.lxc"              = "${file("${path.module}/raw.lxc")}"
  }
  device {
    name = "eth0"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "lxdbr0"
    }
  }
  device {
    name = "eth0"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "br0"
    }
  }

  device {
    type = "disk"
    name = "aadisable"

    properties = {
      source = "/sys/module/nf_conntrack/parameters/hashsize"
      path   = "/sys/module/nf_conntrack/parameters/hashsize"
    }
  }
  device {
    type = "unix-char"
    name = "aadisable2"

    properties = {
      source = "/dev/kmsg"
      path   = "/dev/kmsg"
    }
  }
  device {
    type = "disk"
    name = "aadisable3"

    properties = {
      source = "/dev/kmsg"
      path   = "/dev/kmsg"
    }
  }
  device {
    type = "disk"
    name = "aadisable4"

    properties = {
      source = "/proc/sys/net/netfilter/nf_conntrack_max"
      path   = "/proc/sys/net/netfilter/nf_conntrack_max"
    }
  }
  device {
    type = "disk"
    name = "root"

    properties = {
      pool = "default"
      path = "/"
    }
  }
}
# data "local_file" "cloud_init" {
#     filename = "${path.module}/cloud-init.yaml"
# }
# data "local_file" "raw_lxd" {
#     filename = "${path.module}/raw.lxc"
# }
resource "lxd_container" "ToR1" {
  name      = "ToR1"
  image     = "ubuntu:jammy"
  ephemeral = false
  profiles  = ["${lxd_profile.dual_tor_profile.name}"]
  project = lxd_project.tigeralab.name
  device {
    name = "eth1"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "br-vlan10"
    }
  }
    device {
    name = "eth2"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "${lxd_network.lxd_ToR_Net2.name}"
    }
  }

  config = {
    "boot.autostart"       = true
    "cloud-init.user-data" = templatefile("${path.module}/templates/sw-cloud-init.tpl", { 
      switch = 1, 
      switch_asn = 65021, 
      switch_network = "10.10.10", 
      stableip_asn = 64512,
      stable_ip = "10.30.30.1",
      switch_final_octet = 3,
      peer_tor_as = 65031,
      switch_backbone_net = "10.150.19"
    })
    "cloud-init.network-config" = templatefile("${path.module}/templates/network.tpl", { 
      switch_final_octet = 3
      switch_network = "10.10.10",
    })
  }

  limits = {
    cpu = 2
  }
}

resource "lxd_container" "ToR2" {
  name      = "ToR2"
  image     = "ubuntu:jammy"
  ephemeral = false
  profiles  = ["${lxd_profile.dual_tor_profile.name}"]
  project = lxd_project.tigeralab.name
  device {
    name = "eth1"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "br-vlan20"
    }
  }
  device {
    name = "eth2"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "${lxd_network.lxd_ToR_Net2.name}"
    }
  }
  config = {
    "boot.autostart"       = true
    "cloud-init.user-data" = templatefile("${path.module}/templates/sw-cloud-init.tpl", { 
      switch = 1, 
      switch_asn = 65031, 
      switch_network = "10.10.20", 
      stableip_asn = 64512,
      stable_ip = "10.30.30.21",
      switch_final_octet = 3,
      peer_tor_as = 65021,
      switch_backbone_net = "10.150.19"
    })
    "cloud-init.network-config" = templatefile("${path.module}/templates/network.tpl", { 
      switch_final_octet = 3,
      switch_network = "10.10.20", 
    })
  }

  

  limits = {
    cpu = 2
  }
}


resource "lxd_container" "IntegrationToR1" {
  name      = "IntegrationToR1"
  image     = "ubuntu:jammy"
  ephemeral = false
  profiles  = ["${lxd_profile.dual_tor_profile.name}"]
  project = lxd_project.tigeralab.name
  device {
    name = "eth1"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "br-vlan10"
    }
  }
    device {
    name = "eth2"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "${lxd_network.lxd_ToR_Net2.name}"
    }
  }

  config = {
    "boot.autostart"       = true
    "cloud-init.user-data" = templatefile("${path.module}/templates/sw-cloud-init.tpl", { 
      switch = 1, 
      switch_asn = 65021, 
      switch_network = "10.10.10", 
      stableip_asn = 64512,
      stable_ip = "10.30.30.31",
      switch_final_octet = 23,
      peer_tor_as = 65031,
      switch_backbone_net = "10.150.19"
    })
    "cloud-init.network-config" = templatefile("${path.module}/templates/network.tpl", { 
      switch_final_octet = 23
      switch_network = "10.10.10",
    })
  }

  limits = {
    cpu = 2
  }
}

resource "lxd_container" "IntegrationToR2" {
  name      = "IntegrationToR2"
  image     = "ubuntu:jammy"
  ephemeral = false
  profiles  = ["${lxd_profile.dual_tor_profile.name}"]
  project = lxd_project.tigeralab.name
  device {
    name = "eth1"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "br-vlan20"
    }
  }
  device {
    name = "eth2"
    type = "nic"

    properties = {
      nictype = "bridged"
      parent  = "${lxd_network.lxd_ToR_Net2.name}"
    }
  }
  config = {
    "boot.autostart"       = true
    "cloud-init.user-data" = templatefile("${path.module}/templates/sw-cloud-init.tpl", { 
      switch = 1, 
      switch_asn = 65031, 
      switch_network = "10.10.20", 
      stableip_asn = 64512,
      stable_ip = "10.30.30.41",
      switch_final_octet = 23,
      peer_tor_as = 65021,
      switch_backbone_net = "10.150.19"
    })
    "cloud-init.network-config" = templatefile("${path.module}/templates/network.tpl", { 
      switch_final_octet = 23,
      switch_network = "10.10.20", 
    })
  }

  

  limits = {
    cpu = 2
  }
}

