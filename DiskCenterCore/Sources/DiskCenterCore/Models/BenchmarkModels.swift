// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public struct BenchmarkResult: Sendable, Equatable {
    public let sequentialWriteMBPerSecond: Double
    public let sequentialReadMBPerSecond: Double
    public let randomReadMBPerSecond: Double
    /// 4 KiB random-read operations per second — a rough IOPS figure.
    public let randomReadIOPS: Double

    public init(
        sequentialWriteMBPerSecond: Double,
        sequentialReadMBPerSecond: Double,
        randomReadMBPerSecond: Double,
        randomReadIOPS: Double
    ) {
        self.sequentialWriteMBPerSecond = sequentialWriteMBPerSecond
        self.sequentialReadMBPerSecond = sequentialReadMBPerSecond
        self.randomReadMBPerSecond = randomReadMBPerSecond
        self.randomReadIOPS = randomReadIOPS
    }
}

public enum BenchmarkServiceError: Error, Sendable {
    case couldNotCreateTestFile(String)
}
