#!/bin/bash

APP_NAME="PlayPointer"
EXECUTABLE_NAME="TinyHand"
BUNDLE_ID="app.omiusgm.playpointer"
REPO="omiusgm/playpointer"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${TINYHAND_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"

make_bundle() {
    local binary="$1" app="$2" build="$3" updates="${4:-}"
    if [[ "$updates" == "--with-updates" ]]; then
        echo "Update signing is not configured for PlayPointer." >&2
        return 1
    fi
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$binary" "$app/Contents/MacOS/$APP_NAME"
    cp "$ROOT"/assets/hand_*.png "$app/Contents/Resources/"
    cp "$ROOT"/assets/sounds/tap_*.wav "$ROOT/assets/AppIcon.icns" "$ROOT/assets/Assets.car" "$app/Contents/Resources/"
    cp "$ROOT"/assets/menubar_*.png "$app/Contents/Resources/"

    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$build</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Based on TinyHand © 2026 Kamran Ahmed. MIT License.</string>
</dict>
</plist>
PLIST
}

sign_app() {
    local app="$1" identity="$2"
    codesign --force --sign "$identity" "$app"
    codesign --verify --deep --strict "$app"
}
