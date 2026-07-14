// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public struct GPTBackupResult: Sendable, Equatable {
    public let destination: URL
    public let bytesWritten: Int64
}

public enum GPTBackupServiceError: Error, Sendable {
    case ddFailed(String)
}

/// Saves the leading sectors of a whole disk (GPT primary header + partition
/// entries + protective MBR) to a file, for later restoration (spec §4.8).
/// Read-only against the source disk.
public struct GPTBackupService: Sendable {
    /// 1 MiB comfortably covers the protective MBR (sector 0), the GPT header
    /// (sector 1) and a generous partition-entry array (sectors 2+) — GPT
    /// backup tools conventionally back up more than the strict minimum so a
    /// restore doesn't depend on exact sizing.
    public static let defaultBackupSizeBytes: Int64 = 1024 * 1024

    private let ddService: DDService

    public init(ddService: DDService = DDService()) {
        self.ddService = ddService
    }

    public func commandPreview(rawDevicePath: String, destination: URL) -> String {
        ddService.commandPreview(
            DDRequest(inputPath: rawDevicePath, outputPath: destination.path, limitBytes: Self.defaultBackupSizeBytes)
        )
    }

    /// Backs up the first `Self.defaultBackupSizeBytes` of `rawDevicePath`
    /// (e.g. `/dev/rdisk4`) to `destination`.
    public func backup(
        rawDevicePath: String,
        destination: URL,
        token: ProcessCancellationToken = ProcessCancellationToken(),
        progress: @escaping @Sendable (DDProgress) -> Void = { _ in }
    ) async throws -> GPTBackupResult {
        let request = DDRequest(
            inputPath: rawDevicePath,
            outputPath: destination.path,
            limitBytes: Self.defaultBackupSizeBytes
        )
        let result = try await ddService.run(request, token: token, progress: progress)
        guard result.succeeded else {
            throw GPTBackupServiceError.ddFailed(result.errorOutput)
        }
        return GPTBackupResult(destination: destination, bytesWritten: result.bytesTransferred)
    }
}
