#!/usr/bin/env bash
# Pair a known device onto homelab's Syncthing instance (sys-admin#37, ADR-002).
#
# Purpose-built wrapper per argus-config ADR-002: one narrow, named action
# (add a device to *this* node's own Syncthing config) instead of a general
# REST passthrough. Run ON homelab — targets its own local API, never a
# remote host. Only known device names from the registry below are accepted.
#
# Usage: ./pair-device.sh <device-name> [--dry-run]
#   device-name: one of wsl2, windows, dj15

set -euo pipefail

DEVICE_NAME="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

CONFIG_DIR="$HOME/.config/syncthing"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Private values come from the environment or Bitwarden Secrets Manager by key name
# (sys-admin#194): scripts/private-value.sh, keys in .env.example.
private_value() { bash "$SCRIPT_DIR/../private-value.sh" "$1"; }

CURL_OPTS=(-sk)

# Known-device allowlist — keep in sync with scripts/syncthing/README.md's
# Device Registry table. Intentionally a fixed list of names, not read from user input,
# so this script can only ever pair a device already vetted into the mesh. The device ids
# and addresses are looked up by key name once the name is accepted.
KNOWN_DEVICES=(wsl2 windows dj15)

known=false
for candidate in "${KNOWN_DEVICES[@]}"; do
  [[ "$DEVICE_NAME" == "$candidate" ]] && known=true
done
if [[ -z "$DEVICE_NAME" || "$known" != true ]]; then
  echo "Usage: $0 <device-name> [--dry-run]" >&2
  echo "  device-name must be one of: ${KNOWN_DEVICES[*]}" >&2
  exit 1
fi

# Tailscale-only addresses — no "dynamic", matches the project's
# Tailscale-only enforcement posture (see README Security section).
case "$DEVICE_NAME" in
  wsl2) KEY_SUFFIX=WSL2 IP_KEY=SYS_ADMIN_TAILSCALE_IP_WSL PORT=22001 ;;
  windows) KEY_SUFFIX=WINDOWS IP_KEY=SYS_ADMIN_TAILSCALE_IP_LAPTOP PORT=22000 ;;
  dj15) KEY_SUFFIX=IPHONE IP_KEY=SYS_ADMIN_TAILSCALE_IP_IPHONE PORT=22000 ;;
esac
DEVICE_ID="$(private_value "SYS_ADMIN_SYNCTHING_DEVICE_ID_$KEY_SUFFIX")"
DEVICE_ADDRESS="tcp://$(private_value "$IP_KEY"):$PORT"
API_URL="${SYNCTHING_API_URL:-https://$(private_value SYS_ADMIN_TAILSCALE_IP_HOMELAB):8384}"

if [[ ! -f "$CONFIG_DIR/config.xml" ]]; then
  echo "ERROR: $CONFIG_DIR/config.xml not found — is this running on homelab?" >&2
  exit 1
fi

API_KEY=$(grep -oP '(?<=<apikey>)[^<]+' "$CONFIG_DIR/config.xml")
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: could not read API key from $CONFIG_DIR/config.xml" >&2
  exit 1
fi

echo "==> Pairing device '$DEVICE_NAME' (${DEVICE_ID:0:7}) onto homelab's Syncthing (dry-run=$DRY_RUN)"

ALREADY_PAIRED=$(curl "${CURL_OPTS[@]}" -H "X-API-Key: $API_KEY" "$API_URL/rest/config/devices" \
  | python3 -c "import json,sys; ids=[d['deviceID'] for d in json.load(sys.stdin)]; print('yes' if '$DEVICE_ID' in ids else 'no')")

if [[ "$ALREADY_PAIRED" == "yes" ]]; then
  echo "    already paired — nothing to do"
  exit 0
fi

DEVICE_ADDR="$DEVICE_ADDRESS"
PAYLOAD=$(python3 -c "import json; print(json.dumps({'deviceID': '$DEVICE_ID', 'name': '$DEVICE_NAME', 'addresses': ['$DEVICE_ADDR'], 'introducer': False, 'autoAcceptFolders': False}))")

if $DRY_RUN; then
  echo "    [dry-run] would PUT the homelab API /rest/config/devices with:"
  echo "    $PAYLOAD"
  exit 0
fi

curl "${CURL_OPTS[@]}" -X POST -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d "$PAYLOAD" "$API_URL/rest/config/devices" > /dev/null

curl "${CURL_OPTS[@]}" -X POST -H "X-API-Key: $API_KEY" "$API_URL/rest/system/restart" > /dev/null

echo "    paired and restarted Syncthing to apply"
