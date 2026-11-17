# Permissions and privacy

DualPoint asks for two permissions, and only the first is required for normal
switching.

## Input Monitoring

macOS does not attach a device identity to pointer events. To know whether the
trackpad or the mouse moved the cursor, DualPoint needs to:

1. **List and read HID pointing devices** with `IOHIDManager`
   (`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`).
2. **Observe pointer events** with a `CGEventTap`
   (`CGPreflightListenEventAccess`).

Both checks map to the single **Input Monitoring** switch in System Settings →
Privacy & Security → Input Monitoring.

With Input Monitoring but without Accessibility, the tap is listen-only: it
observes events and passes all of them through. That is enough to identify
devices and to switch the single real cursor between their saved positions.

If the permission is missing:

- Devices cannot be listed or distinguished.
- The engine keeps running so the UI can explain what is missing.
- Automatic switching stays paused.

The app retries periodically, so enabling the switch in System Settings takes
effect without a relaunch. “Check Again” in Settings forces an immediate refresh.

## Accessibility

For **simultaneous cursors**, an external device is isolated through raw HID:
DualPoint opens it with `kIOHIDOptionsTypeSeizeDevice`, reads its X/Y counts and
releases it when the blue pointer is handed over. That path is covered by Input
Monitoring and does not need Accessibility.

The built-in trackpad is a DriverKit event service and cannot be seized. It also
cannot be isolated with a `CGEventTap`: returning `nil` from a tap hides a
`mouseMoved` event from applications but does not stop the window server from
moving the real cursor, so an unseizable device would move both pointers. The
blue cursor is therefore limited to external devices, and the trackpad always
owns the real cursor while a second device is active. This limitation is shared
by DoubleMouse and is stated in the app.

`AXIsProcessTrusted()` still controls whether the pointer tap is active, which
affects diagnostics only. With or without it, external devices get an independent
blue cursor and single-device switching is unchanged.

The permission is never used to read window contents, menus, keystrokes or
clipboard data.

The app notices a grant while running and restarts the tap once, so the feature
does not require a relaunch. Grants are tied to the code signature, so a rebuilt
ad-hoc bundle may need to be enabled again.

## Launch at login

The optional login item uses `SMAppService.mainApp`, the public macOS 13 API.
macOS may show it as “Waiting for approval” until it is enabled in System
Settings → General → Login Items. The bundle must live in `/Applications` for
this to be available.

## What DualPoint reads

- Vendor/product IDs, product name, transport, serial number and USB location
  from connected pointing devices.
- Timestamps of HID reports and pointer movement, clicks and scrolls.
- Display IDs, names, bounds, scale and main/built-in flags.
- The pointer location, which is needed to save and restore positions.

## What DualPoint does not read or store

- No keystrokes or key codes.
- No movement history, window titles, application names or screen contents.
- No clipboard contents.
- No network connections of any kind.

## Local files

| Path | Contents |
| --- | --- |
| `~/Library/Application Support/DualPoint/state.json` | Assignments, saved anchors, preferences, onboarding flag |
| `~/Library/Logs/DualPoint/DualPoint.log` | Short diagnostic log of switches and device events |

Both files are human-readable JSON/text and stay on this Mac. The Activity tab
can reveal them, copy the recent log, or open the saved state in Finder.

## Revoking access

1. Open System Settings → Privacy & Security → Input Monitoring.
2. Turn DualPoint off.
3. Optionally do the same under Accessibility.
4. Optionally remove `state.json` and the log directory to erase local data.

With Input Monitoring revoked, DualPoint no longer sees devices and cannot move
the cursor. With only Accessibility revoked, switching and saved positions keep
working but the second cursor is disabled.

## Rebuilds and ad-hoc signatures

TCC grants are tied to the code signature. Every rebuilt ad-hoc signed copy can
require Input Monitoring and Accessibility approval again. Granting them to one
copy does not grant them to another. For day-to-day use, sign with a stable
Developer ID.

Launching from Terminal
(`./build/DualPoint.app/Contents/MacOS/DualPoint`) inherits the grants of that
specific binary; launching via `open` after a rebuild may show no devices or no
second cursor until permission is granted again.
