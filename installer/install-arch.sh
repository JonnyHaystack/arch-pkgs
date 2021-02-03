#!/usr/bin/env bash

# Harden script against failure.
set -o pipefail


# My Arch package repositories.
META_REPO_URL="https://gitlab.com/JonnyHaystack/arch-repo/-/raw/master/x86_64"
AURTO_REPO_URL="http://aurpkgs.haylett.lan"

# Set up logging.
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

# Set temporary keyboard layout for prompts.
loadkeys dvorak

# Installer dependencies
pacman -Sy dialog

# Partitioning {{{

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
DEVICE=$(dialog --stdout --menu "Select installation disk" 0 0 0 \
  ${devicelist}) || exit 1
clear

# Partition disks.
sleep 1
# Partition disks.
while true; do
    fdisk "$DEVICE"
    read -p "Have you finished partitioning disks? [Y/n] " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) ;;
        * ) echo "Please answer yes or no.";;
    esac
done

# Confirm ESP partition.
esplist=$(fdisk -l "$DEVICE" | grep "EFI System" | awk '{print $1,$5}')
ESP=$(dialog --stdout --menu "Select EFI System Partition" 0 0 0 ${esplist}) || exit 1
clear
: ${ESP:?"ESP must be set"}

# Get EXT partitions.
extlist=$(fdisk -l "$DEVICE" | grep "Linux filesystem" | awk '{print $1,$5}')

# Confirm root partition.
ROOT_PART=$(dialog --stdout --menu "Select root partition" 0 0 0 ${extlist}) || exit 1
clear
: ${ROOT_PART:?"Root partition must be set"}

# Confirm home partition.
HOME_PART=$(dialog --stdout --menu \
  "Select home partition (Cancel if not using separate home partition)" 0 0 0 ${extlist})
clear

# Check which partitions to format.
if dialog --stdout --defaultno --yesno \
    "Format ${ESP}?\nWARNING: THIS WILL DESTROY ALL DATA ON THE PARTITION" 0 0; then
  FORMAT_ESP=1
fi
clear

if dialog --stdout --defaultno --yesno \
    "Format ${ROOT_PART}?\nWARNING: THIS WILL DESTROY ALL DATA ON THE PARTITION" 0 0; then
  FORMAT_ROOT=1
fi
clear

if [ -n "${HOME_PART}" ]; then
  if dialog --stdout --defaultno --yesno \
      "Format ${HOME_PART}?\nWARNING: THIS WILL DESTROY ALL DATA ON THE PARTITION" 0 0; then
    FORMAT_HOME=1
  fi
  clear
fi

# Format partitions.
if [ -n "${FORMAT_ESP}" ]; then
  wipefs "${ESP}"
  mkfs.vfat -F32 "${ESP}"
fi
if [ -n "${FORMAT_ROOT}" ]; then
  wipefs "${ROOT_PART}"
  mkfs.ext4 "${ROOT_PART}"
fi
if [ -n "${FORMAT_HOME}" ]; then
  wipefs "${HOME_PART}"
  mkfs.ext4 "${HOME_PART}"
fi

# Mount partitions.
mount "${ROOT_PART}" /mnt
mkdir -p /mnt/boot
mount "${ESP}" /mnt/boot
if [ -n "${HOME_PART}" ]; then
  mkdir -p /mnt/home
  mount "${HOME_PART}" /mnt/home
fi

# }}}

# Installation of system {{{

# Enable NTP.
timedatectl set-ntp true

# Add my repo for the installer ISO.
cat >>/etc/pacman.conf <<EOF
[meta]
SigLevel = Optional TrustAll
Server = $META_REPO_URL

[aurto]
SigLevel = Optional TrustAll
Server = $AURTO_REPO_URL
EOF

# Install base packages.
pacstrap /mnt haystack-base
genfstab -t PARTUUID /mnt > /mnt/etc/fstab

# Add my repo for the installation.
if ! grep aurto /mnt/etc/pacman.conf; then
cat >>/mnt/etc/pacman.conf <<EOF
[meta]
SigLevel = Optional TrustAll
Server = $META_REPO_URL

[aurto]
SigLevel = Optional TrustAll
Server = $AURTO_REPO_URL
EOF
fi

# Install bootloader.
arch-chroot /mnt bootctl install

cat <<EOF > /mnt/boot/loader/loader.conf
default arch
timeout 5
EOF

cat <<EOF > /mnt/boot/loader/entries/arch.conf
title    Arch Linux
linux    /vmlinuz-linux
initrd   /initramfs-linux.img
options  root=PARTUUID=$(blkid -s PARTUUID -o value "${ROOT_PART}") rw
EOF

# Set timezone.
arch-chroot /mnt hwclock --systohc

# }}}

# Set hostname and set up users and passwords {{{

# Hostname.
HOSTNAME=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${HOSTNAME:?"hostname cannot be empty"}

# Username.
USER=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${USER:?"user cannot be empty"}

# Password.
PASSWORD=$(dialog --stdout --passwordbox "Enter admin user's password" 0 0) || exit 1
clear
: ${PASSWORD:?"password cannot be empty"}
PASSWORD2=$(dialog --stdout --passwordbox "Enter admin user's password again" 0 0) || exit 1
clear
[[ "$PASSWORD" == "$PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

# Root password.
ROOT_PASSWORD=$(dialog --stdout --passwordbox "Enter root password" 0 0) || exit 1
clear
: ${ROOT_PASSWORD:?"password cannot be empty"}
ROOT_PASSWORD2=$(dialog --stdout --passwordbox "Enter root password again" 0 0) || exit 1
clear
[[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD2" ]] || ( echo "Passwords did not match"; exit 1; )

# Set hostname
echo "${HOSTNAME}" > /mnt/etc/hostname

# Create admin user.
arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G wheel,lp "$USER"
arch-chroot /mnt chsh -s /usr/bin/zsh

# Change passwords.
echo "$USER:$PASSWORD" | chpasswd --root /mnt
echo "root:$ROOT_PASSWORD" | chpasswd --root /mnt

# }}}
