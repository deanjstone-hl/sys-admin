#!/usr/bin/env bats
# What keeps this repository safe to publish (sys-admin#194, map homelab#478; the model is
# deanjstone/skills tests/test_public_safe.py, skills#27).
#
# The repository goes public through a fresh-history cutover, so a pull request from a fork
# runs these workflows on this repository's behalf and every file is world-readable. These
# tests pin the rules:
#   - jobs run on GitHub-hosted `ubuntu-latest`; the only other runner allowed is
#     `[self-hosted, homelab, deploy]`, and only in a workflow that a push to `deploy` alone
#     starts (GitHub, secure use of Actions: self-hosted runners "should almost never be used
#     for public repositories"; the fork-approval policy does not stop a fork's pull request
#     reaching one);
#   - no `pull_request_target`, no secret in a pull-request workflow beyond the read-only token;
#   - no private value in the tree (scripts/scrub-scan.sh).
# Workflows are read as text, as in release-workflow.bats, so no YAML parser is needed. Any
# value that looks private is built at run time, so this file holds none.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORKFLOWS="$REPO_ROOT/.github/workflows"
  load_helpers
}

load_helpers() {
  # code <file>: the file without comment lines, so a comment may name what a workflow avoids.
  code() { grep -v '^[[:space:]]*#' "$1"; }

  # on_keys <file>: the top-level keys under `on:` (push, pull_request, ...), one per line.
  on_keys() {
    code "$1" | awk '
      /^on:/ { inon = 1; next }
      inon && /^[^[:space:]]/ { inon = 0 }
      inon && /^  [A-Za-z_]+:/ { sub(/^  /, ""); sub(/:.*/, ""); print }'
  }

  # check_workflows <dir>: print one line per violation; the status is 1 when there is any.
  check_workflows() {
    local dir="$1" file name keys bad=0 values
    for file in "$dir"/*.yml; do
      [ -e "$file" ] || continue
      name="$(basename "$file")"
      if code "$file" | grep -qE 'pull_request_target'; then
        echo "$name: pull_request_target"; bad=1
      fi
      if code "$file" | grep -qE 'CI_RUNS_ON|vars\.[A-Z_]*RUNS_ON|runner\.environment'; then
        echo "$name: a runner-selecting variable or runner.environment test"; bad=1
      fi
      if code "$file" | grep -qE 'uses:[[:space:]]*deanjstone/'; then
        echo "$name: uses an action or workflow from a repository of the owner"; bad=1
      fi
      if code "$file" | grep -qE 'BWS_ACCESS_TOKEN'; then
        echo "$name: reads the Secrets Manager token"; bad=1
      fi
      keys="$(on_keys "$file")"
      values="$(code "$file" | sed -nE 's/^[[:space:]]*runs-on:[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p')"
      if [ -z "$values" ]; then echo "$name: no runs-on"; bad=1; fi
      while IFS= read -r value; do
        [ -n "$value" ] || continue
        case "$value" in
          ubuntu-latest) ;;
          '[self-hosted, homelab, deploy]')
            if [ "$keys" != "push" ] || ! code "$file" | grep -qE '^    branches: \[deploy\]$'; then
              echo "$name: a self-hosted job in a workflow that a push to deploy alone does not start"; bad=1
            fi ;;
          *) echo "$name: runs-on '$value'"; bad=1 ;;
        esac
      done <<< "$values"
      if grep -qx 'pull_request' <<< "$keys"; then
        if code "$file" | grep -oE 'secrets\.[A-Za-z0-9_]+' | grep -qvx 'secrets.GITHUB_TOKEN'; then
          echo "$name: a pull-request workflow reads a secret"; bad=1
        fi
        if ! code "$file" | awk '/^permissions:/ { p = 1; next } p && /^  contents:/ { print; exit } p && /^[^[:space:]]/ { exit }' | grep -qx '  contents: read'; then
          echo "$name: a pull-request workflow without top-level permissions: contents: read"; bad=1
        fi
      fi
    done
    return "$bad"
  }

  planted() {
    PLANT="$(mktemp -d)"
    mkdir -p "$PLANT/w"
    printf '%s\n' "$1" > "$PLANT/w/$2"
  }
}

teardown() {
  [ -z "${PLANT:-}" ] || rm -rf "$PLANT"
}

# ---- the workflows in this repository ----------------------------------------------------

@test "there are workflows to check" {
  [ "$(ls "$WORKFLOWS"/*.yml | wc -l)" -ge 1 ]
}

@test "every workflow here passes the public-repository rules" {
  run check_workflows "$WORKFLOWS"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "every job runs on ubuntu-latest and nothing here is self-hosted yet" {
  for file in "$WORKFLOWS"/*.yml; do
    [ "$(code "$file" | grep -cE 'self-hosted|homelab')" -eq 0 ] || { echo "$file"; return 1; }
    [ "$(code "$file" | grep -cE '^[[:space:]]*runs-on:')" -ge 1 ]
    [ "$(code "$file" | grep -E '^[[:space:]]*runs-on:' | grep -vc 'runs-on: ubuntu-latest$')" -eq 0 ] || { echo "$file"; return 1; }
  done
}

@test "the Pester job runs on ubuntu-latest, not a Windows or homelab runner" {
  code "$WORKFLOWS/ci.yml" | grep -qE '^    name: Pester'
  [ "$(code "$WORKFLOWS/ci.yml" | grep -cE 'windows-latest')" -eq 0 ]
}

@test "the pull-request workflows exist and are covered by the secret rule" {
  [ "$(on_keys "$WORKFLOWS/ci.yml" | grep -cx pull_request)" -eq 1 ]
  [ "$(on_keys "$WORKFLOWS/lint.yml" | grep -cx pull_request)" -eq 1 ]
  [ "$(on_keys "$WORKFLOWS/readme-guard.yml" | grep -cx pull_request)" -eq 1 ]
}

# ---- the checker itself: each rule fails on a planted breach ------------------------------

@test "the checker rejects pull_request_target" {
  planted $'name: x\non:\n  pull_request_target:\njobs:\n  a:\n    runs-on: ubuntu-latest' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
  [[ "$output" == *pull_request_target* ]]
}

@test "the checker rejects a self-hosted job in a workflow a pull request starts" {
  planted $'name: x\non:\n  pull_request:\n  push:\n    branches: [deploy]\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: [self-hosted, homelab, deploy]' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
  [[ "$output" == *"self-hosted job"* ]]
}

@test "the checker rejects a self-hosted job that a push to main starts" {
  planted $'name: x\non:\n  push:\n    branches: [main]\njobs:\n  a:\n    runs-on: [self-hosted, homelab, deploy]' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
}

@test "the checker accepts a self-hosted deploy job that only a push to deploy starts" {
  planted $'name: x\non:\n  push:\n    branches: [deploy]\njobs:\n  a:\n    runs-on: [self-hosted, homelab, deploy]' ok.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the checker rejects any other runner, the CI_RUNS_ON variable and runner.environment" {
  planted $'name: x\non:\n  push:\n    branches: [main]\njobs:\n  a:\n    runs-on: windows-latest' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
  planted $'name: x\non:\n  push:\n    branches: [main]\njobs:\n  a:\n    runs-on: ${{ fromJSON(vars.CI_RUNS_ON || \'"ubuntu-latest"\') }}' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
}

@test "the checker rejects a secret in a pull-request workflow and a missing read-only token" {
  planted $'name: x\non:\n  pull_request:\npermissions:\n  contents: read\njobs:\n  a:\n    runs-on: ubuntu-latest\n    env:\n      T: ${{ secrets.SOME_TOKEN }}' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reads a secret"* ]]
  planted $'name: x\non:\n  pull_request:\njobs:\n  a:\n    runs-on: ubuntu-latest' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
  [[ "$output" == *"permissions"* ]]
}

@test "the checker rejects an action from a repository of the owner and the Secrets Manager token" {
  planted $'name: x\non:\n  push:\n    branches: [main]\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: deanjstone/argus/.github/actions/x@v1' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
  planted $'name: x\non:\n  push:\n    branches: [main]\njobs:\n  a:\n    runs-on: ubuntu-latest\n    env:\n      BWS_ACCESS_TOKEN: x' bad.yml
  run check_workflows "$PLANT/w"
  [ "$status" -eq 1 ]
}

# ---- private values ----------------------------------------------------------------------

KEYS="SYS_ADMIN_TAILSCALE_IP_WSL SYS_ADMIN_TAILSCALE_IP_LAPTOP SYS_ADMIN_TAILSCALE_IP_HOMELAB SYS_ADMIN_TAILSCALE_IP_IPHONE SYS_ADMIN_TAILSCALE_HOST_WSL SYS_ADMIN_TAILSCALE_HOST_VAULTWARDEN SYS_ADMIN_SYNCTHING_DEVICE_ID_WSL2 SYS_ADMIN_SYNCTHING_DEVICE_ID_WINDOWS SYS_ADMIN_SYNCTHING_DEVICE_ID_IPHONE"

@test ".env.example names the Secrets Manager keys and holds no value" {
  run grep -vE '^[[:space:]]*(#|$)' "$REPO_ROOT/.env.example"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Z][A-Z0-9_]*=$ ]] || { echo "not a blank assignment: $line"; return 1; }
  done <<< "$output"
  named="$(sed -nE 's/^# BWS secret ([A-Za-z0-9_-]+):.*/\1/p' "$REPO_ROOT/.env.example" | sort | tr '\n' ' ')"
  expected="$(printf '%s\n' $KEYS | sort | tr '\n' ' ')"
  [ "$named" = "$expected" ] || { echo "named: $named"; echo "expected: $expected"; return 1; }
}

@test ".env is ignored" {
  grep -qx '.env' "$REPO_ROOT/.gitignore"
}

@test "the syncthing-pair skill names no address and reads each from Secrets Manager by key name" {
  skill="$REPO_ROOT/skills/syncthing-pair/SKILL.md"
  [ -z "$(grep -oE '\b[0-9]{1,3}(\.[0-9]{1,3}){3}\b' "$skill" | grep -vx '127.0.0.1')" ]
  for key in SYS_ADMIN_TAILSCALE_IP_WSL SYS_ADMIN_TAILSCALE_IP_LAPTOP SYS_ADMIN_TAILSCALE_IP_HOMELAB SYS_ADMIN_TAILSCALE_IP_IPHONE; do
    grep -q "$key" "$skill"
  done
  grep -q 'private-value.sh' "$skill"
}

@test "the scrub config and script exist" {
  [ -f "$REPO_ROOT/.gitleaks.toml" ]
  [ -f "$REPO_ROOT/scripts/scrub-scan.sh" ]
}

@test "the licence is Apache-2.0 and the NOTICE names the owner and the year" {
  grep -q 'Apache License' "$REPO_ROOT/LICENSE"
  grep -q 'Version 2.0, January 2004' "$REPO_ROOT/LICENSE"
  grep -qE 'Copyright 2026 Dean Stone' "$REPO_ROOT/NOTICE"
}

@test "private-value.sh prints a set variable and fails with the key name when nothing supplies it" {
  run env -i PATH=/usr/bin:/bin HOME=/nonexistent SYS_ADMIN_TAILSCALE_IP_WSL=planted \
    bash "$REPO_ROOT/scripts/private-value.sh" SYS_ADMIN_TAILSCALE_IP_WSL
  [ "$status" -eq 0 ]
  [ "$output" = planted ]
  run env -i PATH=/usr/bin:/bin HOME=/nonexistent bash "$REPO_ROOT/scripts/private-value.sh" SYS_ADMIN_TAILSCALE_IP_WSL
  [ "$status" -ne 0 ]
  [[ "$output" == *SYS_ADMIN_TAILSCALE_IP_WSL* ]]
}

# ---- the scrub scan (needs gitleaks; the CI job installs it) ------------------------------

scan() { bash "$REPO_ROOT/scripts/scrub-scan.sh" "$@"; }

plant_dir() {
  PLANT="$(mktemp -d)"
  printf '%s\n' "$2" > "$PLANT/$1"
}

require_gitleaks() {
  command -v gitleaks > /dev/null || skip "gitleaks is not installed"
  command -v jq > /dev/null || skip "jq is not installed"
}

@test "the tree at HEAD has no finding" {
  require_gitleaks
  cd "$REPO_ROOT"
  run scan
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"scrub-scan: pass (0 findings)"* ]]
}

@test "a clean directory passes" {
  require_gitleaks
  plant_dir a.md "nothing private here, write to owner@example.com"
  run scan "$PLANT"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "each private value kind fails the scan and is never printed" {
  require_gitleaks
  # Built from parts so this file holds no private-looking value itself.
  local dot="." seven="ABCDEFG"
  declare -A values=(
    [tailnet-ip]="100${dot}97${dot}96${dot}95"
    [lan-ip]="192${dot}168${dot}7${dot}9"
    [tailnet-hostname]="box${dot}tail1a2b3${dot}ts${dot}net"
    [personal-email]="someone@mail${dot}invalid-tld-example${dot}org"
    [cloudflare-id]="$(printf 'ab%.0s' {1..16})"
    [access-team-domain]="team-xxxx${dot}cloudflareaccess${dot}com"
    [syncthing-device-id]="$(printf "${seven}-%.0s" {1..7})${seven}"
  )
  for rule in "${!values[@]}"; do
    plant_dir leak.txt "value ${values[$rule]}"
    run scan "$PLANT"
    [ "$status" -eq 1 ] || { echo "$rule: status $status"; return 1; }
    [[ "$output" == *"$rule"* ]] || { echo "$rule: not named"; return 1; }
    [[ "$output" != *"${values[$rule]}"* ]] || { echo "$rule: value printed"; return 1; }
    rm -rf "$PLANT"
  done
}
