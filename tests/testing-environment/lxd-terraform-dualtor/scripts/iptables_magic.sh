#!/bin/bash

iptables -t nat -A POSTROUTING -s 192.168.0.0/16 ! -d 10.30.30.0/24 -o eth0 -j SNAT --to 10.77.167.159
iptables -t nat -A POSTROUTING -s 10.30.30.0/24 ! -d 10.30.30.0/24 -o eth0 -j SNAT --to 10.77.167.159