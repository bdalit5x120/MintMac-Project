#!/usr/bin/env bash
# mint-clone-rename.sh (v3)
# Clone helper for Linux Mint:
# - Rename user + home
# - Set hostname to mint{N}-Imac (or your prefix/suffix)
# - Generalize identity (machine-id, SSH host keys, logs)
# - PERMANENT FIX: XDG user dirs + Nemo/GTK bookmarks use $HOME paths
# - Optional: --repair-only runs only the folder/bookmark repair
#
# USAGE (typical new machine):
#   sudo bash mint-clone-rename.sh --old mintmain --new mint3 --index 3 --gecos "mint3"
#
# USAGE (auto infer next index from hostname like mint2-Imac -> 3):
#   sudo bash mint-clone-rename.sh --old mintmain --new mint3 --auto
#
# USAGE (only repair folders/bookmarks for the current NEW user):
#   sudo bash mint-clone-rename.sh --repair-only --user mint3
#
set -euo pipefail

PREFIX="mint"
SUFFIX="-Imac"
FULL_GENERALIZE=1
DRY_RUN=0
REPAIR_ONLY=0
TARGET_USER_FOR_REPAIR=""

err(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "[*] $*"; }
ok(){ echo "[✓] $*"; }
require_root(){ [[ "$(id -u)" -eq 0 ]] || err "Run as root (use sudo)."; }
command_exists(){ command -v "$1" >/dev/null 2>&1; }

first_human_sudo_user() {
  awk -F: '$3>=1000 && $6 ~ "^/home/" {print $1":"$6}' /etc/passwd |
  while IFS=: read -r u h; do id -nG "$u" 2>/dev/null | grep -qw sudo && { echo "$u"; return 0; }; done
  return 1
}
current_static_hostname(){ hostnamectl --static 2>/dev/null || hostname; }
next_index_from_hostname(){
  local h="$1"
  [[ "$h" == "${PREFIX}main${SUFFIX}" ]] && { echo 2; return; }
  if [[ "$h" =~ ^${PREFIX}([0-9]+)${SUFFIX}$ ]]; then echo $(( BASH_REMATCH[1] + 1 )); else echo 2; fi
}

# ---------- Args ----------
OLDUSER=""; NEWUSER=""; INDEX=""; AUTO=0; GECOS=""
while (( "$#" )); do
  case "$1" in
    --old) OLDUSER="${2:-}"; shift 2 ;;
    --new) NEWUSER="${2:-}"; shift 2 ;;
    --index) INDEX="${2:-}"; shift 2 ;;
    --auto) AUTO=1; shift ;;
    --gecos) GECOS="${2:-}"; shift 2 ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --suffix) SUFFIX="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --repair-only) REPAIR_ONLY=1; shift ;;
    --user) TARGET_USER_FOR_REPAIR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '1,200p' "$0"; exit 0 ;;
    *) err "Unknown arg: $1" ;;
  esac
done

require_root

# ---------- Functions ----------
repair_user_dirs_and_bookmarks() {
  local user="$1"
  local home
  home="$(getent passwd "$user" | cut -d: -f6)"
  [[ -n "$home" && -d "$home" ]] || err "Home for '$user' not found."

  info "Repairing XDG user dirs and bookmarks for user '$user' ($home)…"

  # Ensure config dirs
  install -d -o "$user" -g "$user" "$home/.config" "$home/.config/gtk-3.0"

  # Write user-dirs.dirs using $HOME (portable), backup if exists
  if [[ -f "$home/.config/user-dirs.dirs" ]]; then
    cp -a "$home/.config/user-dirs.dirs" "$home/.config/user-dirs.dirs.bak.$(date +%s)" || true
  fi
  cat > "$home/.config/user-dirs.dirs" <<'EOF'
# This file is written by xdg-user-dirs-update
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF
  chown "$user:$user" "$home/.config/user-dirs.dirs"

  # Update GTK/Nemo bookmarks: rewrite any absolute old paths to $HOME
  for f in "$home/.config/gtk-3.0/bookmarks" "$home/.gtk-bookmarks"; do
    if [[ -f "$f" ]]; then
      cp -a "$f" "$f.bak.$(date +%s)" || true
      # Normalize any /home/<something> to this user's $HOME when it points into standard dirs
      sed -i "s#^file:///home/[^/]*/#file://${home#/}#/g" "$f" || true
      sed -i "s#/home/[^/]*/#$home/#g" "$f" || true
      chown "$user:$user" "$f"
    fi
  done

  # Apply XDG and restart Nemo as that user
  if command_exists runuser; then
    runuser -l "$user" -c 'xdg-user-dirs-update --force || true'
    runuser -l "$user" -c 'nemo -q || true'
  fi

  ok "Folders/bookmarks repaired for '$user'."
}

# ---------- REPAIR-ONLY MODE ----------
if [[ "$REPAIR_ONLY" -eq 1 ]]; then
  [[ -n "$TARGET_USER_FOR_REPAIR" ]] || err "--repair-only requires --user USER"
  repair_user_dirs_and_bookmarks "$TARGET_USER_FOR_REPAIR"
  exit 0
fi

# ---------- Normal rename + host + generalize flow ----------
# Detect old user if not provided
[[ -z "$OLDUSER" ]] && OLDUSER="$(first_human_sudo_user || true)"
[[ -n "$OLDUSER" ]] || err "Could not auto-detect old user. Pass --old OLDUSER."
[[ -n "$NEWUSER" ]] || err "--new NEWUSER is required"

# Compute target hostname
CUR_HOST="$(current_static_hostname)"
if [[ -n "$INDEX" ]]; then
  [[ "$INDEX" =~ ^[0-9]+$ ]] || err "--index must be an integer"
  TARGET_INDEX="$INDEX"
elif [[ "$AUTO" -eq 1 ]]; then
  TARGET_INDEX="$(next_index_from_hostname "$CUR_HOST")"
else
  TARGET_INDEX="$(next_index_from_hostname "$CUR_HOST")"
fi
NEWHOST="${PREFIX}${TARGET_INDEX}${SUFFIX}"

# Safety
getent passwd "$OLDUSER" >/dev/null || err "User '$OLDUSER' not found."
getent passwd "$NEWUSER" >/dev=null && err "Target user '$NEWUSER' already exists." || true
if who | awk '{print $1}' | grep -qx "$OLDUSER"; then err "User '$OLDUSER' is logged in. Log that user out first."; fi

pgrep -u "$OLDUSER" >/dev/null 2>&1 && { info "Killing processes for '$OLDUSER'…"; pkill -KILL -u "$OLDUSER" || true; }

OLD_UID=$(id -u "$OLDUSER")
OLD_GID=$(id -g "$OLDUSER")
OLD_HOME=$(getent passwd "$OLDUSER" | cut -d: -f6)
OLD_GROUPS=$(id -nG "$OLDUSER" | tr ' ' '\n' | sort -u | grep -v "^$OLDUSER$" || true)
NEW_HOME="/home/$NEWUSER"

info "Plan:"
echo "  • $OLDUSER → $NEWUSER"
echo "  • $OLD_HOME → $NEW_HOME"
echo "  • Hostname: $CUR_HOST → $NEWHOST"
echo "  • Generalize: YES"
[[ -n "$GECOS" ]] && echo "  • GECOS: $GECOS"
[[ "$DRY_RUN" -eq 1 ]] && { ok "Dry-run only; exiting."; exit 0; }

# Hostname
if [[ "$CUR_HOST" != "$NEWHOST" ]]; then
  info "Setting hostname to $NEWHOST"
  hostnamectl set-hostname "$NEWHOST"
  if grep -q '^127\.0\.1\.1' /etc/hosts; then
    sed -i "s/^127\.0\.1\.1\s\+.*/127.0.1.1\t$NEWHOST/g" /etc/hosts
  else
    echo -e "127.0.1.1\t$NEWHOST" >> /etc/hosts
  fi
  ok "Hostname updated."
fi

# Rename user + home
info "Renaming user '$OLDUSER' → '$NEWUSER'…"
usermod -l "$NEWUSER" "$OLDUSER"
if [[ "$OLD_HOME" != "$NEW_HOME" ]]; then
  usermod -d "$NEW_HOME" -m "$NEWUSER"
  ok "Home moved."
fi

# Primary group
if getent group "$NEWUSER" >/dev/null; then
  :
else
  getent group "$OLDUSER" >/dev/null 2>&1 && groupmod -n "$NEWUSER" "$OLDUSER" || true
  getent group "$NEWUSER" >/dev/null 2>&1 || { groupadd -g "$OLD_GID" "$NEWUSER" || groupadd "$NEWUSER"; }
fi
usermod -g "$NEWUSER" "$NEWUSER"

# Supplemental groups
if [[ -n "$OLD_GROUPS" ]]; then
  RESTORE_GROUPS=$(echo "$OLD_GROUPS" | grep -v "^$NEWUSER$" | tr '\n' ',' | sed 's/,$//')
  [[ -n "$RESTORE_GROUPS" ]] && usermod -aG "$RESTORE_GROUPS" "$NEWUSER"
fi

# GECOS
[[ -n "$GECOS" ]] && usermod -c "$GECOS" "$NEWUSER"

# Ownership fix
chown -R "$NEWUSER:$NEWUSER" "$NEW_HOME"

# LightDM autologin
for path in /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/*.conf; do
  [[ -e "$path" ]] || continue
  if grep -q "autologin-user=$OLDUSER" "$path" 2>/dev/null; then
    sed -i "s/autologin-user=$OLDUSER/autologin-user=$NEWUSER/g" "$path"
  fi
done

# sudoers includes
if compgen -G "/etc/sudoers.d/*" >/dev/null; then
  for f in /etc/sudoers.d/*; do
    [[ -f "$f" ]] || continue
    if grep -qE "(^|[^A-Za-z0-9_-])$OLDUSER([^A-Za-z0-9_-]|$)" "$f"; then
      cp -a "$f" "$f.bak.$(date +%s)"
      sed -i "s/\b$OLDUSER\b/$NEWUSER/g" "$f"
      visudo -cf "$f" >/dev/null || { mv "$f.bak."* "$f"; err "Sudoers validation failed for $f"; }
    fi
  done
fi

# Folders/bookmarks repair (permanent)
repair_user_dirs_and_bookmarks "$NEWUSER"

# Generalize
info "Generalizing clone identity…"
[[ -f /etc/machine-id ]] && truncate -s 0 /etc/machine-id
[[ -f /var/lib/dbus/machine-id ]] && truncate -s 0 /var/lib/dbus/machine-id || true
[[ -d /etc/ssh ]] && rm -f /etc/ssh/ssh_host_* || true
command_exists journalctl && { journalctl --rotate || true; journalctl --vacuum-time=1s || true; }

ok "All done!"
echo
echo "NEXT STEPS:"
echo "  • Reboot: sudo reboot"
echo "  • Log in as '$NEWUSER'  (hostname: '$NEWHOST')"
echo "  • Verify: whoami; hostnamectl; open Nemo — no red badges; paths under $NEW_HOME"
cat: .: Is a directory
