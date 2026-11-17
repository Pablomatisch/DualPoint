# Testing

DualPoint combines a deterministic core suite, an off-screen UI renderer and a
manual hardware checklist. This page records what has actually been verified and
what still needs a physical run.

Last updated: 2026-11-17

## Environment

| | |
| --- | --- |
| Mac | Apple M3 |
| macOS | 27.2 |
| Built-in display | Retina, 1710 × 1112 pt, bounds `(-801, 1440, 1710, 1112)` |
| External display | DELL S2725QS, 2560 × 1440 pt, main display |
| Pointing devices | Built-in trackpad, Logitech `USB Optical Mouse` (`046D:C077`) |
| Build | SwiftPM, ad-hoc signed `build/DualPoint.app` |

## Automated suite

```bash
swift build
swift run DualPointSelfTest
```

Current result: **55 passed, 0 failed**.

The suite is a dependency-free executable because a Command Line Tools-only
toolchain has no XCTest. It covers:

- **DeviceIdentity** — built-in trackpad key, serial-number precedence, USB
  location fallback, name fallback.
- **CursorGeometry** — display containment, anchor round-trip, clamping,
  assignment fallback, unreachable restore points, off-display detection.
- **Attribution** — 25 ms attribution window, 2 ms clock-skew tolerance,
  newest-report wins, out-of-order reports, device removal and clearing.
- **PersistedState** — JSON round-trip, decoding older state without metadata,
  defaults for unknown devices, identity migration from an old connection key.
- **PointingDevice** — managed-state rules and assignment descriptions.

## Release 1.0.0 verification

Prepared from `main` at `8e1c333` on an Apple M3 running macOS 27.2.

| Check | Result |
| --- | --- |
| Clean release build via `./Scripts/build-app.sh` | Passed |
| `swift run DualPointSelfTest` | 55 passed, 0 failed |
| Bundle identifier `com.dualpoint.DualPoint` | Verified in the built `Info.plist` |
| Bundle version `1.0.0`, build `1` | Verified in the built `Info.plist` |
| `LSMinimumSystemVersion` 13.0 | Verified in the built `Info.plist` |
| Architecture arm64 | Verified with `lipo -archs` |
| Ad-hoc signature valid | `codesign --verify --deep --strict` passed |
| Hardened Runtime | Not enabled; no Developer ID certificate available |
| Notarization | Not performed; no Developer ID certificate available |
| Gatekeeper `spctl -a -t install` | Rejected, expected for an ad-hoc signed build |
| DMG mounts, contains app and Applications link | Verified |
| App copied from DMG keeps a valid signature | Verified |
| ZIP integrity (`unzip -t`) | Verified |
| SHA-256 checksums | Written to `dist/SHA256SUMS.txt` |
| Device-handover checklist on real hardware | Still pending; see below |

A clean build emits linker warnings about missing Command Line Tools framework search paths. The build itself succeeds and the resulting app is valid.

## UI verification

Debug builds render every screen off-screen when `DUALPOINT_SNAPSHOT_DIR` is set:

```bash
swift build
DUALPOINT_SNAPSHOT_DIR=/tmp/dualpoint-shots .build/debug/DualPoint
```

The renderer writes `panel.png`, `settings-general.png`,
`settings-devices.png`, `settings-activity.png`, `settings-about.png` and
`onboarding-1.png` … `onboarding-4.png`. No Screen Recording permission is
needed. Layout was checked for:

- Panel margins (20 pt content inset, no text against the edge).
- Settings header and card spacing without overlap.
- All four onboarding steps at 780 × 760 pt, including the feature grid.
- No duplicated “LIVE”/“Active” indicators on the same screen.

## Hardware matrix

| Check | Result |
| --- | --- |
| Built-in trackpad detected | Verified |
| Logitech USB mouse identified (`046D:C077`) | Verified |
| Attribution labels trackpad vs. mouse correctly | Verified |
| Display inventory and UUIDs | Verified |
| Menu bar icon opens and closes the panel | Verified with synthetic clicks on a clean launch |
| USB location-ID migration after reconnecting on another port | Verified against the real state file |
| Trackpad → mouse handover | **Pending for 1.0.0** |
| Mouse → trackpad handover | **Pending for 1.0.0** |
| Cursor over the menu bar / panel does not oscillate | **Pending for 1.0.0** |
| Sleep/wake and display hot-plug | **Pending for 1.0.0** |
| Launch at login from `/Applications` | **Pending** |

Rows marked *pending* must not be described as working until they are confirmed
on real hardware.

## Manual handover checklist

Run the app from Terminal so it inherits the existing TCC grants:

```bash
./build/DualPoint.app/Contents/MacOS/DualPoint
```

1. Open the menu bar panel and confirm both devices are listed.
2. Move the trackpad to a spot on the built-in display. Pause.
3. Move the mouse. The cursor should return to the mouse's own last position.
4. Move the trackpad again. The cursor should return to the trackpad's spot.
5. Start a drag with the mouse, keep the button down and move the trackpad.
   The cursor must not jump.
6. Move the cursor over the menu bar and over an open DualPoint window. It must
   stay put instead of warping back and forth.
7. Move the cursor across the display boundary with one device. Free movement
   across displays must still work.
8. Disconnect the external display. The cursor must stay on a reachable display.
9. Reconnect the display and switch devices. The saved anchors must restore.
10. Quit and relaunch. Both positions must survive.
11. Disable automatic switching. Positions should still be recorded, but no
    warps should occur.
12. Re-enable switching and repeat steps 2–4.

## Hardware diagnostics

```bash
swift run DualPointDiagnose list     # devices, displays, permissions
swift run DualPointDiagnose watch    # live connect/disconnect events
swift run DualPointDiagnose monitor  # HID reports vs. attributed pointer events
```

Use `monitor` while moving one device at a time. Every pointer event should be
attributed to the device that produced it; unattributed events are expected only
for the built-in trackpad.

## Regression notes

- Rebuilding an ad-hoc signed bundle can invalidate Input Monitoring. If no
  devices appear, grant permission again.
- The debug snapshot build has no normal app lifecycle; its status text may read
  “Ready · waiting for input” even when the installed app is switching normally.
- A rebuilt copy must be re-tested with the checklist above before a release.
