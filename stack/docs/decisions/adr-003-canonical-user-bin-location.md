---
title: ADR-003 — Canonical location for user-installed CLI tools
status: accepted
date: 2026-07-09
---

# ADR-003: Canonical location for user-installed CLI tools

## Context

CLI tools on WSL2 had accumulated across five different install methods with no consistent
location: `~/bin` (manual downloads + Windows-interop symlinks mixed together), `~/.local/bin`
(pipx, uv, and most direct-source installers' own defaults), npm-global (tied to whichever fnm
Node version was active at install time), pipx (Python-venv-backed), and apt (system packages).

npm-global was explicitly the least-preferred install method (native binary or source preferred;
pnpm or apt as fallbacks if a manager is required), but had accumulated seven tools anyway
(`claude-code`, `claude-agent-acp`, `@bitwarden/cli` — a duplicate of an already-correct binary
install, `claudestat`, `playwright`, `pm2`, `wrangler`), including some with no alternative
compiled-binary distribution.

Two candidate locations were considered for consolidation:
- **`~/bin`** — already had PATH priority (established for shadowing `jq`/`direnv` over apt), but
  is a manual convention with no installer defaults; every tool would need to be placed there by hand.
- **`~/.local/bin`** — the XDG-standard user binary directory. Most direct-source installers
  (`uv`, `pipx`, `starship`, `zellij`, `goose`, official install scripts generally) already default
  here without configuration.

`~/.local/bin` was chosen as lower-friction: most tools were already landing there by default, so
consolidation meant moving a handful of outliers rather than fighting every installer's defaults.

## Decision

1. **`~/.local/bin` is the canonical location for all directly-installed, self-updating user
   binaries** — anything downloaded from source/GitHub Releases or installed via an official
   installer script.
2. **`~/bin` is repurposed as Windows-interop shims only** — symlinks or wrapper scripts that
   exec a Windows-side binary (`.exe` files, or scripts like `zed` that `exec` a Windows path).
   This gives a directory-level signal for provenance: `ls ~/bin` shows everything that crosses
   the WSL2/Windows boundary, at a glance, with nothing else mixed in.
3. **pnpm-global is the fallback** for tools with no standalone compiled-binary release (no
   change to existing pnpm-primary-package-manager policy). `pnpm setup` was run to wire
   `~/.local/share/pnpm/bin` onto `PATH` in both `.zshrc` and `.bashrc`.
4. **apt remains in scope** for system packages and anything with systemd-service integration
   (`tailscale`, `syncthing`) — moving daemon binaries out from under apt's management would
   orphan their existing systemd units.
5. **fnm remains the Node version manager**; it is not in conflict with pnpm as the package
   manager and was kept unchanged. `node`/`npm`/`npx`/`pnpm` continue to resolve via fnm's
   per-shell multishell bin directory, which by design still precedes `~/.local/bin` on `PATH`.

### Migrations performed
| Tool | From | To |
|---|---|---|
| `claude` (Claude Code) | npm (`@anthropic-ai/claude-code`) | native installer binary, `~/.local/bin/claude` |
| `gh`, `bat`, `fd`, `eza`, `fzf`, `zoxide`, `git-delta` | apt | GitHub Releases binaries, `~/.local/bin` |
| `bw`, `cloudflared`, `direnv`, `slack`, `agent` | `~/bin` | `~/.local/bin` |
| `claude-agent-acp`, `claudestat`, `playwright`, `pm2`, `wrangler` | npm-global | pnpm-global |
| `@bitwarden/cli` (npm) | — | removed (redundant with the existing `bw` binary install) |
| `clawteam` (pipx) | — | removed (unused trial artifact) |

## Consequences

- **Alias fix required**: apt's `bat`/`fd-find` packages ship binaries named `batcat`/`fdfind`
  (Debian naming-collision convention); the direct-source binaries use their real names. `.zshrc`
  aliases (`cat='batcat'`, `find='fdfind'`) were updated to `bat`/`fd`.
- **Redundant PATH exports removed** from `.zshrc`, `.bashrc`, and `.profile` — several installers
  (Antigravity CLI, Codex) had each appended their own `export PATH=".../.local/bin:$PATH"` block
  on top of the existing one.
- **`corepack` must never be removed** during npm-global cleanup — it is what provides the `pnpm`
  (and `yarn`) shims under fnm, not a leftover app install. Uninstalling it alongside the other
  npm-global tools broke `pnpm` entirely during this migration; fixed via
  `npm install -g corepack@latest && corepack enable`. Any future npm-global cleanup must exclude
  `corepack` explicitly.
- **Claude Code auto-update gotcha**: a running Claude Code session's background self-updater
  reinstalls itself via whichever method it was *originally* installed with — it has no way to
  detect an out-of-band migration to the native binary. A session that started life as the
  npm-installed copy silently re-created `@anthropic-ai/claude-code` under fnm's Node install
  during this migration, and because fnm's per-shell bin directory precedes `~/.local/bin` on
  `PATH`, that shadowed the native binary for any *new* shell too. Fix: remove the npm package
  again, then fully quit and start a new session — a freshly spawned `claude` process picks up
  the native binary via `PATH` resolution and its self-updater then updates in place there.
  Mid-migration `npm list -g` checks should watch for `@anthropic-ai/claude-code` reappearing
  while any old session is still alive.
- **Four unrelated dangling symlinks** were found and cleaned up during verification (not caused
  by this migration): `~/.local/bin/node`, `npm`, `npx` pointed at a deleted `~/.hermes/node/`
  install, and `~/bin/code` pointed at a VS Code path no longer present on the Windows side.
- **`sudo apt autoremove`** required a manual run in a real terminal — `sudo` needs a TTY that
  isn't available when a command is run through the agent (matches the existing
  `feedback_sudo_pipe_wsl2` gotcha). Orphaned deps (`libgit2-1.7`, `libhttp-parser2.9`,
  `libssh2-1t64`) were removed this way.
- **Follow-up not yet done**: the redundant Antigravity/Codex `PATH` blocks are cosmetic-only;
  no functional issue remains. `~/.local/share/pnpm/bin` is now on `PATH` in both shells but was
  not audited in `.profile` (login-only, non-interactive contexts).
