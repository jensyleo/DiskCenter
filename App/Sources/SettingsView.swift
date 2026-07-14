// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let availableDisks: [Disk]
    @State private var scheduler = ScheduledBackupsViewModel()
    @State private var showAddSchedule = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            backupsTab
                .tabItem { Label("Backups", systemImage: "externaldrive.badge.checkmark") }
            logsTab
                .tabItem { Label("Logs", systemImage: "doc.text") }
        }
        .frame(width: 460)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.rawValue).tag(appearance)
                }
            }
            TextField("Default block size", text: $settings.defaultBlockSize)
                .help("Passed to dd's bs= parameter, e.g. 4m")
            Toggle("Compute checksum automatically after Create Image", isOn: $settings.autoChecksumOnImage)
            Picker("Default compression", selection: $settings.defaultCompression) {
                ForEach(CompressionKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
        }
        .padding()
    }

    private var backupsTab: some View {
        Form {
            HStack {
                TextField("Default backup folder", text: $settings.defaultBackupFolderPath)
                Button("Choose…") {
                    if let url = SavePanel.pickFolder() {
                        settings.defaultBackupFolderPath = url.path
                    }
                }
            }

            Section("Scheduled GPT Backups") {
                Text("Runs only while DiskCenter is open — there is no background/launchd support yet.")
                    .font(.caption).foregroundStyle(.secondary)
                if scheduler.schedules.isEmpty {
                    Text("No schedules yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(scheduler.schedules) { schedule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(schedule.diskLabel)
                                Text("Every \(schedule.intervalHours)h → \(schedule.destinationFolder.lastPathComponent)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                scheduler.remove(id: schedule.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add Schedule…") { showAddSchedule = true }
                    .disabled(availableDisks.isEmpty)
            }
        }
        .padding()
        .sheet(isPresented: $showAddSchedule) {
            AddScheduleView(availableDisks: availableDisks) { diskID, label, folder, hours in
                scheduler.add(diskID: diskID, diskLabel: label, destinationFolder: folder, intervalHours: hours)
            }
        }
    }

    private var logsTab: some View {
        Form {
            Stepper("Keep the last \(settings.maxLogFilesToKeep) log files", value: $settings.maxLogFilesToKeep, in: 1...365)
            Text("Logs are stored in ~/Library/Application Support/DiskCenter/logs/ and are tamper-evident (hash-chained) for chain-of-custody purposes.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct AddScheduleView: View {
    let availableDisks: [Disk]
    let onAdd: (String, String, URL, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDisk: Disk?
    @State private var destinationFolder: URL?
    @State private var intervalHours = 24

    init(availableDisks: [Disk], onAdd: @escaping (String, String, URL, Int) -> Void) {
        self.availableDisks = availableDisks
        self.onAdd = onAdd
        _selectedDisk = State(initialValue: availableDisks.first)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Scheduled Backup").font(.headline)

            Picker("Disk", selection: $selectedDisk) {
                ForEach(availableDisks) { disk in
                    Text(disk.model ?? disk.id).tag(Optional(disk))
                }
            }

            HStack {
                Text(destinationFolder?.path ?? "Choose a folder…").foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { destinationFolder = SavePanel.pickFolder() }
            }

            Stepper("Every \(intervalHours) hours", value: $intervalHours, in: 1...720)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add") {
                    guard let disk = selectedDisk, let folder = destinationFolder else { return }
                    onAdd(disk.id, disk.model ?? disk.id, folder, intervalHours)
                    dismiss()
                }
                .disabled(selectedDisk == nil || destinationFolder == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
