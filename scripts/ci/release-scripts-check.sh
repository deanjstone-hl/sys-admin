#!/usr/bin/env bash
# Fails when this repo's vendored release scripts have drifted from the argus-config
# source they name (argus-config#1269, map #1259).
#
# argus-config holds the one source of release-with-retry.sh, release-proof.sh, release-gate.sh and this
# script. Every deploy repo vendors all three byte-for-byte, with a release-scripts.lock
# beside them that names the source commit and the sha256 of each file.
# `scripts/sync-release-scripts.sh <repo>` in argus-config writes the copies and the lock;
# nobody edits them in a deploy repo. Run this from the repo's CI.
#
#   bash scripts/ci/release-scripts-check.sh                    # the directory of this script
#   bash scripts/ci/release-scripts-check.sh <dir>              # another directory
#   bash scripts/ci/release-scripts-check.sh --source <checkout> [<dir>]
#
# Offline, it compares each copy with the hash in the lock: a hand-edited script is red.
# That alone cannot catch an edit that also rewrites the lock, nor this script itself
# being edited; with --source (a checkout of argus-config that has the named commit) it
# also compares the lock with the file as committed at that commit.
# A repo that is merely behind argus-config main is not drift: the lock still names a real
# version. Syncing is how it catches up.
set -uo pipefail

source_repo=""
dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --source)
      [ "$#" -ge 2 ] || { echo "release-scripts-check: --source needs a checkout" >&2; exit 2; }
      source_repo="$2"
      shift 2
      ;;
    -*)
      echo "release-scripts-check: unknown option $1" >&2
      exit 2
      ;;
    *)
      dir="$1"
      shift
      ;;
  esac
done
dir="${dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
lock="$dir/release-scripts.lock"
source_dir="scripts/ci"
files=(release-gate.sh release-proof.sh release-scripts-check.sh release-with-retry.sh)
fix="run scripts/sync-release-scripts.sh from argus-config against this repo"

sha256_of() {
  if command -v sha256sum > /dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

failed=0
fail() {
  echo "release-scripts-check: $*" >&2
  failed=1
}

if [ ! -f "$lock" ]; then
  echo "release-scripts-check: no release-scripts.lock in $dir ($fix)" >&2
  exit 1
fi

# The config repo is being renamed argus-config -> config and moved between owners
# (argus-config#1401), so a lock may name either owner and either name.
named_commit=$(sed -n -E 's#^source deanjstone(-hl)?/(argus-config|config) ([0-9a-f]{7,40})$#\3#p' "$lock" | head -n 1)
[ -n "$named_commit" ] || fail "$lock names no source commit (a 'source deanjstone/argus-config <sha>' line, or deanjstone-hl/ or /config)"

for name in "${files[@]}"; do
  locked=$(sed -n "s/^\([0-9a-f]\{64\}\)  $name\$/\1/p" "$lock" | head -n 1)
  if [ -z "$locked" ]; then
    fail "$name is not listed in release-scripts.lock ($fix)"
    continue
  fi
  if [ ! -f "$dir/$name" ]; then
    fail "drift: $name is missing from $dir ($fix)"
    continue
  fi
  actual=$(sha256_of < "$dir/$name")
  if [ "$actual" != "$locked" ]; then
    fail "drift: $name differs from argus-config@${named_commit:0:7} (lock ${locked:0:12}, copy ${actual:0:12}); never edit it here, $fix"
  fi
  if [ -n "$source_repo" ] && [ -n "$named_commit" ]; then
    if ! git -C "$source_repo" cat-file -e "${named_commit}^{commit}" 2> /dev/null; then
      continue
    fi
    committed=$(git -C "$source_repo" show "$named_commit:$source_dir/$name" 2> /dev/null | sha256_of)
    if [ "$committed" != "$locked" ]; then
      fail "the lock does not match $name at argus-config@${named_commit:0:7} (lock ${locked:0:12}, source ${committed:0:12}); $fix"
    fi
  fi
done

if [ -n "$source_repo" ] && [ -n "$named_commit" ] \
   && ! git -C "$source_repo" cat-file -e "${named_commit}^{commit}" 2> /dev/null; then
  fail "the source checkout $source_repo has no commit ${named_commit:0:7} (git fetch it, or $fix)"
fi

if [ "$failed" -ne 0 ]; then
  exit 1
fi
if [ -n "$source_repo" ]; then
  echo "release-scripts-check: ${#files[@]} scripts in sync with source commit ${named_commit:0:7}"
else
  echo "release-scripts-check: ${#files[@]} scripts in sync with the lock (argus-config@${named_commit:0:7})"
fi
