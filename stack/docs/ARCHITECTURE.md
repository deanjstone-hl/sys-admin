# WSL2 Service Architecture

**Stack:** Tailscale · tmux · Syncthing · SSH · Bitwarden CLI

> Vaultwarden is documented below but **not deployed** in the current stack — no pre-built binary was available for the current release and Rust is not installed. Bitwarden CLI points to the hosted bitwarden.com instead.

---

## Foundation: Enable systemd

Everything else depends on this.

```bash
systemctl --no-pager status   # check if already running
cat /etc/wsl.conf             # check existing config
```

```ini
# /etc/wsl.conf
[boot]
systemd = true
command = /usr/local/bin/wsl2-boot.sh

[network]
hostname = LNV-LGN5
generateHosts = true
generateResolvConf = true

[user]
default = deanj
```

```bash
wsl.exe --shutdown   # from Windows Terminal, then relaunch Ubuntu
systemctl --no-pager status  # should show running units
```

**Minimum WSL version:** `wsl --version` → `WSL version: 1.0.0+`. Update via `winget upgrade Microsoft.WSL` if needed.

---

## 1. Tailscale

Running inside WSL2 gives it a dedicated Tailscale IP — cleaner than port-forwarding through Windows. Two nodes appear in your Tailnet: `LNV-LGN5` (Windows) and `lnv-lgn5-wsl` (WSL2).

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up --hostname=lnv-lgn5-wsl --accept-routes
tailscale ip -4   # note this IP for SSH client config
```

---

## 2. SSH Server

```bash
sudo apt install -y openssh-server
```

```bash
# /etc/ssh/sshd_config.d/99-wsl2.conf  (drop-in, doesn't touch main config)
Port 22
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
AllowUsers deanj
X11Forwarding no
PrintMotd no
```

```bash
sudo systemctl enable --now ssh

mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... your-device-key" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

iOS/Echo SSH+Mosh client config:

```
Host wsl
  HostName <tailscale-wsl2-ip>
  User deanj
  Port 22
  IdentityFile ~/.ssh/id_ed25519
```

Prefer Mosh over SSH in Echo for roaming resilience — Echo handles the Mosh handshake automatically once the host entry is configured with Mosh enabled.

Auto-attach to tmux on SSH login — add to `~/.bashrc`:

```bash
if [[ -n "$SSH_CONNECTION" ]] && [[ -z "$TMUX" ]]; then
  tmux new-session -A -s main
fi
```

---

## 3. Mosh

Mosh keeps sessions alive across network changes and poor connectivity — preferred over raw SSH for iOS access via Echo.

```bash
sudo apt install -y mosh
sudo ufw allow 60000:61000/udp
```

Mosh uses SSH for the initial handshake (port 22), then switches to UDP 60000–61000. No separate key setup needed — reuses the same Ed25519 key as SSH.

**iOS client:** Echo (replay.software/echo) — $2.99, iOS 26+. Supports Mosh natively. Configure hosts in Echo with Mosh enabled; it manages the handshake automatically.

---

## 4. tmux

```bash
sudo apt install -y tmux
```

Boot script to pre-create the main session:

```bash
# /usr/local/bin/wsl2-boot.sh
#!/bin/bash
sleep 2  # let systemd settle
sudo -u deanj tmux new-session -d -s main 2>/dev/null || true
```

```bash
chmod +x /usr/local/bin/wsl2-boot.sh
```

> `[boot] command` and `systemd = true` coexist — the command runs as a one-shot after systemd starts.

Optional layout persistence via tmux-resurrect:

```bash
# ~/.tmux.conf
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-resurrect'
run '~/.tmux/plugins/tpm/tpm'
# Save: Prefix + Ctrl-s  |  Restore: Prefix + Ctrl-r
```

---

## 5. Syncthing

```bash
curl -fsSL https://syncthing.net/release-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] \
  https://apt.syncthing.net/ syncthing stable" \
  | sudo tee /etc/apt/sources.list.d/syncthing.list
sudo apt update && sudo apt install -y syncthing
```

Run as a user systemd service (not root):

```bash
systemctl --user enable --now syncthing
systemctl --user status syncthing
```

Admin UI at `http://localhost:8384` (accessible from Windows browser). **Set a GUI password immediately:** Actions > Settings > GUI > GUI Authentication Password.

**Key decisions:**

- Sync folders should live inside the WSL2 filesystem (`~/sync/`), not on `/mnt/c/` — NTFS performance across the 9P boundary is poor.
- To sync with Windows paths, run two paired Syncthing instances — one in WSL2, one on Windows:

```
WSL2 Syncthing          Windows Syncthing
~/sync/notes/    ←──→   C:\Users\deanj\sync\notes\
```

```bash
# Install Syncthing on Windows
winget install Syncthing.Syncthing

# In WSL2 Syncthing UI (localhost:8384):
#   Add Device → paste Windows device ID
#   Share folder with that device → path: /home/deanj/sync/

# In Windows Syncthing UI:
#   Accept folder share → set local path: C:\Users\deanj\sync\
```

Both instances bind to `:8384` in their own network namespaces — no port conflict. They sync via `127.0.0.1:22000`.

---

## 6. Vaultwarden

Install via pre-built binary from GitHub releases (no Docker, no Rust):

```bash
VW_VERSION=$(curl -s https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest \
  | grep '"tag_name"' | cut -d'"' -f4)

curl -fsSL \
  "https://github.com/dani-garcia/vaultwarden/releases/download/${VW_VERSION}/vaultwarden-${VW_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
  | sudo tar -xz -C /usr/local/bin/
sudo chmod +x /usr/local/bin/vaultwarden
```

> **Note:** Confirm the binary asset name on the [releases page](https://github.com/dani-garcia/vaultwarden/releases) — naming varies by version. If no pre-built binary exists for the current release, fallback: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh` then `cargo build --features sqlite --release`.

**Systemd service:**

```bash
sudo useradd -r -s /bin/false -d /opt/vaultwarden vaultwarden
sudo mkdir -p /opt/vaultwarden/data
sudo chown -R vaultwarden:vaultwarden /opt/vaultwarden
```

Systemd unit tracked at [`config/wsl2/systemd/vaultwarden.service`](../config/wsl2/systemd/vaultwarden.service) — installed by `install-wsl2.sh`.

```bash
sudo systemctl enable --now vaultwarden
```

Expose via Tailscale only — do not open to the internet:

```bash
tailscale serve --bg http://localhost:8080
# Available at https://lnv-lgn5-wsl.<tailnet>.ts.net with valid TLS cert
```

---

## 7. Bitwarden CLI

Download standalone binary — version-independent, no npm/Node dependency:

```bash
BW_VERSION=$(curl -s https://api.github.com/repos/bitwarden/clients/releases \
  | grep '"tag_name": "cli-v' | head -1 | cut -d'"' -f4 | sed 's/cli-v//')
curl -fsSL \
  "https://github.com/bitwarden/clients/releases/download/cli-v${BW_VERSION}/bw-linux-${BW_VERSION}.zip" \
  -o /tmp/bw.zip
unzip -o /tmp/bw.zip -d ~/.local/bin/   # canonical location, ADR-003
chmod +x ~/.local/bin/bw
rm /tmp/bw.zip

# Point to local Vaultwarden
bw config server http://localhost:8080   # or Tailscale Serve URL
bw login
export BW_SESSION="$(bw unlock --raw)"
```

Non-interactive secret retrieval for scripts and agents:

```bash
bw get password "my-api-key" --session "$BW_SESSION"
```

---

## 8. Goose

Open-source AI agent from the Agentic AI Foundation (AAIF). Runs as a CLI in WSL2 and as a native desktop GUI on Windows.

**WSL2 (CLI)**

Installed to `~/.local/bin/goose` via the installer script:

```bash
# Install / update
curl -fsSL https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh | bash
```

Goose is not configured on WSL2 and no config is tracked here. The stale copy was removed on 2026-09-30 (argus-config#338 decision 5). The only live goose config is the Windows GUI's, below.

**Windows (GUI)**

`install-windows.ps1` downloads and runs the latest installer directly from GitHub releases — no package manager involved. The installer lands at `%LOCALAPPDATA%\Programs\Goose\Goose.exe`.

To install manually: download from the [GitHub releases page](https://github.com/aaif-goose/goose/releases/latest) and run the Windows setup executable.

The Windows Goose desktop stores its own config at `%APPDATA%\goose\config.yaml` — managed independently from the WSL2 CLI config.

**Expose WSL2 Goose as an ACP server (optional)**

Goose can serve an HTTP/WebSocket ACP endpoint that editors and other tools can connect to:

```bash
goose serve   # binds to :3000 by default
```

---

## Integration Map

```
iOS (Echo — SSH+Mosh client)
  └─ Mosh → Tailscale → WSL2 UDP :60000-61000
      └─ (SSH handshake on :22)
              └─ tmux attach -t main
                  ├─ Claude Code agents
                  └─ bw CLI (secrets)

WSL2 services (systemd)
  ├─ tailscaled     → TS IP for direct access
  ├─ sshd           → :22, key-only, Tailscale-reachable
  ├─ mosh-server    → UDP :60000-61000 (on-demand, spawned by mosh)
  └─ syncthing      → :8384 (localhost), user service
```

---

## Health Check Alias

```bash
# Add to ~/.bashrc
alias svc='systemctl --no-pager status tailscaled ssh && systemctl --user --no-pager status syncthing'
```

---

## First-Time Setup Order

1. `wsl --version` → update if needed
2. Enable systemd in `/etc/wsl.conf` → `wsl --shutdown`
3. Install Tailscale → `tailscale up`
4. Install + configure `sshd` → test SSH from Echo
5. Install Mosh → open UDP 60000-61000 in Windows Firewall → test Mosh from Echo
6. Install tmux → apply config → verify session persists
7. Install Syncthing → configure folders → set GUI password
8. Install Vaultwarden binary → `bw config server` → `bw login`
9. Confirm `svc` alias shows all green
