// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum SMARTServiceError: Error, Sendable {
    case diskutilFailed(String)
}

/// Reads SMART health, read-only. Two tiers:
/// - Basic status via `diskutil info -plist` (`SMARTStatus`) — always available,
///   no external dependency.
/// - Detailed attributes (temperature, power-on hours, reallocated sectors) via
///   `smartctl` (smartmontools, GPL) if the user installed it via Homebrew.
///   `smartctl` is invoked as an external process, never bundled, so its GPL
///   terms don't extend to this app's binary. Not all USB bridges expose SMART
///   passthrough; when `smartctl` can't reach the device, that limitation is
///   surfaced via `unavailableReason` instead of hidden.
public struct SMARTService: Sendable {
    private let runner: ProcessRunner
    private static let diskutil = "/usr/sbin/diskutil"
    private static let candidateSmartctlPaths = [
        "/opt/homebrew/bin/smartctl", "/usr/local/bin/smartctl", "/usr/sbin/smartctl",
    ]

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Basic status via `diskutil info -plist` — no external dependency.
    public func basicStatus(for diskID: String) throws -> SMARTStatus {
        let result = try runner.run(Self.diskutil, ["info", "-plist", diskID])
        guard result.succeeded else {
            throw SMARTServiceError.diskutilFailed(result.stderrString)
        }
        let plist = try DiskService.parsePlist(result.standardOutput)
        return SMARTStatus(diskutilValue: plist["SMARTStatus"] as? String)
    }

    /// Full SMART info: basic status plus detailed attributes when `smartctl`
    /// is installed and can reach the device.
    public func info(for diskID: String, smartctlPath: String? = nil) throws -> SMARTInfo {
        let status = try basicStatus(for: diskID)
        guard let smartctl = smartctlPath ?? Self.detectSmartctl() else {
            return SMARTInfo(status: status, smartctlAvailable: false)
        }

        let result = try? runner.run(smartctl, ["-a", "/dev/\(diskID)"])
        guard let result else {
            return SMARTInfo(status: status, smartctlAvailable: true, unavailableReason: "Could not launch smartctl.")
        }

        if !result.succeeded, let reason = Self.bridgeUnavailableReason(from: result.stderrString) {
            return SMARTInfo(status: status, smartctlAvailable: true, unavailableReason: reason)
        }

        let output = result.stdoutString
        return SMARTInfo(
            status: status,
            smartctlAvailable: true,
            temperatureCelsius: Self.parseAttributeRawValue(named: "Temperature_Celsius", in: output),
            powerOnHours: Self.parseAttributeRawValue(named: "Power_On_Hours", in: output),
            reallocatedSectorCount: Self.parseAttributeRawValue(named: "Reallocated_Sector_Ct", in: output)
        )
    }

    static func detectSmartctl() -> String? {
        candidateSmartctlPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Extracts a friendly reason when `smartctl` cannot read the device — most
    /// commonly a USB-SATA bridge that doesn't expose SMART passthrough (the spec's
    /// documented limitation: not all bridges support `-d sat,auto` or equivalent).
    static func bridgeUnavailableReason(from stderrText: String) -> String? {
        let lower = stderrText.lowercased()
        guard !stderrText.isEmpty else { return nil }
        if lower.contains("unknown usb bridge") || lower.contains("unable to detect device type")
            || lower.contains("please specify device type") || lower.contains("permission denied") {
            return "This drive's USB bridge doesn't expose SMART data (smartctl couldn't read it)."
        }
        return stderrText.split(separator: "\n").first.map(String.init)
    }

    /// Parses one attribute's RAW_VALUE from standard `smartctl -a` ATA attribute
    /// table output. The table is fixed-column: `ID# NAME FLAG VALUE WORST THRESH
    /// TYPE UPDATED WHEN_FAILED RAW_VALUE`, so the first token of RAW_VALUE is the
    /// 10th whitespace-separated token (index 9). Trailing annotations (e.g.
    /// `33 (Min/Max 20/45)`) are dropped by only reading the leading digits.
    static func parseAttributeRawValue(named attributeName: String, in output: String) -> Int? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains(attributeName) else { continue }
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
            guard tokens.count > 9 else { continue }
            let digits = tokens[9].prefix { $0.isNumber }
            if let value = Int(digits) { return value }
        }
        return nil
    }
}
