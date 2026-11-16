---
name: tmux-mgmt
description: >
  Expert tmux reference scoped to WSL2 (Ubuntu). Use this skill whenever the user asks about
  tmux commands, session/window/pane management, keybindings, scripting, multi-agent layout,
  supervising Claude Code agents, or managing persistent shells over SSH + Tailscale
  into WSL2. Trigger for any question containing "tmux", "session", "pane", "window", "attach",
  "detach", "split", "send-keys", or requests to automate terminal workflows or set up agent
  clusters on WSL2. Do NOT trigger for "spawn claude", "new session in <project>", "open
  claude in <project>" — those are handled by the launch-claude skill.
disable-model-invocation: true
---

# tmux on WSL2

Scoped to: Ubuntu on WSL2, SSH access via Tailscale (iOS SSH client), multi-agent
orchestration, Claude Code supervision.

---

## WSL2-Specific Gotchas

| Issue | Cause | Fix |
|---|---|---|
| tmux server dies on WSL restart | WSL2 process tree killed on Windows shutdown | Use `wsl --shutdown` sparingly; pre-start session via Task Scheduler |
| `$DISPLAY` unset inside tmux | GUI env vars not inherited | `set-option -g update-environment "DISPLAY WAYLAND_DISPLAY"` in `.tmux.conf` |
| Clipboard not working | WSL2 clipboard bridge missing | Pipe through `clip.exe`: `tmux show-buffer \| clip.exe` |
| SSH auth sock stale in old panes | `$SSH_AUTH_SOCK` not refreshed on reconnect | `set -g update-environment "SSH_AUTH_SOCK"` in `.tmux.conf` |
| Bell noise | WSL terminal passes bells through | `set -g bell-action none` in `.tmux.conf` |
| Sluggish escape key | Default escape-time 500ms | `set -sg escape-time 10` in `.tmux.conf` |

---

## Recommended `.tmux.conf` for WSL2

```bash
# ~/.tmux.conf

# Performance
set -sg escape-time 10
set -g repeat-time 300

# WSL2 env passthrough
set -g update-environment "DISPLAY WAYLAND_DISPLAY SSH_AUTH_SOCK SSH_CONNECTION"

# Sane defaults
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 50000
set -g mouse on

# Clipboard (WSL2)
bind-key -T copy-mode-vi y send -X copy-pipe-and-cancel "clip.exe"
bind-key -T copy-mode-vi Enter send -X copy-pipe-and-cancel "clip.exe"

# Splits that remember cwd
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"
bind c new-window -c "#{pane_current_path}"

# Reload config
bind r source-file ~/.tmux.conf \; display "Reloaded"

# Status bar
set -g status-interval 5
set -g status-left "[#S] "
set -g status-right "%H:%M %d-%b"
```

Apply without restart: `tmux source-file ~/.tmux.conf`

---

## Session Lifecycle

```bash
# Start or attach if exists
tmux new-session -A -s main

# Named session with start directory
tmux new-session -s work -c ~/repos

# List sessions
tmux ls

# Attach by name
tmux attach -t work

# Detach (inside tmux)
# Prefix + d

# Kill session
tmux kill-session -t work

# Kill all except currently attached session (must be inside tmux)
tmux kill-session -a

# Kill all except a named session (safe to run from outside tmux)
tmux kill-session -a -t work
```

---

## Window & Pane Essentials

```
Windows
  New:            Prefix + c
  Rename:         Prefix + ,
  Next/prev:      Prefix + n / p
  Jump to N:      Prefix + N
  List:           Prefix + w

Panes — DEFAULT bindings
  Left/right split:   Prefix + %
  Top/bottom split:   Prefix + "
  Navigate:           Prefix + arrow keys
  Zoom toggle:        Prefix + z
  Kill:               Prefix + x
  Show numbers:       Prefix + q
  Break to window:    Prefix + !

Panes — CUSTOM bindings (defined in .tmux.conf above)
  Horizontal (side-by-side): Prefix + |    (split-window -h)
  Vertical   (top/bottom):   Prefix + -    (split-window -v)
  Note: these override the defaults; both keep the current working directory
```

---

## Scripting: Multi-Agent Layout

Bootstrap a fixed window layout for Claude Code agents.

```bash
#!/usr/bin/env bash
# Usage: agent-layout.sh [session-name] [agent-count]

SESSION="${1:-agents}"
AGENTS="${2:-4}"
WORKDIR="$HOME/repos"

tmux kill-session -t "$SESSION" 2>/dev/null

# First window = orchestrator
tmux new-session -d -s "$SESSION" -n "orch" -c "$WORKDIR"

# Agent windows
for i in $(seq 1 "$AGENTS"); do
  tmux new-window -t "$SESSION" -n "agent-$i" -c "$WORKDIR"
done

tmux select-window -t "$SESSION:orch"
tmux attach -t "$SESSION"
```

---

## send-keys: Drive Agents Programmatically

`Enter` is a tmux reserved keyword for the return key. Pass it as a separate argument —
not inside the quoted string, and not as `""` (empty string sends nothing, command won't run).

```bash
# Send command to a specific window
tmux send-keys -t agents:agent-1 "claude --dangerously-skip-permissions" Enter

# Send to all agent windows
for i in 1 2 3 4; do
  tmux send-keys -t "agents:agent-$i" "claude --dangerously-skip-permissions" Enter
done

# Target a specific pane within a window (window.pane)
tmux send-keys -t agents:agent-1.0 "ls -la" Enter

# Broadcast same keys to ALL panes in current window
tmux set-window-option synchronize-panes on
tmux send-keys "echo synced" Enter
tmux set-window-option synchronize-panes off
```

---

## Supervision Pattern (SSH + Tailscale from a phone)

```bash
# On WSL2 — ensure session exists before closing SSH
tmux new-session -A -s sup

# From an iOS SSH client — attach or create:
ssh deanj@LNV-LGN5 -t "tmux attach -t sup || tmux new-session -s sup"
# -t allocates pseudo-TTY so tmux renders correctly over SSH

# Observe a session read-only without interfering
tmux attach -t agents -r
```

---

## Capture & Inspect Agent Output

```bash
# Visible pane content
tmux capture-pane -t clawteam:agent-1 -p

# With scrollback
tmux capture-pane -t clawteam:agent-1 -p -S -3000

# Save to file
tmux capture-pane -t clawteam:agent-1 -p -S -3000 > /tmp/agent1.log

# Poll a pane every 2s
watch -n 2 "tmux capture-pane -t clawteam:agent-1 -p | tail -20"
```

---

## Keeping Sessions Alive Across WSL Restarts

WSL2 kills all processes when the distro stops.

**Option A — Windows Task Scheduler (recommended)**
Create a task triggered at logon, running:
```
wsl.exe -d Ubuntu -- bash -c "tmux new-session -A -d -s main"
```
Pre-warms a detached session before you SSH in.

**Option B — `wsl.conf` boot command**

Requires WSL ≥ 0.67.6 (Sept 2022). Verify with `wsl --version` — if `WSL version:` is absent
or below that, update via `winget upgrade Microsoft.WSL` or the Microsoft Store.

Safest approach — point to a script to avoid ini quoting edge cases:

```bash
# Create the script
cat > /usr/local/bin/start-tmux.sh << 'EOF'
#!/bin/bash
su - deanj -c 'tmux new-session -d -s boot 2>/dev/null; true'
EOF
chmod +x /usr/local/bin/start-tmux.sh
```

```ini
# /etc/wsl.conf
[boot]
command = /usr/local/bin/start-tmux.sh
```

Runs automatically after `wsl --shutdown` + next distro start. The `[boot] command` runs as root.

**Option C — tmux-resurrect (manual save/restore)**
```bash
# Save:    Prefix + Ctrl-s
# Restore: Prefix + Ctrl-r
# Saves layout + pane contents to ~/.tmux/resurrect/
```

---

## Quick Reference

| Action | Command / Key |
|---|---|
| New session | `tmux new -s <name>` |
| Attach | `tmux attach -t <name>` |
| Detach | `Prefix + d` |
| List sessions | `tmux ls` |
| New window | `Prefix + c` |
| Split horizontal | `Prefix + \|` |
| Split vertical | `Prefix + -` |
| Zoom pane | `Prefix + z` |
| Reload config | `Prefix + r` |
| Send command to pane | `tmux send-keys -t <target> "<cmd>" Enter` |
| Capture pane output | `tmux capture-pane -t <target> -p` |
| Sync panes toggle | `tmux set-window-option synchronize-panes on\|off` |
| Read-only attach | `tmux attach -t <name> -r` |