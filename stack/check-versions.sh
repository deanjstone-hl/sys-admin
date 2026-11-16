#!/usr/bin/env bash
# Report current versions of tracked dev tools
set -euo pipefail

ver() {
  local name="$1"; shift
  local v
  v=$("$@" 2>/dev/null | head -1) || v="NOT FOUND"
  printf "  %-20s %s\n" "$name" "$v"
}

# `shellcheck --version` opens with a banner line; the number is on "version: X.Y.Z".
shellcheck_version() {
  local out
  out=$(shellcheck --version) || return 1
  sed -n 's/^version: //p' <<< "$out"
}

echo "==> WSL2 dev tool versions ($(date '+%Y-%m-%d'))"
echo ""
echo "Runtimes"
ver "node"          node --version
ver "fnm"           fnm --version
ver "python"        python3 --version
ver "uv"            uv --version
ver "bun"           bun --version
echo ""
echo "Package managers"
ver "pnpm"          pnpm --version
ver "npm"           npm --version
ver "pip"           pip3 --version
echo ""
echo "Shell tools"
ver "git"           git --version
ver "gh"            gh --version
ver "tmux"          tmux -V
ver "direnv"        direnv --version
ver "jq"            jq --version
ver "shellcheck"    shellcheck_version
echo ""
echo "AI tools"
ver "claude"        claude --version
ver "goose"         goose --version
ver "gemini"        gemini --version
ver "codex"         codex --version
ver "acp"           acp --version
echo ""
echo "Dev tools"
ver "playwright"    playwright --version
echo ""
echo "Infrastructure"
ver "tailscale"     tailscale version
ver "bw"            bw --version
ver "oci"           oci --version
echo ""
echo "System"
printf "  %-20s %s\n" "OS" "$(lsb_release -d 2>/dev/null | cut -f2 || echo 'NOT FOUND')"
ver "kernel"        uname -r
