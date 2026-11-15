#!/bin/bash
# Builds DualPoint.app without Xcode (uses the active Swift toolchain).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/DualPoint.app"
CONFIG="${1:-release}"

cd "$ROOT"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "Generating app icon…"
  swift "$ROOT/Scripts/make-icons.swift"
  iconutil -c icns "$ROOT/Resources/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
fi

echo "Building DualPoint ($CONFIG)…"
swift build -c "$CONFIG" --product DualPoint
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/DualPoint" "$APP/Contents/MacOS/DualPoint"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"

# Ad-hoc signature. TCC (Input Monitoring) binds to this signature; rebuilding
# may require re-approval in System Settings.
codesign --force --sign - --identifier com.dualpoint.DualPoint "$APP" >/dev/null

echo "Built: $APP"
echo "Launch with: open \"$APP\""
