#!/usr/bin/env bats
# scripts/owner-steps/194.sh: the owner's cutover of this repository to a fresh-history public
# one (sys-admin#194, map homelab#478; the model is skills scripts/owner-steps/27.sh and its
# tests). The owner runs it live: it renames sys-admin to sys-admin-archive, publishes ONE
# squashed commit of the scrubbed tree as a new sys-admin, and moves the open issues, Secrets
# Manager keys and wiring across.
#
# These cases run it in a throwaway checkout against stub `gh` and `bws` programs that serve
# canned state and log every call, so they prove what it would do, and that it prints no value,
# without touching GitHub or Secrets Manager. They need jq, git and gitleaks; a host without
# one skips the file. Every private-looking value is built at run time, so this file holds none.

setup() {
  command -v jq > /dev/null && command -v git > /dev/null && command -v gitleaks > /dev/null || skip "jq, git and gitleaks are needed"
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  WORK="$(mktemp -d)"
  STUB="$WORK/stub"
  BIN="$WORK/bin"
  CHECKOUT="$WORK/checkout"
  mkdir -p "$STUB/fixtures" "$STUB/remotes/deanjstone" "$BIN" "$CHECKOUT"
  build_values
  write_stubs
  build_checkout
  write_fixtures
}

teardown() {
  [ -z "${WORK:-}" ] || rm -rf "$WORK"
}

build_values() {
  local dot="." a="100" b="99"
  IP_WSL="$a$dot$b${dot}98${dot}97"
  IP_LGN5="$a$dot$b${dot}98${dot}96"
  IP_HOMELAB="$a$dot$b${dot}98${dot}95"
  IP_DJ15="$a$dot$b${dot}98${dot}94"
  HOST_WSL="wsl-node${dot}tail9z9z${dot}ts${dot}net"
  HOST_VAULT="vault-node${dot}tail9z9z${dot}ts${dot}net"
  ID_WSL2="$(printf 'AAAAAAA-%.0s' {1..7})AAAAAAA"
  ID_WINDOWS="$(printf 'BBBBBBB-%.0s' {1..7})BBBBBBB"
  ID_DJ15="$(printf 'CCCCCCC-%.0s' {1..7})CCCCCCC"
  LEAK="$a$dot$b${dot}1${dot}2"
  SECRET_VALUE="mapped-secret-VALUE"
  OWNER_EMAIL="owner@example${dot}invalid"
  KEYS="SYS_ADMIN_TAILSCALE_IP_WSL SYS_ADMIN_TAILSCALE_IP_LGN5 SYS_ADMIN_TAILSCALE_IP_HOMELAB SYS_ADMIN_TAILSCALE_IP_DJ15 SYS_ADMIN_TAILSCALE_HOST_WSL SYS_ADMIN_TAILSCALE_HOST_VAULTWARDEN SYS_ADMIN_SYNCTHING_DEVICE_ID_WSL2 SYS_ADMIN_SYNCTHING_DEVICE_ID_WINDOWS SYS_ADMIN_SYNCTHING_DEVICE_ID_DJ15"
}

write_stubs() {
  cat > "$BIN/gh" <<'STUB'
#!/bin/bash
echo "gh $*" >> "$STUB_DIR/calls.log"
fx="$STUB_DIR/fixtures"
repo=""; args=("$@"); for i in "${!args[@]}"; do [ "${args[$i]}" = -R ] && repo=${args[$((i+1))]}; done
case "$1" in
  auth) exit 0 ;;
  api)
    shift
    method=GET; [ "$1" = "-X" ] && { method=$2; shift 2; }
    path=$1
    if [ "$method" = PATCH ] && [ "$path" = "repos/deanjstone/sys-admin" ]; then
      sed 's#deanjstone/sys-admin"#deanjstone/sys-admin-archive"#' "$fx/repo_sys-admin.json" > "$fx/repo_sys-admin-archive.json"
      rm "$fx/repo_sys-admin.json"; touch "$STUB_DIR/renamed"; echo '{}'; exit 0
    fi
    if [ "$method" = PUT ]; then echo ''; exit 0; fi
    case "$path" in
      repos/deanjstone/ops-hub/contents/*) printf '%s' "$HUB_LIST" ;;
      repos/deanjstone/sys-admin|repos/deanjstone/sys-admin-archive)
        name=${path#repos/deanjstone/}; f="$fx/repo_$name.json"
        if [ -f "$f" ]; then cat "$f"; else echo '{"message":"Not Found"}'; exit 1; fi ;;
      repos/deanjstone/sys-admin/branches/main)
        if git -C "$STUB_DIR/remotes/deanjstone/sys-admin.git" rev-parse --verify -q refs/heads/main > /dev/null 2>&1; then echo '{"name":"main"}'; else echo '{"message":"Not Found"}'; exit 1; fi ;;
      */branches/deploy) echo '{"message":"Not Found"}'; exit 1 ;;
      */hooks) cat "$fx/hooks.json" ;;
      */keys) echo '[]' ;;
      */actions/runners) echo '{"total_count":0,"runners":[]}' ;;
      *) echo '{}' ;;
    esac ;;
  repo)
    case "$2" in
      create) touch "$STUB_DIR/created"; echo '{"private":true,"full_name":"deanjstone/sys-admin"}' > "$fx/repo_sys-admin.json"
              git init -q --bare "$STUB_DIR/remotes/deanjstone/sys-admin.git"; echo "https://github.com/deanjstone/sys-admin" ;;
      edit) sed -i 's/"private":true/"private":false/' "$fx/repo_sys-admin.json"; touch "$STUB_DIR/public" ;;
    esac ;;
  label) exit 0 ;;
  secret)
    case "$2" in
      set) cat > "$STUB_DIR/secret_$3.value"; echo "$3" >> "$STUB_DIR/secrets_set.log" ;;
      list) cat "$fx/secrets.json" ;;
    esac ;;
  variable) cat "$fx/variables.json" ;;
  issue)
    case "$2" in
      list)
        if [ "$repo" = deanjstone/sys-admin-archive ] || { [ "$repo" = deanjstone/sys-admin ] && [ ! -f "$STUB_DIR/created" ] && [ ! -f "$STUB_DIR/renamed" ]; }; then
          if [ -f "$STUB_DIR/transferred" ]; then echo '[{"number":194},{"number":195}]'; else cat "$fx/issues.json"; fi
        elif [ -f "$STUB_DIR/transferred" ]; then jq -R '{number: (tonumber + 1000)}' "$STUB_DIR/transfers.log" | jq -s .
        else echo '[]'; fi ;;
      view) n=$3; [ "$n" -gt 1000 ] && n=$((n-1000)); cat "$fx/issue_$n.json" ;;
      transfer) touch "$STUB_DIR/transferred"; echo "$3" >> "$STUB_DIR/transfers.log"; echo "https://github.com/deanjstone/sys-admin/issues/$((${3}+1000))" ;;
    esac ;;
esac
exit 0
STUB
  cat > "$BIN/bws" <<'STUB'
#!/bin/bash
[ -n "${BWS_ACCESS_TOKEN:-}" ] || { echo "Missing access token" >&2; exit 1; }
echo "bws $1 $2" >> "$STUB_DIR/calls.log"
sub="$1 $2"; shift 2
case "$sub" in
  "secret list") cat "$STUB_DIR/bws_list.json" ;;
  "secret create")
    key=${@: -3:1}; value=${@: -2:1}; project=${@: -1}
    echo "$key $project" >> "$STUB_DIR/bws_created.log"
    printf '%s' "$value" > "$STUB_DIR/bws_value_$key"
    jq --arg k "$key" --arg p "$project" '. + [{key: $k, id: ("id-" + $k), projectId: $p, value: "x"}]' "$STUB_DIR/bws_list.json" > "$STUB_DIR/bws_list.next" && mv "$STUB_DIR/bws_list.next" "$STUB_DIR/bws_list.json" ;;
esac
exit 0
STUB
  chmod +x "$BIN/gh" "$BIN/bws"
}

# A checkout with two commits: the old tree carrying the values, then the scrubbed one.
build_checkout() {
  local origin="$WORK/origin.git"
  git -C "$CHECKOUT" init -q -b main
  git -C "$CHECKOUT" config user.name Owner
  git -C "$CHECKOUT" config user.email "$OWNER_EMAIL"
  mkdir -p "$CHECKOUT/scripts/owner-steps" "$CHECKOUT/scripts/syncthing" "$CHECKOUT/stack/config/wsl2/systemd"
  cp "$REPO_ROOT/scripts/owner-steps/194.sh" "$CHECKOUT/scripts/owner-steps/194.sh"
  cp "$REPO_ROOT/scripts/scrub-scan.sh" "$CHECKOUT/scripts/scrub-scan.sh"
  cp "$REPO_ROOT/.gitleaks.toml" "$CHECKOUT/.gitleaks.toml"
  cat > "$CHECKOUT/scripts/syncthing/pair-device.sh" <<EOF
API_URL="\${SYNCTHING_API_URL:-https://$IP_HOMELAB:8384}"
declare -A KNOWN_DEVICES=(
  [wsl2]="$ID_WSL2"
  [windows]="$ID_WINDOWS"
  [dj15]="$ID_DJ15"
)
declare -A DEVICE_ADDRESSES=(
  [wsl2]="tcp://$IP_WSL:22001"
  [windows]="tcp://$IP_LGN5:22000"
  [dj15]="tcp://$IP_DJ15:22000"
)
EOF
  echo "echo \"    GUI (remote): https://$HOST_WSL:8384\"" > "$CHECKOUT/scripts/syncthing/setup-wsl2.sh"
  echo "# Environment=DOMAIN=https://$HOST_VAULT" > "$CHECKOUT/stack/config/wsl2/systemd/vaultwarden.service"
  git -C "$CHECKOUT" add -A
  git -C "$CHECKOUT" commit -q -m "feat: first"
  PRE_REF="$(git -C "$CHECKOUT" rev-parse HEAD)"
  echo "see the key names in .env.example" > "$CHECKOUT/scripts/syncthing/pair-device.sh"
  echo "echo done" > "$CHECKOUT/scripts/syncthing/setup-wsl2.sh"
  echo "# no value here" > "$CHECKOUT/stack/config/wsl2/systemd/vaultwarden.service"
  if [ "${SCRUB_FAILS:-0}" = 1 ]; then echo "host $LEAK" > "$CHECKOUT/leak.txt"; else echo clean > "$CHECKOUT/ok.txt"; fi
  git -C "$CHECKOUT" add -A
  git -C "$CHECKOUT" commit -q -m "chore: scrub"
  git init -q --bare -b main "$origin"
  git -C "$CHECKOUT" remote add origin "$origin"
  git -C "$CHECKOUT" push -q origin main
  git -C "$CHECKOUT" fetch -q origin
}

write_fixtures() {
  local fx="$STUB/fixtures" key
  local listing='[{"key":"syncthing-device-homelab","id":"id-anchor","projectId":"proj-personal","value":"anchor-VALUE"},{"key":"mapped-bws-key","id":"id-mapped","projectId":"proj-personal","value":"'"$SECRET_VALUE"'"}]'
  for key in ${PRESENT_KEYS:-}; do
    listing="$(jq --arg k "$key" '. + [{key: $k, id: ("id-" + $k), projectId: "proj-personal", value: "v"}]' <<< "$listing")"
  done
  echo "$listing" > "$STUB/bws_list.json"
  echo '[{"id":"proj-personal","name":"personal-machine-secrets"}]' > "$STUB/bws_projects.json"
  if [ "${RENAMED:-0}" = 1 ]; then
    echo '{"private":true,"full_name":"deanjstone/sys-admin-archive","description":"A test description."}' > "$fx/repo_sys-admin-archive.json"
    touch "$STUB/renamed"
  else
    echo '{"private":true,"full_name":"deanjstone/sys-admin","description":"A test description."}' > "$fx/repo_sys-admin.json"
  fi
  echo '[{"number":196},{"number":195},{"number":194},{"number":190}]' > "$fx/issues.json"
  local n body
  for n in 190 194 195 196; do
    body="plain text"
    [ "$n" = "${DIRTY_ISSUE:-0}" ] && body="host $LEAK"
    jq -n --arg t "issue $n" --arg b "$body" '{title: $t, body: $b, comments: []}' > "$fx/issue_$n.json"
  done
  echo "${ACTIONS_SECRET_NAMES:-[]}" > "$fx/secrets.json"
  echo '[{"name":"CI_RUNS_ON"}]' > "$fx/variables.json"
  echo '[]' > "$fx/hooks.json"
  printf 'BWS_ACCESS_TOKEN=machine-token\n' > "$WORK/bws_token"
}

run_step() {
  HUB_LIST=$'# the hub list\ndeanjstone/homelab\ndeanjstone/sys-admin\n' \
  PATH="$BIN:$PATH" HOME="$WORK" STUB_DIR="$STUB" \
  SYS_ADMIN_BWS_TOKEN_FILE="$WORK/bws_token" \
  SYS_ADMIN_PRE_SCRUB_REF="$PRE_REF" \
  SYS_ADMIN_GIT_REMOTE_BASE="file://$STUB/remotes" \
  SYS_ADMIN_ACTIONS_SECRETS="${MAPPING:-}" \
    run bash -c 'cd "$1" && shift && exec bash scripts/owner-steps/194.sh "$@"' _ "$CHECKOUT" "$@"
}

calls() { cat "$STUB/calls.log" 2> /dev/null || true; }

assert_no_value() {
  local value
  for value in "$IP_WSL" "$IP_LGN5" "$IP_HOMELAB" "$IP_DJ15" "$HOST_WSL" "$HOST_VAULT" "$ID_WSL2" "$ID_WINDOWS" "$ID_DJ15" "$LEAK" "$SECRET_VALUE" "$OWNER_EMAIL"; do
    [[ "$output" != *"$value"* ]] || { echo "a value was printed: ${value:0:6}..."; return 1; }
  done
}

@test "it rejects an unknown argument" {
  run_step --bogus
  [ "$status" -eq 2 ]
}

@test "--dry-run prints every action, changes nothing and prints no value" {
  run_step --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"pre-flight ok: the scrubbed tree passes the scrub scan"* ]]
  for action in \
    "rename deanjstone/sys-admin to sys-admin-archive" \
    "create deanjstone/sys-admin as a PRIVATE repository" \
    "transfer the open issues" \
    "make deanjstone/sys-admin public" \
    "fork pull-request approval policy" \
    "CI_RUNS_ON" \
    "OPS_HUB_PROMOTION_REPOS" \
    "jit-dispatcher.json" \
    "local checkouts to re-clone"; do
    [[ "$output" == *"$action"* ]] || { echo "missing: $action"; echo "$output"; return 1; }
  done
  for key in $KEYS; do
    [[ "$output" == *"Secrets Manager $key: create"* ]] || { echo "missing key: $key"; return 1; }
  done
  [[ "$output" == *"done: nothing was changed"* ]]
  assert_no_value
  # Only reads: no rename, create, edit, transfer, secret set, bws create or PUT.
  [ "$(calls | grep -cE 'api -X (PATCH|PUT|POST)|repo create|repo edit|label clone|secret set|issue transfer|bws secret create')" -eq 0 ]
  [ ! -e "$STUB/bws_created.log" ]
  [ ! -d "$STUB/remotes/deanjstone/sys-admin.git" ]
}

@test "--dry-run reports the hub list and that the kept cutover issues stay" {
  run_step --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPS_HUB_PROMOTION_REPOS"*"deanjstone/sys-admin"* ]]
  [[ "$output" == *"skip 194 195"* ]]
}

@test "--dry-run stops with nothing changed when the scrubbed tree still has a finding" {
  SCRUB_FAILS=1 setup_again
  run_step --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"pre-flight FAILED: the scrubbed tree passes the scrub scan"* ]]
  [[ "$output" == *"nothing was changed"* ]]
  assert_no_value
}

setup_again() {
  rm -rf "$CHECKOUT" "$STUB"
  mkdir -p "$STUB/fixtures" "$STUB/remotes/deanjstone" "$CHECKOUT"
  rm -rf "$WORK/origin.git"
  build_checkout
  write_fixtures
}

@test "--dry-run lists a missing owner step: an Actions secret with no Secrets Manager source" {
  ACTIONS_SECRET_NAMES='[{"name":"DEPLOY_TOKEN"}]' setup_again
  run_step --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-flight MISSING (owner step before the real run): Actions secret DEPLOY_TOKEN has a Secrets Manager source"* ]]
  [[ "$output" == *"Owner steps before the real run"* ]]
}

@test "a real run does the cutover in order, creates every key, never pushes deploy and prints no value" {
  run_step
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  assert_no_value
  log="$(calls)"
  # order: rename, then create, then public last
  rename_line="$(grep -n 'api -X PATCH repos/deanjstone/sys-admin -f name=sys-admin-archive' <<< "$log" | head -1 | cut -d: -f1)"
  create_line="$(grep -n 'repo create deanjstone/sys-admin' <<< "$log" | head -1 | cut -d: -f1)"
  public_line="$(grep -n 'repo edit deanjstone/sys-admin --visibility public' <<< "$log" | head -1 | cut -d: -f1)"
  transfer_line="$(grep -n 'issue transfer' <<< "$log" | head -1 | cut -d: -f1)"
  [ -n "$rename_line" ] && [ -n "$create_line" ] && [ -n "$public_line" ] && [ -n "$transfer_line" ]
  [ "$rename_line" -lt "$create_line" ]
  [ "$create_line" -lt "$transfer_line" ]
  [ "$transfer_line" -lt "$public_line" ]
  # every key created, in the project of the anchor secret, with the right value
  for key in $KEYS; do grep -qx "$key proj-personal" "$STUB/bws_created.log"; done
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_TAILSCALE_IP_WSL")" = "$IP_WSL" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_TAILSCALE_IP_LGN5")" = "$IP_LGN5" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_TAILSCALE_IP_HOMELAB")" = "$IP_HOMELAB" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_TAILSCALE_IP_DJ15")" = "$IP_DJ15" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_TAILSCALE_HOST_WSL")" = "$HOST_WSL" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_TAILSCALE_HOST_VAULTWARDEN")" = "$HOST_VAULT" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_SYNCTHING_DEVICE_ID_WSL2")" = "$ID_WSL2" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_SYNCTHING_DEVICE_ID_WINDOWS")" = "$ID_WINDOWS" ]
  [ "$(cat "$STUB/bws_value_SYS_ADMIN_SYNCTHING_DEVICE_ID_DJ15")" = "$ID_DJ15" ]
  # the kept issues stay, the others move
  [ "$(sort "$STUB/transfers.log" | tr '\n' ' ')" = "190 196 " ]
  # one squashed commit on main, no deploy branch, and no value in it
  remote="$STUB/remotes/deanjstone/sys-admin.git"
  [ "$(git -C "$remote" rev-list --count refs/heads/main)" -eq 1 ]
  [ "$(git -C "$remote" branch --list deploy | wc -l)" -eq 0 ]
  [ "$(git -C "$remote" grep -c "$IP_WSL" refs/heads/main || true)" = "" ]
  # public, with the fork approval policy
  [ -e "$STUB/public" ]
  grep -q 'actions/permissions/fork-pr-contributor-approval -f approval_policy=all_external_contributors' <<< "$log"
}

@test "a real run stops before the repository goes public when a transferred issue holds a value" {
  DIRTY_ISSUE=190 setup_again
  run_step
  [ "$status" -eq 3 ]
  [ ! -e "$STUB/public" ]
  [[ "$output" == *"issue 1190: 1 finding(s)"* ]]
  assert_no_value
}

@test "a second run after a stop is idempotent: no second rename, create or key" {
  run_step
  [ "$status" -eq 0 ]
  : > "$STUB/calls.log"
  rm -f "$STUB/bws_created.log"
  run_step
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(calls | grep -cE 'api -X PATCH|repo create|bws secret create')" -eq 0 ]
  [ ! -e "$STUB/bws_created.log" ]
  [[ "$output" == *"already set, left as is"* ]]
}

@test "a real run sets a mapped Actions secret from Secrets Manager through stdin" {
  ACTIONS_SECRET_NAMES='[{"name":"DEPLOY_TOKEN"}]' setup_again
  MAPPING="DEPLOY_TOKEN=mapped-bws-key" run_step
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(cat "$STUB/secret_DEPLOY_TOKEN.value")" = "$SECRET_VALUE" ]
  [ "$(calls | grep -c "$SECRET_VALUE")" -eq 0 ]
  assert_no_value
}
