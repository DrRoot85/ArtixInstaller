#!/usr/bin/env bash
# recovery.sh — mount an existing Artix install and enter chroot
# Safe to run repeatedly. Never destroys data.
set -Eeuo pipefail

LOG_FILE="/tmp/artix-recovery.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=================================================="
echo " Artix Linux — Recovery / Resume into chroot"
echo "=================================================="

TARGET_DISK="/dev/nvme0n1"
EFI_PART="${TARGET_DISK}p1"
SWAP_PART="${TARGET_DISK}p2"
ROOT_PART="${TARGET_DISK}p3"
OPTS="noatime,compress=zstd:3,discard=async"

# --- Sanity: partitions must exist ---
for p in "${EFI_PART}" "${ROOT_PART}"; do
    if [[ ! -b "$p" ]]; then
        echo "Error: $p not found. Nothing to recover." >&2
        exit 1
    fi
done

# --- 1. Open LUKS root if not already open ---
if cryptsetup status main &>/dev/null; then
    echo ">> LUKS 'main' already open."
elif cryptsetup isLuks "${ROOT_PART}" 2>/dev/null; then
    echo ">> Opening LUKS on ${ROOT_PART}..."
    cryptsetup luksOpen "${ROOT_PART}" main
else
    echo "Error: ${ROOT_PART} is not LUKS — refusing to proceed." >&2
    exit 1
fi

# --- 2. Mount subvolumes (idempotent) ---
mkdir -p /mnt/{home,.snapshots,var/log,var/cache,boot}

if ! mountpoint -q /mnt; then
    echo ">> Mounting @ → /mnt"
    mount -o "${OPTS}",subvol=@ /dev/mapper/main /mnt
else
    echo ">> /mnt already mounted."
fi

mountpoint -q /mnt/home       || { echo ">> Mounting @home";       mount -o "${OPTS}",subvol=@home      /dev/mapper/main /mnt/home; }
mountpoint -q /mnt/.snapshots || { echo ">> Mounting @snapshots"; mount -o "${OPTS}",subvol=@snapshots /dev/mapper/main /mnt/.snapshots; }
mountpoint -q /mnt/var/log    || { echo ">> Mounting @log";       mount -o "${OPTS}",subvol=@log       /dev/mapper/main /mnt/var/log; }
mountpoint -q /mnt/var/cache  || { echo ">> Mounting @cache";     mount -o "${OPTS}",subvol=@cache     /dev/mapper/main /mnt/var/cache; }
mountpoint -q /mnt/boot       || { echo ">> Mounting ESP";        mount "${EFI_PART}" /mnt/boot; }

# --- 3. Stage 2 script present? ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/configure-artix.sh" ]]; then
    echo ">> Refreshing /mnt/root/configure-artix.sh from ${SCRIPT_DIR}"
    cp "${SCRIPT_DIR}/configure-artix.sh" /mnt/root/configure-artix.sh
    chmod +x /mnt/root/configure-artix.sh
elif [[ ! -x /mnt/root/configure-artix.sh ]]; then
    echo "!! Warning: no configure-artix.sh found — chroot will start with a plain shell." >&2
fi

# --- 4. Enter chroot ---
echo
echo ">> Ready. Entering chroot at /mnt"
echo "   - Finish manually, e.g.:  /root/configure-artix.sh"
echo "   - Exit shell to return to live ISO."
echo
artix-chroot /mnt /bin/bash
