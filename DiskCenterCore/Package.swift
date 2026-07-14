// swift-tools-version: 6.0
//
// DiskCenter — a disk administration center for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.

import PackageDescription

let package = Package(
    name: "DiskCenterCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DiskCenterCore", targets: ["DiskCenterCore"]),
        .executable(name: "diskcenter-cli", targets: ["diskcenter-cli"]),
    ],
    targets: [
        .target(name: "DiskCenterCore"),
        .executableTarget(
            name: "diskcenter-cli",
            dependencies: ["DiskCenterCore"]
        ),
        .testTarget(
            name: "DiskCenterCoreTests",
            dependencies: ["DiskCenterCore"]
        ),
    ]
)
