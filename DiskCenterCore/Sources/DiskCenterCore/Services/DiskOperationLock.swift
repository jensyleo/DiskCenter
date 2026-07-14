// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum DiskOperationLockError: Error, Sendable, Equatable {
    case alreadyInProgress(diskID: String, operation: String)
}

/// Prevents two operations from running concurrently against the same whole
/// disk (spec §6: no other operation may be in progress on the same disk).
/// Shared app-wide, since two independent services (imaging, GPT backup,
/// repair, and future erase/clone) must all respect the same lock.
public actor DiskOperationLock {
    public static let shared = DiskOperationLock()

    /// diskID → human-readable description of the operation holding the lock.
    private var inProgress: [String: String] = [:]

    public init() {}

    /// Claims `diskID` for `operation`, throwing immediately (never blocking)
    /// if another operation already holds it. Always pair with `release`.
    ///
    /// Exposed as explicit acquire/release rather than a `withLock { ... }`
    /// higher-order function: a closure crossing into this actor from a
    /// `@MainActor` view model must be `Sendable`, and a closure literal
    /// defined inside a MainActor method (even one that only captures
    /// Sendable values) is inferred MainActor-isolated by default — fighting
    /// that inference wasn't worth it for what is otherwise a two-line lock.
    public func acquire(diskID: String, operation: String) throws {
        if let existing = inProgress[diskID] {
            throw DiskOperationLockError.alreadyInProgress(diskID: diskID, operation: existing)
        }
        inProgress[diskID] = operation
    }

    public func release(diskID: String) {
        inProgress[diskID] = nil
    }

    public func isBusy(_ diskID: String) -> Bool {
        inProgress[diskID] != nil
    }
}
