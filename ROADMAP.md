# Roadmap

Each phase is a self-contained, usable MVP that builds on the previous one
without breaking what was already delivered.

## Phase 0 — Technical foundation (architecture spike)
- Privilege mechanism: **decided** — an in-app sudo relaunch (same pattern as
  TCPV4MAC), not `SMAppService`/XPC, to avoid depending on a paid Developer ID.
  Verified end-to-end with a real password. ✅ done
- Reliable system-disk detection (traces "/" through its APFS physical store to
  the real whole disk — whole-container `Bootable`/`OSInternal` are not
  trustworthy on Apple Silicon). ✅ done
- `DiskService` reading `diskutil list -plist` into Swift models. ✅ done
- Ad-hoc signing working end to end (real ad-hoc, not linker-signed). ✅ done
- Notarized distribution / packaging: not pursued (requires a paid Developer ID;
  same constraint as the privilege decision above).
- Sandbox / distribution policy documented.

## Phase 1 — Read-only MVP ("see and understand")
- Dashboard (summary cards), sidebar navigation, disk explorer. ✅ done
- SMART in read mode, USB-bridge-without-passthrough handled explicitly. ✅ done
- Simple mount / unmount (reversible). ✅ done
- Basic logging (`LoggerService`), Dark Mode, VoiceOver labels. ✅ done
- Manual test checklist for what can't be automated: see `TESTING.md`.
- Disk explorer resolves real APFS volumes (Macintosh HD, Data, Preboot, VM,
  Recovery…) instead of opaque GPT containers; Apple-internal volumes shown
  dimmed with a "system" tag rather than hidden. ✅ done

**Phase 1 is functionally complete.** Remaining before moving to Phase 2:
manually work through `TESTING.md` (VoiceOver, real hardware, wrong-password
flow) at your convenience.

## Phase 2 — Backups and verification (safe, non-destructive on the source)
- Create image (SHA256 checksum included), GPT backup, disk verify (read-only
  `verifyDisk`). ✅ done
- Per-disk concurrency lock (`DiskOperationLock`) — real infrastructure used by
  every operation from this phase onward. ✅ done
- Simulation mode: exact command shown before executing, Execute/Cancel. ✅ done
- `ValidationService`: destination free-space check. ✅ done — the full
  destructive checklist (origin ≠ destination, unmounted, Time Machine
  snapshots, open processes) is deferred to Phase 3, where it actually gates
  something (nothing in Phase 2 overwrites an existing disk/volume).
- Compression (gzip/xz/zstd) deferred to Phase 4, per spec.
- Manual test checklist: see `TESTING.md` (real hardware imaging/verify runs,
  cancellation mid-copy, insufficient-space case).
- **Minor known gap**: selecting an APFS container disk (`disk1`/`disk2`/
  `disk3`) directly in the sidebar shows "No partitions" — their real volumes
  only resolve when browsing the *physical* parent disk (`disk0`), since
  `DiskService.volumes` only replaces a raw GPT partition that's a container's
  physical store, not a container browsed as itself. Not blocking (the
  physical disk view already shows everything); worth revisiting if it proves
  confusing in practice.

## Phase 3 — Controlled destructive operations (the professional core)
- Secure erase with media-type detection (HDD gets all 5 `secureErase` levels;
  SSD/NVMe/unknown get ONLY quick zero-fill — enforced by `EraseService`
  itself, not just hidden in the UI). ✅ done
- Red confirmation screen (type disk identifier or `ERASE`), separate from and
  before the simulation screen. ✅ done — verified visually end-to-end
  (without erasing anything for real)
- Active repair (`repairDisk`), alongside the existing read-only `verifyDisk`. ✅ done
- `ValidationService`'s destructive checklist: origin ≠ destination, not the
  system disk, not Recovery, local-snapshot check, open-file-handle check. ✅ done
- `CloneService` backend (disk→disk / image→disk restore) ready and tested. ✅ done
- Privileged helper: still the in-app sudo relaunch from Phase 0 (not
  `SMAppService`) — no change needed here.
- Restore Image, Clone Disk, and Create Bootable USB UI, all sharing the same
  red confirmation screen (`CloneSetupView`) as Secure Erase. ✅ done —
  verified visually end-to-end (Clone Disk's destination picker correctly
  excluded the source and system disk); cancelled before executing anything
  for real.
- Interruption recovery documented per operation type: see
  `INTERRUPTION-RECOVERY.md`. ✅ done

**Phase 3 is feature-complete.** Manual test checklist: see `TESTING.md` —
**nothing destructive was run against real hardware during development**;
every erase/repair/clone/restore test is either a stand-in executable
(`/usr/bin/true`/`false`) or a real-but-harmless small-file copy. Real
hardware verification (on a disposable disk) is explicitly deferred to you.

## Phase 4 — Advanced features and quality of life
- Benchmark (§4.12): sequential write/read + random-read IOPS, measured with a
  temp file on the volume's own mount point (never the raw device — can never
  be destructive). Falls back to the user's home directory when a volume's
  mount-point ROOT isn't user-writable (e.g. `/System/Volumes/Data` itself) —
  found and fixed while testing live: same physical disk, still a valid
  benchmark. ✅ done — verified end-to-end on the real `Data` volume.
- Image compression (gzip/xz/zstd): `dd` piped through the compressor: gzip
  ships with macOS; xz/zstd are optional external tools (same pattern as
  `smartctl`), detected, never bundled. ✅ done — verified with a real gzip
  round-trip (compress then decompress, byte-identical).
- Extra checksums (SHA512, MD5) and an image-vs-disk comparison in
  `ChecksumService`. ✅ core done — no dedicated standalone-verify UI yet
  (SHA256 is still what's shown automatically after Create Image).
- History (§7): last images/backups/clones/restores, shown as "Recent
  Activity" on the Dashboard. ✅ done.
- Full preferences (§8): Settings scene (⌘,) — appearance, default block
  size, auto-checksum, default compression, default backup folder, log
  retention. ✅ done — verified visually (all three tabs render correctly).
- Scheduled backups: recurring GPT backups, configured in Settings ▸ Backups,
  checked every 15 minutes while the app is open. ✅ done — **known
  limitation**: no `launchd` integration yet, so a schedule does nothing if
  DiskCenter isn't running at the due time (documented in
  `ScheduledBackup`'s doc comment).
- Tamper-evident logs (§7): hash-chained (`LoggerService`) — altering,
  deleting, or reordering any line breaks the chain from that point on. ✅ done.
- Manual test checklist: see `TESTING.md`.

## Phase 5 — Expansion

**Sequencing (decided 2026-07-11): do NOT start Phase 5 yet.** The order is:
1. Work through `TESTING.md` on real/disposable hardware (Phases 1-4).
2. Fold in whatever bugs, gaps, or rough edges that testing surfaces —
   the same way the Benchmark bugs got caught and fixed by testing live in
   Phase 4, more almost certainly remain in the destructive paths
   (erase/clone/restore) that were only tested with stand-ins so far.
3. Publish to GitHub (README/CHANGELOG already in English, impersonal,
   GPLv3 — see the `Publicar GitHub/` convention used in the sibling
   projects).
4. Only then take on Phase 5, since it's a genuine scope jump (multi-platform,
   a real plugin API, network operations) — not a natural continuation of
   polishing the macOS app.

### Scope
- Linux/Windows ports.
- Remote SSH cloning (clone/backup a disk on another machine over the network).
- APFS snapshots as a first-class flow (browse/mount/restore individual
  snapshots, not just detect them for the destructive-checklist warning).
- AppleRAID / Fusion Drive (software RAID management, legacy CoreStorage
  read support on older Intel Macs).
- A plugin system and external-tool integrations (detailed below).

### What plugins would DiskCenter actually need?

None of `DiskCenterCore`'s services are hard-coded to one vendor or format —
the plugin points are exactly where the spec already anticipates variation:

1. **Image format converters** — read/write VHD, VMDK, QCOW2, raw `.img`,
   Apple `.dmg`/sparse image, so an image made by DiskCenter is usable in a
   VM tool (or vice versa). Today `ImageService` only does raw `dd`-style
   copies.
2. **Compression backends** — `CompressionKind` is already a small enum with
   a detect-and-invoke pattern (gzip/xz/zstd); a plugin API would let a
   third party add e.g. `lz4` or `brotli` without touching core code.
3. **Erase strategies** — `EraseService` only knows `diskutil secureErase`.
   A plugin could add vendor-specific NVMe/ATA sanitize commands (e.g. via
   `nvme-cli` on Linux) for drives where the OS-level command isn't the best
   option.
4. **Cloud backup destinations** — a plugin that lets Create Image / Backup
   GPT target S3/Backblaze B2/a NAS over SFTP instead of only a local file,
   reusing the same simulation-mode + progress UI.
5. **Filesystem-specific repair/recovery** — `RepairService` only wraps
   `diskutil verifyDisk`/`repairDisk` (APFS/HFS+). A Linux port would need
   `fsck.ext4`/`btrfs check` plugins behind the same `RepairResult` shape.
6. **Notifications** — a plugin that posts to Slack/email/a webhook when a
   scheduled backup fails or a SMART status flips to Failing, instead of
   only writing to the local hash-chained log.
7. **Custom disk-info providers** — for hardware `diskutil` doesn't fully
   describe (RAID controllers, exotic enclosures), a plugin could supply
   extra `Disk`/`MediaKind` detail beyond what `DiskService` parses today.

The common thread: every plugin point is a service DiskCenter already has
(`ImageService`, `CompressionService`, `EraseService`, `RepairService`,
`LoggerService`, `DiskService`) — Phase 5's job is turning each into a
protocol with a default built-in implementation, not inventing new surface.

### How would external-tool integrations actually work?

Same pattern already proven three times in this codebase (`smartctl`,
`xz`/`zstd`, and the erase-level gating) — **detect, never bundle, degrade
gracefully**:

- Check a list of candidate paths (`/opt/homebrew/bin/…`, `/usr/local/bin/…`)
  for the tool's executable at runtime.
- If present, expose the feature in the UI; if absent, hide/gray it out with
  an "install via Homebrew" hint — never a broken button.
- Wrap each tool in its own service (own `Process`, not the shared
  `ProcessRunner` lock, following `DDService`'s reasoning) so a long-running
  external tool never blocks unrelated UI.
- Never vendor the tool's binary into the app bundle — keeps DiskCenter's own
  GPLv3 license clean of the external tool's licensing terms (the same
  reasoning already documented for `smartctl`, which is GPL).

Per tool:
- **`ddrescue`** — alternative to `dd` for a damaged/failing disk: skips and
  retries bad sectors instead of stopping. Natural fit as a "Recover from
  Damaged Disk" mode alongside today's plain Create Image, sharing
  `ImageService`'s destination-picker/checksum/progress UI.
- **`rsync`** — file-level (not block-level) backup: copies just files/
  folders with incremental updates, unlike `dd`'s always-full-disk copy.
  Would need its own progress parser (rsync's `--info=progress2`) instead of
  the `dd`/`status=progress` one `DDService` already has.
- **`testdisk` / `photorec`** — partition-table recovery and raw file
  carving. Both have scriptable/batch CLI modes; would back a new "Recover
  Lost Partitions" / "Recover Deleted Files" advanced feature, parsing their
  structured log output the same careful way `RepairService` treats
  `diskutil`'s text (transparency, not blind trust).
- **`VeraCrypt`** — encrypted container support via its CLI (mount/unmount/
  create), so DiskCenter can detect and handle VeraCrypt volumes without
  reimplementing any cryptography.
- **Clonezilla / Ventoy / balenaEtcher** — these are complete competing
  applications, not libraries, so "integration" means something narrower:
  reading/writing image formats compatible with what they produce (so a
  Clonezilla image can be restored via DiskCenter, or a DiskCenter image
  boots correctly when written by Ventoy), not shelling out to them directly.
- **ZFS tools (`zpool`/`zfs`)** — relevant once there's a Linux port (or rare
  OpenZFS-on-Mac setups): `zpool status`/`scrub` as an alternative SMART-like
  health view for a ZFS pool, alongside — not replacing — today's
  disk-level SMART.
