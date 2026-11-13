#!/usr/bin/env bash
set -Eeuo pipefail

# ---- RustDesk (official OpenRC package) ----
sudo pacman -S --needed --noconfirm rustdesk rustdesk-openrc || {
    echo "rustdesk-openrc unavailable — check 'pacman -Ss rustdesk'."
}
sudo rc-update add rustdesk default 2>/dev/null || true

# ---- AnyDesk: no OpenRC package. Manual init script only if you want it. ----
echo "AnyDesk skipped (no OpenRC package). Install manually + write init script if required."

# ---- Fingerprint: Validity 138a:0090 on P50 ----
if lsusb | grep -qi '138a:0090'; then
    echo "Validity 138a:0090 detected."

    sudo pacman -S --needed --noconfirm base-devel git fprintd

    WDIR="$HOME/fp-build"; mkdir -p "$WDIR"; cd "$WDIR"

    # python-validity (AUR)
    [[ -d python-validity ]] || git clone https://aur.archlinux.org/python-validity.git
    ( cd python-validity && makepkg -si --noconfirm )

    # libfprint vfs0090 fork (AUR: libfprint-vfs0090-git or community fork)
    [[ -d libfprint-vfs0090-git ]] || git clone https://aur.archlinux.org/libfprint-vfs0090-git.git
    ( cd libfprint-vfs0090-git && makepkg -si --noconfirm )

    sudo systemctl disable fprintd 2>/dev/null || true
    sudo rc-update add fprintd default 2>/dev/null || true

    echo
    echo "Sensor paired in Windows before? If yes, enter the Windows SID"
    echo "(wmic useraccount get name,sid). If no, press Enter to skip."
    read -rp "Windows SID: " SID
    if [[ -n "$SID" ]]; then
        validity-sensors-tools.initializer --sid "$SID" || \
            echo "Initializer failed — run 'validity-sensors-tools.initializer' manually."
    else
        echo "Skipped SID mapping. Enrollment will fail until a Windows pairing exists."
    fi

    fprintd-enroll || echo "Enrollment failed — see README troubleshooting."
else
    echo "No Validity 138a:0090 sensor found. Skipping fingerprint."
fi

echo "Done. PAM integration is NOT modified automatically (per spec)."
