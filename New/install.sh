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
DISK=""
select opt in "${disks[@]}"; do
    DISK=$opt
    break
done
# Mountpoint
# INST_MNT=$(mktemp -d)
INST_MNT="/mnt"
# Format and Partition
sgdisk --zap-all $DISK
sgdisk -n 0:0:+512MiB -t 0:ef00 -c 0:boot $DISK
sgdisk -n 0:0:0 -t 0:8300 -c 0:root $DISK
# small delay
sleep 5
BOOT_PATH=$DISK-part1
ROOT_PATH=$DISK-part2
# Format partitions
mkfs.vfat -n EFI $BOOT_PATH
mkfs.btrfs -f $ROOT_PATH
mount $ROOT_PATH $INST_MNT
# Create subvolumes
cd $INST_MNT
btrfs subvolume create @
mkdir @/0
btrfs subvolume create @/0/snapshot
for i in {home,root,srv,opt,swap,var}; do
    btrfs subvolume create @$i
done
# exclude these dirs under /var from system snapshot
for i in {tmp,spool,log,cache}; do
    btrfs subvolume create @var/$i
done
# Mount subvolumes
o_btrfs=defaults,noatime,ssd,discard=async,compress=lzo,space_cache=v2
o_btrfs_swap=defaults,noatime,ssd,discard=async
cd ~
umount $INST_MNT
mount $ROOT_PATH $INST_MNT -o subvol=/@/0/snapshot,$o_btrfs
mkdir -p $INST_MNT/{.snapshots,home,root,srv,tmp,opt,swap}
mkdir -p $INST_MNT/var/{tmp,spool,log,cache}
mount $ROOT_PATH $INST_MNT/.snapshots/ -o subvol=@,$o_btrfs
# separate /{home,root,srv,opt} from root filesystem
for i in {home,root,srv,opt}; do
    mount $ROOT_PATH $INST_MNT/$i -o subvol=@$i,$o_btrfs
done
# separate /var/{tmp,spool,log,cache} from root filesystem
for i in {tmp,spool,log,cache}; do
    mount $ROOT_PATH $INST_MNT/var/$i -o subvol=@var/$i,$o_btrfs
done
#Disable Copy-on-Write
for i in {swap,}; do
    mount $ROOT_PATH $INST_MNT/$i -o subvol=@$i,$o_btrfs_swap
    chattr +C $INST_MNT/$i
done

# Format and mount EFI partition
ESP_PATH=$INST_MNT/efi
mkdir -p $ESP_PATH
mount $BOOT_PATH $ESP_PATH
sleep 5
# Packages
pacstrap $INST_MNT base base-devel \
    $INST_LINVAR linux-firmware linux-headers \
    vim git mandoc btrfs-progs \
    dosfstools efibootmgr \
    grub grub-btrfs \
    snapper snap-pac \
    amd-ucode

# System Configuration
# First, generate fstab
genfstab -U $INST_MNT >>$INST_MNT/etc/fstab
# Remove hard-coded system subvolume. If not removed, system will ignore btrfs default-id setting, which is used by snapper when rolling back.
sed -i 's|,subvolid=258,subvol=/@/0/snapshot,subvol=@/0/snapshot||g' $INST_MNT/etc/fstab

# Configure initramfs
mv $INST_MNT/etc/mkinitcpio.conf $INST_MNT/etc/mkinitcpio.conf.original
tee $INST_MNT/etc/mkinitcpio.conf <<EOF
BINARIES=(/usr/bin/btrfs)
FILES=()
HOOKS=(base udev autodetect modconf block filesystems keyboard fsck grub-btrfs-overlayfs)
EOF

askYesNo "Create a swap file?" false
if [ "$ANSWER" = true ]; then
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
fi

cat <<EOF >$INST_MNT/root/part2.sh
#!/bin/bash

# Generating Locales
# English
sed -i '177s/.//' /etc/locale.gen
# Russian
#sed -i '403s/.//' /etc/locale.gen
locale-gen

# Timezone and time
ln -sf $INST_TZ /etc/localtime
timedatectl set-ntp true
hwclock --systohc

# Base settings
#echo "LANG=ru_RU.UTF-8" >>/etc/locale.conf
echo "LANG=en_US.UTF-8" >>/etc/locale.conf
#echo "KEYMAP=ru" >>/etc/vconsole.conf
#echo "FONT=cyr-sun16" >>/etc/vconsole.conf
# Network
echo $INST_HOST >>/etc/hostname
echo "127.0.0.1 localhost" >>/etc/hosts
echo "::1       localhost" >>/etc/hosts
echo "127.0.1.1 $INST_HOST.localdomain $INST_HOST" >>/etc/hosts

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

grub-install --target=x86_64-efi --efi-directory=$ESP_PATH --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
#Enable btrfs service
systemctl enable grub-btrfs.path

pacman -S --noconfirm --needed networkmanager wpa_supplicant
systemctl enable NetworkManager
# to leave the chroot
exit
EOF

# Chroot:
arch-chroot $INST_MNT \
    /usr/bin/env \
    DISK=$DISK \
    INST_UUID=$INST_UUID \
    ESP_PATH=$ESP_PATH \
    INST_TZ=$INST_TZ \
    INST_HOST=$INST_HOST \
    GRUB=true \
    NM=true \
    SNAPPER=$SNAPPER \
    bash --login ./root/part2.sh

rm $INST_MNT/root/part2.sh

#exit
#mount | grep "$INST_MNT/" | tac | cut -d' ' -f3 | xargs -i{} umount -lf {}
#umount $INST_MNT
