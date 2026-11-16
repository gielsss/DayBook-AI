#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

echo "🔨 Building DayBook AI macOS app..."

mkdir -p build
mkdir -p /tmp/clang-cache

# Finances & Work Tracker is optional. It is built in unless DAYBOOK_FINANCES=0 (or the Finances
# folders aren't there, as in the public copy made by scripts/export_public.sh).
# Reminders works the same way with DAYBOOK_REMINDERS.
FIND_EXCLUDES=()
FEATURE_FLAGS=""
if [ "${DAYBOOK_FINANCES:-1}" != "0" ] && [ -d Sources/PersonalPlanner/Services/Finances ]; then
    FEATURE_FLAGS="$FEATURE_FLAGS -D DAYBOOK_FINANCES"
    echo "Including Finances"
else
    FIND_EXCLUDES+=(-not -path "*/Finances/*" -not -name "FinancesTest.swift")
    echo "Building without Finances"
fi
if [ "${DAYBOOK_REMINDERS:-1}" != "0" ] && [ -f Sources/PersonalPlanner/Views/RemindersView.swift ]; then
    FEATURE_FLAGS="$FEATURE_FLAGS -D DAYBOOK_REMINDERS"
    echo "Including Reminders"
else
    FIND_EXCLUDES+=(-not -name "Reminder.swift" -not -name "AppState+Reminders.swift" -not -name "RemindersView.swift")
    echo "Building without Reminders"
fi
SWIFT_FILES=$(find Sources/PersonalPlanner -name "*.swift" "${FIND_EXCLUDES[@]}")

# Select compiler and SDK (prefer CommandLineTools SDK which doesn't require sudo license accept)
SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

if [ ! -f "$SWIFTC" ]; then
    SWIFTC="swiftc"
    SDK=$(xcrun --show-sdk-path)
fi

echo "Using compiler: $SWIFTC"
echo "Using SDK: $SDK"

PLUGIN_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
PLUGIN_FLAG=""
if [ -d "$PLUGIN_PATH" ]; then
    PLUGIN_FLAG="-plugin-path $PLUGIN_PATH"
fi

"$SWIFTC" \
    -sdk "$SDK" \
    -module-cache-path /tmp/clang-cache \
    $PLUGIN_FLAG \
    $FEATURE_FLAGS \
    -parse-as-library \
    -O \
    -target arm64-apple-macosx14.0 \
    -o build/DayBookAI \
    $SWIFT_FILES

echo "📦 Packaging DayBook AI.app bundle..."
APP_BUNDLE="build/DayBook AI.app"
# The app was called PersonalPlanner before; drop the old bundle so only one copy exists.
rm -rf build/PersonalPlanner.app build/PersonalPlanner
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp build/DayBookAI "$APP_BUNDLE/Contents/MacOS/DayBookAI"

# Ensure AppIcon.icns exists and copy it into the app bundle resources
if [ ! -f "Resources/AppIcon.icns" ]; then
    if [ -f "scripts/generate_icons.sh" ]; then
        ./scripts/generate_icons.sh
    fi
fi
# Workbook import script (one-time Excel import in Finances)
if [[ "$FEATURE_FLAGS" == *DAYBOOK_FINANCES* ]] && [ -f scripts/import_spending_ledger.py ]; then
    cp scripts/import_spending_ledger.py "$APP_BUNDLE/Contents/Resources/import_spending_ledger.py"
else
    rm -f "$APP_BUNDLE/Contents/Resources/import_spending_ledger.py"
fi

if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat << 'EOF' > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DayBookAI</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.personalplanner.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DayBook AI</string>
    <key>CFBundleDisplayName</key>
    <string>DayBook AI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSCalendarsUsageDescription</key>
    <string>DayBook AI reads your Apple Calendar commitments to schedule tasks around your existing busy times.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>DayBook AI reads your Apple Calendar commitments to schedule tasks around your existing busy times.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>DayBook AI reads Canvas through the Canvas tab you have open in your browser (read-only) to find your assignments and announcements.</string>
</dict>
</plist>
EOF

# Remove extended attributes/detritus before code signing
xattr -cr "$APP_BUNDLE"

# Detect if a valid code signing identity is configured or available on this system
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 '"' | awk -F'"' '{print $2}' || true)
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Signing with cryptographic identity: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" \
        --identifier "com.personalplanner.app" \
        "$APP_BUNDLE/Contents/MacOS/DayBookAI"
    codesign --force --sign "$SIGNING_IDENTITY" \
        --identifier "com.personalplanner.app" \
        "$APP_BUNDLE"
else
    echo "No cryptographic signing identity found. Using secure default ad-hoc signing (cdhash-bound)..."
    echo "Notice: Without a local code signing certificate, rebuilds change binary hashes and may require reauthorization."
    codesign --force --sign - \
        --identifier "com.personalplanner.app" \
        "$APP_BUNDLE/Contents/MacOS/DayBookAI"
    codesign --force --sign - \
        --identifier "com.personalplanner.app" \
        "$APP_BUNDLE"
fi

echo "✅ Build complete: build/DayBook AI.app"
