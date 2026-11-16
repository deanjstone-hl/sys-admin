---
title: ADR-004 — Minis (iSH Alpine on iOS) is a deliberate non-managed environment
status: accepted
date: 2026-09-06
---

# ADR-004: Minis (iSH Alpine on iOS) is a deliberate non-managed environment

## Context

`argus-config` gained a fourth environment for the **Minis** iOS app — agent harness config:
SOUL, skills, `GLOBAL.md`, and a model/provider snapshot. The obvious companion move is a
fourth machine entry in this repo: `stack/config/minis/`, an `install-minis.sh`, a row in the
drift check.

That symmetry is the trap this ADR exists to name. `argus-config` describes *how the agent
behaves*; `sys-admin` describes *how the machine is configured*. Minis is a real environment
for the first and very nearly an empty one for the second.

**The environment, as measured** (recorded in [#98](https://github.com/deanjstone/sys-admin/issues/98)):
Alpine 3.21.0, aarch64, running under iSH inside an iOS app container. The entire declarative
stack is 21 explicitly-installed packages in `/etc/apk/world` — `apk add` plus a re-clone
rebuilds it.

Roughly half this repo's machine model does not apply:

| `sys-admin` mechanism | Minis | |
|---|---|---|
| `packages.txt` → package manager | `/etc/apk/world` → `apk add` | applies |
| `config/<env>/` symlinked to live paths | rootfs symlinks work | applies |
| `check-drift.sh` | would work against apk | applies |
| `systemd/` units | `systemctl` / `rc-service` absent | no service layer |
| Tailscale Serve exposure | `tailscale` absent | not on the tailnet |
| `backup.sh` / restic / Borg | no `sudo`, no daemon, no root | N/A |
| Remote administration | `openssh-client` only; **no `sshd`** | unreachable |

`crond` exists at `/usr/sbin/crond`, but scheduling is unusable: iOS suspends the app, and
in-app cron/`at`/`nohup` loops stop with it. Recurring work has to route through Apple
Shortcuts, outside anything this repo manages.

## Decision

**No machine entry is added for Minis.** No `stack/config/minis/`, no `install-minis.sh`, no
drift-check row. Minis stays an `argus-config`-only environment.

Two reasons, and the second is the substantive one:

1. **It is not a machine you administer.** No `sshd`, not on the tailnet, no service manager —
   so none of the remote-administration tooling this repo exists to provide can reach it. Every
   other machine here is reachable and long-lived; this one is neither.

2. **Its system state is not durable.** The rootfs lives in an iOS app container keyed by a
   UUID that changes on reinstall, and system files outside `/var/minis/` are lost on a rootfs
   reset. During `argus-config#230`, a patch to `/usr/libexec/bats-core/bats-exec-suite`
   (working around missing `/dev/fd` process substitution) was needed to run the test suite at
   all — that patch will simply vanish. This repo has no concept of an environment whose system
   files evaporate. Minis is a **new machine class, not a fourth instance of the existing one**.

The operational quirks worth keeping — Python/OCR constraints under iSH, no `**` globstar in
BusyBox ash, which `/var/minis/` subdirectories permit symlinks, disk-headroom warnings — are
agent-facing knowledge and already live in `argus-config`'s `minis/GLOBAL.md`. That is the
correct side of the boundary.

## Consequences

- The asymmetry between `argus-config` (four environments) and `sys-admin` (three machines) is
  **intentional**. Anyone who notices it should land here rather than re-deriving the argument
  or "fixing" it.
- Minis recovery after a rootfs reset is a manual `apk add` plus re-clone. That is accepted, not
  overlooked.
- The bats-core patch is expected to be lost on reset and re-applied by hand.

### Reversal conditions

Any one of these makes a machine entry worth adding:

1. **A rootfs reset starts costing real time.** If setup grows past what is comfortable to redo
   by hand, a `bootstrap-minis.sh` earns its place — most likely first as
   `stack/config/minis/packages.txt` alone, with no installer.
2. **The device joins the tailnet**, making it addressable like the other three.
3. **A second Minis device appears.** One instance is configuration; two is a fleet, and a fleet
   needs reproducibility.

### Timing

Recording this rather than acting on it also avoids writing something that
[#74](https://github.com/deanjstone/sys-admin/issues/74) (LNV-LGN5 → Kubuntu) would likely
invalidate. That map may change the WSL2 assumptions underpinning both repos; a fourth machine
model is better designed after it lands.

## Related

- [#98](https://github.com/deanjstone/sys-admin/issues/98) — the issue this ADR resolves, carrying the full measured environment survey
- `argus-config#230` — instruction-file drift reconciliation; the Minis environment work builds on it
- [#74](https://github.com/deanjstone/sys-admin/issues/74) — Kubuntu migration map, which would reshape the machine model this ADR declines to extend
