#!/bin/bash

# Timezone
INST_TZ=/usr/share/zoneinfo/Europe/Moscow
# Host name
read -p "....Enter hostname of the machine: " INST_HOST

# Kernel variant
PS3='Please select the kernel: '
options=("linux" "linux-lts" "linux-zen" "linux-hardened")
select opt in "${options[@]}"; do
    INST_LINVAR=$opt
    break
done

# Target disk
PS3='Please select the disk to install: '
#(lsblk -d | tail -n+2 | awk '{print $1" "$4}')
#$(lsblk -d | tail -n+2 | cut -d" " -f1)
disks=($(ls -d /dev/disk/by-id/* | grep -v part))
select opt in "${disks[@]}"; do
    #DISK=/dev/$opt
    DISK=/dev/disk/by-id/$ortp
    break
done

# Mountpoint
#INST_MNT=$(mktemp -d)
INST_MNT="/mnt"

# Format and Partition
# Clear the partition table:
sgdisk --zap-all $DISK
# Create EFI system partition (for use now or in the future):
sgdisk -n1:1M:+512M -t1:EF00 $DISK
# Create main partition:
sgdisk -n2:0:0 $DISK

# cryptsetup mapper
# This naming scheme is taken from Debian installer
boot_partuuid=$(blkid -s PARTUUID -o value $DISK-part2)
boot_mapper_name=cryptroot-luks1-partuuid-$boot_partuuid
boot_mapper_path=/dev/mapper/$boot_mapper_name

# Format and open LUKS container
cryptsetup luksFormat --type luks1 $DISK-part2
cryptsetup open $DISK-part2 $boot_mapper_name

# Format the LUKS container as Btrfs
mkfs.btrfs $boot_mapper_path
mount $boot_mapper_path $INST_MNT

# Create subvolumes
# The idea is to separate persistent data from root file system rollbacks.
# System is installed to snapshot 0.
cd $INST_MNT

btrfs subvolume create @
mkdir @/0
btrfs subvolume create @/0/snapshot

for i in {home,root,srv,usr,usr/local,swap,var}; do
    btrfs subvolume create @$i
done

# exclude these dirs under /var from system snapshot
for i in {tmp,spool,log}; do
    btrfs subvolume create @var/$i
done

# Mount subvolumes
cd ~
umount $INST_MNT
mount $boot_mapper_path $INST_MNT -o subvol=/@/0/snapshot,compress-force=zstd,noatime,space_cache=v2

mkdir -p $INST_MNT/{.snapshots,home,root,srv,tmp,usr/local,swap}

mkdir -p $INST_MNT/var/{tmp,spool,log}
mount $boot_mapper_path $INST_MNT/.snapshots/ -o subvol=@,compress-force=zstd,noatime,space_cache=v2

# mount subvolumes
# separate /{home,root,srv,swap,usr/local} from root filesystem
for i in {home,root,srv,swap,usr/local}; do
    mount $boot_mapper_path $INST_MNT/$i -o subvol=@$i,compress-force=zstd,noatime,space_cache=v2
done
# separate /var/{tmp,spool,log} from root filesystem
for i in {tmp,spool,log}; do
    mount $boot_mapper_path $INST_MNT/var/$i -o subvol=@var/$i,compress-force=zstd,noatime,space_cache=v2
done
#Disable Copy-on-Write
for i in {swap,}; do
    chattr +C $INST_MNT/$i
done

# Format and mount EFI partition
mkfs.vfat -n EFI $DISK-part1
mkdir -p $INST_MNT/boot/efi
mount $DISK-part1 $INST_MNT/boot/efi

# Packages
# Only essential packages given here
pacstrap $INST_MNT base vim mandoc grub cryptsetup btrfs-progs snapper snap-pac grub grub-btrfs
chmod 750 $INST_MNT/root
chmod 1777 $INST_MNT/var/tmp/
# Install kernel
pacstrap $INST_MNT $INST_LINVAR
# If your computer has hardware that requires firmware to run:
pacstrap $INST_MNT linux-firmware
# If you boot your computer with EFI:
pacstrap $INST_MNT dosfstools efibootmgr
# Microcode:
pacstrap $INST_MNT amd-ucode
pacstrap $INST_MNT intel-ucode

# System Configuration
# First, generate fstab
genfstab -U $INST_MNT >>$INST_MNT/etc/fstab
# Remove hard-coded system subvolume. If not removed, system will ignore btrfs default-id setting, which is used by snapper when rolling back.
sed -i 's|,subvolid=258,subvol=/@/0/snapshot,subvol=@/0/snapshot||g' $INST_MNT/etc/fstab
# Create LUKS key for initramfs. Without this, you will need to enter the password twice: once in GRUB, once in initramfs.
mkdir -p $INST_MNT/lukskey
dd bs=512 count=8 if=/dev/urandom of=$INST_MNT/lukskey/crypto_keyfile.bin
chmod 600 $INST_MNT/lukskey/crypto_keyfile.bin
cryptsetup luksAddKey $DISK-part2 $INST_MNT/lukskey/crypto_keyfile.bin
chmod 700 $INST_MNT/lukskey
# Configure initramfs
cryptkey=/lukskey/crypto_keyfile.bin
mv $INST_MNT/etc/mkinitcpio.conf $INST_MNT/etc/mkinitcpio.conf.original
tee $INST_MNT/etc/mkinitcpio.conf <<EOF
BINARIES=(/usr/bin/btrfs)
FILES=($cryptkey)
HOOKS=(base udev autodetect modconf block encrypt filesystems keyboard fsck grub-btrfs-overlayfs)
EOF
# Edit /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >>$INST_MNT/etc/default/grub
echo "GRUB_CMDLINE_LINUX=\"cryptdevice=PARTUUID=$boot_partuuid:$boot_mapper_name root=$boot_mapper_path cryptkey=rootfs:$cryptkey\"" >>$INST_MNT/etc/default/grub
# Optional: Create swapfile. Adjust the file size if needed.
touch $INST_MNT/swap/swapfile
truncate -s 0 $INST_MNT/swap/swapfile
chattr +C $INST_MNT/swap/swapfile
btrfs property set $INST_MNT/swap/swapfile compression none
dd if=/dev/zero of=$INST_MNT/swap/swapfile bs=1M count=8192 status=progress
chmod 700 $INST_MNT/swap
chmod 600 $INST_MNT/swap/swapfile
mkswap $INST_MNT/swap/swapfile
echo /swap/swapfile none swap defaults 0 0 >>$INST_MNT/etc/fstab
# Host name:
echo $INST_HOST >$INST_MNT/etc/hostname
# Timezone:
ln -sf $INST_TZ $INST_MNT/etc/localtime
hwclock --systohc
# Locale:
echo "en_US.UTF-8 UTF-8" >>$INST_MNT/etc/locale.gen
echo "LANG=en_US.UTF-8" >>$INST_MNT/etc/locale.conf
# Other locales should be added after reboot.
# Chroot:
arch-chroot $INST_MNT /usr/bin/env DISK=$DISK \
    INST_UUID=$INST_UUID bash --login
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
exit
mount | grep "$INST_MNT/" | tac | cut -d' ' -f3 | xargs -i{} umount -lf {}
umount $INST_MNT
cryptsetup close $boot_mapper_name
reboot
