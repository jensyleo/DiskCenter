// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

@main
struct DiskCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings = AppSettings()
    /// Owned here (not inside `ContentView`) so the separate `Settings` scene
    /// can also see the live disk list (for the scheduled-backup disk picker).
    @State private var disksModel = DisksViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: disksModel)
                .frame(minWidth: 720, minHeight: 460)
                .preferredColorScheme(settings.appearance.colorScheme)
                .environment(settings)
        }
        .commands {
            // Replace the default About item with a GPLv3-aware panel.
            CommandGroup(replacing: .appInfo) {
                Button("About DiskCenter") { showAboutPanel() }
            }
            CommandGroup(replacing: .help) {
                Button("DiskCenter Help") { showHelp() }
            }
        }

        Settings {
            SettingsView(settings: settings, availableDisks: disksModel.disks)
        }
    }
}

/// When the app runs as root (launched directly by the "Run as Administrator"
/// flow, not via LaunchServices), it doesn't grab focus on its own — pull it to
/// the front a few times once the normal instance has quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard getuid() == 0 else { return }
        for delay in [0.2, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                // `ignoringOtherApps:` is deprecated but it's the only reliable
                // way to force a directly-launched root app to the foreground.
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Quit the whole app when its window is closed (single-window utility, so
    /// lingering with no window serves no purpose).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Standard About panel with a GPLv3 notice + license link in the credits.
/// (Name, version and copyright come from the Info.plist automatically.)
@MainActor
func showAboutPanel() {
    let credits = NSMutableAttributedString(
        string: "A disk administration center for macOS: imaging, cloning, "
            + "verification, SMART and secure erase, built on the system's own "
            + "tools with safety first.\n\n"
            + "Free software under the GNU General Public License v3.0 — with NO WARRANTY.\n",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    )
    credits.append(NSAttributedString(
        string: "gnu.org/licenses/gpl-3.0",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .link: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!,
        ]
    ))
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    NSApp.activate(ignoringOtherApps: true)
}

/// Brief technical help, in the style of the other apps (an NSAlert, not a window).
@MainActor
func showHelp() {
    let alert = NSAlert()
    alert.messageText = "How DiskCenter works"
    alert.informativeText = """
    DiskCenter inspects and manages storage devices through the system's own \
    tools (diskutil, dd, hdiutil…), so operations are transparent and never \
    a memorized command — every action shows its exact command before running.

    • Read-only: Dashboard, disk explorer, SMART, mount/unmount.
    • Safe writes: Create Image (with checksum + optional compression), \
    Backup GPT, Benchmark.
    • Destructive (behind a red confirmation screen): Secure Erase, Restore \
    Image, Clone Disk, Create Bootable USB, Repair Disk.
    • The system/boot disk is never offered as a destructive target.
    • Logs are tamper-evident (hash-chained) for chain-of-custody purposes.

    Free software under the GNU GPL v3.0 — with no warranty.
    """
    alert.runModal()
}
