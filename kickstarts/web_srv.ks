# =============================================================================
# CragPillars - Web Kickstart
# =============================================================================
#
# Description:
#   Automated installation of the CentOS Stream 10 Web server.
#   Configures the base system, networking, and administrator account.
#   Prepares the server for subsequent configuration through Ansible.
#
# Hostname: web.crag.internal
# Project:  cragpillars-ansible-hardening
#
# =============================================================================


## Choosing mode (graphical|text|cmdline [--non-interactive])
text

# repo --name="AppStream" --baseurl=file:///run/install/sources/mount-000-cdrom/AppStream

## Use network installation
# url --mirrorlist="https://mirrors.fedoraproject.org/mirrorlist?repo=fedora-36&arch=x86_64"
# url --mirrorlist="https://mirrors.centos.org/mirrorlist?repo=centos-stream-10&arch=aarch64"
# url --mirrorlist="https://mirrors.centos.org/mirrorlist?path=/10-stream/BaseOS/x86_64/iso/CentOS-Stream-10-latest-x86_64-dvd1.iso&redirect=1&protocol=https"

## Use CDROM installation media
cdrom

## Initial Setup Agent on first boot
firstboot --disable

## System language
lang en_CA.UTF-8

## Keyboard layout
keyboard --xlayouts="us(intl)"
# keyboard --xlayouts="us"

## System timezone
timezone America/Toronto --utc

## Public network interface
network --bootproto=static --device=ens33 --ip=10.10.1.20 --netmask=255.255.255.0 --gateway=10.10.1.2 --nameserver=10.10.1.40,9.9.9.9 --onboot=on

## Administration interface is configured by the installer-side %post script.

## Hostname
network --hostname="web.crag.internal"

## Root password
rootpw --lock

## Administrator account
user --name="crag_admin" --groups="wheel" --gecos="CragPillars Administrator" --iscrypted --password="REPLACE_WITH_PASSWORD_HASH"

## Firewall configuration
firewall --enabled --ssh

## SELinux
selinux --enforcing

## Partition layout
## Disk type
#ignoredisk --only-use="nvme0n1"
ignoredisk --only-use="sda"
## -----
clearpart --all --initlabel --disklabel="gpt"
autopart --nohome

## Packages
%packages
@^minimal-environment
python3
nano
open-vm-tools
%end

## Services
services --enabled="sshd.service,vmtoolsd.service"

## Reboot the system after installation.
reboot

## Enable kdump
%addon com_redhat_kdump --enable --reserve-mb='auto'
%end

%pre
%end

%post --erroronfail
dnf update -y
dnf install -y epel-release
dnf update -y

# Disable IPv6 system-wide
grubby --update-kernel=ALL --args="ipv6.disable=1"
%end

# Discover the administration NIC and configure its persistent name.
# This installer-side script writes into the installed system.
%post --nochroot --erroronfail --log=/tmp/crag-admin-network.log
set -eu

# Exactly two Ethernet NICs are expected; ens33 is the public NIC.
admin_device=""
count=0

for device_path in /sys/class/net/*; do
    device="${device_path##*/}"

    [ "$device" = "ens33" ] && continue
    [ -f "$device_path/type" ] || continue
    [ "$(cat "$device_path/type")" = "1" ] || continue
    [ -e "$device_path/device" ] || continue

    count=$((count + 1))
    admin_device="$device"
done

if [ "$count" -ne 1 ]; then
    echo "Expected exactly one administration Ethernet NIC; found $count" >&2
    exit 1
fi

pci_path="$(udevadm info --query=property --path="/sys/class/net/$admin_device" | sed -n 's/^ID_PATH=//p')"

if [ -z "$pci_path" ]; then
    echo "Could not discover PCI path for $admin_device" >&2
    exit 1
fi

sysroot=/mnt/sysroot

if [ ! -d "$sysroot/etc" ]; then
    echo "Installed system not found" >&2
    exit 1
fi

mkdir -p "$sysroot/etc/systemd/network"
mkdir -p "$sysroot/etc/NetworkManager/system-connections"

cat > "$sysroot/etc/systemd/network/10-crag-admin.link" <<EOF
[Match]
Path=$pci_path

[Link]
NamePolicy=
Name=cragadmin0
EOF

cat > "$sysroot/etc/NetworkManager/system-connections/cragadmin0.nmconnection" <<EOF
[connection]
id=cragadmin0
type=ethernet
interface-name=cragadmin0
autoconnect=true

[ethernet]

[ipv4]
method=manual
address1=10.10.10.20/24
never-default=true

[ipv6]
method=disabled
EOF

chmod 600 "$sysroot/etc/NetworkManager/system-connections/cragadmin0.nmconnection"

# Ensure generated configuration files receive appropriate SELinux labels.
touch "$sysroot/.autorelabel"

echo "Administration NIC: $admin_device ($pci_path) -> cragadmin0 (10.10.10.20/24)"
%end
