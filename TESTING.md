# Manual testing checklist

Automated coverage (66 unit tests, `swift test --package-path DiskCenterCore`)
and static build verification are in place. The items below need a human,
external hardware, or interactive UI/system state that can't be driven headlessly
— run them when convenient. **Nothing in Phase 3 (erase/repair) has been run
against real hardware from any automated session — every destructive path
below is genuinely untested against a real disk.**

## Dashboard (§4.1)
- [ ] Numbers match reality: disk count, total capacity, mounted-volume count
      against what Finder/`diskutil list` shows.
- [ ] Plug in an external drive mid-session, hit Refresh, confirm the Dashboard
      updates (count, capacity, health).
- [ ] Force a disk with `SMARTStatus: Failing` (or simulate) and confirm the red
      warning banner appears with the correct count.

## Disk explorer (§4.2/4.3)
- [ ] Confirm every real volume (Macintosh HD, Data, Preboot, VM, Recovery,
      plus the hidden system ones) shows up with the right mount point and
      size — cross-check against `diskutil list` in Terminal.
- [ ] Attach an external APFS-formatted drive with more than one volume in its
      container and confirm they all appear (this was only verified against
      the internal disk's containers so far).
- [ ] System disk badge: confirm only the *physical* boot disk (not every APFS
      container) shows "SYSTEM" — verified once on this Mac; re-check on an
      Intel Mac or a Mac with Fusion Drive/CoreStorage if available.

## SMART (§4.11)
- [ ] Install `smartmontools` (`brew install smartmontools`) and confirm
      temperature/power-on-hours/reallocated-sector values appear and look sane
      against `smartctl -a` run directly in Terminal.
- [ ] Test against a USB external drive whose bridge does NOT support SMART
      passthrough — confirm the "doesn't expose SMART data" message appears
      instead of a silent failure or a wrong status.
- [ ] Without `smartmontools` installed, confirm the "Install smartmontools for
      details" hint is accurate and the basic status is still correct.

## Mount / unmount
- [ ] Unmount an external volume, confirm it disappears from Finder and the
      green mounted dot clears; mount it again, confirm it reappears in Finder.
- [ ] Try unmounting a volume that's in use (e.g. has an open Terminal `cd`'d
      into it) — confirm the error alert shows a clear message, not a crash.

## Admin relaunch (SudoRelaunch / AdminPasswordSheet)
- [x] Real end-to-end test done by the user (2026-07-11): correct password
      relaunches as root, no orphaned process after quitting.
- [ ] Wrong password: confirm the sheet shows "Incorrect password" and stays
      open for retry (doesn't quit or hang).
- [ ] Copy-command button: paste the copied command into Terminal, confirm it
      relaunches as admin and closes the terminal window as described.

## Accessibility
- [ ] Turn on VoiceOver (⌘F5) and navigate: sidebar (Dashboard vs. each disk),
      Dashboard cards, SMART row, partition rows, mount/unmount button. Confirm
      every element has a sensible spoken label (not just "button" or a raw
      SF Symbol name).
- [ ] Keyboard-only navigation: Tab/arrow keys through sidebar and toolbar
      without a mouse.

## Logging
- [ ] After a session (refresh, mount/unmount, SMART reads), open
      `~/Library/Application Support/DiskCenter/logs/YYYY-MM-DD.log` and confirm
      entries are readable and timestamps look correct.

## Concurrency fix regression
- [x] Automated: `ProcessRunnerTests.realLaunchesNeverOverlap` proves real
      launches never overlap (timing-based).
- [ ] Manual spot-check occasionally: refresh a few times in a row with several
      disks attached and confirm SMART status is never wrong (this was the
      original bug — serialized now, but worth re-confirming after any
      `ProcessRunner`/`SMARTService` change).

## Phase 2: Create Image (§4.4)
- [x] Automated: real small-file copy + SHA256 match (`ImageServiceTests`).
- [ ] Create a real image of a small external volume (not the boot disk — a
      spare USB stick is ideal). Confirm: the simulation sheet shows the right
      `dd` command, progress updates look sane (bytes/speed), the resulting
      `.img` file opens/mounts correctly, and the shown SHA256 matches
      `shasum -a 256` run on the file directly.
- [ ] Try imaging the live system disk (`disk0`) — expected to work (read-only)
      but confirm the result is usable and the UI doesn't claim false
      precision about "crash consistency" of a live copy.
- [ ] Cancel mid-copy on a large source; confirm the process actually stops
      (check Activity Monitor for a lingering `dd`), the partial file is
      cleaned up or clearly marked incomplete, and the disk lock releases
      (try starting a new operation on the same disk right after).
- [ ] Try creating two images of the *same* disk at once (or an image while a
      GPT backup of that disk is running) — confirm the second attempt is
      rejected with a clear "already running" message, not silently queued or
      allowed to run concurrently.
- [ ] Point the destination at a volume with insufficient free space — confirm
      the space-check alert appears before anything runs, not a `dd` failure
      partway through.
- [ ] Confirm running as non-root: imaging an external volume you own should
      work without elevation; imaging the raw system disk may need "Run as
      Administrator" first — confirm the failure message (if any) is clear
      enough to point the user there.

## Phase 2: Backup GPT (§4.8)
- [ ] Back up a real disk's GPT, then inspect the resulting file (`xxd` or
      similar) and confirm it starts with the protective MBR signature and a
      recognizable GPT header — cross-check against `gpt show <disk>` in
      Terminal.

## Phase 2: Verify Disk (§4.9)
- [x] Automated: exit-code-only pass/fail logic (`RepairServiceTests`), plus a
      real end-to-end run against the live system disk during development
      (`diskutil verifyDisk disk0` — passed, logged correctly).
- [ ] Verify a disk with a KNOWN issue if you have one available (or
      deliberately create one on a disposable test volume) and confirm the
      "Failed" state shows the real diagnostic text, not just a generic error.
- [ ] Cancel a verify mid-run on a large disk; confirm it actually stops.

## Phase 3: Media-kind detection
- [x] Automated: verified via `diskcenter-cli` during development that all 4
      internal containers report `media=SSD` correctly.
- [ ] Test against a real spinning HDD (internal or USB enclosure) and confirm
      it reports `HDD`, not `SSD` — no HDD was available to verify against
      during development.
- [ ] Test against a real USB flash drive and an NVMe external enclosure;
      confirm `BusProtocol` detection reports `USB`/`NVMe` correctly (only
      "Apple Fabric" internal SSD was available to verify against).

## Phase 3: Secure Erase (§4.10) — HIGH RISK, use a disposable test disk
- [x] Automated: level-gating logic (`EraseServiceTests`) and exit-code pass/
      fail, all against stand-in executables (`/usr/bin/true`/`false`) —
      **no real `diskutil secureErase` has been run**.
- [x] Visually verified the red confirmation screen renders correctly (model,
      identifier, capacity, device path, SSD-only quick-fill note, "type
      disk1 or ERASE" gate) — confirmed on a real disk without erasing it.
- [ ] **Use a spare/disposable external disk you don't need** (never the
      internal disk, never anything with data you care about). Confirm:
      - "Secure Erase…" doesn't appear at all for the system disk.
      - The picker for an HDD shows all 5 levels; for an SSD/USB-flash it
        shows NO picker, just the quick zero-fill note.
      - Typing the wrong text keeps "Erase" disabled; typing the exact disk
        identifier OR literally "ERASE" enables it.
      - After confirming the red screen, the simulation screen still shows
        the exact `diskutil secureErase` command before anything runs.
      - After a real erase, the disk shows as blank/unpartitioned in Finder
        and re-appears correctly in DiskCenter after Refresh.
      - Cancel mid-erase; confirm the process actually stops (Activity
        Monitor) and the disk lock releases.

## Phase 3: Repair Disk (§4.9, active)
- [ ] Deliberately create a MINOR filesystem issue on a disposable test
      volume (if you know how) and confirm "Repair Disk" actually fixes it —
      re-run "Verify Disk" afterward to confirm clean.
- [ ] Confirm the concurrency lock: try Verify Disk and Repair Disk on the
      same disk at the same time — the second should be rejected immediately
      with a clear "already running" message.

## Phase 4: Benchmark, compression, history, preferences, scheduling
- [x] Automated: benchmark metrics are positive and the temp file is cleaned
      up; the home-directory fallback (`BenchmarkServiceTests`).
- [x] Visually verified: Settings scene (all 3 tabs), and a real benchmark run
      against the `Data` volume (fallback fixed a real failure found live).
- [ ] Run a benchmark against an EXTERNAL drive (not an internal system
      volume) and confirm it writes to the drive's own root directly (no
      fallback needed) — only internal-volume fallback was verified.
- [ ] Create a compressed image (gzip) of a real disk/partition and confirm
      it actually opens/decompresses correctly with `gunzip`/Archive Utility.
- [ ] If you have `xz` or `zstd` installed via Homebrew, confirm those
      compression options work too (only gzip was verified against real data).
- [ ] Confirm "Recent Activity" on the Dashboard updates after a real
      Create Image / Backup GPT / Clone / Restore, and that "Clear" empties it.
- [ ] Add a scheduled GPT backup (Settings ▸ Backups), set a short interval
      for testing, leave the app open, and confirm it actually runs when due
      (check the log file and the destination folder) — the periodic checker
      itself was never exercised end-to-end, only its due-date logic in isolation.
- [ ] Confirm a schedule does NOT run if you quit and reopen the app before
      the interval elapses, and DOES run (once) shortly after reopening if
      the interval elapsed while the app was closed.

## Phase 3: Restore Image / Clone Disk / Create Bootable USB — HIGH RISK, use disposable disks
- [x] Automated: real small-file copy end-to-end (`CloneServiceTests`).
- [x] Visually verified the Clone Disk red screen: destination picker
      correctly excluded both the source disk and the system disk, device
      path shown correctly — confirmed without executing anything.
- [ ] **Use spare/disposable disks.** Restore a real image to one, confirm it
      mounts and matches the source (checksum). Clone one small disk to
      another, confirm every partition/volume matches. Create a real bootable
      USB from a real ISO, confirm it actually boots on real hardware and
      that it auto-ejects on success (message says "safe to unplug" — verify
      that's actually true, i.e. no lingering write cache).
- [ ] Confirm the destination picker never lets you pick the system disk or
      (for Clone) the source disk, no matter how many disks are attached.
- [ ] Cancel mid-restore/clone; confirm the destination disk's state matches
      `INTERRUPTION-RECOVERY.md`'s guidance (unusable until redone) and that
      DiskCenter doesn't claim success.
- [ ] Confirm two operations can't target the same destination disk at once
      (e.g. start a Clone to disk5, then immediately try a Restore to disk5).
