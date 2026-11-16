#!/usr/bin/env bats
# stack/install-user-units.sh installs the WSL2 user-scope units and drop-ins
# from stack/config/wsl2/systemd-user/ into ~/.config/systemd/user/.
# deanjstone/sys-admin#165 (argus-config#640): a unit was a
# symlink into argus-config, so a plain `cp` would write through the link and
# overwrite the file in the other repo. HOME is a tmpdir and systemctl is a
# stub, so nothing touches the real user manager.

REAL_REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

setup() {
  # Mirrors the repo: the installer finds scripts/require-deploy-checkout.sh at ../scripts.
  FIXTURE_ROOT="$(mktemp -d)"
  FIXTURE="$FIXTURE_ROOT/stack"
  TEST_HOME="$(mktemp -d)"
  OTHER_REPO="$(mktemp -d)"
  SRC="$FIXTURE/config/wsl2/systemd-user"
  DST="$TEST_HOME/.config/systemd/user"

  mkdir -p "$FIXTURE/bin" "$SRC/demo.service.d" "$FIXTURE_ROOT/scripts"
  # The deploy guard is a stub that logs its call; its own tests are in release-deploy-guard.bats.
  GUARD_LOG="$TEST_HOME/guard.log"
  printf '#!/usr/bin/env bash\necho called >> "%s"\n[[ "${GUARD_FAIL:-}" != 1 ]]\n' "$GUARD_LOG" \
    > "$FIXTURE_ROOT/scripts/require-deploy-checkout.sh"
  cp "$REAL_REPO_DIR/stack/install-user-units.sh" "$FIXTURE/install-user-units.sh"
  printf '[Unit]\nDescription=fixture\n\n[Service]\nExecStart=/bin/true\n\n[Install]\nWantedBy=default.target\n' \
    > "$SRC/demo.service"
  printf '[Service]\nEnvironment=PATH=/x\n' > "$SRC/demo.service.d/10-path.conf"

  cat > "$FIXTURE/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${SYSTEMCTL_LOG}"
exit 0
EOF
  chmod +x "$FIXTURE/bin/systemctl"
  export SYSTEMCTL_LOG="$TEST_HOME/systemctl.log"
  : > "$SYSTEMCTL_LOG"
  export PATH="$FIXTURE/bin:$PATH"
}

teardown() {
  rm -rf "$FIXTURE_ROOT" "$TEST_HOME" "$OTHER_REPO"
}

install_units() {
  HOME="$TEST_HOME" run "$FIXTURE/install-user-units.sh" "$@"
}

@test "installs a unit and a drop-in as real files" {
  install_units
  [ "$status" -eq 0 ]
  [ -f "$DST/demo.service" ] && [ ! -L "$DST/demo.service" ]
  [ -f "$DST/demo.service.d/10-path.conf" ] && [ ! -L "$DST/demo.service.d/10-path.conf" ]
  cmp "$SRC/demo.service" "$DST/demo.service"
}

@test "replaces a symlink into another repo without writing through it" {
  mkdir -p "$DST"
  printf 'OLD ARGUS-CONFIG CONTENT\n' > "$OTHER_REPO/demo.service"
  ln -s "$OTHER_REPO/demo.service" "$DST/demo.service"

  install_units
  [ "$status" -eq 0 ]
  [ ! -L "$DST/demo.service" ]
  cmp "$SRC/demo.service" "$DST/demo.service"
  [ "$(cat "$OTHER_REPO/demo.service")" = "OLD ARGUS-CONFIG CONTENT" ]
}

@test "leaves an identical real file untouched" {
  mkdir -p "$DST"
  cp "$SRC/demo.service" "$DST/demo.service"
  touch -d '2020-01-01 00:00:00' "$DST/demo.service"
  before="$(stat -c %Y "$DST/demo.service")"

  install_units
  [ "$status" -eq 0 ]
  [ "$(stat -c %Y "$DST/demo.service")" = "$before" ]
  [[ "$output" == *"demo.service: unchanged"* ]]
}

@test "reloads the user manager but never restarts or starts a unit" {
  install_units
  [ "$status" -eq 0 ]
  grep -q -- '--user daemon-reload' "$SYSTEMCTL_LOG"
  ! grep -q -E 'restart|start|stop|--now' "$SYSTEMCTL_LOG"
}

@test "--dry-run writes nothing and does not call systemctl" {
  install_units --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$DST" ]
  [ ! -s "$SYSTEMCTL_LOG" ]
  [[ "$output" == *"[dry-run]"*"demo.service"* ]]
}

@test "install-wsl2.sh calls install-user-units.sh" {
  grep -q 'install-user-units.sh' "$REAL_REPO_DIR/stack/install-wsl2.sh"
}

@test "a real run asks the deploy guard first and installs nothing when it refuses" {
  GUARD_FAIL=1 install_units
  [ "$status" -ne 0 ]
  [ -s "$GUARD_LOG" ]
  [ ! -e "$DST" ]
}

@test "--dry-run skips the deploy guard" {
  install_units --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$GUARD_LOG" ]
}
