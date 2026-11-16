---
name: ssh-perms-check
description: >
  Check SSH key and config file permissions against expected values. Use for "check SSH
  permissions", "/ssh-perms-check", or as a sub-step of health-check or config-audit.
  Read-only.
---

# SSH Permissions Check

Read-only check. Nothing is modified.

```bash
stat -c "%a %n" ~/.ssh/id_* ~/.ssh/authorized_keys ~/.ssh/config 2>/dev/null
stat -c "%a %n" ~/.ssh/ 2>/dev/null
```

Expected:
- `~/.ssh/` → `700`
- Private keys (`id_ed25519`, `id_rsa`, etc.) → `600`
- `authorized_keys` → `600`
- `config` → `600`
- Public keys (`*.pub`) → `644`

Flag anything that deviates. SSH agent connections and remote logins fail silently with
wrong perms — this is a common, easy-to-miss cause of "SSH suddenly stopped working."

## Output

Return one line per file: `✓ <path> (<perm>)` or `✗ <path> (<perm>, expected <expected>)`.

If called as a sub-step of another skill, return just that list — let the calling skill
fold it into its own report format.
