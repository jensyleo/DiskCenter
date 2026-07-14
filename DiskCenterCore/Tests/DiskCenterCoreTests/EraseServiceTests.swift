// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct EraseServiceTests {
    @Test func ssdOnlyAllowsQuickZeroFill() {
        let service = EraseService()
        #expect(service.allowedLevels(for: .ssd) == [.quickZeroFill])
        #expect(service.allowedLevels(for: .nvme) == [.quickZeroFill])
    }

    @Test func unknownMediaConservativelyAllowsOnlyQuickZeroFill() {
        let service = EraseService()
        #expect(service.allowedLevels(for: .unknown) == [.quickZeroFill])
    }

    @Test func hddAllowsAllLevels() {
        let service = EraseService()
        #expect(service.allowedLevels(for: .hdd) == EraseLevel.allCases)
    }

    @Test func usbAndThunderboltAllowAllLevels() {
        // A USB/Thunderbolt HDD enclosure is still a spinning disk; the
        // interconnect isn't what determines whether multi-pass makes sense.
        let service = EraseService()
        #expect(service.allowedLevels(for: .usb) == EraseLevel.allCases)
        #expect(service.allowedLevels(for: .thunderbolt) == EraseLevel.allCases)
    }

    @Test func erasingWithDisallowedLevelForSSDThrowsWithoutRunningAnything() async throws {
        // Defense in depth: even if a caller bypasses the UI (which should
        // only ever offer allowed levels), the service itself refuses.
        let service = EraseService(diskutilPath: "/usr/bin/true")
        await #expect(throws: EraseServiceError.self) {
            _ = try await service.erase(diskID: "disk9", level: .sevenPass, mediaKind: .ssd)
        }
    }

    @Test func commandPreviewShowsLevelAndDisk() {
        let preview = EraseService().commandPreview(diskID: "disk4", level: .quickZeroFill)
        #expect(preview.contains("secureErase"))
        #expect(preview.contains("0"))
        #expect(preview.contains("disk4"))
    }

    @Test func eraseSucceedsWithAllowedLevelUsingStandInExecutable() async throws {
        // /usr/bin/true stands in for a successful `diskutil secureErase`
        // without touching any real disk.
        let service = EraseService(diskutilPath: "/usr/bin/true")
        let result = try await service.erase(diskID: "disk9", level: .quickZeroFill, mediaKind: .ssd)
        #expect(result.succeeded)
        #expect(result.diskID == "disk9")
    }

    @Test func eraseFailureIsDeterminedByExitCode() async throws {
        let service = EraseService(diskutilPath: "/usr/bin/false")
        let result = try await service.erase(diskID: "disk9", level: .quickZeroFill, mediaKind: .ssd)
        #expect(!result.succeeded)
    }
}
