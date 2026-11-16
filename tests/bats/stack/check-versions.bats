#!/usr/bin/env bats

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

@test "stack/check-versions.sh runs and exits 0" {
  run "$REPO_DIR/stack/check-versions.sh"
  [ "$status" -eq 0 ]
}

@test "stack/check-versions.sh reports a Runtimes section" {
  run "$REPO_DIR/stack/check-versions.sh"
  [[ "$output" == *"Runtimes"* ]]
}

@test "stack/check-versions.sh reports the ShellCheck version number, not its banner" {
  run "$REPO_DIR/stack/check-versions.sh"
  [[ "$output" =~ shellcheck\ +([0-9]+\.[0-9]+\.[0-9]+|NOT\ FOUND) ]]
}

@test "stack/check-versions.sh reports ShellCheck as NOT FOUND when it is not on PATH" {
  stub_dir="$(mktemp -d)"
  for tool in bash head printf date sed; do ln -s "$(command -v "$tool")" "$stub_dir/$tool"; done
  PATH="$stub_dir" run "$REPO_DIR/stack/check-versions.sh"
  rm -rf "$stub_dir"
  [[ "$output" =~ shellcheck\ +NOT\ FOUND ]]
}
