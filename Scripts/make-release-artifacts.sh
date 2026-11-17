#!/bin/bash
# Packages the already-built build/DualPoint.app into release artifacts.
# Usage: ./Scripts/make-release-artifacts.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$ROOT/build/DualPoint.app"
VERSION="1.0.0"
TMP_ROOT="/private/var/folders/p0/xvfffz2d20d6sny3xjkksdm40000gn/T"
DMG_RW="$DIST/.DualPoint-dmg-rw.dmg"
MOUNT="$TMP_ROOT/dualpoint-dmg-mount"
DMG="$DIST/DualPoint-$VERSION.dmg"
ZIP="$DIST/DualPoint-$VERSION.zip"

[[ -d "$APP" ]] || { echo "missing $APP — run Scripts/build-app.sh first" >&2; exit 1; }

rm -rf "$DIST" "$MOUNT"
mkdir -p "$DIST" "$MOUNT"

# --- DMG staging ---------------------------------------------------------
STAGE="$DIST/.stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/DualPoint.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/assets/dmg-background.png" "$STAGE/.background/background.png"

# --- DMG -----------------------------------------------------------------
echo "Creating DMG…"
hdiutil create -volname "DualPoint" -srcfolder "$STAGE" -ov -format UDRW "$DMG_RW" >/dev/null
# Finder can only style a disk that appears in /Volumes, so attach normally.
hdiutil attach "$DMG_RW" -noautoopen >/dev/null
VOLUME="/Volumes/DualPoint"
[[ -d "$VOLUME" ]] || { echo "DMG did not mount at $VOLUME" >&2; exit 1; }

osascript >/dev/null <<'APPLESCRIPT'
tell application "Finder"
  tell disk "DualPoint"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {80, 100, 740, 520}
    set viewOptions to icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "DualPoint.app" of container window to {170, 250}
    set position of item "Applications" of container window to {470, 250}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

hdiutil detach "$VOLUME" >/dev/null
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG" >/dev/null
rm -f "$DMG_RW"
rm -rf "$STAGE"

# --- ZIP -----------------------------------------------------------------
echo "Creating ZIP…"
ZIP_STAGE="$DIST/.zipstage"
mkdir -p "$ZIP_STAGE"
cp -R "$APP" "$ZIP_STAGE/DualPoint.app"
cat > "$ZIP_STAGE/README.txt" <<'EOF'
DualPoint 1.0.0
===============

Move DualPoint.app into your Applications folder, open it and follow the setup
assistant. Allow Input Monitoring when macOS asks. If the prompt does not appear:
System Settings > Privacy & Security > Input Monitoring > DualPoint > On

This build is ad-hoc signed and not notarized. If Gatekeeper blocks the first
launch, control-click DualPoint.app, choose Open, and confirm Open.

Copyright (c) 2026 DualPoint. All rights reserved.
EOF
(cd "$ZIP_STAGE" && zip -q -r -y "$ZIP" DualPoint.app README.txt)
rm -rf "$ZIP_STAGE"

# --- checksums -----------------------------------------------------------
shasum -a 256 "$DMG" "$ZIP" | sed "s|$DIST/||" > "$DIST/SHA256SUMS.txt"

# --- verification --------------------------------------------------------
echo "Verifying…"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "Bundle architecture: $(lipo -archs "$APP/Contents/MacOS/DualPoint")"
echo "Bundle version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "Bundle identifier: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
echo "Signature: $(codesign -dv "$APP" 2>&1 | grep '^Signature=' | head -1)"
echo "Hardened runtime: $(codesign -dv "$APP" 2>&1 | grep -o 'runtime' | head -1 || echo 'not enabled')"

spctl_output="$(spctl -a -vvv -t install "$APP" 2>&1 || true)"
echo "Gatekeeper assessment: $spctl_output"

unzip -tq "$ZIP" >/dev/null && echo "ZIP: integrity OK"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -noautoopen >/dev/null
[[ -d "$MOUNT/DualPoint.app" ]] && echo "DMG: DualPoint.app present"
[[ -L "$MOUNT/Applications" ]] && echo "DMG: Applications link present"
cp -R "$MOUNT/DualPoint.app" "$TMP_ROOT/dualpoint-dmg-verify.app"
codesign --verify --deep --strict "$TMP_ROOT/dualpoint-dmg-verify.app" && echo "DMG copy: signature OK"
rm -rf "$TMP_ROOT/dualpoint-dmg-verify.app"
hdiutil detach "$MOUNT" >/dev/null

ls -lh "$DMG" "$ZIP" "$DIST/SHA256SUMS.txt"
cat "$DIST/SHA256SUMS.txt"
