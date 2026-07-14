// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import SwiftUI

/// Initial screen (spec §4.1): an at-a-glance summary of every connected disk —
/// count, total capacity, filesystem/health overview — before drilling into any
/// one disk via the sidebar.
struct DashboardView: View {
    let model: DisksViewModel

    private var totalCapacity: Int64 {
        model.disks.compactMap(\.size).reduce(0, +)
    }

    private var healthCounts: (verified: Int, failing: Int, other: Int) {
        var verified = 0, failing = 0, other = 0
        for disk in model.disks {
            switch model.smartInfoByDisk[disk.id]?.status {
            case .verified: verified += 1
            case .failing: failing += 1
            default: other += 1
            }
        }
        return (verified, failing, other)
    }

    private var mountedVolumeCount: Int {
        model.disks.flatMap(\.partitions).filter(\.isMounted).count
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                SummaryCard(
                    title: "Disks Connected",
                    value: "\(model.disks.count)",
                    systemImage: "externaldrive.fill",
                    tint: .blue
                )
                SummaryCard(
                    title: "Total Capacity",
                    value: DisksViewModel.humanSize(totalCapacity),
                    systemImage: "chart.pie.fill",
                    tint: .purple
                )
                SummaryCard(
                    title: "Mounted Volumes",
                    value: "\(mountedVolumeCount)",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                )
                healthCard
            }
            .padding(20)

            if healthCounts.failing > 0 {
                Label(
                    "\(healthCounts.failing) disk(s) report a failing SMART status — back up their data.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
                .padding(.horizontal, 20)
                .accessibilityElement(children: .combine)
            }

            RecentsSection()
                .padding(.horizontal, 20)
                .padding(.top, 8)
        }
        .navigationTitle("Dashboard")
        .task {
            for disk in model.disks {
                await model.loadSMARTInfo(for: disk.id)
            }
        }
    }

    private var healthCard: some View {
        let counts = healthCounts
        let tint: Color = counts.failing > 0 ? .red : (counts.other > 0 ? .secondary : .green)
        let value = counts.failing > 0 ? "\(counts.failing) Failing" : "All Verified"
        return SummaryCard(
            title: "SMART Health",
            value: model.disks.isEmpty ? "—" : value,
            systemImage: "heart.text.square.fill",
            tint: tint
        )
    }
}

/// Spec §7: recently used disks, images, backups, and clones — the most
/// recent operations, most-recent-first.
private struct RecentsSection: View {
    @State private var entries: [HistoryEntry] = []
    private let historyService = HistoryService()

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent Activity").font(.headline)
                    Spacer()
                    Button("Clear") {
                        historyService.clear()
                        entries = []
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.kind.rawValue)
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .leading)
                            Text(entry.label)
                            Spacer()
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .onAppear { entries = historyService.fetchAll() }
        } else {
            EmptyView().onAppear { entries = historyService.fetchAll() }
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(value).font(.title).bold()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}
