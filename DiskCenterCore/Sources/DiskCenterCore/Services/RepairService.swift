// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public struct RepairResult: Sendable, Equatable {
    public let passed: Bool
    /// Raw `diskutil` output, shown to the user verbatim for transparency —
    /// never parsed for structured fields (its text format isn't stable).
    /// Pass/fail is decided solely by the exit code.
    public let log: String
}

public enum RepairServiceError: Error, Sendable {
    case launchFailed(String)
}

/// Disk verification (read-only, Phase 2) and repair (Phase 3, §4.9). Runs its
/// own `Process` rather than going through `ProcessRunner`: both verbs can
/// take minutes on a large disk, and `ProcessRunner`'s process-wide lock would
/// freeze every other diskutil call for that whole time.
public struct RepairService: Sendable {
    public static let defaultDiskutilPath = "/usr/sbin/diskutil"
    private let diskutilPath: String

    /// `diskutilPath` is injectable so tests can point at a harmless stand-in
    /// executable instead of running the real `diskutil verifyDisk`/`repairDisk`
    /// (which can take minutes and needs a real disk).
    public init(diskutilPath: String = RepairService.defaultDiskutilPath) {
        self.diskutilPath = diskutilPath
    }

    public func commandPreview(diskID: String) -> String {
        "diskutil verifyDisk \(diskID)"
    }

    public func repairCommandPreview(diskID: String) -> String {
        let prefix = getuid() == 0 ? "" : "sudo "
        return "\(prefix)diskutil repairDisk \(diskID)"
    }

    /// Runs `diskutil verifyDisk <diskID>`. `diskID` may be a whole disk
    /// (`disk4`) or a single volume (`disk4s2`).
    public func verifyDisk(
        _ diskID: String,
        token: ProcessCancellationToken = ProcessCancellationToken()
    ) async throws -> RepairResult {
        try await run(["verifyDisk", diskID], token: token)
    }

    /// Runs `diskutil repairDisk <diskID>` — actively fixes filesystem issues
    /// (unlike `verifyDisk`, this writes to the disk). Callers must run the
    /// same pre-flight checks as any other destructive-adjacent operation
    /// (not the system disk while booted from it in a way that matters, disk
    /// not busy with another operation via `DiskOperationLock`, etc.).
    public func repairDisk(
        _ diskID: String,
        token: ProcessCancellationToken = ProcessCancellationToken()
    ) async throws -> RepairResult {
        try await run(["repairDisk", diskID], token: token)
    }

    private func run(
        _ arguments: [String],
        token: ProcessCancellationToken
    ) async throws -> RepairResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: diskutilPath)
            process.arguments = arguments

            let outPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = outPipe

            let collected = OutputCollector()
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
                continuation.resume(returning: RepairResult(
                    passed: exitCode == 0,
                    log: collected.text
                ))
            }

            do {
                try process.run()
                token.attach(process)
            } catch {
                continuation.resume(throwing: RepairServiceError.launchFailed(error.localizedDescription))
            }
        }
    }
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
