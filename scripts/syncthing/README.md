---
type: reference
title: Syncthing Setup
description: Syncthing topology, device registry, and setup guide for all nodes
tags: [syncthing, infrastructure, cortex]
timestamp: 2026-06-20T00:00:00Z
---

# Syncthing Setup

Syncthing handles cross-device file sync for the CORTEX vault across all nodes.

CORTEX lives at `~/CORTEX` on every device. The WSL2 instance runs as a systemd user service and is peered with Windows. Memory symlink: `~/.claude/memory → ~/CORTEX/MEMORY`.

## Topology

**Current (live, applied 2026-07-31 — sys-admin#37):**

Homelab is the Syncthing introducer. All three direct legs to homelab are now
connected: WSL2↔homelab (closed the gap that let WSL2 sit silently at 66.5%
completion against Windows while homelab was fully synced, undetected until
an INDEX.md conflict surfaced it — see `sys-admin#32`, wayfinder map, closed),
Windows↔homelab (fixed 2026-07-31 — see below), and dj15↔homelab (already
connected via SyncTrain; the abandoned VaultSync device was removed from every
node, sys-admin#127).

```
        WSL2 ───────────────── Windows
          │  \                /   │
          │   \              /    │
          │    \            /     │
        homelab ─────────────────┘
       (introducer)   │
                       │
                     dj15 (iPhone)
                       SyncTrain
```

All four legs to/through homelab are live and connected as of 2026-07-31.

- **Auto-accept:** introducer-driven auto-accept of new device/folder offers
  is trusted **from homelab only** — `introducer="true"` set on WSL2's and
  Windows's device entries *for homelab* (Windows's flag set 2026-07-31 as
  part of the fix below). Homelab's own entries for WSL2/Windows stay
  `introducer="false"` (homelab is the source of introductions, not a
  follower).
- **Folder-sharing matrix:** CONTEXT and CORTEX both shared identically
  across nodes — no per-node narrowing. WSL2's CONTEXT/CORTEX folders now
  include Windows, dj15, and homelab; homelab's include Windows, dj15, WSL2.
- **Why homelab-only auto-accept:** dj15 (iPhone) is the highest-friction
  node to manually re-pair, so trusting homelab specifically (not a blanket
  auto-accept from anywhere) covers that case without giving up manual review
  for the WSL2/Windows leg.
- **Windows↔homelab fix (2026-07-31):** two independent root causes, both
  fixed:
  1. Windows's `config.xml` had `<address>dynamic</address>` for the
     homelab device entry, relying on global discovery/relay/NAT
     traversal — all explicitly disabled on homelab by the Tailscale-only
     lockdown below. Fixed to `tcp://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000`
     (`introducer="true"` also set, closing the auto-accept gap above).
  2. Independently, Windows's `Syncthing` service (see Notes — native
     Windows Service via NSSM, not SyncTrayzor) had been stopped since
     2026-07-30 12:06 (clean shutdown, likely a reboot/update) despite
     `StartType: Automatic` — it simply never restarted. Started via
     elevated PowerShell (`Start-Service`, UAC-approved). Both fixes were
     required; the address fix alone would have stayed inert with the
     service down.
- **sys-admin#36 completed 2026-07-31:** Windows versioning/watcher-delay
  change applied via its REST API (`PUT /rest/config/folders/<id>`, key read
  from `config.xml`) once argus-config#97 (classifier block on Syncthing
  REST mutations) closed — no GUI edit needed after all. All three nodes
  now match. SyncTrain is the active iOS client and works fine.

## Device Registry

| Name | Device ID | Tailscale IP | OS | App |
|---|---|---|---|---|
| LNV-LGN5-WSL2 | `QZY5U6X` | `<SYS_ADMIN_TAILSCALE_IP_WSL>` | Ubuntu/WSL2 | syncthing (systemd user) |
| LNV-LGN5 (Windows) | `EJZYLDC` | `<SYS_ADMIN_TAILSCALE_IP_LAPTOP>` | Windows 11 | syncthing (native, Windows Service via NSSM — SyncTrayzor removed) |
| dj15 (iPhone) | `LTS4Z7E` | `<SYS_ADMIN_TAILSCALE_IP_IPHONE>` | iOS | SyncTrain (`dj15-SyncTrain` in the live config). The earlier VaultSync device (`dj15-VaultSync`, `X2ASWHV…`) was abandoned and removed from every node ([#127](https://github.com/deanjstone/sys-admin/issues/127)). |
| homelab (Dell Inspiron) | `QUTF5GA` | `<SYS_ADMIN_TAILSCALE_IP_HOMELAB>` | Ubuntu 24.04 | syncthing (systemd user), introducer (`sys-admin#37`) |

## Folder Map

| Folder ID | Label | Canonical path | Devices (live, 2026-10-29) | Purpose |
|---|---|---|---|---|
| `CORTEX` | CORTEX | `C:\Users\deanj\CORTEX` (Windows) · `/home/deanj/CORTEX` (WSL2) · `/home/srvr/CORTEX` (homelab) | LNV-LGN5-WSL2, homelab, Windows, dj15 — all connected | CORTEX vault sync |
| `CONTEXT` | CONTEXT | `/home/deanj/CONTEXT` (WSL2) · `/home/srvr/CONTEXT` (homelab) | LNV-LGN5-WSL2, homelab, Windows, dj15 — all connected | CONTEXT vault sync |
| `claude-sessions-wsl2` | claude-sessions (WSL2) | `/home/deanj/.claude/projects` (WSL2, send-only) · `/home/srvr/.argus/remote-sessions/wsl2` (homelab, receive-only) | LNV-LGN5-WSL2, homelab | Claude Code session transcripts, WSL2 → homelab |

The Syncthing `default` folder (`/home/deanj/Sync`) no longer exists on any node.

## GUI Access

| Node | URL |
|---|---|
| WSL2 (local) | http://127.0.0.1:8385 |
| WSL2 (remote via Tailscale) | https://<SYS_ADMIN_TAILSCALE_HOST_WSL>:8384 |
| Windows | http://127.0.0.1:8386 (native service — **not 8384**, see Notes) |
| Homelab | https://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:8384 |

## Config Locations

| Node | Config path |
|---|---|
| WSL2 | `~/.local/state/syncthing/config.xml` |
| Windows (Syncthing, native service via NSSM) | `%LOCALAPPDATA%\Syncthing\config.xml` |
| Homelab | `~/.config/syncthing/config.xml` |

## Setup Scripts

| Script | Purpose |
|---|---|
| [setup-wsl2.sh](setup-wsl2.sh) | Install + enable Syncthing on WSL2 |
| [setup-windows.md](setup-windows.md) | **Stale — describes SyncTrayzor setup.** Windows now runs native Syncthing as an NSSM-managed Windows Service (see Notes below); this doc needs a rewrite to match. |
| [pair-device.sh](pair-device.sh) | Run 2026-07-30 for `wsl2` against homelab. Adds a known device (wsl2/windows/dj15) to homelab's own Syncthing config, via homelab's local REST API (`https://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:8384`, `-k` for self-signed TLS). Per ADR-002 (argus-config#97/#98) — a named wrapper script, not a general REST allow-rule. Run *on* homelab. Windows and dj15 legs are now both connected (Windows fixed manually 2026-07-31 — dynamic address + stopped service, not re-run via this script; dj15 was already connected via SyncTrain). |
| [trigger-rescan.sh](trigger-rescan.sh) | **Not yet run as a script**, though its underlying action (`POST /rest/db/scan`) was run ad hoc via curl/PowerShell on 2026-07-31 to apply the `(?d).git/` global-model fix on WSL2, homelab, and Windows. Not called by the drift poller below — that poller only alerts, per #35's locked resolution — kept for manual/future use. |
| [reset-gui-password.sh](reset-gui-password.sh) | Reset the GUI password on a node that is already set up ([#104](https://github.com/deanjstone/sys-admin/issues/104)). Syncthing's own `syncthing generate --gui-password=-` does the bcrypt hashing into config.xml's `<gui>` block; keys, device ID and API key are kept. The password comes from `--bw-item <item>` (Bitwarden) or stdin, never an argument. Stops and restarts the `syncthing.service` user unit around the write. Run *on* the node being reset. Provisioning is homelab's `install.sh` phase 7, not this. Example: `./reset-gui-password.sh --bw-item <item>`. |
| drift-poller.sh | **Moved to homelab** ([homelab#101](https://github.com/deanjstone/homelab/issues/101)). Runs only on homelab against its own Syncthing API, so it now lives at [`homelab/services/syncthing-drift-poller/`](https://github.com/deanjstone/homelab/tree/main/services/syncthing-drift-poller). Built under sys-admin#35. |

## Conflict/versioning + watcher-delay changes (sys-admin#36, applied on all 3 nodes — WSL2 + homelab 2026-07-30, Windows 2026-07-31)

`config.xml` changes for the CONTEXT and CORTEX `<folder>` elements:

```diff
- fsWatcherDelayS="10"
+ fsWatcherDelayS="2"
```

```xml
<versioning type="simple">
    <param key="keep" val="5"/>
    <param key="cleanoutDays" val="0"/>  <!-- 0 = no time cap, keep last 5 -->
</versioning>
```

Applied via each node's REST API (`PUT /rest/config/folders/<id>`). WSL2 and
homelab applied 2026-07-30 with a service restart; Windows applied
2026-07-31 via the same REST endpoint (`http://127.0.0.1:8386`, API key
read from `config.xml`, no restart required — REST config writes apply
live). Previously thought to need a manual GUI edit since the native
service has no obvious remote write path, but the REST API works
identically to the other two nodes once the key is sourced locally.

## Tailscale-only lockdown (applied on homelab 2026-07-30)

Homelab's Syncthing previously listened on `default` (0.0.0.0, all interfaces) with relays, global announce, and NAT traversal enabled — inconsistent with the Tailscale-only posture the other three nodes already had. Fixed via `PUT /rest/config/options`:

```diff
- listenAddress: default
+ listenAddresses: [tcp://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000, quic://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000]
- relaysEnabled: true
+ relaysEnabled: false
- globalAnnounceEnabled: true
+ globalAnnounceEnabled: false
- natEnabled: true
+ natEnabled: false
```

## Auto-mode wiring for the wrapper scripts above

Per ADR-002, each wrapper script needs its own scoped auto-mode allow-rule once it's actually wired into unattended automation (the drift poller). Draft rule (not yet added to `settings.json`):

```
Bash(*/scripts/syncthing/pair-device.sh:*)
Bash(*/scripts/syncthing/trigger-rescan.sh:*)
```

Scoped to the script paths, not to `curl` or the REST endpoint directly — see ADR-002 for why a broader rule was rejected.

## Security: Tailscale-only enforcement

All four nodes are configured to sync **only over Tailscale** — no LAN, no relay servers.

| Setting | WSL2 | Windows | iOS | homelab |
|---|---|---|---|---|
| Listen addresses | `tcp/quic://<SYS_ADMIN_TAILSCALE_IP_WSL>:22001` only | `default` (0.0.0.0:22000) — firewall enforces Tailscale-only | N/A (outbound only) | `tcp/quic://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000` only (fixed 2026-07-30, was `default`) |
| Local discovery | ❌ disabled | ❌ disabled | ❌ disabled | ❌ disabled (fixed 2026-07-30) |
| Relays | ❌ disabled (2026-10-25) | ❌ disabled (2026-10-25) | ❌ disabled | ❌ disabled (fixed 2026-07-30, was enabled + actively joined) |
| Device addresses | Tailscale IPs only (no `dynamic`) | Tailscale IPs only (no `dynamic`) | Tailscale IPs only | Tailscale IPs only (no `dynamic`) |

**Consequence:** Syncthing will not sync on any WiFi network unless Tailscale is also connected. This is intentional — CORTEX is never exposed on untrusted networks.

## CORTEX completion% stuck at ~5.4% (sys-admin#37, fixed 2026-07-31)

CORTEX's per-device completion% (`/rest/db/completion`) looked permanently
stalled (e.g. `5.42%`, `needBytes: ~612MB`) no matter what — even after
correctly wiring `.git/` into the ignore patterns and confirming files showed
`ignored: true`, and even after a full Syncthing restart. Root cause: a
plain ignore pattern only stops *future* syncing of a file — it does not
retroactively purge an already-indexed file from a folder's aggregate
**global** model, so previously-synced `.git/` content stayed counted in
`globalBytes`/completion% forever.

**Fix:** changed the `.git/` line in `.stglobalignore` (synced vault content,
canonical copy on WSL2) to use the `(?d)` deletion-flag prefix:

```diff
- .git/
+ (?d).git/
```

`(?d)` tells Syncthing to mark already-indexed matches as *deleted* rather
than merely ignoring future changes to them — this is what actually shrinks
the global model. Each device only applies this to its own local index on
its next rescan of the folder (triggered via `POST /rest/db/scan?folder=X`,
or its normal periodic scan interval). Confirmed 2026-07-31: WSL2, homelab,
and Windows all converged from ~647MB to ~333MB in their own local/global
view after rescanning. **dj15 (iPhone) had not converged as of 2026-07-31**
— iOS Syncthing apps (SyncTrain) only rescan when foregrounded, so homelab's
overall aggregate stayed at the old, larger figure until the app is next
opened. Not a bug — just a background-execution limitation of the iOS app.

## Notes

- Windows Syncthing runs as a **native Windows Service** (`Syncthing`,
  managed by NSSM) — **SyncTrayzor was removed** after it proved unreliable
  at startup (see `context` vault memory `project_syncthing_windows_service`
  for the full NSSM config). It has `StartType: Automatic` but does not
  reliably self-restart after every stop; check
  `Get-Service Syncthing` if a connection looks dead.
- Windows Syncthing GUI is on **port 8386, not 8384** — WSL2's `tailscaled`
  holds port 8384 across all Windows interfaces via mirrored networking
  (Windows-side tools can't see WSL2-owned ports across the namespace
  boundary). See `context` vault memory
  `reference_wsl2_mirrored_port_conflict`.
- WSL2 Syncthing is installed via apt (`syncthing`) and runs as a user-scoped systemd service.
- WSL2 Syncthing runs on GUI port 8385 and BEP port 22001 (avoiding conflict with Windows via mirrored networking).
- **Local peers use `127.0.0.1`, not a Tailscale IP.** WSL2 and Windows share one network
  stack under mirrored networking, so the WSL2↔Windows leg is addressed on loopback: WSL2's
  entry for Windows is `tcp://127.0.0.1:22000`, Windows's entry for WSL2 is
  `tcp://127.0.0.1:22001`. Only peers on *another* machine (homelab, dj15) take a Tailscale
  address. The same applies to the GUI: reach a local node on `127.0.0.1:<gui-port>` (table
  above). This was rediscovered in four separate sessions before it was written down here
  ([#104](https://github.com/deanjstone/sys-admin/issues/104)).
- The WSL2 Tailscale serve rule exposes port 8384: `tailscale serve --bg --https=8384 http://localhost:8385`
- Conflict files follow the pattern `filename.sync-conflict-<timestamp>-<deviceid>`. See cleanup commands in the Windows setup guide.
- `~/.claude/memory` on WSL2 is symlinked to `~/CORTEX/MEMORY` — changes propagate to Windows and iOS via Syncthing.
- CORTEX was previously inside `C:\Users\deanj\Obsidian\` (moved 2026-06-20). The Syncthing folder ID also changed from `Obsidian` to `CORTEX`.
