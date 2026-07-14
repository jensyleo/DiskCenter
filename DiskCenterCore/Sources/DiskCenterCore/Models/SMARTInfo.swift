// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Coarse SMART health, as reported by `diskutil info` (`SMARTStatus`). Always
/// available for internal disks with no external dependency.
public enum SMARTStatus: String, Sendable, Codable {
    case verified = "Verified"
    case failing = "Failing"
    case notSupported = "Not Supported"
    case unknown

    public init(diskutilValue: String?) {
        switch diskutilValue {
        case "Verified": self = .verified
        case "Failing": self = .failing
        case "Not Supported", nil: self = .notSupported
        default: self = .unknown
        }
    }
}

/// SMART information for a disk. `status` comes from `diskutil` (no dependency).
/// The detailed attributes come from `smartctl` (smartmontools, GPL), invoked as
/// an external process the user installs — never bundled, per the spec's
/// licensing note. Detailed fields are nil when `smartctl` isn't installed, the
/// USB bridge doesn't expose SMART passthrough, or the drive lacks a given attribute.
public struct SMARTInfo: Sendable, Codable, Equatable {
    public let status: SMARTStatus
    public let smartctlAvailable: Bool
    public let temperatureCelsius: Int?
    public let powerOnHours: Int?
    public let reallocatedSectorCount: Int?
    /// Set when `smartctl` ran but could not read the device (e.g. a USB bridge
    /// without SAT passthrough) — surfaced to the user instead of silently hidden.
    public let unavailableReason: String?

    public init(
        status: SMARTStatus,
        smartctlAvailable: Bool = false,
        temperatureCelsius: Int? = nil,
        powerOnHours: Int? = nil,
        reallocatedSectorCount: Int? = nil,
        unavailableReason: String? = nil
    ) {
        self.status = status
        self.smartctlAvailable = smartctlAvailable
        self.temperatureCelsius = temperatureCelsius
        self.powerOnHours = powerOnHours
        self.reallocatedSectorCount = reallocatedSectorCount
        self.unavailableReason = unavailableReason
    }

    public var hasDetailedAttributes: Bool {
        temperatureCelsius != nil || powerOnHours != nil || reallocatedSectorCount != nil
    }
}
