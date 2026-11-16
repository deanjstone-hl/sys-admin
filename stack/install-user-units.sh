#!/usr/bin/env bash
# Install the WSL2 user-scope systemd units and drop-ins from
# config/wsl2/systemd-user/ into ~/.config/systemd/user/.
# Usage: ./install-user-units.sh [--dry-run]
#
# Copies, never links, and uses `cp --remove-destination`: a unit here once
# existed as a symlink into argus-config (argus-config#640), and a plain `cp`
# writes through a symlink, overwriting the file in the other repo.
#
# Never restarts or starts a unit. A running daemon keeps its old definition
# until its owner restarts it; this only reloads the user manager.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/config/wsl2/systemd-user"
DST="${HOME}/.config/systemd/user"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Installs live units: only from a checkout that is exactly origin/deploy (sys-admin#189).
# A dry run changes nothing and skips the check.
$DRY_RUN || bash "$REPO_DIR/../scripts/require-deploy-checkout.sh"

if [[ ! -d "$SRC" ]]; then
  echo "    No units directory at $SRC — skipping"
  exit 0
fi

CHANGED=0

install_file() {
  local src="$1" dst="$2" label="$3"
  if [[ -f "$dst" && ! -L "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "    $label: unchanged"
    return
  fi
  CHANGED=$((CHANGED + 1))
  if $DRY_RUN; then
    echo "[dry-run] cp --remove-destination $src $dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  cp --remove-destination "$src" "$dst"
  echo "    $label: installed"
}

shopt -s nullglob
for unit in "$SRC"/*.service; do
  install_file "$unit" "$DST/$(basename "$unit")" "$(basename "$unit")"
done
for dropin_dir in "$SRC"/*.service.d; do
  for conf in "$dropin_dir"/*.conf; do
    rel="$(basename "$dropin_dir")/$(basename "$conf")"
    install_file "$conf" "$DST/$rel" "$rel"
  done
done

if $DRY_RUN || ! command -v systemctl >/dev/null 2>&1; then
  exit 0
fi

systemctl --user daemon-reload

# `enable` only writes the wants link; it does not start the unit. A unit
# without [Install] is pulled in by something else and cannot be enabled.
for unit in "$SRC"/*.service; do
  grep -q '^\[Install\]' "$unit" || continue
  systemctl --user enable "$(basename "$unit")"
done
