#!/bin/bash

#ls /usr/share/kbd/keymaps/**/*.map.gz
loadkeys ru
setfont cyr-sun16
#ls /sys/firmware/efi/efivars
timedatectl set-ntp true


#gdisk /dev/sda
#n/ENTER/+512M/ef00
#n/ENTER/ENTER/ENTER

#mkfs.vfat /dev/sda1
#mkfs.btrfs /dev/sda2

read -p "....Enter DEV partition to mount as ROOT: " ROOT_PARTITION
# Create BTRFS subvolumes + mount directories
mount $ROOT_PARTITION /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@opt
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@var
#btrfs subvolume create /mnt/var_log
#btrfs subvolume create /mnt/var_cache
btrfs subvolume create /mnt/@swap
sleep 1
umount /mnt
sleep 1
echo "....BTRFS Subvolumes created"
# Mount BTRFS subvolumes
o_btrfs=defaults,noatime,ssd,discard=async,compress=lzo,space_cache=v2
mount -o $o_btrfs,subvol=@ $ROOT_PARTITION /mnt
#mkdir -p /mnt/{boot,home,var/{cache,log},opt,srv,tmp,.snapshots,swap}
#mkdir -p /mnt/{boot,home,var,opt,srv,tmp,.snapshots,swap}
mkdir -p /mnt/{efi,home,var,opt,srv,tmp,.snapshots,swap}
mount -o $o_btrfs,subvol=@home $ROOT_PARTITION /mnt/home
mount -o $o_btrfs,subvol=@snapshots $ROOT_PARTITION /mnt/.snapshots
mount -o $o_btrfs,subvol=@tmp $ROOT_PARTITION /mnt/tmp
mount -o $o_btrfs,subvol=@opt $ROOT_PARTITION /mnt/opt
mount -o $o_btrfs,subvol=@srv $ROOT_PARTITION /mnt/srv
mount -o $o_btrfs,subvol=@var $ROOT_PARTITION /mnt/var
mount -o defaults,noatime,discard=async,ssd,subvol=@swap $ROOT_PARTITION /mnt/swap
#mount -o $o_btrfs,subvol=var_log /dev/sda2 /mnt/var/log
#mount -o $o_btrfs,subvol=var_cache /dev/sda2 /mnt/var/cache
read -p "....Enter BOOT partition to mount as BOOT: " BOOT_PARTITION
# Mount EFI partition
mount $BOOT_PARTITION /mnt/efi

# Install the base system plus a few packages
pacstrap /mnt base linux linux-firmware

# Mountpoints make persistent
echo "....Generating FSTAB"
genfstab -U /mnt >> /mnt/etc/fstab
echo "....FSTAB file generated"
chmod +x arch_install2.sh
chmod +x arch_install3.sh
cp arch_install2.sh /mnt
cp arch_install3.sh /mnt
echo "....Scripts copied to /mnt"
arch-chroot /mnt
