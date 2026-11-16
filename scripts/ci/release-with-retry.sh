#!/usr/bin/env bash
# Runs one semantic-release track up to 3 times, each attempt from the remote tip of the
# release branch (argus-config#1269: the one vendored copy, merged from the per-repo copies
# in atto1, apsjobs-discovery, quick-capture, skills, ios-scripts, myargus and homelab).
#
# Vendored byte-for-byte into each deploy repo and never edited there: a repo's
# differences are the env below, set by its release workflow. argus-config holds the
# source; `scripts/sync-release-scripts.sh` copies it out and
# `release-scripts-check.sh` fails CI when a copy has drifted.
#
# Why: the release branch is `deploy`, and a second promotion can land between this run's
# checkout and semantic-release's push of the tag; on a trunk repo, agents push to the
# release branch while a run is in flight. That shows up two ways, both safe to retry
# because nothing has been tagged or published yet:
#   1. semantic-release sees the local branch is behind, logs "is behind the remote one"
#      and exits 0 having released nothing. Left alone, the release silently does not
#      happen.
#   2. A push is rejected as a non-fast-forward and it exits non-zero.
#
# Before every attempt (the first included) the checkout is made to equal the remote
# branch exactly, dropping a half-finished attempt's local commits, staged and untracked
# files and a detached HEAD. That is a rebase in effect: the release is redone on top of
# whatever landed.
#
# Release only what was tested. When the release job `needs:` a test job that went green
# on the promoted SHA (TESTED_SHA, github.sha) and the remote tip is past that SHA, a
# newer promotion has its own run, with its own tests, and that run releases everything
# since the last tag; this one stops with exit 0 rather than tag an untested commit.
#
# Anything else that fails (bad token, a rejected hook, a plugin error) is not a race and
# is not retried: its exit status is passed through. Still behind after the last attempt
# exits 1, so a skipped release is never green.
#
# Env:
#   RELEASE_BRANCH         the branch released from (default deploy; main for a trunk release)
#   RELEASE_REMOTE         what to fetch from (default origin); CI may pass an authenticated URL
#   GITHUB_TOKEN           when set, authenticates the fetch (the checkout has persist-credentials off)
#   TESTED_SHA             the commit the test job ran on; unset skips the check (a manual run)
#   RELEASE_COMMAND        default `pnpm exec semantic-release`; the tests stub it
#   RELEASE_ATTEMPT_PAUSE  seconds to wait before a retry (default 5)
set -uo pipefail

RELEASE_BRANCH="${RELEASE_BRANCH:-deploy}"
RELEASE_REMOTE="${RELEASE_REMOTE:-origin}"
TESTED_SHA="${TESTED_SHA:-}"
RELEASE_COMMAND="${RELEASE_COMMAND:-pnpm exec semantic-release}"
PAUSE="${RELEASE_ATTEMPT_PAUSE:-5}"
LOG="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/semantic-release.log"
MAX_ATTEMPTS=3
# `[remote rejected]` (a protected ref or a hook) is deliberately not here.
REJECTED_PATTERN='failed to push some refs|\[rejected\]|non-fast-forward|fetch first|Updates were rejected'

git_authenticated=(git)
if [ -n "${GITHUB_TOKEN:-}" ]; then
  basic=$(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 -w0)
  git_authenticated=(git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}")
fi

reason=""
for attempt in $(seq 1 "${MAX_ATTEMPTS}"); do
  if ! "${git_authenticated[@]}" fetch --quiet --tags --force "${RELEASE_REMOTE}" "+refs/heads/${RELEASE_BRANCH}:refs/remotes/origin/${RELEASE_BRANCH}"; then
    echo "::error::could not fetch ${RELEASE_BRANCH} from the remote"
    exit 1
  fi
  tip="$(git rev-parse "origin/${RELEASE_BRANCH}")"
  if [ -n "${TESTED_SHA}" ] && [ "${tip}" != "${TESTED_SHA}" ]; then
    echo "::notice::${RELEASE_BRANCH} is at ${tip:0:7}, past the tested ${TESTED_SHA:0:7}: a newer promotion has its own tests and releases it. Nothing released here."
    exit 0
  fi
  git checkout --quiet --force -B "${RELEASE_BRANCH}" "origin/${RELEASE_BRANCH}" || exit 1
  git clean --quiet -fd

  bash -c "${RELEASE_COMMAND}" 2>&1 | tee "${LOG}"
  exit_code="${PIPESTATUS[0]}"

  if [ "${exit_code}" -eq 0 ]; then
    if ! grep -q "is behind the remote one" "${LOG}"; then
      exit 0
    fi
    reason="behind"
    echo "::warning::local ${RELEASE_BRANCH} was behind the remote (attempt ${attempt} of ${MAX_ATTEMPTS})"
  elif grep -qE "${REJECTED_PATTERN}" "${LOG}"; then
    reason="rejected"
    echo "::warning::a release push was rejected, ${RELEASE_BRANCH} moved under it (attempt ${attempt} of ${MAX_ATTEMPTS})"
  else
    exit "${exit_code}"
  fi
  [ "${attempt}" -eq "${MAX_ATTEMPTS}" ] || sleep "${PAUSE}"
done

if [ "${reason}" = "behind" ]; then
  echo "::error::still behind the remote after ${MAX_ATTEMPTS} attempts, release skipped"
else
  echo "::error::release push was rejected ${MAX_ATTEMPTS} times because ${RELEASE_BRANCH} kept moving, release not completed"
fi
exit 1
