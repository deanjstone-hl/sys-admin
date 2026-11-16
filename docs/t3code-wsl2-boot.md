# T3 Code — WSL2 Server at Windows Boot

Runs the T3 Code server inside WSL2 (LGN5, distro `Ubuntu`) from Windows startup, before any
user logs in. The homelab equivalent is [homelab/docs/t3code.md](https://github.com/deanjstone/homelab/blob/main/docs/t3code.md).

## Why it needs three pieces

Before this, the desktop app ran in `wslOnly` mode and spawned the WSL server itself over
`wsl.exe` (`~/.t3/wsl-runtime/<hash>/t3 --bootstrap-fd 0`). Nothing ran until someone logged
in and opened the app.

1. **`t3code.service`** — `systemctl --user` unit from `t3 service install`. Linger is already
   on (`loginctl show-user deanj -p Linger` → `yes`), so it starts with the distro, not with a
   login.
2. **Scheduled Task `WSL Ubuntu keep-alive (T3 Code)`** — `stack/install-t3-boot-task.ps1`.
   Boots the distro at startup and keeps it running. WSL stops a distro that has no attached
   client, even while systemd services are running inside it, so the task runs
   `wsl.exe -d Ubuntu --exec /bin/sleep infinity`. `.wslconfig`'s `vmIdleTimeout=-1` only
   keeps the VM up, not the distro.
   - `S4U` logon: runs whether or not the user is logged on, with no stored password.
   - `ExecutionTimeLimit` is `0` (the default 72h would kill the keep-alive). It may start on
     battery and keeps running on battery, because LGN5 is a laptop.
3. **The desktop app's own WSL backend is turned off** (`wslBackendEnabled: false`,
   `wslOnly: false` in `C:\Users\deanj\.t3\userdata\desktop-settings.json`). If left on, it
   would start a second Linux server against the same `~/.t3` SQLite file. The desktop app
   scans for a free port starting at 3773, so its Windows backend moves to 3774 on its own. The
   WSL service is added as a saved environment instead.

The service uses `T3CODE_HOME=~/.t3`, the same data directory the desktop-managed backend
used, so existing threads and projects carry over.

## Install

1. Register the boot task (elevated pwsh, one UAC prompt):
   ```powershell
   pwsh -ExecutionPolicy Bypass -File \\wsl.localhost\Ubuntu\home\deanj\repos\sys-admin\stack\install-t3-boot-task.ps1
   ```
2. Quit the T3 Code desktop app completely, including the tray icon. This stops every T3
   session.
3. From a plain terminal (Windows Terminal → Ubuntu, not a T3 session):
   ```bash
   ~/repos/sys-admin/stack/t3-boot-cutover.sh
   ```
   It refuses to run while port 3773 is busy, backs up and edits `desktop-settings.json`,
   runs `t3 service install`, waits for HTTP 200, then prints a pairing URL (valid 30 min).
   `T3_VERSION=<version>` pins the service to a specific t3 release (default `latest`). Use it
   to match the desktop app's runtime if `latest` is older, so an older server never opens a
   database a newer one has already migrated. `PAIR_TTL=12h` makes the pairing URL last longer.
4. Open the desktop app → add an environment → paste the `/pair#token=...` URL.

## Remote access

The service binds `127.0.0.1:3773`, which is what the desktop app on this PC pairs to. Other
tailnet devices reach it through Tailscale Serve at `https://<SYS_ADMIN_TAILSCALE_HOST_WSL>/`.
That's WSL's own tailnet node: `tailscaled` runs inside the distro with `operator=deanj`. The
server sets up the Serve mapping itself because of
`stack/config/wsl2/systemd-user/t3code.service.d/override.conf`. Install it with:

```bash
mkdir -p ~/.config/systemd/user/t3code.service.d
cp ~/repos/sys-admin/stack/config/wsl2/systemd-user/t3code.service.d/override.conf \
  ~/.config/systemd/user/t3code.service.d/
systemctl --user daemon-reload && systemctl --user restart t3code
```

Don't set `T3CODE_HOST` to the WSL node's tailnet IP (`<SYS_ADMIN_TAILSCALE_IP_WSL>`). That was tried on
2026-10-02, and the desktop app on this PC then timed out: under mirrored networking, Windows
sends traffic for that IP out through its own Tailscale adapter, and it never reaches WSL. It
also makes the bind depend on `tailscaled` being up at boot, and a user unit can't order itself
after a system unit. `0.0.0.0` would work too, but mirrored networking would also put the
server on the Wi-Fi LAN. HTTPS through Serve also works from the hosted `app.t3.codes`, which
blocks plain-HTTP backends as mixed content.

If Serve setup fails at startup, the server logs it and keeps serving loopback, so the local
desktop app is unaffected. The mapping is stored by `tailscaled` and survives reboots.

## T3 Connect

T3 Connect makes this server reachable from the iPhone and from other desktops without Tailscale,
and it is the only path that delivers iOS push notifications and Live Activities. Link it once
from a WSL terminal (not a T3 session), approving the printed code in any browser:

```bash
t3 connect link --headless
t3 connect publish          # enables push notifications; `link` alone does not
systemctl --user restart t3code
t3 connect status           # exposure enabled, stored credential, publish enabled
```

The managed tunnel runs `cloudflared` as a child of the server, so the service must be able to
find it. A systemd user service does not have `~/.local/bin` on its PATH, so the drop-in sets
`PATH` explicitly. Without it the log shows `Failed to start the confirmed T3 Connect tunnel ...
The relay client is not installed.` while `t3 connect status` in your shell still reports the
relay client as available (it uses your shell's PATH, not the service's).

Check the live tunnel in the service log, not in `t3 connect status`, which only reports saved
setup:

```bash
grep -a "Relay client tunnel connection registered" ~/.t3/userdata/logs/boot-service.log | tail -3
```

While the laptop sleeps the tunnel is released and push notifications stop until it wakes.
LGN5's power plan is set never to sleep on AC (`standby-timeout-ac 0`, `hibernate-timeout-ac
0`, lid action on AC `0`) so the tunnel stays up while plugged in.

### Tunnel up but the phone gets `endpoint_request_failed`

A registered tunnel can still forward to the wrong origin. The managed tunnel's origin is
reconciled from whichever server last started with this `~/.t3/userdata`. On 2026-10-05 the
desktop app's WSL backend briefly started (port `3774`, same data directory) and re-pointed the
WSL2 environment's tunnel at `127.0.0.1:3774`. With `networkingMode=mirrored`, that loopback port
is the Windows desktop app's own server, which rejects the WSL2 environment's credential, so
every relay request got `401` and the phone showed `endpoint_request_failed`. Diagnose from
`cloudflared`'s metrics, not the log:

```bash
curl -s http://127.0.0.1:20241/metrics | grep -E '^cloudflared_tunnel_response_by_code'
grep -a -o 'originService=[^ ]*' ~/.t3/userdata/logs/boot-service.log | tail -3
```

Many `401`s (or `dial tcp 127.0.0.1:3774` errors) mean the origin is wrong. Fix it with
`systemctl --user restart t3code`, which reconciles the origin back to `3773`, and confirm
`wslBackendEnabled` is still `false`.

## Verify

The service binds `127.0.0.1`, so it can't be reached from another device before login. To
prove it started before login, reboot, leave the machine at the lock screen for ~2 minutes,
log in, then compare the service start time against the login time:

```bash
systemctl --user show t3code -p ActiveEnterTimestamp -p NRestarts
```

```powershell
(Get-CimInstance Win32_OperatingSystem).LastBootUpTime                        # Windows boot
(Get-Process explorer | Sort-Object StartTime | Select-Object -First 1).StartTime  # login
```

`ActiveEnterTimestamp` must fall between the two. First verified 2026-10-02: boot 10:31:48,
task ran 10:32:36, `t3code` active 10:32:40, login 10:34:06.

```bash
systemctl --user status t3code --no-pager
curl -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3773/   # expect 200
```

```powershell
Get-ScheduledTaskInfo -TaskName "WSL Ubuntu keep-alive (T3 Code)"   # LastTaskResult 267009 = running
```

## Updates

The service keeps itself at the desktop app's version, so there's nothing to do by hand. When
the desktop app updates, it tells the server to update too. The server downloads the new
runtime into `~/.t3/runtime/versions/<version>/`, logs `Server update prepared; handing off
to the service launcher` in `~/.t3/userdata/logs/boot-service.log`, and the launcher switches to
it. `~/.t3/runtime/service-state.json` records the active version and the update status. Seen
on 2026-10-02: the service went `0.0.44` → `0.0.45-nightly.20261001.2552` →
`…20261002.2561` the same day, while following the nightly desktop app.

`ExecStart` in the unit still points at the version that was installed first (here
`versions/0.0.44/t3 __service-launcher`). That's only the launcher. Check the version
actually running with:

```bash
jq -r .activeVersion ~/.t3/runtime/service-state.json
curl -s http://127.0.0.1:3773/.well-known/t3/environment | jq -r .serverVersion
```

Old runtimes pile up in `~/.t3/runtime/versions/` at about 220 MB each. When pruning, keep the
`ExecStart` launcher version and `activeVersion`. `~/.t3/wsl-runtime/` belonged to the desktop
app's own WSL server, and nothing uses it after the cutover.

## Rollback

```bash
npx t3@latest service uninstall
```

```powershell
Unregister-ScheduledTask -TaskName "WSL Ubuntu keep-alive (T3 Code)" -Confirm:$false
```

Then set `wslBackendEnabled` and `wslOnly` back to `true` in `desktop-settings.json`. The
cutover script left a `.bak-<timestamp>` copy beside it.
