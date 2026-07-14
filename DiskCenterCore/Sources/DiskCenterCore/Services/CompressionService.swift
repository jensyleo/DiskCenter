// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Locates compressor executables. `gzip` ships with macOS (`/usr/bin/gzip`);
/// `xz`/`zstd` are optional, detected the same way `SMARTService` detects
/// `smartctl` — first existing candidate path, never bundled.
public struct CompressionService: Sendable {
    private static let candidatePaths: [CompressionKind: [String]] = [
        .gzip: ["/usr/bin/gzip"],
        .xz: ["/opt/homebrew/bin/xz", "/usr/local/bin/xz", "/usr/bin/xz"],
        .zstd: ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd"],
    ]

    public init() {}

    public func path(for kind: CompressionKind) -> String? {
        guard kind != .none else { return nil }
        return (Self.candidatePaths[kind] ?? []).first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public func isAvailable(_ kind: CompressionKind) -> Bool {
        kind == .none || path(for: kind) != nil
    }
}
