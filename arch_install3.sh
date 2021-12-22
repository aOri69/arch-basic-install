#!/bin/bash

sudo pacman -S --noconfirm open-vm-tools
sudo systemctl enable vmtoolsd

sudo pacman -S --noconfirm xorg xf86-video-vmware pipewire pipewire-pulse pipewire-jack pipewire-alsa xfce4 xfce4-pulseaudio-plugin firefox htop
sudo pacman -S --noconfirm lightdm lightdm-gtk-greeter
sudo systemctl enable lightdm

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