// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import SwiftUI

/// The spec's required red confirmation screen (§6): shows model, capacity,
/// and device path, and requires typing the disk identifier (or "ERASE") to
/// unlock the destructive action. Shown BEFORE the normal simulation/execute
/// flow (`OperationSheetView`), which still runs afterward with the exact
/// command — two independent confirmations, not one.
struct EraseSetupView: View {
    @Bindable var setup: EraseSetup
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This will permanently erase all data")
                        .font(.headline)
                    Text("There is no undo. Make sure you have a backup.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Model").foregroundStyle(.secondary)
                    Text(setup.disk.model ?? setup.disk.id)
                }
                GridRow {
                    Text("Identifier").foregroundStyle(.secondary)
                    Text(setup.disk.id).font(.system(.body, design: .monospaced))
                }
                GridRow {
                    Text("Capacity").foregroundStyle(.secondary)
                    Text(DisksViewModel.humanSize(setup.disk.size))
                }
                GridRow {
                    Text("Device path").foregroundStyle(.secondary)
                    Text(setup.disk.rawDevicePath).font(.system(.caption, design: .monospaced))
                }
            }
            .font(.callout)

            if setup.allowedLevels.count > 1 {
                Picker("Erase method", selection: $setup.selectedLevel) {
                    ForEach(setup.allowedLevels, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
            } else {
                // SSD/NVMe: only the quick zero-fill is offered — never leave
                // multi-pass selectable for flash media (spec §2 decision #3).
                Label(
                    "Quick zero-fill (multi-pass erase is skipped on SSD/NVMe — it wears the flash with no security benefit; use FileVault encryption if you need instant, secure erasure)",
                    systemImage: "info.circle"
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            Text("Type **\(setup.disk.id)** or **ERASE** to confirm:")
                .font(.callout)
            TextField("", text: $setup.confirmationText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if setup.isConfirmed { onConfirm() } }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Erase", role: .destructive) { onConfirm() }
                    .disabled(!setup.isConfirmed)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
