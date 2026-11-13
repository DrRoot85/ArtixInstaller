#!/usr/bin/env bash
set -Eeuo pipefail

echo "=================================================="
echo " Stage 3: Installing Remote Access & Hardware Tools"
echo "=================================================="

# Ensure yay or paru is available for AUR packages
if ! command -v yay &> /dev/null && ! command -v paru &> /dev/null; then
    echo "Installing yay AUR helper..."
    cd /tmp
    git clone [https://aur.archlinux.org/yay.git](https://aur.archlinux.org/yay.git)
    git clone [https://aur.archlinux.org/paru.git](https://aur.archlinux.org/paru.git)
    cd yay-bin
    makepkg -si --noconfirm
    cd ~
fi

HELPER="yay"
if command -v paru &> /dev/null; then
    HELPER="paru"
fi

# 1. Install AnyDesk and RustDesk from AUR
echo "Installing AnyDesk and RustDesk..."
$HELPER -S --noconfirm anydesk-bin rustdesk-bin

# 2. Fingerprint Reader Diagnostics & Tools (Validity VFS7500 / 138a:0090)
echo "Checking USB devices for fingerprint reader..."
lsusb | grep -i "138a:" || echo "No Validity fingerprint sensor detected via lsusb."

echo "Installing fingerprint daemon and utility helpers..."
$HELPER -S --noconfirm fprintd libfprint-vfs009x-git validity-sensors-tools-git || echo "Optional fingerprint packages skipped or unavailable."

echo "=================================================="
echo " All installation stages completed successfully!"
echo " You can now start AnyDesk/RustDesk services or start dwm."
echo "=================================================="
