# LNV-LGN5 `C:` size audit — 2026-08-16

Resolves [sys-admin#75](https://github.com/deanjstone/sys-admin/issues/75), a ticket on
[Map: Windows 11 + WSL2 → Kubuntu (#74)](https://github.com/deanjstone/sys-admin/issues/74).

**Read-only.** Nothing was deleted, moved, or reconfigured. This produces numbers, not free space.

## Method

Full recursive sweep of `C:\` from a non-elevated PowerShell process (977,222 files / 269,908
directories). Sizes are **on-disk allocated bytes** via `GetCompressedFileSizeW`, not logical
length, for anything sparse, compressed, offline, or `.vhdx`. Directory reparse points were
**not** followed during the main sweep, then measured separately in a second pass — this is what
keeps the `iCloudDrive` placeholder problem from poisoning the totals.

Only 8 directories were access-denied (all system, incl. `System Volume Information`).

Units are **GiB** throughout (`1 GiB = 2^30`), which is what Explorer shows. The map body's
figures are decimal GB — hence `ext4.vhdx` is "185 GB" there and 171.96 GiB here; same file.

## Headline: the premise has moved

| | Map body (charting) | Measured now |
|---|---|---|
| `C:` free | 19.3 GB | **47.29 GiB (50.8 GB)** |
| `C:` used | ~457 GB | 428.72 GiB |

Roughly **28 GB was freed between charting and this audit** by something not recorded. Any
partition arithmetic in #81 must start from the measured number, not the map body's.

## Reconciliation — nothing is missing

| Component | GiB |
|---|---:|
| Main sweep (reparse points excluded) | 406.16 |
| `iCloudPhotos` (on-disk, placeholders excluded) | 27.36 |
| `OneDrive` (on-disk) | 2.68 |
| `iCloudDrive` (on-disk) | 0.05 |
| **Sum** | **436.25** |
| Volume reports used | 428.72 |
| Delta | +7.53 (+1.8%) |

The overshoot is **NTFS hardlinks counted once per link** — `WinSxS`, `System32` and
`DriverStore` share physical extents, so `C:\Windows`'s 37.18 GiB is inflated by several GiB.
Offsetting under-counts: the 8 denied directories (shadow copies live in `System Volume
Information`) and NTFS metadata/`$MFT`. Within 1.8%, the volume is fully accounted for. **The
"270 GB unaccounted for" in the ticket does not exist** — it was the absence of a measurement,
not the absence of an explanation.

## Size-ranked breakdown

### Top level

| GiB | Path |
|---:|---|
| 311.85 | `C:\Users` |
| 37.18 | `C:\Windows` *(hardlink-inflated)* |
| 31.26 | `C:\Program Files` |
| 12.35 | `C:\Program Files (x86)` |
| 5.40 | `C:\ProgramData` |
| 6.35 | `C:\hiberfil.sys` |
| 1.45 | `C:\pagefile.sys` |

`$Recycle.Bin` is under 0.5 GiB — not a factor.

### Inside `C:\Users\deanj` (311.84 GiB)

| GiB | Path | Nature |
|---:|---|---|
| 171.96 | `AppData\Local\wsl\{9330d942-…}\ext4.vhdx` | the WSL2 distro being migrated |
| 42.93 | `AppData\Local\Temp` | **garbage** — see below |
| 27.36 | `iCloudPhotos` | local cache of a cloud library |
| 24.29 | `AppData\Roaming` | app state |
| 23.05 | `Apple\MobileSync\Backup` | 2 iOS device backups |
| 6.40 | `Downloads` | installers + a 3.21 GiB X/Twitter archive |
| 4.75 | `.cache` | 2.80 of it is `puppeteer` |
| 2.68 | `OneDrive` | mostly dehydrated (49.31 GiB logical) |
| 1.36 | `CORTEX` | vault |

### `AppData\Local\Temp` — 42.93 GiB, essentially all junk

| GiB | Item |
|---:|---|
| 22.10 | `wsl-crashes\` — WSL crash dumps. **One file is 17.36 GiB**, a second 4.71 GiB; both are `electron-11.dmp` from `argusde` |
| 19.42 | **12 orphaned `swap.vhdx`** in GUID-named dirs (1.32–2.04 GiB each) — dead WSL2 sessions' swap files, never cleaned up |
| 0.88 | `DiagOutputDir\` |
| ~0.5 | everything else |

### `AppData\Roaming` — 24.29 GiB

| GiB | Item |
|---:|---|
| 9.73 | `Claude\` — 8.79 of it `vm_bundles` (`rootfs.vhdx` 7.51 + `sessiondata.vhdx` 1.16) |
| 4.53 | `Code\` (VS Code) |
| 4.05 | `Jan\` — 2.79 is one local LLM `.gguf` |
| 2.11 | `npm\node_modules` |
| 1.33 | `orca\` |

### Cloud folders — measured, not guessed

| Path | Files | Locally present | Logical GiB | On-disk GiB |
|---|---:|---:|---:|---:|
| `iCloudPhotos` | 17,080 | 7,891 | 57.64 | **27.36** |
| `OneDrive` | 15,411 | 4,440 | 49.31 | **2.68** |
| `iCloudDrive` | 3,796 | 2,105 | 0.82 | **0.05** |

`iCloudDrive` is fully dehydrated and costs nothing — the "~849 GB via `du`" figure in
`docs/backup-coverage.md` is a reparse-point artefact and should not be trusted or repeated.
`iCloudPhotos` is the one that is genuinely on the disk.

## The two reclaim figures

### A. Reclaimable **without** touching WSL2

**Tier 1 — pure garbage, no decision required: ~65 GiB**

| GiB | Item |
|---:|---|
| 42.93 | all of `AppData\Local\Temp` (crash dumps + orphan swap files) |
| 8.79 | `Roaming\Claude\vm_bundles` (recreated on next launch) |
| 6.35 | `hiberfil.sys` (`powercfg /h off`) |
| 7.21 | regenerable dev caches: `puppeteer` 2.80, `npm-cache` 1.89, `pnpm\store` 1.85, `ms-playwright` 0.67 |
| **65.28** | |

**Tier 2 — needs a decision or a destination: ~+61 GiB**

| GiB | Item | Decision |
|---:|---|---|
| 27.36 | `iCloudPhotos` local cache | evict via "Optimise" — but per [#77](https://github.com/deanjstone/sys-admin/issues/77) this folder is a *mirror, not a backup*; evicting is safe, deleting is not |
| 23.05 | `Apple\MobileSync\Backup` (15.25 + 7.81, two devices) | relocate to the external HDD, or drop if iCloud device backup is on — feeds [#85](https://github.com/deanjstone/sys-admin/issues/85) |
| 6.40 | `Downloads` | 3.21 GiB X archive is data (see the X bookmarks pipeline work); the rest are installers |
| 4.05 | `Roaming\Jan` | local LLM models, re-downloadable |
| **60.86** | |

**Not counted, unverified:** `WinSxS` component cleanup (`DISM /Cleanup-Image
/StartComponentCleanup`) typically returns 3–6 GiB but needs elevation, and `Duplicati`'s 2.47 GiB
of local SQLite job DBs should be left alone — deleting them forces a very expensive rebuild.

> **Reclaimable without touching WSL2: ~65 GiB with no decisions, ~126 GiB with them.**
> Free space would go from 47.29 GiB to ~112 GiB, or ~173 GiB.

### B. Reclaimable **including** WSL2 retirement

Add `ext4.vhdx` at **171.96 GiB**.

> **Reclaimable including WSL2 retirement: ~237 GiB with no decisions, ~298 GiB with them.**
> Free space would reach ~284 GiB, or ~345 GiB of the 476 GiB volume.

Note the vhdx is **fully allocated, not sparse** — logical and on-disk both read 171.96 GiB while
only ~150 GB is used inside it. ~20 GiB is reclaimable from the vhdx *without retiring WSL2 at
all*, via `wsl --manage Ubuntu --set-sparse true` or an offline `Optimize-VHD`.

## This breaks the space deadlock

The ticket's framing was that Kubuntu could be given at most ~19 GB. That is no longer true.

**Tier-1 cleanup alone — deleting nothing but crash dumps, orphaned swap files, a regenerable VM
bundle, the hibernation file and dev caches — leaves ~112 GiB free, enough to cut a 100 GiB
Kubuntu partition while WSL2 is still running and intact.** The external HDD is not required as a
staging area, and WSL2 does not have to be retired before the install. That changes the shape of
the cutover sequence #81 has to design: it can be *install alongside, soak, then retire*, rather
than *evacuate, wipe, install, restore*.

**Caveat — the shrink limit is not the free-space number.** NTFS will not shrink past the last
immovable file (`$MFT`, pagefile, hibernation file, shadow copies). `Get-PartitionSupportedSize`
requires elevation and could not be run here, so the *actual* shrinkable figure is
**unmeasured**. It must be read after the Tier-1 cleanup, elevated, before any partition plan is
committed. Disabling hibernation and clearing shadow copies both help.

## Surprises worth carrying forward

1. **Fast Startup is enabled** (`HiberbootEnabled = 1`, `powercfg /a` confirms Hibernate and Fast
   Startup available). This is a genuine dual-boot hazard: it leaves NTFS in a hibernated state, so
   Linux either refuses to mount the Windows volume or risks corrupting it. It must be disabled
   before Kubuntu ever touches the Windows partition — a hard prerequisite for the migration spec,
   not a preference.
2. **A single 17.36 GiB WSL crash dump** (plus a 4.71 GiB sibling), both from `argusde`'s Electron
   under WSL2. WSL crash dumping is on and unbounded; it will refill.
3. **12 orphaned `swap.vhdx` files, 19.42 GiB.** WSL2 leaves these behind on unclean shutdown.
   Also self-refilling.
4. **`ext4.vhdx` is not sparse** — ~20 GiB of pure air, reclaimable today.
5. **`iCloudDrive` costs 0.05 GiB, not 849 GB.** `docs/backup-coverage.md` should be corrected.
6. **Two iOS device backups, 23.05 GiB**, sitting on the daily-driver disk with no Linux
   equivalent — a fifth Windows dependency alongside the four #77 identified.
7. Windows itself is modest: `C:\Windows` + both `Program Files` trees are ~81 GiB *inflated by
   hardlinks*. The disk is full of **user and agent-tooling state**, not Windows.

## Raw data

Sweep outputs (CSV) written to `C:\Users\deanj\AppData\Local\Temp\csweep\` —
`dirs.csv` (every directory ≥ 500 MiB, with recursive on-disk totals), `bigfiles.csv` (top 120
files ≥ 200 MiB), `denied.txt`, `reparse.txt`, `summary.json`. These are in `Temp` and will not
survive the Tier-1 cleanup above; re-run the script if they are needed again.
