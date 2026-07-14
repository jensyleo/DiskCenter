// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct CompressionServiceTests {
    @Test func noneIsAlwaysAvailable() {
        #expect(CompressionService().isAvailable(.none))
        #expect(CompressionService().path(for: .none) == nil)
    }

    @Test func gzipIsAvailableOnStockMacOS() {
        // /usr/bin/gzip ships with macOS — this should never be missing.
        #expect(CompressionService().isAvailable(.gzip))
        #expect(CompressionService().path(for: .gzip) == "/usr/bin/gzip")
    }

    @Test func createsGzipCompressedImageThatDecompressesToOriginalContent() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".gz")
        let decompressedURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
            try? FileManager.default.removeItem(at: decompressedURL)
        }
        let payload = Data((0..<500_000).map { UInt8($0 % 256) })
        try payload.write(to: sourceURL)

        let result = try await ImageService().createImage(
            sourceDevicePath: sourceURL.path,
            destination: destURL,
            compression: .gzip,
            progress: { _ in }
        )

        #expect(result.bytesWritten > 0)
        // Compressed output must actually be smaller than the (repetitive,
        // highly compressible) source — proves it went through gzip, not a
        // plain copy.
        #expect(result.bytesWritten < Int64(payload.count))

        // Decompress with the real gzip binary and confirm round-trip fidelity.
        let gunzip = Process()
        gunzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gunzip.arguments = ["-d", "-c", destURL.path]
        let outPipe = Pipe()
        gunzip.standardOutput = outPipe
        try gunzip.run()
        let decompressedData = outPipe.fileHandleForReading.readDataToEndOfFile()
        gunzip.waitUntilExit()

        #expect(decompressedData == payload)
    }

    @Test func commandPreviewShowsPipeline() {
        let preview = ImageService().commandPreview(
            sourceDevicePath: "/dev/rdisk4",
            destination: URL(fileURLWithPath: "/tmp/out.img.gz"),
            compression: .gzip
        )
        #expect(preview.contains("dd if=/dev/rdisk4"))
        #expect(preview.contains("| gzip -c >"))
    }

    @Test func requestingUnavailableCompressorThrows() async throws {
        // zstd is very unlikely to be installed in a CI/dev sandbox; if it
        // somehow IS installed, this test would need a genuinely-missing
        // tool instead — using a fake CompressionKind isn't possible (it's a
        // fixed enum), so this documents the expected behavior via zstd's
        // common absence rather than guaranteeing it in every environment.
        let compressionService = CompressionService()
        guard !compressionService.isAvailable(.zstd) else { return }
        await #expect(throws: ImageServiceError.self) {
            _ = try await ImageService().createImage(
                sourceDevicePath: "/dev/null",
                destination: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                compression: .zstd,
                progress: { _ in }
            )
        }
    }
}
