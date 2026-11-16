#!/usr/bin/env bash
# Trigger a Syncthing rescan on a known folder (sys-admin#37, ADR-002).
#
# Purpose-built wrapper per argus-config ADR-002: one narrow, named action
# instead of a general REST passthrough. Intended caller: the drift-monitoring
# poller (sys-admin#35). Targets the local node's own API only — run on
# whichever node needs its folder rescanned, never a remote host.
#
# Usage: ./trigger-rescan.sh <folder-id> [--dry-run]
#   folder-id: one of CONTEXT, CORTEX

set -euo pipefail

FOLDER_ID="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=true

# Known-folder allowlist — keep in sync with scripts/syncthing/README.md's
# Folder Map table.
KNOWN_FOLDERS=(CONTEXT CORTEX)

if [[ -z "$FOLDER_ID" ]] || ! printf '%s\n' "${KNOWN_FOLDERS[@]}" | grep -qx "$FOLDER_ID"; then
  echo "Usage: $0 <folder-id> [--dry-run]" >&2
  echo "  folder-id must be one of: ${KNOWN_FOLDERS[*]}" >&2
  exit 1
fi

CONFIG_DIR="${SYNCTHING_CONFIG_DIR:-$HOME/.local/state/syncthing}"
[[ -f "$CONFIG_DIR/config.xml" ]] || CONFIG_DIR="$HOME/.config/syncthing"
API_URL="${SYNCTHING_API_URL:-http://127.0.0.1:8384}"

if [[ ! -f "$CONFIG_DIR/config.xml" ]]; then
  echo "ERROR: no local Syncthing config.xml found (checked \$HOME/.local/state/syncthing and \$HOME/.config/syncthing)" >&2
  exit 1
fi

API_KEY=$(grep -oP '(?<=<apikey>)[^<]+' "$CONFIG_DIR/config.xml")
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: could not read API key from $CONFIG_DIR/config.xml" >&2
  exit 1
fi

echo "==> Triggering rescan of folder '$FOLDER_ID' (dry-run=$DRY_RUN)"

if $DRY_RUN; then
  echo "    [dry-run] would POST $API_URL/rest/db/scan?folder=$FOLDER_ID"
  exit 0
fi

curl -s -X POST -H "X-API-Key: $API_KEY" "$API_URL/rest/db/scan?folder=$FOLDER_ID" > /dev/null
echo "    rescan triggered"
