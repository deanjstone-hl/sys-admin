# sys-admin

SysAdmin workspace for WSL2 (LNV-LGN5), Windows (LNV-LGN5) and the homelab (Tailscale `homelab`): the declarative WSL2/Windows dev stack, cross-machine automation scripts, and the Claude Code sysadmin skills that drive them.

Public repository, licensed under [Apache-2.0](./LICENSE) (see [NOTICE](./NOTICE)). It holds no private value: every Tailscale address, MagicDNS name and Syncthing device id is a Bitwarden Secrets Manager key read by name (see [Config and secrets](#config-and-secrets)). How the repository went public: [docs/public-cutover.md](./docs/public-cutover.md).

## Boundary

- **sys-admin** owns cross-machine sysadmin tooling (`skills/`, `scripts/`) and LGN5's WSL2/Windows dev stack (`stack/`).
- **homelab** owns the homelab's own machine state and the services hosted there.
- **argus-config** owns Claude Code's configuration (settings, hooks, instructions, dev-workflow skills) and the shell dotfiles (`.gitconfig`, `.tmux.conf`, `.bashrc.d/`). `stack/install-wsl2.sh` deliberately does not link them.

Full rule and per-artefact table: [stack/docs/SCOPE.md](./stack/docs/SCOPE.md). Architectural constraints for agents: [.claude/SYSTEM.md](./.claude/SYSTEM.md).

## Layout

```
stack/      LGN5 dev stack: config/ (tracked tool config), install scripts, drift and version checks, docs/ (architecture, scope, ADRs)
scripts/    check.sh (the local check), heavy-lock.sh and heavy-lock.lock (vendored from argus-config), check-versions.sh, require-deploy-checkout.sh, private-value.sh, scrub-scan.sh, ci/ (the vendored release scripts), syncthing/, owner-steps/
skills/     Claude Code sysadmin skills: wsl-root, provision-server, update-tools, syncthing-pair,
            health-check, config-audit, ssh-perms-check, tmux-mgmt
tests/      bats/ (bash scripts) and pester/ (PowerShell scripts)
docs/       runbooks and machine facts: backups, Bitwarden items, T3 Code on WSL2 boot, Tailscale/Node IPv4, the public cutover
```

## Prerequisites

- Developing here: `bash`, `bats`, `shellcheck`, `git`. `pwsh` (PowerShell 7) with Pester is optional locally; CI runs the Pester suite.
- Release tooling only (runs in CI on a promotion, not locally): Node 22 and pnpm 12.13.0 (pinned in `package.json`).
- Running the stack scripts: WSL2 Ubuntu for `*.sh`, Windows PowerShell 7 for `*.ps1`, `sudo` for apt (see the `wsl-root` skill; `sudo` cannot escalate under the `systemd --user` session).

## Check and push

Trunk-based: small conventional commits straight to `main`, no branch, no pull request.

```bash
bash scripts/check.sh              # bats, ShellCheck, Pester; prints `check: pass <short sha>`
bash scripts/check.sh bats         # or any of: bats shellcheck pester
git pull --rebase
git push origin HEAD:main
```

`check.sh` runs the same steps as CI. A step the machine cannot run (`pester` without `pwsh`) is reported as skipped and CI covers it.
It resolves the repo root from its own path, so `bash /path/to/sys-admin/scripts/check.sh` checks this tree from any directory (another repo's pre-push gate calls it that way). The gate takes the host-wide heavy lock ([argus-config/1506](https://github.com/deanjstone/argus-config/issues/1506)): `scripts/check.sh` re-runs itself through `scripts/heavy-lock.sh`, so only one full check runs at a time on a host, whichever thread or CI job starts it, and it also waits while memory `some avg60` is 10 or more. A queued run prints `waiting for the host lock` and starts when the holder ends; it exits 75 without running once `HEAVY_LOCK_TIMEOUT` (3600 s) passes. `scripts/heavy-lock.sh` and `scripts/heavy-lock.lock` are vendored byte-for-byte from argus-config (its `scripts/sync-heavy-lock.sh` rewrites both; never edit them here), and `tests/bats/scripts/heavy-lock.bats` fails on a copy that no longer matches its lock.

## Stack scripts (`stack/`)

Report-only (safe to run):

```bash
bash stack/check-versions.sh       # report installed tool versions
bash stack/check-drift.sh [--quiet]  # compare declared stack state to the live WSL2 system; exit 0 clean, 1 drift
```

Changes the machine (owner steps, run on LGN5; both support a dry run). A real run refuses unless the checkout is exactly `origin/deploy` (`scripts/require-deploy-checkout.sh`), so run it from `~/repos/sys-admin` after the owner's promotion; `--dry-run` skips that check:

```bash
bash stack/install-wsl2.sh [--dry-run]          # symlinks, apt packages, fnm, binaries, systemd units; checks the AI CLIs, Playwright and gh
# it refuses to run `fnm install` when that would add a second node (the config repo's scripts/check-one-node.sh, found under `~/repos/config` else `~/repos/argus-config`, or `ONE_NODE_CHECK`; one node per host); `stack/config/wsl2/fnm-versions` holds the one version
bash stack/install-user-units.sh [--dry-run]    # copy user-scope systemd units/drop-ins from stack/config/wsl2/systemd-user/ (install-wsl2.sh calls it)
```

```powershell
.\stack\install-windows.ps1 [-DryRun]   # winget packages, gitconfig, profile; run with pwsh (7+)
```

Also: `stack/install-wezterm.ps1` (install WezTerm and deploy `wezterm.lua`; elevated PowerShell), `stack/install-t3-boot-task.ps1` (Scheduled Task that boots the WSL distro at Windows startup; elevated pwsh) and `stack/t3-boot-cutover.sh` (one-time move to `t3code.service`). The last two are described in [docs/t3code-wsl2-boot.md](./docs/t3code-wsl2-boot.md). `stack/update-inventory.sh` regenerates `stack/docs/reports/wsl2-software-inventory.md`.

Tracked config in `stack/config/` is linked or copied to its live location by the install scripts; never edit the live copy. Declared tool versions and packages live in `stack/config/wsl2/` (`packages.txt`, `fnm-versions`).

## Other scripts (`scripts/`)

- `check-versions.sh`: reports installed Claude versions on WSL2 and Windows.
- `syncthing/`: `setup-wsl2.sh [--dry-run]`, `pair-device.sh <device> [--dry-run]` and `trigger-rescan.sh <folder-id> [--dry-run]` (run on the node concerned, each accepts only names from its allowlist), `reset-gui-password.sh` (password from Bitwarden, stdin or a prompt, never an argument). Topology and folder map: [scripts/syncthing/README.md](./scripts/syncthing/README.md).
- `private-value.sh <KEY> [<bws-key>]`: prints one private value by key name: the environment variable `KEY` if set, else the Secrets Manager secret of that name. `scrub-scan.sh [--head | <dir>]`: the gitleaks scan with this repository's personal-data rules (`.gitleaks.toml`); prints `scrub-scan: pass (0 findings)` or each finding's rule and place, never a value. `owner-steps/194.sh [--dry-run]`: the one-time cutover to the fresh-history public repository (see [docs/public-cutover.md](./docs/public-cutover.md)); an owner step, never run by an agent.
- `require-deploy-checkout.sh`: the guard every live installer runs first on a real run (`stack/install-wsl2.sh`, `stack/install-user-units.sh`, `syncthing/setup-wsl2.sh`). It exits 1 unless `HEAD` equals `origin/deploy` and tracked files are clean. It takes the per-host deploy lock shared with the other deploy repos.
- `ci/release-proof.sh`: used by the `Release` workflow to decide whether `main`'s green `CI` run of the promoted SHA can stand in for a test. `ci/release-with-retry.sh`, `ci/release-scripts-check.sh` and `ci/release-scripts.lock` come with it: the release scripts are vendored from argus-config (`scripts/sync-release-scripts.sh`) and are synced, never edited here. `release-scripts-check.sh` fails CI (the `bats` job, every push and pull request) on a hand-edited copy, and argus-config tests the script bodies. `release.yml` sets `RELEASE_PROOF_WORKFLOW=CI` and `RELEASE_PROOF_JOBS` (the two CI jobs) for the proof script.

## Skills

The skills in `skills/` are inert until symlinked into `~/.claude/skills/`. Re-run after adding one:

```bash
for skill in skills/*/; do
  name=$(basename "$skill")
  ln -sfn "$PWD/skills/$name" ~/.claude/skills/"$name"
done
```

Verify with `ls -l ~/.claude/skills/<name>`. Run from the primary checkout (`~/repos/sys-admin`) at `origin/deploy` (`git fetch origin deploy && git switch --detach origin/deploy`), so the links point there, not at a worktree, and only at promoted content.

## Config and secrets

Settings are script flags and these environment variables: `SYNCTHING_API_URL` (`pair-device.sh`), `T3_VERSION` and `PAIR_TTL` (`t3-boot-cutover.sh`). Credentials come from Bitwarden; none are stored in this repo. Vault item inventory: [docs/bitwarden.md](./docs/bitwarden.md).

Private values (Tailscale addresses and MagicDNS names, Syncthing device ids) are Bitwarden Secrets Manager (BWS) secrets named `SYS_ADMIN_<KEY>`, listed in [`.env.example`](./.env.example). `bash scripts/private-value.sh SYS_ADMIN_TAILSCALE_IP_HOMELAB` prints one: the environment variable of that name if set, else the BWS secret (needs `BWS_ACCESS_TOKEN`, or `~/.bws_token`). To run a script by hand without BWS, copy `.env.example` to `.env` (gitignored), fill the blanks and load it with `set -a; . ./.env; set +a`. The docs name each device by its 7-character id prefix and each address by its key. No workflow reads any of them.

## CI and releases

- `CI` (`.github/workflows/ci.yml`): bats and Pester on every push to `main` and every pull request, on GitHub-hosted `ubuntu-latest`. The bats job installs a pinned, checksummed gitleaks so the scrub scan runs.
- `Lint` (`.github/workflows/lint.yml`): ShellCheck at `warning` severity.
- The repository is public, so `tests/bats/scripts/public-safe.bats` pins the rules: every job on `ubuntu-latest` (the one other runner allowed is `[self-hosted, homelab, deploy]`, only in a workflow a push to `deploy` alone starts; none exists today), no `pull_request_target`, no secret but the read-only token in a pull-request workflow, no `CI_RUNS_ON`, no action from a private repository, and a clean `scripts/scrub-scan.sh` over the tree.
- `Release` (`.github/workflows/release.yml`): on a push to `deploy`, the owner's promotion, never on a push to `main`. A `workflow_dispatch` runs only with `--ref deploy`. It runs in order: `Test before release (main CI on this SHA)`, which first checks that the promotion carries a `feat`, `fix`, `perf` or `revert` commit or a breaking change since the last tag (none: no test, no version) and then reuses `main`'s green `CI` run of the exact SHA (`scripts/ci/release-proof.sh`; any red `main` run on the SHA fails the job); `Test before release (bats, Pester)`, which runs `ci.yml` itself only when `main` has no full green run of the SHA; then `Release` (`needs:` the test), which runs semantic-release on `deploy`. One version per promotion. It commits nothing back to `deploy`, so `CHANGELOG.md` is frozen at 1.2.1 and the GitHub Release notes carry the history. Concurrency group `release`, never cancelled. `docs`, `chore`, `ci`, `refactor` and `test` commits do not release.
- `README guard` (`.github/workflows/readme-guard.yml`): fails a change to workflows, `package.json` scripts, deploy/install scripts, env templates or CLI entry points that touches no README and has no `README: not needed because <reason>` line (PR body, or commit message for a push to `main`).

## Deploy and promotion

`deploy` is the production branch ([deploy rule](https://github.com/deanjstone/argus-config/blob/main/docs/instructions/deploys.md)). A merge to `main` ships nothing. The owner's Approve on the ops-hub promotion card fast-forwards `deploy` to a SHA already on `main`, never a force-push, and that push cuts the release. Nothing here is deployed by CI beyond the release: the stack scripts and symlinks run on the machine they target, from a checkout at `origin/deploy` only (`scripts/require-deploy-checkout.sh`). The Windows scripts (`stack/install-windows.ps1`, `install-wezterm.ps1`, `install-t3-boot-task.ps1`) have no such guard yet.

Rollback is a revert on `main` plus a promotion.

## More

- [AGENTS.md](./AGENTS.md): agent instructions for this repo
- [stack/AGENTS.md](./stack/AGENTS.md): agent instructions for `stack/`
- [CONTRIBUTING.md](./CONTRIBUTING.md): commit message format
- [scripts/README.md](./scripts/README.md): notes on `scripts/`
