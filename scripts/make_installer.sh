#!/bin/bash
# Builds everything a release needs, in one step, into build/release/:
#   DayBook-AI.zip                     the file to share or attach to a GitHub release
#   DayBook AI Installer.dmg           what's inside the zip: the app, an Applications shortcut, the guide
#   Start Here - How to Install.pdf    INSTALL.md as a printable page (also inside the installer)
#
# Run it in the public copy (made by scripts/export_public.sh), so Finances, Reminders and
# personal details stay out of the app you hand to other people:
#   ./scripts/make_installer.sh
#
# Options: SKIP_TESTS=1 skips the test suites. ALLOW_PRIVATE=1 runs it in the private repository
# anyway (the features are still left out, but its other files aren't checked for personal details).
# Needs Google Chrome, Chromium, Microsoft Edge or Brave to print the guide to PDF.
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
cd "$DIR"

if [ -d Sources/PersonalPlanner/Services/Finances ] && [ "${ALLOW_PRIVATE:-0}" != "1" ]; then
    echo "This looks like the private repository (it has Finances)." >&2
    echo "Make the public copy first and run this there:" >&2
    echo "  ./scripts/export_public.sh ../DayBook-AI-release && cd ../DayBook-AI-release && ./scripts/make_installer.sh" >&2
    exit 1
fi

GUIDE_MD="INSTALL.md"
[ -f "$GUIDE_MD" ] || GUIDE_MD="public/INSTALL.md"
[ -f "$GUIDE_MD" ] || { echo "INSTALL.md not found." >&2; exit 1; }

BROWSER=""
for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
    if [ -x "$candidate" ]; then BROWSER="$candidate"; break; fi
done
[ -n "$BROWSER" ] || { echo "Install Google Chrome (or Chromium, Edge or Brave) to print the guide to PDF." >&2; exit 1; }

echo "== 1/5 Building the app (without Finances and Reminders)"
DAYBOOK_FINANCES=0 DAYBOOK_REMINDERS=0 ./scripts/build.sh
APP="build/DayBook AI.app"
BIN="$APP/Contents/MacOS/DayBookAI"
[ "$(lipo -archs "$BIN")" = "arm64" ] || echo "Note: the app is built for $(lipo -archs "$BIN")."

echo "== 2/5 Testing"
if [ "${SKIP_TESTS:-0}" = "1" ]; then
    echo "Skipped (SKIP_TESTS=1)."
else
    for suite in --test-persistence --test-milestone-improvements --test-ollama --test-email-discovery --test-quick-capture --test-canvas; do
        if "$BIN" "$suite" > "build/test${suite}.log" 2>&1; then
            echo "  passed $suite"
        else
            echo "  FAILED $suite (see build/test${suite}.log)" >&2
            exit 1
        fi
    done
fi
if strings "$BIN" | grep -qiE "DAYBOOK_FINANCES|import_spending_ledger"; then
    echo "The app still contains Finances code; not packaging it." >&2
    exit 1
fi

OUT="build/release"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT"
mkdir -p "$OUT"
PDF_NAME="Start Here - How to Install.pdf"
DMG_NAME="DayBook AI Installer.dmg"
ZIP_NAME="DayBook-AI.zip"

echo "== 3/5 Printing the guide to PDF"
python3 -I scripts/install_guide_html.py "$GUIDE_MD" "$WORK/guide.html"
"$BROWSER" --headless=new --disable-gpu --no-pdf-header-footer --user-data-dir="$WORK/browser" \
    --print-to-pdf="$OUT/$PDF_NAME" "file://$WORK/guide.html" >/dev/null 2>&1
[ -s "$OUT/$PDF_NAME" ] || { echo "Printing the guide failed." >&2; exit 1; }

echo "== 4/5 Making the installer"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/DayBook AI.app"
ln -s /Applications "$STAGE/Applications"
cp "$OUT/$PDF_NAME" "$STAGE/"
hdiutil create -volname "DayBook AI" -srcfolder "$STAGE" -ov -format UDZO "$OUT/$DMG_NAME" >/dev/null 2>&1
hdiutil verify "$OUT/$DMG_NAME" >/dev/null 2>&1 || { echo "The installer image didn't verify." >&2; exit 1; }
MOUNT="$WORK/mount"
mkdir -p "$MOUNT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$OUT/$DMG_NAME" >/dev/null 2>&1
codesign --verify --deep --strict "$MOUNT/DayBook AI.app" || { hdiutil detach "$MOUNT" >/dev/null 2>&1; echo "The app's signature didn't verify." >&2; exit 1; }
hdiutil detach "$MOUNT" >/dev/null 2>&1

echo "== 5/5 Zipping"
ditto -c -k --sequesterRsrc "$OUT/$DMG_NAME" "$OUT/$ZIP_NAME"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
echo
echo "Done: DayBook AI $VERSION in $OUT/"
( cd "$OUT" && ls -lh | tail -n +2 && echo && shasum -a 256 "$ZIP_NAME" "$DMG_NAME" )
echo
echo "To publish: GitHub → Releases → Draft a new release, attach $ZIP_NAME (keep that name so"
echo "INSTALL.md's 'latest release' link keeps working), and optionally the PDF."
