#!/usr/bin/env bats
# Baseline coverage for stack/check-drift.sh — a read-only reporter, so per
# the strategy resolved in deanjstone/sys-admin#15 external commands (apt,
# fnm, systemctl) are mocked via PATH rather than relying on the real system
# state, and REPO_DIR/HOME are pointed at an isolated fixture.

REAL_REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"

setup() {
  FIXTURE="$(mktemp -d)"
  FIXTURE_HOME="$(mktemp -d)"

  cp "$REAL_REPO_DIR/stack/check-drift.sh" "$FIXTURE/check-drift.sh"
  mkdir -p "$FIXTURE/config/wsl2/zellij" "$FIXTURE/config/wsl2/systemd" "$FIXTURE/bin"

  echo "bash" > "$FIXTURE/config/wsl2/packages.txt"
  echo "coreutils" >> "$FIXTURE/config/wsl2/packages.txt"
  echo "20.11.0" > "$FIXTURE/config/wsl2/fnm-versions"

  echo "// fixture zellij config" > "$FIXTURE/config/wsl2/zellij/config.kdl"
  echo "[Unit]" > "$FIXTURE/config/wsl2/systemd/fixture.service"

  cat > "$FIXTURE/bin/apt" <<'EOF'
#!/usr/bin/env bash
echo "Listing..."
echo "bash/stable,now 5.1 amd64 [installed]"
echo "coreutils/stable,now 8.32 amd64 [installed]"
EOF
  chmod +x "$FIXTURE/bin/apt"

  cat > "$FIXTURE/bin/fnm" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "current" ]] && echo "v20.11.0"
EOF
  chmod +x "$FIXTURE/bin/fnm"

  # Every unit reports active unless listed in $INACTIVE_UNITS
  cat > "$FIXTURE/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "is-active" ]] || exit 0
if [[ " ${INACTIVE_UNITS:-} " == *" $2 "* ]]; then echo failed; exit 3; fi
echo active
EOF
  chmod +x "$FIXTURE/bin/systemctl"

  mkdir -p "$FIXTURE_HOME/.config/zellij"
}

teardown() {
  rm -rf "$FIXTURE" "$FIXTURE_HOME"
}

link_all_clean() {
  ln -sf "$FIXTURE/config/wsl2/zellij/config.kdl" "$FIXTURE_HOME/.config/zellij/config.kdl"
}

@test "check-drift.sh reports no drift when everything matches" {
  link_all_clean
  PATH="$FIXTURE/bin:$PATH" HOME="$FIXTURE_HOME" run "$FIXTURE/check-drift.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no drift detected"* ]]
}

@test "check-drift.sh detects a missing symlink" {
  # zellij config intentionally left missing

  PATH="$FIXTURE/bin:$PATH" HOME="$FIXTURE_HOME" run "$FIXTURE/check-drift.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"zellij"*"missing"* ]]
}

@test "check-drift.sh leaves argus-config-owned dotfiles alone (sys-admin#120)" {
  link_all_clean
  # Correct LGN5 state: these link into argus-config, not this repo
  ln -sf /dev/null "$FIXTURE_HOME/.gitconfig"
  ln -sf /dev/null "$FIXTURE_HOME/.tmux.conf"

  PATH="$FIXTURE/bin:$PATH" HOME="$FIXTURE_HOME" run "$FIXTURE/check-drift.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"gitconfig"* ]]
  [[ "$output" != *"tmux.conf"* ]]
  [[ "$output" != *"dev.sh"* ]]
}

@test "check-drift.sh reports a declared systemd unit that is not active (sys-admin#121)" {
  link_all_clean

  INACTIVE_UNITS="fixture.service" PATH="$FIXTURE/bin:$PATH" HOME="$FIXTURE_HOME" run "$FIXTURE/check-drift.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fixture.service"*"failed"* ]]
}

@test "check-drift.sh detects an undeclared-vs-installed apt package mismatch" {
  link_all_clean
  echo "definitely-not-a-real-package" >> "$FIXTURE/config/wsl2/packages.txt"

  PATH="$FIXTURE/bin:$PATH" HOME="$FIXTURE_HOME" run "$FIXTURE/check-drift.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"definitely-not-a-real-package"*"not installed"* ]]
}
