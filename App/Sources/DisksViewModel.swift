// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import Foundation
import Observation

@MainActor
@Observable
final class DisksViewModel {
    private(set) var disks: [Disk] = []
    private(set) var errorMessage: String?
    private(set) var isLoading = false
    /// SMART info per whole-disk BSD name, fetched lazily as rows appear.
    private(set) var smartInfoByDisk: [String: SMARTInfo] = [:]
    /// Error from the most recent mount/unmount action, if any.
    private(set) var volumeActionError: String?

    private let diskService = DiskService()
    private let smartService = SMARTService()
    private let logger = LoggerService()

    /// Reload the disk list off the main actor, then publish on it.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await Task.detached { try DiskService().listDisks() }.value
            disks = result
            logger.log("Refreshed disk list (\(result.count) disks)")
        } catch {
            errorMessage = "\(error)"
            disks = []
            logger.log("Failed to refresh disk list: \(error)")
        }
    }

    /// Fetch SMART info for a whole disk, off the main actor, cached afterwards.
    func loadSMARTInfo(for diskID: String) async {
        guard smartInfoByDisk[diskID] == nil else { return }
        let smartService = self.smartService
        let logger = self.logger
        let info = await Task.detached { () -> SMARTInfo? in
            try? smartService.info(for: diskID)
        }.value
        if let info {
            smartInfoByDisk[diskID] = info
            logger.log("Read SMART info for \(diskID): \(info.status.rawValue)")
        }
    }

    func mount(_ volumeID: String) async {
        volumeActionError = nil
        let service = diskService
        let logger = logger
        do {
            try await Task.detached { try service.mount(volumeID) }.value
            logger.log("Mounted \(volumeID)")
            await refresh()
        } catch {
            volumeActionError = "Could not mount \(volumeID): \(error)"
            logger.log("Failed to mount \(volumeID): \(error)")
        }
    }

    func unmount(_ volumeID: String) async {
        volumeActionError = nil
        let service = diskService
        let logger = logger
        do {
            try await Task.detached { try service.unmount(volumeID) }.value
            logger.log("Unmounted \(volumeID)")
            await refresh()
        } catch {
            volumeActionError = "Could not unmount \(volumeID): \(error)"
            logger.log("Failed to unmount \(volumeID): \(error)")
        }
    }

    func clearVolumeActionError() {
        volumeActionError = nil
    }

    /// Human-readable byte size for display.
    static func humanSize(_ bytes: Int64?) -> String {
        guard let bytes else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
