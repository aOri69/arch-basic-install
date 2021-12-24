#!/bin/bash

# Enter installed system
#arch-chroot /mnt

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
echo "LANG=ru_RU.UTF-8" >>/etc/locale.conf
echo "KEYMAP=ru" >>/etc/vconsole.conf
echo "FONT=cyr-sun16" >>/etc/vconsole.conf
# Network
echo "$HOSTNAME" >>/etc/hostname
echo "127.0.0.1 localhost" >>/etc/hosts
echo "::1       localhost" >>/etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >>/etc/hosts

askYesNo "Install amd-ucode?" true
if [ "$ANSWER" = true ]; then
    pacman -S --noconfirm amd-ucode
fi
askYesNo "Install intel-ucode?" true
if [ "$ANSWER" = true ]; then
    pacman -S --noconfirm intel-ucode
fi

# Additional packages
pacman -S --noconfirm --needed vim git bash-completion
pacman -S --noconfirm --needed efibootmgr grub grub-btrfs btrfs-progs

# Loader
read -p "....Enter EFI directory for GRUB: " EFI_DIR
grub-install --target=x86_64-efi --efi-directory=$EFI_DIR --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

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
echo "$USERNAME ALL=(ALL) ALL" >>/etc/sudoers.d/$USERNAME

# Enable services
pacman -S --noconfirm --needed networkmanager wpa_supplicant
systemctl enable NetworkManager
pacman -S --noconfirm --needed acpid acpi acpi_call
systemctl enable acpid
#systemctl enable iwd
#systemctl enable systemd-networkd
#systemctl enable systemd-resolved
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

function askYesNo {
    QUESTION=$1
    DEFAULT=$2
    if [ "$DEFAULT" = true ]; then
        OPTIONS="[Y/n]"
        DEFAULT="y"
    else
        OPTIONS="[y/N]"
        DEFAULT="n"
    fi
    read -p "$QUESTION $OPTIONS " -n 1 -s -r INPUT
    INPUT=${INPUT:-${DEFAULT}}
    echo ${INPUT}
    if [[ "$INPUT" =~ ^[yY]$ ]]; then
        ANSWER=true
    else
        ANSWER=false
    fi
}
