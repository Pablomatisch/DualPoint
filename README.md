# DualPoint

**Independent cursor positions for every physical pointing device.**

DualPoint is a native macOS menu bar utility that remembers where each pointing
device left the cursor. Pick up the trackpad and the pointer returns to where it
was on the MacBook display; reach for the mouse and it jumps back to its own
position on the external monitor.

DualPoint manages **one real macOS cursor**. It never draws a second cursor, it
does not change pointer acceleration, and it does not confine the pointer to a
display. Drag and drop, gestures, and normal cross-display movement keep working.

## Features

- **Per-device positions** — every mouse and trackpad keeps its own last cursor
  position, saved as a display-relative anchor so resolution, scaling and
  arrangement changes do not lose it.
- **Live device detection** — built-in trackpad, USB mice, wireless mice,
  external trackpads, multiple mice and hot-plugging.
- **Display assignments** — assign a device to the built-in display, any
  external display, or leave it Unmanaged. Assignments are the starting point;
  a device's actual last position always wins.
- **Display awareness** — disconnecting or rearranging displays updates the
  available targets and rescues a cursor that would be left off-screen.
- **Drag protection** — the cursor does not jump away in the middle of a drag.
- **Guided setup** — a four-step assistant covers permissions, privacy,
  assignments and a real handover test.
- **Menu bar first** — no Dock icon, no second cursor, automatic launch at login
  is optional.
- **Local-only** — no network access, no keystroke logging, no movement history.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 13 Ventura or newer
- Input Monitoring permission
- Command Line Tools (`xcode-select --install`) if you build from source

## Install from source

```bash
./Scripts/build-app.sh          # release build
open build/DualPoint.app
```

The script builds with SwiftPM, assembles `build/DualPoint.app`, and ad-hoc
signs it. No Xcode project is required.

On first launch, DualPoint opens the setup assistant. Grant **Input Monitoring**
in System Settings → Privacy & Security → Input Monitoring, then complete the
device assignments.

> Because the app is ad-hoc signed, every rebuilt copy can require the Input
> Monitoring grant again. Sign with your own Developer ID for day-to-day use.

## Usage

Click the DualPoint icon in the menu bar to see the active device, assignments
and quick actions. `Settings` contains the full configuration;
`Setup` reopens the assistant.

| Action | Where |
| --- | --- |
| Assign a device to a display | Panel → Manage, or Settings → Devices |
| Switch positions immediately | Settings → Devices → ••• → Move Cursor Now |
| Forget a saved position | Settings → Devices → ••• |
| Pause automatic switching | Panel footer, or Settings → General |
| Run setup again | Panel → Setup |
| Quit | Panel footer power button |

## Build and test

```bash
swift build
swift run DualPointSelfTest      # 55 assertions
swift run DualPointDiagnose list # real hardware inventory
```

`swift test` is not available with a Command Line Tools-only toolchain, so the
self-test is a dependency-free executable in the same package.

See [`docs/TESTING.md`](docs/TESTING.md) for the hardware matrix and the manual
handover checklist.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — runtime design, device
  attribution, cursor model, persistence and failure handling.
- [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) — why Input Monitoring is needed,
  what is optional, where data lives and how to revoke access.
- [`docs/DESIGN.md`](docs/DESIGN.md) — the visual system, motion and interface
  structure.
- [`docs/TESTING.md`](docs/TESTING.md) — automated coverage, real hardware
  results and regression checks.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/DualPointCore` | HID detection, attribution, display geometry, switching, persistence |
| `Sources/DualPoint` | AppKit menu bar app, SwiftUI panels, Settings and Onboarding |
| `Sources/DualPointCLI` | `DualPointDiagnose` hardware diagnostics |
| `Tests/DualPointCoreTests` | Dependency-free self-test suite |
| `Scripts` | Build and icon scripts |
| `Resources` | `Info.plist` and application icon |
| `docs` | Architecture, permissions, design and testing documentation |

## Limitations

- macOS does not label pointer events with a device. DualPoint correlates HID
  reports with system pointer events by timestamp; on Apple Silicon the built-in
  trackpad emits no HID reports and is inferred from unattributed events.
- A USB location ID changes when a device is moved to another port. DualPoint
  migrates saved settings when exactly one disconnected record matches the same
  vendor/product, name and kind. Two identical devices that were both
  disconnected at once cannot be told apart until each is used again.
- DualPoint does not work while the Mac is locked or on the login window.
- Automatic switching pauses while permissions or setup are incomplete.
- macOS may require Input Monitoring approval again after rebuilding an ad-hoc
  signed copy.

## License

Copyright © 2026 DualPoint. All rights reserved.
