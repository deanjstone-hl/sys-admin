# sys-admin/stack/

This file provides guidance to agents working in the `stack/` subdirectory of the
`sys-admin` repo. See `../AGENTS.md` (repo root) for the full repo boundary and structure —
this file only covers `stack/`.

## What this directory is

The declarative dev stack: tool definitions, versions, config files, and install scripts for
WSL2 and Windows on `LNV-LGN5`. Claude Code's own config (skills, hooks, settings) is **not**
here — it lives in `~/repos/argus-config/` (extracted from this repo's former
`packages/dev-stack/` per ADR-007, 2026-07-04).

## Structure

```
config/
├── wsl2/           # WSL2 config files — symlinked to live locations by install-wsl2.sh
└── windows/        # Windows config files — copied by install-windows.ps1

docs/               # Architecture, decisions, scope, reports, session logs

check-drift.sh           # Compare declared stack state vs actual machine state
check-versions.sh        # Report current tool versions
install-windows.ps1      # Bootstrap Windows: winget, gitconfig, profile
install-wsl2.sh           # Bootstrap WSL2: symlinks, apt, binaries
install-wezterm.ps1      # Bootstrap WezTerm on Windows
update-inventory.sh      # Regenerate docs/reports/wsl2-software-inventory.md
```

## Common Tasks

- Regenerate software inventory: `./update-inventory.sh`
- Check tool versions: `./check-versions.sh`
- Bootstrap fresh WSL2: `./install-wsl2.sh [--dry-run]`
- Bootstrap Windows: `.\install-windows.ps1 [-DryRun]`
