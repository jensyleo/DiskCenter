# Changelog

All notable changes to DiskCenter are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions follow SemVer.

## [Unreleased]

### Added — 2026-07-11 · App icon
- `Scripts/make-appicon.sh` (same pattern as the sibling apps): generates the
  full `AppIcon.appiconset` (16pt–512pt @1x/@2x) from the user's 1024×1024
  source artwork in `Icons/App/`. Wired into `project.yml`
  (`ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`, already present from the
  original scaffold). Verified visually in Finder's `/Applications` folder.

### Fixed — 2026-07-11 · Debugging/optimization pass (5 real bugs, no new features)
- **"Create Bootable USB" auto-eject used the wrong `diskutil` verb.** It
  called `diskutil unmount <wholedisk>` — `unmount` only operates on a single
  mounted volume, not a whole disk with several volumes on it, so the eject
  likely silently did nothing. Worse, the failure was swallowed by `try?`,
  so the success message falsely claimed "…and ejected. It's safe to
  unplug." regardless. Added `DiskService.eject(_:)` (the correct
  `diskutil eject` verb for a whole disk) and made the message honest: if
  eject fails, it now says so and asks for a manual eject instead of
  claiming success it didn't verify.
- **Two crash risks from a non-throwing `FileHandle.write(_:)` API.**
  `BenchmarkService`'s sequential-write pass and `LoggerService`'s log
  writer both used the legacy `write(_:)` overload, which raises an
  uncatchable Objective-C exception (not a Swift error) if the write fails —
  e.g. the volume filling up mid-benchmark, or logging when a disk is
  completely full. Both crash the app instead of failing gracefully. Fixed
  by switching to `write(contentsOf:)`, the modern Swift-throwing
  equivalent — a benchmark on a full disk now fails cleanly with an error
  message; a failed log write is silently ignored (matches the logger's own
  "must never break the feature it's observing" rule) instead of taking the
  whole app down with it.
- **A scheduled-backup filename used colons.** The auto-generated filename
  for a scheduled GPT backup used `ISO8601DateFormatter`'s output
  (`disk4-scheduled-2026-07-11T15:30:00Z.bin`) — harmless at the filesystem
  level, but Finder displays a literal `:` in a filename as `/`, making the
  file look broken/mis-named. Switched to a colon-free timestamp format.
- **`ImageService`'s compressed-image path could leak an orphaned `dd`
  process.** If the compressor failed to launch (e.g. a transient resource
  limit) AFTER `dd` had already started writing to the pipe between them,
  nothing ever terminated `dd` — it would block forever on a full, unread
  pipe buffer, an invisible zombie process. Now `dd` is explicitly
  terminated if the compressor's launch fails.
- **Settings ▸ Logs' "keep the last N log files" did nothing.** The
  preference existed and could be changed in the UI, but no code anywhere
  actually deleted old log files — a setting that silently had zero effect.
  Added `LoggerService.pruneOldLogs(keeping:)` (sorts by filename, since log
  files are named `yyyy-MM-dd.log` and that sorts chronologically) and wired
  it to run once per app launch using the real preference value.
- Minor: removed a benign but noisy compiler warning in `DiskService`.

98 unit tests total (5 new: `eject`'s correct arguments and failure path,
three `pruneOldLogs` scenarios). No behavior was changed beyond what's
described above — this pass was audit-and-fix, not new functionality.

### Added — 2026-07-11 · Phase 4: benchmark, compression, history, preferences, scheduling
- `BenchmarkService` (§4.12): sequential write/read and random-read (IOPS),
  measured against a temp file on the volume's mount point — never the raw
  device, so it can never be destructive.
- Image compression (gzip/xz/zstd) for Create Image, wired to a new
  `defaultCompression` preference. `dd`'s output is piped through the
  compressor rather than parsed for `status=progress` (would need a third
  pipe); progress instead polls the growing destination file's size every
  500ms — simpler and accurate enough for a progress bar.
- `ChecksumService` gained SHA512/MD5 digests and an image-vs-disk comparison
  (hashes the same byte count from each side, since the device is normally
  larger than the image).
- `HistoryService`: persists the most recent images/backups/clones/restores
  (capped, most-recent-first) in `UserDefaults`; shown as "Recent Activity" on
  the Dashboard.
- `LoggerService` logs are now hash-chained (tamper-evident, spec §7): each
  line embeds the SHA256 of the line before it; altering, deleting, or
  reordering any line breaks the chain from that point on. `verifyIntegrity`
  re-derives the chain and confirms it.
- `AppSettings` + a full Settings scene (⌘,): appearance, default block size,
  auto-checksum toggle, default compression, default backup folder, log
  retention. Verified visually — all three tabs render correctly.
- `ScheduledBackup`/`ScheduledBackupStore`: recurring GPT-backup schedules,
  configured in Settings ▸ Backups, checked every 15 minutes while the app is
  open (no `launchd` integration yet — documented limitation).
- 93 unit tests total (27 new), including a real gzip compress→decompress
  round-trip and real SHA512/MD5 digests checked against CryptoKit directly.

### Fixed — 2026-07-11 · Two bugs found while testing Benchmark live
- **Benchmark had no way to cancel/dismiss without running it** — the sheet
  only had a "Run Benchmark" button, no Close. A real user opening it by
  mistake would have been stuck. Added a "Close" button.
- **Benchmarking an internal system volume (e.g. `Data`) failed**: its mount
  point ROOT isn't writable by a normal user (only subfolders like the user's
  home are), so creating the test file there threw a raw, unreadable Swift
  error dump to the user. Fixed two ways: `BenchmarkService` now falls back
  to the user's home directory (same physical disk, so the benchmark is
  still valid) when the preferred mount point isn't writable, and the
  remaining failure case shows a clear, actionable message instead of a raw
  error description. Verified end-to-end on the real `Data` volume after the
  fix (Sequential Write 5461 MB/s, Read 5335.7 MB/s, Random Read 730.5 MB/s,
  187,010 IOPS on this Mac's internal SSD).

**Phase 4 is functionally complete** per the roadmap's scope, with the
documented exceptions (standalone checksum-compare UI and launchd-backed
scheduling — explicitly deferred, not forgotten).

### Added — 2026-07-11 · Phase 3: destructive operations (core + UI)
- `MediaKind` detection (`SolidState`/`BusProtocol` from `diskutil info`) wired
  into `Disk` — the foundation for media-aware erase strategy (spec §2
  decision #3). Verified against the real system.
- `EraseService` (§4.10): `allowedLevels(for:)` restricts SSD/NVMe (and
  unknown media, conservatively) to a single quick zero-fill — multi-pass is
  never offered, matching Apple's own `diskutil` man page, which calls
  multi-pass erase "no longer considered safe" on modern devices (wear-leveling
  makes the passes never touch the actual cells). HDD keeps all 5 levels.
  Defense in depth: the service itself throws if a disallowed level is
  requested for the detected media, not just the UI hiding the option.
- `CloneService` (§4.6): disk→disk / image→disk (restore), reusing `DDService`.
- `RepairService.repairDisk` (§4.9): active repair, alongside the existing
  read-only `verifyDisk` from Phase 2.
- `ValidationService` grew the full destructive checklist (§6): origin ≠
  destination, not the system disk, not a Recovery partition, and a
  best-effort local-APFS-snapshot check (`diskutil apfs listSnapshots -plist`)
  plus an open-file-handle check (`lsof -F`, a stable machine-readable mode —
  a different tool's documented format, not free-form `diskutil` text).
- App: the spec's red confirmation screen (`EraseSetupView`) — disk
  model/identifier/capacity/device path, an erase-level picker (only shown
  when more than one level is allowed), and a required "type the disk
  identifier or ERASE" field that gates the destructive button. This is a
  SEPARATE, earlier step than the simulation screen (exact command shown) —
  two independent confirmations, not one. "Secure Erase…" is hidden entirely
  for the system disk. "Repair Disk" added alongside "Verify Disk".
  Verified visually end-to-end through the red screen (without erasing
  anything — no destructive command was executed against real hardware).
- 66 unit tests total (24 new), including a real small-file clone and
  stand-in-executable-based erase/repair logic tests — never a real
  `secureErase`/`repairDisk` run against actual hardware from this session.

### Added — 2026-07-11 · Phase 3 completed: Restore/Clone/Bootable USB UI
- `Disk`/`Partition` gained `Hashable` conformance (needed for a SwiftUI
  `Picker` selection).
- App: "Restore Image…" and "Create Bootable USB…" in the toolbar's "More"
  menu; "Clone to…" per disk (source can be any disk, including the system
  disk — cloning only reads it, same as Create Image). All three share
  `CloneSetupView`, a red confirmation screen (source, a destination picker
  pre-filtered to exclude the system disk and, for Clone, the source disk
  too, device path, and the same "type the identifier or ERASE" gate as
  Secure Erase) shown before the normal simulation/execute flow.
  Create Bootable USB additionally ejects the destination automatically on
  success (spec's unmount→write→sync→verify→eject flow — the write itself
  already targets the raw device regardless of mount state, matching how
  `ImageService`/`GPTBackupService` already work; eject is the one genuinely
  distinct extra step).
  Verified visually end-to-end: the Clone Disk red screen correctly excluded
  both the source disk and the system disk from its destination picker,
  showed the right device path, and left "Continue" disabled until confirmed
  — cancelled without executing anything against real hardware.
- `INTERRUPTION-RECOVERY.md` (spec §6): what to do if an operation is
  interrupted, per operation type — imaging/backup only ever corrupts the
  destination FILE (safe to just delete and redo); restore/clone/erase can
  leave the destination DISK inconsistent (documented as: don't trust it,
  redo it, since it was already assumed lost by the red confirmation screen).
  Documents what DiskCenter already does today (per-disk lock releases
  immediately on cancel, every operation logged with a timestamp) versus what's
  explicitly not implemented yet (resumable transfers, automatic
  post-interruption state detection on next launch).

**Phase 3 is now feature-complete** per the roadmap's scope. Nothing
destructive (`secureErase`, `repairDisk`, a real `dd` restore/clone) was ever
run against real hardware during development — see `TESTING.md` for what to
verify manually, on a disposable disk, when convenient.

### Added — 2026-07-11 · Phase 2: image creation, GPT backup, disk verification
- `DDService`: builds `dd` invocations from typed, separated fields (never a
  shell string), runs them streaming `status=progress` output live, supports
  cancellation, and exposes `commandPreview` for the spec's required
  simulation step (show the exact command before it runs).
- `ImageService` (§4.4, no compression yet): copies a disk/partition to a file
  and computes its SHA256 (`ChecksumService`, streamed in 4 MiB chunks so
  multi-gigabyte images never load fully into memory).
- `GPTBackupService` (§4.8): saves the leading 1 MiB of a whole disk (GPT
  header, partition entries, protective MBR) to a file for later restoration.
- `RepairService` (§4.9, read-only this phase): runs `diskutil verifyDisk`;
  pass/fail is decided solely by the exit code, raw output is shown to the
  user verbatim for transparency, never parsed for structured fields.
- `DiskOperationLock`: per-disk exclusivity so two operations (imaging,
  backup, verify, and future erase/clone) can never target the same disk at
  once — the spec's concurrency-lock requirement, wired in from this phase.
- `ValidationService`: destination free-space check before starting. The full
  destructive checklist (origin ≠ destination, unmounted, Time Machine
  snapshots, open processes) is deferred to Phase 3, where restore/clone/erase
  are the first operations that actually need it — implementing it now, with
  nothing destructive to gate, would just be unused code.
- App: "Create Image…", "Backup GPT…", "Verify Disk" buttons per whole disk.
  Each opens a simulation sheet (exact command shown, Execute/Cancel), then
  live progress, then a result screen. Verified end-to-end against the real
  system disk (`diskutil verifyDisk disk0` — partition map OK, logged).
- 42 unit tests total (real small-file `dd` copies and a real `diskutil
  verifyDisk`-shaped process, not just mocks — per the spec's ask for
  logic testable in CI without touching real hardware).

### Fixed — 2026-07-11 · `Process`/`Pipe` race could silently drop the last output
- Found while testing a sub-10ms `dd` copy: `Process.terminationHandler` can
  fire and be read before the pipe's `readabilityHandler` has delivered the
  final buffered chunk, on a process fast enough to exit before that chunk is
  scheduled. Mixing a manual `readDataToEndOfFile()` "catch anything left
  over" call into the termination handler doesn't fix it (same race, moved).
  The reliable fix (`ProcessCompletionCoordinator`): treat "process exited"
  and "pipe reached EOF" as two independent async signals and wait for both
  before resuming — the pattern now used by both `DDService` and
  `RepairService`, so any future service piping a `Process`'s output inherits
  the fix instead of rediscovering the bug.

### Fixed — 2026-07-11 · Disk explorer now shows real APFS volumes, not raw containers
- Closed the gap noted in Phase 1: `DiskService` previously listed only
  physical/GPT-level partitions, so every APFS container disk showed "no
  partitions" and the Dashboard's mounted-volume count was always 0. It now
  resolves each container's real volumes (Macintosh HD, Data, Preboot, VM,
  Recovery…) from `diskutil list -plist`'s `APFSVolumes`, replacing the opaque
  container entry. A sealed root volume with no direct mount point is skipped
  when its live snapshot (which carries the real mount point) is listed
  separately, avoiding a duplicate row. Apple-internal volumes (iSCPreboot,
  xART, Hardware, Update) are flagged `isOSInternal` and shown dimmed with a
  "system" tag instead of hidden — kept visible per the spec's transparency
  principle. Verified against the real system: `disk0` now shows all 12
  volumes across its containers with correct mount points; Dashboard's
  "Mounted Volumes" went from 0 to 8.
- Found and fixed a real bug while wiring this: `diskutil list -plist` names
  an APFS container's physical-store reference `DeviceIdentifier`, while
  `diskutil info -plist <volume>` names the same concept `APFSPhysicalStore`
  (singular) — same idea, different key per subcommand. The first
  implementation (and its unit test fixture) used the wrong key consistently
  with itself, so tests passed while the feature silently did nothing against
  the real system. Caught by verifying against real `diskutil` output via the
  CLI harness, not by trusting the test alone — now both are fixed and a CLI
  spot-check is part of the workflow for any `diskutil` plist-shape change.

### Added — 2026-07-11 · Dashboard and accessibility
- `DashboardView` (spec §4.1): summary cards for disks connected, total
  capacity, mounted volumes, and SMART health (with a red warning banner if any
  disk is failing). Sidebar now has real navigation (Dashboard vs. a specific
  disk) instead of a single flat list.
- Explicit VoiceOver labels across the sidebar, Dashboard cards, SMART row, and
  partition rows (mount/unmount buttons keep their own actionable label rather
  than being absorbed into a combined row label).
- `TESTING.md`: manual test checklist for what can't be verified headlessly
  (real hardware, VoiceOver, wrong-password flow, etc.).

### Added — 2026-07-11 · Phase 1: SMART, mount/unmount, logging
- `SMARTService`: basic status via `diskutil info -plist` (`SMARTStatus`, no
  external dependency) plus detailed attributes (temperature, power-on hours,
  reallocated sectors) via `smartctl` when the user has installed it — invoked
  as an external process, never bundled, per smartmontools' GPL terms. Surfaces
  the USB-bridge-without-passthrough limitation instead of hiding it.
- Reversible mount/unmount per partition (`DiskService.mount/unmount`), with
  toolbar buttons in the disk detail list.
- `LoggerService`: appends one line per event (list refresh, SMART read,
  mount/unmount, failures) to a daily file under
  `~/Library/Application Support/DiskCenter/logs/`.

### Fixed — 2026-07-11 · Concurrent `diskutil` calls returned wrong SMART data
- Loading SMART status for all four disks in parallel (one async task per row)
  intermittently returned `Not Supported` for a disk that reports `Verified`
  when queried alone. Reproduced with plain concurrent shell invocations of
  `diskutil` itself — a race in `diskutil`/diskarbitrationd under simultaneous
  calls, unrelated to this app's parsing. `ProcessRunner` now serializes every
  real external-tool launch with a process-wide lock. Verified with 5 rounds of
  4 concurrent lookups (100% correct after the fix, previously flaky roughly
  1 in 4–8 attempts) and a permanent regression test that measures actual
  execution time to prove launches no longer overlap.

### Added — 2026-07-11 · Privilege mechanism: own sudo sheet (TCPV4MAC pattern)
- Closed the architecture decision on privileges (spec §2, decision #1): DiskCenter
  uses the same in-app sudo relaunch as TCPV4MAC instead of `SMAppService` + XPC,
  avoiding a dependency on a paid Developer ID. `SudoRelaunch` validates the typed
  password via `sudo -S -k` (stdin only, never argv/logs) and relaunches the app
  detached, inside the GUI session; `AdminPasswordSheet` is the in-app prompt
  (with a copyable CLI-equivalent command); the toolbar's "More" menu exposes
  "Run as Administrator…", and a blue "Admin" badge appears once elevated.
  Verified end-to-end on a real build: authenticating with a real password
  relaunched the app as root, and quitting left no orphaned processes.

### Fixed — 2026-07-11 · Reliable system-disk detection
- `Bootable`/`OSInternal` at the whole-APFS-container level are not reliable on
  Apple Silicon: the boot container itself reports `Bootable=false` (the actually
  bootable volume lives one layer down, synthesized on top of it). `DiskService`
  now resolves the real physical system disk by tracing the mounted root volume
  ("/") down through its APFS physical store to the whole disk that backs it
  (`diskutil info -plist /` → physical store → `ParentWholeDisk`), and marks only
  that disk as the system disk — the one that must never be offered as a
  destructive target. `OSInternal` is kept as a secondary signal. Verified against
  the real disk layout and by screenshot (only the physical disk is flagged).

### Added — 2026-07-10 · Project scaffold (Phase 0 groundwork)
- `DiskCenterCore` Swift package: `Disk`/`Partition` models, a `ProcessRunner`
  that always launches tools with separated arguments (never a shell string),
  and a `DiskService` that discovers disks by parsing `diskutil list -plist` and
  `diskutil info -plist` — property lists only, text output is never parsed.
- `diskcenter-cli` verification harness that lists real disks via the core.
- Unit tests for the plist parser and system-disk detection.
- SwiftUI app target (XcodeGen `project.yml`): read-only disk/partition list,
  About panel and Help alert with a GPLv3 / no-warranty notice.
- Bundle identifier `com.jensyleo.diskcenter`; ad-hoc signed; no App Sandbox.
