#!/bin/sh

[ -f /tmp/.istoreos_offline -a "$1" != "force" ] && exit 0

if virsh domstate istoreos | grep -q running ; then
    virsh snapshot-revert istoreos --current --running # --force
    # sync time with NTP
    sshpass -p password ssh root@192.168.100.1 /etc/init.d/sysntpd restart
    touch /tmp/.istoreos_lastrevert
fi
