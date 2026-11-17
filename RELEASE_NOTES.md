# DualPoint 1.0.0

DualPoint is a small macOS menu bar app that remembers where each of your pointing devices left the cursor. Switch from your trackpad to your mouse and the cursor returns to the mouse's own spot. Switch back and it returns to the trackpad's spot.

This is the first public release. DualPoint uses one real macOS cursor — it does not draw a second pointer, change pointer acceleration, or confine the pointer to a display. Drag and drop, gestures and normal movement across displays keep working.

## Highlights

- Separate, saved cursor positions for the built-in trackpad, mice and external trackpads.
- Automatic switching when you start using another device.
- Assign each device to the built-in display or any external display. Positions follow displays when their arrangement changes.
- Stable device recognition, including migration when a USB device is moved to another port.
- Quiet menu bar panel, full Settings, and a four-step setup assistant with a handover test.
- Everything stays local: no account, no network connection, no keystrokes, no movement history.

## Installation

Download **DualPoint-1.0.0.dmg** (or **DualPoint-1.0.0.zip**) from the assets attached to this release.

1. Open the downloaded disk image or unzip the archive.
2. Move **DualPoint.app** into your **Applications** folder.
3. Open DualPoint and follow the setup assistant.
4. Allow **Input Monitoring** when macOS asks. If the prompt does not appear, go to **System Settings → Privacy & Security → Input Monitoring** and enable DualPoint, then choose **Check Again** in the app.

This release is ad-hoc signed and not notarized. If Gatekeeper blocks the first launch, control-click DualPoint in Applications, choose **Open**, and confirm **Open** once.

To uninstall, quit DualPoint from the menu bar and delete the app from Applications. You can also remove `~/Library/Application Support/DualPoint/state.json` and `~/Library/Logs/DualPoint/DualPoint.log`.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon (arm64)
- Input Monitoring permission

Built and internally tested on an Apple M3 with macOS 27.2, a built-in Retina display, a DELL S2725QS external display, the built-in trackpad and a Logitech USB Optical Mouse (`046D:C077`). Other hardware combinations have not been verified yet.

## Permissions

DualPoint needs **Input Monitoring** to tell which physical device moved the pointer: macOS does not attach device identities to pointer events. The event tap is listen-only; DualPoint never modifies or suppresses input events.

**Accessibility** is not required for normal operation. It is only requested if macOS refuses to create the listen-only event tap even though Input Monitoring is granted. DualPoint does not read window contents, menus or keystrokes.

## Known limitations

- On Apple Silicon the built-in trackpad emits no classic HID reports; its activity is inferred from unmatched pointer events.
- Moving a USB device to another port changes its location ID. Settings migrate when exactly one previous device matches; two identical devices disconnected at the same time cannot be distinguished until they are used again.
- DualPoint does not operate at the login window or while the Mac is locked.
- Automatic switching stays paused while permissions or setup are incomplete.
- Device-handover checks on real hardware are documented as pending in `docs/TESTING.md`.

## Feedback

Please report bugs and device-specific issues in [GitHub Issues](https://github.com/Pablomatisch/DualPoint/issues). Include your macOS version, Mac model, pointing devices and the recent lines from `~/Library/Logs/DualPoint/DualPoint.log` if possible.
