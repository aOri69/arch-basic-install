#!/bin/bash

pacman -S --noconfirm open-vm-tools
systemctl enable vmtoolsd

pacman -S --noconfirm xorg xf86-video-vmware pipewire pipewire-pulse pipewire-jack pipewire-alsa xfce4 xfce4-pulseaudio-plugin firefox htop
pacman -S --noconfirm lightdm lightdm-gtk-greeter
systemctl enable lightdm

# AUR helper
git clone https://aur.archlinux.org/paru
cd paru
makepkg -si
cd..

rm -rf paru

# ZRAM
paru -S zramd
sudo vim /etc/default/zramd
systemctl enable --now zramd

# Timeshift btrfs
paru -S timeshift timeshift-autosnap