// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Lets a caller cancel an in-flight long-running `Process` (a `dd` copy, a
/// `diskutil verifyDisk`…) before it finishes. Thread-safe: output is drained
/// on a background queue, so cancellation can arrive from any thread.
public final class ProcessCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    func attach(_ process: Process) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
        if cancelled { process.terminate() }
    }

    /// Sends SIGTERM to the running `dd` process, if any.
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        process?.terminate()
    }
}

/// Builds and runs `dd` invocations. Arguments are always separate array
/// elements — `commandPreview` renders the equivalent shell text ONLY for the
/// spec's "simulation mode" display; execution never goes through a shell.
///
/// Runs its own `Process` rather than going through `ProcessRunner`: an image
/// copy can take minutes, and `ProcessRunner` serializes ALL real launches
/// process-wide (the fix for a `diskutil` concurrency bug) — holding that lock
/// for the whole copy would freeze every other diskutil call (disk list
/// refresh, SMART reads) for the duration. `dd` doesn't share that bug (it
/// doesn't talk to diskarbitrationd), so it's safe to bypass; per-disk
/// exclusivity is instead enforced by `DiskOperationLock` at the call site.
public struct DDService: Sendable {
    private static let ddPath = "/bin/dd"

    public init() {}

    /// The exact command that will run, for the spec's required "show the
    /// command before executing" simulation step. Prefixes `sudo` only when
    /// this process isn't already root, matching what will actually happen.
    public func commandPreview(_ request: DDRequest) -> String {
        let prefix = getuid() == 0 ? "" : "sudo "
        return prefix + "dd " + arguments(for: request).joined(separator: " ")
    }

    func arguments(for request: DDRequest) -> [String] {
        var args = [
            "if=\(request.inputPath)",
            "of=\(request.outputPath)",
        ]
        if let limitBytes = request.limitBytes {
            // Sector-aligned for a partial copy (e.g. GPT backup): count is in
            // 512-byte blocks regardless of the caller's requested block size.
            args.append("bs=512")
            args.append("count=\(limitBytes / 512)")
        } else {
            args.append("bs=\(request.blockSize)")
        }
        if !request.conv.isEmpty {
            args.append("conv=\(request.conv.joined(separator: ","))")
        }
        args.append("status=progress")
        return args
    }

    /// Runs `dd`, invoking `progress` on a background queue as `status=progress`
    /// lines arrive. Cancel via `token.cancel()`.
    public func run(
        _ request: DDRequest,
        token: ProcessCancellationToken = ProcessCancellationToken(),
        progress: @escaping @Sendable (DDProgress) -> Void
    ) async throws -> DDResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.ddPath)
            process.arguments = arguments(for: request)

            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()

            let buffer = LineBuffer()
            let lastProgressBox = LastProgressBox()
            let coordinator = ProcessCompletionCoordinator()

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    handle.readabilityHandler = nil
                    coordinator.setPipeClosed()
                    return
                }
                for line in buffer.append(data) {
                    if let parsed = Self.parseProgressLine(line) {
                        progress(parsed)
                        lastProgressBox.value = parsed
                    }
                }
            }

            process.terminationHandler = { proc in
                coordinator.setExitCode(proc.terminationStatus)
            }

            coordinator.onComplete { exitCode in
                for line in buffer.flush() {
                    if let parsed = Self.parseProgressLine(line) {
                        progress(parsed)
                        lastProgressBox.value = parsed
                    }
                }
                continuation.resume(returning: DDResult(
                    bytesTransferred: lastProgressBox.value?.bytesTransferred ?? 0,
                    succeeded: exitCode == 0,
                    errorOutput: buffer.fullText
                ))
            }

            do {
                try process.run()
                token.attach(process)
            } catch {
                continuation.resume(throwing: DDServiceError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Parses one `status=progress` line, e.g.
    /// `1234567890 bytes transferred in 12.345 secs (99999999 bytes/sec)`.
    static func parseProgressLine(_ line: String) -> DDProgress? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.count >= 5, tokens[1] == "bytes", tokens[2] == "transferred" else { return nil }
        guard let bytes = Int64(tokens[0]) else { return nil }
        guard let seconds = Double(tokens[4]) else { return nil }

        // The rate is split across two tokens by the space inside the
        // parenthetical, e.g. "(99999999" "bytes/sec)" — find the one that
        // opens the parenthesis, not the one that closes it.
        var bytesPerSecond: Double?
        if let rateToken = tokens.first(where: { $0.hasPrefix("(") }) {
            let digits = rateToken.drop { $0 == "(" }.prefix { $0.isNumber || $0 == "." }
            bytesPerSecond = Double(digits)
        }
        return DDProgress(bytesTransferred: bytes, secondsElapsed: seconds, bytesPerSecond: bytesPerSecond)
    }
}

/// Thread-safe holder for the most recent parsed progress line.
private final class LastProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: DDProgress?
    var value: DDProgress? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// Accumulates raw bytes and splits them into complete lines on `\r` or `\n` —
/// `dd`'s live progress uses `\r` to redraw in place, only the final summary
/// ends with `\n`.
private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var all = ""

    /// Appends `data` and returns any newly completed lines.
    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let text = String(decoding: data, as: UTF8.self)
        all += text
        pending += text
        var completed: [String] = []
        while let index = pending.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
            completed.append(String(pending[pending.startIndex..<index]))
            pending = String(pending[pending.index(after: index)...])
        }
        return completed
    }

    /// Returns any trailing partial line once the process has exited.
    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return [] }
        let last = pending
        pending = ""
        return [last]
    }

    var fullText: String {
        lock.lock(); defer { lock.unlock() }
        return all
    }
}
