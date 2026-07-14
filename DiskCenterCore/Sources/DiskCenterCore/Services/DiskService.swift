// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum DiskServiceError: Error, Sendable {
    case diskutilFailed(String)
    case malformedPlist(String)
}

/// Discovers disks by invoking `diskutil` with `-plist` output and parsing the
/// property list. Text output of `diskutil` is NEVER parsed — its format changes
/// between macOS versions. No destructive operations live here — only discovery
/// and reversible mount/unmount.
public struct DiskService: Sendable {
    private let runner: ProcessRunner
    private static let diskutil = "/usr/sbin/diskutil"

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Enumerate every whole disk and its partitions, enriched with per-disk info.
    public func listDisks() throws -> [Disk] {
        let listPlist = try runPlist(["list", "-plist"])
        let wholeDiskIDs = Self.wholeDiskIDs(from: listPlist)
        // Computed once per call: the ONLY reliable way to know which physical
        // whole disk backs the running system. Per-disk `Bootable`/`OSInternal`
        // flags are unreliable on APFS — the boot container reports Bootable=false
        // at the whole-container level (see `systemWholeDiskID`).
        let systemDiskID = try? systemWholeDiskID()

        return wholeDiskIDs.map { diskID in
            let info = try? runPlist(["info", "-plist", diskID])
            let volumes = Self.volumes(for: diskID, in: listPlist)
            return Self.makeDisk(
                id: diskID,
                info: info,
                partitions: volumes,
                isSystemDisk: diskID == systemDiskID
            )
        }
    }

    /// Mounts a volume by BSD identifier (e.g. `disk4s1`). Reversible; not a
    /// destructive operation.
    public func mount(_ volumeID: String) throws {
        let result = try runner.run(Self.diskutil, ["mount", volumeID])
        guard result.succeeded else {
            throw DiskServiceError.diskutilFailed(result.stderrString)
        }
    }

    /// Unmounts a volume by BSD identifier. Reversible; not a destructive
    /// operation — the volume's data is untouched, only ejected from the Finder.
    public func unmount(_ volumeID: String) throws {
        let result = try runner.run(Self.diskutil, ["unmount", volumeID])
        guard result.succeeded else {
            throw DiskServiceError.diskutilFailed(result.stderrString)
        }
    }

    /// Ejects a WHOLE disk (e.g. `disk4`, not a single volume like `disk4s1`)
    /// — unmounts every volume on it and spins it down so it's safe to
    /// physically remove. `unmount` only operates on one mounted volume;
    /// passing a whole-disk identifier to `diskutil unmount` doesn't do what
    /// you'd expect for a multi-volume disk, hence this separate verb
    /// (`diskutil eject`), matching what the "Create Bootable USB" flow needs.
    public func eject(_ wholeDiskID: String) throws {
        let result = try runner.run(Self.diskutil, ["eject", wholeDiskID])
        guard result.succeeded else {
            throw DiskServiceError.diskutilFailed(result.stderrString)
        }
    }

    /// Traces the mounted root volume ("/") down to the physical whole disk that
    /// backs it: root volume → its APFS physical store partition → that
    /// partition's whole disk. This is the disk that must NEVER be offered as a
    /// destructive target, regardless of what its own `Bootable`/`OSInternal`
    /// flags say (those are unreliable at the synthesized-container level).
    func systemWholeDiskID() throws -> String? {
        let rootInfo = try runPlist(["info", "-plist", "/"])
        guard let stores = rootInfo["APFSPhysicalStores"] as? [[String: Any]],
              let storeID = stores.first?["APFSPhysicalStore"] as? String
        else { return nil }

        let storeInfo = try runPlist(["info", "-plist", storeID])
        return storeInfo["ParentWholeDisk"] as? String
    }

    // MARK: - Running diskutil

    private func runPlist(_ arguments: [String]) throws -> [String: Any] {
        let result = try runner.run(Self.diskutil, arguments)
        guard result.succeeded else {
            throw DiskServiceError.diskutilFailed(result.stderrString)
        }
        return try Self.parsePlist(result.standardOutput)
    }

    static func parsePlist(_ data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = object as? [String: Any] else {
            throw DiskServiceError.malformedPlist("root is not a dictionary")
        }
        return dict
    }

    // MARK: - Parsing `diskutil list -plist`

    /// The top-level `WholeDisks` array lists whole-disk BSD names (disk0, disk1…).
    static func wholeDiskIDs(from listPlist: [String: Any]) -> [String] {
        (listPlist["WholeDisks"] as? [String]) ?? []
    }

    /// Extract partitions of `diskID` from the `AllDisksAndPartitions` array.
    static func partitions(for diskID: String, in listPlist: [String: Any]) -> [Partition] {
        guard let all = listPlist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        guard let entry = all.first(where: { ($0["DeviceIdentifier"] as? String) == diskID })
        else { return [] }

        let raw = (entry["Partitions"] as? [[String: Any]]) ?? []
        return raw.compactMap { p in
            guard let id = p["DeviceIdentifier"] as? String else { return nil }
            return Partition(
                id: id,
                content: p["Content"] as? String,
                volumeName: p["VolumeName"] as? String,
                fileSystem: p["Content"] as? String,
                size: (p["Size"] as? NSNumber)?.int64Value,
                mountPoint: p["MountPoint"] as? String
            )
        }
    }

    /// User-facing volumes for `diskID`: raw GPT partitions that are themselves
    /// terminal (e.g. a plain FAT32 stick's single partition), plus — for any
    /// raw partition that is an APFS container's physical store — that
    /// container's actual APFS volumes (Macintosh HD, Data, Preboot…) in place
    /// of the opaque container entry itself. Without this, every Apple Silicon
    /// Mac shows "no partitions" under its APFS containers, since `diskutil`
    /// nests real volumes one level deeper than the raw GPT partition table.
    static func volumes(for diskID: String, in listPlist: [String: Any]) -> [Partition] {
        guard let all = listPlist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        let raw = partitions(for: diskID, in: listPlist)

        return raw.flatMap { partition -> [Partition] in
            containerVolumes(physicalStoreID: partition.id, in: all) ?? [partition]
        }
    }

    /// If `physicalStoreID` (a raw GPT partition, e.g. `disk0s2`) backs some APFS
    /// container, returns that container's volumes; `nil` if no container claims
    /// it (i.e. the partition is itself terminal).
    ///
    /// A sealed root volume (e.g. `disk3s1`, "Macintosh HD") has no `MountPoint`
    /// of its own — its live content is exposed only through a separate
    /// snapshot entry (e.g. `disk3s1s1`) that DOES carry the real mount point
    /// (`/`). Skip the sealed parent when it has a mounted snapshot, so the
    /// volume doesn't appear twice (once "unmounted", once mounted).
    static func containerVolumes(physicalStoreID: String, in allEntries: [[String: Any]]) -> [Partition]? {
        // NOTE: `diskutil list -plist` names this field `DeviceIdentifier`, unlike
        // `diskutil info -plist <volume>`'s `APFSPhysicalStores`, which instead
        // uses `APFSPhysicalStore` (singular) — same concept, different key per
        // subcommand. `systemWholeDiskID()` above reads the `info` shape; this
        // reads the `list` shape. Mixing them up silently returns nil matches.
        guard let container = allEntries.first(where: { entry in
            let stores = (entry["APFSPhysicalStores"] as? [[String: Any]]) ?? []
            return stores.contains { ($0["DeviceIdentifier"] as? String) == physicalStoreID }
        }) else { return nil }

        let rawVolumes = (container["APFSVolumes"] as? [[String: Any]]) ?? []
        return rawVolumes.compactMap { v -> Partition? in
            guard let id = v["DeviceIdentifier"] as? String else { return nil }
            let hasMountedSnapshot = !((v["MountedSnapshots"] as? [[String: Any]])?.isEmpty ?? true)
            let mountPoint = v["MountPoint"] as? String
            if mountPoint == nil && hasMountedSnapshot { return nil }

            return Partition(
                id: id,
                content: "APFS Volume",
                volumeName: v["VolumeName"] as? String,
                fileSystem: "APFS",
                size: (v["Size"] as? NSNumber)?.int64Value,
                mountPoint: mountPoint,
                isOSInternal: (v["OSInternal"] as? Bool) ?? false
            )
        }
    }

    // MARK: - Parsing `diskutil info -plist <disk>`

    static func makeDisk(
        id: String,
        info: [String: Any]?,
        partitions: [Partition],
        isSystemDisk: Bool
    ) -> Disk {
        let mediaName = info?["MediaName"] as? String
        let ioKitName = info?["IORegistryEntryName"] as? String
        let size = (info?["Size"] as? NSNumber)?.int64Value
        let isInternal = (info?["Internal"] as? Bool) ?? false
        let isRemovable = (info?["Removable"] as? Bool) ?? false
        // Secondary heuristic only (used by callers that don't have a resolved
        // systemWholeDiskID, e.g. isolated unit tests): OSInternal is a real
        // signal, but Bootable at the whole-container level is NOT — see
        // `systemWholeDiskID` for the authoritative check used by listDisks().
        let systemImage = (info?["OSInternal"] as? Bool) ?? false

        return Disk(
            id: id,
            model: mediaName ?? ioKitName,
            size: size,
            isInternal: isInternal,
            isRemovable: isRemovable,
            isSystemDisk: isSystemDisk || systemImage,
            partitions: partitions,
            mediaKind: mediaKind(info: info, isInternal: isInternal)
        )
    }

    /// Determines the physical media type (spec §2 decision #3): whether a
    /// disk is SSD/NVMe (where multi-pass erase is pointless and harmful —
    /// Apple's own `diskutil` man page calls it "no longer considered safe" on
    /// modern devices) or a spinning HDD (where it's still meaningful).
    static func mediaKind(info: [String: Any]?, isInternal: Bool) -> MediaKind {
        let busProtocol = (info?["BusProtocol"] as? String) ?? ""
        let isSolidState = (info?["SolidState"] as? Bool) ?? false

        if busProtocol.localizedCaseInsensitiveContains("USB") { return .usb }
        if busProtocol.localizedCaseInsensitiveContains("Thunderbolt") { return .thunderbolt }
        if busProtocol.localizedCaseInsensitiveContains("NVMe") { return .nvme }
        if isSolidState { return .ssd }
        if info == nil { return .unknown }
        return .hdd
    }
}
