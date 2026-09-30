#!/bin/bash
# Builds PerformStat.app — native arm64, no external dependencies.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="PerformStat"
BUNDLE_ID="local.performstat.app"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

echo "==> compiling sources (arm64)…"
mkdir -p "$MACOS_DIR" "$APP_DIR/Contents/Resources"
swiftc \
    -O \
    -whole-module-optimization \
    -enforce-exclusivity=checked \
    -target arm64-apple-macos13.0 \
    -framework AppKit -framework IOKit -framework CoreFoundation \
    app/main.swift \
    app/AppDelegate.swift \
    app/HotKeyCenter.swift \
    overlay/DesktopOverlayWindow.swift \
    overlay/OverlayManager.swift \
    overlay/PerformStatView.swift \
    statistics/SystemMonitor.swift \
    statistics/MemoryPressureMonitor.swift \
    statistics/MemoryMonitor.swift \
    statistics/NetworkMonitor.swift \
    statistics/PowerMonitor.swift \
    settings/SettingsModel.swift \
    settings/MenuBarController.swift \
    -o "$MACOS_DIR/$APP_NAME"

echo "==> copying resources…"
cp resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp resources/Assets/StatusIcon.png "$APP_DIR/Contents/Resources/StatusIcon.tiff" 2>/dev/null || true
cp resources/Assets/StatusIcon.png "$APP_DIR/Contents/Resources/StatusIcon@2x.png"
# named-image lookup wants tiff or png in Contents/Resources; provide both scales
sips -s format tiff resources/Assets/StatusIcon.png --out "$APP_DIR/Contents/Resources/StatusIcon.tiff" >/dev/null

echo "==> ad-hoc signing…"
codesign --force --deep -s - "$APP_DIR"

echo "==> built: $APP_DIR"
