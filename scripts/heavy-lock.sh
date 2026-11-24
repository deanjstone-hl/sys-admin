#!/usr/bin/env bash
# Host-wide lock for heavy commands: only one runs at a time on this host
# (argus-config#1488). On 19 Nov 2026 three overlapping full checks made systemd-oomd
# kill five agent scopes; "one heavy command at a time" only binds one thread.
#
#   bash scripts/heavy-lock.sh <command> [args...]
#
# It takes an flock on one file, waits (with a timeout) while memory pressure is high,
# then runs the command and exits with its status. Waiting is normal: a queued run
# prints what it waits for and carries on when the lock frees.
#
# Exit status: the command's own; 2 usage; 75 timed out waiting for the lock or for
# memory pressure to drop (EX_TEMPFAIL); 1 the lock file could not be opened.
#
# Env:
#   HEAVY_LOCK_FILE      the lock file (default /run/user/<uid>/heavy.lock; when that
#                        directory is missing, e.g. a hosted CI runner, falls back to
#                        ${TMPDIR:-/tmp}/heavy-lock-<uid>.lock)
#   HEAVY_LOCK_RUN_DIR   the directory of the default lock file (default /run/user/<uid>)
#   HEAVY_LOCK_TIMEOUT   seconds to wait in all (default 3600)
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
timeout_s="${HEAVY_LOCK_TIMEOUT:-3600}"
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

exec 9>>"$lock_file" || {
  echo "heavy-lock.sh: cannot open $lock_file" >&2
  exit 1
}

started=$SECONDS
deadline=$((started + timeout_s))

if ! flock -n 9; then
  echo "heavy-lock.sh: waiting for the host lock ($lock_file), another heavy command is running" >&2
  remaining=$((deadline - SECONDS))
  [ "$remaining" -ge 1 ] || remaining=1
  if ! flock -w "$remaining" 9; then
    echo "heavy-lock.sh: timed out after ${timeout_s}s waiting for the host lock" >&2
    exit 75
  fi
fi

if pressure_high; then
  echo "heavy-lock.sh: waiting for memory pressure to drop (some avg60 >= $psi_max)" >&2
  while pressure_high; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "heavy-lock.sh: timed out after ${timeout_s}s waiting for memory pressure to drop" >&2
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
  "$systemd_run" --user --scope --quiet -p "MemoryMax=$memory_max" -p MemorySwapMax=0 -- "$@" || rc=$?
  if [ "$rc" -eq 137 ]; then
    echo "heavy-lock.sh: the command was killed (137), probably by its memory cap of $memory_max; raise it with HEAVY_LOCK_MEMORY_MAX, or run fewer files" >&2
  fi
else
  "$@" || rc=$?
fi
exit "$rc"
