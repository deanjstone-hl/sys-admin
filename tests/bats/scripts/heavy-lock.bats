#!/usr/bin/env bats
# Host-wide heavy lock (argus-config#1506): two overlapping full checks made systemd-oomd kill
# agent scopes, so scripts/check.sh takes the lock itself, from a copy of argus-config's
# scripts/heavy-lock.sh.

REPO_ROOT="$BATS_TEST_DIRNAME/../../.."
CHECK_SH="$REPO_ROOT/scripts/check.sh"

@test "the vendored heavy-lock.sh matches the sha256 in its lock file" {
  digest="$(sha256sum "$REPO_ROOT/scripts/heavy-lock.sh" | cut -d' ' -f1)"
  grep -q "^${digest}  heavy-lock.sh\$" "$REPO_ROOT/scripts/heavy-lock.lock"
}

@test "check.sh re-runs itself under the lock" {
  grep -q 'heavy-lock.sh' "$CHECK_SH"
  grep -q 'HEAVY_LOCK_HELD' "$CHECK_SH"
}

@test "check.sh gives exit 75 without running a step while the lock is held" {
  lock_file="$BATS_TEST_TMPDIR/heavy.lock"
  stub_bin="$BATS_TEST_TMPDIR/bin"
  step_log="$BATS_TEST_TMPDIR/steps.log"
  mkdir -p "$stub_bin"
  : > "$step_log"
  for tool in bats shellcheck; do
    printf '#!/usr/bin/env bash\necho ran >> "%s"\n' "$step_log" > "$stub_bin/$tool"
    chmod +x "$stub_bin/$tool"
  done

  LOCK_FILE="$lock_file" bash -c 'exec 9>>"$LOCK_FILE"; flock 9; echo held > "$LOCK_FILE.held"; sleep 30' &
  holder=$!
  for _ in $(seq 1 100); do
    [ -f "$lock_file.held" ] && break
    sleep 0.1
  done
  [ -f "$lock_file.held" ]

  run env -u HEAVY_LOCK_HELD HEAVY_LOCK_FILE="$lock_file" HEAVY_LOCK_TIMEOUT=1 \
    HEAVY_LOCK_PSI_FILE="$BATS_TEST_TMPDIR/none" PATH="$stub_bin:$PATH" bash "$CHECK_SH" bats shellcheck
  kill "$holder" 2>/dev/null || true

  [ "$status" -eq 75 ]
  [[ "$output" == *"waiting for the host lock"* ]]
  [ ! -s "$step_log" ]
}
