#!/usr/bin/env bash
# Regenerate docs/reports/wsl2-software-inventory.md
set -euo pipefail

STACK_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="$STACK_DIR/docs/reports/wsl2-software-inventory.md"
DATE=$(date '+%Y-%m-%d')

ver() { eval "$1" 2>/dev/null | head -1 || echo "n/a"; }

# Report how a binary was actually installed, rather than asserting it: the
# owning dpkg package if there is one, otherwise the resolved path on disk.
install_method() {
  local bin path pkg
  bin=$(command -v "$1" 2>/dev/null) || { echo "not found"; return; }
  path=$(readlink -f "$bin")
  if pkg=$(dpkg -S "$path" 2>/dev/null | head -1 | cut -d: -f1) && [[ -n "$pkg" ]]; then
    echo "apt ($pkg)"
  else
    echo "${path/#$HOME/\~} (not packaged)"
  fi
}

cat > "$OUT" <<EOF
# WSL2 Software Inventory

Generated: $DATE
Machine: $(hostname) ($(lsb_release -d | cut -f2), kernel $(uname -r))

## Runtimes

| Tool | Version |
|---|---|
| Node.js | $(ver "node --version") |
| fnm | $(ver "fnm --version") |
| Python | $(ver "python3 --version") |
| uv | $(ver "uv --version") |
| Bun | $(ver "bun --version") |

## Package Managers

| Tool | Version |
|---|---|
| pnpm | $(ver "pnpm --version") |
| npm | $(ver "npm --version") |
| pip | $(ver "pip3 --version") |

## Shell & Dev Tools

| Tool | Version |
|---|---|
| git | $(ver "git --version") |
| gh | $(ver "gh --version | head -1") |
| tmux | $(ver "tmux -V") |
| direnv | $(ver "direnv --version") |
| jq | $(ver "jq --version") |

## AI / Agent Tools

| Tool | Version |
|---|---|
| claude | $(ver "claude --version") |
| goose | $(ver "goose --version") |
| gemini | $(ver "gemini --version") |
| codex | $(ver "codex --version") |
| acp | $(ver "acp --version") |

## Infrastructure

| Tool | Version | Location |
|---|---|---|
| Tailscale | $(ver "tailscale version") | system |
| Bitwarden CLI | $(ver "bw --version") | ~/.local/bin |
| OCI CLI | $(ver "oci --version") | ~/bin |
| GitHub CLI | $(ver "gh --version | head -1") | $(install_method gh) |

## Services (systemd)

| Service | Status |
|---|---|
$(for svc in tailscaled ssh vaultwarden; do
  status=$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")
  echo "| $svc | $status |"
done)
| syncthing (user) | $(systemctl --user is-active syncthing 2>/dev/null || echo "not-found") |

## Projects

| Project | Path |
|---|---|
$(ls -1 ~/repos/ 2>/dev/null | awk '{print "| " $1 " | ~/repos/" $1 " |"}')
EOF

echo "Updated: $OUT"
