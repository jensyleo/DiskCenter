// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum ValidationError: Error, Sendable, Equatable {
    case insufficientSpace(availableBytes: Int64, requiredBytes: Int64)
    case destinationNotWritable(String)
    case sameDisk(String)
    case isSystemDisk(String)
    case isRecoveryPartition(String)
    /// Non-fatal by design — the caller decides whether to warn and let the
    /// user proceed, or block. See `checkForLocalSnapshots` doc comment.
    case hasLocalSnapshots(diskID: String, names: [String])
}

/// Pre-flight checks (spec §6). Phase 2 only needed the free-space check
/// (imaging/backup write brand-new files, nothing existing to collide with).
/// Phase 3 (restore/clone/erase) overwrites an EXISTING disk or volume, so the
/// full destructive checklist is implemented here: origin ≠ destination,
/// destination isn't the system disk, isn't a Recovery partition, and a
/// best-effort local-snapshot check. Per-disk concurrency lives separately in
/// `DiskOperationLock`.
public struct ValidationService: Sendable {
    private let runner: ProcessRunner
    private static let diskutil = "/usr/sbin/diskutil"

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Confirms `destinationDirectory`'s volume has at least `requiredBytes`
    /// free. A generous 5% margin is added on top of the exact source size,
    /// since some filesystems reserve space and image files can round up.
    public func validateSufficientSpace(destinationDirectory: URL, requiredBytes: Int64) throws {
        let values = try destinationDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage else {
            throw ValidationError.destinationNotWritable(destinationDirectory.path)
        }
        // Overflow-safe 5% margin: fall back to `requiredBytes` unchanged if
        // adding the margin would exceed Int64 (a pathological/test-only size).
        let margin = requiredBytes / 20
        let withMargin = requiredBytes > Int64.max - margin ? requiredBytes : requiredBytes + margin
        guard available >= withMargin else {
            throw ValidationError.insufficientSpace(availableBytes: available, requiredBytes: withMargin)
        }
    }

    /// The source and destination of a destructive operation (restore, clone)
    /// must never be the same disk.
    public func validateOriginNotDestination(sourceDiskID: String, destinationDiskID: String) throws {
        guard sourceDiskID != destinationDiskID else {
            throw ValidationError.sameDisk(sourceDiskID)
        }
    }

    /// Never allow the boot/system disk as a destructive TARGET. (It can
    /// still be a read-only SOURCE for imaging — see `ImageService`.)
    public func validateNotSystemDisk(_ disk: Disk) throws {
        guard !disk.isSystemDisk else {
            throw ValidationError.isSystemDisk(disk.id)
        }
    }

    /// Recovery partitions are identified by content hint or volume name —
    /// `diskutil`'s `Content` field for these is a stable string
    /// ("Apple_APFS_Recovery" or a volume literally named "Recovery"), not
    /// free-form text being parsed for meaning beyond an exact-match check.
    public func validateNotRecoveryPartition(_ partition: Partition) throws {
        let content = partition.content ?? ""
        let name = partition.volumeName ?? ""
        if content.localizedCaseInsensitiveContains("Recovery") || name.localizedCaseInsensitiveContains("Recovery") {
            throw ValidationError.isRecoveryPartition(partition.id)
        }
    }

    /// Best-effort check for local APFS snapshots on `volumeID` that would be
    /// silently discarded by a destructive operation — informational: the
    /// caller decides whether to warn-and-allow or block, since a snapshot
    /// existing isn't by itself unsafe (e.g. it may already be backed up
    /// elsewhere). Uses `-plist` output only; never parses free-form text.
    public func checkForLocalSnapshots(volumeID: String) throws -> [String] {
        let result = try runner.run(Self.diskutil, ["apfs", "listSnapshots", "-plist", volumeID])
        guard result.succeeded else { return [] }
        guard let plist = try? DiskService.parsePlist(result.standardOutput) else { return [] }
        let snapshots = (plist["Snapshots"] as? [[String: Any]]) ?? []
        return snapshots.compactMap { $0["SnapshotName"] as? String }
    }

    /// Processes with an open file handle on `mountPoint` — offer to close
    /// them (or force-unmount) before a destructive operation, rather than
    /// have the operation fail confusingly partway through. `lsof` (not
    /// `diskutil`) has a stable machine-readable mode (`-F`, field-prefixed
    /// lines) that's parsed here — a different tool's documented format, not
    /// the free-form `diskutil` text the codebase otherwise never parses.
    public func processesHoldingOpen(mountPoint: String) throws -> [(pid: Int32, command: String)] {
        let result = try runner.run("/usr/sbin/lsof", ["-F", "pc", mountPoint])
        guard result.succeeded else { return [] }
        return Self.parseLsofFieldOutput(result.stdoutString)
    }

    static func parseLsofFieldOutput(_ output: String) -> [(pid: Int32, command: String)] {
        var items: [(Int32, String)] = []
        var currentPID: Int32?
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())
            switch marker {
            case "p": currentPID = Int32(value)
            case "c":
                if let pid = currentPID { items.append((pid, value)) }
            default: break
            }
        }
        return items
    }
}
