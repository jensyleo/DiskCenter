// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Persists `ScheduledBackup` entries in `UserDefaults`. See
/// `ScheduledBackup`'s doc comment for the "only runs while the app is open"
/// limitation — this store just tracks the schedules, it doesn't run them.
public struct ScheduledBackupStore: Sendable {
    private static let key = "DiskCenter.ScheduledBackups"
    private let suiteName: String?

    public init() {
        self.suiteName = nil
    }

    public init(suiteName: String) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func fetchAll() -> [ScheduledBackup] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([ScheduledBackup].self, from: data)) ?? []
    }

    public func save(_ schedules: [ScheduledBackup]) {
        if let data = try? JSONEncoder().encode(schedules) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func add(_ schedule: ScheduledBackup) {
        var all = fetchAll()
        all.append(schedule)
        save(all)
    }

    public func remove(id: UUID) {
        save(fetchAll().filter { $0.id != id })
    }

    /// Updates `lastRunDate` for the schedule with `id`, if present.
    public func markRun(id: UUID, date: Date) {
        var all = fetchAll()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].lastRunDate = date
        save(all)
    }

    /// Every schedule that `isDue(now:)`.
    public func dueSchedules(now: Date) -> [ScheduledBackup] {
        fetchAll().filter { $0.isDue(now: now) }
    }
}
