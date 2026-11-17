# Architecture

DualPoint is a small AppKit application with a deterministic core. It observes
physical input, decides which device is active, and moves the single system
cursor to that device's saved position. If two devices move at the same time it
keeps the real cursor with the first one and draws a temporary second cursor for
the other.

## Goals and non-goals

**Goals**

- One real cursor with per-device positions.
- Two independent cursors while two devices move simultaneously.
- A device switch is explicit, fast and reversible.
- Normal macOS pointer behavior is untouched.
- No private APIs, no input injection, no network access.
- Predictable behavior across hot-plug, sleep, display changes and restarts.

**Non-goals**

- Replacing the system pointer while only one device moves.
- Confining a device to a display or altering acceleration.
- Remapping buttons, gestures or scrolling.
- Working at the login window or while the screen is locked.

## Runtime topology

```
┌──────────────────────┐      HID reports      ┌────────────────────┐
│ IOHIDManager         │ ────────────────────► │                    │
│ (attribution only)   │                       │   DualPointEngine  │
└──────────────────────┘                       │                    │
                                               │  · device registry │
┌──────────────────────┐   raw HID, seized     │  · activity table  │
│ SecondaryPointer     │ ────────────────────► │  · switching       │
│ Monitor              │ ◄──────────────────── │  · interim arbiter │
└──────────────────────┘   release on handover │  · anchors         │
                                               └─────────┬──────────┘
┌──────────────────────┐   pointer events      ▲
│ CGEventTap           │ ──────────────────────┘
│ (fallback for the    │   pass / consume
│  built-in trackpad)  │
└──────────────────────┘
                                                         │
                         ┌───────────────────────────────┼──────────────────┐
                         │                               │                  │
┌──────────────────────┐ │                 ┌─────────────▼──────┐  ┌────────▼─────────┐
│ DisplayManager       │ │                 │ CursorController  │  │ InterimCursor    │
│ display changes      │ │                 │ CGWarpMouseCursor │  │ Overlay (AppKit) │
└──────────────────────┘ │                 └───────────────────┘  └──────────────────┘
                         │                          warp + persist       blue arrow
                         └─────────────────────────────────────────────────────────────►
```

The engine is `@MainActor` and is driven by three sources: HID callbacks,
the event tap and display reconfiguration notifications. All state changes
happen on the main run loop, so the SwiftUI views can observe the engine
directly.

## Modules

| Module | Responsibility |
| --- | --- |
| `HIDMonitor` | Enumerates pointing devices with `IOHIDManager`, opens them without seizing, streams values and input reports for attribution, reports hot-plug. |
| `SecondaryPointerMonitor` | A second, independent `IOHIDManager` that exclusively seizes the external device driving the blue pointer and streams raw X/Y, wheel and button reports. Releases the device on handover. |
| `BuiltInTrackpadDetector` | Finds the built-in trackpad through DriverKit/IOHID services; it has no classic HID reports and cannot be seized. |
| `EventTapMonitor` | `CGEventTap` for movement, buttons and scrolling. Active tap with Accessibility; used only as the fallback that suppresses the built-in trackpad. |
| `Attribution` | Timestamp table that maps a pointer event to the newest preceding HID report. |
| `InterimCursor` | Arbiter for simultaneous movement: main/interim roles, settle detection, handover cooldown and policy. |
| `DisplayManager` | Enumerates `CGDirectDisplayID`s, names, bounds, scale, main/built-in flags; emits changes. |
| `CursorGeometry` | Display-relative anchors, clamping, restore priority and display lookup. |
| `StateStore` | Debounced JSON persistence in Application Support. |
| `DualPointEngine` | Merge devices and preferences, confirm switches, warp, save anchors, recover from display changes. |
| `DiagnosticLog` | In-memory ring buffer mirrored to a local log file. |
| `PermissionCenter` | Input Monitoring and Accessibility checks, prompts and Settings deep links. |

## Device identity

Keys are stable strings (`DeviceIdentity.stableKey`):

1. `builtin.trackpad` for the built-in trackpad.
2. `hid:<vid>:<pid>:sn:<serial>` when the device exposes a usable serial or
   physical unique ID.
3. `hid:<vid>:<pid>:loc:<location>` for USB devices without a serial.
4. `hid:<vid>:<pid>:name:<name>` as the final fallback.

If two identical devices are connected simultaneously, the second one gets a
`#<registryID>` suffix so both can be used at once. Registry IDs are never used
as the primary identity because they change across reconnects.

**Location migration.** A USB location ID changes when the cable moves to a
different port or hub. When a new key appears, the engine looks for exactly one
disconnected stored record with the same vendor/product prefix, name and kind.
If found, `PersistedState.migrateSettings(from:to:)` removes the old record and
carries the assignment, anchor and metadata to the new key. The newer record's
own anchor wins; an assignment is inherited only when the new record is
Unmanaged.

## Attribution

`CGEvent` has no device identity. `ActivityTable` stores the timestamp of the
most recent report per device and attributes an event to the newest report
inside a 25 ms window (with 2 ms clock skew tolerance). If no report matches,
the event is treated as built-in trackpad activity.

The built-in trackpad on Apple Silicon is a DriverKit event service and produces
no classic HID reports, which is why the fallback path exists.

Attribution is deliberately defensive during handover:

- **Two-event confirmation.** A new device must produce two samples within
  150 ms before the cursor moves. A single stray event cannot warp the pointer.
- **Unmatched-event grace.** While an external device is active and has moved
  within the last 75 ms, an unmatched event is treated as a delayed report from
  that device instead of a trackpad event.
- **Drag guard.** Switches are suppressed while any mouse button is down, except
  for the button-down event that starts a new interaction.
- **Anchor capture floor.** Pointer events timestamped before the most recent
  warp are ignored when capturing the active anchor, so a queued event cannot
  overwrite the restored position.
- **Synthetic events** (generated by tools or other software) never trigger a
  switch.
- **One-to-one interim routing.** Once a device owns the interim cursor, every
  one of its events is checked against the arbiter before attribution can hand
  the cursor back. Interleaved reports therefore cannot make the two devices
  fight over the real pointer.

True simultaneous movement is the hardest case for attribution. A built-in
trackpad event has no HID report, while the mouse emits one every few
milliseconds. An unmatched trackpad event that lands inside the 25 ms window can
still be labelled as mouse activity. The engine mitigates this with the
unmatched-event grace and by preferring an explicit interim session once one is
running, but it cannot make the signal unambiguous. `docs/TESTING.md` records
what real hardware has confirmed.

## Cursor model

Positions are stored as normalized anchors on a specific display:

```json
{
  "displayUUID": "C9CFBC56-CE17-40EF-8898-2D0390A92D4F",
  "displayName": "DELL S2725QS",
  "x": 0.578,
  "y": 0.435
}
```

`x`/`y` are fractions of the display's top-left origin. An anchor survives
resolution and scaling changes, and it follows the same physical display when
its arrangement moves.

Restore priority for a device:

1. The anchor, if its display is currently connected.
2. The assigned display's default point, if the anchor is unavailable.
3. Nothing — the cursor stays where it is (for Unmanaged devices).

Switching saves the outgoing device's current position first, then activates the
incoming device and restores its position if it is managed. The same path is
used for real input, the manual `Move Cursor Now` action and the onboarding test
drive.

Anchors are updated on pointer events while the device is active, throttled to
one write every 500 ms, and forced on switch, disconnect, display change and
quit.

## Simultaneous cursors

External pointing devices are isolated at the source, following DoubleMouse's
model. `SecondaryPointerMonitor` opens the device that is about to become blue
with `kIOHIDOptionsTypeSeizeDevice`. macOS then stops delivering that device's
reports to the window server, so it can no longer drag the real cursor around
behind the blue one. Raw X/Y counts are coalesced per report, scaled with a
linear 1x–2x gain curve and applied to the overlay. Clicks are synthesized at
the blue position after the device is released; scrolls are synthesized without
moving the real cursor.

The built-in trackpad is a DriverKit event service and cannot be seized. When
it is the second device, DualPoint falls back to an active `CGEventTap` that
consumes its movement and uses the event deltas for the overlay. Accessibility
is therefore required only for that case.

`InterimCursorArbiter` holds three facts: the device that owns the real cursor
(`mainDeviceID`), the device that owns the drawn cursor (`interimDeviceID`) and
the last movement timestamp per device. Its rules are:

1. The first device to move owns the real cursor.
2. A different device that moves while the main device moved within the last
   350 ms gets the interim cursor, starting from its own saved position.
3. When the interim device has been quiet for the configured handover delay
   (never less than the internal 280 ms settle delay) and the cooldown since the
   last handover has elapsed, the seized device is released, the real cursor
   warps to the blue position, the overlay disappears and the blue device
   becomes the only active device. There is no role swap: the previous main
   device does not acquire a new blue cursor.
4. A button press from the interim device commits immediately: the device is
   released, the real cursor warps to it, and the click is posted there. A
   scroll stays at the blue position without committing. Drags are never
   interrupted by a timer.
5. The handover delay (0–3 s, default 0.8 s) is both the quiet time after the
   interim device stops and the minimum interval between two automatic
   handovers, which blocks ping-ponging. A button press bypasses both waits.
6. Single-device movement never reaches the interim path: when the device is
   already `activeDeviceID`, the event passes straight through.

The overlay (`InterimCursorOverlay` in the app target) is one transparent,
non-activating `NSWindow` spanning the union of every display. Its content view
is flipped so local coordinates match Core Graphics, it ignores mouse events and
never becomes key. The arrow is `NSCursor.arrow.image` tinted with the app
icon's electric blue, drawn at the system hotspot so it is exactly the same
size as the real pointer. Only the small dirty rectangles around the old and new
positions are redrawn; a 30 Hz timer checks settling.

If neither isolation path is available — no Input Monitoring for HID seizure and
no active tap for the trackpad — the arbiter is not used, the overlay is not
drawn, and both devices share the real cursor as before. The UI states this
explicitly instead of pretending the feature works.

`PersistedState` stores `interimCursorEnabled` and `handoverCooldown`. The
schema accepts older files without these keys and fills in the defaults.

## Display changes

`DisplayManager` observes `CGDisplayRegisterReconfigurationCallback`. After a
configuration change the engine:

1. Refreshes the device list and assignments.
2. If the cursor is still on a display, keeps it and updates the active anchor.
3. Otherwise restores the active device's saved position or assignment.
4. If that is unreachable too, moves the cursor to the main display.
5. Logs the new configuration.

An assignment is never treated as a hard boundary. The engine only warps on a
device switch, a display rescue or an explicit user action.

## Persistence

State lives in
`~/Library/Application Support/DualPoint/state.json` (schema version 2):

```json
{
  "schemaVersion": 2,
  "automaticSwitching": true,
  "interimCursorEnabled": true,
  "handoverCooldown": 0.8,
  "onboardingCompleted": true,
  "devices": {
    "hid:046d:c077:loc:130000": {
      "assignment": { "displayUUID": "...", "displayName": "DELL S2725QS" },
      "isEnabled": true,
      "anchor": { "displayUUID": "...", "displayName": "DELL S2725QS", "x": 0.58, "y": 0.44 },
      "lastKnownName": "USB Optical Mouse",
      "lastKnownKind": "mouse"
    }
  }
}
```

Writes are debounced and atomic. Disconnected devices stay in the file so their
assignment and position are available when they return. Unknown keys decode with
defaults, which keeps older files readable.

## Interface architecture

The app is launched from `main.swift` by `DualPointApp` (an
`NSApplicationDelegate`). There is no SwiftUI `App` scene: that avoids an empty
Settings window and the default app menu.

- **Menu bar panel** — a custom `NSStatusItem` plus a borderless,
  non-activating `NSPanel` hosting `MenuBarContentView`. The panel owns its
  spring/fade entrance, glass background and outside-click dismissal. It never
  activates DualPoint.
- **Settings** — one AppKit window hosting `SettingsView` with four tabs
  (General, Devices, Activity, About).
- **Setup** — a separate AppKit window hosting the four-step `OnboardingView`.
  Its final step temporarily enables switching (`setTestDriving(true)`) so the
  handover can be tested before setup is committed.
- **Design QA** — in debug builds, `DUALPOINT_SNAPSHOT_DIR` renders the panel,
  every Settings tab and all onboarding steps off-screen to PNG. This is how the
  layout was verified without Screen Recording permission.
- **Interim cursor overlay** — a borderless, non-activating `NSWindow` at
  `.screenSaver` level, spanning all screens and joining every Space. It is
  owned by `AppModel` and fed by `engine.onInterimCursorChange`.

## Failure handling

| Failure | Behavior |
| --- | --- |
| Input Monitoring denied | HID monitoring stops, devices are not listed, switching stays paused; a 2 s timer retries after approval. |
| Event tap unavailable | Switching is paused; the UI explains the missing permission. |
| Accessibility denied | External devices still get a blue cursor through HID seizure; the built-in trackpad cannot, so both devices share the real cursor in that case. |
| Accessibility granted while running | The tap is restarted once, so the trackpad fallback starts working without a relaunch. |
| HID seizure refused | The engine logs the error and falls back to event-tap suppression when available; otherwise normal switching continues. |
| Interim device disconnects | The overlay is hidden, its last point is saved if possible, and the real cursor keeps its position. |
| Permission or event tap lost with an interim cursor visible | The overlay is hidden and the interim role is cleared; no warp happens. |
| HID open fails for one device | The device is listed but cannot be attributed; the error is logged. |
| Active device disconnects | Its anchor is saved, the active device clears, the cursor stays put. |
| Display disappears | Cursor is restored to the active device's reachable position or the main display. |
| Onboarding incomplete | Input is observed for the UI, but the cursor never moves. |
| Automatic switching off | Positions are still recorded; only warps are disabled. |

## Privacy

DualPoint reads pointer reports and system pointer events locally. It does not
record keystrokes, movement history, window contents or application names, and
it makes no network connections. Diagnostics are a short in-memory log mirrored
to `~/Library/Logs/DualPoint/DualPoint.log`.
