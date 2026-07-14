// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A `diskutil secureErase` level. Apple's own `diskutil` man page says
/// multi-pass levels are "no longer considered safe" on modern devices —
/// wear-leveling and block-sparing mean the passes never actually touch the
/// physical cells being "overwritten", so they only wear the flash for no
/// security benefit. `EraseService.allowedLevels(for:)` enforces this: SSD/NVMe
/// only ever offers `.quickZeroFill`.
public enum EraseLevel: Int, Sendable, CaseIterable {
    case quickZeroFill = 0
    case randomFill = 1
    case sevenPass = 2
    case gutmann35Pass = 3
    case threePass = 4

    public var label: String {
        switch self {
        case .quickZeroFill: return "Quick (zero fill)"
        case .randomFill: return "Random fill"
        case .sevenPass: return "7-pass"
        case .gutmann35Pass: return "Gutmann 35-pass"
        case .threePass: return "3-pass"
        }
    }
}

public struct EraseResult: Sendable, Equatable {
    public let diskID: String
    public let succeeded: Bool
    public let log: String
}

public enum EraseServiceError: Error, Sendable, Equatable {
    /// Thrown if a caller somehow requests a multi-pass level for SSD/NVMe
    /// media — defense in depth beyond hiding the option in the UI.
    case levelNotAllowedForMedia(level: EraseLevel, mediaKind: MediaKind)
    case launchFailed(String)
}
