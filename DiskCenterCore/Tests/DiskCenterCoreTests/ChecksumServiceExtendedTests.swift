// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CryptoKit
import Foundation
import Testing
@testable import DiskCenterCore

@Suite struct ChecksumServiceExtendedTests {
    private func makeTempFile(_ payload: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try payload.write(to: url)
        return url
    }

    @Test func sha512MatchesCryptoKitReference() throws {
        let payload = Data((0..<50_000).map { UInt8($0 % 256) })
        let url = try makeTempFile(payload)
        defer { try? FileManager.default.removeItem(at: url) }

        let expected = SHA512.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let actual = try ChecksumService().digest(of: url, algorithm: .sha512)
        #expect(actual == expected)
    }

    @Test func md5MatchesCryptoKitReference() throws {
        let payload = Data((0..<50_000).map { UInt8($0 % 256) })
        let url = try makeTempFile(payload)
        defer { try? FileManager.default.removeItem(at: url) }

        let expected = Insecure.MD5.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let actual = try ChecksumService().digest(of: url, algorithm: .md5)
        #expect(actual == expected)
    }

    @Test func compareMatchesWhenImageAndDevicePrefixEqual() throws {
        let payload = Data((0..<100_000).map { UInt8($0 % 256) })
        let imageURL = try makeTempFile(payload)
        // "Device" is the same payload plus trailing garbage (simulating a
        // device larger than the image) — compare should only hash the first
        // `byteCount` bytes of each side.
        let deviceURL = try makeTempFile(payload + Data(repeating: 0xFF, count: 20_000))
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: deviceURL)
        }

        let matches = try ChecksumService().compare(
            imageURL: imageURL, devicePath: deviceURL.path, byteCount: Int64(payload.count)
        )
        #expect(matches)
    }

    @Test func compareFailsWhenContentDiffers() throws {
        let imageURL = try makeTempFile(Data([1, 2, 3, 4]))
        let deviceURL = try makeTempFile(Data([1, 2, 3, 5]))
        defer {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: deviceURL)
        }

        let matches = try ChecksumService().compare(imageURL: imageURL, devicePath: deviceURL.path, byteCount: 4)
        #expect(!matches)
    }
}
