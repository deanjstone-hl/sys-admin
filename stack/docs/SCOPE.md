# Scope

`stack/` is the source of truth for the **dev tool stack on `LNV-LGN5`** — the WSL2 and
Windows sides of one laptop.

## The repo boundary

sys-admin sits between two neighbours that both look like it. The rule, in one line:

> **sys-admin owns cross-machine sysadmin *tooling*, plus LGN5 machine state.
> homelab owns homelab machine state and the services hosted there.
> argus-config owns Claude Code's own configuration everywhere.**

So a file's home is decided by what it *is*, not which machine it runs on:

| It is… | It lives in… |
|---|---|
| A sysadmin skill, audit or inventory script — useful against any machine | **sys-admin** (`skills/`, `scripts/`) |
| Config or install for LGN5's WSL2/Windows dev stack | **sys-admin** (`stack/`) |
| Config, a systemd unit or an install script specific to homelab | **homelab** |
| A service *hosted on* homelab (its unit, deploy script, env template) | **homelab** (`services/<name>/`) |
| Claude Code settings, hooks, global CLAUDE.md, dev-workflow skills | **argus-config** |
| Shell and tool dotfiles (`.gitconfig`, `.tmux.conf`, `.bashrc.d/`) | **argus-config** (`envs/<env>/`) |
| Project/application code | its own repo under `~/repos/` |

This resolves a contradiction that stood in this file until 2026-09-28: it claimed
`stack/` covered "WSL2 + Windows" while `.claude/SYSTEM.md` claimed all three
environments. Both were half right — the *skills* are cross-machine, `stack/` is not.

### Known exceptions to the rule

None currently. Closed out so far (the first two on 2026-09-29, the third on 2026-10-28):

- The homelab Syncthing drift poller moved to the homelab repo
  ([homelab#101](https://github.com/deanjstone/homelab/issues/101)).
- `config/wsl2/` used to carry its own `gitconfig`, `tmux.conf` and
  `bashrc.d/{dev,bitwarden}.sh`, which `install-wsl2.sh` linked over argus-config's live
  copies. They were deleted ([#120](https://github.com/deanjstone/sys-admin/issues/120));
  `install-wsl2.sh` and `check-drift.sh` no longer touch those paths.
- The Windows `gitconfig` and `powershell-profile.ps1` moved to argus-config `envs/windows/`
  for the same reason ([#153](https://github.com/deanjstone/sys-admin/issues/153), decided on
  [#123](https://github.com/deanjstone/sys-admin/issues/123)), along with the `claude` /
  `claude-agent-acp` shims (the profile functions and `C:\Users\deanj\bin\*.cmd`). Its
  `install-windows.ps1` installs them and keeps the profile current; the terminal `claude` on
  Windows is the WSL2 install.

## What lives here

### WSL2 (`config/wsl2/`)

| Path | Purpose |
|---|---|
| `zellij/config.kdl` | Zellij config — symlinked to `~/.config/zellij/config.kdl` |
| `packages.txt` | apt packages to maintain — declarative, read by `check-drift.sh` |
| `fnm-versions` | Node versions managed by fnm — declarative |
| `systemd/vaultwarden.service` | Vaultwarden unit — installed by `install-wsl2.sh` |
| `systemd-user/t3code.service.d/override.conf` | T3 Code drop-in — copied into `~/.config/systemd/user/` by `install-user-units.sh`, which `install-wsl2.sh` calls. Copied, not linked, with `cp --remove-destination`; never restarts a unit |

### Windows (`config/windows/`)

| Path | Purpose |
|---|---|
| `wezterm.lua` | Copied to `%USERPROFILE%\.wezterm.lua` by `install-wezterm.ps1` |
| `winget-packages.json` | Package ID reference; winget installs run individually from `install-windows.ps1` |
| `zed-settings.json`, `zed-theme-dimidium{,-light}.json` | Zed settings and the Dimidium theme, both appearances |
| `wt-scheme-dimidium{,-light}.json` | Windows Terminal colour schemes |
| `wslconfig` | Hand-applied copy of `C:\Users\deanj\.wslconfig` — no installer applies it (moved from argus-config, [argus-config#338](https://github.com/deanjstone/argus-config/issues/338); settings from [#101](https://github.com/deanjstone/sys-admin/issues/101)) |

### Shared (`config/shared/`)

OS-independent config applied through an app's **own UI**, never installed to a path by a
script — which is why it is not under `wsl2/` or `windows/`. Currently
`t3code-theme-dimidium.json`. See `config/shared/README.md`.

### Scripts

| Path | Purpose |
|---|---|
| `install-wsl2.sh` | Bootstrap WSL2: symlinks, apt, binaries, systemd units. Dotfiles come from argus-config's installer |
| `install-windows.ps1` | Bootstrap Windows: apps, Zed and Windows Terminal config, power settings. The gitconfig, PowerShell profile and `claude` shims come from argus-config's installer |
| `install-wezterm.ps1` | Install WezTerm and deploy `config/windows/wezterm.lua` |
| `check-drift.sh` | Compare declared stack state vs actual machine state: packages, Node, owned symlinks, declared units active |
| `check-versions.sh` | Report current tool versions |
| `update-inventory.sh` | Regenerate `docs/reports/wsl2-software-inventory.md` |

### Docs

`docs/ARCHITECTURE.md` (service architecture), `docs/DECISIONS.md` + `docs/decisions/`
(ADRs), `docs/reports/` (point-in-time inventories), and this file. Session logs go to
`~/CONTEXT/03.SESSIONS/`, not here ([#152](https://github.com/deanjstone/sys-admin/issues/152)).

Backup coverage for LNV-LGN5 is **not** here — it is `docs/backup-coverage.md` at the repo
root, which is the cross-machine register. A restic scheme once lived at `docs/BACKUP.md`
with `backup.sh`, `init-backup.sh`, `setup-backup-server.sh` and a `backup.timer`; it was
never deployed and was deleted on 2026-09-28 rather than carried as dead code.

### Dashboard

A WSL2 status dashboard lived in `dashboard/` with `deploy-dashboard.sh` and a
`wsl2-dashboard.service` unit. It had not run since June 2026 and was never exposed, and
[Watchtower](https://github.com/deanjstone/watchtower) monitors the same hosts, so it was
deleted on 2026-09-29 ([#121](https://github.com/deanjstone/sys-admin/issues/121)).

## Stack in scope

**WSL2 services:** Tailscale · SSH · Syncthing · Bitwarden CLI · Vaultwarden ·
(the WSL2 dashboard was deleted — #121; Watchtower covers cross-host health)

**Dev tools tracked:** fnm · Node.js · pnpm · Python (uv) · git · gh · direnv · bw · zellij ·
claude · goose · codex · acp · gemini · playwright

**Windows tools tracked:** Git · GitHub CLI · Zed · Obsidian · PowerShell · WezTerm ·
Lenovo Vantage · winget packages
**Windows power config tracked:** lid-close actions, system cooling policy — see
`docs/DECISIONS.md`

## Out of scope

- **Project code** — individual projects live under `~/repos/` with their own repos
- **Claude Code config** — argus-config (`envs/wsl2/`, `envs/windows/`, `envs/homelab/`);
  settings, hooks, global CLAUDE.md, dev-workflow skills. Note it also owns the shell
  dotfiles (`.gitconfig`, `.tmux.conf`, `.bashrc.d/`)
- **homelab's own state and services** — the homelab repo
- **Secrets** — Bitwarden, never committed here
- **`minis`** — a non-managed environment by decision; see
  `docs/decisions/adr-004-minis-is-a-non-managed-environment.md`

## Updating

- Config change → edit `config/<env>/`, re-run the install script to re-symlink if needed
- Software inventory → `./update-inventory.sh`
- Architecture change → update `docs/ARCHITECTURE.md`
- New Windows package → add to `config/windows/winget-packages.json`, re-run
  `install-windows.ps1`
- A decision that moves the boundary above → an ADR, not an edit to this file alone
