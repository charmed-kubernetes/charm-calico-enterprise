#cloud-config
package_update: true
package_upgrade: true
users:
  - name: ubuntu
    groups: adm,audio,cdrom,dialout,floppy,video,plugdev,dip,netdev
    plain_text_passwd: "ubuntu"
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
    - ${juju_authorized_key}
    sudo:
    - ALL=(ALL) NOPASSWD:ALL
write_files:
- content: |
    PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
    HTTP_PROXY="${http_proxy}"
    HTTPS_PROXY="${https_proxy}"
    http_proxy="${http_proxy}"
    https_proxy="${https_proxy}"
    NO_PROXY="${no_proxy}"
    no_proxy="${no_proxy}"
  path: /etc/environment
  permissions: "0644"
  owner: root:root
output: {all: '| tee -a /var/log/cloud-init-output.log'}
