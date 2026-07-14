// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public struct CloneResult: Sendable, Equatable {
    public let bytesWritten: Int64
}

public enum CloneServiceError: Error, Sendable {
    case ddFailed(String)
}

/// Disk-to-disk cloning and image restoration (spec §4.5/§4.6). Unlike
/// `ImageService` (source is read-only, destination is always a brand-new
/// file), both sides here can be existing disks — callers MUST run
/// `ValidationService`'s destructive checklist before calling in, this
/// service performs no validation itself, only the copy.
public struct CloneService: Sendable {
    private let ddService: DDService

    public init(ddService: DDService = DDService()) {
        self.ddService = ddService
    }

    public func commandPreview(sourcePath: String, destinationPath: String) -> String {
        ddService.commandPreview(DDRequest(inputPath: sourcePath, outputPath: destinationPath))
    }

    /// Disk→disk, partition→partition, or image→disk (restore) — `dd` doesn't
    /// distinguish, the caller supplies the right device/file paths on each side.
    public func clone(
        sourcePath: String,
        destinationPath: String,
        token: ProcessCancellationToken = ProcessCancellationToken(),
        progress: @escaping @Sendable (DDProgress) -> Void
    ) async throws -> CloneResult {
        let request = DDRequest(inputPath: sourcePath, outputPath: destinationPath)
        let result = try await ddService.run(request, token: token, progress: progress)
        guard result.succeeded else {
            throw CloneServiceError.ddFailed(result.errorOutput)
        }
        return CloneResult(bytesWritten: result.bytesTransferred)
    }
}
