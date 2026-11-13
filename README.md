# Artix Linux Installation Suite - ThinkPad P50

A robust, fully scripted automated installation framework for Artix Linux with OpenRC tailored specifically for the Lenovo ThinkPad P50 (Intel CPU, NVIDIA Quadro M1000M 4GB, NVMe SSD, 32GB RAM).

## Features
- **Strict UEFI Verification**: Prevents legacy boot failures.
- **LUKS2 Encryption**: Fully secures the root filesystem partition.
- **Btrfs Subvolumes**: Tailored layout (`@`, `@home`, `@snapshots`, `@log`, `@cache`) with optimized mount flags (`noatime,compress=zstd:3,discard=async`).
- **Nvidia Quadro Support**: Installs `nvidia-580xx-dkms` with configured kernel modules and modeset flags.
- **OpenRC-native services**: Clean management of network, sound, firewall, and session daemons without `systemd`.
- **Comprehensive Compression Suite**: Full command-line archive support (`7z`, `tar`, `zstd`, `rar`, `zip`, etc.).

## Quick Start
1. Boot from the Artix Linux live ISO.
2. Clone or copy this repository to the live environment.
3. Execute the first script:
   ```bash
   sudo ./install-artix.sh
