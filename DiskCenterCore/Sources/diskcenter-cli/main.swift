// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.
//
// Verification harness for the core: lists real disks via DiskService so the
// Phase 0 discovery layer can be validated against the live system.

import DiskCenterCore
import Foundation

func humanSize(_ bytes: Int64?) -> String {
    guard let bytes else { return "—" }
    let units = ["B", "KB", "MB", "GB", "TB"]
    var value = Double(bytes)
    var unit = 0
    while value >= 1024, unit < units.count - 1 {
        value /= 1024
        unit += 1
    }
    return String(format: "%.1f %@", value, units[unit])
}

do {
    let disks = try DiskService().listDisks()
    print("Found \(disks.count) disk(s):\n")
    for disk in disks {
        let flags = [
            disk.isInternal ? "internal" : "external",
            disk.isRemovable ? "removable" : nil,
            disk.isSystemDisk ? "SYSTEM" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        print("● \(disk.id)  \(disk.model ?? "Unknown")  \(humanSize(disk.size))  [\(flags)]  media=\(disk.mediaKind.rawValue)")
        for p in disk.partitions {
            let mount = p.mountPoint.map { " → \($0)" } ?? ""
            print("   └ \(p.id)  \(p.volumeName ?? p.content ?? "—")  \(humanSize(p.size))\(mount)")
        }
    }
} catch {
    FileHandle.standardError.write(Data("diskcenter-cli error: \(error)\n".utf8))
    exit(1)
}
