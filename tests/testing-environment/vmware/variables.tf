variable "vsphere_server" {
    description = "IP Address of the VSphere Environment."
    sensitive   = true
    type        = string
}

variable "vsphere_user" {
    description = "Username for VSphere Environment"
    type        = string
    sensitive   = true
}

variable "vsphere_password" {
    description = "Password for VSphere Environment"
    type        = string
    sensitive   = true
}

variable "vsphere_folder" {
    description = "Folder location in which vsphere starts the vm instances"
    type = string
}

variable "juju_authorized_key" {
    description = "Public key juju will use when adding the machines to the model."
    type = string
}

variable "tigera_registry_user" {
    type = string
    default = "VALUE NOT SET"
    sensitive = true
}

variable "tigera_registry_password" {
    type = string
    default = "VALUE NOT SET"
    sensitive = true
}

variable "calico_early_version" {
    type = string
    default = "3.17.1"
}