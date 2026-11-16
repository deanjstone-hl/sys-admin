#!/usr/bin/env bash
# Syncthing setup for WSL2 (LNV-LGN5-WSL2)
# Installs syncthing, enables the systemd user service, and validates the setup.
# Run as the target user (not root). Requires sudo for apt.
# Usage: ./setup-wsl2.sh [--dry-run]

set -euo pipefail

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Installs and enables a live service: only from a checkout that is exactly origin/deploy
# (sys-admin#189). A dry run changes nothing and skips the check.
$DRY_RUN || bash "$(dirname "$0")/../require-deploy-checkout.sh"

SYNCTHING_PORT=8384
CONFIG_DIR="$HOME/.local/state/syncthing"
SYNC_DIR="$HOME/Sync"

log()  { echo "==> $*"; }
step() { echo "    $*"; }
run()  { $DRY_RUN && echo "    [dry-run] $*" || eval "$*"; }

log "Syncthing WSL2 setup (dry-run=$DRY_RUN)"
echo ""

# --- install ---

log "Install syncthing"
if command -v syncthing &>/dev/null; then
  INSTALLED_VER=$(syncthing --version | awk '{print $2}')
  step "already installed: $INSTALLED_VER"
else
  step "installing via apt..."
  run "sudo apt-get update -qq"
  run "sudo apt-get install -y syncthing"
fi
echo ""

# --- systemd user service ---

log "Enable syncthing systemd user service"
if systemctl --user is-enabled syncthing &>/dev/null; then
  step "service already enabled"
else
  run "systemctl --user enable syncthing"
  step "enabled"
fi

if systemctl --user is-active syncthing &>/dev/null; then
  step "service already active"
else
  run "systemctl --user start syncthing"
  step "started"
fi
echo ""

# --- wait for API ---

if ! $DRY_RUN; then
  log "Waiting for Syncthing API..."
  API_KEY=""
  for _ in $(seq 1 20); do
    if [[ -f "$CONFIG_DIR/config.xml" ]]; then
      API_KEY=$(grep -oP '(?<=<apikey>)[^<]+' "$CONFIG_DIR/config.xml" || true)
      [[ -n "$API_KEY" ]] && break
    fi
    sleep 1
  done

  if [[ -z "$API_KEY" ]]; then
    echo "ERROR: Could not read API key from $CONFIG_DIR/config.xml after 20s"
    exit 1
  fi
  step "API key: ${API_KEY:0:8}..."

  for _ in $(seq 1 10); do
    STATUS=$(curl -s --max-time 2 -H "X-API-Key: $API_KEY" "http://127.0.0.1:$SYNCTHING_PORT/rest/system/ping" 2>/dev/null || true)
    [[ "$STATUS" == '{"ping":"pong"}' ]] && break
    sleep 2
  done
  [[ "$STATUS" == '{"ping":"pong"}' ]] || { echo "ERROR: Syncthing API not responding"; exit 1; }
  step "API responding"
fi
echo ""

# --- default folder ---

log "Verify default sync folder"
if [[ -d "$SYNC_DIR" ]]; then
  step "$SYNC_DIR exists"
else
  run "mkdir -p '$SYNC_DIR'"
  step "created $SYNC_DIR"
fi
echo ""

# --- Tailscale serve rule ---

log "Tailscale serve for remote GUI access"
EXISTING=$(tailscale serve status 2>/dev/null | grep ":8384" || true)
if [[ -n "$EXISTING" ]]; then
  step "rule already present: $EXISTING"
else
  run "tailscale serve --bg --https=8384 http://localhost:8384"
  step "added https/:8384 → localhost:8384"
fi
echo ""

# --- status summary ---

log "Status"
systemctl --user --no-pager status syncthing | grep -E "Active:|Main PID:" | sed 's/^/    /'
if ! $DRY_RUN; then
  MY_ID=$(curl -s -H "X-API-Key: $API_KEY" "http://127.0.0.1:$SYNCTHING_PORT/rest/system/status" | python3 -c "import json,sys; print(json.load(sys.stdin)['myID'])" 2>/dev/null || echo "unknown")
  step "Device ID: $MY_ID"
fi

echo ""
log "Done."
echo ""
echo "    GUI (local):  http://127.0.0.1:8384"
remote_host="$(bash "$(dirname "${BASH_SOURCE[0]}")/../private-value.sh" SYS_ADMIN_TAILSCALE_HOST_WSL 2> /dev/null || echo '<SYS_ADMIN_TAILSCALE_HOST_WSL>')"
echo "    GUI (remote): https://${remote_host}:8384"
echo ""
echo "    To add Windows as a peer, open the GUI and add device:"
echo "    LNV-LGN5 — see config/syncthing/README.md for the device ID"
