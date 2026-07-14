// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CryptoKit
import Foundation

public enum ChecksumServiceError: Error, Sendable {
    case fileNotReadable(String)
}

/// Which digest to compute (spec §4.13: SHA256, SHA512, MD5). SHA256 remains
/// the default used automatically after Create Image; the others are for
/// manual verification against a checksum from elsewhere.
public enum ChecksumAlgorithm: String, Sendable, CaseIterable {
    case sha256 = "SHA256"
    case sha512 = "SHA512"
    case md5 = "MD5"
}

/// Computes and verifies checksums, streaming in chunks so multi-gigabyte
/// disk images never need to fit in memory at once.
public struct ChecksumService: Sendable {
    private static let chunkSize = 4 * 1024 * 1024 // 4 MiB

    public init() {}

    /// Lowercase hex digest of the file at `url`, using `algorithm`.
    public func digest(of url: URL, algorithm: ChecksumAlgorithm = .sha256) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw ChecksumServiceError.fileNotReadable(url.path)
        }
        defer { try? handle.close() }
        return try Self.hashChunks(from: handle, algorithm: algorithm)
    }

    /// Backwards-compatible SHA256-only entry point (used by `ImageService`).
    public func sha256(of url: URL) throws -> String {
        try digest(of: url, algorithm: .sha256)
    }

    /// Whether the file at `url` hashes to `expectedHex` (case-insensitive),
    /// under `algorithm`.
    public func verify(_ url: URL, expectedHex: String, algorithm: ChecksumAlgorithm = .sha256) throws -> Bool {
        try digest(of: url, algorithm: algorithm).caseInsensitiveCompare(expectedHex) == .orderedSame
    }

    /// Compares an image file against a disk/partition device by hashing the
    /// SAME number of bytes from each side (the device is typically larger
    /// than the image, so we read only `byteCount` from it) — spec §4.13's
    /// "image vs. disk" comparison.
    public func compare(
        imageURL: URL,
        devicePath: String,
        byteCount: Int64,
        algorithm: ChecksumAlgorithm = .sha256
    ) throws -> Bool {
        let imageHash = try digest(of: imageURL, algorithm: algorithm)
        guard let deviceHandle = FileHandle(forReadingAtPath: devicePath) else {
            throw ChecksumServiceError.fileNotReadable(devicePath)
        }
        defer { try? deviceHandle.close() }
        let deviceHash = try Self.hashChunks(from: deviceHandle, algorithm: algorithm, limitBytes: byteCount)
        return imageHash.caseInsensitiveCompare(deviceHash) == .orderedSame
    }

    private static func hashChunks(
        from handle: FileHandle,
        algorithm: ChecksumAlgorithm,
        limitBytes: Int64? = nil
    ) throws -> String {
        var sha256Hasher = algorithm == .sha256 ? SHA256() : nil
        var sha512Hasher = algorithm == .sha512 ? SHA512() : nil
        var md5Hasher = algorithm == .md5 ? Insecure.MD5() : nil

        var remaining = limitBytes
        while true {
            let toRead = remaining.map { Swift.min(chunkSize, Int($0)) } ?? chunkSize
            if toRead <= 0 { break }
            let chunk = try handle.read(upToCount: toRead) ?? Data()
            if chunk.isEmpty { break }
            sha256Hasher?.update(data: chunk)
            sha512Hasher?.update(data: chunk)
            md5Hasher?.update(data: chunk)
            if let r = remaining { remaining = r - Int64(chunk.count) }
        }

        let digestBytes: [UInt8]
        switch algorithm {
        case .sha256: digestBytes = Array(sha256Hasher!.finalize())
        case .sha512: digestBytes = Array(sha512Hasher!.finalize())
        case .md5: digestBytes = Array(md5Hasher!.finalize())
        }
        return digestBytes.map { String(format: "%02x", $0) }.joined()
    }
}
