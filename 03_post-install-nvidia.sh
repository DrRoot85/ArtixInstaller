#!/usr/bin/env bash
set -Eeuo pipefail

# NVIDIA Quadro M1000M (Pascal) — 580xx legacy DKMS branch.
# AUR-only on Artix stable. Build as DrRoot, install as root.


sudo pacman -S --needed --noconfirm base-devel dkms linux-headers git

WORKDIR="$HOME/nvidia-build"
mkdir -p "$WORKDIR" && cd "$WORKDIR"

# --- NVIDIA 580xx: prefer Artix world repo, fall back to AUR ---
install_nvidia_pkg() {
    local pkg="$1"
    if pacman -Si "$pkg" &>/dev/null; then
        echo "Installing $pkg from Artix repos..."
        sudo pacman -S --needed --noconfirm "$pkg"
    else
        echo "$pkg not in repos — building from AUR..."
        [[ -d "$pkg" ]] || git clone "https://aur.archlinux.org/${pkg}.git"
        ( cd "$pkg" && makepkg -si --noconfirm )
    fi
}

sudo pacman -S --needed --noconfirm base-devel dkms linux-headers git

for pkg in nvidia-580xx-dkms nvidia-580xx-utils nvidia-580xx-settings; do
    install_nvidia_pkg "$pkg"
done


# Blacklist nouveau
echo "blacklist nouveau" | sudo tee /etc/modprobe.d/blacklist-nouveau.conf
echo "options nouveau modeset=0" | sudo tee -a /etc/modprobe.d/blacklist-nouveau.conf

# Kernel modules + modeset
echo "nvidia" | sudo tee /etc/modules-load.d/nvidia.conf
echo "nvidia_modeset" | sudo tee -a /etc/modules-load.d/nvidia.conf
echo "nvidia_uvm" | sudo tee -a /etc/modules-load.d/nvidia.conf
echo "nvidia_drm" | sudo tee -a /etc/modules-load.d/nvidia.conf

# Add modules to initramfs now that they exist
sudo sed -i 's/^MODULES=.*/MODULES=(btrfs usbhid atkbd nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sudo mkinitcpio -P

# modeset kernel arg
sudo sed -i 's|^\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)"|\1 nvidia-drm.modeset=1"|' /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "NVIDIA installed. Reboot."
