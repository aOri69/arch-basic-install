#!/bin/bash

# Apply locales:
locale-gen
#Enable networking:
systemctl enable systemd-networkd systemd-resolved
#Set root password:
passwd
#Generate initramfs:
mkinitcpio -P
#Enable btrfs service
systemctl enable grub-btrfs.path
#Enable snapper
umount /.snapshots/
rmdir /.snapshots/
snapper --no-dbus -c root create-config /
rmdir /.snapshots/
mkdir /.snapshots/
mount /.snapshots/
snapper --no-dbus -c home create-config /home/
systemctl enable /lib/systemd/system/snapper-*
#Optionally add a normal user, use --btrfs-subvolume-home:
#useradd -s /bin/bash -U -G wheel,video -m --btrfs-subvolume-home asokolov
#snapper --no-dbus -c myuser create-config /home/myuser

#GRUB installation
#EFI
#grub-install
#Some motherboards does not properly recognize GRUB boot entry, to ensure that your computer will boot, also install GRUB to fallback location with:
grub-install --removable
# Generate GRUB menu
grub-mkconfig -o /boot/grub/grub.cfg

# Finish Installation