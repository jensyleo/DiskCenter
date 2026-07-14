// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CryptoKit
import Foundation

/// Appends one hash-chained line per event to a daily log file under
/// `~/Library/Application Support/DiskCenter/logs/` (spec §7: tamper-evident
/// logs, relevant if there's a chain of custody in a repair shop). Each line
/// is `<timestamp> <sha256-of-previous-line> <message>`; the first line in a
/// file chains from 64 zeros ("genesis"). Altering, deleting, or reordering
/// any line breaks the chain from that point on — `verifyIntegrity` detects it.
public struct LoggerService: Sendable {
    private static let genesisHash = String(repeating: "0", count: 64)

    private let logsDirectory: URL

    public init(baseDirectory: URL? = nil) {
        if let baseDirectory {
            self.logsDirectory = baseDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            self.logsDirectory = (appSupport ?? URL(fileURLWithPath: NSHomeDirectory()))
                .appendingPathComponent("DiskCenter", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
        }
    }

    /// Appends `message` to today's log file, prefixed with an ISO-8601
    /// timestamp and chained to the previous line's hash. Failures are
    /// swallowed on purpose — logging must never break the feature it's observing.
    public func log(_ message: String) {
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let fileURL = logsDirectory.appendingPathComponent("\(Self.dayFileName(for: Date())).log")

        let previousHash = Self.lastLineHash(in: fileURL)
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(previousHash) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            // `write(_:)` (the legacy, non-throwing overload) can raise an
            // uncatchable Objective-C exception on failure (e.g. a full
            // disk) — a crash is the one thing this doc comment says logging
            // must never cause. `write(contentsOf:)` fails as a catchable
            // Swift error instead.
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    /// Deletes the oldest daily log files beyond `maxCount` (spec §8's "max
    /// number of logs" preference). Log files are named `yyyy-MM-dd.log`, so
    /// sorting by filename is equivalent to sorting by date — no filesystem
    /// metadata (which can be altered by copying/backup) needs trusting.
    public func pruneOldLogs(keeping maxCount: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory, includingPropertiesForKeys: nil
        ) else { return }
        let logFiles = files.filter { $0.pathExtension == "log" }
        guard logFiles.count > maxCount else { return }

        let newestFirst = logFiles.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in newestFirst.dropFirst(maxCount) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    /// Re-derives the hash chain over `fileURL` and confirms every line's
    /// stored "previous hash" matches the hash of the line before it. `true`
    /// (vacuously) if the file doesn't exist yet.
    public func verifyIntegrity(fileURL: URL) -> Bool {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return true }
        return Self.verifyChain(content)
    }

    static func verifyChain(_ content: String) -> Bool {
        var expectedPreviousHash = genesisHash
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let tokens = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard tokens.count >= 2 else { return false }
            guard tokens[1] == expectedPreviousHash else { return false }
            expectedPreviousHash = sha256Hex(String(line))
        }
        return true
    }

    static func lastLineHash(in fileURL: URL) -> String {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return genesisHash }
        guard let last = content.split(separator: "\n", omittingEmptySubsequences: true).last else {
            return genesisHash
        }
        return sha256Hex(String(last))
    }

    private static func sha256Hex(_ string: String) -> String {
        SHA256.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func dayFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
