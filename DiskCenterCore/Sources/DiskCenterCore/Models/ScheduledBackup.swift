// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A recurring GPT-backup schedule (spec §4: task scheduling for recurring
/// backups). Scope is intentionally limited to GPT backups —
/// small, fast, safe to run unattended — not full disk imaging, which is
/// large/slow and better left to an explicit user action.
///
/// **Known limitation**: schedules only run while DiskCenter itself is open
/// (an in-app timer checks `isDue`) — there is no `launchd` agent yet, so a
/// schedule does nothing if the app isn't running at the due time. Real
/// background scheduling is future work (Phase 5+).
public struct ScheduledBackup: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let diskID: String
    public let diskLabel: String
    public let destinationFolder: URL
    public let intervalHours: Int
    public var lastRunDate: Date?

    public init(
        id: UUID = UUID(),
        diskID: String,
        diskLabel: String,
        destinationFolder: URL,
        intervalHours: Int,
        lastRunDate: Date? = nil
    ) {
        self.id = id
        self.diskID = diskID
        self.diskLabel = diskLabel
        self.destinationFolder = destinationFolder
        self.intervalHours = intervalHours
        self.lastRunDate = lastRunDate
    }

    /// Whether this schedule should run now, given `now`. Never run before
    /// (`lastRunDate == nil`) counts as due immediately.
    public func isDue(now: Date) -> Bool {
        guard let lastRunDate else { return true }
        let elapsedHours = now.timeIntervalSince(lastRunDate) / 3600
        return elapsedHours >= Double(intervalHours)
    }
}
