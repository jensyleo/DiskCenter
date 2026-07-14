# DiskCenter

A native macOS disk administration center. DiskCenter performs advanced storage
tasks — imaging, cloning, restore, verification, SMART, repair and secure erase —
through a modern, safety-first graphical interface built on the system's own
tools (`diskutil`, `dd`, `asr`, `hdiutil`, `gpt`, `smartctl`).

It does not replace those tools; it unifies them so operations are transparent
and never a memorized command.

## Status

Early scaffold. The core (`DiskCenterCore`) discovers disks by parsing
`diskutil list -plist` (property lists only — text output is never parsed). The
app lists disks and partitions read-only. Destructive operations are gated for
later phases behind the validation and confirmation rules described in the spec.

## Design principles

1. Safety above everything — destructive operations require multiple validations.
2. Transparency — the exact command is shown before it runs.
3. Modularity and extensibility.

The boot/system disk is never offered as a destructive target.

## Architecture

- Swift 6, SwiftUI, MVVM (`Views → ViewModels → Services → system tools`).
- `DiskCenterCore`: an AppKit-free Swift package (models, services, CLI harness).
- The app target is generated with XcodeGen from `project.yml`.
- Distributed outside the Mac App Store (writing to `/dev/rdiskN` is incompatible
  with the App Sandbox); ad-hoc signed for development.

## Build

```sh
Scripts/build.sh          # generate + build + install to /Applications
Scripts/build.sh --run    # …and launch
swift test --package-path DiskCenterCore   # run the core unit tests
```

## License

Free software under the [GNU General Public License v3.0](LICENSE) — with no
warranty. Copyright © 2026 Jensy Leonardo Martínez Cruz.

`smartctl` (smartmontools, GPL) is invoked as an external process the user
installs; it is not bundled, to avoid extending its license terms to this app.
