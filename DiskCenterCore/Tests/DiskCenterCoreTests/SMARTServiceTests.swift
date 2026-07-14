// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

private let smartctlSampleOutput = """
smartctl 7.4 2023-08-01 r5530 [Darwin 24.0.0 arm64] (Homebrew)
Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org

=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED

ID# ATTRIBUTE_NAME          FLAG     VALUE WORST THRESH TYPE      UPDATED  WHEN_FAILED RAW_VALUE
  5 Reallocated_Sector_Ct   0x0033   100   100   005    Pre-fail  Always       -       0
  9 Power_On_Hours          0x0032   098   098   000    Old_age   Always       -       1234
194 Temperature_Celsius     0x0022   067   041   000    Old_age   Always       -       33 (Min/Max 20/45)
"""

private let smartctlUSBBridgeError = """
smartctl 7.4 2023-08-01 r5530 [Darwin 24.0.0 arm64] (Homebrew)
Copyright (C) 2002-23, Bruce Allen, Christian Franke, www.smartmontools.org

/dev/disk4: Unknown USB bridge
Please specify device type with the -d option.
"""

@Suite struct SMARTServiceTests {
    @Test func parsesTemperatureDespiteTrailingAnnotation() {
        let value = SMARTService.parseAttributeRawValue(named: "Temperature_Celsius", in: smartctlSampleOutput)
        #expect(value == 33)
    }

    @Test func parsesPowerOnHours() {
        let value = SMARTService.parseAttributeRawValue(named: "Power_On_Hours", in: smartctlSampleOutput)
        #expect(value == 1234)
    }

    @Test func parsesReallocatedSectorCount() {
        let value = SMARTService.parseAttributeRawValue(named: "Reallocated_Sector_Ct", in: smartctlSampleOutput)
        #expect(value == 0)
    }

    @Test func missingAttributeReturnsNil() {
        let value = SMARTService.parseAttributeRawValue(named: "Nonexistent_Attribute", in: smartctlSampleOutput)
        #expect(value == nil)
    }

    @Test func recognizesUSBBridgeLimitation() {
        let reason = SMARTService.bridgeUnavailableReason(from: smartctlUSBBridgeError)
        #expect(reason?.contains("USB bridge") == true)
    }

    @Test func smartStatusMapsKnownDiskutilValues() {
        #expect(SMARTStatus(diskutilValue: "Verified") == .verified)
        #expect(SMARTStatus(diskutilValue: "Failing") == .failing)
        #expect(SMARTStatus(diskutilValue: "Not Supported") == .notSupported)
        #expect(SMARTStatus(diskutilValue: nil) == .notSupported)
        #expect(SMARTStatus(diskutilValue: "Something Else") == .unknown)
    }

    @Test func basicStatusReadsFromDiskutilPlist() throws {
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["SMARTStatus": "Verified"], format: .xml, options: 0
        )
        let runner = ProcessRunner.stub { _, _ in
            ProcessResult(exitCode: 0, standardOutput: plistData, standardError: Data())
        }
        let status = try SMARTService(runner: runner).basicStatus(for: "disk0")
        #expect(status == .verified)
    }

    @Test func infoFallsBackToBasicWhenSmartctlMissing() throws {
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["SMARTStatus": "Verified"], format: .xml, options: 0
        )
        let runner = ProcessRunner.stub { _, _ in
            ProcessResult(exitCode: 0, standardOutput: plistData, standardError: Data())
        }
        let info = try SMARTService(runner: runner).info(for: "disk0", smartctlPath: nil)
        #expect(info.status == .verified)
        #expect(!info.smartctlAvailable)
        #expect(!info.hasDetailedAttributes)
    }

    @Test func infoParsesDetailedAttributesWhenSmartctlAvailable() throws {
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["SMARTStatus": "Verified"], format: .xml, options: 0
        )
        let runner = ProcessRunner.stub { launchPath, _ in
            if launchPath.hasSuffix("diskutil") {
                return ProcessResult(exitCode: 0, standardOutput: plistData, standardError: Data())
            }
            return ProcessResult(exitCode: 0, standardOutput: Data(smartctlSampleOutput.utf8), standardError: Data())
        }
        let info = try SMARTService(runner: runner).info(for: "disk0", smartctlPath: "/opt/homebrew/bin/smartctl")
        #expect(info.smartctlAvailable)
        #expect(info.temperatureCelsius == 33)
        #expect(info.powerOnHours == 1234)
        #expect(info.reallocatedSectorCount == 0)
        #expect(info.hasDetailedAttributes)
    }
}
