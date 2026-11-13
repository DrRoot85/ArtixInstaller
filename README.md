# Artix Linux — ThinkPad P50 (OpenRC, LUKS2, Btrfs)

## Files
| File | Runs where | As |
|---|---|---|
| 01_install-artix.sh | live ISO | root |
| 02_configure-artix.sh | chroot | root |
| 03_post-install-nvidia.sh | first boot | DrRoot |
| 04_post-install-remote-fingerprint.sh | first boot | DrRoot |

## Disk layout (`/dev/nvme0n1`)
| Part | Size | Use | FS |
|---|---|---|---|
| p1 | 1 GiB | EFI | FAT32 |
| p2 | 8 GiB | swap (plain dm-crypt, random key/boot) | swap |
| p3 | rest | root (LUKS2 → Btrfs) | btrfs |

## Encryption
- Root: LUKS2, PBKDF2 (GRUB-compatible).
- Swap: plain dm-crypt, `/dev/urandom` key each boot, configured via
  `/etc/conf.d/dmcrypt` (`swap=cryptswap`). OpenRC `dmcrypt` reads this file,
  **not** `/etc/crypttab`.
- fstab references `/dev/mapper/cryptswap`.

## Boot order of stages
1. Boot Artix live ISO (UEFI).
2. `bash install-artix.sh` → prompts ERASE → partitions → basestrap → chroot.
3. `configure-artix.sh` runs inside chroot.
4. Reboot. Log in as DrRoot.
5. `bash post-install-nvidia.sh`, reboot.
6. `bash post-install-remote-fingerprint.sh`.

## NVIDIA
Quadro M1000M = Pascal = legacy 580xx DKMS branch (AUR-only on Artix
stable). Built in Stage 3, after the base system exists, so `mkinitcpio`
never references a module that isn't there.

## Fingerprint (138a:0090)
Runtime: `python-validity` + `libfprint-vfs0090-git` (AUR) + `fprintd`.
If the sensor was paired in Windows, the Windows SID is required for
`validity-sensors-tools.initializer`. If it was never paired, enrollment
will fail — pair in Windows first, then re-run Stage 4.
PAM is not modified automatically.

## Remote access
- RustDesk: official `rustdesk` + `rustdesk-openrc`.
- AnyDesk: no OpenRC package; skipped. Add a manual init script if needed.

## Recovery (from live ISO)
```bash
cryptsetup luksOpen /dev/nvme0n1p3 main
mount -o subvol=@ /dev/mapper/main /mnt
mount -o subvol=@home /dev/mapper/main /mnt/home
mount /dev/nvme0n1p1 /mnt/boot
artix-chroot /mnt
