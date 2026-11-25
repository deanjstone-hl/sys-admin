#!/usr/bin/env bash
# Reset the Syncthing GUI password on an existing node (sys-admin#104).
#
# The provisioning path is covered by homelab's install.sh (phase 7, REST API).
# This is the reset path for a node that is already set up: it hands the new
# password to `syncthing generate --gui-password=-`, so Syncthing itself does
# the bcrypt hashing and writes it into the <gui> block of config.xml. Keys,
# device ID, API key and the rest of the config are kept.
#
# Runs on the node whose password is being reset, against its local config.
#
# Usage: ./reset-gui-password.sh [--config DIR] [--user NAME] [--bw-item ITEM]
#                                [--service UNIT] [--no-restart]
#
# Password source, in order: --bw-item (Bitwarden), stdin if it is not a
# terminal, otherwise an interactive prompt. There is deliberately no
# --password flag: an argument shows up in `ps` and shell history.
#
#   --config DIR    config dir holding config.xml (default: the
#                   trigger-rescan.sh lookup, ~/.local/state/syncthing then
#                   ~/.config/syncthing)
#   --user NAME     also set the GUI user name (default: keep the current one)
#   --bw-item ITEM  read the password from this Bitwarden item. Uses
#                   $BW_SESSION if set, otherwise bitwarden-session from
#                   argus-config's bitwarden.sh ($BW_HELPER overrides the path)
#   --service UNIT  systemd --user unit to stop and restart (default:
#                   syncthing.service)
#   --no-restart    write only; refuses if the unit is running, because a live
#                   instance keeps the old config in memory and can save it back

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^$/s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

CONFIG_DIR=""
GUI_USER=""
BW_ITEM=""
SERVICE="syncthing.service"
RESTART=true

while (( $# )); do
  case "$1" in
    --config)     CONFIG_DIR="${2:?--config needs a directory}"; shift 2 ;;
    --user)       GUI_USER="${2:?--user needs a name}"; shift 2 ;;
    --bw-item)    BW_ITEM="${2:?--bw-item needs an item name}"; shift 2 ;;
    --service)    SERVICE="${2:?--service needs a unit name}"; shift 2 ;;
    --no-restart) RESTART=false; shift ;;
    --password|--password=*)
      echo "ERROR: no --password flag: pass it on stdin or use --bw-item" >&2
      exit 2 ;;
    -h|--help)    usage ;;
    *)            echo "ERROR: unknown option: $1" >&2; usage ;;
  esac
done

if [[ -z "$CONFIG_DIR" ]]; then
  CONFIG_DIR="$HOME/.local/state/syncthing"
  [[ -f "$CONFIG_DIR/config.xml" ]] || CONFIG_DIR="$HOME/.config/syncthing"
fi

# `syncthing generate` on a dir without config.xml would mint a new device
# identity, so this check is load-bearing, not cosmetic.
if [[ ! -f "$CONFIG_DIR/config.xml" ]]; then
  echo "ERROR: no config.xml in $CONFIG_DIR — refusing to generate a new identity" >&2
  exit 1
fi

if [[ -n "$BW_ITEM" ]]; then
  session="${BW_SESSION:-}"
  if [[ -z "$session" ]]; then
    helper="${BW_HELPER:-}"
    if [[ -z "$helper" ]]; then
      # The config repo is being renamed argus-config -> config: prefer ~/repos/config, fall back to the old path.
      helper="$HOME/repos/config/envs/wsl2/bashrc.d/bitwarden.sh"
      [[ -f "$helper" ]] || helper="$HOME/repos/argus-config/envs/wsl2/bashrc.d/bitwarden.sh"
    fi
    if [[ ! -f "$helper" ]]; then
      echo "ERROR: no BW_SESSION and no Bitwarden helper at $helper — pipe the password on stdin instead" >&2
      exit 1
    fi
    # shellcheck source=/dev/null
    source "$helper"
    session=$(bitwarden-session)
  fi
  password=$(bw get password "$BW_ITEM" --session "$session" --nointeraction)
elif [[ ! -t 0 ]]; then
  IFS= read -r password || true
else
  IFS= read -rsp "New Syncthing GUI password: " password; echo >&2
  IFS= read -rsp "Repeat it: " confirm; echo >&2
  if [[ "$password" != "$confirm" ]]; then
    echo "ERROR: passwords do not match" >&2
    exit 1
  fi
fi

if [[ -z "$password" ]]; then
  echo "ERROR: empty password" >&2
  exit 1
fi

was_active=false
if systemctl --user is-active --quiet "$SERVICE"; then
  was_active=true
fi

if $was_active && ! $RESTART; then
  echo "ERROR: $SERVICE is running — stop it first, or drop --no-restart" >&2
  exit 1
fi

if $was_active; then
  echo "==> Stopping $SERVICE"
  systemctl --user stop "$SERVICE"
fi

# generate wants --data alongside --config; it writes nothing there, so a
# scratch dir keeps it away from the real database.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

generate_args=(generate --config="$CONFIG_DIR" --data="$scratch" --gui-password=-)
[[ -n "$GUI_USER" ]] && generate_args+=(--gui-user="$GUI_USER")

echo "==> Writing new GUI password hash into $CONFIG_DIR/config.xml"
if ! printf '%s\n' "$password" | syncthing "${generate_args[@]}" > "$scratch/generate.log" 2>&1; then
  echo "ERROR: syncthing generate failed:" >&2
  cat "$scratch/generate.log" >&2
  $was_active && systemctl --user start "$SERVICE"
  exit 1
fi
unset password

if ! grep -qE '<password>\$2[aby]\$' "$CONFIG_DIR/config.xml"; then
  echo "ERROR: config.xml has no bcrypt GUI password after the write" >&2
  $was_active && systemctl --user start "$SERVICE"
  exit 1
fi

if $was_active; then
  echo "==> Starting $SERVICE"
  systemctl --user start "$SERVICE"
else
  echo "    $SERVICE was not running — it picks the new password up when it next starts"
fi

echo "    GUI password reset${GUI_USER:+ (user: $GUI_USER)}"
