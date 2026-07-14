// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A `dd` invocation described by typed, separated fields — never a
/// concatenated shell string. `DDService` turns this into an argument array.
public struct DDRequest: Sendable, Equatable {
    public let inputPath: String
    public let outputPath: String
    public let blockSize: String
    public let conv: [String]
    /// Byte offset to stop reading at (maps to `count=` in 512-byte sectors when
    /// set) — used by GPT backups to copy only the leading sectors, not the
    /// whole disk.
    public let limitBytes: Int64?

    public init(
        inputPath: String,
        outputPath: String,
        blockSize: String = "4m",
        conv: [String] = ["fsync"],
        limitBytes: Int64? = nil
    ) {
        self.inputPath = inputPath
        self.outputPath = outputPath
        self.blockSize = blockSize
        self.conv = conv
        self.limitBytes = limitBytes
    }
}

/// Live progress parsed from BSD `dd`'s `status=progress` stderr output.
public struct DDProgress: Sendable, Equatable {
    public let bytesTransferred: Int64
    public let secondsElapsed: Double
    public let bytesPerSecond: Double?

    public init(bytesTransferred: Int64, secondsElapsed: Double, bytesPerSecond: Double?) {
        self.bytesTransferred = bytesTransferred
        self.secondsElapsed = secondsElapsed
        self.bytesPerSecond = bytesPerSecond
    }
}

public struct DDResult: Sendable, Equatable {
    public let bytesTransferred: Int64
    public let succeeded: Bool
    public let errorOutput: String

    public init(bytesTransferred: Int64, succeeded: Bool, errorOutput: String) {
        self.bytesTransferred = bytesTransferred
        self.succeeded = succeeded
        self.errorOutput = errorOutput
    }
}

public enum DDServiceError: Error, Sendable {
    case launchFailed(String)
    case cancelled
}
