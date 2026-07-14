// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct HistoryServiceTests {
    private func makeService() -> HistoryService {
        HistoryService(suiteName: "DiskCenterTests.\(UUID().uuidString)", maxEntries: 3)
    }

    @Test func recordsMostRecentFirst() {
        let service = makeService()
        service.record(HistoryEntry(kind: .diskUsed, label: "disk4", date: Date(timeIntervalSince1970: 1)))
        service.record(HistoryEntry(kind: .imageCreated, label: "backup.img", date: Date(timeIntervalSince1970: 2)))

        let all = service.fetchAll()
        #expect(all.count == 2)
        #expect(all[0].label == "backup.img")
        #expect(all[1].label == "disk4")
    }

    @Test func trimsToMaxEntries() {
        let service = makeService() // maxEntries: 3
        for i in 0..<5 {
            service.record(HistoryEntry(kind: .diskUsed, label: "disk\(i)", date: Date(timeIntervalSince1970: Double(i))))
        }
        let all = service.fetchAll()
        #expect(all.count == 3)
        #expect(all.map(\.label) == ["disk4", "disk3", "disk2"])
    }

    @Test func fetchFiltersbyKind() {
        let service = makeService()
        service.record(HistoryEntry(kind: .diskUsed, label: "disk4", date: Date()))
        service.record(HistoryEntry(kind: .imageCreated, label: "backup.img", date: Date()))

        let images = service.fetch(kind: .imageCreated)
        #expect(images.count == 1)
        #expect(images.first?.label == "backup.img")
    }

    @Test func clearRemovesEverything() {
        let service = makeService()
        service.record(HistoryEntry(kind: .diskUsed, label: "disk4", date: Date()))
        service.clear()
        #expect(service.fetchAll().isEmpty)
    }
}
