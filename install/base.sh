#!/bin/bash

ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
hwclock --systohc
# English
sed -i '177s/.//' /etc/locale.gen
# Russian
sed -i '403s/.//' /etc/locale.gen
locale-gen

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
echo root:password | chpasswd

useradd -m asokolov
echo asokolov:password | chpasswd
#usermod -aG libvirt asokolov

# Install packages
pacman -S --needed - < package_list.txt

echo "asokolov ALL=(ALL) ALL" >> /etc/sudoers.d/asokolov