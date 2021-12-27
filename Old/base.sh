#!/bin/bash

ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
# English
sed -i '177s/.//' /etc/locale.gen
# Russian
sed -i '403s/.//' /etc/locale.gen
locale-gen

# Time
timedatectl set-ntp true
hwclock --systohc

# Base settings
echo "LANG=ru_RU.UTF-8" >> /etc/locale.conf
echo "KEYMAP=ru" >> /etc/vconsole.conf
echo "FONT=cyr-sun16" >> /etc/vconsole.conf
# Network
echo "arch" >> /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 arch.localdomain arch" >> /etc/hosts
# Users and passwords
# Root
echo root:password | chpasswd
# User
useradd -m asokolov
echo asokolov:password | chpasswd

# Install packages
pacman -S --needed - < package_list.txt

# pacman -S --noconfirm xf86-video-amdgpu
# pacman -S --noconfirm nvidia nvidia-utils nvidia-settings

# Loader
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable cups.service
systemctl enable sshd
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable acpid
#systemctl enable firewalld
#systemctl enable avahi-daemon
#systemctl disable systemd-resolved

# Reflector
reflector -c Russia -a 6 --sort rate --save /etc/pacman.d/mirrorlist

# Sudo
echo "asokolov ALL=(ALL) ALL" >> /etc/sudoers.d/asokolov

# AUR helper
git clone https://aur.archlinux.org/paru
cd paru
makepkg -si
cd..

# ZRAM
paru -S zramd
sudo vim /etc/default/zramd
systemctl enable --now zramd

# Timeshift btrfs
paru -S timeshift timeshift-autosnap