# Permissions and privacy

DualPoint needs one permission for normal operation and never asks for more than
it uses.

## Input Monitoring

macOS does not attach a device identity to pointer events. To know whether the
trackpad or the mouse moved the cursor, DualPoint needs to:

1. **List and read HID pointing devices** with `IOHIDManager`
   (`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`).
2. **Observe pointer events** with a listen-only `CGEventTap`
   (`CGPreflightListenEventAccess`).

Both checks map to the single **Input Monitoring** switch in System Settings →
Privacy & Security → Input Monitoring. The event tap is listen-only: DualPoint
never modifies, suppresses or synthesizes pointer events.

If the permission is missing:

- Devices cannot be listed or distinguished.
- The engine keeps running so the UI can explain what is missing.
- Automatic switching stays paused.

The app retries periodically, so enabling the switch in System Settings takes
effect without a relaunch. “Check Again” in Settings forces an immediate refresh.

## Accessibility

Accessibility is **not required for normal operation** and is only requested if
macOS refuses to create the listen-only event tap even though Input Monitoring is
granted. This is rare. The permission is never used to read window contents,
menus or keystrokes.

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
3. Optionally remove `state.json` and the log directory to erase local data.

With Input Monitoring revoked, DualPoint no longer sees devices and cannot move
the cursor.

## Rebuilds and ad-hoc signatures

TCC grants are tied to the code signature. Every rebuilt ad-hoc signed copy can
require Input Monitoring approval again. Granting it to one copy does not grant
it to another. For day-to-day use, sign with a stable Developer ID.

Launching from Terminal
(`./build/DualPoint.app/Contents/MacOS/DualPoint`) inherits the grants of that
specific binary; launching via `open` after a rebuild may show no devices until
permission is granted again.
