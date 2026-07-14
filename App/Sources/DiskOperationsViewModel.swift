// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import Foundation
import Observation

enum DiskOperationKind {
    case createImage(disk: Disk, destination: URL, compression: CompressionKind)
    case backupGPT(disk: Disk, destination: URL)
    case verifyDisk(diskID: String, label: String)
    case repairDisk(diskID: String, label: String)
    case secureErase(disk: Disk, level: EraseLevel)
    case restoreImage(source: URL, destination: Disk)
    case cloneDisk(source: Disk, destination: Disk)
    case createBootableUSB(source: URL, destination: Disk)

    var title: String {
        switch self {
        case .createImage: return "Create Image"
        case .backupGPT: return "Backup GPT"
        case .verifyDisk: return "Verify Disk"
        case .repairDisk: return "Repair Disk"
        case .secureErase: return "Secure Erase"
        case .restoreImage: return "Restore Image"
        case .cloneDisk: return "Clone Disk"
        case .createBootableUSB: return "Create Bootable USB"
        }
    }

    /// These already went through their own red confirm screen
    /// (`EraseSetupView`/`CloneSetupView`) before an `ActiveOperation` was
    /// even created — this just marks it so the generic sheet can style the
    /// simulation step accordingly.
    var isDestructive: Bool {
        switch self {
        case .secureErase, .restoreImage, .cloneDisk, .createBootableUSB: return true
        case .createImage, .backupGPT, .verifyDisk, .repairDisk: return false
        }
    }
}

/// Transient state for the red confirmation screen (spec §6) shown BEFORE the
/// normal simulation/execute flow for a destructive operation. Kept separate
/// from `ActiveOperation` because it needs its own mutable, in-progress input
/// (level picker, typed confirmation text) that isn't relevant once the real
/// operation starts.
@MainActor
@Observable
final class EraseSetup: Identifiable {
    let id = UUID()
    let disk: Disk
    let allowedLevels: [EraseLevel]
    var selectedLevel: EraseLevel
    var confirmationText = ""

    init(disk: Disk, allowedLevels: [EraseLevel]) {
        self.disk = disk
        self.allowedLevels = allowedLevels
        self.selectedLevel = allowedLevels.first ?? .quickZeroFill
    }

    var isConfirmed: Bool {
        confirmationText == disk.id || confirmationText == "ERASE"
    }
}

/// What's being written to the destination disk in a `CloneSetup` flow.
enum CloneSourceKind {
    case disk(Disk)
    case imageFile(URL, sizeBytes: Int64?)
    case bootableUSB(URL, sizeBytes: Int64?)
}

/// Transient state for the red confirmation screen shared by Restore Image,
/// Clone Disk, and Create Bootable USB — all three overwrite an existing
/// destination disk, unlike Create Image/Backup GPT which only ever write a
/// brand-new file. `availableDestinations` is pre-filtered to exclude the
/// system disk (and the source disk, for Clone) so an invalid choice can't
/// even be selected.
@MainActor
@Observable
final class CloneSetup: Identifiable {
    let id = UUID()
    let source: CloneSourceKind
    let availableDestinations: [Disk]
    var selectedDestination: Disk?
    var confirmationText = ""

    init(source: CloneSourceKind, availableDestinations: [Disk]) {
        self.source = source
        self.availableDestinations = availableDestinations
        self.selectedDestination = availableDestinations.first
    }

    var isConfirmed: Bool {
        guard let destination = selectedDestination else { return false }
        return confirmationText == destination.id || confirmationText == "ERASE"
    }

    var sourceLabel: String {
        switch source {
        case .disk(let disk): return disk.model ?? disk.id
        case .imageFile(let url, _), .bootableUSB(let url, _): return url.lastPathComponent
        }
    }
}

enum OperationPhase {
    /// Simulation mode (spec §6): the exact command is shown before anything runs.
    case confirming
    case running(DDProgress?)
    case succeeded(String)
    case failed(String)
}

@MainActor
@Observable
final class ActiveOperation: Identifiable {
    let id = UUID()
    let kind: DiskOperationKind
    let commandPreview: String
    var phase: OperationPhase = .confirming

    init(kind: DiskOperationKind, commandPreview: String) {
        self.kind = kind
        self.commandPreview = commandPreview
    }
}

/// Drives the Phase 2 operations (spec §4.4/§4.8/§4.9): create image, GPT
/// backup, and read-only disk verification. Every operation shows its exact
/// command before running (simulation mode) and is serialized per-disk via
/// `DiskOperationLock` so two operations never target the same disk at once.
@MainActor
@Observable
final class DiskOperationsViewModel {
    private(set) var active: ActiveOperation?
    private(set) var setupError: String?
    /// Non-nil while the red confirmation screen for Secure Erase is showing.
    private(set) var eraseSetup: EraseSetup?
    /// Non-nil while the red confirmation screen for Restore/Clone/Bootable
    /// USB is showing.
    private(set) var cloneSetup: CloneSetup?

    private var cancellationToken: ProcessCancellationToken?

    private let imageService = ImageService()
    private let gptBackupService = GPTBackupService()
    private let repairService = RepairService()
    private let eraseService = EraseService()
    private let cloneService = CloneService()
    private let validationService = ValidationService()
    private let logger = LoggerService()
    private let historyService = HistoryService()

    // MARK: - Starting an operation (pick destination, validate, show simulation)

    func beginCreateImage(disk: Disk, compression: CompressionKind = .none) {
        setupError = nil
        let suggestedName = "\(disk.model ?? disk.id).img\(compression.fileExtensionSuffix)"
        guard let destination = SavePanel.pickDestination(suggestedName: suggestedName) else { return }
        do {
            try validationService.validateSufficientSpace(
                destinationDirectory: destination.deletingLastPathComponent(),
                // Compressed images are typically much smaller, but we can't
                // know the ratio in advance — requiring the FULL uncompressed
                // size free is the safe assumption.
                requiredBytes: disk.size ?? 0
            )
        } catch {
            setupError = "\(error)"
            return
        }
        let preview = imageService.commandPreview(
            sourceDevicePath: disk.rawDevicePath, destination: destination, compression: compression
        )
        active = ActiveOperation(
            kind: .createImage(disk: disk, destination: destination, compression: compression),
            commandPreview: preview
        )
    }

    func beginBackupGPT(disk: Disk) {
        setupError = nil
        guard let destination = SavePanel.pickDestination(suggestedName: "\(disk.id)-gpt-backup.bin") else { return }
        do {
            try validationService.validateSufficientSpace(
                destinationDirectory: destination.deletingLastPathComponent(),
                requiredBytes: GPTBackupService.defaultBackupSizeBytes
            )
        } catch {
            setupError = "\(error)"
            return
        }
        let preview = gptBackupService.commandPreview(rawDevicePath: disk.rawDevicePath, destination: destination)
        active = ActiveOperation(kind: .backupGPT(disk: disk, destination: destination), commandPreview: preview)
    }

    func beginVerifyDisk(diskID: String, label: String) {
        setupError = nil
        let preview = repairService.commandPreview(diskID: diskID)
        active = ActiveOperation(kind: .verifyDisk(diskID: diskID, label: label), commandPreview: preview)
    }

    func beginRepairDisk(diskID: String, label: String) {
        setupError = nil
        let preview = repairService.repairCommandPreview(diskID: diskID)
        active = ActiveOperation(kind: .repairDisk(diskID: diskID, label: label), commandPreview: preview)
    }

    /// Step 1 of Secure Erase: the red confirmation screen (spec §6), shown
    /// before the normal simulation/execute flow. Never allowed against the
    /// system disk — `ValidationService` is checked here, not just left to
    /// the UI to remember to filter.
    func beginSecureEraseSetup(disk: Disk) {
        setupError = nil
        do {
            try validationService.validateNotSystemDisk(disk)
        } catch {
            setupError = "\(error)"
            return
        }
        eraseSetup = EraseSetup(disk: disk, allowedLevels: eraseService.allowedLevels(for: disk.mediaKind))
    }

    func cancelEraseSetup() {
        eraseSetup = nil
    }

    /// Step 2: the user typed the disk identifier (or "ERASE") and picked a
    /// level — proceed to the normal simulation screen (show the exact
    /// command) before anything actually runs.
    func confirmEraseSetup() {
        guard let setup = eraseSetup, setup.isConfirmed else { return }
        let preview = eraseService.commandPreview(diskID: setup.disk.id, level: setup.selectedLevel)
        active = ActiveOperation(kind: .secureErase(disk: setup.disk, level: setup.selectedLevel), commandPreview: preview)
        eraseSetup = nil
    }

    /// Step 1 of Restore Image: pick the source image file, then show the red
    /// confirmation screen with a destination-disk picker (system disk
    /// excluded — `ValidationService.validateNotSystemDisk` filters the list,
    /// not just relying on the UI to remember).
    func beginRestoreImageSetup(availableDisks: [Disk]) {
        setupError = nil
        guard let source = OpenPanel.pickSourceImage() else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? nil
        let destinations = availableDisks.filter { !$0.isSystemDisk }
        guard !destinations.isEmpty else {
            setupError = "No non-system disks available as a restore destination."
            return
        }
        cloneSetup = CloneSetup(source: .imageFile(source, sizeBytes: size), availableDestinations: destinations)
    }

    /// Step 1 of Clone Disk: `source` is fixed (the disk the user clicked
    /// from), the red confirmation screen picks the destination from every
    /// OTHER non-system disk.
    func beginCloneDiskSetup(source: Disk, availableDisks: [Disk]) {
        setupError = nil
        let destinations = availableDisks.filter { !$0.isSystemDisk && $0.id != source.id }
        guard !destinations.isEmpty else {
            setupError = "No other non-system disks available as a clone destination."
            return
        }
        cloneSetup = CloneSetup(source: .disk(source), availableDestinations: destinations)
    }

    /// Step 1 of Create Bootable USB: pick the source ISO/image, then the
    /// destination — spec's flow is unmount → write → sync → verify → eject;
    /// the eject happens automatically on success (`runCreateBootableUSB`).
    func beginCreateBootableUSBSetup(availableDisks: [Disk]) {
        setupError = nil
        guard let source = OpenPanel.pickSourceImage() else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? nil
        let destinations = availableDisks.filter { !$0.isSystemDisk }
        guard !destinations.isEmpty else {
            setupError = "No non-system disks available to write the USB to."
            return
        }
        cloneSetup = CloneSetup(source: .bootableUSB(source, sizeBytes: size), availableDestinations: destinations)
    }

    func cancelCloneSetup() {
        cloneSetup = nil
    }

    /// Step 2: destination chosen and confirmation text typed — proceed to
    /// the normal simulation screen (exact command shown) before anything runs.
    func confirmCloneSetup() {
        guard let setup = cloneSetup, setup.isConfirmed, let destination = setup.selectedDestination else { return }
        do {
            try validationService.validateNotSystemDisk(destination)
            if case .disk(let source) = setup.source {
                try validationService.validateOriginNotDestination(sourceDiskID: source.id, destinationDiskID: destination.id)
            }
        } catch {
            setupError = Self.describe(error)
            cloneSetup = nil
            return
        }

        let kind: DiskOperationKind
        let preview: String
        switch setup.source {
        case .disk(let source):
            kind = .cloneDisk(source: source, destination: destination)
            preview = cloneService.commandPreview(sourcePath: source.rawDevicePath, destinationPath: destination.rawDevicePath)
        case .imageFile(let url, _):
            kind = .restoreImage(source: url, destination: destination)
            preview = cloneService.commandPreview(sourcePath: url.path, destinationPath: destination.rawDevicePath)
        case .bootableUSB(let url, _):
            kind = .createBootableUSB(source: url, destination: destination)
            preview = cloneService.commandPreview(sourcePath: url.path, destinationPath: destination.rawDevicePath)
        }
        active = ActiveOperation(kind: kind, commandPreview: preview)
        cloneSetup = nil
    }

    // MARK: - Executing (after the user confirms the simulated command)

    func execute() {
        guard let active else { return }
        let token = ProcessCancellationToken()
        cancellationToken = token
        active.phase = .running(nil)

        switch active.kind {
        case .createImage(let disk, let destination, let compression):
            runCreateImage(disk: disk, destination: destination, compression: compression, token: token)
        case .backupGPT(let disk, let destination):
            runBackupGPT(disk: disk, destination: destination, token: token)
        case .verifyDisk(let diskID, let label):
            runVerifyDisk(diskID: diskID, label: label, token: token)
        case .repairDisk(let diskID, let label):
            runRepairDisk(diskID: diskID, label: label, token: token)
        case .secureErase(let disk, let level):
            runSecureErase(disk: disk, level: level, token: token)
        case .restoreImage(let source, let destination):
            runCloneLike(
                operationName: "Restore Image", historyKind: .restore,
                sourcePath: source.path, destination: destination, token: token,
                successMessage: { bytes in "Restored \(bytes) bytes to \(destination.model ?? destination.id)." }
            )
        case .cloneDisk(let source, let destination):
            runCloneLike(
                operationName: "Clone Disk", historyKind: .clone,
                sourcePath: source.rawDevicePath, destination: destination, token: token,
                successMessage: { bytes in "Cloned \(bytes) bytes from \(source.model ?? source.id) to \(destination.model ?? destination.id)." }
            )
        case .createBootableUSB(let source, let destination):
            runCreateBootableUSB(source: source, destination: destination, token: token)
        }
    }

    func cancelRunningOperation() {
        cancellationToken?.cancel()
    }

    func dismiss() {
        active = nil
        cancellationToken = nil
    }

    func clearSetupError() {
        setupError = nil
    }

    // MARK: - Implementations

    private func runCreateImage(disk: Disk, destination: URL, compression: CompressionKind, token: ProcessCancellationToken) {
        let service = imageService
        let logger = logger
        let history = historyService
        let sourcePath = disk.rawDevicePath
        let diskID = disk.id
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: "Create Image")
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.createImage(
                    sourceDevicePath: sourcePath,
                    destination: destination,
                    compression: compression,
                    token: token,
                    progress: { [weak self] p in
                        Task { @MainActor in self?.active?.phase = .running(p) }
                    }
                )
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Created image of \(diskID) at \(destination.path) (sha256: \(result.sha256))")
                history.record(HistoryEntry(
                    kind: .imageCreated, label: destination.lastPathComponent, path: destination.path, date: Date()
                ))
                active?.phase = .succeeded(
                    "Image created at \(destination.lastPathComponent).\nSHA256: \(result.sha256)"
                )
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Failed to create image of \(diskID): \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    private func runBackupGPT(disk: Disk, destination: URL, token: ProcessCancellationToken) {
        let service = gptBackupService
        let logger = logger
        let history = historyService
        let sourcePath = disk.rawDevicePath
        let diskID = disk.id
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: "Backup GPT")
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.backup(
                    rawDevicePath: sourcePath,
                    destination: destination,
                    token: token,
                    progress: { [weak self] p in
                        Task { @MainActor in self?.active?.phase = .running(p) }
                    }
                )
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Backed up GPT of \(diskID) to \(destination.path) (\(result.bytesWritten) bytes)")
                history.record(HistoryEntry(
                    kind: .gptBackup, label: destination.lastPathComponent, path: destination.path, date: Date()
                ))
                active?.phase = .succeeded("GPT backup saved to \(destination.lastPathComponent).")
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Failed to back up GPT of \(diskID): \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    private func runVerifyDisk(diskID: String, label: String, token: ProcessCancellationToken) {
        let service = repairService
        let logger = logger
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: "Verify Disk")
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.verifyDisk(diskID, token: token)
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Verified \(diskID): \(result.passed ? "passed" : "issues found")")
                if result.passed {
                    active?.phase = .succeeded("No issues found.\n\n\(result.log)")
                } else {
                    active?.phase = .failed(result.log)
                }
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Failed to verify \(diskID): \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    private func runRepairDisk(diskID: String, label: String, token: ProcessCancellationToken) {
        let service = repairService
        let logger = logger
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: "Repair Disk")
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.repairDisk(diskID, token: token)
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Repaired \(diskID): \(result.passed ? "OK" : "issues remain")")
                if result.passed {
                    active?.phase = .succeeded("Repair completed.\n\n\(result.log)")
                } else {
                    active?.phase = .failed(result.log)
                }
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Failed to repair \(diskID): \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    private func runSecureErase(disk: Disk, level: EraseLevel, token: ProcessCancellationToken) {
        let service = eraseService
        let logger = logger
        let diskID = disk.id
        let mediaKind = disk.mediaKind
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: "Secure Erase")
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.erase(diskID: diskID, level: level, mediaKind: mediaKind, token: token)
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Erased \(diskID) at level \(level.rawValue): \(result.succeeded ? "succeeded" : "failed")")
                if result.succeeded {
                    active?.phase = .succeeded("Disk erased.\n\n\(result.log)")
                } else {
                    active?.phase = .failed(result.log)
                }
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Failed to erase \(diskID): \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    /// Shared implementation for Restore Image and Clone Disk — both are just
    /// `CloneService.clone` with a different source, always targeting an
    /// existing destination disk (unlike Create Image, whose destination is
    /// always a brand-new file).
    private func runCloneLike(
        operationName: String,
        historyKind: HistoryEntry.Kind,
        sourcePath: String,
        destination: Disk,
        token: ProcessCancellationToken,
        successMessage: @escaping (Int64) -> String
    ) {
        let service = cloneService
        let logger = logger
        let history = historyService
        let diskID = destination.id
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: operationName)
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.clone(
                    sourcePath: sourcePath,
                    destinationPath: destination.rawDevicePath,
                    token: token,
                    progress: { [weak self] p in
                        Task { @MainActor in self?.active?.phase = .running(p) }
                    }
                )
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("\(operationName) to \(diskID) succeeded (\(result.bytesWritten) bytes)")
                history.record(HistoryEntry(
                    kind: historyKind, label: destination.model ?? destination.id, path: sourcePath, date: Date()
                ))
                active?.phase = .succeeded(successMessage(result.bytesWritten))
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("\(operationName) to \(diskID) failed: \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    /// Spec's flow: unmount → write → sync → verify → eject. `dd` handles the
    /// write; the destination disk isn't separately unmounted first because
    /// `dd` writes to the raw device node directly regardless of mount state
    /// (matching what `ImageService`/`GPTBackupService` already do). Ejecting
    /// afterward is the one truly distinct step versus a plain restore.
    private func runCreateBootableUSB(source: URL, destination: Disk, token: ProcessCancellationToken) {
        let service = cloneService
        let logger = logger
        let diskID = destination.id
        Task {
            do {
                try await DiskOperationLock.shared.acquire(diskID: diskID, operation: "Create Bootable USB")
            } catch {
                active?.phase = .failed(Self.describe(error))
                return
            }
            do {
                let result = try await service.clone(
                    sourcePath: source.path,
                    destinationPath: destination.rawDevicePath,
                    token: token,
                    progress: { [weak self] p in
                        Task { @MainActor in self?.active?.phase = .running(p) }
                    }
                )
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Created bootable USB on \(diskID) (\(result.bytesWritten) bytes)")

                // Eject is a whole-disk operation (`diskutil eject`, not
                // `unmount`, which only targets a single mounted volume) —
                // and its result determines what the user is actually told,
                // rather than being silently assumed to have worked.
                let diskService = DiskService()
                let ejected = (try? await Task.detached { try diskService.eject(destination.id) }.value) != nil
                if ejected {
                    logger.log("Ejected \(diskID)")
                    active?.phase = .succeeded(
                        "Bootable USB created on \(destination.model ?? destination.id) and ejected. It's safe to unplug."
                    )
                } else {
                    logger.log("Created bootable USB on \(diskID) but automatic eject failed")
                    active?.phase = .succeeded(
                        "Bootable USB created on \(destination.model ?? destination.id). "
                            + "Automatic eject failed — eject it manually in Finder before unplugging."
                    )
                }
            } catch {
                await DiskOperationLock.shared.release(diskID: diskID)
                logger.log("Failed to create bootable USB on \(diskID): \(error)")
                active?.phase = .failed(Self.describe(error))
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let lockError = error as? DiskOperationLockError,
           case .alreadyInProgress(let diskID, let operation) = lockError {
            return "\(operation) is already running on \(diskID). Wait for it to finish first."
        }
        return "\(error)"
    }
}
