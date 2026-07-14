// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Image compression options (spec §4.4/Phase 4). `gzip` ships with macOS;
/// `xz`/`zstd` are optional external tools (like `smartctl`) invoked as
/// separate processes if the user installed them via Homebrew — never
/// bundled, so their license terms don't extend to this app's binary.
public enum CompressionKind: String, Sendable, CaseIterable, Identifiable {
    case none = "None"
    case gzip = "gzip"
    case xz = "xz"
    case zstd = "zstd"

    public var id: String { rawValue }

    public var fileExtensionSuffix: String {
        switch self {
        case .none: return ""
        case .gzip: return ".gz"
        case .xz: return ".xz"
        case .zstd: return ".zst"
        }
    }
}
