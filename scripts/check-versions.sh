#!/usr/bin/env bash
# Report installed Claude versions on WSL2 and Windows in one run.
set -uo pipefail

WIN_APPDATA_ROAMING="/mnt/c/Users/deanj/AppData/Roaming"

echo "=== Claude Version Check ==="
echo ""

echo "WSL2:"
wsl2_ver=$(claude --version 2>&1) && echo "  Claude Code CLI: $wsl2_ver" || echo "  Claude Code CLI: not found"
echo ""

echo "Windows:"

# Claude Code CLI — requires claude to be on the Windows PATH
win_cli_ver=$(cmd.exe /c "claude --version" 2>/dev/null | tr -d '\r')
[ -n "$win_cli_ver" ] && echo "  Claude Code CLI: $win_cli_ver" || echo "  Claude Code CLI: not found"

# Claude Desktop app — version stored in Roaming/Claude/config.json
desktop_config="$WIN_APPDATA_ROAMING/Claude/config.json"
if [ -f "$desktop_config" ]; then
  desktop_ver=$(python3 -c \
    "import json; d=json.load(open('$desktop_config')); print(d.get('updaterLastSeenVersion',''))" \
    2>/dev/null)
  [ -n "$desktop_ver" ] && echo "  Claude Desktop:  $desktop_ver" || echo "  Claude Desktop:  not found"
else
  echo "  Claude Desktop:  not found"
fi
