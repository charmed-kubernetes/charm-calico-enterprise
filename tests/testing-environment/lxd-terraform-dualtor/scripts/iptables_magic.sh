#!/bin/bash

iptables -t nat -A POSTROUTING -s 192.168.0.0/16 ! -d 10.30.30.0/24 -o eth0 -j SNAT --to $(ip -j -4 a | jq -r '.[] | select(.ifname=="ens192") | .addr_info[0].local')
iptables -t nat -A POSTROUTING -s 10.30.30.0/24 ! -d 10.30.30.0/24 -o eth0 -j SNAT --to $(ip -j -4 a | jq -r '.[] | select(.ifname=="ens192") | .addr_info[0].local')