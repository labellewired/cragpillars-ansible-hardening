# =============================================================================
# CragPillars - Bastion Kickstart
# =============================================================================
#
# Description:
#   Automated installation of the CentOS Stream 10 Bastion server.
#   Configures the base system, networking, administrator account, and
#   required packages for the Ansible control node.
#
# Hostname: bastion.crag.internal
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
network --bootproto=static --device=ens33 --ip=10.10.1.10 --netmask=255.255.255.0 --gateway=10.10.1.2 --nameserver=10.10.1.40,9.9.9.9 --onboot=on

## Administration network interface
network --bootproto=static --device=ens36 --ip=10.10.10.10 --netmask=255.255.255.0 --onboot=on

## Hostname
network --hostname="bastion.crag.internal"

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
dnf install epel-release -y
dnf update -y
dnf install ansible-core -y

# Disable IPv6 system-wide
grubby --update-kernel=ALL --args="ipv6.disable=1"
%end