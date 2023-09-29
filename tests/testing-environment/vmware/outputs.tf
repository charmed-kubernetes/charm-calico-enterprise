output "k8s_addresses" {
    value = {
        for k, v in vsphere_virtual_machine.k8s_nodes : k => v.default_ip_address
    }
}
output "controller" {
    value = vsphere_virtual_machine.juju-controller.default_ip_address
}
output "tor1" {
    value = vsphere_virtual_machine.tor1.default_ip_address
}
output "tor2" {
    value = vsphere_virtual_machine.tor2.default_ip_address
}
