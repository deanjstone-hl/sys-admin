# Backup Coverage — LNV-LGN5

Canonical record of what's backed up, where, and by what mechanism, for both the WSL2 and
Windows sides of LNV-LGN5. sys-admin owns this doc per its mandate as system administrator
of record for all projects/vaults/apps on the machine — a backup mechanism existing
somewhere (Duplicati config, a plan file, memory) doesn't count unless it's tracked here.

> ⚠️ **This mechanism is being retired.** [#82](https://github.com/deanjstone/sys-admin/issues/82)
> decided all four Duplicati jobs retire in favour of Borg + borgmatic on Kubuntu, with the
> existing 271 GiB archive deleted once a Borg restore has been demonstrated. That cutover
> sits behind [#74](https://github.com/deanjstone/sys-admin/issues/74)/[#81](https://github.com/deanjstone/sys-admin/issues/81),
> so these jobs remain live for the foreseeable interval.
>
> **Restore status, corrected 2026-09-12.** [#78](https://github.com/deanjstone/sys-admin/issues/78)
> closed with "No job can currently restore". That is no longer true across the board:
> `WSL2 (Ubuntu)` was rebuilt on 2026-09-12 and **has a verified restore** (SHA-256 compared
> against originals — see its scope section). The other three remain unproven, and
> `User > DeanJ` has not completed a backup since 2026-08-11.

**Status:** a restic-based scheme once lived at `stack/docs/BACKUP.md`, with `stack/backup.sh`,
`init-backup.sh`, `setup-backup-server.sh` and a `backup.timer` alongside it. It was designed but
**never deployed** — no systemd timer installed, no local restic config, no repo on homelab
(verified 2026-07-09; re-verified 2026-09-28, when `restic` was still absent from PATH and
`backup.timer` still reported `not-found`). All of it was deleted rather than carried as dead
code; this doc is the sole record of backup coverage for LNV-LGN5.

## Live mechanism: Duplicati → homelab (SFTP, chrooted)

**Tool:** [Duplicati](https://duplicati.com/) 2.3.0.1, tray-icon install on Windows (no
Windows Service registered)
**Destination:** `dupbackup@homelab:duplicati/<job>` via SFTP (Tailscale), chrooted to
`/mnt/backups` on a dedicated 700GB ext4 LV (`ubuntu-vg/backups-lv`)
**Auth:** dedicated ed25519 keypair (no passphrase — the account can't get a shell, can't
port-forward, and is chrooted; see Security below), key at
`C:\Users\deanj\.duplicati-keys\duplicati_dupbackup`
**Retention:** `1W:1D,4W:1W,12M:1M` on `Obsidian Vaults`, `Projects` and `WSL2 (Ubuntu)`.
**`User > DeanJ` has no retention policy configured at all** — verified against
`Duplicati-server.sqlite`, whose complete option set for that job is `--dblock-size`,
`--exclude-files-attributes`, `compression-module`, `encryption-module`, `passphrase`.
Duplicati therefore keeps every version indefinitely, which is why that job alone holds
12 versions and 271 GiB

Prior state (before 2026-07-09): all 4 jobs targeted `D:\Duplicati\<job>\` — `D:` was a 2GB
removable IPXE stick, not a real drive. 220 consecutive failures, zero successes, since at
least 2026-06-09. Root cause: local-only destination on a drive letter that depended on
removable media being present.

### Jobs

| Job | Source | Destination path | Notes |
|---|---|---|---|
| Obsidian Vaults | `%HOME%\Obsidian\` | `duplicati/obsidian-vaults` | |
| Projects | `%HOME%\Projects\` | `duplicati/projects` | Windows-side Projects dir |
| User > DeanJ | `C:\Users\deanj\` | `duplicati/user-deanj` | Whole profile, with excludes below |
| WSL2 (Ubuntu) | `\\wsl.localhost\Ubuntu\home\deanj\{.ssh,CONTEXT,repos}\` | `duplicati/wsl2` | Rebuilt 2026-09-12 — **first proven restore**; see the scope section below |
| ~~Windows (LNV-LGN5)~~ | ~~`C:\Windows\`~~ | — | Dropped 2026-07-09 — low value, reproducible via reinstall |

### User > DeanJ excludes

`.cache/`, `.nuget/`, `.vscode/`, `vscode-remote-wsl/`, `node_modules/`, `Tools/`,
`Downloads/`, `NTUSER.DAT*`, `IntelGraphicsProfiles/`, `lid-policy/`, `iCloudDrive/`
(Cloud Files placeholder — see below).

Included as-is: `iCloudPhotos` — **but not as described here previously.** `…\iCloudPhotos\Photos`
*is* a reparse point (`0x431`), and **9,189 of its 17,079 files (53.8%) are dehydrated
placeholders**: 57.64 GiB logical against ~27.36 GiB actually on disk, with
`FILE_ATTRIBUTE_PINNED` set nowhere. So this job never protected more than half the photo
library. [#80](https://github.com/deanjstone/sys-admin/issues/80) uninstalls iCloud for
Windows entirely, removing the folder from scope. Also included: `OneDrive`
(KFM-redirected Documents/Desktop/Pictures), `AppData` (whole tree — covers Zed, Goose,
Obsidian, SyncTrayzor, Telegram, Windows Terminal, PowerToys, PowerShell config; this
supersedes the curated per-app list in the old restic doc), dotfiles, `.ssh`, `Obsidian`,
`CORTEX`, `CONTEXT`, `pkm-vault`, `argus`, `Projects`.

### WSL2 job scope

**Rebuilt 2026-09-12** ([#109](https://github.com/deanjstone/sys-admin/issues/109)). Before
that date this job had **never completed a single backup** — `LastBackupFinished` was null,
every run since 2026-08-17 failed fatally, and a restore attempt on 2026-08-16 logged
`NoFilesRestored`. It is the job #78 was describing when it closed with "No job can
currently restore".

**Current sources**

```
\\wsl.localhost\Ubuntu\home\deanj\{.ssh,CONTEXT,repos}\
```

`~/projects` and `~/agent-cli` were dropped — they no longer exist. `~/repos` was added;
it holds 19 git repos and is where the work actually lives.

**Exclude filters** (10)

```
node_modules  .git  dist  build  .next  .turbo  .venv  target  .cache  scriptable-private
```

**Required options.** These are not tuning — the job fails without them.

| Option | Why |
|---|---|
| `--skip-metadata=true` | Duplicati cannot read Unix metadata across `wsl.localhost` and logs a warning **per file**. Each warning is spooled to a `FileBackedList` temp file; at `~/repos` scale that exhausts Windows resources and kills the run with `Insufficient system resources exist to complete the requested service`. |
| `--dblock-size=10MB`, `--concurrency-compressors=1`, `--concurrency-block-hashers=1`, `--zip-compression-level=1` | At the 50MB default the run dies with `The underlying compression routine could not reserve sufficient memory` when another job is running. The machine has 15.9 GB total and sits near 85% commit with WSL2 holding ~5.8 GB. |

**`.git` is excluded, deliberately.** Restores return working-tree files, including
uncommitted and untracked work, which is the gap this job exists to close. History comes
back from GitHub by re-cloning. This also means a restored directory is *not* a working
git repo until re-cloned.

**Metadata is not stored at all.** Timestamps and permissions do not survive a restore.
**`~/.ssh` keys will come back world-readable and must be `chmod 600` by hand before `ssh`
will accept them.**

**First successful backup — 2026-09-12**

| | |
|---|---|
| Files | 56,959 |
| Remote size | 1.547 GiB across 133 volumes |
| Duration | 5m 12s |

**Restore proven, not assumed.** Two files restored to a scratch directory and compared by
SHA-256 against the originals:

```
CONTEXT/MEMORY.md          f57d6a6a65db39fe = f57d6a6a65db39fe
repos/sys-admin/CLAUDE.md  24d7f71230ed0850 = 24d7f71230ed0850
```

**Known gap — `~/repos/scriptable-private/scripts` cannot be backed up by this job.** It is
a 9p mount of `C:\Users\deanj\iCloudDrive\iCloud~dk~simonbs~Scriptable`, so reaching it
from Duplicati on Windows via `\\wsl.localhost\` is a Windows → WSL2 → Windows round trip
that the bridge denies outright (`UnauthorizedAccessException`, and even `Test-Path` fails).
It is also the one directory under `~/repos` that is **not** a git repo, so the
"everything is on GitHub" mitigation does not cover it, and `iCloudDrive` is excluded from
the `User > DeanJ` job. Tracked separately.

Known failure mode: depends on the WSL2 distro being running at backup time (UNC path
`\\wsl.localhost\Ubuntu\...`). Acceptable given daily use.

### iCloudDrive exclusion rationale

A Cloud Files placeholder (`ReparsePoint` attribute), so excluding it is correct — but the
figures here were wrong. It does not occupy ~849GB: that was a reparse-point artefact of `du`
following placeholders. **Real on-disk cost is 0.05 GiB**, measured in
[#75](https://github.com/deanjstone/sys-admin/issues/75). The stale "C: has 176GB free" was
also wrong — free space was **47.29 GiB** when re-measured on 2026-08-16.

## Homelab-side infrastructure

- New dedicated LV: `/dev/ubuntu-vg/backups-lv`, 700GB, ext4, mounted at `/mnt/backups`
  (fstab, UUID-pinned) — separate from the OS root LV (isolates backup storage; homelab's
  physical disk had 828GB unallocated in the VG before this)
- Dedicated low-privilege user `dupbackup` (`/usr/sbin/nologin`, home `/mnt/backups/duplicati`
  — chosen over `/home/dupbackup` so `authorized_keys` resolves correctly against the
  pre-chroot path OpenSSH checks)
- SSH hardened for this user only (`/etc/ssh/sshd_config.d/dupbackup.conf`):
  `ForceCommand internal-sftp`, `ChrootDirectory /mnt/backups`, no password auth, no TCP
  forwarding, no X11, no tunneling — verified: SFTP session lands in the jail, `ssh` shell
  login is rejected with "This service allows sftp connections only"
- Per-job subdirs under `/mnt/backups/duplicati/`: `obsidian-vaults/`, `projects/`,
  `user-deanj/`, `wsl2/`

## Verification checklist (run after any Duplicati job change)

1. "Test connection" in Duplicati UI before saving a destination change
2. "Run now" rather than waiting for schedule
3. `Duplicati-server.sqlite` → `Log` table should get `Result` rows (not just `ErrorLog`)
   per `BackupID` — the concrete signal a run actually completed
4. Homelab: `ls -la /mnt/backups/duplicati/*/` shows `*.dblock.zip.aes` files appearing
5. Homelab: `df -h /mnt/backups` usage grows as expected
6. Homelab: `/var/log/auth.log` during a test SFTP connection confirms chroot (no shell,
   confined path)

## Full history

Diagnosis and setup done 2026-07-09 in a Claude Code session — the original plan (root
cause, options considered, Windows profile scan, WSL2 scan) is preserved at
`/home/deanj/.claude/plans/polished-fluttering-sun.md` for context, but this doc is the
one to keep current going forward.
