#!/bin/bash
# Renders the DayBook AI app icon from code (scripts/icon_renderer + DayBookMarkDrawing.swift),
# so the Dock icon and the in-app logo always match. Sizes below 64 px use the simplified mark
# (no sparkle, thicker book and sun), per the logo guidelines.
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
if [ ! -f "$SWIFTC" ]; then
    SWIFTC="swiftc"
    SDK=$(xcrun --show-sdk-path)
fi

ICONSET_DIR="Resources/AppIcon.iconset"
RENDERER="$(mktemp -d)/icon_renderer"
mkdir -p /tmp/clang-cache

echo "🎨 Rendering DayBook AI icon sizes..."
"$SWIFTC" -sdk "$SDK" -target arm64-apple-macosx14.0 -O -module-cache-path /tmp/clang-cache \
    -o "$RENDERER" \
    scripts/icon_renderer/main.swift \
    Sources/PersonalPlanner/Views/Components/DayBookMarkDrawing.swift
"$RENDERER" "$ICONSET_DIR" "Resources/AppIcon.png"
cp Resources/AppIcon.png Resources/Assets/AppIcon-Original.png

echo "📦 Packaging iconset into Resources/AppIcon.icns..."
iconutil -c icns "$ICONSET_DIR" -o Resources/AppIcon.icns

echo "✅ AppIcon.icns successfully generated."
