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

Current result: **89 passed, 0 failed**.

The suite is a dependency-free executable because a Command Line Tools-only
toolchain has no XCTest. It covers:

- **DeviceIdentity** — built-in trackpad key, serial-number precedence, USB
  location fallback, name fallback.
- **CursorGeometry** — display containment, anchor round-trip, clamping,
  assignment fallback, unreachable restore points, off-display detection, and
  interim movement across display edges and outer bounds.
- **Attribution** — 25 ms attribution window, 2 ms clock-skew tolerance,
  newest-report wins, out-of-order reports, device removal and clearing.
- **InterimCursor** — single-device immunity, overlap window eligibility, settle
  timing, adoption after the configured quiet time, cooldown, zero cooldown,
  disabled policy, main/interim role changes, out-of-order timestamps and reset.
- **PersistedState** — JSON round-trip, decoding older state without metadata,
  defaults and round-trip for the interim-cursor settings, defaults for unknown
  devices, identity migration from an old connection key.
- **PointingDevice** — managed-state rules and assignment descriptions.

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
- The Simultaneous cursors card, including the delay slider and the
  Accessibility warning, without pushing the Permissions card off-screen.
- All four onboarding steps at 780 × 760 pt, including the feature grid and the
  permission and test-drive copy.
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
| Trackpad → mouse handover | **Pending on the current build** |
| Mouse → trackpad handover | **Pending on the current build** |
| Simultaneous trackpad + mouse starts the blue interim cursor | **Pending on the current build** |
| Interim device moves independently while the other keeps the real cursor | **Pending on the current build** |
| Settle handover moves the real cursor to the blue position | **Pending on the current build** |
| Handover delay slider changes the settle behavior | **Pending on the current build** |
| Click from the blue cursor lands at its position | **Pending on the current build** |
| Single-device movement is unaffected | Verified in earlier builds; re-check on the current build |
| Cursor over the menu bar / panel does not oscillate | **Pending on the current build** |
| Sleep/wake and display hot-plug | **Pending on the current build** |
| Launch at login from `/Applications` | **Pending** |

Simultaneous movement is also the weakest point for attribution. Observe how
often the blue cursor appears when both devices move, and whether an unmatched
trackpad event is labelled as mouse. Do not mark these rows as working from the
automated suite alone.

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
5. Confirm Input Monitoring and Accessibility are both granted.
6. Move both devices at the same time. The device that moved first keeps the
   real cursor; the other gets the blue arrow at its own position.
7. Keep moving the second device. The blue arrow must move independently while
   the real cursor stays with the first device.
8. Stop the second device. After the settle delay and cooldown, the real cursor
   must move to the blue position and replace it.
9. Move both again but keep the first device moving after the handover. The
   first device should become the blue arrow at the position the real cursor
   just left, without a flash.
10. Set Handover delay to 0 s and repeat step 8; then set it to 3 s and repeat.
11. Click with the second device while its blue cursor is visible. The click must
    land at the blue position and the real cursor must commit there.
12. Move only one device. It must behave exactly as before: no blue arrow, no
    extra latency.
13. Start a drag with the mouse, keep the button down and move the trackpad.
    The cursor must not jump.
14. Turn Simultaneous cursors off. Repeat step 6; the blue arrow must not appear
    and normal switching must still work.
15. Move the cursor over the menu bar and over an open DualPoint window. It must
    stay put instead of warping back and forth.
16. Move the cursor across the display boundary with one device. Free movement
    across displays must still work.
17. Disconnect the external display while a blue cursor is visible. The overlay
    must disappear and the real cursor must stay on a reachable display.
18. Reconnect the display and switch devices. The saved anchors must restore.
19. Quit and relaunch. Both positions and the simultaneous-cursor settings must
    survive.
20. Disable automatic switching. Positions should still be recorded, but no
    warps should occur.
21. Re-enable switching and repeat steps 2–4.

## Hardware diagnostics

```bash
swift run DualPointDiagnose list     # devices, displays, permissions
swift run DualPointDiagnose watch    # live connect/disconnect events
swift run DualPointDiagnose monitor  # HID reports vs. attributed pointer events
```

Use `monitor` while moving one device at a time. Every pointer event should be
attributed to the device that produced it; unattributed events are expected only
for the built-in trackpad. Then move both devices together and watch for
unmatched events being labelled as the external device: that is the attribution
weakness described in `docs/ARCHITECTURE.md`.

## Regression notes

- Rebuilding an ad-hoc signed bundle can invalidate Input Monitoring and
  Accessibility. If no devices appear, grant permission again; if the blue
  cursor never appears, grant Accessibility again.
- The debug snapshot build has no normal app lifecycle; its status text may read
  “Ready · waiting for input” even when the installed app is switching normally.
- A rebuilt copy must be re-tested with the checklist above before a release.
