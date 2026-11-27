# sys-admin

SysAdmin workspace for WSL2 (LGN5), Windows (LGN5), and homelab (Tailscale: `homelab`).

Agents operate here in a SysAdmin role — managing settings, applications, and services across all three environments.

**Boundary:** this repo owns cross-machine sysadmin *tooling* (`skills/`, `scripts/`) plus LGN5's WSL2/Windows dev stack (`stack/`). homelab's own machine state and hosted services live in the `homelab` repo; Claude Code's configuration and the shell dotfiles live in `argus-config`. Full rule and per-artefact table: `stack/docs/SCOPE.md`.

**Architectural rules:** `.claude/SYSTEM.md` — read this before making any structural changes (dev stack, cross-env scripts, skill wiring).
**Task workflow:** `.claude/tasks/` — non-trivial work is tracked here.

## Structure

```
stack/          — declarative dev stack: tool definitions, versions, install scripts
  config/         — per-tool config files tracked here and symlinked to live locations
  docs/           — stack architecture and decisions
  install-wsl2.sh       — bootstrap WSL2: apt packages, symlinks, binaries
  install-user-units.sh — copy config/wsl2/systemd-user/ units and drop-ins into ~/.config/systemd/user/ (called by install-wsl2.sh)
  install-windows.ps1   — bootstrap Windows: winget packages, gitconfig, profile
  install-wezterm.ps1   — install WezTerm and deploy config/windows/wezterm.lua
  check-drift.sh, check-versions.sh, update-inventory.sh

scripts/        — system automation (Claude Code install scripts moved to
                  argus-config/scripts/ — see scripts/README.md)
  check-versions.sh     — report current tool versions
  check.sh              — the local check (Bats, ShellCheck, Pester), run before every push
  require-deploy-checkout.sh — guard: live installers run only at origin/deploy
  ci/                   — vendored release scripts (synced from argus-config, never edited; release-scripts-check.sh guards them)
  syncthing/            — Syncthing setup guides and scripts

skills/         — Claude Code sysadmin skills (wired into ~/.claude/skills/)
  wsl-root          — root actions on WSL2 (via a root WSL session, not sudo)
  provision-server  — provision a new server
  update-tools      — update dev stack tools
  syncthing-pair    — pair a new Syncthing device
  health-check      — system health check across environments
  config-audit      — audit config drift
  ssh-perms-check   — SSH key/config permission check (delegated to by the two above)
  tmux-mgmt         — tmux session management

docs/           — runbooks, environment state, architecture notes
```

## Checks and pushing

Branch + PR: work on a branch off `origin/main` in your own worktree, push small conventional commits regularly, open a draft PR on the first push. Run `bash scripts/check.sh` (Bats, ShellCheck, Pester; it prints `check: pass <short sha>`) once before marking the PR ready. Rebase onto `origin/main` when it moves and push with `--force-with-lease` (own PR branch only). Merge with `gh pr merge --rebase --delete-branch` once every check on the head SHA is green. No direct pushes to `main`. CI runs the same steps on every PR and push to `main`. Details: `scripts/README.md`.

## Environments

| Name | Host | Access |
|---|---|---|
| WSL2 | LNV-LGN5 | local |
| Windows | LNV-LGN5 | local / PowerShell |
| Homelab | Dell Inspiron 5559 | Tailscale `homelab`, user `srvr` |

Homelab appears here because the skills target it, not because `stack/` configures it — see
the Boundary note above.

## Wiring sysadmin skills into Claude Code

```bash
for skill in wsl-root provision-server update-tools syncthing-pair health-check \
             config-audit ssh-perms-check tmux-mgmt; do
  ln -sfn ~/repos/sys-admin/skills/$skill ~/.claude/skills/$skill
done
```

Re-run this after adding a skill. **A skill on disk is inert until it is linked** — verify
with `ls -l ~/.claude/skills/<name>`, not by checking the file exists. `ssh-perms-check` was
extracted on 2026-07-11 specifically so `health-check` and `config-audit` could delegate to
it, was left out of this loop, and so was unreachable for the next two and a half months
while `config-audit` step 3 still said "invoke the `ssh-perms-check` skill".

```bash
# verify every skill here is actually wired
for skill in skills/*/; do
  n=$(basename "$skill")
  [[ -L ~/.claude/skills/$n ]] && echo "ok   $n" || echo "MISSING  $n"
done
```

## Related repos

- `argus` — agent CLI + agent-engine (orchestration core)
- `argus-config` — Claude Code configuration (skills, hooks, settings) and the shell dotfiles
- `homelab` — homelab's own machine state and the services hosted on it, including the
  phase-based provisioning scripts the `provision-server` skill drives

## Status

- **Repo structure standard:** Standard tier, applied 2026-10-08 (`repo-standard-rollout`,
  [argus#448](https://github.com/deanjstone/argus/issues/448)). See the
  [Repo Structure Standard](https://github.com/deanjstone/argus/blob/main/docs/system-specs/common/repo-structure-standard.md) in argus.
