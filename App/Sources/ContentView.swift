// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import SwiftUI

private enum SidebarSelection: Hashable {
    case dashboard
    case disk(String)
}

struct ContentView: View {
    let model: DisksViewModel
    @State private var operations = DiskOperationsViewModel()
    @State private var scheduler = ScheduledBackupsViewModel()
    @State private var showAdminSheet = false
    @State private var selection: SidebarSelection? = .dashboard
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarSelection.dashboard)
                    .accessibilityLabel("Dashboard")

                Section("Disks") {
                    ForEach(model.disks) { disk in
                        DiskRow(disk: disk)
                            .tag(SidebarSelection.disk(disk.id))
                    }
                }
            }
            .navigationTitle("DiskCenter")
            .frame(minWidth: 260)
        } detail: {
            detailView
        }
        .toolbar {
            if getuid() == 0 {
                ToolbarItem(placement: .navigation) {
                    Label("Admin", systemImage: "lock.shield.fill")
                        .foregroundStyle(.blue)
                        .help("Running with root privileges")
                        .accessibilityLabel("Running with administrator privileges")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .help("Refresh the disk list")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Restore Image…") {
                        operations.beginRestoreImageSetup(availableDisks: model.disks)
                    }
                    Button("Create Bootable USB…") {
                        operations.beginCreateBootableUSBSetup(availableDisks: model.disks)
                    }
                    Divider()
                    if getuid() != 0 {
                        Button("Run as Administrator…") {
                            showAdminSheet = true
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .help("More actions")
            }
        }
        .sheet(isPresented: $showAdminSheet) { AdminPasswordSheet() }
        .sheet(item: Binding(
            get: { operations.eraseSetup },
            set: { if $0 == nil { operations.cancelEraseSetup() } }
        )) { setup in
            EraseSetupView(
                setup: setup,
                onConfirm: { operations.confirmEraseSetup() },
                onCancel: { operations.cancelEraseSetup() }
            )
        }
        .sheet(item: Binding(
            get: { operations.cloneSetup },
            set: { if $0 == nil { operations.cancelCloneSetup() } }
        )) { setup in
            CloneSetupView(
                setup: setup,
                onConfirm: { operations.confirmCloneSetup() },
                onCancel: { operations.cancelCloneSetup() }
            )
        }
        .sheet(item: Binding(
            get: { operations.active },
            set: { if $0 == nil { operations.dismiss() } }
        )) { active in
            OperationSheetView(
                operation: active,
                onExecute: { operations.execute() },
                onCancelRunning: { operations.cancelRunningOperation() },
                onDismiss: { operations.dismiss() }
            )
        }
        .alert(
            "Could not start the operation",
            isPresented: Binding(
                get: { operations.setupError != nil },
                set: { if !$0 { operations.clearSetupError() } }
            ),
            presenting: operations.setupError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .overlay {
            if model.isLoading { ProgressView() }
        }
        .task { await model.refresh() }
        .task {
            // Once per launch is enough — logs rotate daily, so pruning more
            // often than that has no effect. Applies Settings ▸ Logs' "keep
            // the last N files" preference, which previously had no code
            // actually enforcing it.
            let keepCount = settings.maxLogFilesToKeep
            await Task.detached { LoggerService().pruneOldLogs(keeping: keepCount) }.value
        }
        .task {
            // Scheduled-backup checker: only runs while the app is open (see
            // `ScheduledBackup`'s doc comment on this limitation). Checking
            // every 15 minutes is frequent enough for hour-granularity
            // schedules without meaningfully burning CPU/battery.
            while !Task.isCancelled {
                await scheduler.runDueSchedules(currentDisks: model.disks)
                try? await Task.sleep(for: .seconds(900))
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if let message = model.errorMessage {
            ContentUnavailableView(
                "Could not read disks",
                systemImage: "externaldrive.badge.exclamationmark",
                description: Text(message)
            )
        } else if model.disks.isEmpty && !model.isLoading {
            ContentUnavailableView(
                "No disks",
                systemImage: "externaldrive",
                description: Text("Nothing was returned by diskutil.")
            )
        } else {
            switch selection {
            case .disk(let id):
                if let disk = model.disks.first(where: { $0.id == id }) {
                    List { DiskSection(disk: disk, model: model, operations: operations) }
                        .navigationTitle(disk.model ?? disk.id)
                } else {
                    DashboardView(model: model)
                }
            case .dashboard, nil:
                DashboardView(model: model)
            }
        }
    }
}

private struct DiskRow: View {
    let disk: Disk

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: disk.isSystemDisk ? "internaldrive.fill" : "externaldrive")
                .foregroundStyle(disk.isSystemDisk ? .secondary : .primary)
            VStack(alignment: .leading) {
                Text(disk.model ?? disk.id).font(.body)
                Text("\(disk.id) · \(DisksViewModel.humanSize(disk.size))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if disk.isSystemDisk {
                Text("SYSTEM").font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(disk.model ?? disk.id), \(disk.id), \(DisksViewModel.humanSize(disk.size))"
                + (disk.isSystemDisk ? ", system disk" : "")
        )
    }
}

private struct DiskSection: View {
    let disk: Disk
    let model: DisksViewModel
    let operations: DiskOperationsViewModel

    var body: some View {
        Section(disk.model ?? disk.id) {
            SMARTRow(diskID: disk.id, model: model)
            DiskOperationsRow(disk: disk, allDisks: model.disks, operations: operations)
            ForEach(disk.partitions) { p in
                PartitionRow(partition: p, model: model)
            }
            if disk.partitions.isEmpty {
                Text("No partitions").foregroundStyle(.secondary)
            }
        }
        .alert(
            "Could not complete the action",
            isPresented: Binding(
                get: { model.volumeActionError != nil },
                set: { if !$0 { model.clearVolumeActionError() } }
            ),
            presenting: model.volumeActionError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
    }
}

private struct SMARTRow: View {
    let diskID: String
    let model: DisksViewModel

    var body: some View {
        HStack(spacing: 8) {
            let info = model.smartInfoByDisk[diskID]
            Image(systemName: "heart.text.square")
                .foregroundStyle(color(for: info?.status))
            Text("SMART: \(info?.status.rawValue ?? "Reading…")")
                .foregroundStyle(.secondary)
            if let info, info.hasDetailedAttributes {
                Spacer()
                if let temp = info.temperatureCelsius {
                    Text("\(temp)°C").foregroundStyle(.secondary)
                }
                if let hours = info.powerOnHours {
                    Text("· \(hours)h").foregroundStyle(.secondary)
                }
            } else if let info, !info.smartctlAvailable {
                Spacer()
                Text("Install smartmontools for details")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .task { await model.loadSMARTInfo(for: diskID) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SMART status: \(model.smartInfoByDisk[diskID]?.status.rawValue ?? "reading")")
    }

    private func color(for status: SMARTStatus?) -> Color {
        switch status {
        case .verified: return .green
        case .failing: return .red
        case .notSupported, .unknown, nil: return .secondary
        }
    }
}

/// Whole-disk operations (spec §4.4/§4.8/§4.9/§4.10) — each shows its exact
/// command before running (`OperationSheetView`); Secure Erase additionally
/// requires the red confirmation screen first (`EraseSetupView`).
private struct DiskOperationsRow: View {
    let disk: Disk
    let allDisks: [Disk]
    let operations: DiskOperationsViewModel
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 16) {
                Button {
                    operations.beginCreateImage(disk: disk, compression: settings.defaultCompression)
                } label: {
                    Label("Create Image…", systemImage: "square.and.arrow.down")
                }
                .help("Create a raw image of this disk and checksum it (compression: \(settings.defaultCompression.rawValue))")
                .accessibilityLabel("Create Image")

                Button {
                    operations.beginBackupGPT(disk: disk)
                } label: {
                    Label("Backup GPT…", systemImage: "doc.badge.gearshape")
                }
                .help("Save the disk's partition table for later restoration")
                .accessibilityLabel("Backup GPT")

                Button {
                    operations.beginCloneDiskSetup(source: disk, availableDisks: allDisks)
                } label: {
                    Label("Clone to…", systemImage: "doc.on.doc")
                }
                .help("Copy this disk to another disk, overwriting it (source is read-only, even the system disk)")
                .accessibilityLabel("Clone to another disk")

                Button {
                    operations.beginVerifyDisk(diskID: disk.id, label: disk.model ?? disk.id)
                } label: {
                    Label("Verify Disk", systemImage: "checkmark.seal")
                }
                .help("Read-only check for filesystem issues")
                .accessibilityLabel("Verify Disk")

                Button {
                    operations.beginRepairDisk(diskID: disk.id, label: disk.model ?? disk.id)
                } label: {
                    Label("Repair Disk", systemImage: "wrench.and.screwdriver")
                }
                .help("Actively fix filesystem issues (writes to the disk)")
                .accessibilityLabel("Repair Disk")
            }

            if !disk.isSystemDisk {
                Button(role: .destructive) {
                    operations.beginSecureEraseSetup(disk: disk)
                } label: {
                    Label("Secure Erase…", systemImage: "trash.fill")
                }
                .help("Permanently erase all data on this disk")
                .foregroundStyle(.red)
                .accessibilityLabel("Secure Erase")
            }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }
}

private struct PartitionRow: View {
    let partition: Partition
    let model: DisksViewModel
    @State private var busy = false
    @State private var showBenchmark = false

    var body: some View {
        HStack {
            HStack {
                Text(partition.volumeName ?? partition.content ?? partition.id)
                    .foregroundStyle(partition.isOSInternal ? .tertiary : .primary)
                if partition.isOSInternal {
                    Text("system").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Text(DisksViewModel.humanSize(partition.size))
                    .foregroundStyle(.secondary)
                if partition.isMounted {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7)).foregroundStyle(.green)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(partition.volumeName ?? partition.content ?? partition.id), "
                    + "\(DisksViewModel.humanSize(partition.size))"
                    + (partition.isMounted ? ", mounted" : ", not mounted")
                    + (partition.isOSInternal ? ", internal system volume" : "")
            )

            if partition.isMounted, let mountPoint = partition.mountPoint {
                Button {
                    showBenchmark = true
                } label: {
                    Image(systemName: "speedometer")
                }
                .buttonStyle(.borderless)
                .help("Benchmark this volume")
                .accessibilityLabel("Benchmark \(partition.volumeName ?? partition.id)")
                .sheet(isPresented: $showBenchmark) {
                    BenchmarkView(volumeLabel: partition.volumeName ?? partition.id, mountPoint: mountPoint)
                }
            }

            if busy {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Working")
            } else {
                Button {
                    busy = true
                    Task {
                        if partition.isMounted {
                            await model.unmount(partition.id)
                        } else {
                            await model.mount(partition.id)
                        }
                        busy = false
                    }
                } label: {
                    Image(systemName: partition.isMounted ? "eject" : "arrow.up.bin")
                }
                .buttonStyle(.borderless)
                .help(partition.isMounted ? "Unmount" : "Mount")
                .accessibilityLabel(
                    partition.isMounted
                        ? "Unmount \(partition.volumeName ?? partition.id)"
                        : "Mount \(partition.volumeName ?? partition.id)"
                )
            }
        }
    }
}
