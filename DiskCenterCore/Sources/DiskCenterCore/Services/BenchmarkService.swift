// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Sequential/random read-write benchmark (spec §4.12). Deliberately measures
/// against a temporary REGULAR FILE on the target volume's mount point rather
/// than the raw device (`/dev/rdiskN`) — this still reflects the underlying
/// disk's real performance characteristics (the classic approach used by
/// tools like AmorphousDiskMark/Blackmagic Disk Speed Test) without ever
/// writing to partition data, so a benchmark can never be destructive.
public struct BenchmarkService: Sendable {
    private static let sequentialFileSize = 256 * 1024 * 1024 // 256 MiB
    private static let chunkSize = 4 * 1024 * 1024 // 4 MiB
    private static let randomReadOps = 200
    private static let randomBlockSize = 4 * 1024 // 4 KiB

    public init() {}

    /// Runs sequential write, sequential read, and random-read (IOPS) passes
    /// using a temp file under `mountPoint`, then deletes it.
    ///
    /// Some internal APFS volumes (e.g. `/System/Volumes/Data` itself, as
    /// opposed to a folder inside it) have a root that isn't writable by a
    /// normal user even though the volume clearly is — only `diskutil`/root
    /// can write directly there. When that happens, this falls back to the
    /// user's home directory: it physically lives on the same disk, so the
    /// benchmark still characterizes the intended volume correctly.
    public func run(mountPoint: String) throws -> BenchmarkResult {
        let testFile = try Self.testFileURL(preferredMountPoint: mountPoint)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let writeMBps = try Self.measureSequentialWrite(to: testFile, totalBytes: Self.sequentialFileSize)
        let readMBps = try Self.measureSequentialRead(from: testFile)
        let (randomMBps, iops) = try Self.measureRandomRead(from: testFile)

        return BenchmarkResult(
            sequentialWriteMBPerSecond: writeMBps,
            sequentialReadMBPerSecond: readMBps,
            randomReadMBPerSecond: randomMBps,
            randomReadIOPS: iops
        )
    }

    static func testFileURL(preferredMountPoint: String) throws -> URL {
        let name = ".diskcenter-benchmark-\(UUID().uuidString)"
        let preferred = URL(fileURLWithPath: preferredMountPoint).appendingPathComponent(name)
        if FileManager.default.createFile(atPath: preferred.path, contents: nil) {
            return preferred
        }
        let fallback = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(name)
        guard FileManager.default.createFile(atPath: fallback.path, contents: nil) else {
            throw BenchmarkServiceError.couldNotCreateTestFile(preferred.path)
        }
        return fallback
    }

    static func measureSequentialWrite(to url: URL, totalBytes: Int) throws -> Double {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw BenchmarkServiceError.couldNotCreateTestFile(url.path)
        }
        guard let handle = FileHandle(forWritingAtPath: url.path) else {
            throw BenchmarkServiceError.couldNotCreateTestFile(url.path)
        }
        defer { try? handle.close() }

        let chunk = Data(repeating: 0xAB, count: chunkSize)
        let start = DispatchTime.now()
        var written = 0
        while written < totalBytes {
            // `FileHandle.write(_:)` (the legacy, non-throwing overload) can
            // raise an uncatchable Objective-C exception on failure — e.g. if
            // the volume fills up mid-benchmark — crashing the whole app.
            // `write(contentsOf:)` is the modern Swift-throwing equivalent.
            try handle.write(contentsOf: chunk)
            written += chunk.count
        }
        try handle.synchronize()
        let elapsed = secondsSince(start)
        return megabytesPerSecond(bytes: written, seconds: elapsed)
    }

    static func measureSequentialRead(from url: URL) throws -> Double {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw BenchmarkServiceError.couldNotCreateTestFile(url.path)
        }
        defer { try? handle.close() }

        let start = DispatchTime.now()
        var totalRead = 0
        while let data = try handle.read(upToCount: chunkSize), !data.isEmpty {
            totalRead += data.count
        }
        let elapsed = secondsSince(start)
        return megabytesPerSecond(bytes: totalRead, seconds: elapsed)
    }

    static func measureRandomRead(from url: URL) throws -> (megabytesPerSecond: Double, iops: Double) {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw BenchmarkServiceError.couldNotCreateTestFile(url.path)
        }
        defer { try? handle.close() }
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let fileSize, fileSize > randomBlockSize else { return (0, 0) }

        let start = DispatchTime.now()
        var totalRead = 0
        for _ in 0..<randomReadOps {
            let offset = UInt64.random(in: 0...(UInt64(fileSize - randomBlockSize)))
            try handle.seek(toOffset: offset)
            if let data = try handle.read(upToCount: randomBlockSize) {
                totalRead += data.count
            }
        }
        let elapsed = secondsSince(start)
        let mbps = megabytesPerSecond(bytes: totalRead, seconds: elapsed)
        let iops = elapsed > 0 ? Double(randomReadOps) / elapsed : 0
        return (mbps, iops)
    }

    private static func secondsSince(_ start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }

    private static func megabytesPerSecond(bytes: Int, seconds: Double) -> Double {
        guard seconds > 0 else { return 0 }
        return (Double(bytes) / 1_048_576) / seconds
    }
}
