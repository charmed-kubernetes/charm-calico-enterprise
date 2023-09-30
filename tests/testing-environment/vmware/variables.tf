variable "vsphere_server" {
    description = "IP Address of the VSphere Environment."
    type        = string
    sensitive   = true
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

variable "tigera_registry_secret" {
    description = "$username:$password to use when pulling the tigera images from the upstream repos."
    type = string
    sensitive = true
}

variable "calico_early_version" {
    type = string
    default = "3.17.1"
}