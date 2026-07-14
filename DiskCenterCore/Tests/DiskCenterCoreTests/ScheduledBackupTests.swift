// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct ScheduledBackupTests {
    @Test func neverRunIsAlwaysDue() {
        let schedule = ScheduledBackup(
            diskID: "disk4", diskLabel: "Backup Drive",
            destinationFolder: URL(fileURLWithPath: "/tmp"), intervalHours: 24
        )
        #expect(schedule.isDue(now: Date()))
    }

    @Test func notDueBeforeIntervalElapses() {
        let now = Date()
        let schedule = ScheduledBackup(
            diskID: "disk4", diskLabel: "Backup Drive",
            destinationFolder: URL(fileURLWithPath: "/tmp"), intervalHours: 24,
            lastRunDate: now.addingTimeInterval(-3600) // 1 hour ago
        )
        #expect(!schedule.isDue(now: now))
    }

    @Test func dueAfterIntervalElapses() {
        let now = Date()
        let schedule = ScheduledBackup(
            diskID: "disk4", diskLabel: "Backup Drive",
            destinationFolder: URL(fileURLWithPath: "/tmp"), intervalHours: 24,
            lastRunDate: now.addingTimeInterval(-25 * 3600) // 25 hours ago
        )
        #expect(schedule.isDue(now: now))
    }
}

@Suite struct ScheduledBackupStoreTests {
    private func makeStore() -> ScheduledBackupStore {
        ScheduledBackupStore(suiteName: "DiskCenterTests.\(UUID().uuidString)")
    }

    @Test func addAndFetchRoundTrips() {
        let store = makeStore()
        let schedule = ScheduledBackup(
            diskID: "disk4", diskLabel: "Backup Drive",
            destinationFolder: URL(fileURLWithPath: "/tmp"), intervalHours: 24
        )
        store.add(schedule)
        #expect(store.fetchAll() == [schedule])
    }

    @Test func removeDeletesByID() {
        let store = makeStore()
        let schedule = ScheduledBackup(
            diskID: "disk4", diskLabel: "Backup Drive",
            destinationFolder: URL(fileURLWithPath: "/tmp"), intervalHours: 24
        )
        store.add(schedule)
        store.remove(id: schedule.id)
        #expect(store.fetchAll().isEmpty)
    }

    @Test func markRunUpdatesLastRunDate() {
        let store = makeStore()
        let schedule = ScheduledBackup(
            diskID: "disk4", diskLabel: "Backup Drive",
            destinationFolder: URL(fileURLWithPath: "/tmp"), intervalHours: 24
        )
        store.add(schedule)
        let runDate = Date()
        store.markRun(id: schedule.id, date: runDate)

        let updated = store.fetchAll().first
        #expect(updated?.lastRunDate == runDate)
    }

    @Test func dueSchedulesFiltersCorrectly() {
        let store = makeStore()
        let now = Date()
        let due = ScheduledBackup(
            diskID: "disk4", diskLabel: "Due", destinationFolder: URL(fileURLWithPath: "/tmp"),
            intervalHours: 24, lastRunDate: now.addingTimeInterval(-25 * 3600)
        )
        let notDue = ScheduledBackup(
            diskID: "disk5", diskLabel: "Not Due", destinationFolder: URL(fileURLWithPath: "/tmp"),
            intervalHours: 24, lastRunDate: now.addingTimeInterval(-3600)
        )
        store.add(due)
        store.add(notDue)

        let result = store.dueSchedules(now: now)
        #expect(result.count == 1)
        #expect(result.first?.diskLabel == "Due")
    }
}
