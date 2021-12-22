#!/bin/bash

#ls /usr/share/kbd/keymaps/**/*.map.gz
loadkeys ru
setfont cyr-sun16
#ls /sys/firmware/efi/efivars
timedatectl set-ntp true


#gdisk /dev/sda
#n/ENTER/+512M/ef00
#n/ENTER/ENTER/ENTER

mkfs.vfat /dev/sda1
mkfs.btrfs /dev/sda2

# Create BTRFS subvolumes + mount directories
mount /dev/sda2 /mnt
btrfs subvolume create /mnt/root
btrfs subvolume create /mnt/home
btrfs subvolume create /mnt/snapshots
btrfs subvolume create /mnt/tmp
btrfs subvolume create /mnt/opt
btrfs subvolume create /mnt/srv
btrfs subvolume create /mnt/var
#btrfs subvolume create /mnt/var_log
#btrfs subvolume create /mnt/var_cache
btrfs subvolume create /mnt/swap
umount /mnt

# Mount BTRFS subvolumes
o_btrfs=defaults,noatime,ssd,discard=async,compress=lzo,space_cache=v2
mount -o $o_btrfs,subvol=root /dev/sda2 /mnt
#mkdir -p /mnt/{boot,home,var/{cache,log},opt,srv,tmp,.snapshots,swap}
mkdir -p /mnt/{boot,home,var,opt,srv,tmp,.snapshots,swap}
mount -o $o_btrfs,subvol=root /dev/sda2 /mnt
mount -o $o_btrfs,subvol=home /dev/sda2 /mnt/home
mount -o $o_btrfs,subvol=snapshots /dev/sda2 /mnt/.snapshots
mount -o $o_btrfs,subvol=tmp /dev/sda2 /mnt/tmp
mount -o $o_btrfs,subvol=opt /dev/sda2 /mnt/opt
mount -o $o_btrfs,subvol=srv /dev/sda2 /mnt/srv
mount -o $o_btrfs,subvol=var /dev/sda2 /mnt/var
#mount -o $o_btrfs,subvol=var_log /dev/sda2 /mnt/var/log
#mount -o $o_btrfs,subvol=var_cache /dev/sda2 /mnt/var/cache
mount -o defaults,noatime,discard=async,ssd,subvol=swap /dev/sda2 /mnt/swap

# Mount EFI partition
mount /dev/sda1 /mnt/boot

# Install the base system plus a few packages
pacstrap /mnt base base-devel linux linux-headers btrfs-progs

# Mountpoints make persistent
genfstab -U /mnt >> /mnt/etc/fstab

# Enter installed system
arch-chroot /mnt

# Generating Locales
# English
#sed -i '177s/.//' /etc/locale.gen
# Russian
sed -i '403s/.//' /etc/locale.gen
locale-gen

# Timezone and time
ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
timedatectl set-ntp true
hwclock --systohc


read -p "....Enter hostname of the machine: " HOSTNAME
# Base settings
echo "LANG=ru_RU.UTF-8" >> /etc/locale.conf
echo "KEYMAP=ru" >> /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf
# Network
echo "$HOSTNAME" >> /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Users and passwords
# Root
echo "....Changing root password: "
passwd
# echo root:230989 | chpasswd
# User
read -p "....Enter new username to add: " USERNAME
useradd -m $USERNAME
echo "....Changing $USERNAME password: "
passwd $USERNAME
#echo asokolov:230989 | chpasswd
echo "....Adding $USERNAME to sudo users: "
# Sudo
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers.d/$USERNAME

# Additional packages
pacman -S amd-ucode iwd acpid acpi acpi_call

# Enable services
systemctl enable iwd
systemctl enable acpid
systemctl enable systemd-networkd
systemctl enable systemd-resolved
#------------------------------------------------------------------------------------------------
# systemd-boot config
# bootctl install
# Root UUID using this comand blkid -s PARTUUID -o value /dev/sdxY
# /boot/loader/entries/arch.conf
# ---
# title Arch Linux Encrypted
# linux /vmlinuz-linux
# initrd /intel-ucode.img
# initrd /initramfs-linux.img
# options cryptdevice=UUID=<cryptdevice-UUID>:root root=UUID=<root-UUID> rootflags=subvol=@ rw
# ---
# Set default bootloader entry
# ---
# /boot/loader/loader.conf
# ---
# default		arch
# timeout   4
# editor    0
# ---
# Bootloader PACMAN hook
#/etc/pacman.d/hooks/systemd-boot.hook
#[Trigger]
#Type = Package
#Operation = Upgrade
#Target = systemd
#
#[Action]
#Description = Updating systemd-boot...
#When = PostTransaction
#Exec = /usr/bin/bootctl update
#------------------------------------------------------------------------------------------------
# systemd-networkd config
# Wired network with DHCP
#/etc/systemd/network/20-wired.network
#[Match]
#Name=enp1s0
#
#[Network]
#DHCP=yes
#
#[DHCP]
#RouteMetric=10
#
# Wireless network with DHCP
#/etc/systemd/network/25-wireless.network
#[Match]
#Name=wlp2s0
#
#[Network]
#DHCP=yes
#
#[DHCP]
#RouteMetric=20
#------------------------------------------------------------------------------------------------
