// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public struct ImageCreationResult: Sendable, Equatable {
    public let destination: URL
    public let bytesWritten: Int64
    public let sha256: String
}

public enum ImageServiceError: Error, Sendable {
    case ddFailed(String)
    case compressorNotAvailable(CompressionKind)
    case cancelled
}

/// Creates a raw disk/partition image (spec §4.4) and checksums the result.
/// Read-only against the source; the source device is never written to.
public struct ImageService: Sendable {
    private let ddService: DDService
    private let checksumService: ChecksumService
    private let compressionService: CompressionService

    public init(
        ddService: DDService = DDService(),
        checksumService: ChecksumService = ChecksumService(),
        compressionService: CompressionService = CompressionService()
    ) {
        self.ddService = ddService
        self.checksumService = checksumService
        self.compressionService = compressionService
    }

    /// The exact command that will run — for the required simulation step
    /// (show the command before executing). Compressed images pipe `dd`
    /// through the compressor rather than writing directly.
    public func commandPreview(sourceDevicePath: String, destination: URL, compression: CompressionKind = .none) -> String {
        guard compression != .none else {
            return ddService.commandPreview(DDRequest(inputPath: sourceDevicePath, outputPath: destination.path))
        }
        let prefix = getuid() == 0 ? "" : "sudo "
        return "\(prefix)dd if=\(sourceDevicePath) bs=4m | \(compression.rawValue) -c > \(destination.path)"
    }

    /// Copies `sourceDevicePath` (e.g. `/dev/rdisk4` or `/dev/rdisk4s2`) to
    /// `destination`, then computes its SHA256. `progress` is invoked from a
    /// background queue as data moves.
    public func createImage(
        sourceDevicePath: String,
        destination: URL,
        compression: CompressionKind = .none,
        token: ProcessCancellationToken = ProcessCancellationToken(),
        progress: @escaping @Sendable (DDProgress) -> Void
    ) async throws -> ImageCreationResult {
        if compression == .none {
            let request = DDRequest(inputPath: sourceDevicePath, outputPath: destination.path)
            let result = try await ddService.run(request, token: token, progress: progress)
            guard result.succeeded else {
                throw ImageServiceError.ddFailed(result.errorOutput)
            }
            let checksum = try checksumService.sha256(of: destination)
            return ImageCreationResult(destination: destination, bytesWritten: result.bytesTransferred, sha256: checksum)
        }

        guard let compressorPath = compressionService.path(for: compression) else {
            throw ImageServiceError.compressorNotAvailable(compression)
        }
        return try await createCompressedImage(
            sourceDevicePath: sourceDevicePath,
            destination: destination,
            compressorPath: compressorPath,
            token: token,
            progress: progress
        )
    }

    /// Pipes `dd`'s output through the compressor into `destination`. Unlike
    /// the uncompressed path, progress isn't parsed from `dd`'s
    /// `status=progress` (that would require wiring a third pipe through the
    /// compressor) — instead it's a simple poll of the growing destination
    /// file's size every 500ms, which is accurate enough for a progress bar.
    private func createCompressedImage(
        sourceDevicePath: String,
        destination: URL,
        compressorPath: String,
        token: ProcessCancellationToken,
        progress: @escaping @Sendable (DDProgress) -> Void
    ) async throws -> ImageCreationResult {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw ImageServiceError.ddFailed("Could not create destination file at \(destination.path)")
        }
        guard let outHandle = FileHandle(forWritingAtPath: destination.path) else {
            throw ImageServiceError.ddFailed("Could not open destination for writing")
        }

        let ddProcess = Process()
        ddProcess.executableURL = URL(fileURLWithPath: "/bin/dd")
        ddProcess.arguments = ["if=\(sourceDevicePath)", "bs=4m"]
        let pipe = Pipe()
        ddProcess.standardOutput = pipe
        ddProcess.standardError = Pipe()

        let compressor = Process()
        compressor.executableURL = URL(fileURLWithPath: compressorPath)
        compressor.arguments = ["-c"]
        compressor.standardInput = pipe
        compressor.standardOutput = outHandle
        compressor.standardError = Pipe()

        let pollTask = Task.detached { () -> Void in
            let start = DispatchTime.now()
            while !Task.isCancelled {
                if let size = try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64 {
                    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
                    progress(DDProgress(bytesTransferred: size, secondsElapsed: elapsed, bytesPerSecond: nil))
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { pollTask.cancel() }

        do {
            try ddProcess.run()
        } catch {
            try? outHandle.close()
            throw ImageServiceError.ddFailed("Could not launch dd: \(error.localizedDescription)")
        }
        do {
            try compressor.run()
            token.attach(ddProcess)
        } catch {
            // dd already launched and is writing to `pipe` — if the
            // compressor never starts reading it, dd blocks forever on a
            // full, unread pipe buffer and leaks as an orphaned process.
            // Terminate it before surfacing the error.
            ddProcess.terminate()
            try? outHandle.close()
            throw ImageServiceError.ddFailed("Could not launch \(compressorPath): \(error.localizedDescription)")
        }

        // Orchestrating two dependent processes (dd's stdout feeds the
        // compressor's stdin) is simplest as a direct blocking wait here —
        // this method already only runs off the main actor (called from a
        // background `Task` by the view model), so it doesn't block UI.
        ddProcess.waitUntilExit()
        compressor.waitUntilExit()
        try? outHandle.close()

        guard ddProcess.terminationStatus == 0, compressor.terminationStatus == 0 else {
            throw ImageServiceError.ddFailed(
                "dd exited \(ddProcess.terminationStatus), \(compressor.executableURL?.lastPathComponent ?? "compressor") exited \(compressor.terminationStatus)"
            )
        }

        let bytesWritten: Int64 = (try? FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int64 ?? 0) ?? 0
        let checksum = try checksumService.sha256(of: destination)
        return ImageCreationResult(destination: destination, bytesWritten: bytesWritten, sha256: checksum)
    }
}
