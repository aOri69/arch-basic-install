#!/bin/bash

sudo reflector -c Russia -a 6 --sort rate --save /etc/pacman.d/mirrorlist
sudo pacman -S xorg sddm plasma kde-applications firefox
sudo systemctl enable sddm