// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import DiskCenterCore
import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Full preferences (spec §8): default block size, auto-checksum, theme,
/// backup path, max logs to keep. Backed directly by `UserDefaults` via
/// `didSet`, matching the pattern used in the user's other apps.
@MainActor
@Observable
final class AppSettings {
    var defaultBlockSize: String {
        didSet { UserDefaults.standard.set(defaultBlockSize, forKey: Keys.blockSize) }
    }
    var autoChecksumOnImage: Bool {
        didSet { UserDefaults.standard.set(autoChecksumOnImage, forKey: Keys.autoChecksum) }
    }
    var appearance: AppAppearance {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    var defaultBackupFolderPath: String {
        didSet { UserDefaults.standard.set(defaultBackupFolderPath, forKey: Keys.backupFolder) }
    }
    var maxLogFilesToKeep: Int {
        didSet { UserDefaults.standard.set(maxLogFilesToKeep, forKey: Keys.maxLogFiles) }
    }
    var defaultCompression: CompressionKind {
        didSet { UserDefaults.standard.set(defaultCompression.rawValue, forKey: Keys.compression) }
    }

    private enum Keys {
        static let blockSize = "DiskCenter.Settings.BlockSize"
        static let autoChecksum = "DiskCenter.Settings.AutoChecksum"
        static let appearance = "DiskCenter.Settings.Appearance"
        static let backupFolder = "DiskCenter.Settings.BackupFolder"
        static let maxLogFiles = "DiskCenter.Settings.MaxLogFiles"
        static let compression = "DiskCenter.Settings.Compression"
    }

    init() {
        let defaults = UserDefaults.standard
        defaultBlockSize = defaults.string(forKey: Keys.blockSize) ?? "4m"
        autoChecksumOnImage = defaults.object(forKey: Keys.autoChecksum) as? Bool ?? true
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        defaultBackupFolderPath = defaults.string(forKey: Keys.backupFolder)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory()
        maxLogFilesToKeep = defaults.object(forKey: Keys.maxLogFiles) as? Int ?? 30
        defaultCompression = CompressionKind(rawValue: defaults.string(forKey: Keys.compression) ?? "") ?? .none
    }
}
