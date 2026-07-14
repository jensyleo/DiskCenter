// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import Foundation
import Observation

/// Manages recurring GPT-backup schedules (spec §4/§8) and, while the app is
/// open, runs any that become due. See `ScheduledBackup`'s doc comment for
/// the "only runs while DiskCenter is open" limitation.
@MainActor
@Observable
final class ScheduledBackupsViewModel {
    private(set) var schedules: [ScheduledBackup] = []
    private let store = ScheduledBackupStore()
    private let gptBackupService = GPTBackupService()
    private let logger = LoggerService()

    init() {
        refresh()
    }

    func refresh() {
        schedules = store.fetchAll()
    }

    func add(diskID: String, diskLabel: String, destinationFolder: URL, intervalHours: Int) {
        store.add(ScheduledBackup(
            diskID: diskID, diskLabel: diskLabel,
            destinationFolder: destinationFolder, intervalHours: intervalHours
        ))
        refresh()
    }

    func remove(id: UUID) {
        store.remove(id: id)
        refresh()
    }

    /// Runs every due schedule's GPT backup (fast, safe to run unattended)
    /// against the matching disk in `currentDisks`, if still present.
    func runDueSchedules(currentDisks: [Disk]) async {
        let due = store.dueSchedules(now: Date())
        guard !due.isEmpty else { return }

        for schedule in due {
            guard let disk = currentDisks.first(where: { $0.id == schedule.diskID }) else { continue }
            let destination = schedule.destinationFolder
                .appendingPathComponent("\(disk.id)-scheduled-\(Self.filenameSafeTimestamp(Date())).bin")
            do {
                try await DiskOperationLock.shared.acquire(diskID: disk.id, operation: "Scheduled Backup")
                defer { Task { await DiskOperationLock.shared.release(diskID: disk.id) } }
                _ = try await gptBackupService.backup(rawDevicePath: disk.rawDevicePath, destination: destination)
                store.markRun(id: schedule.id, date: Date())
                logger.log("Scheduled GPT backup of \(disk.id) succeeded: \(destination.path)")
            } catch {
                logger.log("Scheduled GPT backup of \(disk.id) failed: \(error)")
            }
        }
        refresh()
    }

    /// `ISO8601DateFormatter` output contains colons (`2026-07-11T15:30:00Z`) —
    /// harmless at the filesystem level, but Finder displays a literal `:` in
    /// a filename as `/`, which reads as a confusing, broken-looking name.
    private static func filenameSafeTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}
