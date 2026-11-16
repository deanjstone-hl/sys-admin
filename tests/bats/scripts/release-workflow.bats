#!/usr/bin/env bats
# Wiring tests for .github/workflows/release.yml and .releaserc.json (sys-admin#189, the
# Deploys rule's release pattern, argus-config#1167). Versions are cut on the `deploy` push:
# one `Release` workflow, a `Test before release (...)` job, then `Release` with `needs:`.
# They read the files as text so they need no YAML parser on the runner, and each one
# fails against the old workflow (a release on every push to main).

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"
  CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
  RELEASERC="$REPO_ROOT/.releaserc.json"
}

# The workflow with comment lines removed, so a comment cannot satisfy or trip a check.
code() { grep -v '^[[:space:]]*#' "$WORKFLOW"; }

@test "the workflow is named Release" {
  [ "$(sed -n 1p "$WORKFLOW")" = "name: Release" ]
}

@test "it runs on a push to deploy and never on a push to main" {
  code | grep -qE '^    branches: \[deploy\]$'
  [ "$(code | grep -cE 'branches:.*main')" -eq 0 ]
}

@test "it never triggers on workflow_run" {
  [ "$(code | grep -c 'workflow_run')" -eq 0 ]
}

@test "it queues releases in one group and never cancels one" {
  code | grep -qE '^  group: release$'
  code | grep -qE '^  cancel-in-progress: false$'
}

@test "a Test before release job runs first and names what it ran" {
  code | grep -qE '^    name: Test before release \(main CI on this SHA\)$'
  code | grep -qE '^    name: Test before release \(bats, Pester\)$'
}

@test "Release needs the test jobs, so a red or untested SHA gets no version" {
  release_block="$(code | sed -n '/^  release:$/,$p')"
  grep -qE '^    name: Release$' <<<"$release_block"
  grep -qE '^    needs: \[gate, test\]$' <<<"$release_block"
  grep -q "needs.gate.result == 'success'" <<<"$release_block"
}

@test "nothing releasable means no test and no version" {
  code | grep -q "id: anything"
  code | grep -q "release=false"
  code | grep -q "if: steps.anything.outputs.release == 'true'"
  code | grep -q "needs.gate.outputs.release == 'true'"
}

@test "the test reuses main's CI through release-proof.sh and falls back to ci.yml" {
  code | grep -q 'bash scripts/ci/release-proof.sh'
  code | grep -q "needs.gate.outputs.reuse != 'true'"
  code | grep -qE '^    uses: \./\.github/workflows/ci\.yml$'
  grep -qE '^  workflow_call:' "$CI_WORKFLOW"
}

@test "the proof step sets the env the vendored script no longer hard-codes" {
  # Unset, release-proof.sh reuses nothing (argus-config#1269).
  code | grep -qE '^          RELEASE_PROOF_WORKFLOW: CI$'
  code | grep -qE '^          RELEASE_PROOF_JOBS: \|$'
  code | grep -qE '^            bats \(bash scripts\)$'
  code | grep -qE '^            Pester \(PowerShell scripts\)$'
}

@test "CI fails on a hand-edited vendored release script, on every push and pull request" {
  grep -qE '^    branches: \[main\]$' "$CI_WORKFLOW"
  grep -qE '^  pull_request:$' "$CI_WORKFLOW"
  grep -q 'run: bash scripts/ci/release-scripts-check.sh' "$CI_WORKFLOW"
}

@test "the vendored release scripts carry a lock naming the argus-config source" {
  lock="$REPO_ROOT/scripts/ci/release-scripts.lock"
  grep -qE '^source deanjstone/argus-config [0-9a-f]{40}$' "$lock"
  for name in release-proof.sh release-scripts-check.sh release-with-retry.sh; do
    grep -qE "^[0-9a-f]{64}  $name\$" "$lock"
  done
}

@test "the drift check passes on the committed copies and fails on an edited one" {
  run bash "$REPO_ROOT/scripts/ci/release-scripts-check.sh"
  [ "$status" -eq 0 ]
  copy="$BATS_TEST_TMPDIR/ci"
  mkdir -p "$copy"
  cp "$REPO_ROOT"/scripts/ci/* "$copy/"
  echo "# edited" >> "$copy/release-proof.sh"
  run bash "$copy/release-scripts-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift: release-proof.sh"* ]]
}

@test "a dispatch from any ref but deploy releases nothing" {
  [ "$(code | grep -c "github.ref == 'refs/heads/deploy'")" -ge 2 ]
}

@test "no step releases from a push to main or retries against main" {
  [ "$(code | grep -c 'release-with-retry')" -eq 0 ]
  [ "$(code | grep -c 'check.sh')" -eq 0 ]
  [ ! -e "$REPO_ROOT/scripts/release-with-retry.sh" ]
}

@test "semantic-release publishes from deploy and commits nothing back" {
  [ "$(jq -c '.branches' "$RELEASERC")" = '["deploy"]' ]
  [ "$(grep -c '"@semantic-release/git"' "$RELEASERC")" -eq 0 ]
  [ "$(grep -c '@semantic-release/changelog' "$RELEASERC")" -eq 0 ]
  grep -q '@semantic-release/github' "$RELEASERC"
}

@test "the README documents the deploy branch and the release on promotion" {
  grep -q 'deploy' "$REPO_ROOT/README.md"
  grep -q 'Test before release' "$REPO_ROOT/README.md"
  [ "$(grep -c 'There is no `deploy` branch' "$REPO_ROOT/README.md")" -eq 0 ]
}

@test "the workflow files parse as YAML (a colon in a job name once broke the whole run)" {
  python3 -c 'import yaml' 2>/dev/null || skip "PyYAML not installed"
  python3 -I -c 'import sys, yaml
for path in sys.argv[1:]:
    yaml.safe_load(open(path))' "$WORKFLOW" "$CI_WORKFLOW"
}
