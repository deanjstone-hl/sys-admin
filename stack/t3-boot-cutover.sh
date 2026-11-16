#!/usr/bin/env bash
# One-time switch from the desktop-managed WSL backend to t3code.service.
# Run from a plain terminal (not a T3 Code session) with the T3 Code desktop
# app fully closed. See docs/t3code-wsl2-boot.md.
set -euo pipefail

export PATH="$HOME/.local/share/fnm/aliases/default/bin:$PATH"
port=3773
version="${T3_VERSION:-latest}"
pair_ttl="${PAIR_TTL:-30m}"
desktop_settings="/mnt/c/Users/deanj/.t3/userdata/desktop-settings.json"

listeners=$(ss -Hltnp "sport = :$port")
if [[ -n "$listeners" ]]; then
  echo "Port $port is still in use — quit the T3 Code desktop app (tray icon too) and retry." >&2
  echo "$listeners" >&2
  exit 1
fi

echo "==> Disabling the desktop app's own WSL backend"
cp "$desktop_settings" "$desktop_settings.bak-$(date +%Y%m%d%H%M%S)"
updated=$(jq '.wslBackendEnabled = false | .wslOnly = false' "$desktop_settings")
printf '%s\n' "$updated" > "$desktop_settings"
jq -c '{wslBackendEnabled, wslOnly}' "$desktop_settings"

echo "==> Installing t3code.service"
npx --yes "t3@$version" service install

echo "==> Waiting for http://127.0.0.1:$port"
for _ in $(seq 1 30); do
  code=$(curl -s --max-time 2 -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port/" || true)
  [[ "$code" == "200" ]] && break
  sleep 1
done
systemctl --user --no-pager status t3code | head -5
if [[ "$code" != "200" ]]; then
  echo "Server did not answer 200 (last: $code). Log: ~/.t3/userdata/logs/boot-service.log" >&2
  exit 1
fi

echo "==> Pairing token for the desktop app (valid $pair_ttl)"
npx --yes "t3@$version" auth pairing create --base-url "http://127.0.0.1:$port" --ttl "$pair_ttl"
