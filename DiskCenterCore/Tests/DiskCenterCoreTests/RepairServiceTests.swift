// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct RepairServiceTests {
    @Test func passIsDeterminedByExitCodeNotOutputText() async throws {
        // /usr/bin/true ignores its arguments and exits 0 — stands in for a
        // successful `diskutil verifyDisk` without touching a real disk.
        let result = try await RepairService(diskutilPath: "/usr/bin/true").verifyDisk("disk4")
        #expect(result.passed)
    }

    @Test func failureIsDeterminedByExitCodeNotOutputText() async throws {
        let result = try await RepairService(diskutilPath: "/usr/bin/false").verifyDisk("disk4")
        #expect(!result.passed)
    }

    @Test func logCapturesRawOutputVerbatim() async throws {
        // /bin/echo writes its arguments to stdout — verifies output is
        // captured as-is (never parsed for structured fields).
        let result = try await RepairService(diskutilPath: "/bin/echo").verifyDisk("hello world")
        #expect(result.log.contains("verifyDisk"))
        #expect(result.log.contains("hello world"))
    }

    @Test func commandPreviewShowsExactCommand() {
        let preview = RepairService().commandPreview(diskID: "disk4")
        #expect(preview == "diskutil verifyDisk disk4")
    }

    @Test func repairDiskPassIsDeterminedByExitCode() async throws {
        let result = try await RepairService(diskutilPath: "/usr/bin/true").repairDisk("disk4")
        #expect(result.passed)
    }

    @Test func repairDiskFailureIsDeterminedByExitCode() async throws {
        let result = try await RepairService(diskutilPath: "/usr/bin/false").repairDisk("disk4")
        #expect(!result.passed)
    }

    @Test func repairCommandPreviewShowsExactCommand() {
        let preview = RepairService().repairCommandPreview(diskID: "disk4")
        #expect(preview.contains("repairDisk disk4"))
    }
}
