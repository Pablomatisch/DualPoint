# DualPoint

**Independent cursor positions for every physical pointing device.**

DualPoint is a native macOS menu bar utility that remembers where each pointing
device left the cursor. Pick up the trackpad and the pointer returns to where it
was on the MacBook display; reach for the mouse and it jumps back to its own
position on the external monitor.

DualPoint manages **one real macOS cursor**. When two devices move at the same
time, the one that moved first keeps the real cursor and the other gets a blue
app-drawn cursor until it stops; then the real cursor takes its place. It does
not change pointer acceleration or confine the pointer to a display, so drag and
drop, gestures and normal cross-display movement keep working.

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
- **Simultaneous cursors** — move both devices at once: the first keeps the real
  cursor, the other moves a blue interim cursor, and the real cursor follows
  when it settles. The handover delay is adjustable.
- **Drag protection** — the cursor does not jump away in the middle of a drag.
- **Guided setup** — a four-step assistant covers permissions, privacy,
  assignments and a real handover test.
- **Menu bar first** — no Dock icon, and launch at login is optional.
- **Local-only** — no network access, no keystroke logging, no movement history.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 13 Ventura or newer
- Input Monitoring permission
- Accessibility permission for two independently moving cursors (optional;
  without it both devices still share the real cursor)
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
device assignments. Grant **Accessibility** as well if you want both devices to
move independent cursors at the same time.

> Because the app is ad-hoc signed, every rebuilt copy can require the Input
> Monitoring and Accessibility grants again. Sign with your own Developer ID for
> day-to-day use.

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
| Turn the second cursor on or off | Settings → General → Simultaneous cursors |
| Change the handover delay | Settings → General → Handover delay |
| Run setup again | Panel → Setup |
| Quit | Panel footer power button |

## Build and test

```bash
swift build
swift run DualPointSelfTest      # 89 assertions
swift run DualPointDiagnose list # real hardware inventory
```

`swift test` is not available with a Command Line Tools-only toolchain, so the
self-test is a dependency-free executable in the same package.

See [`docs/TESTING.md`](docs/TESTING.md) for the hardware matrix and the manual
handover checklist.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — runtime design, device
  attribution, cursor model, persistence and failure handling.
- [`docs/PERMISSIONS.md`](docs/PERMISSIONS.md) — why Input Monitoring and
  Accessibility are needed, what is optional, where data lives and how to revoke
  access.
- [`docs/DESIGN.md`](docs/DESIGN.md) — the visual system, motion and interface
  structure.
- [`docs/TESTING.md`](docs/TESTING.md) — automated coverage, real hardware
  results and regression checks.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/DualPointCore` | HID detection, attribution, display geometry, switching, interim cursor, persistence |
| `Sources/DualPoint` | AppKit menu bar app, SwiftUI panels, Settings, Onboarding and the cursor overlay |
| `Sources/DualPointCLI` | `DualPointDiagnose` hardware diagnostics |
| `Tests/DualPointCoreTests` | Dependency-free self-test suite |
| `Scripts` | Build and icon scripts |
| `Resources` | `Info.plist` and application icon |
| `docs` | Architecture, permissions, design and testing documentation |

## Limitations

- macOS does not label pointer events with a device. DualPoint correlates HID
  reports with system pointer events by timestamp; on Apple Silicon the built-in
  trackpad emits no HID reports and is inferred from unattributed events.
- The second cursor is drawn by DualPoint, not by macOS. While both devices move
  at once it can move over any app, but it is not a real system pointer: it does
  not change hover state, text selection or the window server's cursor until the
  real cursor is handed over.
- Suppressing the second device's real movement requires Accessibility. Without
  it the feature stays off and both devices share the real cursor.
- True simultaneous trackpad and mouse movement stresses attribution: an
  unmatched trackpad event can arrive close enough to a mouse report to be
  labelled as mouse. This build needs a hardware run to confirm how often it
  happens; see `docs/TESTING.md`.
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
