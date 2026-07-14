// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import SwiftUI

/// Shows the exact command before it runs (spec §6 "simulation mode"), then
/// live progress, then the result — shared by Create Image, Backup GPT, and
/// Verify Disk.
struct OperationSheetView: View {
    let operation: ActiveOperation
    let onExecute: () -> Void
    let onCancelRunning: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(operation.kind.title).font(.headline)

            switch operation.phase {
            case .confirming:
                confirmingBody
            case .running(let progress):
                runningBody(progress)
            case .succeeded(let message):
                resultBody(message: message, isFailure: false)
            case .failed(let message):
                resultBody(message: message, isFailure: true)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var confirmingBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This is the exact command that will run:")
                .foregroundStyle(.secondary)
            Text(operation.commandPreview)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onDismiss() }
                Button("Execute") { onExecute() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func runningBody(_ progress: DDProgress?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let progress {
                Text(Self.humanSize(progress.bytesTransferred) + " transferred")
                if let rate = progress.bytesPerSecond {
                    Text(Self.humanSize(Int64(rate)) + "/s")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Starting…").foregroundStyle(.secondary)
            }
            ProgressView().progressViewStyle(.linear)

            HStack {
                Spacer()
                Button("Cancel", role: .destructive) { onCancelRunning() }
            }
        }
    }

    private func resultBody(message: String, isFailure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                isFailure ? "Failed" : "Done",
                systemImage: isFailure ? "xmark.circle.fill" : "checkmark.circle.fill"
            )
            .foregroundStyle(isFailure ? .red : .green)

            ScrollView {
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)

            HStack {
                Spacer()
                Button("OK") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private static func humanSize(_ bytes: Int64) -> String {
        DisksViewModel.humanSize(bytes)
    }
}
