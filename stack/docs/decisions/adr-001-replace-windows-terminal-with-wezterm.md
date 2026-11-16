---
title: Replace Windows Terminal with WezTerm
status: superseded
superseded_by: deanjstone/argus docs/decisions/adr-006-revert-to-windows-terminal.md
date: 2026-06-21
---

> **Superseded by [argus ADR-006](https://github.com/deanjstone/argus/blob/main/docs/decisions/adr-006-revert-to-windows-terminal.md)** (2026-06-22). The WezTerm migration was stopped the next day; Windows Terminal stayed the standard. Kept as a
> historical record ([argus#418](https://github.com/deanjstone/argus/issues/418)).

## Context

Windows Terminal has been the frontend terminal on LNV-LGN5. It works, but has several gaps:

- Per-project tab colours are configured as scattered JSON fragments with no single source of truth
- No built-in SSH connection manager — SSH to dell-server is done ad-hoc
- No SFTP client — file transfer requires a separate tool
- No config sync story — WT settings live only in `%APPDATA%\Local\Packages\...`
- Tab management and pane UX is functional but not composable

WezTerm is a GPU-accelerated cross-platform terminal emulator written in Rust. Its config is a single Lua file that can live in the argus repo and be version-controlled. It has native SSH and WSL2 domain support, built-in SFTP, and a powerful tab title callback for per-project colouring.

## Decision

Replace Windows Terminal with WezTerm as the primary terminal emulator on Windows.

- Config lives at `argus/config/windows/wezterm.lua`, symlinked or copied by `install-windows.ps1`
- Per-project tab colours migrated to a Lua `format-tab-title` callback (replaces all WT JSON colour fragments)
- dell-server SSH configured as an SSH Domain in wezterm.lua
- WSL2 Ubuntu configured as a WSL Domain (first-class, not a shell profile)
- SFTP available via WezTerm's SSH domain file transfer — no separate client needed

WezTerm coexists with Windows Terminal during migration; no hard cutover required.

## Consequences

- `argus/config/windows/wezterm.lua` added and tracked in git
- `install-windows.ps1` updated to install WezTerm via winget (`wez.wezterm`) and wire the config
- `launch-claude` skill updated: replace `wt.exe` spawn calls with `wezterm.exe cli spawn` equivalents
- Per-project colour map centralised in one Lua table (13 projects)
- `SCOPE.md` updated to document `config/windows/wezterm.lua`
- Windows Terminal can be removed once migration is stable; no immediate rush
