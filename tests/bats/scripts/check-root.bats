#!/usr/bin/env bats
# scripts/check.sh must check this repo's own tree whatever directory it is called from
# (sys-admin#193): another repo's pre-push gate runs it from its own checkout. Stub bats and
# shellcheck on PATH record the directory each step runs in, so the test never recurses into
# the real suites.

CHECK_SH="$BATS_TEST_DIRNAME/../../../scripts/check.sh"

setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STEP_LOG="$BATS_TEST_TMPDIR/step-dirs.log"
  mkdir -p "$STUB_BIN"
  : > "$STEP_LOG"
  for tool in bats shellcheck; do
    printf '#!/usr/bin/env bash\npwd -P >> "%s"\n' "$STEP_LOG" > "$STUB_BIN/$tool"
    chmod +x "$STUB_BIN/$tool"
  done
  REAL_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd -P)"
}

check_from() {
  cd "$1"
  PATH="$STUB_BIN:$PATH" run bash "$CHECK_SH" bats shellcheck
}

@test "check.sh checks this repo's tree when run from another git repo" {
  other="$BATS_TEST_TMPDIR/other-repo"
  git init -q -b main "$other"
  git -C "$other" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "chore: init"
  other_sha="$(git -C "$other" rev-parse --short HEAD)"
  own_sha="$(git -C "$REAL_ROOT" rev-parse --short HEAD)"

  check_from "$other"

  [ "$status" -eq 0 ]
  [ "$(sort -u "$STEP_LOG")" = "$REAL_ROOT" ]
  [ "$(wc -l < "$STEP_LOG")" -eq 2 ]
  [[ "$output" == *"check: pass $own_sha" ]]
  [[ "$output" != *"$other_sha"* ]]
}

@test "check.sh checks this repo's tree when run from outside any repo" {
  outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$outside"

  check_from "$outside"

  [ "$status" -eq 0 ]
  [ "$(sort -u "$STEP_LOG")" = "$REAL_ROOT" ]
}
