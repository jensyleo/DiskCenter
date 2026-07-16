# DiskCenter

A native macOS disk administration center. DiskCenter performs advanced storage
tasks — imaging, cloning, restore, verification, SMART, repair and secure erase —
through a modern, safety-first graphical interface built on the system's own
tools (`diskutil`, `dd`, and optionally `smartctl` for detailed SMART attributes
and `gzip`/`xz`/`zstd` for image compression).

It does not replace those tools; it unifies them so operations are transparent
and never a memorized command.

## Status

Phases 0–4 of the project roadmap are implemented: disk/partition discovery
(`diskutil list -plist`/`info -plist` only — text output is never parsed),
SMART status, mount/unmount, a Dashboard overview, disk imaging with checksums,
GPT backup, disk verification and repair, media-aware secure erase, disk
cloning, image restore, bootable USB creation, benchmarking, image compression,
operation history, preferences, and scheduled backups. All destructive
operations (secure erase, restore, clone, create bootable USB) require a red
confirmation screen and show the exact command in a simulation-mode preview
before anything runs. Manual testing on real hardware is still in progress.

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
