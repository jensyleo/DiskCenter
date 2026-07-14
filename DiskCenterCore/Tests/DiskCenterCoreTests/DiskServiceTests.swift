// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

/// A trimmed `diskutil list -plist` sample (two whole disks, APFS layout).
private let listPlistXML = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AllDisksAndPartitions</key>
  <array>
    <dict>
      <key>DeviceIdentifier</key><string>disk0</string>
      <key>Partitions</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk0s1</string>
          <key>Content</key><string>Apple_APFS</string>
          <key>Size</key><integer>494384795648</integer>
        </dict>
      </array>
    </dict>
    <dict>
      <key>DeviceIdentifier</key><string>disk4</string>
      <key>Partitions</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk4s1</string>
          <key>Content</key><string>Microsoft Basic Data</string>
          <key>VolumeName</key><string>MYUSB</string>
          <key>Size</key><integer>62914560000</integer>
          <key>MountPoint</key><string>/Volumes/MYUSB</string>
        </dict>
      </array>
    </dict>
  </array>
  <key>WholeDisks</key>
  <array>
    <string>disk0</string>
    <string>disk4</string>
  </array>
</dict>
</plist>
"""

/// A trimmed `diskutil list -plist` sample with a real APFS container shape:
/// disk0's only GPT partition (disk0s2) is the physical store for container
/// disk3, whose `APFSVolumes` holds a sealed root ("Macintosh HD", no direct
/// mount point) + its live snapshot (real mount point "/"), a hidden
/// OSInternal volume (Preboot), and an unmounted Data volume.
private let apfsContainerPlistXML = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>AllDisksAndPartitions</key>
  <array>
    <dict>
      <key>DeviceIdentifier</key><string>disk0</string>
      <key>Partitions</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk0s2</string>
          <key>Content</key><string>Apple_APFS</string>
          <key>Size</key><integer>494384795648</integer>
        </dict>
      </array>
    </dict>
    <dict>
      <key>DeviceIdentifier</key><string>disk3</string>
      <key>APFSPhysicalStores</key>
      <array>
        <dict><key>DeviceIdentifier</key><string>disk0s2</string></dict>
      </array>
      <key>APFSVolumes</key>
      <array>
        <dict>
          <key>DeviceIdentifier</key><string>disk3s1</string>
          <key>VolumeName</key><string>Macintosh HD</string>
          <key>Size</key><integer>494384795648</integer>
          <key>OSInternal</key><false/>
          <key>MountedSnapshots</key>
          <array>
            <dict><key>SnapshotBSD</key><string>disk3s1s1</string></dict>
          </array>
        </dict>
        <dict>
          <key>DeviceIdentifier</key><string>disk3s1s1</string>
          <key>VolumeName</key><string>Macintosh HD</string>
          <key>Size</key><integer>494384795648</integer>
          <key>MountPoint</key><string>/</string>
          <key>OSInternal</key><false/>
        </dict>
        <dict>
          <key>DeviceIdentifier</key><string>disk3s2</string>
          <key>VolumeName</key><string>Preboot</string>
          <key>Size</key><integer>9070485504</integer>
          <key>MountPoint</key><string>/System/Volumes/Preboot</string>
          <key>OSInternal</key><true/>
        </dict>
        <dict>
          <key>DeviceIdentifier</key><string>disk3s5</string>
          <key>VolumeName</key><string>Backup</string>
          <key>Size</key><integer>124100000000</integer>
          <key>OSInternal</key><false/>
        </dict>
      </array>
    </dict>
  </array>
  <key>WholeDisks</key>
  <array>
    <string>disk0</string>
  </array>
</dict>
</plist>
"""

/// Thread-safe call counter for stubbed-runner assertions.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@Suite struct DiskServiceTests {
    private func listPlist() throws -> [String: Any] {
        try DiskService.parsePlist(Data(listPlistXML.utf8))
    }

    @Test func parsesWholeDiskIDs() throws {
        let ids = DiskService.wholeDiskIDs(from: try listPlist())
        #expect(ids == ["disk0", "disk4"])
    }

    @Test func parsesPartitionsForDisk() throws {
        let parts = DiskService.partitions(for: "disk4", in: try listPlist())
        #expect(parts.count == 1)
        let p = try #require(parts.first)
        #expect(p.id == "disk4s1")
        #expect(p.volumeName == "MYUSB")
        #expect(p.mountPoint == "/Volumes/MYUSB")
        #expect(p.isMounted)
        #expect(p.size == 62_914_560_000)
    }

    @Test func systemDiskDetectedFromResolvedWholeDiskID() {
        // Whole-container `Bootable` is deliberately false/absent here — this is
        // the real-world APFS shape (see systemWholeDiskID doc comment). Only the
        // resolved `isSystemDisk: true` passed in by listDisks() should matter.
        let info: [String: Any] = ["Internal": true, "Size": NSNumber(value: 494_384_795_648)]
        let disk = DiskService.makeDisk(id: "disk0", info: info, partitions: [], isSystemDisk: true)
        #expect(disk.isSystemDisk)
        #expect(disk.isInternal)
        #expect(disk.rawDevicePath == "/dev/rdisk0")
    }

    @Test func osInternalFlagAloneMarksSystemDisk() {
        let info: [String: Any] = ["Internal": true, "OSInternal": true]
        let disk = DiskService.makeDisk(id: "disk1", info: info, partitions: [], isSystemDisk: false)
        #expect(disk.isSystemDisk)
    }

    @Test func externalDiskIsNotSystem() {
        let info: [String: Any] = ["Internal": false, "Removable": true]
        let disk = DiskService.makeDisk(id: "disk4", info: info, partitions: [], isSystemDisk: false)
        #expect(!disk.isSystemDisk)
        #expect(disk.isRemovable)
    }

    @Test func synthesizedAPFSContainerIsMarkedVirtual() {
        // A container whole-disk (e.g. disk3) carries its own APFSPhysicalStores
        // pointing at the real disk backing it — its Size double-counts that
        // disk's bytes if summed alongside it (found via live Dashboard testing:
        // a single 500 GB SSD showed as "1 TB Total Capacity").
        let info: [String: Any] = [
            "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]],
            "Size": NSNumber(value: 494_384_795_648),
        ]
        let disk = DiskService.makeDisk(id: "disk3", info: info, partitions: [], isSystemDisk: false)
        #expect(disk.isVirtual)
    }

    @Test func realPhysicalDiskIsNotMarkedVirtual() {
        let info: [String: Any] = ["Internal": true, "Size": NSNumber(value: 500_277_792_768)]
        let disk = DiskService.makeDisk(id: "disk0", info: info, partitions: [], isSystemDisk: false)
        #expect(!disk.isVirtual)
    }

    @Test func systemWholeDiskIDResolvesThroughPhysicalStore() throws {
        // "/" → APFSPhysicalStores[0] (disk0s2) → ParentWholeDisk (disk0).
        let rootPlist = plistData([
            "APFSPhysicalStores": [["APFSPhysicalStore": "disk0s2"]],
        ])
        let storePlist = plistData(["ParentWholeDisk": "disk0"])

        let callCount = Counter()
        let runner = ProcessRunner.stub { _, arguments in
            callCount.increment()
            let data = arguments.contains("/") ? rootPlist : storePlist
            return ProcessResult(exitCode: 0, standardOutput: data, standardError: Data())
        }

        let systemDiskID = try DiskService(runner: runner).systemWholeDiskID()
        #expect(systemDiskID == "disk0")
        #expect(callCount.value == 2)
    }

    private func apfsListPlist() throws -> [String: Any] {
        try DiskService.parsePlist(Data(apfsContainerPlistXML.utf8))
    }

    @Test func volumesResolvesRealAPFSVolumesInsteadOfOpaqueContainer() throws {
        let volumes = DiskService.volumes(for: "disk0", in: try apfsListPlist())
        // The container itself (disk0s2 → "Apple_APFS") never appears; only its
        // real volumes do, and the sealed root's duplicate is skipped.
        let ids = volumes.map(\.id)
        #expect(!ids.contains("disk0s2"))
        #expect(!ids.contains("disk3s1"), "sealed root with a mounted snapshot should be skipped")
        #expect(ids == ["disk3s1s1", "disk3s2", "disk3s5"])
    }

    @Test func volumesCarriesRealMountPointForTheSnapshot() throws {
        let volumes = DiskService.volumes(for: "disk0", in: try apfsListPlist())
        let root = try #require(volumes.first { $0.id == "disk3s1s1" })
        #expect(root.mountPoint == "/")
        #expect(root.isMounted)
        #expect(root.volumeName == "Macintosh HD")
    }

    @Test func volumesFlagsOSInternalVolumes() throws {
        let volumes = DiskService.volumes(for: "disk0", in: try apfsListPlist())
        let preboot = try #require(volumes.first { $0.id == "disk3s2" })
        #expect(preboot.isOSInternal)
        let backup = try #require(volumes.first { $0.id == "disk3s5" })
        #expect(!backup.isOSInternal)
        #expect(!backup.isMounted)
    }

    @Test func volumesPassesThroughTerminalPartitionUnchanged() throws {
        // disk4s1 (plain FAT32 stick) has no container claiming it as a
        // physical store, so it should pass through as-is.
        let volumes = DiskService.volumes(for: "disk4", in: try listPlist())
        #expect(volumes.count == 1)
        #expect(volumes.first?.id == "disk4s1")
        #expect(volumes.first?.isOSInternal == false)
    }

    @Test func ejectSendsWholeDiskIdentifierToEjectVerb() throws {
        // A real bug found by inspection: eject must use `diskutil eject`,
        // NOT `diskutil unmount` — `unmount` targets a single mounted volume
        // and doesn't do the right thing for a whole disk with several
        // volumes on it, unlike `eject`.
        let capturedArgs = CapturedArguments()
        let runner = ProcessRunner.stub { _, args in
            capturedArgs.set(args)
            return ProcessResult(exitCode: 0, standardOutput: Data(), standardError: Data())
        }
        try DiskService(runner: runner).eject("disk4")
        #expect(capturedArgs.value == ["eject", "disk4"])
    }

    @Test func ejectThrowsOnFailure() {
        let runner = ProcessRunner.stub { _, _ in
            ProcessResult(exitCode: 1, standardOutput: Data(), standardError: Data("Resource busy".utf8))
        }
        #expect(throws: DiskServiceError.self) {
            try DiskService(runner: runner).eject("disk4")
        }
    }

    private func plistData(_ dict: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}

private final class CapturedArguments: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    func set(_ args: [String]) { lock.withLock { stored = args } }
    var value: [String] { lock.withLock { stored } }
}
