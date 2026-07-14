// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import SwiftUI

/// Red confirmation screen (spec §6) shared by Restore Image, Clone Disk, and
/// Create Bootable USB — all three overwrite an existing destination disk.
/// Shown BEFORE the normal simulation screen (`OperationSheetView`), which
/// still shows the exact command afterward — two independent confirmations.
struct CloneSetupView: View {
    @Bindable var setup: CloneSetup
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This will permanently overwrite the destination disk")
                        .font(.headline)
                    Text("Everything currently on it will be lost. There is no undo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("Source").foregroundStyle(.secondary)
                Text(setup.sourceLabel).font(.system(.body, design: .monospaced))
            }
            .font(.callout)

            Picker("Destination (will be erased)", selection: $setup.selectedDestination) {
                ForEach(setup.availableDestinations) { disk in
                    Text("\(disk.model ?? disk.id) — \(DisksViewModel.humanSize(disk.size)) (\(disk.id))")
                        .tag(Optional(disk))
                }
            }

            if let destination = setup.selectedDestination {
                Text("Device path: \(destination.rawDevicePath)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Type the destination identifier or **ERASE** to confirm:")
                .font(.callout)
            TextField("", text: $setup.confirmationText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if setup.isConfirmed { onConfirm() } }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                Button("Continue", role: .destructive) { onConfirm() }
                    .disabled(!setup.isConfirmed)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}
