#!/usr/bin/env bash
# Check for drift between the repo's declared state and the live WSL2 system.
# Exit 0 = clean; exit 1 = drift detected.
# Usage: ./check-drift.sh [--quiet]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; BOLD='\033[1m'; RESET='\033[0m'
TICK="${GREEN}✓${RESET}"; CROSS="${RED}✗${RESET}"; WARN="${YELLOW}⚠${RESET}"

drift=0

pass()   { $QUIET || printf "  ${TICK}  %s\n" "$1"; }
fail()   { printf "  ${CROSS}  %s\n" "$1" >&2; drift=1; }
warn()   { printf "  ${WARN}  %s\n" "$1" >&2; drift=1; }
header() { $QUIET || printf "\n${BOLD}%s${RESET}\n" "$1"; }

# ── APT packages ──────────────────────────────────────────────────────────────

header "APT packages  (config/wsl2/packages.txt)"
mapfile -t DECLARED < <(grep -v '^#' "$REPO_DIR/config/wsl2/packages.txt" | grep -v '^[[:space:]]*$')

# Build installed-package set once
INSTALLED_SET=$(apt list --installed 2>/dev/null | awk -F/ '{print $1}')

for pkg in "${DECLARED[@]}"; do
  if echo "$INSTALLED_SET" | grep -qx "$pkg"; then
    pass "$pkg"
  else
    fail "$pkg  (in packages.txt but not installed)"
  fi
done

# ── fnm / Node version ────────────────────────────────────────────────────────

header "Node / fnm  (config/wsl2/fnm-versions)"
DECLARED_VERSION=$(grep -v '^#' "$REPO_DIR/config/wsl2/fnm-versions" \
  | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')

if [[ -n "$DECLARED_VERSION" ]]; then
  if ! command -v fnm &>/dev/null; then
    warn "fnm not found — cannot check Node version"
  else
    # fnm current may need PATH primed; fall back to node -v
    ACTIVE=$(fnm current 2>/dev/null || node -v 2>/dev/null || echo "")
    ACTIVE=$(echo "$ACTIVE" | tr -d '[:space:]')
    DECLARED_NORM="v${DECLARED_VERSION#v}"
    ACTIVE_NORM="v${ACTIVE#v}"
    if [[ "$ACTIVE_NORM" == "$DECLARED_NORM" ]]; then
      pass "Node $DECLARED_NORM (active)"
    else
      warn "Node default is '${ACTIVE:-unknown}', expected $DECLARED_NORM"
    fi
  fi
fi

# ── Config symlinks ───────────────────────────────────────────────────────────

header "Config symlinks"

check_symlink() {
  local label="$1" live="${2/#\~/$HOME}" repo_rel="$3"
  local repo_abs="$REPO_DIR/$repo_rel"

  if [[ ! -e "$live" && ! -L "$live" ]]; then
    fail "$label  ($live: missing)"
    return
  fi

  if [[ ! -L "$live" ]]; then
    warn "$label  ($live: exists but is not a symlink — live edit may have replaced it)"
    return
  fi

  local raw target expected
  raw=$(readlink "$live")
  [[ "$raw" == /* ]] || raw="$(dirname "$live")/$raw"

  if ! target=$(realpath "$raw" 2>/dev/null); then
    fail "$label  ($live: broken symlink — target '$raw' does not exist)"
    return
  fi

  expected=$(realpath "$repo_abs" 2>/dev/null || echo "$repo_abs")
  if [[ "$target" == "$expected" ]]; then
    pass "$label  ($live → ${repo_rel})"
  else
    warn "$label  ($live → $target, expected $expected)"
  fi
}

# Only links this repo owns. ~/.gitconfig, ~/.tmux.conf and ~/.bashrc.d are
# argus-config's (sys-admin#120) and are not checked here.
# tilde expanded inside check_symlink(), not by the shell here
# shellcheck disable=SC2088
check_symlink "zellij/config.kdl" "~/.config/zellij/config.kdl"     "config/wsl2/zellij/config.kdl"

# ── Systemd units ─────────────────────────────────────────────────────────────

header "Systemd units  (config/wsl2/systemd/)"

# A declared unit that is not running is drift, not a detail to find by hand
# months later (sys-admin#121).
for unit_file in "$REPO_DIR"/config/wsl2/systemd/*.service; do
  [[ -f "$unit_file" ]] || continue
  unit_name="$(basename "$unit_file")"
  state=$(systemctl is-active "$unit_name" 2>/dev/null || true)
  if [[ "$state" == "active" ]]; then
    pass "$unit_name"
  else
    fail "$unit_name  (declared but ${state:-unknown})"
  fi
done

# ── Result ────────────────────────────────────────────────────────────────────

echo ""
if [[ $drift -eq 0 ]]; then
  printf "${GREEN}All checks passed — no drift detected.${RESET}\n"
  exit 0
else
  printf "${RED}Drift detected — see items marked ✗ or ⚠ above.${RESET}\n" >&2
  exit 1
fi
