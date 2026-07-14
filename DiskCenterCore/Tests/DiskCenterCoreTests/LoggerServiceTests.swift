// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct LoggerServiceTests {
    @Test func appendsLinesToTodaysFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logger = LoggerService(baseDirectory: tempDir)
        logger.log("Refreshed disk list")
        logger.log("Mounted disk4s1")

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(files.count == 1)

        let content = try String(contentsOf: files[0], encoding: .utf8)
        let lines = content.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines[0].contains("Refreshed disk list"))
        #expect(lines[1].contains("Mounted disk4s1"))
    }

    @Test func chainVerifiesIntactAfterMultipleAppends() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logger = LoggerService(baseDirectory: tempDir)
        logger.log("First event")
        logger.log("Second event")
        logger.log("Third event")

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        #expect(logger.verifyIntegrity(fileURL: files[0]))
    }

    @Test func missingFileIsVacuouslyValid() {
        let logger = LoggerService(baseDirectory: FileManager.default.temporaryDirectory)
        let nonExistent = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).log")
        #expect(logger.verifyIntegrity(fileURL: nonExistent))
    }

    @Test func detectsATamperedLine() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logger = LoggerService(baseDirectory: tempDir)
        logger.log("Verified disk0: passed")
        logger.log("Erased disk4 at level 0: succeeded")

        let fileURL = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)[0]
        #expect(logger.verifyIntegrity(fileURL: fileURL))

        // Tamper: rewrite the file with the first line's message altered but
        // its stored "previous hash" token left untouched — as if someone
        // hand-edited the log to hide what really happened.
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        content = content.replacingOccurrences(of: "passed", with: "TAMPERED")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(!logger.verifyIntegrity(fileURL: fileURL))
    }

    @Test func detectsADeletedLine() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logger = LoggerService(baseDirectory: tempDir)
        logger.log("Event A")
        logger.log("Event B")
        logger.log("Event C")

        let fileURL = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)[0]
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        // Remove the middle line — the chain from "Event C" onward no longer
        // matches the hash of its (now different) predecessor.
        let withDeletion = ([lines[0], lines[2]]).joined(separator: "\n") + "\n"
        try withDeletion.write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(!logger.verifyIntegrity(fileURL: fileURL))
    }
}

extension LoggerServiceTests {
    @Test func pruneOldLogsKeepsOnlyTheNewestFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let names = ["2026-01-01.log", "2026-01-02.log", "2026-01-03.log", "2026-01-04.log"]
        for name in names {
            try "line\n".write(to: tempDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        LoggerService(baseDirectory: tempDir).pruneOldLogs(keeping: 2)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path).sorted()
        #expect(remaining == ["2026-01-03.log", "2026-01-04.log"])
    }

    @Test func pruneOldLogsDoesNothingWhenUnderTheLimit() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "line\n".write(to: tempDir.appendingPathComponent("2026-01-01.log"), atomically: true, encoding: .utf8)

        LoggerService(baseDirectory: tempDir).pruneOldLogs(keeping: 30)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(remaining.count == 1)
    }

    @Test func pruneOldLogsIgnoresNonLogFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "x".write(to: tempDir.appendingPathComponent(".DS_Store"), atomically: true, encoding: .utf8)
        try "line\n".write(to: tempDir.appendingPathComponent("2026-01-01.log"), atomically: true, encoding: .utf8)

        LoggerService(baseDirectory: tempDir).pruneOldLogs(keeping: 0)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(remaining == [".DS_Store"])
    }
}
