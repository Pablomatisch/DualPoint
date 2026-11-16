# Architecture

DualPoint is a small AppKit application with a deterministic core. It observes
physical input, decides which device is active, and moves the single system
cursor to that device's saved position.

## Goals and non-goals

**Goals**

- One cursor with per-device positions.
- A device switch is explicit, fast and reversible.
- Normal macOS pointer behavior is untouched.
- No private APIs, no input injection, no network access.
- Predictable behavior across hot-plug, sleep, display changes and restarts.

**Non-goals**

- Drawing a cursor overlay or a second pointer.
- Confining a device to a display or altering acceleration.
- Remapping buttons, gestures or scrolling.
- Working at the login window or while the screen is locked.

## Runtime topology

```
┌──────────────────────┐      HID reports      ┌────────────────────┐
│ IOHIDManager         │ ────────────────────► │                    │
│ (mice, trackpads)    │                       │   DualPointEngine  │
└──────────────────────┘                       │                    │
                                               │  · device registry │
┌──────────────────────┐   pointer events      │  · activity table  │
│ CGEventTap           │ ────────────────────► │  · switching       │
│ (listen-only)        │                       │  · anchors         │
└──────────────────────┘                       └─────────┬──────────┘
                                                         │
┌──────────────────────┐    display changes              │ warp + persist
│ DisplayManager       │ ───────────────────────────────►│
└──────────────────────┘                                 ▼
                                               ┌────────────────────┐
                                               │ CursorController   │
                                               │ CGWarpMouseCursor  │
                                               └────────────────────┘
```

The engine is `@MainActor` and is driven by three sources: HID callbacks,
the event tap and display reconfiguration notifications. All state changes
happen on the main run loop, so the SwiftUI views can observe the engine
directly.

## Modules

| Module | Responsibility |
| --- | --- |
| `HIDMonitor` | Enumerates pointing devices with `IOHIDManager`, opens them without seizing, streams values and input reports, reports hot-plug. |
| `BuiltInTrackpadDetector` | Finds the built-in trackpad through DriverKit/IOHID services; it has no classic HID reports. |
| `EventTapMonitor` | Listen-only `CGEventTap` for movement, buttons and scrolling. Never modifies events. |
| `Attribution` | Timestamp table that maps a pointer event to the newest preceding HID report. |
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
`~/Library/Application Support/DualPoint/state.json` (schema version 1):

```json
{
  "schemaVersion": 1,
  "automaticSwitching": true,
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

## Failure handling

| Failure | Behavior |
| --- | --- |
| Input Monitoring denied | HID monitoring stops, devices are not listed, switching stays paused; a 2 s timer retries after approval. |
| Event tap unavailable | Switching is paused; the UI explains the missing permission. |
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
