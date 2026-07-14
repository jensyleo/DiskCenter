// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
#if canImport(Darwin)
import Darwin
#endif

/// Elevates via the app's own password field: validates the password with
/// `sudo -S -k` (fed through stdin — never in argv or logs) and, if correct,
/// relaunches the app as root, detached and inside the GUI session (so it shows
/// its window). Continuous — no periodic re-prompt.
///
/// This mirrors TCPV4MAC's approach: no paid Developer ID, no `SMAppService`
/// helper (that path requires stable code-signing this app doesn't have). The
/// destructive-operation helper described in the spec (§2, decision #1) is
/// deferred until that constraint changes; until then, elevated reads (e.g.
/// SMART on devices that need it) go through this relaunch instead.
@MainActor
enum SudoRelaunch {
    enum Outcome: Sendable { case success, wrongPassword, failed(String) }

    /// Relaunches as root using the typed password (piped via stdin). If this Mac
    /// has Touch-ID-for-sudo, sudo may still show the biometric prompt first; the
    /// typed password remains a working fallback, so we always ask for it.
    nonisolated static func relaunchAsRoot(password: String) async -> Outcome {
        guard let exec = Bundle.main.executableURL?.path else { return .failed("No executable path.") }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                // -S: read password from stdin · -k: ignore cached creds · -p "":
                // no prompt text. Then launch the app detached as root.
                process.arguments = ["-S", "-k", "-p", "", "/bin/bash", "-c",
                                     "nohup '\(exec)' >/dev/null 2>&1 &"]
                let stdin = Pipe(), stderr = Pipe()
                process.standardInput = stdin
                process.standardError = stderr
                process.standardOutput = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failed(error.localizedDescription)); return
                }
                if let data = (password + "\n").data(using: .utf8) {
                    stdin.fileHandleForWriting.write(data)
                }
                try? stdin.fileHandleForWriting.close()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success)
                    return
                }
                let message = String(decoding: errData, as: UTF8.self)
                let lower = message.lowercased()
                if lower.contains("incorrect password") || lower.contains("try again") || lower.contains("sorry") {
                    continuation.resume(returning: .wrongPassword)
                } else {
                    continuation.resume(returning: .failed(message.isEmpty ? "sudo exited \(process.terminationStatus)." : message))
                }
            }
        }
    }

    /// Quits this (normal-user) instance once the elevated one is confirmed up.
    static func quitWhenRootUp() {
        let selfPID = getpid()
        Task.detached {
            for _ in 0..<12 {
                if rootInstanceRunning(excluding: selfPID) {
                    await MainActor.run { NSApp.terminate(nil) }
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private nonisolated static func rootInstanceRunning(excluding selfPID: Int32) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-x", "DiskCenter"]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let pids = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
        return pids.contains { $0 != selfPID }
    }
}
