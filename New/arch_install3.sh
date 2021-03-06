#!/bin/bash

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

askYesNo "Are you under VMWare virtual machine?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed open-vm-tools
    sudo systemctl enable vmtoolsd
fi

askYesNo "Printing support?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed cups
    sudo systemctl enable cups
fi

askYesNo "Bluetooth support?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed bluez bluez-utils
    sudo systemctl enable bluetooth
fi

askYesNo "Additional IP utils + dialog?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed inetutils dnsutils dialog
fi

askYesNo "Additional filesystems support?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed mtools dosfstools gvfs gvfs-smb nfs-utils ntfs-3g
fi

askYesNo "Zero-configuration networking support?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed avahi nss-mdns
    sudo systemctl enable avahi-daemon
    sudo systemctl disable systemd-resolved
fi

# Virtualization
askYesNo "Virtualization support?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed virt-manager qemu qemu-arch-extra bridge-utils dnsmasq edk2-ovmf vde2 openbsd-netcat
    sudo systemctl enable libvirtd
    sudo usermod -aG libvirt $(whoami)
fi

# Fonts
askYesNo "Additional fonts?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed terminus-font ttf-dejavu ttf-liberation ttf-font-awesome
fi

# Pipewire support
askYesNo "Install PIPEWIRE?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed pipewire pipewire-pulse pipewire-jack pipewire-alsa pavucontrol
fi

# KDE
askYesNo "KDE?" false
if [ "$ANSWER" = true ]; then
    sudo pacman -S --noconfirm --needed xorg xf86-video-vmware
    sudo pacman -S --noconfirm --needed sddm plasma plasma-wayland-session kde-applications packagekit-qt5
    sudo systemctl enable sddm
fi
# AUR helper
askYesNo "Install PARU AUR helper?" false
if [ "$ANSWER" = true ]; then

    git clone https://aur.archlinux.org/paru
    cd paru
    makepkg -si
    cd..
fi
# ZRAM
askYesNo "Install ZRAM?" false
if [ "$ANSWER" = true ]; then

    paru -S zramd
    sudo vim /etc/default/zramd
    systemctl enable --now zramd
fi
# Timeshift btrfs
#paru -S timeshift timeshift-autosnap
