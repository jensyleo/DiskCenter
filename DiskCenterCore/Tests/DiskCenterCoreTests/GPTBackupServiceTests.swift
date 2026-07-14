// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct GPTBackupServiceTests {
    @Test func backsUpOnlyTheLeadingBytesNotTheWholeSource() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        // Bigger than the default 1 MiB backup window.
        let payload = Data((0..<2_000_000).map { UInt8($0 % 256) })
        try payload.write(to: sourceURL)

        let result = try await GPTBackupService().backup(rawDevicePath: sourceURL.path, destination: destURL)

        #expect(result.bytesWritten == GPTBackupService.defaultBackupSizeBytes)
        let backedUp = try Data(contentsOf: destURL)
        #expect(backedUp.count == Int(GPTBackupService.defaultBackupSizeBytes))
        #expect(backedUp == payload.prefix(Int(GPTBackupService.defaultBackupSizeBytes)))
    }

    @Test func commandPreviewShowsSectorCount() {
        let preview = GPTBackupService().commandPreview(
            rawDevicePath: "/dev/rdisk4",
            destination: URL(fileURLWithPath: "/tmp/gpt-backup.bin")
        )
        #expect(preview.contains("bs=512"))
        #expect(preview.contains("count=2048")) // 1 MiB / 512
    }
}
