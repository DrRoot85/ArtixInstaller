#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/artix-install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo " Starting Artix Linux Installation (Stage 1)"
echo "=================================================="

# 1. Verify UEFI Boot Mode
if [ ! -d "/sys/firmware/efi" ]; then
    echo "Error: UEFI boot mode not detected. This installer requires UEFI." >&2
    exit 1
fi

# 2. Select Target Disk
DEFAULT_DISK="/nvme0n1" # Wait, standard block device path
# Let's clean up device selection path defaults
TARGET_DISK="/dev/nvme0n1"
echo "Target disk: ${TARGET_DISK}"
if [ ! -b "${TARGET_DISK}" ]; then
    echo "Error: Target disk ${TARGET_DISK} does not exist." >&2
    exit 1
fi

# Check if disk is mounted or has active swap
if mount | grep -q "${TARGET_DISK}"; then
    echo "Error: ${TARGET_DISK} or its partitions are currently mounted." >&2
    exit 1
fi

# 3. Warning & Confirmation
echo "WARNING: All data on ${TARGET_DISK} will be completely erased!"
read -p "Type 'ERASE' to confirm: " confirmation
if [ "$confirmation" != "ERASE" ]; then
    echo "Aborted by user."
    exit 1
fi

# 4. Synchronize system time
rc-service ntpd start || true

# 5. Partitioning via parted / sfdisk (EFI 1G, Swap 8G, Root Remainder)
echo "Partitioning ${TARGET_DISK}..."
wipefs -a "${TARGET_DISK}"
sgdisk -Z "${TARGET_DISK}"

sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "${TARGET_DISK}"
sgdisk -n 2:0:+8G -t 2:8200 -c 2:"SWAP" "${TARGET_DISK}"
sgdisk -n 3:0:0   -t 3:8300 -c 3:"ROOT" "${TARGET_DISK}"
partprobe "${TARGET_DISK}"

EFI_PART="${TARGET_DISK}p1"
SWAP_PART="${TARGET_DISK}p2"
ROOT_PART="${TARGET_DISK}p3"

# 6. Format and Enable Swap
echo "Setting up encrypted/ephemeral or standard swap..."
mkswap -L SWAP "${SWAP_PART}"
swapon "${SWAP_PART}"

# 7. Format EFI Partition
echo "Formatting EFI partition..."
mkfs.fat -F32 "${EFI_PART}"
fatlabel "${EFI_PART}" ESP

# 8. Set up LUKS2 Encryption
echo "Configuring LUKS2 encryption on ${ROOT_PART}..."
cryptsetup luksFormat --type luks2 "${ROOT_PART}"
cryptsetup luksOpen "${ROOT_PART}" main

# 9. Format Btrfs inside LUKS container
echo "Formatting Btrfs filesystem..."
mkfs.btrfs -L MAIN /dev/mapper/main

# 10. Create Btrfs Subvolumes
echo "Creating Btrfs subvolumes..."
mount /dev/mapper/main /mnt
cd /mnt
btrfs subvolume create @
btrfs subvolume create @home
btrfs subvolume create @snapshots
btrfs subvolume create @log
btrfs subvolume create @cache
cd -
umount /mnt

# 11. Mount Subvolumes
echo "Mounting subvolumes to /mnt..."
mkdir -p /mnt/{home,.snapshots,var/log,var/cache}

mount -o noatime,compress=zstd:3,discard=async,subvol=@ /dev/mapper/main /mnt
mount -o noatime,compress=zstd:3,discard=async,subvol=@home /dev/mapper/main /mnt/home
mount -o noatime,compress=zstd:3,discard=async,subvol=@snapshots /dev/mapper/main /mnt/.snapshots
mount -o noatime,compress=zstd:3,discard=async,subvol=@log /dev/mapper/main /mnt/var/log
mount -o noatime,compress=zstd:3,discard=async,subvol=@cache /dev/mapper/main /mnt/var/cache

# Mount EFI
mkdir -p /mnt/boot
mount "${EFI_PART}" /mnt/boot

# 12. Install Base System Packages
echo "Installing base system and hardware packages..."
basestrap /mnt base base-devel openrc elogind-openrc linux linux-firmware dkms nvidia-580xx-dkms linux-headers nvidia-580xx-utils nvidia-utils-openrc opencl-nvidia-580xx linux-firmware-nvidia nvidia-580xx-settings libxnvctrl-580xx lib32-nvidia-580xx-utils lib32-opencl-nvidia-580xx lib32-nvidia-580xx-utils vim btrfs-progs dosfstools util-linux sudo intel-ucode

# 13. Generate fstab
echo "Generating fstab..."
fstabgen -U /mnt >> /mnt/etc/fstab

# 14. Copy Stage 2 Script into Chroot
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "${SCRIPT_DIR}/configure-artix.sh" /mnt/root/configure-artix.sh
chmod +x /mnt/root/configure-artix.sh

echo "Stage 1 complete. Entering chroot for Stage 2..."
artix-chroot /mnt /root/configure-artix.sh
