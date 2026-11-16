---
name: provision-server
description: >
  Provision a fresh Linux server using the phase-based install script in the homelab repo,
  over SSH. Handles the SSH-key, Tailscale, WiFi and Syncthing interactive pauses and
  supports resuming from a phase. Use when the user says "provision <server>", "set up
  linux server", "run server setup", "install phases on <host>", or any variant of
  initialising a new Ubuntu server in the Argus stack.
disable-model-invocation: true
---

# Provision Server

Drives `~/repos/homelab/scripts/install.sh` on the **target machine** over SSH. The script
is a chained phase runner: it starts at a phase and runs everything from there to the end.

**The phase scripts live in the `homelab` repo, not this one.** That repo is the machine's
own state; this skill is the tooling that runs it. Read
`~/repos/homelab/scripts/install.sh` before a run — if the phase list below disagrees with
it, the script wins and this file needs updating.

> **`homelab` itself is already provisioned.** This skill is for a *new* machine. Re-running
> phases against `homelab` would re-apply hardening, Tailscale and Docker setup to a live
> always-on host — confirm with the Director before pointing it at an existing server.

---

## Step 0 — Gate: is this work still needed?

Run this before any SSH. A provisioning request — especially one filed as a GitHub issue —
can already be done or superseded by a migration that predates it. sys-admin#71 asked to
provision a tool that ADR-003 had already migrated before the issue was filed.

1. **If triggered from an issue, read the issue and its comments.** Comments often carry
   the "already done" or "changed approach" signal the body does not.

   ```bash
   gh api repos/deanjstone/<repo>/issues/<n> --jq '.title, .state, .body'
   gh api repos/deanjstone/<repo>/issues/<n>/comments --jq '.[] | .user.login + ": " + .body'
   ```

2. **Check the ADR indexes and any migration docs or runbooks the issue references**, for
   decisions that make the work done, superseded or different. Search for the tool, service
   or phase named in the request:

   ```bash
   # homelab — the machine's own state and the phase scripts
   cat ~/repos/homelab/docs/DECISIONS.md
   grep -ril '<term>' ~/repos/homelab/docs/
   # sys-admin — cross-machine tooling, incl. ADR-003 (canonical user bin location)
   cat ~/repos/sys-admin/stack/docs/DECISIONS.md
   grep -ril '<term>' ~/repos/sys-admin/stack/docs/
   ```

   Pull first (`git -C <repo> fetch && git -C <repo> status`) so the docs are not stale.
   Open every migration doc or runbook the issue links, not just the ADRs.

3. **Check the related memories** with `memory_search` for the tool, service and host names
   (e.g. `memory_search "<term> homelab"`).

4. **If any evidence says the work is done or superseded, stop and report** — do not
   provision. Cite the ADR/doc/memory, verify the current state read-only where it is cheap
   (`ssh <host-alias> "command -v <tool>; <tool> --version"`), and, for an issue, comment
   with that evidence instead of re-running phases. Only continue to Step 1 when nothing
   says the work is done or changed.

---

## Step 1 — Identify the target host

If the user named a host, use it. Known hosts:

| Host | SSH alias | User | Notes |
|------|-----------|------|-------|
| homelab | `homelab` | `srvr` | Inspiron 5559; Ubuntu 24.04 LTS. **Already provisioned.** |

If the host is not named, ask with `AskUserQuestion`.

Verify connectivity:

```bash
ssh -o ConnectTimeout=5 <host-alias> "echo ok" 2>&1
```

Stop and report if unreachable.

---

## Step 2 — Bootstrap, if the repo is not on the machine yet

A genuinely fresh machine has no clone. `scripts/bootstrap.sh` installs git, clones the
repo and hands off to `install.sh`. It needs a fine-grained read-only PAT for
`deanjstone/homelab`, stored in Bitwarden as **`linux-server deploy token`** (the vault item
keeps its pre-rename name; only the repo was renamed).

```bash
ssh-copy-id srvr@<local-ip>
scp ~/repos/homelab/scripts/bootstrap.sh srvr@<local-ip>:~/
ssh srvr@<local-ip> "GITHUB_TOKEN=<pat> bash ~/bootstrap.sh"
```

Never echo the PAT into the transcript — read it from Bitwarden at the point of use.

---

## Step 3 — Determine the starting phase

If the user specified `--from=N`, use it.

Otherwise read the state file, which holds a single phase number:

```bash
ssh <host-alias> "cat ~/.linux-server-install-phase 2>/dev/null || echo none"
```

`install.sh` writes the just-completed phase number there and deletes the file on a
successful full run. So:

- file absent → either nothing has run, or everything has. Check for a provisioned machine
  (`tailscale status`, `systemctl --user list-units`) before assuming "fresh".
- file contains `N` → resume with `--from=$((N+1))`.

The default with no flag is `--from=3`; phases 0–2 do not exist.

---

## Step 4 — Phase map

| Phase | Name | Interactive? | Notes |
|-------|------|--------------|-------|
| 3 | Terminal setup | No | Shell, prompt, terminal config |
| 4 | OS hardening | **Yes** | Pauses for `ssh-copy-id` if `~/.ssh/authorized_keys` is empty, then again to confirm key-only login still works |
| 5 | Tailscale | **Yes** | Browser auth, then pauses for admin-console approval; opens `ufw` on `tailscale0` |
| 6 | Docker | No | Docker Engine. **Then prompts for optional WiFi setup** before phase 7 |
| 7 | Syncthing | **Yes** | Prompts for GUI username/password and sets them via the REST API |
| 8 | Claude Code | No | fnm + Node LTS + `claude`; needs a manual `claude` run to authenticate |
| 9 | Codex delegation | No | uv + Codex CLI |

---

## Step 5 — Run it

There is **no `--phase=N` flag.** Only `--from=N` is parsed, and it runs that phase and
every phase after it. Passing `--phase=8` is silently ignored, leaving the default
`--from=3` — which would re-run hardening, Tailscale, Docker and Syncthing on the target.
Always pass `--from=`.

Because the run chains phases and stops at interactive prompts, it needs a TTY:

```bash
ssh -t <host-alias> "bash ~/repos/homelab/scripts/install.sh --from=N"
```

Stream the output. The script is `set -euo pipefail`, so it stops on the first failure —
report the error and the phase it died in.

---

## Step 6 — Handle the pauses

Each pause is a `read` on the server's stdin, so the user answers them in the live session.
Tell them what is coming before the run reaches it:

- **Phase 4** — needs an SSH public key already copied, and asks them to verify key-only
  login from WSL2 in a second terminal before continuing.
- **Phase 5** — prints a Tailscale auth URL. They authenticate in a browser, then approve
  the node in the admin console, then press Enter.
- **Phase 6 → 7** — asks whether to configure WiFi before ethernet is unplugged.
- **Phase 7** — asks for a Syncthing GUI username and password. `install.sh` sets these
  itself via the REST API; no manual injection needed. If it warns it could not read the
  API key from `config.xml`, set the credentials by hand afterwards.

To pair the new machine into the Syncthing mesh, ask the owner to run `/syncthing-pair`
after phase 7 completes. That skill is hand-only: do not try to invoke it yourself.

---

## Step 7 — Verify

```bash
ssh <host-alias> "tailscale status | head -3; systemctl --user list-units --type=service --state=running | head -10; ls ~/repos/"
```

Report:
- Phases completed (and the state file's contents, or its absence on a full run)
- Tailscale: connected / pending approval
- Which services came up

Docker is **installed but disabled** on homelab by policy — do not treat a stopped
`docker.service` as a provisioning failure. See the homelab repo's `.claude/SYSTEM.md`.

---

## Rules

- **Step 0 is a gate, not a formality** — never start a run before checking the issue
  comments, ADRs, migration docs and memories for evidence the work is done or superseded.
- **Never skip interactive pauses** — phases 4, 5 and 7 need a human, and the WiFi prompt
  sits between 6 and 7.
- **Always `--from=N`, never `--phase=N`** — the latter does not exist and silently
  restarts the whole run from phase 3.
- **Use `ssh -t`** — the prompts need a TTY.
- **Re-running a phase is not always safe.** The script is broadly idempotent, but phases 4
  and 5 change firewall and SSH state on a live machine. Confirm with the Director before
  re-running either against a server that is already in use.
- **Do not attempt a Bitwarden unlock on the remote server** — secrets are bootstrapped via
  `bootstrap.sh` + the PAT pattern above.
