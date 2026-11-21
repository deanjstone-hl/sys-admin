---
name: syncthing-pair
description: >
  Add a new device to Syncthing and share folders to it across the WSL/LGN5/iOS/homelab
  mesh. Handles device ID discovery, config.xml editing, and WSL2 mirrored-networking
  quirks (127.0.0.1 for local peers, Tailscale IPs for external). Use when the user says
  "add <machine> to syncthing", "pair syncthing with <machine>", "sync <machine>",
  or "share <folder> with <machine>".
disable-model-invocation: true
---

# Syncthing Pair Skill

Adds a new device to the Syncthing mesh and shares one or more folders to it.

Node names: **WSL** is the WSL2 instance on LNV-LGN5, **LGN5** is its Windows host.

The tables below are a cache of live state, read 2026-10-17. Full device IDs, the topology
history and the Tailscale-only posture live in
[`scripts/syncthing/README.md`](../../scripts/syncthing/README.md). Live config wins over
this file: Step 0 re-reads it.

**Private values are keys, not text.** This repository is public, so each Tailscale address
below is the name of a Bitwarden Secrets Manager (`bws secret list`) secret of the same name:
`SYS_ADMIN_TAILSCALE_IP_WSL`, `SYS_ADMIN_TAILSCALE_IP_LAPTOP`, `SYS_ADMIN_TAILSCALE_IP_HOMELAB`
and `SYS_ADMIN_TAILSCALE_IP_IPHONE`. Read one with
`bash scripts/private-value.sh <KEY>` (it prints the environment variable of that name if set,
else the secret, and never anything else). Device IDs are named by their 7-character prefix;
the full ID is never written here.

---

## Mesh topology (live, 2026-10-17)

Every node runs Syncthing v2.1.2. homelab is the introducer: WSL and LGN5 set
`introducer="true"` on their entry for homelab.

| Node | Service | Config path | GUI | BEP listen |
|------|---------|-------------|-----|------------|
| WSL (`lnv-lgn5-wsl`) | apt, `syncthing.service` user unit | `~/.local/state/syncthing/config.xml` | `http://127.0.0.1:8385` | `<SYS_ADMIN_TAILSCALE_IP_WSL>:22001`, `127.0.0.1:22001` |
| LGN5 (`lnv-lgn5`) | native `Syncthing` Windows Service (NSSM) | `/mnt/c/Users/deanj/AppData/Local/Syncthing/config.xml` | `http://127.0.0.1:8386` | `default` (`:22000`) |
| homelab | apt, `syncthing.service` user unit (user `srvr`) | `ssh homelab` → `~/.config/syncthing/config.xml` | `https://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:8384` | `<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000` |
| dj15 (iPhone) | SyncTrain app (VaultSync also paired from LGN5) | App UI only | — | outbound only |

## Devices

Use the short name when adding a device. Live configs still carry older names until
[#161](https://github.com/deanjstone/sys-admin/issues/161) renames them, so match a device
by its ID prefix, never by its name.

| Name | ID prefix | Live names still in config | Tailscale IP |
|------|-----------|----------------------------|--------------|
| `WSL` | `QZY5U6X` | `LNV-LGN5` (own), `LGN5-WSL2` (LGN5), `wsl2` (homelab) | `<SYS_ADMIN_TAILSCALE_IP_WSL>` |
| `LGN5` | `EJZYLDC` | `LNV-LGN5` (all nodes) | `<SYS_ADMIN_TAILSCALE_IP_LAPTOP>` |
| `homelab` | `QUTF5GA` | — | `<SYS_ADMIN_TAILSCALE_IP_HOMELAB>` |
| `dj15-SyncTrain` | `LTS4Z7E` | — | `<SYS_ADMIN_TAILSCALE_IP_IPHONE>` |
| `dj15-VaultSync` | `X2ASWHV` | LGN5 config only | `<SYS_ADMIN_TAILSCALE_IP_IPHONE>` |

Only the hosts above are mesh nodes; any other tailnet host is outside the mesh.

## Folders

| Folder ID | Label | Shared between |
|-----------|-------|----------------|
| `CONTEXT` | CONTEXT | all nodes |
| `CORTEX` | CORTEX | all nodes |
| `claude-sessions-wsl2` | claude-sessions (WSL2) | WSL → homelab only (`~/.claude/projects` → `/home/srvr/.argus/remote-sessions/wsl2`) |

---

## Step 0 — Re-read live config

Print each node's devices, addresses and folders, with IDs cut to a 7-character prefix and
no secrets:

```bash
cat > /tmp/st-mesh.py <<'EOF'
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
for d in r.findall("device"):
    print("device", d.get("id")[:7], d.get("name"), [a.text for a in d.findall("address")])
for f in r.findall("folder"):
    print("folder", f.get("id"), [x.get("id")[:7] for x in f.findall("device")])
EOF
python3 -I /tmp/st-mesh.py ~/.local/state/syncthing/config.xml                          # WSL
python3 -I /tmp/st-mesh.py /mnt/c/Users/deanj/AppData/Local/Syncthing/config.xml       # LGN5
scp -q /tmp/st-mesh.py homelab:/tmp/ && ssh homelab 'python3 -I /tmp/st-mesh.py ~/.config/syncthing/config.xml; rm /tmp/st-mesh.py'
```

Done when every row you will rely on in the tables above matches this output. Where they
differ, use the live value and tell the user the table is stale.

---

## Step 1 — Identify the new device

Ask the user (or infer from the prompt):
- Which machine is being added? (WSL / LGN5 / homelab / iOS / other)
- Which folders should be shared to it?

Done when both are named.

---

## Step 2 — Get the new device's ID

On a Linux node, `syncthing device-id` prints the node's own ID:

```bash
syncthing device-id                    # WSL
ssh homelab "syncthing device-id"      # homelab
```

LGN5: ask its REST API, reading the key inside the command:

```bash
key=$(grep -oP '(?<=<apikey>)[^<]+' /mnt/c/Users/deanj/AppData/Local/Syncthing/config.xml)
curl -s -H "X-API-Key: $key" http://127.0.0.1:8386/rest/system/status | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['myID'])"
```

iOS: copy it from the app.

A config.xml's first `<device>` is often a *peer*, not the node itself, so take the ID
from one of the commands above.

---

## Step 3 — Determine the correct address

| Source → Target | Address to use |
|-----------------|----------------|
| WSL → LGN5 | `tcp://127.0.0.1:22000` (mirrored networking) |
| LGN5 → WSL | `tcp://127.0.0.1:22001` (WSL's BEP port) |
| Any → homelab | `tcp://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000` |
| homelab → WSL | `tcp://<SYS_ADMIN_TAILSCALE_IP_WSL>:22001` |
| homelab → LGN5 | `tcp://<SYS_ADMIN_TAILSCALE_IP_LAPTOP>:22000` |
| Any → iOS | `tcp://<SYS_ADMIN_TAILSCALE_IP_IPHONE>:22000` |
| Any → new remote machine | `tcp://<tailscale-ip>:22000` |

WSL and LGN5 share one network stack, so they reach each other on loopback; every other leg
uses a Tailscale IP. Give each new peer entry exactly the address above. The existing
dj15-SyncTrain entries on WSL and LGN5 also carry `dynamic`; leave them as they are, since
[#161](https://github.com/deanjstone/sys-admin/issues/161) cleans them up.

---

## Step 4 — Add the device to the existing nodes

Stop the node's Syncthing first: a running instance rewrites config.xml on shutdown and
discards your edit.

```bash
systemctl --user stop syncthing                   # WSL
ssh homelab "systemctl --user stop syncthing"     # homelab
```

LGN5: `Stop-Service Syncthing` needs an elevated PowerShell (UAC prompt), so ask the user
to run it. Then confirm it from WSL, since editing a running instance's config loses the
edit:

```bash
powershell.exe -NoProfile -Command "(Get-Service Syncthing).Status"   # must print Stopped
```

`scripts/syncthing/pair-device.sh` is a shortcut for one case only: re-pairing `wsl2`,
`windows` or `dj15` onto homelab. Its device list is hardcoded, so it cannot add a new
device. When it fits, run it on homelab: it goes through homelab's REST API with no stop
needed. Every other case takes the config.xml edit below.

Add to the target node's `<configuration>`:

```xml
<device id="<NEW-DEVICE-ID>" name="<short-name>" compression="metadata" introducer="false" skipIntroductionRemovals="false" introducedBy="">
    <address><computed-address></address>
</device>
```

Use the Edit tool for WSL and LGN5 configs. For homelab, use SSH + heredoc.

---

## Step 5 — Share folders to the new device

For each folder, add inside its `<folder id="...">` block (IDs in the Folders table):

```xml
<device id="<NEW-DEVICE-ID>" introducedBy=""></device>
```

Done when every requested folder carries the new device on every node that shares it.

---

## Step 6 — Restart Syncthing

```bash
systemctl --user start syncthing                  # WSL
ssh homelab "systemctl --user start syncthing"    # homelab
```

LGN5: ask the user to run `Start-Service Syncthing` in an elevated PowerShell, then
confirm `Running` with the `Get-Service` command from Step 4.

---

## Step 7 — Verify pairing

Read the API key inside the command so it never reaches the transcript:

```bash
key=$(grep -oP '(?<=<apikey>)[^<]+' ~/.local/state/syncthing/config.xml)
curl -s -H "X-API-Key: $key" http://127.0.0.1:8385/rest/system/connections | \
  python3 -c "import sys,json; c=json.load(sys.stdin)['connections']; [print(k[:7],v['connected']) for k,v in c.items()]"
```

On homelab use its config path and `https://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:8384` with `curl -sk`; on LGN5,
its config path and `http://127.0.0.1:8386`.
Allow up to 60 seconds for the initial handshake.

---

## Step 8 — Report

```
Syncthing pair complete
  New device: <name> (<device-id-prefix>...)
  Nodes updated: WSL | LGN5 | homelab
  Folders shared: <folder names>
  Status: connected | pending handshake
```

---

## Rules

- **Stop the node's Syncthing before editing** its config.xml, confirm it stopped, restart after
- **Use 127.0.0.1** for WSL↔LGN5 (mirrored networking); WSL's BEP port is 22001
- **Use Tailscale IPs** for every other peer, never `dynamic`
- **Match devices by ID prefix**, never by name
- **Keep the API key and GUI password hash out of output**: read them inside the command
