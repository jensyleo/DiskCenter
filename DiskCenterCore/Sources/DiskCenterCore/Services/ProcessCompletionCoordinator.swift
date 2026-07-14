// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Synchronizes the two independent async signals a piped `Process` produces —
/// `terminationHandler` (the process exited) and the pipe's `readabilityHandler`
/// reporting EOF (empty `availableData`, meaning all output has been read) —
/// which can arrive in either order. Mixing a `readabilityHandler` with a
/// manual `readDataToEndOfFile()` call to "catch anything left over" is racy:
/// on a very fast process, `terminationHandler` can fire and read before the
/// handler has been scheduled at all, silently dropping the final output
/// (found while testing a sub-10ms `dd` copy — the final "bytes transferred"
/// summary line went missing). Waiting for BOTH signals before resuming is the
/// only reliable order.
final class ProcessCompletionCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var exitCode: Int32?
    private var pipeClosed = false
    private var completion: ((Int32) -> Void)?

    func setExitCode(_ code: Int32) {
        lock.lock(); defer { lock.unlock() }
        exitCode = code
        maybeComplete()
    }

    func setPipeClosed() {
        lock.lock(); defer { lock.unlock() }
        pipeClosed = true
        maybeComplete()
    }

    func onComplete(_ block: @escaping (Int32) -> Void) {
        lock.lock(); defer { lock.unlock() }
        completion = block
        maybeComplete()
    }

    /// Caller must hold `lock`.
    private func maybeComplete() {
        guard let code = exitCode, pipeClosed, let block = completion else { return }
        completion = nil
        block(code)
    }
}
