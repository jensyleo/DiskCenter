// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import Observation
import SwiftUI

@MainActor
@Observable
final class BenchmarkViewModel {
    private(set) var result: BenchmarkResult?
    private(set) var isRunning = false
    private(set) var errorMessage: String?

    func run(mountPoint: String) async {
        isRunning = true
        errorMessage = nil
        result = nil
        defer { isRunning = false }
        do {
            result = try await Task.detached { try BenchmarkService().run(mountPoint: mountPoint) }.value
        } catch {
            errorMessage = "Could not write a test file here, even in your home folder. "
                + "Check that this volume has free space and isn't read-only."
        }
    }
}

/// Spec §4.12: sequential read/write and random-read (IOPS) benchmark,
/// measured with a temp file on the volume's own mount point — never the raw
/// device — so a benchmark can never be destructive (see `BenchmarkService`).
struct BenchmarkView: View {
    let volumeLabel: String
    let mountPoint: String
    @State private var model = BenchmarkViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Benchmark: \(volumeLabel)").font(.headline)
            Text(mountPoint).font(.caption).foregroundStyle(.secondary)

            if model.isRunning {
                ProgressView("Measuring sequential write, sequential read, and random read…")
            } else if let result = model.result {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("Sequential Write").foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", result.sequentialWriteMBPerSecond)) MB/s")
                    }
                    GridRow {
                        Text("Sequential Read").foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", result.sequentialReadMBPerSecond)) MB/s")
                    }
                    GridRow {
                        Text("Random Read").foregroundStyle(.secondary)
                        Text("\(String(format: "%.1f", result.randomReadMBPerSecond)) MB/s")
                    }
                    GridRow {
                        Text("Random Read IOPS").foregroundStyle(.secondary)
                        Text("\(Int(result.randomReadIOPS))")
                    }
                }
            } else if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Close", role: .cancel) { dismiss() }
                    .disabled(model.isRunning)
                Button(model.result == nil ? "Run Benchmark" : "Run Again") {
                    Task { await model.run(mountPoint: mountPoint) }
                }
                .disabled(model.isRunning)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
