---
title: Replace tmux with Zellij
status: superseded
superseded_by: deanjstone/argus docs/decisions/adr-006-revert-to-windows-terminal.md
date: 2026-06-21
---

> **Superseded by [argus ADR-006](https://github.com/deanjstone/argus/blob/main/docs/decisions/adr-006-revert-to-windows-terminal.md)** (2026-06-22). The Zellij evaluation was dropped the next day; tmux stayed the multiplexer. Kept as a
> historical record ([argus#418](https://github.com/deanjstone/argus/issues/418)).

## Context

tmux was adopted on WSL2 solely because it was the community default for terminal session persistence. It was never learned beyond the minimum needed to keep `main:argus` running. The actual usage is:

- One named session (`argus`) that survives terminal close
- A small number of named windows per session (argus, obsidian, project tabs)
- The `launch-claude` skill creates new windows in this session
- `ccbot` routes inbound Telegram messages to the active pane
- `my-rename` syncs the session and window name

tmux has a steep learning curve, a prefix-key model that is opaque to beginners, and requires external tooling (plugins, .conf, cheat sheets) to be ergonomic. Since tmux is not being used for any of its advanced features (layouts, plugins, scripting), there is no payoff for its complexity.

Zellij is a terminal multiplexer written in Rust. It provides session persistence with detach/reattach, tabs, panes, and floating panes. Its key differentiator is that all available actions are shown on screen at all times — no prefix key to memorise, no cheat sheet needed. Mouse support works out of the box. Sessions are persistent by default via a background daemon.

## Decision

Replace tmux with Zellij as the session multiplexer on WSL2.

- Zellij session `argus` replaces `main:argus` tmux session
- `zellij attach argus || zellij --session argus` becomes the WezTerm default profile command
- Zellij config lives at `argus/config/wsl2/zellij/config.kdl`; symlinked by `install-wsl2.sh`
- `tmux.conf` removed from `config/wsl2/` once migration is stable

The conceptual mapping is direct: tmux session → Zellij session, tmux window → Zellij tab, tmux pane → Zellij pane.

## Consequences

- `install-wsl2.sh` updated: install Zellij binary to `~/.local/bin/`, remove tmux from apt list
- `packages.txt` updated: remove `tmux`
- `launch-claude` skill updated: replace `tmux new-window -t main` with `zellij --session argus action new-tab --name <project>`
- `ccbot` routing updated: replace tmux pane targeting with `zellij action write-chars`
- `my-rename` skill updated: replace `tmux rename-session` + `tmux rename-window` with `zellij action rename-session` + `zellij action rename-tab`
- Argus `CLAUDE.md` session management section updated to reference Zellij
- `config/wsl2/zellij/config.kdl` added and documented in `SCOPE.md`
- tmux-related entries in argus `TODO.md` (e.g. status bar hooks) are superseded and can be closed
