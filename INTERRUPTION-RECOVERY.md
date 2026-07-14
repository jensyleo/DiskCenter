# Interruption recovery (spec §6)

What happens if a DiskCenter operation is interrupted — power loss, forced
quit, unplugging a drive, or hitting Cancel mid-run — and what the user should
do afterward.

## General principle

`dd`-based operations (Create Image, Backup GPT, Restore Image, Clone Disk,
Create Bootable USB) write sequentially and are **not transactional** — an
interruption leaves the destination in a partially-written state. DiskCenter
does not currently support resuming a partial transfer; **the safe assumption
after any interruption is that the destination is unusable until re-verified
or redone.**

## Per-operation guidance

### Create Image / Backup GPT
The **source is never at risk** — these only read. If interrupted, the
destination **file** is incomplete/corrupt. Action: delete the partial file
and re-run the operation. There is no partial-checksum trick that makes a
truncated image usable.

### Restore Image / Clone Disk / Create Bootable USB
The **destination disk** is at risk — it was mid-overwrite when interrupted.
Its partition table and/or filesystem may be in an inconsistent state.
Action: **do not treat the destination as usable.** Re-run the same restore/
clone from the start (destination content is already assumed lost — that's
what the red confirmation screen already warned about) rather than trying to
mount or repair it. Only after a full, uninterrupted re-run should you trust
the destination again.

### Secure Erase
`diskutil secureErase` is Apple's own tool; if interrupted, the disk may be
partially erased and will very likely fail to mount. Re-run Secure Erase
(same disk, same or different level) rather than attempting to use it as-is —
a partially-erased disk isn't a "less erased" disk, it's an inconsistent one.

### Verify Disk / Repair Disk
Both are `diskutil` operations with their own internal safety — an
interrupted `verifyDisk` simply produces no result (safe: it's read-only).
An interrupted `repairDisk` should be **re-run** before trusting the disk;
`diskutil`'s repair is designed to be re-entrant (running it again on an
already-repaired or partially-repaired disk is safe).

## What DiskCenter does today

- **Cancel button**: sends the process a normal termination signal (not
  `SIGKILL`) and the disk's `DiskOperationLock` releases immediately, so a
  new operation can start right away — but the interruption guidance above
  still applies to whatever state the destination was left in.
- **Per-disk lock**: prevents a second operation from starting on a disk that
  already has one in progress, so at least DiskCenter itself won't compound
  an interruption by racing two writers against the same disk.
- **Logging**: every operation's start/success/failure is recorded in
  `~/Library/Application Support/DiskCenter/logs/` with a timestamp — useful
  to reconstruct what was happening if the app itself was killed rather than
  cleanly cancelled (a log entry with no matching completion entry means it
  was interrupted mid-run).

## Not implemented (future work, Phase 4+)

- **Resumable transfers**: `dd`'s `seek=`/`skip=` could in principle resume a
  known-good prefix, but verifying "known-good" after an unclean interruption
  reliably (not just assuming the last N written bytes are intact) needs a
  checksum-per-chunk design that doesn't exist yet. Tracked as a future
  enhancement, not attempted here.
- **Automatic post-interruption state detection**: DiskCenter doesn't
  currently detect "this disk was left mid-operation" on next launch (e.g. by
  checking for a stale lock/marker file) — treat any disk you were operating
  on when the app or system crashed as suspect until manually re-verified.
