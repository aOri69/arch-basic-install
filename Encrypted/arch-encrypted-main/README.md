# Example for installing Arch Linux with encrypted root (and /boot), btrfs, UEFI on an SSD

## Preamble (skip if you just want to get started)

Coming from Gentoo and knowing that the Arch wiki is an excellent source of well documented Linux information, I was confident that I would be able to quickly set up an Arch linux machine with full root and /boot encryption and UEFI boot. Well, let's just say, I got a thorough reality check ;-).

In case I or anyone else reading this ever wants/needs to do this (again), I decided to write down the process how I finally got this to work - after a hard day of bug hunting. This is by no means a criticism of the documentation over at the Arch Wiki. On the contrary, their [Installation Guide](https://wiki.archlinux.org/title/Installation_guide) and the [Guide to encrypting an entire system](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system) is extremely thorough and I learned a lot about the depths of the UEFI/Linux boot process. However, the thoroughness comes at the price that it was not always easy for me to know which parts of the documentation were relevant for my intended use case. Hence, this guide essentially collects all the steps needed for my use case from the various wiki documentation pages in one place.

## Pre-installation

I am assuming the boot disk is `/dev/sda` here. Replace 'sda' with your intended boot disk.

* [Download](https://archlinux.org/download/) an installation image 
* Copy it to a USB stick: 
  ```bash
  cat path/to/archlinux-version-x86_64.iso > /dev/sda
  ``` 
  **! make sure `dev/sda` is the right device because all data on it will be deleted**
* Boot the USB stick
* Update the system clock
  ```bash
  timedatectl set-ntp true
  ```
* Partition the boot disk 
  ```bash
  fdisk /dev/sda
  ```
  1. If the disk already has a working EFI system partition, leave that one untouched. Otherwise create a `+300M` partition at the beginning of the disk. Make sure to set the type to "EFI System Partition" (`t 1` in fdisk).
  2. Fill the rest of the space with a single partition (the root partition). 
* Encrypt and Format the parition(s):
  1. Do **not** encrypt the EFI partition. If you created a new EFI System Parition, format it with **mkfs.fat** (not mkfs.vfat):
     ```bash
     mkfs.fat /dev/sda1
     ```
  2. Encrypt and unlock the root partition: 
     ```bash
     cryptsetup luksFormat --type luks1 /dev/sda2
     cryptsetup open /dev/sda2 cryptroot
     ``` 
  3. Format the unlocked luks device:
     ```bash
     mkfs.btrfs -L root /dev/mapper/cryptroot
     ```
* Create btrfs subvolumes and mount them
  1. Mount the btrfs volume:
     ```bash
     mount /dev/mapper/cryptroot /mnt
     ```
  2. Create top-level btrfs subvolumes (in order to be able to use snapshots later on):
     ```bash
     btrfs subvolume create /mnt/@          # to be mounted at /
     btrfs subvolume create /mnt/@home      # to be mounted at /home
     btrfs subvolume create /mnt/@snapshots # to be mounted at /.snapshots
     btrfs subvolume create /mnt/@var_log   # to be mounted at /var/log
     ```
  3. Unmount the btrfs volume: 
     ```bash
     umount /mnt
     ``` 
  4. Mount the top level subvolumes
     ```bash
     mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
     mkdir /mnt/home
     mount -o compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
     mkdir /mnt/.snapshots
     mount -o compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
     mkdir -p /mnt/var/log
     mount -o compress=zstd,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
     ```
  5. Create subvolumes for paths to be excluded from snapshots (these excludes are the ones recommended on [the arch wiki](https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#Btrfs_subvolumes_with_swap), add more as needed):
     ```bash
     mkdir -p /mnt/var/cache/pacman/
     btrfs subvolume create /mnt/var/cache/pacman/pkg
     btrfs subvolume create /mnt/var/abs
     btrfs subvolume create /mnt/var/tmp
     btrfs subvolume create /mnt/srv
     ```
  6. Mount the EFI System Partition (esp):
     ```bash
     mkdir /mnt/esp
     mount /dev/sda1 /mnt/esp
     ```

## Install base system packages

* Install essential packages
  ```bash
  pacstrap /mnt base linux linux-firmware btrfs-progs
  ```
* Install highly recommended packages
  ```bash
  pacstrap /mnt man-db man-pages bash-completion nano # replace "nano" with your favorite command line text editor
  ```

## Configure the System

* Create `fstab`
  ```bash
  genfstab -U /mnt >> /mnt/etc/fstab
  ```
  *NB: genfstab checks what is mounted on `/mnt` and writes that into fstab so make sure that everything is mounted correctly at this point (which it should be if you followed the instructions so far)*
* Chroot into the freshly installed system
  ```bash
  arch-chroot /mnt
  ```
* Set the time zone
  ```bash
  ln -sf /usr/share/zoneinfo/<Region>/<City> /etc/localtime

  ```
* Localization
  1. Edit `/etc/locale.gen` and uncomment `en_US.UTF-8 UTF-8` and other needed locales. Generate the locales by running:
     ```bash
     locale-gen
     ```
  2. Create `/etc/locale.conf` and set the LANG variable
     ```bash
     echo "LANG=en_US.UTF-8" > /etc/locale.conf
     ```
  3. If you set the keyboard layout, make the changes persistent in vconsole.conf: 
     ```bash
     echo "KEYMAP=de-latin1" >> /etc/vconsole.conf
     ```
* Network
     ```bash
     echo "myhostname" > /etc/hostname
     echo '127.0.0.1	localhost
     ::1		localhost
     127.0.1.1	myhostname.localdomain	myhostname' > /etc/hosts
     ```
     Now enable DHCP for the first wired network adapter:
     ```bash
     echo '[Match]
     Name=eno1
     
     [Network]
     DHCP=yes
     ' > /etc/systemd/network/20-wired.network
     systemctl enable systemd-networkd systemd-resolved
     ```
* Set the root password
  ```bash
  passwd
  ```
* Install the appropriate microcode for your processor:
  ```bash
  pacman -S amd-ucode # or 'intel-ucode' for Intel Processors
  ```
* Create a new initramfs
  1. Create a keyfile for GRUB to be able to unlock the root partition
     ```bash
     dd bs=512 count=4 if=/dev/random of=/crypto_keyfile.bin iflag=fullblock
     chmod 600 /crypto_keyfile.bin
     chmod 600 /boot/initramfs-linux*
     cryptsetup luksAddKey /dev/sda2 /crypto_keyfile.bin
     ```
  2. Edit mkinitcpio.conf and add the keyfile and needed hooks for unlocking the root partition
     ```bash
     nano /etc/mkinitcpio.conf
     ```
     add the following parameters to the respective places in mkinitcpio.conf:
     ```bash
     BINARIES=(/usr/bin/btrfs)
     FILES=(/crypto_keyfile.bin)
     HOOKS=(base udev keyboard autodetect keymap consolefont modconf block encrypt filesystems fsck)
     ```
  3. Crete the initramfs:
     ```bash
     mkinitcpio -P
     ```
* Configure and install the boot loader

  1. Install the grub efi binaries to the efi partition
  ```bash
  grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=GRUB
  ```
  2. Edit `/etc/default/grub` and change the GRUB_CMDLINE_LINUX parameter:
     ```bash
     uuid=$( blkid -o value /dev/sda2 | head -n 1 )
     sed -i -e "s|\(GRUB_CMDLINE_LINUX=\"\).*\"|\1cryptdevice=UUID=$uuid:cryptroot: crypto=:::: rd.luks.options=discard\"|g" /etc/default/grub
     ```
     now open the file in an editor to uncomment
     ```bash
     GRUB_ENABLE_CRYPTODISK=y
     ```
     while you are there, check that GRUB_CMDLINE_LINUX reads something like:
     ```bash
     GRUB_CMDLINE_LINUX="cryptdevice=UUID=12345678-9abcd-ef10-111213141516:cryptroot:enable-discards crypto=:::: rd.luks.options=discard"
     ```
     *NB: I tried without the `rd.luks.options=discard` kernel parameter, but [when I checked](https://askubuntu.com/questions/162476/how-to-check-if-trim-is-working-for-an-encrypted-volume), fstrim did not work on my ssd until I added it. I am not sure if the cryptdevice option `enable-discards` is necessary together with the kernel parameter `rd.luks.options=discard`, but since fstrim works now, I did not bother to remove it.*

     Bonus: add `rootflags=rw,noatime,ssd,space_cache,subvolid=256,subvol=/@` to `GRUB_CMDLINE_LINUX=` in order to set the `noatime` option for the root filesystem, which improves performance quite a lot for btrfs and reduces the write operations to the ssd. While you are at it, you can also edit `/etc/fstab` to replace `relatime` with `noatime` for all btrfs filesystems.
  3. Generate the grub config file
     ```bash
     grub-mkconfig -o /boot/grub/grub.cfg
     ```

## Reboot
exit the chroot environment with `ctrl-d` and reboot
```bash
reboot
```
Don't forget to remove the installation usb stick as the system boots.

Now you should be welcomed first with a prompt for the password to decrypt the root partition. Then you should see the grub menu and finally a command line terminal where you should be able to log in as root (no other users were created yet).

## Mainenance
There are a number of maintenance tasks that should be performed regularly. Namely, we want to trim the ssd, balance the btrfs filesystem and update the arch system.

### Trim
It is important to regularly trim the ssd in order to let the disk know which blocks have been deleted and can be considered free. Otherwise the disk will become very slow. Follow the [instructions for regular trim on the arch wiki](https://wiki.archlinux.org/title/Solid_state_drive#Periodic_TRIM):
1. Install util-linux
   ```bash
   pacman -S util-linux
   ```
2. Start and enable `fstrim.timer`
   ```bash
   systemctl start fstrim.timer
   systemctl enable fstrim.timer
   ```

### Btrfs balance
Btrfs treats the data on the disk in chunks. Over time, inefficiently used chunks can accumulate and waste space. I created systemd units that rebalance chunks that are used less than 50% weekly and less than 85% monthly (see the [systemd](/systemd) directory in this repository).
1. Download them
   ```bash
   cd /etc/systemd/system
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/systemd/btrfs50.service"
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/systemd/btrfs85.service"
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/systemd/btrfs50.timer"
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/systemd/btrfs85.timer"
   ```
   
2. Start and enable them
   ```bash
   systemctl start btrfs50.timer btrfs85.timer
   systemctl enable btrfs50.timer btrfs85.timer
   ```

### Regular system upgrades
You should regularly upgrade your system. In case the upgrade is messed up, I create a snapshot first and then run `pacman -Syu` every night using some homemade [upgrade scripts](/scripts).
1. Subscribe to the [archwiki mailing list](https://mailman.archlinux.org/mailman/listinfo/arch-announce/) in ordder to receive important information when manual interference is needed in the upgrade process.
2. Install the upgrade scripts
   ```bash
   mkdir /root/bin && cd /root/bin
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/scripts/system-upgrade"
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/scripts/cleanup-snapshots"
   cd /etc/systemd/system
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/systemd/system-upgrade.service"
   wget "https://gitlab.com/Thawn/arch-encrypted/-/raw/main/systemd/system-upgrade.timer"
3. Start and enable them
   ```bash
   systemctl start system-upgrade.timer
   systemctl enable system-upgrade.timer
   ```

You can adjust the upgrade frequency by editing `system-upgrade.timer`. By default, the cleanup script keeps snapshots from the last 14 days. You can change this by editing the line `keep=14` in the `cleanup-snapshots` script.

### Backup your system!!!
No backup - no pity. Therefore configure and enable [backups](https://wiki.archlinux.org/title/System_backup)
I currently use the rsync-based [dirvish](https://dirvish.org/) mainly for historical reasons (because some of my data is still on `ext` filesystems). However, a system based on `btrfs send/receive` would be more powerful and faster for the btrfs filesystem.

## Migrating to a new bigger disk
While this is not exactly part of the installation process, I would like to note down here how to migrate to a new disk. Not because it is difficult, but because it is easy - actually, thanks to btrfs, it is so easy, I could not beleave it. The cool thing is, that you can do this while your system is running (no booting from usb stick needed).

I am going to assume that the original data is on `/dev/sda` and the target drive is `/dev/sdb`. **Make sure that those are correct or you might lose data!**

That bein said, we start pretty standard:

### The standard stuff pt 1: Copying the EFI partition
1. Create the efi partition and the data partition as you normally would, e.g. with fstab or parted. Make sure to set the EFI flag on the EFI partition.
2. Format the EFI partition with Fat32 
   ```bash
   mkfs.fat /dev/sdb1
   ```
3. Mount the new esp partition: 
   ```bash
   mount /dev/sdb1 /mnt/esp
   ```
4. Copy all data from the old to the new efi partition: 
   ```bash
   cp -a /esp /mnt/esp
   ```
   NB: if you followed the instructions above, `/esp` contains the efi partition. If not, replace `/esp` with wherever you mounted the efi partition.
5. Mount the new efi partition in the right place: 
   ```bash
   umount /esp && umount /mnt/esp && mount /dev/sdb1 /esp
   ```
   Not sure if this is really necessary, but it definitely does not hurt.
5. Install grub on the new efi partition
   ```bash
   grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=GRUB
   ```
   This step is important, otherwise your system will not boot (forcing you to recover using an arch installation USB stick).
6. Change the UUID for the efi partition in `/etc/fstab`
   * copy the UUID for /dev/sdb1 to /etc/fstab
   ```bash
   blkid | grep /dev/sdb1 >> /etc/fstab
   ```
   * now use your favorite editor to move the UUID to the right place.
   ```bash
   nano /etc/fstab
   ```
   
### The standard stuff pt 2: Copying the Root Encryption
1. Make a backup of your luks header 
   ```bash
   cryptsetup luksHeaderBackup /dev/sda2 --header-backup-file /mnt/backup/root_luks_header.bak
   ```
   This is extremely useful because it also baks up the uuid of the decrypted partition - no need to fiddle around with /etc/fstab if you use UUIDs (as you should). Also, no need to change the initramfs and kernel command line parameters.
2. Install the backup luks header on the new drive: 
   ```bash
   cryptsetup luksHeaderRestore /dev/sdb2 --header-backup-file /mnt/backup/daffy_root_luks_header.bak
   ```
   For some reason, I had to create a luks header first, before this worked. In case you run into the same problem, just run `cryptsetup luksFormat /dev/sdb2` and then the command above.
3. Unlock the new root partition 
   ```bash
   cryptsetup open /dev/sda2 newroot --key-file /crypto_keyfile.bin
   ```
   That way you already test whether the key file still works (the one that you already have in your initramfs).

### The magic: moving the data using btrfs
1. We can use `btrfs replace` to move all data from the old to the new drive **While your system is still running on the old drive!**
   ```bash
   btrfs replace start /dev/sda2 /dev/sdb2 /
   ```
   Depending on the amount of data, this might take a while. You can check the status with `btrfs replace status`
2. Resize the filesystem to fill up the new disk
   ```bash
   btrfs filesystem resize 1:max /
   ```
   This assumes that your device has the id `1` in btrfs. Use `btrfs device usage /` to confirm if this is true.

You are done! When I did this for the first time, I could not believe how easy it was to migrate data from one disk to the next using btrfs. You don't even need to reboot the system at all to do this! However, I recommend to reboot the system afterwards just to test that it is still booting fine. In my case, I had forgotten to install grub on the new efi partition, which caused the next boot to fail and forced me to use an USB stick to repair grub. See grub trouble shooting below.


## Troubleshooting

### Suspend to disk is not working

For that you need an encrypted swap partition, which [may be possible](https://wiki.archlinux.org/title/Dm-crypt/Swap_encryption) but you have to be careful to set it up with proper encryption to avoid making your full disk encryption obsolete.

Since I was setting up a server that will stay online most of the time, I did not bother with a swap partition.

### No bootable disk

if the boot process fails so early that the Bios doesn't even recognize the disk, then something is likely wrong with the EFI partition. In my case the culprit was that I used vFAT (`mkvs.vfat`) instead of FAT (`mkvs.fat`), which is not supported by the UEFI standard.

### Grub is not working properly

For me, getting GRUB to behave was the most troublesome step. Setting up GRUB with an encrypted /boot requires a lot of things to go right and does not tell you very verbosely at which step it fails. At the first sign of trouble (i.e. if my instructions above don't work for you), I highly recommend reading the whole [GRUB wikipage](https://wiki.archlinux.org/title/GRUB) and particularly [the troubleshooting section](https://wiki.archlinux.org/title/GRUB#Troubleshooting). In my case, I thought I would get away with just a few sections but ended up being forced to read almost the whole thing bit by bit in-between a lot of failed boot attempts ;-).
Also, the [dm-crypt system configuration wikipage](https://wiki.archlinux.org/title/Dm-crypt/System_configuration) has lots of important information, particularly the correct initramfs hooks and kernel paremeters.

Here are some issues that I came across myself
* If you entered the wrong password, grub does not ask again but drops to the `grub rescue` command line. You can recover as follows
  ```bash
  grub rescue> cryptomount <partition>
  grub rescue> insmod normal
  grub rescue> normal
  ```
  replace `<partition>` with the part that grub printed in the passwod dialog **before** the uuid (for example `hd1,gpt2`) on my system the number in hd# tends to vary between boot-ups. 
* grub drops to the `grub` command line after entering the correct password:
  
  In this case, something is likely wrong with your grub configuration. In my case, I had errors in the `cryptdevice` kernel parameter specified under `GRUB_CMDLINE_LINUX` in `/etc/default/grub`. I could see in the command line, that the filesystem was unlocked correctly, but the kernel was not loaded because it did not know which cryptdevice to mount.
* The system complains that there is no bootable disk. This likely means, that the grub header is missing. Just install grub again (assuming that `/dev/sda1` is your EFI partition and `/dev/sda2` is your root partition)
  1. Boot using an Arch installation USB stick
  2. Unlock the encrypted root partition
     ```bash
     cryptsetup open /dev/sda2 cryptroot
     ```
  3. Mount the efi and root partitions
     ```bash
     mount -o compress=zstd,subvol=@ /dev/mapper/cryptroot /mnt
     mount -o compress=zstd,subvol=@home /dev/mapper/cryptroot /mnt/home
     mount -o compress=zstd,subvol=@snapshots /dev/mapper/cryptroot /mnt/.snapshots
     mount -o compress=zstd,subvol=@var_log /dev/mapper/cryptroot /mnt/var/log
     mount /dev/sda1 /mnt/esp
     ```
  4. Chroot into the mounted system
     ```bash
     arch-chroot /mnt
     ```
  5. Install grub
     ```bash
     grub-install --target=x86_64-efi --efi-directory=esp --bootloader-id=GRUB
     ```
     
  
