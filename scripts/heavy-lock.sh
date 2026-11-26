#!/usr/bin/env bash
# Host-wide lock for heavy commands: only one runs at a time on this host
# (argus-config#1488). On 19 Nov 2026 three overlapping full checks made systemd-oomd
# kill five agent scopes; "one heavy command at a time" only binds one thread.
#
#   bash scripts/heavy-lock.sh <command> [args...]
#
# It takes an flock on one file, waits (with a timeout) while memory pressure is high,
# then runs the command and exits with its status. Waiting is normal: a queued run
# prints what it waits for, and who holds the lock, and carries on when the lock frees.
#
# The holder writes its pid, repo, command, session and start time to <lock file>.holder
# while it runs (argus-config#1733); a waiter prints them in its first line and again at
# every notice interval, so it can tell a long check from a stuck one. The lock is the flock,
# not that file: a holder that dies frees it at once, and the command runs with the lock's
# file descriptor closed, so a background process the command leaves behind cannot pin it.
#
# Exit status: the command's own; 2 usage; 75 timed out waiting for the lock or for
# memory pressure to drop (EX_TEMPFAIL), with a message naming the holder and the fix; 1 the
# lock file could not be opened.
#
# Env:
#   HEAVY_LOCK_FILE      the lock file (default /run/user/<uid>/heavy.lock; when that
#                        directory is missing, e.g. a hosted CI runner, falls back to
#                        ${TMPDIR:-/tmp}/heavy-lock-<uid>.lock)
#   HEAVY_LOCK_RUN_DIR   the directory of the default lock file (default /run/user/<uid>)
#   HEAVY_LOCK_TIMEOUT   seconds to wait in all (default 900, 15 min)
#   HEAVY_LOCK_NOTICE    seconds between "still waiting" lines while queued (default 60)
#   HEAVY_LOCK_SESSION   the session or thread id the holder file records (default
#                        $T3CODE_THREAD_ID, else $CLAUDE_CODE_SESSION_ID, else unknown)
#   HEAVY_LOCK_PSI_MAX   wait while memory `some avg60` is at or above this (default 10)
#   HEAVY_LOCK_PSI_FILE  the pressure file (default /proc/pressure/memory; a missing
#                        file does not block)
#   HEAVY_LOCK_POLL      seconds between memory-pressure checks (default 5)
#   HEAVY_LOCK_HELD      set to 1 inside the command: a nested heavy-lock.sh call (a
#                        check that runs the checks' own tests) passes straight through
#                        instead of deadlocking on the lock its parent holds
#   HEAVY_LOCK_MEMORY_MAX  the memory cap of the command's transient user scope (default
#                        3G; 0 or off runs it with no cap). The command also gets no swap,
#                        so an over-limit check is killed alone and fast, not the session
#                        around it (argus-config#1654). Where no user scope can be started
#                        (a hosted CI runner), it runs uncapped and says so.
#   HEAVY_LOCK_SYSTEMD_RUN the launcher (default systemd-run; the tests stub it)
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: heavy-lock.sh <command> [args...]" >&2
  exit 2
fi

if [ "${HEAVY_LOCK_HELD:-}" = 1 ]; then
  exec "$@"
fi

uid=$(id -u)
run_dir="${HEAVY_LOCK_RUN_DIR:-/run/user/$uid}"
if [ -n "${HEAVY_LOCK_FILE:-}" ]; then
  lock_file="$HEAVY_LOCK_FILE"
elif [ -d "$run_dir" ]; then
  lock_file="$run_dir/heavy.lock"
else
  lock_file="${TMPDIR:-/tmp}/heavy-lock-$uid.lock"
fi
timeout_s="${HEAVY_LOCK_TIMEOUT:-900}"
notice_s="${HEAVY_LOCK_NOTICE:-60}"
holder_file="$lock_file.holder"
psi_max="${HEAVY_LOCK_PSI_MAX:-10}"
psi_file="${HEAVY_LOCK_PSI_FILE:-/proc/pressure/memory}"
poll_s="${HEAVY_LOCK_POLL:-5}"
memory_max="${HEAVY_LOCK_MEMORY_MAX:-3G}"
systemd_run="${HEAVY_LOCK_SYSTEMD_RUN:-systemd-run}"

command -v flock >/dev/null 2>&1 || {
  echo "heavy-lock.sh: flock is not installed" >&2
  exit 1
}

# The `some avg60` figure, empty when the file is missing or unreadable.
memory_some_avg60() {
  [ -r "$psi_file" ] || return 0
  sed -n 's/^some .*avg60=\([0-9.]*\).*/\1/p' "$psi_file" 2>/dev/null | head -n1
}

# true when pressure is at or above the limit.
pressure_high() {
  local avg
  avg=$(memory_some_avg60)
  [ -n "$avg" ] || return 1
  awk -v a="$avg" -v m="$psi_max" 'BEGIN { exit !(a + 0 >= m + 0) }'
}

# Holder bookkeeping (argus-config#1733). One key=value per line; the first match of a key wins.
holder_field() {
  [ -r "$holder_file" ] || return 0
  sed -n "s/^$1=//p" "$holder_file" 2>/dev/null | head -n1
}

# Describe the holder in one line. A holder file whose pid is gone while the lock is still held
# means a process the holder left behind has the lock; no file means an older heavy-lock.sh or
# a plain flock. A holder that has just taken the lock may not have written its file yet, so
# look a few times (the argument) before calling the file stale.
describe_holder() {
  local tries=$(($1 + 1)) pid
  while :; do
    pid=$(holder_field pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      break
    fi
    tries=$((tries - 1))
    [ "$tries" -gt 0 ] || break
    sleep 0.1
  done
  if [ -z "$pid" ]; then
    echo "holder unknown (no holder file at $holder_file)"
    return 0
  fi
  local repo command session started started_epoch running="" gone=""
  repo=$(holder_field repo)
  command=$(holder_field command)
  session=$(holder_field session)
  started=$(holder_field started)
  started_epoch=$(holder_field started_epoch)
  case "$started_epoch" in
    '' | *[!0-9]*) ;;
    *) running=", running $(($(date +%s) - started_epoch))s" ;;
  esac
  if ! kill -0 "$pid" 2>/dev/null; then
    gone="; pid $pid is gone but the lock is still held, by a process it left behind (find it: fuser $lock_file)"
  fi
  echo "held by pid $pid (repo $repo, command \"$command\", session $session) since $started$running$gone"
}

repo_name() {
  local common
  if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    common=${common%/.git}
    basename "$common"
  else
    basename "$PWD"
  fi
}

write_holder() {
  local command tmp="$holder_file.$$"
  command=${*//$'\n'/ }
  command=${command:0:200}
  {
    echo "pid=$$"
    echo "repo=$(repo_name)"
    echo "command=$command"
    echo "session=${HEAVY_LOCK_SESSION:-${T3CODE_THREAD_ID:-${CLAUDE_CODE_SESSION_ID:-unknown}}}"
    echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "started_epoch=$(date +%s)"
  } >"$tmp" 2>/dev/null && mv -f "$tmp" "$holder_file" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  holder_written=1
}

holder_written=0
# shellcheck disable=SC2329 # runs through the EXIT trap
cleanup_holder() {
  if [ "$holder_written" -eq 1 ] && [ "$(holder_field pid)" = "$$" ]; then
    rm -f "$holder_file" 2>/dev/null || true
  fi
}
trap cleanup_holder EXIT

exec 9>>"$lock_file" || {
  echo "heavy-lock.sh: cannot open $lock_file" >&2
  exit 1
}

started=$SECONDS
deadline=$((started + timeout_s))

timed_out_on_lock() {
  local description pid
  description=$(describe_holder 0)
  pid=$(holder_field pid)
  echo "heavy-lock.sh: timed out after ${timeout_s}s waiting for the host lock, $description" >&2
  echo "heavy-lock.sh: nothing ran. A live holder is a long check, not a stuck lock: retry later, or confirm it is alive with 'kill -0 ${pid:-<pid>}' (do not kill another thread's check). To wait longer, set HEAVY_LOCK_TIMEOUT (seconds)." >&2
  exit 75
}

if ! flock -n 9; then
  echo "heavy-lock.sh: waiting for the host lock ($lock_file), $(describe_holder 3); giving up after ${timeout_s}s" >&2
  while :; do
    remaining=$((deadline - SECONDS))
    [ "$remaining" -ge 1 ] || timed_out_on_lock
    step=$notice_s
    [ "$remaining" -ge "$step" ] || step=$remaining
    if flock -w "$step" 9; then
      break
    fi
    [ "$SECONDS" -lt "$deadline" ] || timed_out_on_lock
    echo "heavy-lock.sh: still waiting for the host lock, waited $((SECONDS - started))s of ${timeout_s}s, $(describe_holder 0)" >&2
  done
fi

write_holder "$@"

if pressure_high; then
  echo "heavy-lock.sh: waiting for memory pressure to drop (some avg60 >= $psi_max)" >&2
  while pressure_high; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "heavy-lock.sh: timed out after ${timeout_s}s waiting for memory pressure to drop (some avg60 stayed at or above $psi_max); nothing ran. Retry later, or move the limit with HEAVY_LOCK_PSI_MAX, or wait longer with HEAVY_LOCK_TIMEOUT." >&2
      exit 75
    fi
    sleep "$poll_s"
  done
fi

export HEAVY_LOCK_HELD=1

# Run the command in a transient user scope with a memory cap (argus-config#1654). The lock
# only stops two heavy commands overlapping; one check alone took ~3 GB of an 8 GB homelab
# and the kernel OOM killer took the worker's whole scope and two services with it. With
# MemoryMax the kill stays inside this scope. A probe first tells "no user scope here" (a
# hosted CI runner, no user bus) from the command itself failing.
capped=0
case "$memory_max" in
  0 | off) ;;
  *)
    if "$systemd_run" --user --scope --quiet -p "MemoryMax=$memory_max" -- true >/dev/null 2>&1; then
      capped=1
    else
      echo "heavy-lock.sh: no user systemd scope here, running with no memory cap" >&2
    fi
    ;;
esac

rc=0
if [ "$capped" -eq 1 ]; then
  "$systemd_run" --user --scope --quiet -p "MemoryMax=$memory_max" -p MemorySwapMax=0 -- "$@" 9>&- || rc=$?
  if [ "$rc" -eq 137 ]; then
    echo "heavy-lock.sh: the command was killed (137), probably by its memory cap of $memory_max; raise it with HEAVY_LOCK_MEMORY_MAX, or run fewer files" >&2
  fi
else
  "$@" 9>&- || rc=$?
fi
exit "$rc"
