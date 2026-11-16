---
name: wsl-root
description: >
  Run root-privileged commands on WSL2 (LNV-LGN5). `sudo` cannot escalate under the
  systemd --user session (NoNewPrivs), so root actions go through a fresh WSL session
  started as root from Windows. Use for any WSL2 task needing root: apt installs, edits
  outside $HOME, system-scope systemd units, "run this with sudo", or a sudo attempt
  that failed with "no new privileges".
---

# wsl-root — root actions on WSL2

> **Formerly `bw-sudo`.** Renamed because it no longer uses Bitwarden and no
> longer uses `sudo` — the route it documents needs neither. See
> [sys-admin#92](https://github.com/deanjstone/sys-admin/issues/92).

## Why `sudo` cannot work here

Not a TTY problem, and not the agent sandbox. **The entire `systemd --user`
session on this machine runs inside a user namespace with no uid mapping for
root**, and with `NoNewPrivs=1` set.

```
NoNewPrivs, agent Bash tool         : 1
NoNewPrivs, herdr.service (boot-time user unit, not agent-spawned) : 1
NoNewPrivs, PID 1 (system systemd)  : 0
```

`no_new_privs` is inherited by every descendant and **cannot be unset once
set**, so `sudo` can never gain privilege anywhere in that tree. That covers
the agent's Bash tool, tmux panes, herdr panes, and any remote/mobile shell —
all of them. Attempts fail with:

```
sudo: /etc/sudo.conf is owned by uid 65534, should be 0
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

**The first line is a red herring.** Inside the namespace *every* file outside
`$HOME` reads as `nobody` — `/etc/passwd`, `/etc/sudoers`, `/usr/bin/sudo`
included. Viewed from outside, `/etc/sudo.conf` is owned by `root` exactly as
it should be. Nothing on the system is broken and nothing needs repairing.

**Do not** try `sudo -S`, a pty wrapper, `script -qc`, or "ask the user to run
it in a real terminal" — the last one has been tested and fails, because every
terminal under the user session inherits the namespace.

## The route that works

Invoke the **Windows-side WSL launcher** and ask it for a root session. The
launcher goes through the Windows service, so the resulting Linux process is a
child of WSL's init rather than of the caller — it starts outside the
namespace even when invoked from inside it.

Shape of the call:

```
<windows-wsl-launcher> -d <distro> -u root -- <command>
```

On this machine the launcher is at `/mnt/c/Windows/System32/` and the distro is
`Ubuntu`. Verify the escape before relying on it:

```
... -u root -- sh -c 'id; grep -i nonewprivs /proc/self/status'
```

Expect `uid=0(root)` and `NoNewPrivs: 0`. If you get `uid=1000`, you are still
inside the namespace and nothing you do will escalate.

**No password is required.** That is why this skill no longer touches
Bitwarden.

## Expect a permission prompt

This is a genuine privilege escalation, and Claude Code's permission classifier
**blocks it by default**. That is correct behaviour, not a bug to route around.

- If you are an agent and the call is denied: **stop and tell the user what you
  were trying to run and why.** Do not look for another way through.
- The user can allow it deliberately with a Bash permission rule, or run the
  command themselves.

The command works from anywhere that can reach the Windows launcher — including
a remote/mobile shell — because the escape happens on the Windows side rather
than through escalation in Linux. A user asked to run it does **not** need to be
at the physical machine.

## Preferences before reaching for root

Root is a last resort on this machine. In order:

1. **User-local install.** Check for an `install.sh` that accepts a prefix and
   install to `~/.local` from a scratch clone — `~/.local/bin` is already on
   `PATH` and is canonical per
   [ADR-003](../../stack/docs/decisions/adr-003-canonical-user-bin-location.md).
2. **Per-user systemd.** If the goal is a service, prefer a `--user` unit —
   those need no root at all.
3. **Root session**, via the route above, for genuine system-scope work: apt
   packages, files outside `$HOME`, system-scope units.

For file writes needing root, stage in `/tmp` and move as a single root
operation — never pipe a download straight into a privileged writer.

## Reference

- Root-cause investigation and evidence:
  [sys-admin#92](https://github.com/deanjstone/sys-admin/issues/92)
- The failure that surfaced it:
  [sys-admin#90](https://github.com/deanjstone/sys-admin/issues/90)
- Canonical binary location: ADR-003
- The Bitwarden item this skill used to read as `bw-sudo` (`LNV-LGN5 WSL2`) is
  left in the vault. **It has no remaining consumer anywhere** in sys-admin,
  argus-config or argus — see [sys-admin#60](https://github.com/deanjstone/sys-admin/issues/60).
