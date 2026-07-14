// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

/// Thread-safe accumulator for progress callbacks arriving off the test's task.
private final class ProgressCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DDProgress] = []
    func append(_ item: DDProgress) { lock.withLock { items.append(item) } }
    var all: [DDProgress] { lock.withLock { items } }
}

@Suite struct DDServiceTests {
    @Test func buildsArgumentsAsSeparatedTokensNeverAConcatenatedString() {
        let service = DDService()
        let request = DDRequest(inputPath: "/dev/rdisk4", outputPath: "/tmp/out.img", blockSize: "4m", conv: ["fsync"])
        let args = service.arguments(for: request)
        #expect(args == ["if=/dev/rdisk4", "of=/tmp/out.img", "bs=4m", "conv=fsync", "status=progress"])
    }

    @Test func limitBytesOverridesToSectorAlignedCount() {
        let service = DDService()
        let request = DDRequest(inputPath: "/dev/rdisk4", outputPath: "/tmp/gpt.bin", limitBytes: 1_048_576)
        let args = service.arguments(for: request)
        #expect(args.contains("bs=512"))
        #expect(args.contains("count=2048")) // 1 MiB / 512
        #expect(!args.contains { $0.hasPrefix("bs=4m") })
    }

    @Test func commandPreviewMatchesRealArguments() {
        let service = DDService()
        let request = DDRequest(inputPath: "/dev/rdisk4", outputPath: "/tmp/out.img")
        let preview = service.commandPreview(request)
        #expect(preview.contains("if=/dev/rdisk4"))
        #expect(preview.contains("of=/tmp/out.img"))
        #expect(preview.hasSuffix("status=progress"))
    }

    @Test func parsesRealBSDStatusProgressLine() throws {
        let progress = DDService.parseProgressLine("1234567890 bytes transferred in 12.345 secs (99999999 bytes/sec)")
        let parsed = try #require(progress)
        #expect(parsed.bytesTransferred == 1_234_567_890)
        #expect(parsed.secondsElapsed == 12.345)
        #expect(parsed.bytesPerSecond == 99_999_999)
    }

    @Test func ignoresUnrelatedLines() {
        #expect(DDService.parseProgressLine("dd: some error message") == nil)
        #expect(DDService.parseProgressLine("") == nil)
    }

    /// End-to-end against a REAL `dd` process copying a real (small) file —
    /// exercises the full streaming + progress-parsing + completion path
    /// without touching any actual disk device, per the spec's ask for
    /// simulation/logic testable in CI against real files, not just mocks.
    @Test func copiesARealFileEndToEnd() async throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destURL)
        }
        let payload = Data((0..<200_000).map { UInt8($0 % 256) })
        try payload.write(to: sourceURL)

        let service = DDService()
        let progressUpdates = ProgressCollector()
        let result = try await service.run(
            DDRequest(inputPath: sourceURL.path, outputPath: destURL.path, blockSize: "4096"),
            progress: { progressUpdates.append($0) }
        )

        #expect(result.succeeded)
        let copied = try Data(contentsOf: destURL)
        #expect(copied == payload)
    }

    @Test func cancellationTerminatesTheProcess() async throws {
        // A slow copy from /dev/zero so there's time to cancel before it
        // would naturally finish (bs is tiny, forcing many iterations).
        let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: destURL) }

        let service = DDService()
        let token = ProcessCancellationToken()
        let request = DDRequest(inputPath: "/dev/zero", outputPath: destURL.path, blockSize: "1", limitBytes: nil)

        let task = Task {
            try await service.run(request, token: token, progress: { _ in })
        }
        try await Task.sleep(for: .milliseconds(100))
        token.cancel()

        let result = try await task.value
        #expect(!result.succeeded)
    }
}
