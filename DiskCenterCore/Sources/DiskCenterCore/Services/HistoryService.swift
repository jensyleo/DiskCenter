// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Persists a capped, most-recent-first list of recent operations (spec §7).
/// Backed by `UserDefaults` — small, structured data, no need for a database.
public struct HistoryService: Sendable {
    private static let key = "DiskCenter.History"
    /// `UserDefaults` itself isn't `Sendable`, so this stores the suite name
    /// (nil = `.standard`) and resolves a fresh instance per call rather than
    /// holding a live reference — keeps the type safely `Sendable`.
    private let suiteName: String?
    private let maxEntries: Int

    /// Use the default initializer for the real app (`.standard`). Tests
    /// should use `init(suiteName:maxEntries:)` with a unique suite name to
    /// stay isolated from real user defaults.
    public init(maxEntries: Int = 20) {
        self.suiteName = nil
        self.maxEntries = maxEntries
    }

    public init(suiteName: String, maxEntries: Int = 20) {
        self.suiteName = suiteName
        self.maxEntries = maxEntries
    }

    private var defaults: UserDefaults {
        suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// Inserts `entry` at the front, trimming to `maxEntries`.
    public func record(_ entry: HistoryEntry) {
        var all = fetchAll()
        all.insert(entry, at: 0)
        if all.count > maxEntries {
            all = Array(all.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(all) {
            defaults.set(data, forKey: Self.key)
        }
    }

    public func fetchAll() -> [HistoryEntry] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
    }

    public func fetch(kind: HistoryEntry.Kind) -> [HistoryEntry] {
        fetchAll().filter { $0.kind == kind }
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
