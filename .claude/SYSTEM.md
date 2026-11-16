# sys-admin — Architectural Constraints

This file is the permanent grounding document for Claude Code in this repository.
These rules are non-negotiable and must never be violated without explicit Director approval.

## Repo Boundary

The full rule, with a per-artefact table, is `stack/docs/SCOPE.md`. In short:

- **sys-admin owns cross-machine sysadmin *tooling*, plus LGN5 machine state.** A sysadmin skill, audit or inventory script belongs here whichever machine it targets. `stack/` is narrower than that: it is LGN5's WSL2 and Windows dev stack only.
- **homelab owns homelab machine state and the services hosted there** — its systemd units, install scripts and per-service config. A script that runs only on homelab belongs in that repo even when it is sysadmin-shaped.
- **argus-config owns Claude Code's own configuration** (settings, hooks, global CLAUDE.md, dev-workflow skills) *and* the shell/tool dotfiles (`.gitconfig`, `.tmux.conf`, `.bashrc.d/`). Never add Claude Code skill/hook/settings content here unless it is specifically a sysadmin skill wired into `skills/`.
- **Project and application code** lives in its own repo under `~/repos/`, never here.

Decided 2026-09-28, resolving a contradiction between this file (which claimed all three environments) and `stack/docs/SCOPE.md` (which claimed WSL2 + Windows). Both were half right: the skills are cross-machine, `stack/` is not. Two known violations of the rule are tracked and documented in `SCOPE.md` rather than silently tolerated — `homelab#101` and `#120`.

## Dev Stack (`stack/`)

- Tool definitions and versions are declarative — a tool's install/version state must be represented in `stack/config/`, not just performed ad hoc on a live machine.
- Config files tracked in `stack/config/` are symlinked to their live locations, not copied. Never break the symlink relationship by editing the live copy directly.
- Drift between declared stack state and actual machine state should be caught via the `config-audit` skill, not manual comparison.

## Cross-Environment Changes

- WSL2, Windows, and homelab are three distinct environments sharing this repo. A change to one environment's install/config script does not automatically apply to the others — if a change is meant to be cross-cutting, update `stack/install-wsl2.sh` and `stack/install-windows.ps1` together in the same step.
- After changing `stack/install-windows.ps1`, the change is not complete until it has actually been run/verified on Windows.
- Claude Code's own install scripts (`install-wsl2.sh`, `install-homelab.sh`, `install-windows.ps1`) live in `argus-config/scripts/`, not here — see the Repo Boundary note above. This repo's old `scripts/install-homelab.sh`/`install-windows.ps1` were retired in favor of that.

## Skills

- Sysadmin skills live in `skills/` and are wired into `~/.claude/skills/` via symlink (see the loop in the repo's `AGENTS.md`). Never duplicate a skill's content into `~/.claude/skills/` directly — always symlink from here.

## Secrets

- Secrets and credentials flow through Bitwarden (the `secrets-setup` skill, which lives in argus-config since #152). Never hardcode a credential in a script or config file tracked in this repo.
- Root actions on WSL2 are **not** a Bitwarden flow — see the `wsl-root` skill (formerly `bw-sudo`). They go through a fresh WSL session started as root from the Windows side, which needs no password, because `sudo` cannot escalate under the `systemd --user` namespace. See [#92](https://github.com/deanjstone/sys-admin/issues/92).

## Director-Agent Workflow

- All non-trivial work (new install script, changes to `stack/`, new sysadmin skill, provisioning a new server) begins with a GitHub issue — the issue is the source of truth, not a `.claude/tasks/` file. See `docs/agents/issue-tracker.md`.
- Claude writes the specification into the issue body under "## Specification", then appends its implementation plan under "## AI Implementation Plan" (files to create/modify/delete, step-by-step execution, risks — including any command that changes state on a live machine, not just file edits) before executing anything.
- Claude summarises the plan in chat so the Director can review without opening the issue.
- Code/command execution is blocked until the Director provides explicit approval in chat.
- Claude executes, comments on the issue with the verification checklist and results, and closes it once the Director confirms the work is done.
- Chat is the interface — the GitHub issue is the record.
- **Migration note (2026-07-29):** this repo's Director-Agent record moved from `.claude/tasks/task-XXX-*.md` files to GitHub issues, bringing sys-admin in line with every other active Director-Agent repo (batch-migrated 2026-07-17 through 2026-07-26). Task files created before this date remain as a historical archive; no new ones are created.

## Destructive Operations

- Scripts here can affect real, in-use machines (LGN5 WSL2/Windows, homelab). Treat anything that modifies system packages, symlinks into `~/.claude/`, or `systemd` units as high-blast-radius: confirm with the Director before running, even under an already-approved task.
