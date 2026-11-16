#!/usr/bin/env bats
# Baseline coverage for stack/install-wsl2.sh per the dry-run testing
# strategy resolved in deanjstone/sys-admin#15. HOME is redirected to an
# isolated tmpdir so `~`-expanded paths in the script never touch the
# real home directory, even though DRY_RUN=true already short-circuits
# every mutating call through run()/symlink().

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

setup() {
  TEST_HOME="$(mktemp -d)"
  mkdir -p "$TEST_HOME"
  # The one-node check lives in argus-config (scripts/check-one-node.sh, argus-config#1164).
  # Tests stub it so they never read this machine's real node installs.
  ONE_NODE_STUB="$TEST_HOME/check-one-node-stub.sh"
  printf '#!/usr/bin/env bash\necho "stub: $*" >> "%s/check-calls.txt"\n' "$TEST_HOME" > "$ONE_NODE_STUB"
  export ONE_NODE_CHECK="$ONE_NODE_STUB"
}

teardown() {
  rm -rf "$TEST_HOME"
}

@test "install-wsl2.sh --dry-run exits 0" {
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [ "$status" -eq 0 ]
}

@test "install-wsl2.sh --dry-run reports dry-run mode in the banner" {
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [[ "$output" == *"dry-run=true"* ]]
}

@test "install-wsl2.sh --dry-run does not create the zellij symlink" {
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_HOME/.config/zellij/config.kdl" ]
}

@test "install-wsl2.sh --dry-run logs the symlink it would create" {
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [[ "$output" == *"[dry-run] ln -sf"*"zellij/config.kdl"* ]]
}

@test "install-wsl2.sh never links argus-config-owned dotfiles (sys-admin#120)" {
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"ln -sf"*".gitconfig"* ]]
  [[ "$output" != *"ln -sf"*".tmux.conf"* ]]
  [[ "$output" != *"ln -sf"*".bashrc.d"* ]]
}

# argus-config#1164: one node per host. The installer asks the check before `fnm install`.

@test "install-wsl2.sh asks the one-node check about the version it is about to install" {
  expected="$(grep -v '^#' "$REPO_DIR/stack/config/wsl2/fnm-versions" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')"
  [ "$expected" = "v24.18.0" ]
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [ "$status" -eq 0 ]
  grep -qxF "stub: --install $expected" "$TEST_HOME/check-calls.txt"
}

@test "install-wsl2.sh stops before fnm install when the one-node check refuses" {
  printf '#!/usr/bin/env bash\necho "refusing: 2 node installs" >&2\nexit 1\n' > "$ONE_NODE_STUB"
  HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing: 2 node installs"* ]]
  [[ "$output" != *"fnm install"* ]]
  [[ "$output" != *"fnm default"* ]]
}

@test "install-wsl2.sh declares a node version the hosts run, never a second one" {
  [ "$(grep -v '^#' "$REPO_DIR/stack/config/wsl2/fnm-versions" | grep -c '[^[:space:]]')" = "1" ]
  grep -qx 'v24\.18\.0' "$REPO_DIR/stack/config/wsl2/fnm-versions"
}

@test "install-wsl2.sh refuses when node is present and the check script is missing" {
  stub_dir="$TEST_HOME/bin"
  mkdir -p "$stub_dir"
  printf '#!/bin/sh\necho v24.18.0\n' > "$stub_dir/node"
  chmod +x "$stub_dir/node"
  ONE_NODE_CHECK="$TEST_HOME/absent.sh" PATH="$stub_dir:$PATH" HOME="$TEST_HOME" run "$REPO_DIR/stack/install-wsl2.sh" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot verify"* ]]
}
