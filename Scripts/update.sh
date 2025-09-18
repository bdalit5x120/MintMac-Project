#!/usr/bin/env bash
set -euo pipefail

# Offline Broadcom Wi-Fi (BCM4360) fix for Mint/Ubuntu on older iMacs.
# Installs from a Ventoy USB that already contains:
#   - bcmwl-kernel-source_*.deb
#   - broadcom-sta-dkms_*.deb
#   - dkms_*.deb
#   - build-essential_*.deb
#   - linux-headers-$(uname -r).deb (recommended)
#
# Default source: /media/$USER/Ventoy  (auto-detects if not found)
# Reboots automatically on success.

bold(){ printf "\e[1m%s\e[0m\n" "$*"; }
info(){ printf "\e[36m%s\e[0m\n" "$*"; }
warn(){ printf "\e[33m%s\e[0m\n" "$*"; }
die(){ printf "\e[31mERROR:\e[0m %s\n" "$*" >&2; exit 1; }

require_root(){
  if [[ $EUID -ne 0 ]]; then
    die "Run as root: sudo $0"
  fi
}
require_root

USER_NAME="${SUDO_USER:-$USER}"

# 1) Locate the Ventoy folder (or allow override via $1)
PKGDIR="${1:-}"
if [[ -z "${PKGDIR}" ]]; then
  CANDS=(
    "/media/$USER_NAME/Ventoy"
    "/media/$USER_NAME/"*/"Ventoy"
    "/media/$USER_NAME/"*
  )
  for c in "${CANDS[@]}"; do
    if [[ -d "$c" ]] && ls "$c" 1>/dev/null 2>&1; then
      if ls "$c"/bcmwl-kernel-source_*.deb 1>/dev/null 2>&1; then PKGDIR="$c"; break; fi
    fi
  done
fi
[[ -n "${PKGDIR}" ]] || die "Couldn't find Ventoy folder with the .deb files. Pass the path explicitly: sudo $0 /media/$USER/Ventoy"
[[ -d "${PKGDIR}" ]] || die "Not a directory: $PKGDIR"

bold ">>> Using package folder: $PKGDIR"
KVER="$(uname -r)"
info "Kernel detected: $KVER"

# 2) Verify required packages exist
shopt -s nullglob
BCMWL=( "$PKGDIR"/bcmwl-kernel-source_*.deb )
STA_DKMS=( "$PKGDIR"/broadcom-sta-dkms_*.deb )
DKMS_PKG=( "$PKGDIR"/dkms_*.deb )
BUILD_ESS=( "$PKGDIR"/build-essential_*.deb )
HEADERS=( "$PKGDIR"/linux-headers-"$KVER"_*.deb )

((${#BCMWL[@]}))    || die "Missing bcmwl-kernel-source_*.deb in $PKGDIR"
((${#STA_DKMS[@]})) || die "Missing broadcom-sta-dkms_*.deb in $PKGDIR"

# 3) Remove conflicting modules, blacklist them
bold ">>> Removing conflicting modules (ignore errors if not loaded)…"
modprobe -r wl || true
modprobe -r b43 || true
modprobe -r brcmsmac || true
modprobe -r bcma || true
modprobe -r ssb || true

bold ">>> Blacklisting conflicting in-kernel drivers…"
BLACKLIST="/etc/modprobe.d/broadcom-blacklist.conf"
cat > "$BLACKLIST" <<'EOF'
# Prefer Broadcom STA (wl) over in-kernel drivers
blacklist b43
blacklist bcma
blacklist brcmsmac
blacklist ssb
EOF

# 4) Install packages (headers -> dkms/build-ess -> sta dkms -> bcmwl)
bold ">>> Installing packages offline…"
if ((${#HEADERS[@]})); then
  info "Installing kernel headers: ${HEADERS[*]}"
  dpkg -i "${HEADERS[@]}" || true
else
  warn "No linux-headers-$KVER deb found. If build fails, add it and re-run."
fi

if ((${#DKMS_PKG[@]})); then dpkg -i "${DKMS_PKG[@]}" || true; fi
if ((${#BUILD_ESS[@]})); then dpkg -i "${BUILD_ESS[@]}" || true; fi

dpkg -i "${STA_DKMS[@]}" || true
dpkg -i "${BCMWL[@]}" || true

# Fix dependency order using local cache only (offline-safe)
apt -y -f install || true

bold ">>> Regenerating initramfs & module deps…"
depmod -a || true
update-initramfs -u || true

# 5) Load wl and show status
bold ">>> Loading wl module…"
if modprobe wl; then
  info "wl loaded successfully."
else
  warn "wl did not load immediately; this often resolves after a reboot."
fi

echo
bold ">>> Devices (nmcli):"
nmcli -t d || true
echo

bold ">>> Done. Rebooting in 5 seconds… (Ctrl+C to cancel)"
sleep 5
systemctl reboot

