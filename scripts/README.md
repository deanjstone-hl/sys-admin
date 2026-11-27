# scripts/

Claude Code install scripts (`install-homelab.sh`, `install-windows.ps1`) have moved to [`argus-config/scripts/`](https://github.com/deanjstone/argus-config/tree/main/scripts) — this repo no longer owns Claude Code deploy. See that repo's `AGENTS.md` for the current symlink maps and install procedure per environment.

This directory still owns non-Claude-Code system automation: `check-versions.sh`, `syncthing/`, and the development tooling:

- `check.sh [bats|shellcheck|pester ...]`: the local check. Runs the same steps CI runs on every PR and on every push to `main` (no argument runs all three) and prints `check: pass <short sha>`. A step the machine cannot run (`pester` without `pwsh`) is reported as skipped; CI covers it. Run it once before marking a PR ready.
- `require-deploy-checkout.sh`: refuses a live install unless the checkout is exactly `origin/deploy` (tests: `tests/bats/scripts/require-deploy-checkout.bats`). Called first by `stack/install-wsl2.sh`, `stack/install-user-units.sh` and `syncthing/setup-wsl2.sh` on a real run.
- `ci/release-proof.sh`: the `Release` workflow's test step. Reuses `main`'s green `CI` run of the promoted SHA, fails on a red `main` run, else asks for a full run. Vendored from argus-config, which tests it; `release.yml` sets `RELEASE_PROOF_WORKFLOW` and `RELEASE_PROOF_JOBS`.
- `ci/release-with-retry.sh`, `ci/release-scripts-check.sh`, `ci/release-scripts.lock`: the rest of the vendored release scripts and their drift check. Synced from argus-config, never edited here; `ci.yml` runs the check on every push and pull request.
