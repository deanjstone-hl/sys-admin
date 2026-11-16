#!/usr/bin/env bash
# Bootstrap WSL2 dev environment from sys-admin's stack/
# Usage: ./install-wsl2.sh [--dry-run]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Symlinks and installs change the live machine: only from a checkout that is exactly
# origin/deploy (sys-admin#189). A dry run changes nothing and skips the check.
$DRY_RUN || bash "$REPO_DIR/../scripts/require-deploy-checkout.sh"

run() {
  if $DRY_RUN; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

echo "==> sys-admin stack: WSL2 bootstrap (dry-run=$DRY_RUN)"
echo "    Repo: $REPO_DIR"
echo ""

# --- Symlinks ---

echo "==> Symlinking config files"

symlink() {
  local src="$REPO_DIR/$1" dst="$2"
  if $DRY_RUN; then
    echo "[dry-run] ln -sf $src $dst"
    return
  fi
  if [[ -e "$dst" && ! -L "$dst" ]]; then
    echo "    Backing up existing $dst -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  fi
  ln -sf "$src" "$dst"
  echo "    $dst -> $src"
}

# ~/.gitconfig, ~/.tmux.conf and ~/.bashrc.d are argus-config's — run its
# scripts/install-wsl2.sh for those. Never link them from here (sys-admin#120).

mkdir -p ~/.config/zellij
symlink config/wsl2/zellij/config.kdl ~/.config/zellij/config.kdl

# bashrc.d sourcing — the directory itself comes from argus-config
# Marker text is matched against live ~/.bashrc: keep it, even though dev-stack is retired.
BASHRC_MARKER="# dev-stack: source bashrc.d"
if ! grep -qF "$BASHRC_MARKER" ~/.bashrc; then
  echo ""
  echo "==> Adding bashrc.d sourcing to ~/.bashrc"
  if ! $DRY_RUN; then
    cat >> ~/.bashrc <<'EOF'

# dev-stack: source bashrc.d
for f in ~/.bashrc.d/*.sh; do [ -f "$f" ] && source "$f"; done
EOF
  else
    echo "[dry-run] append bashrc.d loader to ~/.bashrc"
  fi
fi

# --- APT packages ---

echo ""
echo "==> Installing apt packages from config/wsl2/packages.txt"
mapfile -t PACKAGES < <(grep -v '^#' "$REPO_DIR/config/wsl2/packages.txt" | grep -v '^[[:space:]]*$')
run sudo apt-get update -qq
run sudo apt-get install -y "${PACKAGES[@]}"

# --- fnm (Node version manager) ---

echo ""
echo "==> Checking fnm"
if ! command -v fnm &>/dev/null; then
  echo "    Installing fnm..."
  if $DRY_RUN; then
    echo "[dry-run] curl -fsSL https://fnm.vercel.app/install | bash"
  else
    curl -fsSL https://fnm.vercel.app/install | bash
  fi
else
  echo "    fnm already installed ($(fnm --version))"
fi

# Skip comments and blank lines: the first line of the file used to be blank, so this came out empty
# and the fnm install below never ran.
NODE_VERSION=$(grep -v '^#' "$REPO_DIR/config/wsl2/fnm-versions" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')
if [[ -n "$NODE_VERSION" ]]; then
  # One node per host (argus-config#1164): the check lives in argus-config and refuses when
  # installing $NODE_VERSION would add a second node. A node upgrade is a replace step.
  ONE_NODE_CHECK="${ONE_NODE_CHECK:-$HOME/repos/argus-config/scripts/check-one-node.sh}"
  if [[ -f "$ONE_NODE_CHECK" ]]; then
    bash "$ONE_NODE_CHECK" --install "$NODE_VERSION" || exit 1
  elif command -v node &>/dev/null; then
    echo "refusing: cannot verify one node per host, $ONE_NODE_CHECK is missing and node is already installed" >&2
    exit 1
  fi
  echo "    Switching to Node $NODE_VERSION"
  run fnm install "$NODE_VERSION"
  run fnm default "$NODE_VERSION"
fi

# --- Standalone binaries ---

echo ""
echo "==> Checking standalone binaries in ~/bin"
mkdir -p ~/bin

if ! command -v direnv &>/dev/null; then
  echo "    direnv not found — install from https://direnv.net/docs/installation.html"
fi

if ! command -v bw &>/dev/null; then
  echo "    Bitwarden CLI not found — download from https://bitwarden.com/help/cli/"
fi

if ! command -v zellij &>/dev/null; then
  echo "    Installing Zellij..."
  run mkdir -p ~/.local/bin
  if $DRY_RUN; then
    echo "[dry-run] curl -fsSL .../zellij-x86_64-unknown-linux-musl.tar.gz | tar xz -C ~/.local/bin/"
  else
    curl -fsSL https://github.com/zellij-org/zellij/releases/latest/download/zellij-x86_64-unknown-linux-musl.tar.gz \
      | tar xz -C ~/.local/bin/
    echo "    Zellij installed ($(zellij --version 2>/dev/null || echo 'check PATH'))"
  fi
else
  echo "    zellij: ok ($(zellij --version))"
fi

# --- Systemd units ---

echo ""
echo "==> Installing systemd units from config/wsl2/systemd/"
UNITS_SRC="$REPO_DIR/config/wsl2/systemd"
if [[ -d "$UNITS_SRC" ]]; then
  for unit_file in "$UNITS_SRC"/*.service "$UNITS_SRC"/*.timer; do
    [[ -f "$unit_file" ]] || continue
    unit_name="$(basename "$unit_file")"
    if $DRY_RUN; then
      echo "[dry-run] cp $unit_file /etc/systemd/system/$unit_name"
      echo "[dry-run] systemctl enable $unit_name"
    else
      run sudo cp "$unit_file" "/etc/systemd/system/$unit_name"
      run sudo systemctl enable "$unit_name"
      if systemctl is-enabled --quiet "$unit_name" 2>/dev/null; then
        echo "    $unit_name: installed and enabled"
      else
        echo "    $unit_name: installed but NOT enabled — check unit file" >&2
      fi
    fi
  done
  run sudo systemctl daemon-reload
else
  echo "    No units directory found — skipping"
fi

# --- User systemd units ---

echo ""
echo "==> Installing user systemd units from config/wsl2/systemd-user/"
if $DRY_RUN; then
  "$REPO_DIR/install-user-units.sh" --dry-run
else
  "$REPO_DIR/install-user-units.sh"
fi

# --- AI CLI tools ---

echo ""
echo "==> Checking AI CLI tools"
for tool in claude goose acp codex gemini; do
  if command -v "$tool" &>/dev/null; then
    echo "    $tool: ok"
  else
    echo "    $tool: NOT FOUND"
  fi
done

# --- Playwright ---

echo ""
echo "==> Checking Playwright"
if ! command -v playwright &>/dev/null; then
  echo "    Installing Playwright 1.61.1..."
  run npm install -g playwright@1.61.1
  echo "    Playwright installed ($(playwright --version 2>/dev/null || echo 'check PATH'))"
else
  echo "    playwright: ok ($(playwright --version))"
fi
echo "    Chromium cache: ${PLAYWRIGHT_BROWSERS_PATH:-~/.cache/ms-playwright}"

# --- GitHub CLI ---

echo ""
echo "==> Checking gh"
if ! command -v gh &>/dev/null; then
  echo "    gh not found — install: https://cli.github.com/"
else
  echo "    gh: $(gh --version | head -1)"
  run gh auth status 2>/dev/null || echo "    (not authenticated — run: gh auth login)"
fi

echo ""
echo "==> Done. Next steps:"
echo "    1. Dotfiles:      bash ~/repos/argus-config/scripts/install-wsl2.sh"
echo "    2. Reload shell:  source ~/.bashrc"
echo "    3. Authenticate:  gh auth login"
