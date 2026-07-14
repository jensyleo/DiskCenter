// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct CloneServiceTests {
    @Test func clonesARealFileEndToEnd() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        let payload = Data((0..<300_000).map { UInt8($0 % 256) })
        try payload.write(to: sourceURL)

        let result = try await CloneService().clone(
            sourcePath: sourceURL.path,
            destinationPath: destURL.path,
            progress: { _ in }
        )

        #expect(result.bytesWritten == Int64(payload.count))
        #expect(FileManager.default.contentsEqual(atPath: sourceURL.path, andPath: destURL.path))
    }

    @Test func commandPreviewShowsBothPaths() {
        let preview = CloneService().commandPreview(sourcePath: "/dev/rdisk4", destinationPath: "/dev/rdisk5")
        #expect(preview.contains("/dev/rdisk4"))
        #expect(preview.contains("/dev/rdisk5"))
    }
}
