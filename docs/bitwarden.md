# Bitwarden — item inventory and WSL2 CLI notes

Moved here from argus `context/tools.md` ([argus#418](https://github.com/deanjstone/argus/issues/418)):
which vault items each project uses, and how the `bw` CLI behaves on this machine, are machine
facts, so sys-admin owns them. The item-naming convention itself (Login item, username = env var
key, password = value) stays in argus `context/tools.md`.

Bitwarden is the source of truth for every credential. For the non-interactive unlock used by
agents and scripts, see argus-config's WSL2 instructions (`bashrc.d/bitwarden.sh`,
`bitwarden-session`).

## Bitwarden items per project

Personal vault Login items relevant to Argus-ecosystem projects (excludes the much larger set of unrelated personal items in the same vault). One `bws` (Bitwarden Secrets Manager) exception is called out separately below.

| Project | Item(s) |
|---|---|
| **argus** (agent CLI, agent-engine, brrr) | `telegram-argus-ccgram-bot-token`, `telegram-argus-shared-bot-token`, `telegram-claude-tui-bot-token`, `telegram-owner-chat-id`, `telegram-allowed-user-ids`, `slack-argus-app-config-token`, `slack-argus-app-token`, `slack-argus-bot-token`, `brrr-webhook-secret`, `github-claude-mcp`, `Watchtower: usage-shim (wsl2)` |
| **memory-mcp** (`apps/memory-mcp`, claude-memory MCP; formerly argus-context / mcp-memory) | Uses **Bitwarden Secrets Manager** (`bws`), not a vault Login item — machine-scoped access token at `~/.bws_token` fetches `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` secrets. `github_pat_pkm-vault` (context/CORTEX vault sync) is a regular vault item. |
| **myargus** (web monorepo) | `myargus`, `myargus GitHub app: collector PAT`, `SupaBase: myargus (service_role)`, `CLOUDFLARE-TOKEN-DNS`, `CLOUDFLARE-TOKEN-PAGES`, `CLOUDFLARE_GLOBAL` |
| **budget** (Budget Buddy) | `budget-app-url`, `budget-cron-secret`, `budget-homelab-db-url`, `budget-supabase-anon-key`, `budget-supabase-url`, `budget-up-api-encryption-key` |
| **stockade** | `stockade-supabase-anon-key`, `stockade-supabase-url` |
| **homelab** | `homelab deploy token`, `homelab-cloudflared-tunnel-token`, `homelab-paperless-admin`, `homelab-paperless-db-password`, `homelab-paperless-secret-key`, `Syncthing - homelab`, `Syncthing: homelab (API key)` |
| **Shared / cross-project** (LLM & dev-tool API keys, not owned by one project) | `Claude (anthropic.com)`, `OpenAI`, `Gemini Projects API`, `Mistral.ai`, `HuggingFace_token_Llama-3-8B`, `huggingface.co`, `Brave Search API`, `Supabase: Management API PAT` |

Item names double as the source of truth for what's project-scoped — this table is a pointer for orientation, not a mirror; if an item's project ownership is unclear from its name (e.g. a bare `myargus`), check the consuming `deploy.sh` rather than trusting this table blindly.

Deploy script pattern for a `deploy.sh` that needs Bitwarden secrets (ccbot's `deploy.sh` was the original reference; it was deleted with the package in #407):
```bash
[[ -f "$HOME/.bw_session" ]] && source "$HOME/.bw_session"

# IMPORTANT: use --nointeraction + a targeted item get for session validation.
# - bw status always shows "locked" in WSL2 new shells (unreliable)
# - bw list items exits 0 even with an expired session (false positive)
# Both of these caused silent failures in earlier deploys.
if bw get username "known-item-name" --session "$BW_SESSION" --nointeraction &>/dev/null 2>&1; then
  echo "Session valid"
else
  echo "Run: bw-unlock  then re-run deploy.sh"; exit 1
fi

# Fetch secrets with --nointeraction so they fail cleanly instead of prompting
VALUE=$(bw get password "item-name" --session "$BW_SESSION" --nointeraction 2>/dev/null || true)
```

**WSL2 gotchas:**
- `bw status` → always `locked` in a new shell even with a valid BW_SESSION. Do not use.
- `bw list items --session KEY` → exits 0 with expired session (returns empty list). Do not use for validation.
- `bw unlock --raw` inside `$()` → stdin may not be a tty; password read silently fails. `bw-unlock` script uses `< /dev/tty` to fix this.
- Missing items are silently skipped when using `|| true` — check `secret_ok` warnings in output.

**BW CLI 2026.5.0 + WSL2 (no gnome-keyring):**
- Saved sessions (`~/.bw_session`) no longer work across processes — the new CLI uses OS keyring to persist unlock state; without it, sessions expire on process exit.
- **Read ops** (`bw get`, `bw list`) work fine with a fresh `--passwordenv` unlock each script run.
- **Write ops** (`bw create`, `bw edit`, `bw delete`) work with `--passwordenv` but require passing encoded JSON via a **temp file** — piping stdin conflicts with bw's internal password prompt handling: `bw encode > /tmp/f && bw create item --session "$S" < /tmp/f`.
- Use the `bitwarden-session` helper (in `bashrc.d/bitwarden.sh`) for non-interactive unlock in scripts, direnv and agent tool calls: `S=$(bitwarden-session)`. Agents never ask the user to unlock (argus-config CLAUDE.md, WSL2-Specific → Bitwarden).
- `bw-unlock` still works interactively but saved session is only useful in the same terminal session.

