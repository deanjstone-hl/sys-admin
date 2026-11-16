#!/usr/bin/env bats
# scripts/syncthing/reset-gui-password.sh (sys-admin#104). Every test runs
# against a throwaway Syncthing config generated into a temp dir — never a
# live instance. systemctl and bw are stubbed on PATH.

REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
SCRIPT="$REPO_DIR/scripts/syncthing/reset-gui-password.sh"
PASSWORD='correct horse battery staple'

setup() {
  command -v syncthing >/dev/null || skip "syncthing not installed"
  CONFIG_DIR="$(mktemp -d)"
  STUB_DIR="$(mktemp -d)"
  syncthing generate --home="$CONFIG_DIR" --no-port-probing >/dev/null 2>&1
  BEFORE_ID="$(grep -o '<device id="[^"]*"' "$CONFIG_DIR/config.xml" | head -1)"
  BEFORE_APIKEY="$(grep -o '<apikey>[^<]*' "$CONFIG_DIR/config.xml")"

  # systemctl stub: records every call; is-active answers from $STUB_ACTIVE.
  cat > "$STUB_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$STUB_LOG"
if [[ " $* " == *" is-active "* ]]; then [[ "${STUB_ACTIVE:-no}" == yes ]]; exit; fi
exit 0
EOF
  chmod +x "$STUB_DIR/systemctl"
  export STUB_LOG="$STUB_DIR/systemctl.log"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "${CONFIG_DIR:-}" "${STUB_DIR:-}"
}

gui_password_hash() {
  grep -oP '(?<=<password>)[^<]+' "$CONFIG_DIR/config.xml"
}

hash_matches() {
  python3 -W ignore -c 'import crypt, sys; sys.exit(crypt.crypt(sys.argv[1], sys.argv[2]) != sys.argv[2])' "$1" "$2"
}

@test "writes a bcrypt hash of the stdin password into <gui>" {
  run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR'"
  [ "$status" -eq 0 ]
  hash="$(gui_password_hash)"
  [[ "$hash" == '$2'[ab]'$'* ]]
  hash_matches "$PASSWORD" "$hash"
}

@test "never prints the password or its hash" {
  run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$PASSWORD"* ]]
  [[ "$output" != *"$(gui_password_hash)"* ]]
}

@test "keeps the device identity and API key" {
  run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR'"
  [ "$status" -eq 0 ]
  [ "$(grep -o '<device id="[^"]*"' "$CONFIG_DIR/config.xml" | head -1)" = "$BEFORE_ID" ]
  [ "$(grep -o '<apikey>[^<]*' "$CONFIG_DIR/config.xml")" = "$BEFORE_APIKEY" ]
}

@test "--user sets the GUI user name" {
  run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR' --user admin"
  [ "$status" -eq 0 ]
  grep -q '<user>admin</user>' "$CONFIG_DIR/config.xml"
}

@test "rejects an empty password and leaves config.xml untouched" {
  before="$(sha256sum < "$CONFIG_DIR/config.xml")"
  run bash -c "printf '\n' | '$SCRIPT' --config '$CONFIG_DIR'"
  [ "$status" -ne 0 ]
  [ "$(sha256sum < "$CONFIG_DIR/config.xml")" = "$before" ]
}

@test "refuses a directory with no config.xml rather than generating a new identity" {
  empty_dir="$(mktemp -d)"
  run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$empty_dir'"
  [ "$status" -ne 0 ]
  [ -z "$(ls -A "$empty_dir")" ]
  rm -rf "$empty_dir"
}

@test "rejects a literal password argument" {
  run "$SCRIPT" --config "$CONFIG_DIR" --password "$PASSWORD"
  [ "$status" -ne 0 ]
  [[ "$output" != *"$PASSWORD"* ]]
}

@test "--bw-item reads the password from Bitwarden" {
  cat > "$STUB_DIR/bw" <<EOF
#!/usr/bin/env bash
[[ "\$1 \$2 \$3" == "get password syncthing-gui" ]] && [[ " \$* " == *" --session stub-session "* ]] || exit 1
printf '%s' '$PASSWORD'
EOF
  chmod +x "$STUB_DIR/bw"
  BW_SESSION=stub-session run "$SCRIPT" --config "$CONFIG_DIR" --bw-item syncthing-gui < /dev/null
  [ "$status" -eq 0 ]
  hash_matches "$PASSWORD" "$(gui_password_hash)"
  [[ "$output" != *"$PASSWORD"* ]]
}

@test "stops and restarts an active service around the write" {
  STUB_ACTIVE=yes run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR' --service syncthing.service"
  [ "$status" -eq 0 ]
  grep -qx -- '--user stop syncthing.service' "$STUB_LOG"
  grep -qx -- '--user start syncthing.service' "$STUB_LOG"
}

@test "does not start a service that was not running" {
  STUB_ACTIVE=no run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR'"
  [ "$status" -eq 0 ]
  run grep -q -- ' start ' "$STUB_LOG"
  [ "$status" -ne 0 ]
}

@test "--no-restart refuses while the service is running" {
  before="$(sha256sum < "$CONFIG_DIR/config.xml")"
  STUB_ACTIVE=yes run bash -c "printf '%s\n' '$PASSWORD' | '$SCRIPT' --config '$CONFIG_DIR' --no-restart"
  [ "$status" -ne 0 ]
  [ "$(sha256sum < "$CONFIG_DIR/config.xml")" = "$before" ]
}
