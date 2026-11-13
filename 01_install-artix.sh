#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/tmp/artix-install-stage1.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo " Artix Linux Installation — Stage 1 (live ISO)"
echo "=================================================="

pacman -S parted gptfdisk

# --- Cleanup trap: never leave mounts or LUKS open on failure ---
cleanup() {
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "!! Stage 1 failed (rc=$rc). Cleaning up mounts and LUKS..."
        umount -R /mnt 2>/dev/null || true
        cryptsetup close main 2>/dev/null || true
        swapoff /dev/mapper/swap 2>/dev/null || true
        cryptsetup close swap 2>/dev/null || true
    fi
}
trap cleanup EXIT

# --- 1. UEFI check ---
if [[ ! -d /sys/firmware/efi ]]; then
    echo "Error: UEFI boot mode not detected. This installer requires UEFI." >&2
    exit 1
fi

# --- 2. Network check (basestrap needs repos) ---
if ! ping -c1 -W3 archlinux.org &>/dev/null; then
    echo "Error: no network connectivity. Connect and re-run." >&2
    exit 1
fi

# --- 3. Target disk ---
TARGET_DISK="/dev/nvme0n1"
echo "Target disk: ${TARGET_DISK}"
[[ -b "${TARGET_DISK}" ]] || { echo "Error: ${TARGET_DISK} not found." >&2; exit 1; }

if mount | grep -q "^${TARGET_DISK}"; then
    echo "Error: ${TARGET_DISK} or a partition is mounted." >&2
    exit 1
fi
if swapon --show=NAME --noheadings 2>/dev/null | grep -q "${TARGET_DISK}"; then
    echo "Error: swap active on ${TARGET_DISK}. Run 'swapoff -a' first." >&2
    exit 1
fi

echo "WARNING: ALL data on ${TARGET_DISK} will be erased."
read -rp "Type 'ERASE' to confirm: " confirmation
[[ "$confirmation" == "ERASE" ]] || { echo "Aborted."; exit 1; }

# --- 4. Time sync (best effort; ntpd may not exist on ISO) ---
if rc-service --exists ntpd 2>/dev/null; then
    rc-service ntpd start || true
elif command -v chronyd &>/dev/null; then
    chronyd -q 'pool pool.ntp.org iburst' || true
fi

# --- 5. Partitioning ---
echo "Partitioning ${TARGET_DISK}..."
wipefs -a "${TARGET_DISK}"
sgdisk -Z "${TARGET_DISK}"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI"  "${TARGET_DISK}"
sgdisk -n 2:0:+8G -t 2:8200 -c 2:"SWAP" "${TARGET_DISK}"
sgdisk -n 3:0:0   -t 3:8300 -c 3:"ROOT" "${TARGET_DISK}"
partprobe "${TARGET_DISK}"
udevadm settle
sleep 1

EFI_PART="${TARGET_DISK}p1"
SWAP_PART="${TARGET_DISK}p2"
ROOT_PART="${TARGET_DISK}p3"
for p in "${EFI_PART}" "${SWAP_PART}" "${ROOT_PART}"; do
    [[ -b "$p" ]] || { echo "Error: $p did not appear." >&2; exit 1; }
done

# --- 6. Encrypted ephemeral swap (plain dm-crypt, random key per boot) ---
echo "Setting up encrypted swap..."
cryptsetup open --type plain --key-file /dev/urandom "${SWAP_PART}" swap
mkswap -L SWAP /dev/mapper/swap
swapon /dev/mapper/swap

SWAP_UUID="$(blkid -s UUID -o value "${SWAP_PART}")"

# --- 7. EFI ---
echo "Formatting EFI..."
mkfs.fat -F32 "${EFI_PART}"
fatlabel "${EFI_PART}" ESP

# --- 8. LUKS2 root (PBKDF2 for GRUB compat) ---
echo "Configuring LUKS2 on ${ROOT_PART}..."
cryptsetup luksFormat --type luks2 --pbkdf pbkdf2 --iter-time 2000 "${ROOT_PART}"
cryptsetup luksOpen "${ROOT_PART}" main

ROOT_UUID="$(blkid -s UUID -o value "${ROOT_PART}")"

# --- 9. Btrfs ---
mkfs.btrfs -L MAIN /dev/mapper/main
mount /dev/mapper/main /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@cache
umount /mnt

# --- 10. Mount subvolumes ---
OPTS="noatime,compress=zstd:3,discard=async"
mkdir -p /mnt/{home,.snapshots,var/log,var/cache,boot}
mount -o "${OPTS}",subvol=@          /dev/mapper/main /mnt
mount -o "${OPTS}",subvol=@home      /dev/mapper/main /mnt/home
mount -o "${OPTS}",subvol=@snapshots /dev/mapper/main /mnt/.snapshots
mount -o "${OPTS}",subvol=@log       /dev/mapper/main /mnt/var/log
mount -o "${OPTS}",subvol=@cache     /dev/mapper/main /mnt/var/cache
mount "${EFI_PART}" /mnt/boot

# --- 11. Base system (NO NVIDIA, NO AUR-only pkgs) ---
echo "Installing base system..."
basestrap /mnt \
    base base-devel openrc elogind-openrc \
    linux linux-headers linux-firmware linux-firmware-nvidia \
    dkms btrfs-progs dosfstools util-linux cryptsetup cryptsetup-openrc \
    sudo vim intel-ucode \
    nvidia-580xx-dkms  nvidia-580xx-utils \
    nvidia-utils-openrc nvidia-580xx-settings \
    libxnvctrl-580xx lib32-nvidia-580xx-utils 
 

 # --- 12. crypttab for OpenRC? No — OpenRC uses /etc/conf.d/dmcrypt.
#         We write the dmcrypt config here so Stage 2 only enables the service.
cat > /mnt/etc/conf.d/dmcrypt <<EOF
# Ephemeral encrypted swap — random key each boot
swap=cryptswap
source='UUID=${SWAP_UUID}'
options='--type plain --key-file /dev/urandom'
EOF
chmod 600 /mnt/etc/conf.d/dmcrypt

# --- 13. fstab (references /dev/mapper/cryptswap for swap) ---
fstabgen -U /mnt >> /mnt/etc/fstab
# Replace the raw-swap line with the dmcrypt device
sed -i "s|^UUID=${SWAP_UUID}[[:space:]].*swap.*$|/dev/mapper/cryptswap none swap defaults 0 0|" /mnt/etc/fstab

# --- 14. Hand off to Stage 2 ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "${SCRIPT_DIR}/configure-artix.sh" /mnt/root/configure-artix.sh
chmod +x /mnt/root/configure-artix.sh
cp "$LOG_FILE" /mnt/var/log/artix-install-stage1.log

echo "Stage 1 complete. Entering chroot..."
artix-chroot /mnt /root/configure-artix.sh

# --- 15. Post-chroot teardown ---
trap - EXIT
umount -R /mnt
cryptsetup close main
swapoff /dev/mapper/cryptswap 2>/dev/null || true
cryptsetup close cryptswap 2>/dev/null || true
echo "Done. Remove the ISO and reboot."
