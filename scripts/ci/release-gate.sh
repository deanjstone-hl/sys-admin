#!/usr/bin/env bash
# The Release workflow's test gate (argus-config#1595, map #1591, owner decision of
# 22 Nov 2026). The deploy push runs no test suite. The gate passes only when both hold:
#
#   1. main's CI is green on the exact promoted SHA. That run may be a scoped run: it ran
#      the tests the push changed, and the daily run below covers the rest.
#   2. the repo's latest completed daily full run is green and under 24 hours old.
#
# A red or stale daily full run blocks promotion until it is fixed. Each half prints its
# own `main CI half FAILED` or `daily full half FAILED` line, and both are checked on every
# run so one failure does not hide the other. Exit 0 passes, 1 fails, 2 is a usage error
# (a missing env variable): the gate never passes on a misconfiguration, and it never
# falls back to running the suite, because nothing here starts a run.
#
# Vendored byte-for-byte into each deploy repo and never edited there: a repo's
# differences are the RELEASE_GATE_* env below, set by its release workflow.
# argus-config holds the source; `scripts/sync-release-scripts.sh` copies it out and
# `release-scripts-check.sh` fails CI when a copy has drifted.
#
# Half 1: every run on main for this SHA (the events in RELEASE_GATE_CI_EVENTS) is read.
# A red one fails the gate (a red SHA never releases), as do no run at all, a run still
# going, a cancelled run (untested, not red) and the absence of a green run of
# RELEASE_GATE_CI_WORKFLOW. A pull_request run and the deploy push's own runs are not
# main's CI.
#
# Half 2: the newest completed run of the workflow file RELEASE_GATE_DAILY_WORKFLOW on
# main, from RELEASE_GATE_DAILY_EVENTS, decides. A newer green run (a rerun, or a
# dispatch of the daily workflow) clears a red or stale one; an older green run does not
# rescue a newer red one. Its age is measured from when it finished
# (RELEASE_GATE_DAILY_MAX_AGE_HOURS, default 24). When RELEASE_GATE_DAILY_JOBS names jobs
# (`Job` or `Job::Step`), each must have succeeded in that run, so a run whose jobs were
# skipped is not a full run.
#
# Env:
#   RELEASE_GATE_CI_WORKFLOW         required: name of the workflow that is main's CI (CI, Lint, Test)
#   RELEASE_GATE_DAILY_WORKFLOW      required: file name of the daily full workflow (daily-full.yml)
#   RELEASE_GATE_CI_EVENTS           space-separated events whose runs on the SHA count (default `push schedule`)
#   RELEASE_GATE_DAILY_EVENTS        space-separated events of the daily run (default `schedule workflow_dispatch`)
#   RELEASE_GATE_DAILY_JOBS          newline-separated jobs that must have succeeded in the daily run (default none)
#   RELEASE_GATE_DAILY_MAX_AGE_HOURS limit on the daily run's age (default 24)
#   RELEASE_GATE_NOW                 epoch seconds standing in for the clock (tests)
# Needs: gh and jq on PATH, GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA.
# Token permissions: actions read.
set -uo pipefail

output="${GITHUB_OUTPUT:-/dev/stdout}"

usage_error() {
  echo "release-gate: $1" >&2
  exit 2
}

[[ -n "${GITHUB_REPOSITORY:-}" ]] || usage_error "GITHUB_REPOSITORY unset"
[[ -n "${GITHUB_SHA:-}" ]] || usage_error "GITHUB_SHA unset"
[[ -n "${RELEASE_GATE_CI_WORKFLOW:-}" ]] || usage_error "RELEASE_GATE_CI_WORKFLOW unset"
[[ -n "${RELEASE_GATE_DAILY_WORKFLOW:-}" ]] || usage_error "RELEASE_GATE_DAILY_WORKFLOW unset"
max_age_hours="${RELEASE_GATE_DAILY_MAX_AGE_HOURS:-24}"
[[ "$max_age_hours" =~ ^[0-9]+$ ]] || usage_error "RELEASE_GATE_DAILY_MAX_AGE_HOURS is not a whole number: $max_age_hours"

repo="$GITHUB_REPOSITORY"
sha="$GITHUB_SHA"
now="${RELEASE_GATE_NOW:-$(date +%s)}"
failures=0

fail_half() { # <main CI|daily full> <why>
  echo "release-gate: $1 half FAILED: $2" >&2
  failures=$((failures + 1))
}

# ---- half 1: main's CI on the promoted SHA ----
check_main_ci() {
  local ci_events_json all_runs main_runs red pending cancelled green
  ci_events_json=$(jq -Rnc --arg events "${RELEASE_GATE_CI_EVENTS:-push schedule}" '$events | split(" ") | map(select(. != ""))')
  all_runs=$(gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=100") \
    || { fail_half "main CI" "could not list the workflow runs of $sha"; return; }
  main_runs=$(jq -c --argjson events "$ci_events_json" '
    if .total_count != (.workflow_runs | length) then error("more runs than one page") else . end
    | [.workflow_runs[] | select(.head_branch == "main" and (.event | IN($events[])))]' \
    <<< "$all_runs" 2> /dev/null) \
    || { fail_half "main CI" "could not read the workflow runs of $sha (or more than one page)"; return; }

  red=$(jq -r '[.[] | select(.status == "completed"
    and (.conclusion | IN("success", "skipped", "neutral", "cancelled") | not))
    | "\(.name) (\(.event), \(.conclusion))"] | join(", ")' <<< "$main_runs")
  if [[ -n "$red" ]]; then
    fail_half "main CI" "main CI is red on $sha: $red"
    return
  fi
  if [[ "$(jq length <<< "$main_runs")" -eq 0 ]]; then
    fail_half "main CI" "no main CI run on $sha (a push to main starts one; nothing ran for this SHA)"
    return
  fi
  pending=$(jq -r '[.[] | select(.status != "completed") | .name] | join(", ")' <<< "$main_runs")
  if [[ -n "$pending" ]]; then
    fail_half "main CI" "main CI is still running on $sha: $pending; run Release again when it ends"
    return
  fi
  cancelled=$(jq -r '[.[] | select(.conclusion == "cancelled") | .name] | join(", ")' <<< "$main_runs")
  if [[ -n "$cancelled" ]]; then
    fail_half "main CI" "a main run on $sha was cancelled: $cancelled; it tested nothing, so re-run it"
    return
  fi
  green=$(jq -r --arg name "$RELEASE_GATE_CI_WORKFLOW" '[.[] | select(.name == $name and .conclusion == "success") | .id] | first // empty' <<< "$main_runs")
  if [[ -z "$green" ]]; then
    fail_half "main CI" "no green $RELEASE_GATE_CI_WORKFLOW run on main for $sha"
    return
  fi
  echo "release-gate: main CI half ok ($RELEASE_GATE_CI_WORKFLOW run $green passed on $sha and every main run on it is green)"
}

# ---- half 2: the latest daily full run ----
check_daily_full() {
  local daily_events_json runs latest id conclusion finished finished_epoch age_seconds jobs required_json missing
  daily_events_json=$(jq -Rnc --arg events "${RELEASE_GATE_DAILY_EVENTS:-schedule workflow_dispatch}" '$events | split(" ") | map(select(. != ""))')
  runs=$(gh api "repos/$repo/actions/workflows/$RELEASE_GATE_DAILY_WORKFLOW/runs?branch=main&status=completed&per_page=30") \
    || { fail_half "daily full" "could not list the runs of $RELEASE_GATE_DAILY_WORKFLOW"; return; }
  latest=$(jq -c --argjson events "$daily_events_json" '
    [.workflow_runs[] | select(.head_branch == "main" and (.event | IN($events[])))]
    | sort_by(.created_at) | last // empty' <<< "$runs" 2> /dev/null) \
    || { fail_half "daily full" "could not read the runs of $RELEASE_GATE_DAILY_WORKFLOW"; return; }
  if [[ -z "$latest" ]]; then
    fail_half "daily full" "no completed daily full run of $RELEASE_GATE_DAILY_WORKFLOW on main; dispatch it, or wait for its schedule"
    return
  fi
  id=$(jq -r '.id' <<< "$latest")
  conclusion=$(jq -r '.conclusion' <<< "$latest")
  if [[ "$conclusion" != success ]]; then
    fail_half "daily full" "the latest daily full run $id is $conclusion: fix it, then rerun it or dispatch $RELEASE_GATE_DAILY_WORKFLOW; promotion stays blocked until a daily full run is green"
    return
  fi
  finished=$(jq -r '.updated_at' <<< "$latest")
  finished_epoch=$(jq -nr --arg t "$finished" '$t | fromdateiso8601' 2> /dev/null) \
    || { fail_half "daily full" "could not read the finish time of daily full run $id ($finished)"; return; }
  age_seconds=$((now - finished_epoch))
  if [[ "$age_seconds" -ge $((max_age_hours * 3600)) ]]; then
    fail_half "daily full" "the latest daily full run $id is stale: it finished $((age_seconds / 3600))h ago ($finished), over the ${max_age_hours}h limit; dispatch $RELEASE_GATE_DAILY_WORKFLOW and run Release again"
    return
  fi

  required_json=$(jq -Rnc --arg jobs "${RELEASE_GATE_DAILY_JOBS:-}" '$jobs | split("\n") | map(select(. != ""))')
  if [[ "$(jq length <<< "$required_json")" -gt 0 ]]; then
    jobs=$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100") \
      || { fail_half "daily full" "could not list the jobs of daily full run $id"; return; }
    missing=$(jq -r --argjson required "$required_json" '
      if .total_count != (.jobs | length) then error("more jobs than one page") else . end
      | . as $all
      | [$required[] | select(. as $entry
          | ($entry | split("::")) as $parts
          | [$all.jobs[] | select(.name == $parts[0] and .conclusion == "success"
              and (($parts | length) < 2
                   or ([.steps[]? | select(.name == $parts[1] and .conclusion == "success")] | length) > 0))]
          | length == 0)] | join(", ")' <<< "$jobs" 2> /dev/null) \
      || { fail_half "daily full" "could not read the jobs of daily full run $id (or more than one page)"; return; }
    if [[ -n "$missing" ]]; then
      fail_half "daily full" "daily full run $id did not pass: $missing (a skipped job is not a full run)"
      return
    fi
  fi
  echo "release-gate: daily full half ok (run $id passed and finished $((age_seconds / 3600))h ago, limit ${max_age_hours}h)"
}

check_main_ci
check_daily_full

if [[ "$failures" -gt 0 ]]; then
  printf 'pass=false\n' >> "$output"
  echo "release-gate: blocked ($failures half(s) failed); no test suite runs on the deploy push" >&2
  exit 1
fi
printf 'pass=true\n' >> "$output"
echo "release-gate: pass"
