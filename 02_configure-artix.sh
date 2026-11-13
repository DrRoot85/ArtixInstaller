#!/usr/bin/env bash
set -Eeuo pipefail

echo "=================================================="
echo " Starting Artix Configuration (Stage 2 in Chroot)"
echo "=================================================="

# 1. Timezone & Locale
ln -sf /usr/share/zoneinfo/Asia/Riyadh /etc/localtime
hwclock --systohc

sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# 2. Hostname & Hosts
echo "P50" > /etc/hostname
cat <<EOF> /etc/hosts
127.0.0.1    localhost
::1          localhost
127.0.1.1    P50.localdomain P50
EOF

# 3. Passwords & User Setup
echo "Set root password:"
passwd

echo "Creating user DrRoot..."
useradd -m -G wheel -s /bin/bash DrRoot
echo "Set password for DrRoot:"
passwd DrRoot

mkdir -p /etc/sudoers.d
chmod 755 /etc/sudoers.d
echo "DrRoot ALL=(ALL) ALL" > /etc/sudoers.d/DrRoot
chmod 0440 /etc/sudoers.d/DrRoot

# 4. Enable Artix Arch Repositories (multilib & extra)
pacman -S --noconfirm artix-archlinux-support
cat <<EOF>> /etc/pacman.conf

[extra]
Include = /etc/pacman.d/mirrorlist-arch

[multilib]
Include = /etc/pacman.d/mirrorlist-arch
EOF

pacman -Syu --noconfirm

# 5. Install Full Toolchain, Desktop Infrastructure, Audio, and Archive Utils
pacman -S --noconfirm \
  linux-headers btrfs-progs cryptsetup networkmanager networkmanager-openrc network-manager-applet \
  openssh openssh-openrc sudo neovim vim git firewalld firewalld-openrc reflector acpid acpid-openrc \
  cronie cronie-openrc grub elogind dbus dbus-openrc polkit xdg-user-dirs efibootmgr intel-ucode \
  pipewire pipewire-openrc pipewire-audio pipewire-alsa pipewire-pulse pipewire-pulse-openrc pipewire-jack \
  wireplumber wireplumber-openrc alsa-utils sof-firmware bluez bluez-utils bluez-openrc \
  xorg-apps xorg-drivers xorg xclip brightnessctl udisks2 udiskie udisks2-lvm2 udisks2-btrfs pavucontrol \
  man-db man-pages texinfo nerd-fonts kitty go rustup \
  7zip unrar zip unzip p7zip tar gzip bzip2 xz zstd lz4 lzop cpio pigz pbzip2 pixz unar atool file \
  opencl-nvidia-580xx lib32-opencl-nvidia-580xx 

# 6. Detect RAM for Information & Adjustments
TOTAL_RAM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
echo "Detected system RAM: ~${TOTAL_RAM_GB} GB"

# --- INSERT HERE (Before mkinitcpio / GRUB configuration) ---

# Configure encrypted ephemeral swap via crypttab
SWAP_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
echo "swap UUID=${SWAP_UUID} /dev/urandom swap=yes,cipher=aes-xts-plain64,size=256" >> /etc/crypttab

# Update fstab to use the mapped swap device instead of raw partition
sed -i 's|/dev/nvme0n1p2|/dev/mapper/swap|g' /etc/fstab

# Enable dmcrypt service for OpenRC

# --- END OF INSERTION ---


# 8. Configure OpenRC Services
rc-update add NetworkManager default
rc-update add bluetoothd default
rc-update add openssh default
rc-update add firewalld default
rc-update add acpid default
rc-update add cronie default
rc-update add dbus default
rc-update add pipewire default
rc-update add wireplumber default
rc-update add dmcrypt default

# Firewall setup
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload

# Weekly TRIM cron job
echo "@weekly root fstrim -av" > /etc/cron.d/fstrim
chmod 644 /etc/cron.d/fstrim


# 9. Configure mkinitcpio (Btrfs, Encryption, USB, NVIDIA)
sed -i 's/^MODULES=(.*)/MODULES=(btrfs usbhid atkbd nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=(.*)/HOOKS=(base udev autodetect modconf kms keyboard keymap block encrypt filesystems)/' /etc/mkinitcpio.conf

mkinitcpio -P

# 10. Configure GRUB Bootloader with LUKS UUID
ROOT_PART_UUID=$(blkid -s UUID -o value /dev/nvme0n1p3)

cat <<EOF>> /etc/default/grub
GRUB_ENABLE_CRYPTODISK=y
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet zswap.enabled=1 cryptdevice=UUID=${ROOT_PART_UUID}:main root=/dev/mapper/main"
EOF

grub-install --recheck /dev/nvme0n1
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Unblock radio devices before exit
rfkill unblock all || true

echo "Configuration complete! You can now exit and reboot."
