---
name: config-audit
description: >
  Detect configuration drift across WSL2: stale path references, settings.json drift
  and skill-link health (both delegated to argus-config's own dry-runs), SSH key
  permissions, and missing Bitwarden item names for active projects. Use when the user says "audit config", "check settings", "config drift",
  "check for drift", "/config-audit", or any variant asking to validate system configuration
  consistency.
disable-model-invocation: true
---

# Config Audit

Runs a multi-point configuration health check and reports what's inconsistent, stale, or
missing — with suggested fixes for each finding.

## Execution

This is mechanical, read-only scanning with no judgment calls. Delegate the entire audit
to a Haiku subagent instead of running the steps inline — keeps the (usually Sonnet)
main session from burning tokens on rote `grep`/`diff`/`stat` output:

```javascript
Agent({
  description: "Config drift audit",
  subagent_type: "Explore",
  model: "haiku",
  prompt: `Run the config audit below and return ONLY the final formatted report
  (Step 6 format) — do not include raw command output in your response.

  <paste Steps 1–5 verbatim, substituting the actual ssh-perms-check stat commands for Step 3
  since the subagent cannot invoke the Skill tool. Steps 2 and 5 run argus-config's own
  --dry-run scripts; they write nothing>`
})
```

Present the returned report to the user as-is.

---

## Step 1 — Stale path references

Scan for legacy path refs that should be `~/repos/argus/`. Two prior layouts can show
up: the pre-`~/projects/` bare `~/argus/`, and `~/projects/argus/` itself now that
`~/projects/` has been renamed to `~/repos/`.

```bash
grep -rE "~/argus/|~/projects/argus/" \
  ~/.claude/settings.json \
  ~/repos/argus-config/envs/wsl2/ \
  ~/bin/ \
  ~/.bashrc ~/.zshrc ~/.profile \
  2>/dev/null | grep -v ".git"
```

Also scan for the fully-qualified variants:

```bash
grep -rE "/home/deanj/argus/|/home/deanj/projects/argus/" \
  ~/repos/argus-config/ \
  ~/bin/ \
  2>/dev/null | grep -v ".git"
```

Flag every match. The correct path is always `~/repos/argus/` or `/home/deanj/repos/argus/`.

---

## Step 2 — settings.json drift (argus-config owns this)

argus-config owns Claude Code's settings, so its sync script is the check. Run it from the
**primary checkout** (a worktree only warns, and its diff is not the deploy copy's). Both
runs are read-only:

```bash
bash ~/repos/argus-config/scripts/sync-settings.sh wsl2 --dry-run
bash ~/repos/argus-config/scripts/sync-settings.sh windows --dry-run
```

Read the `keys changing in live:` line of each. `(none — already in sync)` is clean; any
named key means the live file differs from the repo copy. `preserved from live:` keys
(`autoMode`, `model`, `effortLevel`, `modelSettings`) are live-only on purpose, so they
are not drift. An `ERROR: live has key(s) not in the repo copy` is a finding: report it
as written.

The fix for drift is the same command without `--dry-run`, run by the owner. Never hand-copy
the repo file over a live one.

---

## Step 3 — SSH key permissions

Invoke the `ssh-perms-check` skill and fold its output into this report's SSH row.

---

## Step 4 — Bitwarden item coverage

Check that known Bitwarden item names are present (existence check only — not secret values).

```bash
source ~/.bw_session 2>/dev/null
```

If session is missing or expired, skip this step and note: "BW session unavailable — skipping
Bitwarden item check. Run bw-unlock to enable."

If session is valid, check for known item names:

```bash
bw list items --session "$BW_SESSION" --nointeraction 2>/dev/null | \
  jq -r '.[].name' | sort
```

Expected items (check these are present):
- `telegram-argus-ccgram-bot-token`
- `mcp-memory-cloudflare-api-token`
- `agent-engine-supabase-url`

Flag any that are absent.

---

## Step 5 — Skill and config link health (argus-config owns this)

`install-wsl2.sh` ends with `verify_managed_links`, which checks that every link it manages
(including each `~/.claude/skills/*` entry) exists and resolves. Run its dry-run from the
primary checkout; it changes nothing:

```bash
bash ~/repos/argus-config/scripts/install-wsl2.sh --dry-run
```

Read the `Verification` section at the end. A `DANGLING:` or `⚠` line is a finding; `✓ all
… resolve` is clean. The `[dry-run] ln -sfn` lines above it are the plan, not drift, except
where they say `relinked … (was pointing elsewhere)` for a path other than the checkout the
script ran from.

Skills that come from this repo (`~/repos/sys-admin/skills/<name>/`) are outside
argus-config's installer. Check only those:

```bash
for s in ~/.claude/skills/*/; do
  target=$(readlink -f "$s" 2>/dev/null)
  if [ ! -d "$target" ]; then
    echo "DANGLING: $s → $target"
  fi
done
```

---

## Step 6 — Report

Present findings as a table with status indicators:

| Area | Status | Finding |
|------|--------|---------|
| Stale paths | ✓ / ✗ | N files with legacy ~/argus/ or ~/projects/argus/ refs |
| settings.json drift | ✓ / ✗ | Keys changing in live, per `sync-settings.sh` (wsl2 and windows) |
| SSH permissions | ✓ / ✗ | List of files with wrong perms |
| Bitwarden items | ✓ / skip | Missing item names if any |
| Skill and config links | ✓ / ✗ | Findings from `install-wsl2.sh --dry-run` verification; dangling sys-admin skill links |

For each finding, provide the exact command to fix it.

If all checks pass, report: "Config looks clean — no drift detected."
