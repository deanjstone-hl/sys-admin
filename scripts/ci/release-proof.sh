#!/usr/bin/env bash
# Decides whether the deploy push may reuse main's CI instead of running the full test
# again (argus-config#1198, #1168; #1269: the one vendored copy, merged from the copies in
# argus-config, argus, atto1, apsjobs-discovery, quick-capture and sys-admin). Prints
# `reuse=true|false` to $GITHUB_OUTPUT.
#
# Vendored byte-for-byte into each deploy repo and never edited there: a repo's
# differences are the RELEASE_PROOF_* env below, set by its release workflow.
# argus-config holds the source; `scripts/sync-release-scripts.sh` copies it out and
# `release-scripts-check.sh` fails CI when a copy has drifted.
#
# The promoted SHA is already on main. Reuse main's result only when BOTH hold:
#   1. a run of RELEASE_PROOF_WORKFLOW on main for this SHA, from one of
#      RELEASE_PROOF_EVENTS, concluded success and, when RELEASE_PROOF_JOBS names jobs,
#      every one of them concluded success (a `Job::Step` entry also needs that step to
#      have succeeded). A scoped run (a pull_request, or a push scoped to its diff) and a
#      run whose required job skipped do not count: name the jobs that only a whole run
#      executes;
#   2. every other workflow run on main for this SHA finished green.
# A main run on this SHA that concluded red fails the script (exit 1): a red SHA never
# releases. A cancelled run is untested, not red. Anything else, an API error and a
# missing RELEASE_PROOF_WORKFLOW included, prints reuse=false so the release workflow
# runs the full test itself.
#
# A repo's Guard may also call it on the nightly schedule, to skip a second full run of a
# main SHA that already passed one; GITHUB_RUN_ID (always set in Actions) keeps the
# calling run itself out of the reckoning.
#
# Env:
#   RELEASE_PROOF_WORKFLOW  required: the workflow name that runs the whole test (CI, Lint, Test)
#   RELEASE_PROOF_EVENTS    space-separated events whose runs count (default `push schedule`)
#   RELEASE_PROOF_JOBS      newline-separated job names that must have succeeded in that
#                           run (default none: the run's own success is enough)
# Needs: gh and jq on PATH, GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA.
# Token permissions: actions read.
set -uo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"

decide() {
  printf 'reuse=%s\n' "$1" >> "$output"
  echo "release-proof: reuse=$1 ($2)"
  exit 0
}

[[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_SHA:-}" ]] || decide false "GITHUB_REPOSITORY or GITHUB_SHA unset"
[[ -n "${RELEASE_PROOF_WORKFLOW:-}" ]] || decide false "RELEASE_PROOF_WORKFLOW unset"
repo="$GITHUB_REPOSITORY"
sha="$GITHUB_SHA"
full_workflow="$RELEASE_PROOF_WORKFLOW"
events_json=$(jq -Rnc --arg events "${RELEASE_PROOF_EVENTS:-push schedule}" '$events | split(" ") | map(select(. != ""))')
required_json=$(jq -Rnc --arg jobs "${RELEASE_PROOF_JOBS:-}" '$jobs | split("\n") | map(select(. != ""))')

all_runs=$(gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=100") \
  || decide false "could not list the workflow runs of $sha"
main_runs=$(jq -c --arg self "${GITHUB_RUN_ID:-}" --argjson events "$events_json" '
  if .total_count != (.workflow_runs | length) then error("more runs than one page") else . end
  | [.workflow_runs[] | select(.head_branch == "main" and (.event | IN($events[])) and (.id | tostring) != $self)]' \
  <<< "$all_runs" 2> /dev/null) || decide false "could not read the workflow runs of $sha (or more than one page)"

red=$(jq -r '[.[] | select(.status == "completed"
  and (.conclusion | IN("success", "skipped", "neutral", "cancelled") | not))
  | "\(.name) (\(.event), \(.conclusion))"] | join(", ")' <<< "$main_runs") \
  || decide false "could not read the main runs of $sha"
if [[ -n "$red" ]]; then
  echo "release-proof: main CI is red on $sha: $red" >&2
  exit 1
fi

[[ "$(jq length <<< "$main_runs")" -gt 0 ]] || decide false "no main CI run on $sha"
pending=$(jq -r '[.[] | select(.status != "completed") | .name] | join(", ")' <<< "$main_runs")
[[ -z "$pending" ]] || decide false "main CI still running on $sha: $pending"
cancelled=$(jq -r '[.[] | select(.conclusion == "cancelled") | .name] | join(", ")' <<< "$main_runs")
[[ -z "$cancelled" ]] || decide false "a main run on $sha was cancelled: $cancelled"

full_ids=$(jq -r --arg name "$full_workflow" '.[] | select(.name == $name and .conclusion == "success") | .id' <<< "$main_runs") \
  || decide false "could not read the main runs of $sha"
[[ -n "$full_ids" ]] || decide false "no green $full_workflow run on main for $sha"

if [[ "$(jq length <<< "$required_json")" -eq 0 ]]; then
  full_id=$(head -n 1 <<< "$full_ids")
  decide true "$full_workflow run $full_id ran the full test on $sha and passed; main CI is green"
fi

for id in $full_ids; do
  jobs=$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100") \
    || decide false "could not list the jobs of $full_workflow run $id"
  missing=$(jq -r --argjson required "$required_json" '
    if .total_count != (.jobs | length) then error("more jobs than one page") else . end
    | . as $all
    | [$required[] | select(. as $entry
        | ($entry | split("::")) as $parts
        | [$all.jobs[] | select(.name == $parts[0] and .conclusion == "success"
            and (($parts | length) < 2
                 or ([.steps[]? | select(.name == $parts[1] and .conclusion == "success")] | length) > 0))]
        | length == 0)]
    | join(", ")' <<< "$jobs" 2> /dev/null) \
    || decide false "could not read the jobs of $full_workflow run $id (or more than one page)"
  if [[ -z "$missing" ]]; then
    decide true "$full_workflow run $id ran the full test on $sha and passed; main CI is green"
  fi
  echo "release-proof: $full_workflow run $id on $sha did not run the full test (no passing: $missing)"
done

decide false "no full $full_workflow run passed on main for $sha"
