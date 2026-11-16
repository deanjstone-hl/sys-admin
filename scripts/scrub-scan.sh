#!/usr/bin/env bash
# The scrub gate for a public tree (skills/27): gitleaks' default rules plus the personal-data
# rules in .gitleaks.toml (tailnet and LAN addresses, tailnet hostnames, email addresses, AU
# mobile numbers, Cloudflare ids and UUIDs).
#
#   bash scripts/scrub-scan.sh            scan the tracked and new files as they are on disk (so no
#                                         node_modules, dist or ignored file)
#   bash scripts/scrub-scan.sh --head     scan the tracked files at HEAD (git archive)
#   bash scripts/scrub-scan.sh <dir>      scan that directory as it is
#
# Prints `scrub-scan: pass` or `scrub-scan: FAIL: N finding(s)`, then one line per finding
# with rule, file and line. Every value is redacted (--redact=100): this never prints one.
# Needs gitleaks on PATH. Run by scripts/owner-steps/27.sh on the tree it would publish.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="$root/.gitleaks.toml"

command -v gitleaks > /dev/null || { echo "scrub-scan: gitleaks is not on PATH" >&2; exit 2; }
[ "$#" -le 1 ] || { echo "usage: $0 [dir]" >&2; exit 2; }

target="${1:-}"
workdir=""
cleanup() { [ -z "$workdir" ] || rm -rf "$workdir"; }
trap cleanup EXIT
if [ -z "$target" ] || [ "$target" = "--head" ]; then
  workdir="$(mktemp -d)"
  if [ "$target" = "--head" ]; then
    git -C "$root" archive HEAD | tar -x -C "$workdir"
  else
    # Tracked files and new ones not yet added (never an ignored file).
    git -C "$root" ls-files -z --cached --others --exclude-standard | tar -C "$root" --null -T - -cf - 2> /dev/null | tar -x -C "$workdir"
  fi
  target="$workdir"
fi
[ -d "$target" ] || { echo "scrub-scan: $target is not a directory" >&2; exit 2; }

report="$(mktemp)"
trap 'cleanup; rm -f "$report"' EXIT
set +e
gitleaks dir "$target" --config "$config" --redact=100 --no-banner --log-level error \
  --report-format json --report-path "$report" --exit-code 1 > /dev/null 2>&1
status=$?
set -e
[ "$status" -le 1 ] || { echo "scrub-scan: gitleaks failed (exit $status)" >&2; exit 2; }

count="$(jq 'length' "$report")"
if [ "$count" -eq 0 ]; then
  echo "scrub-scan: pass (0 findings)"
  exit 0
fi
echo "scrub-scan: FAIL: $count finding(s)"
jq -r --arg base "$target/" '.[] | "  \(.RuleID)  \(.File | ltrimstr($base)):\(.StartLine)"' "$report"
exit 1
