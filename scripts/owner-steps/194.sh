#!/usr/bin/env bash
# Owner step for sys-admin#194 (map homelab#478): cut sys-admin over to a fresh-history PUBLIC
# repository. Read docs/public-cutover.md first. Modelled on deanjstone/skills
# scripts/owner-steps/27.sh (skills#27).
#
# Run on WSL2, from an approval thread or a terminal, as ONE approved command, from a checkout
# of main at the merged commit (clean, equal to origin/main):
#   bash scripts/owner-steps/194.sh --dry-run    # read state, print every action, change nothing
#   bash scripts/owner-steps/194.sh
#
# What it does, in this order. Each step checks the state first, so a run that stopped can be
# run again (idempotent):
#   1. Renames deanjstone/sys-admin to sys-admin-archive. It stays PRIVATE. GitHub redirects
#      the old name only until a repository is created under it again, which step 3 does on
#      purpose.
#   2. Writes the nine private values this repository used to carry in its text (four Tailscale
#      addresses, two MagicDNS names, three Syncthing device ids) into Bitwarden Secrets
#      Manager (BWS), under the key names in .env.example, from the last commit of the old
#      history that still held them (SYS_ADMIN_PRE_SCRUB_REF), into the project of the existing
#      `syncthing-device-homelab` secret. An existing secret is left as it is.
#   3. Creates deanjstone/sys-admin as a PRIVATE repository from ONE squashed commit of the
#      scrubbed tree at main (scripts/scrub-scan.sh must pass on it) and pushes main. It is
#      private first because GitHub cannot transfer an issue from a private repository to a
#      public one (skills#27 found this; the GitHub docs on visibility do not mention it).
#   4. Clones the labels (a transferred issue keeps a label only if the target has it) and sets
#      the Actions secrets named in SYS_ADMIN_ACTIONS_SECRETS from BWS. Today there are none:
#      the workflows use only the read-only GITHUB_TOKEN, so BWS_ACCESS_TOKEN is deliberately
#      not created. The variable CI_RUNS_ON is not recreated (the workflows run on
#      ubuntu-latest and a guard test forbids the variable).
#   5. Transfers the open issues from sys-admin-archive (gh issue transfer), oldest first,
#      except those named in SYS_ADMIN_KEEP_ISSUES (default "194 195": the cutover's own
#      ticket and the diagrams ticket the orchestrator closes).
#   6. Scans the transferred issues' text with the scrub rules. Any hit stops the run BEFORE
#      the repository goes public (exit 3): edit those issues, then run this script again.
#   7. Makes deanjstone/sys-admin public and sets the fork pull-request approval policy to
#      all_external_contributors.
#   8. Prints the wiring to re-point and the local checkouts to re-clone on both hosts,
#      including the hub's OPS_HUB_PROMOTION_REPOS list (read-only check here).
# It never pushes `deploy`, never runs promote.sh and never starts a workflow: the first
# promotion creates `deploy` in the new repository.
#
# Secrets: read inside this script from BWS, never printed, logged or put in a gh argument
# (`gh secret set` reads its value from stdin). `bws` 2.1.0 has no stdin form for a value, so
# a value being stored is in that one `bws` process's arguments for a moment, visible only to
# this user on this host. It prints only names, ids and counts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OWNER="${SYS_ADMIN_OWNER:-deanjstone}"
REPO="sys-admin"
ARCHIVE="sys-admin-archive"
SOURCE_REF="${SYS_ADMIN_SOURCE_REF:-origin/main}"
# The last commit of the old history that still carries the private values (the parent of the scrub).
PRE_SCRUB_REF="${SYS_ADMIN_PRE_SCRUB_REF:-6710bb1c0809182ac8bf2e819b0d50f14b928af2}"
BWS_TOKEN_FILE="${SYS_ADMIN_BWS_TOKEN_FILE:-$HOME/.bws_token}"
KEEP_ISSUES="${SYS_ADMIN_KEEP_ISSUES:-194 195}"
REMOTE_BASE="${SYS_ADMIN_GIT_REMOTE_BASE:-https://github.com}"
HUB_REPO="${SYS_ADMIN_HUB_REPO:-ops-hub}"
HUB_LIST_PATH="apps/ops-hub/promotion-repos.txt"
# "NAME=bws-key" pairs: an Actions secret on the old repository and the BWS secret holding its value.
ACTIONS_SECRETS="${SYS_ADMIN_ACTIONS_SECRETS:-}"

ANCHOR_KEY="syncthing-device-homelab"
VALUE_KEYS=(
  SYS_ADMIN_TAILSCALE_IP_WSL SYS_ADMIN_TAILSCALE_IP_LGN5 SYS_ADMIN_TAILSCALE_IP_HOMELAB SYS_ADMIN_TAILSCALE_IP_DJ15
  SYS_ADMIN_TAILSCALE_HOST_WSL SYS_ADMIN_TAILSCALE_HOST_VAULTWARDEN
  SYS_ADMIN_SYNCTHING_DEVICE_ID_WSL2 SYS_ADMIN_SYNCTHING_DEVICE_ID_WINDOWS SYS_ADMIN_SYNCTHING_DEVICE_ID_DJ15
)
IP_RE='100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}'
HOST_RE='[a-z0-9-]+(\.[a-z0-9-]+)*\.ts\.net'
ID_RE='[A-Z2-7]{7}(-[A-Z2-7]{7}){7}'

DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "usage: $0 [--dry-run]" >&2; exit 2; }

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
want() { if [ "$DRY_RUN" -eq 1 ]; then echo "[dry-run] $*"; else echo "plan: $*"; fi; }
did() { echo "+ $*"; }

secrets="" project_id=""
export_dir=""
cleanup() { [ -z "$export_dir" ] || rm -rf "$export_dir"; }
trap cleanup EXIT

secret_id() { jq -r --arg k "$1" '[.[] | select(.key == $k)][0].id // empty' <<< "$secrets"; }
secret_value() { jq -r --arg k "$1" '[.[] | select(.key == $k)][0].value // empty' <<< "$secrets"; }
secret_set() { [ -n "$(secret_id "$1")" ]; }

repo_json() { gh api "repos/$OWNER/$1" 2> /dev/null || true; }
repo_full_name() { jq -r '.full_name // empty' <<< "$(repo_json "$1")" | tr '[:upper:]' '[:lower:]'; }
repo_is_private() { [ "$(jq -r '.private // empty' <<< "$(repo_json "$1")")" = "true" ]; }
new_repo_exists() { [ "$(repo_full_name "$REPO")" = "$OWNER/$REPO" ]; }
archive_exists() { [ "$(repo_full_name "$ARCHIVE")" = "$OWNER/$ARCHIVE" ]; }

# ---- pre-flight: read-only, also under --dry-run -------------------------------------------

preflight_failed=0
preflight_need() {
  local description="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "pre-flight ok: $description"
  else
    echo "pre-flight FAILED: $description" >&2
    preflight_failed=1
  fi
}

# owner_need: a prerequisite only the owner can supply. A dry run lists it and carries on, so the
# plan still prints; a real run stops.
owner_missing=0
owner_notes=()
owner_need() {
  local description="$1" note="$2"; shift 2
  if "$@" > /dev/null 2>&1; then
    echo "pre-flight ok: $description"
  elif [ "$DRY_RUN" -eq 1 ]; then
    echo "pre-flight MISSING (owner step before the real run): $description"
    owner_missing=1
    owner_notes+=("$note")
  else
    echo "pre-flight FAILED: $description" >&2
    preflight_failed=1
  fi
}

have_tools() {
  local tool
  for tool in gh git jq bws gitleaks tar; do command -v "$tool" > /dev/null || return 1; done
}
gh_authenticated() { gh auth status; }
source_is_clean_and_current() {
  [ -z "$(git -C "$ROOT" status --porcelain)" ] || return 1
  git -C "$ROOT" rev-parse --verify --quiet "$SOURCE_REF^{commit}" > /dev/null || return 1
  [ "$(git -C "$ROOT" rev-parse HEAD)" = "$(git -C "$ROOT" rev-parse "$SOURCE_REF")" ]
}
pre_scrub_ref_is_old_history() {
  git -C "$ROOT" rev-parse --verify --quiet "$PRE_SCRUB_REF^{commit}" > /dev/null || return 1
  git -C "$ROOT" merge-base --is-ancestor "$PRE_SCRUB_REF" "$SOURCE_REF"
}
repo_state_is_known() {
  # Fresh: sys-admin is the old private repo. Renamed or resumed: sys-admin-archive exists and is private.
  if archive_exists; then repo_is_private "$ARCHIVE"; else [ "$(repo_full_name "$REPO")" = "$OWNER/$REPO" ] && repo_is_private "$REPO"; fi
}
export_tree() {
  export_dir="$(mktemp -d)"
  git -C "$ROOT" archive "$SOURCE_REF" | tar -x -C "$export_dir"
}
tree_is_scrubbed() { bash "$ROOT/scripts/scrub-scan.sh" "$export_dir"; }
load_secrets() {
  set -a
  # shellcheck source=/dev/null
  . "$BWS_TOKEN_FILE"
  set +a
  secrets=$(bws secret list -o json) || return 1
  jq -e 'type == "array"' <<< "$secrets"
}
resolve_project() {
  project_id=$(jq -r --arg k "$ANCHOR_KEY" '[.[] | select(.key == $k)][0].projectId // empty' <<< "$secrets")
  [ -n "$project_id" ]
}

# pre_file <path>: a file as the old history had it. Empty, with a failure status, when it did not.
pre_file() { git -C "$ROOT" show "$PRE_SCRUB_REF:$1" 2> /dev/null; }

# first_match <ere> <text> [<line filter ere>]: the first match of <ere> on the lines matching the
# filter. Never prints a line, only the match.
first_match() {
  local lines="$2"
  [ -z "${3:-}" ] || lines=$(grep -E "$3" <<< "$2" || true)
  grep -m1 -oE "$1" <<< "$lines" || true
}

# pre_value <key>: the value the old history held for a key, from the one file and the one line
# that carried it. Prints the value (the caller keeps it off the screen) or nothing.
pre_value() {
  local pair setup vault
  pair=$(pre_file scripts/syncthing/pair-device.sh) || true
  case "$1" in
    SYS_ADMIN_TAILSCALE_IP_WSL) first_match "$IP_RE" "$pair" '\[wsl2\]="tcp://' ;;
    SYS_ADMIN_TAILSCALE_IP_LGN5) first_match "$IP_RE" "$pair" '\[windows\]="tcp://' ;;
    SYS_ADMIN_TAILSCALE_IP_DJ15) first_match "$IP_RE" "$pair" '\[dj15\]="tcp://' ;;
    SYS_ADMIN_TAILSCALE_IP_HOMELAB) first_match "$IP_RE" "$pair" 'API_URL=' ;;
    SYS_ADMIN_SYNCTHING_DEVICE_ID_WSL2) first_match "$ID_RE" "$pair" '\[wsl2\]=' ;;
    SYS_ADMIN_SYNCTHING_DEVICE_ID_WINDOWS) first_match "$ID_RE" "$pair" '\[windows\]=' ;;
    SYS_ADMIN_SYNCTHING_DEVICE_ID_DJ15) first_match "$ID_RE" "$pair" '\[dj15\]=' ;;
    SYS_ADMIN_TAILSCALE_HOST_WSL)
      setup=$(pre_file scripts/syncthing/setup-wsl2.sh) || true
      first_match "$HOST_RE" "$setup" 'GUI \(remote\)' ;;
    SYS_ADMIN_TAILSCALE_HOST_VAULTWARDEN)
      vault=$(pre_file stack/config/wsl2/systemd/vaultwarden.service) || true
      first_match "$HOST_RE" "$vault" 'DOMAIN=' ;;
  esac
}
seeds_are_derivable() {
  local key missing=0
  for key in "${VALUE_KEYS[@]}"; do
    secret_set "$key" && continue
    [ -n "$(pre_value "$key")" ] || missing=1
  done
  [ "$missing" -eq 0 ]
}

# secret_source <Actions secret name>: the BWS key mapped to it, or nothing.
secret_source() {
  local pair
  for pair in $ACTIONS_SECRETS; do
    [ "${pair%%=*}" = "$1" ] && { echo "${pair#*=}"; return 0; }
  done
  return 0
}
secret_has_source() {
  local key
  key=$(secret_source "$1")
  [ -n "$key" ] && secret_set "$key"
}

# scan_issue <repo> <number>: the number of scrub-rule findings in the issue's title, body and
# comments. The text goes to gitleaks on stdin and is never printed.
scan_issue() {
  local json text report
  json=$(gh issue view "$2" -R "$OWNER/$1" --json title,body,comments) || return 1
  text=$(jq -r '[.title, .body, (.comments[]? | .body)] | join("\n\n")' <<< "$json") || return 1
  report=$(gitleaks stdin --config "$ROOT/.gitleaks.toml" --redact=100 --no-banner --log-level error \
    --report-format json --report-path /dev/stdout --exit-code 0 <<< "$text") || return 1
  jq 'length' <<< "$report"
}
open_issues() { gh issue list -R "$OWNER/$1" --state open --limit 200 --json number | jq -r 'sort_by(.number) | .[].number'; }
is_kept() { [[ " $KEEP_ISSUES " == *" $1 "* ]]; }

# The hub's list of repos with a promotion card (ops-hub apps/ops-hub/promotion-repos.txt), read
# from its main. The repository name does not change, so the entry stays valid for the new repo.
hub_lists_repo() {
  local list
  list=$(gh api "repos/$OWNER/$HUB_REPO/contents/$HUB_LIST_PATH" -H "Accept: application/vnd.github.raw") || return 1
  grep -qx "$OWNER/$REPO" <<< "$(sed -E 's/#.*//; s/[[:space:]]+$//' <<< "$list")"
}

echo "sys-admin#194 cutover: $OWNER/$REPO -> $OWNER/$ARCHIVE (private) and a new public $OWNER/$REPO"
preflight_need "gh, git, jq, bws, gitleaks and tar are installed" have_tools
preflight_need "gh is signed in" gh_authenticated
preflight_need "this checkout is clean and is exactly $SOURCE_REF" source_is_clean_and_current
if [ "$preflight_failed" -eq 0 ]; then
  preflight_need "the old history's last unscrubbed commit is in this checkout's history ($PRE_SCRUB_REF)" pre_scrub_ref_is_old_history
  preflight_need "the repository state is known (the old private $REPO, or the private $ARCHIVE already renamed)" repo_state_is_known
  preflight_need "the tree at $SOURCE_REF exports" export_tree
fi
if [ "$preflight_failed" -eq 0 ]; then
  preflight_need "the scrubbed tree passes the scrub scan" tree_is_scrubbed
  preflight_need "$BWS_TOKEN_FILE exists (Secrets Manager access)" test -f "$BWS_TOKEN_FILE"
fi
if [ "$preflight_failed" -eq 0 ]; then
  preflight_need "Secrets Manager answers (bws secret list)" load_secrets
fi
if [ "$preflight_failed" -eq 0 ]; then
  preflight_need "Secrets Manager holds $ANCHOR_KEY (its project receives the new keys)" resolve_project
fi
if [ "$preflight_failed" -eq 0 ]; then
  preflight_need "every missing private value is in the old history" seeds_are_derivable
fi
[ "$preflight_failed" -eq 0 ] || { echo "stopping: nothing was changed" >&2; exit 1; }

# ---- the state, and the plan ---------------------------------------------------------------

have_archive=0; have_new=0
archive_exists && have_archive=1
if [ "$have_archive" -eq 1 ] && new_repo_exists; then have_new=1; fi
src_repo="$REPO"; [ "$have_archive" -eq 1 ] && src_repo="$ARCHIVE"

names_of() { jq -r '[.[].name] | join(", ")' <<< "$1"; }
secret_names=$(gh secret list -R "$OWNER/$src_repo" --json name) || die "could not list the Actions secrets"
variable_names=$(gh variable list -R "$OWNER/$src_repo" --json name) || die "could not list the Actions variables"
hooks=$(gh api "repos/$OWNER/$src_repo/hooks") || die "could not list the webhooks"
runners=$(gh api "repos/$OWNER/$src_repo/actions/runners") || die "could not list the runners"
deploy_keys=$(gh api "repos/$OWNER/$src_repo/keys") || die "could not list the deploy keys"

while read -r name; do
  [ -n "$name" ] || continue
  owner_need "Actions secret $name has a Secrets Manager source" \
    "Actions secret $name on $src_repo: GitHub never returns its value. Store it in Secrets Manager, then run with SYS_ADMIN_ACTIONS_SECRETS=\"$name=<bws key>\"" \
    secret_has_source "$name"
done < <(jq -r '.[].name' <<< "$secret_names")
[ "$preflight_failed" -eq 0 ] || { echo "stopping: nothing was changed" >&2; exit 1; }

echo
echo "State: old repository is $OWNER/$src_repo (private); new $OWNER/$REPO exists: $([ "$have_new" -eq 1 ] && echo yes || echo no)"
echo "Open issues in $src_repo, not transferred (SYS_ADMIN_KEEP_ISSUES): skip $KEEP_ISSUES"
echo "Actions secrets on $src_repo (names): $(names_of "$secret_names")"
echo "Actions variables on $src_repo (names): $(names_of "$variable_names")"
echo "Webhooks on $src_repo: $(jq 'length' <<< "$hooks"); deploy keys: $(jq 'length' <<< "$deploy_keys"); repo-level runners: $(jq '.runners | length' <<< "$runners")"
if [ "$(jq 'length' <<< "$hooks")" -gt 0 ]; then
  echo "  webhooks (id, events, active; the URL and secret stay in $ARCHIVE): $(jq -r '[.[] | "\(.id) \(.events | join("+")) active=\(.active)"] | join("; ")' <<< "$hooks")"
fi
echo

if [ "$have_archive" -eq 1 ]; then echo "rename: already done ($ARCHIVE exists)"
else want "rename $OWNER/$REPO to $ARCHIVE (stays private; GitHub redirects the old name until step 3 reuses it)"; fi
for key in "${VALUE_KEYS[@]}"; do
  if secret_set "$key"; then echo "Secrets Manager $key: already set, left as is"
  else want "Secrets Manager $key: create (value from the old history at $PRE_SCRUB_REF, in the project of $ANCHOR_KEY; never printed)"; fi
done
if [ "$have_new" -eq 1 ]; then echo "create: $OWNER/$REPO already exists"
else want "create $OWNER/$REPO as a PRIVATE repository, then push ONE squashed commit of the scrubbed tree at $SOURCE_REF to main (never deploy)"; fi
want "labels: gh label clone $OWNER/$ARCHIVE into $OWNER/$REPO (a transferred issue keeps a label only if the target has it)"
mapped=0
while read -r name; do
  [ -n "$name" ] || continue
  mapped=1
  want "Actions secret $name on $OWNER/$REPO: set from Secrets Manager ($(secret_source "$name"))"
done < <(jq -r '.[].name' <<< "$secret_names")
[ "$mapped" -eq 1 ] || want "Actions secrets: none to recreate; BWS_ACCESS_TOKEN is deliberately not created (no workflow reads Secrets Manager)"
want "Actions variable CI_RUNS_ON: not recreated (the workflows run on ubuntu-latest); any other variable listed above has no Secrets Manager source and is not copied"
want "transfer the open issues of $ARCHIVE to $OWNER/$REPO (gh issue transfer, oldest first; GitHub allows it only while both are private), skip $KEEP_ISSUES"

echo
echo "Issue text carrying a private value (rule findings, values redacted):"
dirty=0
while read -r number; do
  [ -n "$number" ] || continue
  is_kept "$number" && continue
  count=$(scan_issue "$src_repo" "$number") || die "could not scan issue $number"
  if [ "$count" -gt 0 ]; then echo "  issue $number: $count finding(s)"; dirty=1; fi
done < <(open_issues "$src_repo")
[ "$dirty" -eq 1 ] || echo "  none"
[ "$dirty" -eq 0 ] || echo "  A real run stops before step 7 on these (after transferring them, so they can be edited in the new repository)."
want "make $OWNER/$REPO public (gh repo edit --visibility public), only when no transferred issue has a finding"
want "set the fork pull-request approval policy of $OWNER/$REPO to all_external_contributors"

hub_state="MISSING: add $OWNER/$REPO to $HUB_LIST_PATH in $OWNER/$HUB_REPO (a commit plus a promotion of ops-hub)"
if hub_lists_repo; then hub_state="listed: $OWNER/$REPO (the name is unchanged, so the card follows the new repository; nothing to edit)"; fi

print_wiring() {
  cat <<EOF

Wiring to re-point (nothing here is automatic):
  - Hub (OPS_HUB_PROMOTION_REPOS, read from $HUB_LIST_PATH in $OWNER/$HUB_REPO): $hub_state. Each token request names one repo, so check the hub's GitHub App can reach the NEW repository: if its installation is on selected repositories, add $OWNER/$REPO there (the new repository has a new id). Withdraw any promotion flag for a SHA of the old history. The first promotion creates \`deploy\` in the new repository: approve it on the ops-hub promotion card, never push it by hand.
  - Runners: the repository has no repository-level runner and its workflows run on ubuntu-latest, so register none on the public repository. Remove $OWNER/$REPO from the homelab JIT dispatcher enrolment (\`repos\` in ~/.config/homelab-ci/jit-dispatcher.json, homelab runbook jit-dispatcher.md) and from the fine-grained token's repository list: a self-hosted runner must never serve a public repository. The old CI_RUNS_ON variable stays on $ARCHIVE only.
  - Issue numbers restart. Transferred issues get new numbers (listed above as archive#N -> $REPO#M); every other old issue and pull request stays in $OWNER/$ARCHIVE. A reference to $OWNER/$REPO#N in another repository, a wayfinder map, a loop-state slot or a notice-board message now means the NEW repository's #N: repoint anything that should mean the old history to $OWNER/$ARCHIVE#N (the rewrite rules of argus-config#1064).
  - Releases and tags stay in $ARCHIVE (v1.2.x); the new history has none. Its first commit is a \`chore\`, so the first promotion runs the full CI as the test (no tag yet) and cuts no version until a \`feat\` or \`fix\` lands.
  - Webhooks, GitHub App installations and deploy keys on $OWNER/$ARCHIVE are not copied; Actions secrets and variables are recreated by name only as listed above.
  - Before the first trunk push to the new repository run \`scripts/trunk-readiness.sh $OWNER/$REPO\` from argus-config. Settings a public repository gains (rulesets, secret scanning, push protection) are the owner's to enable.
  - Decide whether to archive $OWNER/$ARCHIVE (gh repo archive), which also stops its workflows.
  - The local checkouts to re-clone on both hosts (WSL2 and homelab): move the old one aside, then clone the new repository:
      mv ~/repos/$REPO ~/repos/$ARCHIVE && git clone https://github.com/$OWNER/$REPO.git ~/repos/$REPO
    and point the T3 project for $REPO at the new clone. Worktrees under ~/.t3/worktrees/$REPO belong to the old history: remove them (git worktree remove) once their branches are merged or abandoned.
EOF
}

if [ "$DRY_RUN" -eq 1 ]; then
  if [ "$owner_missing" -eq 1 ]; then
    echo
    echo "Owner steps before the real run (a real run stops without them):"
    for note in "${owner_notes[@]}"; do echo "  - $note"; done
  fi
  echo
  echo "[dry-run] verify (a real run): new repository public, archive private, open issues moved, main is one commit, no deploy branch"
  print_wiring | sed 's/^/[dry-run] /'
  echo "[dry-run] done: nothing was changed"
  exit 0
fi

# ---- changes -------------------------------------------------------------------------------

# 1. rename
if [ "$have_archive" -eq 0 ]; then
  gh api -X PATCH "repos/$OWNER/$REPO" -f "name=$ARCHIVE" > /dev/null
  did "renamed $OWNER/$REPO to $ARCHIVE"
  archive_exists || die "$ARCHIVE does not exist after the rename"
  repo_is_private "$ARCHIVE" || die "$ARCHIVE is not private: stop and fix it before anything else"
fi

# 2. Secrets Manager
for key in "${VALUE_KEYS[@]}"; do
  secret_set "$key" && continue
  value=$(pre_value "$key")
  [ -n "$value" ] || die "no value for $key in the old history"
  bws secret create --note "sys-admin private value (sys-admin#194)" -o none "$key" "$value" "$project_id" || die "could not create $key"
  unset value
  did "created Secrets Manager secret $key"
done
secrets=$(bws secret list -o json) || die "could not re-read Secrets Manager"

# 3. the new repository, private, one squashed commit
description=$(jq -r '.description // empty' <<< "$(repo_json "$src_repo")")
if [ "$have_new" -eq 0 ]; then
  gh repo create "$OWNER/$REPO" --private --description "$description" > /dev/null
  did "created $OWNER/$REPO (private)"
fi
if ! gh api "repos/$OWNER/$REPO/branches/main" > /dev/null 2>&1; then
  src_short=$(git -C "$ROOT" rev-parse --short "$SOURCE_REF")
  git -C "$export_dir" init -q -b main
  git -C "$export_dir" add -A
  git -C "$export_dir" -c "user.name=$(git -C "$ROOT" config user.name)" -c "user.email=$(git -C "$ROOT" config user.email)" \
    commit -q -m "chore: start the public history from $ARCHIVE@$src_short" -m "The earlier history is kept, private, in $OWNER/$ARCHIVE. Refs $OWNER/$ARCHIVE#194"
  git -C "$export_dir" remote add origin "$REMOTE_BASE/$OWNER/$REPO.git"
  git -C "$export_dir" -c "credential.helper=!gh auth git-credential" push -q origin main
  did "pushed one squashed commit to $OWNER/$REPO main (from $ARCHIVE@$src_short)"
fi

# 4. labels, Actions secrets
gh label clone "$OWNER/$ARCHIVE" -R "$OWNER/$REPO" > /dev/null
did "cloned the labels of $ARCHIVE into $REPO"
while read -r name; do
  [ -n "$name" ] || continue
  key=$(secret_source "$name")
  value=$(secret_value "$key")
  [ -n "$value" ] || die "Secrets Manager has no value for $key"
  gh secret set "$name" -R "$OWNER/$REPO" < <(printf '%s' "$value") || die "could not set the Actions secret $name"
  unset value
  did "set the Actions secret $name on $OWNER/$REPO (from $key)"
done < <(jq -r '.[].name' <<< "$secret_names")

# 5. issues
echo "Issue transfers (archive -> new):"
while read -r number; do
  [ -n "$number" ] || continue
  if is_kept "$number"; then echo "  archive#$number stays (kept)"; continue; fi
  url=$(gh issue transfer "$number" "$OWNER/$REPO" -R "$OWNER/$ARCHIVE") || die "could not transfer issue $number"
  echo "  archive#$number -> $REPO#${url##*/}"
done < <(open_issues "$ARCHIVE")

# 6. scan every open issue in the new repository, the transferred ones included
dirty=0
while read -r number; do
  [ -n "$number" ] || continue
  count=$(scan_issue "$REPO" "$number") || die "could not scan issue $number"
  if [ "$count" -gt 0 ]; then echo "issue $number: $count finding(s) (values redacted)" >&2; dirty=1; fi
done < <(open_issues "$REPO")
if [ "$dirty" -eq 1 ]; then
  echo "stopping before the repository goes public: edit the issues above in $OWNER/$REPO (https://github.com/$OWNER/$REPO/issues), then run this script again" >&2
  exit 3
fi

# 7. public
if repo_is_private "$REPO"; then
  gh repo edit "$OWNER/$REPO" --visibility public --accept-visibility-change-consequences
  did "made $OWNER/$REPO public"
fi
gh api -X PUT "repos/$OWNER/$REPO/actions/permissions/fork-pr-contributor-approval" -f approval_policy=all_external_contributors > /dev/null
did "set the fork pull-request approval policy to all_external_contributors"

# 8. wiring
print_wiring
