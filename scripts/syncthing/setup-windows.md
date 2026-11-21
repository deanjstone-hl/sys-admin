# Syncthing Windows Setup (native service via NSSM)

Setup guide for Syncthing on LNV-LGN5 (Windows 11). **SyncTrayzor was removed**
after it proved unreliable at startup — Syncthing now runs as a native
Windows Service, managed by NSSM (Non-Sucking Service Manager), using the
Syncthing binary that shipped with SyncTrayzor.

## Install

1. Get NSSM (already staged at `C:\Users\deanj\AppData\Local\Temp\nssm-setup\nssm.exe`
   on this machine; otherwise download from nssm.cc).
2. The Syncthing binary is at `C:\Users\deanj\AppData\Roaming\SyncTrayzor\syncthing.exe`
   (left in place from the old SyncTrayzor install — do not delete it, nothing
   else replaces it).
3. Register the service:

```powershell
nssm install Syncthing "C:\Users\deanj\AppData\Roaming\SyncTrayzor\syncthing.exe"
nssm set Syncthing AppParameters '--home "C:\Users\deanj\AppData\Local\Syncthing" --no-browser --allow-newer-config'
nssm set Syncthing AppEnvironmentExtra "USERPROFILE=C:\Users\deanj" "HOMEPATH=\Users\deanj" "HOMEDRIVE=C:"
nssm set Syncthing AppRestartDelay 3000
nssm set Syncthing Start SERVICE_AUTO_START
```

`AppEnvironmentExtra` is required — the service runs as `LocalSystem`, which
has no `USERPROFILE` of its own, and Syncthing needs one to resolve `~`-style
paths. `AppRestartDelay` (3000ms) avoids a crash-loop race if the port isn't
released fast enough on a quick restart.

Do NOT install `Syncthing.Syncthing` via winget — it would conflict with the
SyncTrayzor-bundled binary, since both target the same home dir
(`%LOCALAPPDATA%\Syncthing\`).

## Service management

```powershell
Get-Service Syncthing              # check status
Start-Service Syncthing            # start (requires elevation — UAC prompt)
Restart-Service Syncthing          # restart, e.g. after an ignore/config change
Stop-Service Syncthing
```

**Starting/stopping/restarting the service requires admin rights.** From an
unelevated shell (including WSL2 via `powershell.exe` interop), this fails
silently or with "Cannot open Syncthing service" — use
`Start-Process powershell.exe -Verb RunAs -Wait` to trigger a UAC prompt, or
run the command from an already-elevated PowerShell window.

**Known gotcha (hit 2026-07-31):** `StartType: Automatic` does not guarantee
the service survives every reboot/update — it was found stopped (clean
shutdown, not a crash) for over a day with no auto-restart. If a device looks
disconnected from Windows's side, check `Get-Service Syncthing` before
assuming a config/network problem.

If the service fails to start: kill any zombie `syncthing.exe` process first,
wait ~3s for the port to release, then retry.

## Configure CORTEX Vault Sync

1. Confirm the service is running (`Get-Service Syncthing`).
2. Open the Syncthing web UI at **http://127.0.0.1:8386** (not 8384 — see
   Notes). Log in with the credentials in Bitwarden item
   `Syncthing - LNV-LGN5`.
3. **Add folder** (if not already present):
   - Folder Label: `CORTEX`
   - Folder ID: `CORTEX`
   - Folder Path: `C:\Users\deanj\CORTEX`
   - Share with the WSL2, homelab, and dj15 devices
4. **Add each remote device**, using the device IDs in this directory's
   `README.md` device registry — **not** `dynamic` for the address field.
   Pin each to its Tailscale IP explicitly, e.g. for homelab:
   `tcp://<SYS_ADMIN_TAILSCALE_IP_HOMELAB>:22000`. A `dynamic` address relies on global
   discovery/relay/NAT traversal, all of which are deliberately disabled
   across this mesh (Tailscale-only lockdown) — `dynamic` will silently
   never connect. This was the root cause of a real Windows↔homelab outage
   fixed 2026-07-31.
5. For the iOS device (currently SyncTrain, `dj15`): on the phone, SyncTrain
   → Settings → Device ID (copy it); in the Windows Syncthing web UI, Add
   Remote Device → paste it, name `dj15`, share the `CORTEX` and `CONTEXT`
   folders. Accept the pairing/folder offer on the phone.

## Tailscale-only enforcement (required)

Syncthing must be locked to Tailscale to prevent CORTEX from being exposed on
untrusted WiFi networks. In the web UI: **Actions (top right) → Settings →
Connections**:

| Setting | Value |
|---|---|
| Sync Protocol Listen Addresses | `tcp://<SYS_ADMIN_TAILSCALE_IP_LAPTOP>:22000, quic://<SYS_ADMIN_TAILSCALE_IP_LAPTOP>:22000` |
| Enable Local Discovery | ❌ unchecked |
| Enable Relaying | ❌ unchecked |
| Global Discovery | ❌ unchecked — matches the rest of the mesh (see `README.md` Tailscale-only table); do not leave this enabled "for address exchange", every device address should be pinned explicitly instead |

Also verify every remote device's address is pinned to its Tailscale IP (no
`dynamic`) — see step 4 above.

Click **Save**, then `Restart-Service Syncthing` (elevated) for listen
address changes to take effect.

## GUI access without a tray icon

There's no tray icon anymore (that was SyncTrayzor). Two ways to reach the
web UI:

- Directly: http://127.0.0.1:8386
- Via the Brave PWA shortcut `Syncthing GUI.lnk` in the Windows Startup
  folder (`%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\`),
  which opens the same URL as an app window. Similar shortcuts exist for
  the WSL2 and homelab GUIs — see `README.md` for the full list.

## Config locations

| File | Contents |
|---|---|
| `%LOCALAPPDATA%\Syncthing\config.xml` | Syncthing's actual device/folder config, GUI credentials, API key |
| `%LOCALAPPDATA%\Syncthing\syncthing.log` | Runtime log |
| `%LOCALAPPDATA%\Syncthing\syncthing-service*.log` | Service wrapper logs (NSSM) |

Not committed to this repo — contains API keys and device credentials.
Device IDs live in `README.md`'s device registry instead; GUI credentials
and API key live in Bitwarden item `Syncthing - LNV-LGN5`.

**If you rotate the API key** (e.g. after it's been accidentally exposed):
edit the `<apikey>` value in `config.xml` directly, `Restart-Service
Syncthing` (elevated) to pick it up, then update the `api-key` custom field
on the Bitwarden item — nothing does this automatically.

## Conflict File Cleanup

Syncthing creates `*.sync-conflict-<timestamp>-<deviceid>` files on
simultaneous edits. To clean from the CORTEX vault (from WSL2):

```bash
cd ~/CORTEX

# Remove tracked conflict files
git rm -f $(git ls-files | grep sync-conflict) 2>/dev/null || true

# Remove untracked ones
find . -name "*sync-conflict*" -type f -delete

git commit -m "chore: remove sync conflict files"

# Verify
find . -name "*sync-conflict*" -type f
```

## Tailscale Access to WSL2 Syncthing

The WSL2 Syncthing GUI is accessible from Windows at:

```
https://<SYS_ADMIN_TAILSCALE_HOST_WSL>:8384
```

The Tailscale serve rule on WSL2 is set up by `setup-wsl2.sh`.

## Known Device IDs

See `README.md` for the full device registry.
To view the Windows device ID: open the web UI (http://127.0.0.1:8386) →
Actions (top right) → Show ID.

## Notes

- Windows Syncthing GUI is on **port 8386, not 8384** — WSL2's `tailscaled`
  holds port 8384 across all Windows interfaces via mirrored networking, and
  Windows-side tools (`netstat`, `Get-NetTCPConnection`) can't see
  WSL2-owned ports across that namespace boundary, so binding 8384 on
  Windows will always fail while WSL2 is running.
