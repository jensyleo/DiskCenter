// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import DiskCenterCore

/// Regression test for a real race found while wiring per-disk SMART lookups:
/// four concurrent `diskutil info -plist` calls (one per disk) intermittently
/// returned wrong data for one of them — reproduced with plain concurrent shell
/// invocations of `diskutil` itself. `ProcessRunner` now serializes every real
/// launch; this exercises the *actual* `Process` launch path (not the stub) to
/// prove overlapping invocations never run concurrently.
@Suite struct ProcessRunnerTests {
    @Test func realLaunchesNeverOverlap() async {
        let runner = ProcessRunner()
        let launchCount = 6
        let sleepSeconds = 0.05

        // If launches were concurrent, six 0.05s sleeps would all finish in
        // ~0.05s total. Serialized, they take ~launchCount × sleepSeconds. This
        // proves actual overlap at the OS-process level, not just lock-wait time.
        let start = DispatchTime.now()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<launchCount {
                group.addTask { _ = try? runner.run("/bin/sleep", [String(sleepSeconds)]) }
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

        #expect(elapsed >= Double(launchCount) * sleepSeconds * 0.8)
    }
}
