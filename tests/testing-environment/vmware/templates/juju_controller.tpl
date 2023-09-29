#cloud-config
package_update: true
package_upgrade: true
users:
  - name: ubuntu
    groups: [adm, audio, cdrom, dialout, floppy, video, plugdev, dip, netdev]
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
    HTTP_PROXY="http://squid.internal:3128"
    HTTPS_PROXY="http://squid.internal:3128"
    http_proxy="http://squid.internal:3128"
    https_proxy="http://squid.internal:3128"
    NO_PROXY="localhost,127.0.0.1,0.0.0.0,ppa.launchpad.net,launchpad.net,10.246.153.0/24,10.246.154.0/24"
    no_proxy="localhost,127.0.0.1,0.0.0.0,ppa.launchpad.net,launchpad.net,10.246.153.0/24,10.246.154.0/24"
  path: /etc/environment
  permissions: "0644"
  owner: root:root
output: {all: '| tee -a /var/log/cloud-init-output.log'}
