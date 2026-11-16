#!/usr/bin/env bash
# Print one private value (a Tailscale address or hostname, a Syncthing device id) by key name.
# The public tree holds no such value (sys-admin#194): every script and doc names the key and
# this script supplies the value.
#
#   bash scripts/private-value.sh <KEY> [<bws-key>]
#
# Order: the environment variable <KEY> if it is set and not empty (the .env.example
# overrides), else the Bitwarden Secrets Manager (BWS) secret named <bws-key> (default: <KEY>).
# BWS needs BWS_ACCESS_TOKEN, or the file named by BWS_TOKEN_FILE (default ~/.bws_token).
# Prints the value and a newline on stdout, nothing else. Exits 1 and names the key, never a
# value, when nothing supplies it; exits 2 on a malformed call.
set -euo pipefail

key="${1:-}"
bws_key="${2:-$key}"
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || ! [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
  echo "usage: $0 <KEY> [<bws-key>]   (KEY is an upper-case variable name)" >&2
  exit 2
fi

if [ -n "${!key:-}" ]; then
  printf '%s\n' "${!key}"
  exit 0
fi

if command -v bws > /dev/null && command -v jq > /dev/null; then
  token_file="${BWS_TOKEN_FILE:-${HOME:-/nonexistent}/.bws_token}"
  if [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -r "$token_file" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$token_file"
    set +a
  fi
  if [ -n "${BWS_ACCESS_TOKEN:-}" ]; then
    listing=""
    listing=$(bws secret list -o json 2> /dev/null) || listing=""
    value=""
    [ -z "$listing" ] || value=$(jq -r --arg k "$bws_key" '[.[] | select(.key == $k)][0].value // empty' <<< "$listing")
    if [ -n "$value" ]; then
      printf '%s\n' "$value"
      exit 0
    fi
  fi
fi

echo "private-value: $key is not set and Secrets Manager has no secret named $bws_key (see .env.example)" >&2
exit 1
