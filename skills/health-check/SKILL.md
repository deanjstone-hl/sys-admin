---
name: health-check
description: >
  One-shot WSL2 system and project health snapshot: disk space, memory, systemd user
  services, log file sizes, SSH permissions, and unpushed git commits. Use when the user
  says "health check", "system check", "status report", "check everything", "/health-check",
  or any variant asking for a general system health overview.
disable-model-invocation: true
---

# Health Check

Runs a parallel multi-point health scan and presents a colour-coded summary with action
items. Nothing is modified — read-only audit only.

## Execution

This is mechanical, read-only data collection with no judgment calls. Delegate the entire
scan to a Haiku subagent instead of running the steps inline — keeps the (usually Sonnet)
main session from burning tokens on rote `df`/`ps`/`systemctl`/`git` output:

```javascript
Agent({
  description: "Health check scan",
  subagent_type: "Explore",
  model: "haiku",
  prompt: `Run the WSL2 health check below and return ONLY the final formatted report
  (Step 8 format) — do not include raw command output in your response.

  <paste Steps 1–7 verbatim, substituting the actual ssh-perms-check stat commands for Step 5
  since the subagent cannot invoke the Skill tool>`
})
```

Present the returned report to the user as-is.

---

## Step 1 — Disk space

```bash
df -h / /mnt/c 2>/dev/null | awk 'NR==1 || /\/$/ || /\/mnt\/c/'
du -sh ~/repos/ ~/.argus/ ~/CORTEX/ 2>/dev/null | sort -h
```

Flag if `/` is below 10 GB free or above 85% used.

---

## Step 2 — WSL2 memory

```bash
free -h
# Top memory consumers
ps aux --sort=-%mem | head -8 | awk '{print $1, $2, $3, $4, $11}'
```

Flag if memory usage is above 80%.

---

## Step 3 — Systemd user services

Check all known argus-managed services and timers:

```bash
systemctl --user status agent-engine.service syncthing.service t3code.service \
  memory-reconcile.timer vault-sync.timer 2>/dev/null | \
  grep -E "●|Active:|Main PID:"
```

For each service, report: `active (running)` / `inactive (dead)` / `failed`.

Flag any service that should be running but isn't.

---

## Step 4 — Large log files

```bash
find ~/.argus/ ~/repos/argus/ /tmp/ -name "*.log" -size +50M 2>/dev/null | \
  xargs -I{} du -sh {} 2>/dev/null | sort -rh | head -10
```

Flag any log file over 50 MB. Suggest truncating with:
```bash
truncate -s 0 <file>
```
(Do not truncate automatically.)

---

## Step 5 — SSH permissions

Invoke the `ssh-perms-check` skill and fold its output into this report's SSH line.

---

## Step 6 — Git repos: unpushed commits and stale branches

Check key repos for commits that haven't been pushed:

```bash
for repo in ~/repos/argus ~/repos/myargus ~/repos/stockade ~/repos/atto1; do
  [ -d "$repo/.git" ] || continue
  ahead=$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null || echo "?")
  branch=$(git -C "$repo" branch --show-current 2>/dev/null)
  [ "$ahead" != "0" ] && echo "$repo ($branch): $ahead unpushed commit(s)"
done
```

Also report repos with uncommitted changes:

```bash
for repo in ~/repos/argus ~/repos/myargus ~/repos/stockade ~/repos/atto1; do
  [ -d "$repo/.git" ] || continue
  dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
  [ "$dirty" -gt 0 ] && echo "$repo: $dirty uncommitted file(s)"
done
```

---

## Step 7 — Agent engine status

```bash
if [ -f ~/.argus/engine.pid ]; then
  pid=$(cat ~/.argus/engine.pid)
  ps -p "$pid" -o pid,stat,etime,cmd 2>/dev/null || echo "PID $pid not running (stale PID file)"
else
  echo "Engine: no PID file — not started"
fi

# Quick HTTP ping
curl -sf http://localhost:3747/health 2>/dev/null | head -1 || echo "Engine HTTP: not responding"
```

---

## Step 8 — Report

Present as a summary table:

```
HEALTH CHECK — <date>
─────────────────────────────────────────────
✓ Disk: / has 45 GB free (22% used)
✗ Memory: 87% used — top: node (1.2 GB), claude (340 MB)
✓ agent-engine: active (running)
✗ Log: ~/.argus/engine.log is 230 MB — consider truncating
✓ SSH permissions: all correct
✗ argus (main): 3 unpushed commits
✓ Engine: responding on :3747
─────────────────────────────────────────────
2 issues found. See above for fix commands.
```

Use ✓ for passing, ✗ for flagged items. List actionable commands for each ✗.

If everything is clean: "All systems healthy — nothing to action."
