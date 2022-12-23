#!/bin/sh
LAN_IF=br-iso1
WAN_IF=br-iso0

# block VM accessing the internet
BLOCK_PORT="22 23 101 107 512 513 992"
BLOCK_NET="192.168.0.0/16 172.0.0.0/8 169.0.0.0/8 127.0.0.0/8 10.0.0.0/8"

# forward host ports to VM's
FORWARD_PORTS="80 443 1024:65535"
PROXY_PORTS="80 443"

patch_legacy(){
    iptables-legacy -N ISKVM_FWI && iptables-legacy -A ISKVM_FWI -j ACCEPT && iptables-legacy -A FORWARD -i $WAN_IF -j ISKVM_FWI
    iptables-legacy -N ISKVM_FWO && iptables-legacy -A ISKVM_FWO -j ACCEPT && iptables-legacy -A FORWARD -o $WAN_IF -j ISKVM_FWO
    return 0
}

unblock(){
    local port
    iptables -t nat -F ISKVM_FWD
    iptables -t nat -A ISKVM_FWD -i $WAN_IF -j RETURN
    iptables -t nat -A ISKVM_FWD -i $LAN_IF -j RETURN
    iptables -F ISKVM_WEB
    # port forward
    for port in $FORWARD_PORTS ; do
        iptables -t nat -A ISKVM_FWD -p tcp -m tcp --dport $port -j DNAT --to-destination 192.168.100.1:`echo $port | sed 's/:/-/g'`
        iptables -t nat -A ISKVM_FWD -p udp -m udp --dport $port -j DNAT --to-destination 192.168.100.1:`echo $port | sed 's/:/-/g'`
    done

    # proxy by nginx or something
    [ -z "$PROXY_PORTS" ] && return 0
    for port in $PROXY_PORTS ; do
        iptables -A ISKVM_WEB -p tcp -m tcp --dport $port -j ACCEPT
        iptables -A ISKVM_WEB -p udp -m udp --dport $port -j ACCEPT
    done
}

block(){
    local port
    iptables -t nat -F ISKVM_FWD
    iptables -t nat -A ISKVM_FWD -i $WAN_IF -j RETURN
    iptables -t nat -A ISKVM_FWD -i $LAN_IF -j RETURN
    iptables -F ISKVM_WEB
    [ -z "$PROXY_PORTS" ] && return 0
    for port in $PROXY_PORTS ; do
        iptables -A ISKVM_WEB -p tcp -m tcp --dport $port -j REJECT --reject-with icmp-port-unreachable
        iptables -A ISKVM_WEB -p udp -m udp --dport $port -j REJECT --reject-with icmp-port-unreachable
    done
}

start(){
    local chain
    local port
    local net
    stop >/dev/null 2>&1

    # filter table
    for chain in ISKVM_INP ISKVM_FWI ISKVM_FWO ISKVM_FWB ISKVM_OUT ISKVM_WEB ; do
        iptables -N $chain
        iptables -F $chain
    done
    iptables -A ISKVM_INP -d 172.11.1.0/24 -p icmp -m icmp --icmp-type 8 -j ACCEPT
    iptables -A ISKVM_INP -d 192.168.100.0/24 -p icmp -m icmp --icmp-type 8 -j ACCEPT
    iptables -A ISKVM_INP -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -A ISKVM_INP -j REJECT --reject-with icmp-host-prohibited
    iptables -A ISKVM_FWI ! -s 172.11.1.0/24 -j DROP
    iptables -A ISKVM_FWI -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # deny accessing local network
    for net in $BLOCK_NET ; do
        iptables -A ISKVM_FWI -d $net -j REJECT --reject-with icmp-host-prohibited
    done
    # avoid being zombie
    for port in $BLOCK_PORT ; do
        iptables -A ISKVM_FWI -p udp -m udp --dport $port -j REJECT --reject-with icmp-port-unreachable
        iptables -A ISKVM_FWI -p tcp -m tcp --dport $port -j REJECT --reject-with icmp-port-unreachable
    done
    iptables -A ISKVM_FWI -m addrtype --dst-type UNICAST -j ACCEPT
    iptables -A ISKVM_FWI -j DROP
    iptables -A ISKVM_FWO -j ACCEPT
    iptables -A ISKVM_FWB -j DROP
    iptables -A ISKVM_OUT -j ACCEPT

    iptables -I INPUT -j ISKVM_WEB
    iptables -I INPUT -i $WAN_IF -j ISKVM_INP
    iptables -I INPUT -i $LAN_IF -j ISKVM_INP
    iptables -I FORWARD -i $WAN_IF -j ISKVM_FWI
    iptables -A FORWARD -o $WAN_IF -j ISKVM_FWO
    iptables -I FORWARD -i $LAN_IF -j ISKVM_FWB
    iptables -A FORWARD -o $LAN_IF -j ISKVM_FWO
    iptables -A OUTPUT -o $LAN_IF -j ISKVM_OUT
    iptables -A OUTPUT -o $WAN_IF -j ISKVM_OUT

    # nat table, out
    iptables -t nat -N ISKVM_INET
    iptables -t nat -F ISKVM_INET
    # iptables -t nat -A ISKVM_INET -i $WAN_IF ! -o $WAN_IF -j MASQUERADE
    iptables -t nat -A ISKVM_INET ! -s 172.11.1.0/24 -j RETURN
    for net in $BLOCK_NET ; do
        iptables -t nat -A ISKVM_INET -d $net -j ACCEPT
    done
    iptables -t nat -A ISKVM_INET -d 172.11.1.0/24 -j ACCEPT
    iptables -t nat -A ISKVM_INET -j MASQUERADE
    iptables -t nat -I POSTROUTING -j ISKVM_INET

    # nat table, forward host ports to VM's
    iptables -t nat -N ISKVM_FWD
    block
    iptables -t nat -A PREROUTING -m addrtype --dst-type LOCAL -j ISKVM_FWD

    patch_legacy >/dev/null 2>&1
}

unpatch_legacy(){
    iptables-legacy -D FORWARD -i $WAN_IF -j ISKVM_FWI
    iptables-legacy -D FORWARD -o $WAN_IF -j ISKVM_FWO
    iptables-legacy -F ISKVM_FWI
    iptables-legacy -X ISKVM_FWI
    iptables-legacy -F ISKVM_FWO
    iptables-legacy -X ISKVM_FWO
    return 0
}

stop(){
    local chain
    iptables -t nat -D PREROUTING -m addrtype --dst-type LOCAL -j ISKVM_FWD
    iptables -t nat -D POSTROUTING -j ISKVM_INET
    iptables -D INPUT -j ISKVM_WEB
    iptables -D INPUT -i $WAN_IF -j ISKVM_INP
    iptables -D INPUT -i $LAN_IF -j ISKVM_INP
    iptables -D FORWARD -i $WAN_IF -j ISKVM_FWI
    iptables -D FORWARD -o $WAN_IF -j ISKVM_FWO
    iptables -D FORWARD -i $LAN_IF -j ISKVM_FWB
    iptables -D FORWARD -o $LAN_IF -j ISKVM_FWO
    iptables -D OUTPUT -o $LAN_IF -j ISKVM_OUT
    iptables -D OUTPUT -o $WAN_IF -j ISKVM_OUT

    for chain in ISKVM_INP ISKVM_FWI ISKVM_FWO ISKVM_FWB ISKVM_OUT ISKVM_WEB ; do
        iptables -F $chain
        iptables -X $chain
    done
    iptables -t nat -F ISKVM_INET
    iptables -t nat -X ISKVM_INET
    iptables -t nat -F ISKVM_FWD
    iptables -t nat -X ISKVM_FWD

    unpatch_legacy >/dev/null 2>&1
}

ACTION=${1}
shift 1
[ -z "${ACTION}" ] && ACTION=help

case ${ACTION} in
  "start" | "stop" | "block" | "unblock")
    ${ACTION}
  ;;
  *)
    echo "Unknown Action" >&2
    exit 1
  ;;
esac
