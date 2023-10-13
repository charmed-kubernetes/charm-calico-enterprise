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

variable "http_proxy" {
    type = string
    description = "Redirect through a proxy address for all http requests"
    default = "http://squid.internal:3128"
}

variable "https_proxy" {
    type = string
    description = "Redirect through a proxy address for all https requests"
    default = "http://squid.internal:3128"
}

variable "no_proxy" {
    type = string
    description = "Ignore http/https proxy for the following hosts/cirds"
    default = "localhost,127.0.0.1,0.0.0.0,ppa.launchpad.net,launchpad.net,10.101.249.0/24,10.152.183.0/24,10.246.153.0/24,10.246.154.0/24,10.246.155.0/24"
}