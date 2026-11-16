#!/usr/bin/env bats
# scripts/require-deploy-checkout.sh (sys-admin#189, argus-config#1133, map #1048): the guard
# every live installer runs first. A checkout may change the machine only when it is exactly
# what origin/deploy holds. The shared deploy lock is switched off (ARGUS_DEPLOY_LOCK=off);
# it is argus-config's to test.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export ARGUS_DEPLOY_LOCK=off
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  CLONE="$BATS_TEST_TMPDIR/clone"
  git init -q --bare -b main "$ORIGIN"
  git clone -q "$ORIGIN" "$CLONE" 2>/dev/null
  mkdir -p "$CLONE/scripts"
  cp "$REPO_ROOT/scripts/require-deploy-checkout.sh" "$CLONE/scripts/"
  echo one > "$CLONE/file"
  git -C "$CLONE" add .
  git -C "$CLONE" commit -q -m one
  git -C "$CLONE" push -q origin main
}

guard() {
  run bash "$CLONE/scripts/require-deploy-checkout.sh"
}

promote() {
  git -C "$CLONE" push -q origin "$1:refs/heads/deploy"
}

@test "passes when HEAD is exactly origin/deploy" {
  promote HEAD
  guard
  [ "$status" -eq 0 ]
}

@test "refuses when origin has no deploy branch" {
  guard
  [ "$status" -eq 1 ]
  [[ "$output" == *"deploy does not exist"* ]]
}

@test "refuses when HEAD is ahead of origin/deploy" {
  promote HEAD
  echo two > "$CLONE/file"
  git -C "$CLONE" commit -q -am two
  guard
  [ "$status" -eq 1 ]
  [[ "$output" == *"deploy"* ]]
}

@test "refuses when tracked files have uncommitted changes" {
  promote HEAD
  echo dirty > "$CLONE/file"
  guard
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted"* ]]
}

@test "every live installer calls the guard on a real run" {
  grep -q 'require-deploy-checkout.sh' "$REPO_ROOT/stack/install-wsl2.sh"
  grep -q 'require-deploy-checkout.sh' "$REPO_ROOT/stack/install-user-units.sh"
  grep -q 'require-deploy-checkout.sh' "$REPO_ROOT/scripts/syncthing/setup-wsl2.sh"
}
