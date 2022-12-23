#!/bin/sh
OFFLINE=0

[ -f /tmp/.istoreos_offline ] && OFFLINE=1
touch /tmp/.istoreos_offline

ip link add name br-iso0 type bridge
ip link add name br-iso1 type bridge
sysctl -w net.ipv6.conf.br-iso0.disable_ipv6=1
sysctl -w net.ipv6.conf.br-iso1.disable_ipv6=1
sysctl -w net.ipv4.ip_forward=1
./firewall.sh start
ip link set br-iso0 up
ip link set br-iso1 up
ip addr add 172.11.1.1/24 dev br-iso0
ip addr add 192.168.100.2/24 dev br-iso1
virsh start istoreos

[ "$1" = init -o "$OFFLINE" = 1 ] || {
    virsh snapshot-revert istoreos --snapshotname istoreos-running --running # --force
    ./firewall.sh unblock
    rm -f /tmp/.istoreos_offline
}
