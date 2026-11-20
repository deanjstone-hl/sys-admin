#!/usr/bin/env bash
# The local check: the CI jobs on a push to main, run before a push (argus-config#1179,
# trunk-based development). Each step matches a CI job exactly:
#   - bats: the "bats (bash scripts)" job in .github/workflows/ci.yml
#   - shellcheck: the "ShellCheck" job in .github/workflows/lint.yml, severity warning
#   - pester: the "Pester (PowerShell scripts)" job in .github/workflows/ci.yml
#
# Usage: scripts/check.sh [step ...]   (no step runs all three, in the order above)
# A step the machine cannot run (pwsh missing for pester) is reported as skipped and
# CI is the backstop for it. On success prints one line: `check: pass <short sha>`.
set -euo pipefail

# The root comes from this script's own path, never the caller's cwd: another repo's
# pre-push gate runs it from its own checkout (sys-admin#193).
builtin cd "$(dirname "${BASH_SOURCE[0]}")/.."

# One full check at a time per host (argus-config#1506): two overlapping gates made
# systemd-oomd kill agent scopes. The re-exec waits for the host lock (HEAVY_LOCK_TIMEOUT,
# default 3600 s, then exit 75) and runs this script with HEAVY_LOCK_HELD=1 so it does not
# wait again. scripts/heavy-lock.sh is vendored from argus-config.
if [ "${HEAVY_LOCK_HELD:-}" != 1 ]; then
  exec bash "$PWD/scripts/heavy-lock.sh" bash "$PWD/scripts/check.sh" "$@"
fi

steps=("$@")
if [ ${#steps[@]} -eq 0 ]; then
  steps=(bats shellcheck pester)
fi

fail() {
  echo "check: FAIL at step $1" >&2
  exit 1
}

for step in "${steps[@]}"; do
  echo "check: step ${step}" >&2
  case "$step" in
    bats)
      bats tests/bats/ -r || fail bats
      ;;
    shellcheck)
      git ls-files -z '*.sh' | xargs -0 shellcheck --severity=warning || fail shellcheck
      ;;
    pester)
      if command -v pwsh >/dev/null 2>&1; then
        pwsh -NoProfile -Command 'Invoke-Pester -Path tests/pester -CI' || fail pester
      else
        echo "check: skipped pester (pwsh not installed); CI runs it" >&2
      fi
      ;;
    *)
      echo "check: unknown step '${step}' (bats, shellcheck, pester)" >&2
      exit 2
      ;;
  esac
done

echo "check: pass $(git rev-parse --short HEAD)"
