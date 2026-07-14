// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One remembered recent operation (spec §7: recently used disks, images,
/// backups, and clones).
public struct HistoryEntry: Sendable, Codable, Identifiable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case diskUsed = "Disk"
        case imageCreated = "Image"
        case gptBackup = "GPT Backup"
        case clone = "Clone"
        case restore = "Restore"
    }

    public let id: UUID
    public let kind: Kind
    public let label: String
    public let path: String?
    public let date: Date

    public init(id: UUID = UUID(), kind: Kind, label: String, path: String? = nil, date: Date) {
        self.id = id
        self.kind = kind
        self.label = label
        self.path = path
        self.date = date
    }
}
