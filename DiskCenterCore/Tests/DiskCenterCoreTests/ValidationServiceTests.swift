// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct ValidationServiceTests {
    @Test func passesWhenRequiredBytesFitsEasily() throws {
        // The system temp volume has far more than a few bytes free.
        try ValidationService().validateSufficientSpace(
            destinationDirectory: FileManager.default.temporaryDirectory,
            requiredBytes: 1024
        )
    }

    @Test func throwsWhenRequiredBytesExceedsAvailable() {
        #expect(throws: ValidationError.self) {
            try ValidationService().validateSufficientSpace(
                destinationDirectory: FileManager.default.temporaryDirectory,
                requiredBytes: Int64.max - 1
            )
        }
    }

    @Test func sameDiskAsSourceAndDestinationThrows() {
        #expect(throws: ValidationError.self) {
            try ValidationService().validateOriginNotDestination(sourceDiskID: "disk4", destinationDiskID: "disk4")
        }
    }

    @Test func differentDisksPassOriginDestinationCheck() throws {
        try ValidationService().validateOriginNotDestination(sourceDiskID: "disk4", destinationDiskID: "disk5")
    }

    @Test func systemDiskAsTargetThrows() {
        let disk = Disk(id: "disk0", isSystemDisk: true)
        #expect(throws: ValidationError.self) {
            try ValidationService().validateNotSystemDisk(disk)
        }
    }

    @Test func nonSystemDiskAsTargetPasses() throws {
        let disk = Disk(id: "disk4", isSystemDisk: false)
        try ValidationService().validateNotSystemDisk(disk)
    }

    @Test func recoveryPartitionByContentThrows() {
        let partition = Partition(id: "disk0s3", content: "Apple_APFS_Recovery")
        #expect(throws: ValidationError.self) {
            try ValidationService().validateNotRecoveryPartition(partition)
        }
    }

    @Test func recoveryPartitionByVolumeNameThrows() {
        let partition = Partition(id: "disk3s3", volumeName: "Recovery")
        #expect(throws: ValidationError.self) {
            try ValidationService().validateNotRecoveryPartition(partition)
        }
    }

    @Test func ordinaryPartitionPassesRecoveryCheck() throws {
        let partition = Partition(id: "disk3s1s1", volumeName: "Macintosh HD")
        try ValidationService().validateNotRecoveryPartition(partition)
    }

    @Test func parsesLsofFieldOutputIntoPidsAndCommands() {
        let output = "p1234\ncbash\np5678\ncfinder\n"
        let items = ValidationService.parseLsofFieldOutput(output)
        #expect(items.count == 2)
        #expect(items[0].pid == 1234)
        #expect(items[0].command == "bash")
        #expect(items[1].pid == 5678)
        #expect(items[1].command == "finder")
    }

    @Test func emptyLsofOutputYieldsNoProcesses() {
        #expect(ValidationService.parseLsofFieldOutput("").isEmpty)
    }

    @Test func checksForLocalSnapshotsUsingStubbedPlist() throws {
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: ["Snapshots": [["SnapshotName": "com.apple.os.update-ABC123"]]],
            format: .xml, options: 0
        )
        let runner = ProcessRunner.stub { _, _ in
            ProcessResult(exitCode: 0, standardOutput: plistData, standardError: Data())
        }
        let names = try ValidationService(runner: runner).checkForLocalSnapshots(volumeID: "disk3s1s1")
        #expect(names == ["com.apple.os.update-ABC123"])
    }

    @Test func noSnapshotsReturnsEmptyArray() throws {
        let runner = ProcessRunner.stub { _, _ in
            ProcessResult(exitCode: 1, standardOutput: Data(), standardError: Data("not an APFS volume".utf8))
        }
        let names = try ValidationService(runner: runner).checkForLocalSnapshots(volumeID: "disk4s1")
        #expect(names.isEmpty)
    }
}

@Suite struct DiskOperationLockTests {
    @Test func secondOperationOnSameDiskThrowsImmediately() async throws {
        let lock = DiskOperationLock()
        try await lock.acquire(diskID: "disk4", operation: "Create Image")

        await #expect(throws: DiskOperationLockError.self) {
            try await lock.acquire(diskID: "disk4", operation: "Backup GPT")
        }

        await lock.release(diskID: "disk4")
    }

    @Test func differentDisksDoNotContend() async throws {
        let lock = DiskOperationLock()
        try await lock.acquire(diskID: "disk4", operation: "A")
        try await lock.acquire(diskID: "disk5", operation: "B")
        await lock.release(diskID: "disk4")
        await lock.release(diskID: "disk5")
    }

    @Test func lockReleasesAfterCompletionSoANewOperationCanStart() async throws {
        let lock = DiskOperationLock()
        try await lock.acquire(diskID: "disk4", operation: "First")
        await lock.release(diskID: "disk4")
        try await lock.acquire(diskID: "disk4", operation: "Second")
        await lock.release(diskID: "disk4")
    }

    @Test func isBusyReflectsCurrentState() async throws {
        let lock = DiskOperationLock()
        #expect(await !lock.isBusy("disk4"))
        try await lock.acquire(diskID: "disk4", operation: "Create Image")
        #expect(await lock.isBusy("disk4"))
        await lock.release(diskID: "disk4")
        #expect(await !lock.isBusy("disk4"))
    }
}
