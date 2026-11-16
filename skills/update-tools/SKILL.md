---
name: update-tools
description: >
  Check for and apply updates to all WSL2 dev tools and applications on LNV-LGN5. Use for
  "check for updates", "update tools", "update applications", "what needs updating".
---

# Update Tools — WSL2 Dev Stack

Checks current versions against latest releases and applies updates using the correct method
per tool category.

## Step 1: Run the version check script

```bash
cd ~/repos/sys-admin && ./stack/check-versions.sh
```

## Step 1b: One node per host

```bash
bash ~/repos/argus-config/scripts/check-one-node.sh
```

Exit non-zero means the host has a second node install: stop, show the one-line refusal, and do not run any Node step below until it is resolved (argus-config#1164). This is read-only.

## Step 2: Check latest versions

Run these in parallel to get upstream latest for all key tools:

```bash
# Claude Code (native install, ~/.local/bin — ADR-003): `claude update` checks and applies
# npm-managed AI tools
npm show @openai/codex version
npm show @google/gemini-cli version

# GitHub Releases (via API)
curl -s https://api.github.com/repos/Schniz/fnm/releases/latest | jq -r '.tag_name'
curl -s https://api.github.com/repos/astral-sh/uv/releases/latest | jq -r '.tag_name'
curl -s https://api.github.com/repos/oven-sh/bun/releases/latest | jq -r '.tag_name'
curl -s https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name'
curl -s https://api.github.com/repos/jqlang/jq/releases/latest | jq -r '.tag_name'
curl -s https://api.github.com/repos/koalaman/shellcheck/releases/latest | jq -r '.tag_name'
curl -s https://api.github.com/repos/direnv/direnv/releases/latest | jq -r '.tag_name'

# npm registries
npm show @google/gemini-cli version
npm show playwright version

# Node LTS
fnm list-remote --lts | tail -5
```

## Step 3: Present the update table

Show a table of installed vs latest, with "update available" / "current" status. Include
notable callouts (major version bumps, security patches, apt-lagging packages).

## Step 3b: Confirm before applying

If any tools have updates available, ask:

```
AskUserQuestion: "Apply all available updates now?"
Options:
  - "Yes — apply all updates"
  - "No — show table only"
```

If the user declines, stop here. Do not apply any updates unless confirmed.

---

## Step 4: Apply updates

### Claude Code (native, `~/.local/bin` per ADR-003, never npm)
```bash
claude update
```

### npm-managed AI tools
```bash
npm update -g @openai/codex @google/gemini-cli
```

### uv
```bash
uv self update
```

### bun
```bash
bun upgrade
```

### jq — install binary to ~/.local/bin (no sudo; takes precedence over /usr/bin)
```bash
JQ_VERSION="<latest>"
curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
  -o ~/.local/bin/jq && chmod +x ~/.local/bin/jq
jq --version
```
`~/.local/bin` is earlier on `$PATH` than `/usr/bin`, so this shadowing approach works without sudo.

### shellcheck — install binary to ~/.local/bin (no sudo)
```bash
SHELLCHECK_VERSION="<latest>"   # tag from Step 2, e.g. v0.11.0
tmp=$(mktemp -d)
curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.x86_64.tar.gz" \
  | tar -xz -C "$tmp"
install -m 755 "$tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" ~/.local/bin/shellcheck
rm -rf "$tmp"
shellcheck --version
```
`check-versions.sh` reports the installed number. Compare it with the tag minus its `v`.

### gh — add GitHub CLI apt repo (requires sudo; prompt user to run manually if sudo unavailable)
```bash
# Two-step pattern — curl|sudo pipes fail without a TTY in WSL2
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /tmp/githubcli-archive-keyring.gpg
sudo mv /tmp/githubcli-archive-keyring.gpg /usr/share/keyrings/githubcli-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null

sudo apt update -qq && sudo apt install --only-upgrade gh -y
```
Ubuntu's apt repo lags significantly (e.g. 2.45 vs 2.93). The GitHub CLI team maintains their
own apt repo at cli.github.com — use that instead once the keyring is in place.

IMPORTANT: Never use `curl | sudo dd` or `curl | sudo tee` — WSL2 non-interactive shells have no
TTY so sudo cannot prompt for a password and the whole pipeline fails. Always download to /tmp
first, then sudo the move separately. See [[feedback_sudo_pipe_wsl2]].

### fnm — self-update or reinstall via curl
```bash
curl -fsSL https://fnm.vercel.app/install | bash
```

### direnv — install binary to ~/bin
```bash
DIRENV_VERSION="<latest without v prefix>"
curl -fsSL "https://github.com/direnv/direnv/releases/download/v${DIRENV_VERSION}/direnv.linux-amd64" \
  -o ~/bin/direnv && chmod +x ~/bin/direnv
```
`~/bin` is earlier on `$PATH` than `/usr/bin` and `~/.local/bin` — see [[feedback_bin_path_npm_link]].

### tailscale — via apt (Ubuntu repo tracks stable)
```bash
sudo apt update -qq && sudo apt install --only-upgrade tailscale -y
```

### Node.js — a replace, never an add (one node per host)

Never run `fnm install` (or `fnm install --lts`) on its own: it leaves two nodes on the host. First ask the check about the target version; it must refuse only because a different version is installed:

```bash
bash ~/repos/argus-config/scripts/check-one-node.sh --install v<new>
```

If it refuses, the upgrade is a replace. Confirm with the owner, then in one sitting: install the new version, move the fnm aliases (`default`, `taskview`) to it, rebuild native modules (e.g. `better-sqlite3` in agent-engine), remove the old version, and re-run `check-one-node.sh` until it passes. On homelab the install lives under `/usr/local/lib/nodejs` and needs root, so it is an owner step. Full procedure: argus-config `docs/reference/one-node-version.md`. `cf` wants node `^24.22.0`; that upgrade goes this way.

## Step 5: Verify

Re-run `./stack/check-versions.sh` (from `~/repos/sys-admin`) or spot-check each updated tool with `--version`.

### Playwright — npm global
```bash
npm update -g playwright
```
After updating, verify the browser bundle is still compatible:
```bash
playwright install --dry-run
```
Browsers are cached at `~/.cache/ms-playwright/` and are versioned alongside the npm package — a major version bump may require `playwright install chromium` to fetch the new bundle.

## Notes

- **pnpm**: managed via corepack under the active fnm Node install (not a Windows mount) — update with `corepack use pnpm@latest` or `npm install -g corepack@latest && corepack enable`.
- **bun**: not currently installed on this machine — skip Step 4 bun upgrade unless it's been installed since.
- **goose**: GitHub API returns null for latest; check https://github.com/block/goose/releases manually.
- **tmux**: Ubuntu apt ships 3.4 stable; upstream 3.6 is still beta. No action needed until stable.
- **Bitwarden CLI (bw)**: GitHub tags releases as `cli-vX.Y.Z`; compare with `bw --version`.
- **OCI CLI**: installed via pip; update with `pip install --upgrade oci`.
