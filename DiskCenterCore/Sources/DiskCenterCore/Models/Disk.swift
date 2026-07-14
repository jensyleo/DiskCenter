// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The connection/media type of a physical disk, as reported by the system.
public enum MediaKind: String, Sendable, Codable, Hashable {
    case ssd = "SSD"
    case hdd = "HDD"
    case nvme = "NVMe"
    case usb = "USB"
    case thunderbolt = "Thunderbolt"
    case diskImage = "Disk Image"
    case unknown = "Unknown"
}

/// A partition or volume living on a physical disk. For a plain disk (e.g. a
/// FAT32 USB stick) this is a raw GPT partition. For an APFS container this is
/// the actual user-facing volume (Macintosh HD, Data, Preboot…) — not the
/// opaque container itself; see `DiskService.volumes(for:in:)`.
public struct Partition: Identifiable, Sendable, Codable, Equatable, Hashable {
    /// BSD identifier, e.g. `disk0s1`.
    public let id: String
    public let content: String?          // partition content hint (e.g. Apple_APFS)
    public let volumeName: String?       // user-visible volume name
    public let fileSystem: String?       // APFS / HFS+ / FAT32 / exFAT / …
    public let size: Int64?              // bytes
    public let mountPoint: String?
    /// True for Apple-internal APFS volumes (iSCPreboot, xarts, Hardware,
    /// Update…) that exist but aren't meaningful to a user browsing their disks.
    public let isOSInternal: Bool

    public var bsdName: String { id }
    public var isMounted: Bool { mountPoint?.isEmpty == false }

    public init(
        id: String,
        content: String? = nil,
        volumeName: String? = nil,
        fileSystem: String? = nil,
        size: Int64? = nil,
        mountPoint: String? = nil,
        isOSInternal: Bool = false
    ) {
        self.id = id
        self.content = content
        self.volumeName = volumeName
        self.fileSystem = fileSystem
        self.size = size
        self.mountPoint = mountPoint
        self.isOSInternal = isOSInternal
    }
}

/// A physical disk (whole disk, e.g. `disk0`) with its partitions.
public struct Disk: Identifiable, Sendable, Codable, Equatable, Hashable {
    /// BSD identifier of the whole disk, e.g. `disk0`.
    public let id: String
    public let model: String?
    public let size: Int64?
    public let isInternal: Bool
    public let isRemovable: Bool
    /// Reported by `diskutil` as the boot/system disk — never a destructive target.
    public let isSystemDisk: Bool
    public let partitions: [Partition]
    /// Drives erase-strategy selection (spec §2 decision #3): multi-pass wipes
    /// are meaningless (and harmful) on SSD/NVMe — see `EraseService`.
    public let mediaKind: MediaKind
    /// True for a synthesized APFS container whole-disk (e.g. Apple Silicon's
    /// ISC/Recovery/main containers, `disk1`/`disk2`/`disk3` alongside the real
    /// `disk0`) — it has its own BSD whole-disk identifier but is backed by the
    /// SAME physical bytes as its `APFSPhysicalStores` parent, not additional
    /// storage. Callers summing capacity across disks must exclude these to
    /// avoid double-counting the same physical disk.
    public let isVirtual: Bool

    public var bsdName: String { id }
    public var devicePath: String { "/dev/\(id)" }
    /// The raw device is faster for whole-disk imaging (`/dev/rdiskN`).
    public var rawDevicePath: String { "/dev/r\(id)" }

    public init(
        id: String,
        model: String? = nil,
        size: Int64? = nil,
        isInternal: Bool = false,
        isRemovable: Bool = false,
        isSystemDisk: Bool = false,
        partitions: [Partition] = [],
        mediaKind: MediaKind = .unknown,
        isVirtual: Bool = false
    ) {
        self.id = id
        self.model = model
        self.size = size
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.isSystemDisk = isSystemDisk
        self.partitions = partitions
        self.mediaKind = mediaKind
        self.isVirtual = isVirtual
    }
}
