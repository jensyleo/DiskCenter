// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Result of running an external tool.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: Data
    public let standardError: Data

    public var stdoutString: String { String(decoding: standardOutput, as: UTF8.self) }
    public var stderrString: String { String(decoding: standardError, as: UTF8.self) }
    public var succeeded: Bool { exitCode == 0 }
}

public enum ProcessRunnerError: Error, Sendable {
    case launchFailed(String)
    case nonZeroExit(code: Int32, stderr: String)
}

/// Runs system tools via `Process`, always with separated arguments — never a
/// concatenated shell string. This is the single choke point every service uses
/// to reach `diskutil`, `smartctl`, etc.
///
/// Real invocations are serialized process-wide via `executionLock`. `diskutil
/// info -plist` was found to be flaky under concurrent invocation for different
/// disks — e.g. four simultaneous calls (one per disk, as the SMART UI issues
/// when a disk list first renders) intermittently returned `SMARTStatus: Not
/// Supported` for a disk that reports `Verified` when queried alone. Reproduced
/// with plain concurrent shell invocations of `diskutil` itself (nothing to do
/// with this app's parsing), so the safe fix is to never let two invocations of
/// any external tool overlap.
public struct ProcessRunner: Sendable {
    public typealias Launcher = @Sendable (String, [String]) throws -> ProcessResult

    private static let executionLock = NSLock()
    private let stubbedLauncher: Launcher?

    public init() {
        self.stubbedLauncher = nil
    }

    /// Test-only constructor: bypasses `Process` entirely so services can be
    /// exercised against fixture plists instead of the live system.
    public static func stub(_ launcher: @escaping Launcher) -> ProcessRunner {
        ProcessRunner(stubbedLauncher: launcher)
    }

    private init(stubbedLauncher: @escaping Launcher) {
        self.stubbedLauncher = stubbedLauncher
    }

    /// Launch `launchPath` with `arguments`, capturing stdout, stderr and exit code.
    public func run(_ launchPath: String, _ arguments: [String]) throws -> ProcessResult {
        if let stubbedLauncher {
            return try stubbedLauncher(launchPath, arguments)
        }

        Self.executionLock.lock()
        defer { Self.executionLock.unlock() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }

        // Read fully before waiting to avoid pipe-buffer deadlocks on large output.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: outData,
            standardError: errData
        )
    }
}
