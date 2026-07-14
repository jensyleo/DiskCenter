// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct BenchmarkServiceTests {
    @Test func runProducesPositiveMetricsAndCleansUpTestFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let before = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)

        let result = try BenchmarkService().run(mountPoint: tempDir.path)

        #expect(result.sequentialWriteMBPerSecond > 0)
        #expect(result.sequentialReadMBPerSecond > 0)
        #expect(result.randomReadIOPS > 0)

        let after = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(after.filter { $0.hasPrefix(".diskcenter-benchmark-") }.count
            == before.filter { $0.hasPrefix(".diskcenter-benchmark-") }.count)
    }
}

extension BenchmarkServiceTests {
    @Test func fallsBackToHomeDirectoryWhenMountPointRootIsNotWritable() throws {
        // "/System/Volumes/Data" is a real macOS path whose ROOT isn't
        // writable by a normal user (only subfolders like Users/<home> are) —
        // confirms the fallback kicks in instead of throwing.
        let url = try BenchmarkService.testFileURL(preferredMountPoint: "/System/Volumes/Data")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.deletingLastPathComponent().path == NSHomeDirectory())
    }

    @Test func usesPreferredMountPointWhenWritable() throws {
        let url = try BenchmarkService.testFileURL(preferredMountPoint: FileManager.default.temporaryDirectory.path)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(url.deletingLastPathComponent().path == FileManager.default.temporaryDirectory.path)
    }
}
