#!/bin/bash
# DiskCenter — generate, build, install (and optionally run) the app.
# Copyright (C) 2026 Jensy Leonardo Martínez Cruz — GPLv3, no warranty.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "▸ Generating Xcode project with XcodeGen…"
xcodegen generate

echo "▸ Building DiskCenter (Debug)…"
xcodebuild -project DiskCenter.xcodeproj -scheme DiskCenter \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath build/DerivedData build | tail -5

APP="build/DerivedData/Build/Products/Debug/DiskCenter.app"
DEST="/Applications/DiskCenter.app"

echo "▸ Installing to $DEST …"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "✓ Installed $DEST"
if [[ "${1:-}" == "--run" ]]; then
    open "$DEST"
fi
