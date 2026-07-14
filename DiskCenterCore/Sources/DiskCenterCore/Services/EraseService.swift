// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Secure erase with media-aware strategy (spec §2 decision #3, §4.10).
/// Runs its own `Process` (see `DDService`'s doc comment for why: this can
/// take minutes and mustn't hold `ProcessRunner`'s process-wide lock).
public struct EraseService: Sendable {
    public static let defaultDiskutilPath = "/usr/sbin/diskutil"
    private let diskutilPath: String

    public init(diskutilPath: String = EraseService.defaultDiskutilPath) {
        self.diskutilPath = diskutilPath
    }

    /// The only levels safe to offer for a given media type. SSD/NVMe (and
    /// unknown, conservatively) get ONLY the quick zero-fill — never leave
    /// "7-pass"/"Gutmann" as a selectable option for flash media, per the
    /// spec's explicit requirement and Apple's own guidance (see `EraseLevel`).
    public func allowedLevels(for mediaKind: MediaKind) -> [EraseLevel] {
        switch mediaKind {
        case .ssd, .nvme, .unknown:
            return [.quickZeroFill]
        case .hdd, .usb, .thunderbolt, .diskImage:
            return EraseLevel.allCases
        }
    }

    public func commandPreview(diskID: String, level: EraseLevel) -> String {
        let prefix = getuid() == 0 ? "" : "sudo "
        return "\(prefix)diskutil secureErase \(level.rawValue) \(diskID)"
    }

    /// Erases `diskID` (a whole disk) at `level`. Throws
    /// `.levelNotAllowedForMedia` without touching the disk if `level` isn't
    /// in `allowedLevels(for: mediaKind)` — the UI is expected to only ever
    /// offer allowed levels, so hitting this means a caller bypassed it.
    public func erase(
        diskID: String,
        level: EraseLevel,
        mediaKind: MediaKind,
        token: ProcessCancellationToken = ProcessCancellationToken()
    ) async throws -> EraseResult {
        guard allowedLevels(for: mediaKind).contains(level) else {
            throw EraseServiceError.levelNotAllowedForMedia(level: level, mediaKind: mediaKind)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: diskutilPath)
            process.arguments = ["secureErase", "\(level.rawValue)", diskID]

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe

            let collected = LogCollector()
            let coordinator = ProcessCompletionCoordinator()

            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    coordinator.setPipeClosed()
                    return
                }
                collected.append(data)
            }

            process.terminationHandler = { proc in
                coordinator.setExitCode(proc.terminationStatus)
            }

            coordinator.onComplete { exitCode in
                continuation.resume(returning: EraseResult(
                    diskID: diskID,
                    succeeded: exitCode == 0,
                    log: collected.text
                ))
            }

            do {
                try process.run()
                token.attach(process)
            } catch {
                continuation.resume(throwing: EraseServiceError.launchFailed(error.localizedDescription))
            }
        }
    }
}

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.withLock { data.append(chunk) } }
    var text: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
