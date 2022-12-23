# iStoreOS KVM
iStoreOS running on libvirt qemu-kvm, mainly for demo purpose

# Prerequisite
Run `grep -wEq 'vmx|svm|lm' /proc/cpuinfo && echo OK` on host to check if the host supports KVM.

# Host
Install *libvirt* and *qemu-kvm* (Debian or Ubuntu):
```
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils sshpass
sudo systemctl is-active libvirtd | grep active || echo "libvirtd not running, is it correctly installed?"
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER
exit
```
Relogin to get new group working

# VM
1. Prepare iStoreOS disk image
```
wget https://fw.koolcenter.com/iStoreOS/x86_64/istoreos-21.02.3-2022121613-x86-64-squashfs-combined.img.gz
gunzip -k istoreos-21.02.3-2022121613-x86-64-squashfs-combined.img.gz
qemu-img convert -f raw -O qcow2 istoreos-21.02.3-2022121613-x86-64-squashfs-combined.img istoreos.qcow2
# maybe resize
# qemu-img resize istoreos.qcow2 20G
sudo chmod libvirt-qemu:libvirt-qemu istoreos.qcow2
```

2. Update the path of `istoreos.qcow2` in `istoreos.xml`
```
sed -i "s# file='.*/istoreos.qcow2'# file='`pwd`/istoreos.qcow2'#" istoreos.xml
```

3. Add iStoreOS VM to libvirt
```
virsh define istoreos.xml
```

4. Setup isolated virtual network and start VM
```
sudo ./boot.sh init
```

5. Setup iStoreOS
Access iStoreOS by LUCI ( http://192.168.100.1/ ) or VNC ( 127.0.0.1:5901 , password `isosdemo` ),

set WAN interface to static ip, address `172.11.1.2/24`, gateway `172.11.1.1` DNS `114.114.114.114`.

6. When iStoreOS is ready for serving, create snapshot
```
virsh snapshot-create-as istoreos istoreos-running
```

7. Forward host WAN ports to VM LAN ports
```
sudo ./online.sh
```

# Auto start and schedule reverting snapshot
```
sudo crontab -e
```
Add these line ( Change `/home/istoreos/kvm` to your actual path ):
```
@reboot sh -c 'cd /home/istoreos/kvm; ./boot.sh'
*/10 * * * * sh -c 'cd /home/istoreos/kvm; ./reset.sh'
```
Save and exit.


# Snapshot management
Revert to lastest snapshot
```
sudo ./reset.sh force
```

Delete snapshot
```
virsh snapshot-delete istoreos --current
```

List snapshot
```
virsh snapshot-list istoreos
```

# Maintenance
Offline and revert lastest snapshot
```
sudo ./offline.sh
sudo ./reset.sh force
```
Now you can manage virtual machines without interruption.

When all done, then create new snapshot
```
# virsh snapshot-delete istoreos --current
virsh snapshot-create-as istoreos istoreos-running
```

Online
```
sudo ./online.sh
```
