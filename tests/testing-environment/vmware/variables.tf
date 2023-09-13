variable "vsphere_user" {
    type = string
}

variable "vsphere_password" {
    type = string
}

variable "vsphere_folder" {
    type = string
}

variable "juju_authorized_key" {
    type = string
}

variable "vsphere_server" {
    type = string
}

variable "tigera_registry_user" {
    type = string
    default = "VALUE NOT SET"
}

variable "tigera_registry_password" {
    type = string
    default = "VALUE NOT SET"
}

variable "calico_early_version" {
    type = string
    default = "3.17.1"
}