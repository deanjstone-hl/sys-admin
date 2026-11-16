# Decisions

## ADR Index

Formal ADRs with full context live in `decisions/`:

| # | Title | Status | Date |
|---|---|---|---|
| [001](decisions/adr-001-replace-windows-terminal-with-wezterm.md) | Replace Windows Terminal with WezTerm | superseded by argus ADR-006 | 2026-06-21 |
| [002](decisions/adr-002-replace-tmux-with-zellij.md) | Replace tmux with Zellij | superseded by argus ADR-006 | 2026-06-21 |
| [003](decisions/adr-003-canonical-user-bin-location.md) | Canonical location for user-installed CLI tools | accepted | 2026-07-09 |
| [004](decisions/adr-004-minis-is-a-non-managed-environment.md) | Minis (iSH Alpine on iOS) is a deliberate non-managed environment | accepted | 2026-09-06 |

---

## Legacy decision log

Decisions recorded before the ADR format was adopted. Most recent first.

The three **Dashboard** entries and the sudoers drop-in below are historical: the WSL2
dashboard was deleted on 2026-09-29 ([#121](https://github.com/deanjstone/sys-admin/issues/121)),
superseded by Watchtower.

---

## Windows lid-close power actions: Do nothing (AC) / Hibernate (DC)

**Decision:** On LNV-LGN5's Windows side, lid-close action is set to **Do nothing** while plugged in (AC) and **Hibernate** on battery (DC), in the active (Balanced) power scheme.

**Why:** Default was Sleep on both. Sleep on battery still draws power and generates heat (RAM stays refreshed); Hibernate writes RAM to disk and cuts power entirely, which matters since the lid is closed with no visual indication of thermal state. AC left as "Do nothing" so the machine keeps serving as a headless/docked box when the lid is shut and plugged in.

**Risk accepted:** Running lid-closed on AC means no visible thermal warning if airflow is restricted. Mitigation: physical (stand/riser keeping vents clear) plus Lenovo Vantage's Intelligent Cooling set to **Performance** (favors fan ramp over silent throttling) — see next entry.

**How set:** `powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0` and `powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 2`, then `powercfg /setactive SCHEME_CURRENT`. Both AC and DC lid settings are flagged `Attributes=1` (hidden) in the registry, so they don't show in a plain `powercfg /q` — this is normal, not a sign the setting isn't live. Verify at `HKLM\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\<active-scheme-guid>\4f971e89-eebd-4455-a8de-9e59040e7347\5ca83367-6e45-459f-a27b-476b1d01c936` (`ACSettingIndex` / `DCSettingIndex`).

**Date:** 2026-07-11

---

## Lenovo Vantage: installed via winget/Microsoft Store (exception to no-winget rule)

**Decision:** Installed Lenovo Vantage (`9WZDNCRFJ4MV`) via `winget install --id 9WZDNCRFJ4MV --source msstore`.

**Why:** Vantage is a Store-only UWP app — no GitHub release, no standalone vendor `.exe` exists for it. Checked both before falling back to winget, per the repo's general no-winget preference; this is the documented exception case where no other install path exists.

**Purpose:** Needed for Intelligent Cooling / thermal-mode control, since Windows' own `SYSCOOLPOLICY` (system cooling policy) setting isn't exposed in the registry on this model — Lenovo hands fan/thermal control to Vantage instead of the generic Windows power setting.

**Follow-up (not yet done in this session):** Set Vantage's Intelligent Cooling / thermal mode to **Performance** (Device tab → Smart Settings) to bias toward fan ramp-up over CPU throttling during lid-closed-on-AC operation. Also check for a Vantage battery/auto-switch setting that could silently override this on unplug.

**Date:** 2026-07-11

---

## AI terminals: Aider (WSL2) + Wave Terminal (Windows)

**Decision:** Aider for in-terminal AI coding assistance in WSL2; Wave Terminal as the Windows terminal with built-in AI sidebar.

**Why:** Aider is pure TUI, runs anywhere, has first-class Claude + Ollama support, and auto-commits accepted changes into git. Wave Terminal replaces Windows Terminal as the daily driver with native Ollama integration and a block-based UI — no separate app needed for quick AI queries.

**OpenCode** noted as a watch candidate (Go TUI, 75+ providers) — not installed yet.

**Details:** the session log moved to `~/CONTEXT/03.SESSIONS/Session - AI Terminals Setup - 2026-06-04.md` ([#152](https://github.com/deanjstone/sys-admin/issues/152)).

---

## Aider: default model is Ollama (local, no API key)

**Decision:** Aider defaults to `ollama/qwen2.5:3b`. No cloud API key is used or required.

**Why:** Ollama is already running locally with qwen2.5:3b and gemma3:4b. Local-first keeps all code off external services. Switch with `aider --model ollama/gemma3:4b` for heavier tasks.

---

## direnv: standalone binary in `~/bin/`, not apt

> **Superseded 2026-07-09 (ADR-003):** direnv was moved from `~/bin/` to `~/.local/bin/direnv`.
> `~/bin` is now Windows-interop shims only; `~/.local/bin` is the canonical location for
> direct-source binaries. The "not apt" rationale below still holds unchanged — only the
> directory changed. Do not reintroduce a `~/bin/direnv` binary. See
> [ADR-003](decisions/adr-003-canonical-user-bin-location.md).

**Decision:** Install direnv as a standalone binary downloaded from GitHub releases to `~/bin/direnv`, not via `sudo apt install direnv`.

**Why:** No sudo access available in this shell context. Consistent with the Bitwarden CLI standalone binary pattern. Shell hook added to `~/.bashrc` via `eval "$(direnv hook bash)"`. Per-project `.envrc` files call the existing `bw get` pattern — no secrets are stored on disk.

---

## Dashboard: `pgrep` for Syncthing health check

**Decision:** Use `pgrep -x syncthing` instead of `systemctl --user is-active syncthing` or an HTTP ping to check Syncthing status in the dashboard.

**Why:** The dashboard runs as a systemd system service (`wsl2-dashboard.service`). `systemctl --user` from a system service context has no access to the user's D-Bus session, so it always returns inactive. The HTTP ping (`/rest/system/ping`) returns 401 once a GUI password is set. `pgrep` is process-level and works regardless of context.

---

## Dashboard: separate `index.html` instead of inline HTML

**Decision:** Dashboard frontend lives in `dashboard/index.html`, read from disk at startup. Not embedded as a template string in `server.mjs`.

**Why:** Easier to edit and diff. Keeps server logic and UI concerns separate. Allows the file to be opened and previewed directly.

---

## Syncthing: dedicated HTTPS port via Tailscale Serve, not sub-path

**Decision:** Syncthing is exposed at `https://<SYS_ADMIN_TAILSCALE_HOST_WSL>:8384` (port-based), not at a sub-path like `/syncthing`.

**Why:** Syncthing's frontend uses root-relative asset paths (`/syncthing.js`, etc.). Serving behind a sub-path prefix breaks all asset loading, resulting in an unstyled page with unrendered templates. A dedicated port sidesteps this entirely.

---

## Syncthing: `insecureSkipHostcheck` in config

**Decision:** Set `<insecureSkipHostcheck>true</insecureSkipHostcheck>` in `~/.local/state/syncthing/config.xml`.

**Why:** Syncthing rejects requests whose `Host` header doesn't match `localhost`. When accessed via the Tailscale `.ts.net` hostname, the host check blocks the request. Tailscale Serve already enforces tailnet-only access, so the host check provides no additional security benefit here.

---

## Syncthing: no TLS in Syncthing GUI

**Decision:** Left `Use HTTPS for GUI` disabled in Syncthing settings.

**Why:** Tailscale Serve provides TLS termination end-to-end. Enabling Syncthing's own TLS would create a double-TLS stack and conflict with the serve proxy.

---

## Tailscale Serve: `tailscale set --operator=$USER`

**Decision:** Run `sudo tailscale set --operator=$USER` once to allow unprivileged `tailscale serve` commands.

**Why:** Without this, `tailscale serve` requires sudo. Setting the operator means the current user can manage serve config without root, which is needed for `deploy.sh` to work without elevated permissions.

---

## Deploy: NOPASSWD sudoers drop-in for service restart

**Decision:** `/etc/sudoers.d/wsl2-dashboard` grants `deanj` passwordless `sudo systemctl restart wsl2-dashboard`.

**Why:** The deploy script needs to restart the systemd service after copying files. Scoped to a single command — does not grant broad sudo access.

---

## Bitwarden CLI: standalone binary in `~/bin/`

> **Superseded 2026-07-09 (ADR-003):** `bw` was moved from `~/bin/` to `~/.local/bin/bw`.
> `~/bin` is now Windows-interop shims only. The "not npm" rationale below still holds unchanged
> — only the directory changed. Do not reintroduce a `~/bin/bw` binary. See
> [ADR-003](decisions/adr-003-canonical-user-bin-location.md).

**Decision:** Download standalone `bw` binary from GitHub releases to `~/bin/bw` rather than using `npm install -g`.

**Why:** The npm-installed version is tied to whatever Node version fnm has active at install time. Switching Node versions breaks it silently. The standalone binary has no runtime dependency.

---

## Vaultwarden: skipped

**Decision:** Vaultwarden not installed.

**Why:** No pre-built binary is published for the current release. Building from source requires Rust, which is not installed and adds significant setup overhead. Revisit when a pre-built binary is available or if Rust is added to the stack.

---

## Dashboard: bind to `127.0.0.1` only

**Decision:** Dashboard server binds to `127.0.0.1:4000`, not `0.0.0.0`.

**Why:** Prevents the dashboard from being reachable on the WSL2 network interface directly. All external access goes through Tailscale Serve, which enforces tailnet-only access and provides a valid TLS cert.

---

## SSH: drop-in config in `sshd_config.d/`

**Decision:** SSH hardening applied via `/etc/ssh/sshd_config.d/99-wsl2.conf` rather than editing `/etc/ssh/sshd_config` directly.

**Why:** Drop-ins survive package upgrades cleanly. The main config file remains at its distro defaults, making future diffs easier.

---

## Tailscale: WSL2 node renamed to `lnv-lgn5-wsl`

**Decision:** WSL2 Tailscale node hostname set to `lnv-lgn5-wsl` (not `lnv-lgn5`).

**Why:** Both Windows and WSL2 are on the same Tailnet. Distinguishing the hostname makes it clear which node is which in the Tailscale admin console, peer lists, and Tailscale Serve URLs.
