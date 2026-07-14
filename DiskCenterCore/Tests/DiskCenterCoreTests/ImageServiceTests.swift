// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CryptoKit
import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct ImageServiceTests {
    /// Uses a regular file as the "source device" — DDService/ImageService
    /// don't care whether `if=` is a device node or a file, so this exercises
    /// the full copy + checksum pipeline without touching real hardware.
    @Test func createsImageAndComputesMatchingChecksum() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        let payload = Data((0..<500_000).map { _ in UInt8.random(in: 0...255) })
        try payload.write(to: sourceURL)
        let expectedHash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

        let result = try await ImageService().createImage(
            sourceDevicePath: sourceURL.path,
            destination: destURL,
            progress: { _ in }
        )

        #expect(result.sha256 == expectedHash)
        #expect(FileManager.default.contentsEqual(atPath: sourceURL.path, andPath: destURL.path))
    }

    @Test func commandPreviewShowsSourceAndDestination() {
        let preview = ImageService().commandPreview(sourceDevicePath: "/dev/rdisk4", destination: URL(fileURLWithPath: "/tmp/out.img"))
        #expect(preview.contains("/dev/rdisk4"))
        #expect(preview.contains("/tmp/out.img"))
    }
}
