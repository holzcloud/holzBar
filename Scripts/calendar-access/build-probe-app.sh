#!/bin/bash
#
# Builds the Calendar access probe as a small signed app bundle in one of four variants.
#
#   build-probe-app.sh v1|v2|v3|v4 [--out DIR]
#
#   v1  ad hoc signature, hardened runtime, no entitlement
#   v2  ad hoc signature, hardened runtime, com.apple.security.personal-information.calendars
#   v3  holzBar's release certificate, hardened runtime, no entitlement
#   v4  holzBar's release certificate, hardened runtime, the Calendars entitlement
#
# The probe must be an app bundle started with `open`, not a command-line tool: the Calendar
# permission belongs to the process that asks (for a tool started in Terminal, Terminal), so only
# a bundle with its own identifier measures what holzBar would get. Every variant has its own
# bundle identifier, so macOS keeps one answer per variant. `tccutil reset Calendar <identifier>`
# makes a variant ask again.
#
# This is a throwaway spike. It builds with the Command Line Tools alone, touches nothing of
# holzBar.app, the root test package or the Xcode project, and ships nowhere. The certificate for
# v3 and v4 is the one in docs/signing.md ("holzBar Release Signing"), imported into a keychain.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PACKAGE="$ROOT/Scripts/calendar-access"
ENTITLEMENT="com.apple.security.personal-information.calendars"

VARIANT="${1:-}"
case "$VARIANT" in
    v1|v2|v3|v4) shift ;;
    *) echo "usage: $0 v1|v2|v3|v4 [--out DIR]" >&2; exit 2 ;;
esac

OUT="${TMPDIR:-/tmp}"
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="${2:-}"; [ -n "$OUT" ] || { echo "error: --out needs a folder" >&2; exit 2; }; shift 2 ;;
        *) echo "usage: $0 v1|v2|v3|v4 [--out DIR]" >&2; exit 2 ;;
    esac
done
mkdir -p "$OUT"

case "$VARIANT" in
    v1) IDENTITY="-"; WITH_ENTITLEMENT=no ;;
    v2) IDENTITY="-"; WITH_ENTITLEMENT=yes ;;
    v3) IDENTITY="holzBar Release Signing"; WITH_ENTITLEMENT=no ;;
    v4) IDENTITY="holzBar Release Signing"; WITH_ENTITLEMENT=yes ;;
esac

if [ "$IDENTITY" != "-" ] && ! security find-identity -p codesigning | grep -q "$IDENTITY"; then
    echo "error: the certificate \"$IDENTITY\" is not in your keychains." >&2
    echo "Import holzBar's release certificate as described in docs/signing.md, or use v1 or v2." >&2
    exit 1
fi

echo "==> Building the probe"
swift build -c release --package-path "$PACKAGE" >/dev/null
BINARY="$(swift build -c release --package-path "$PACKAGE" --show-bin-path)/calendar-access-probe"
[ -x "$BINARY" ] || { echo "error: no probe binary at $BINARY" >&2; exit 1; }

APP="$OUT/HolzBarCalendarProbe-$VARIANT.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/calendar-access-probe"

PLIST="$APP/Contents/Info.plist"
plutil -create xml1 "$PLIST"
plutil -insert CFBundleIdentifier -string "ch.holzcloud.holzbar.calendarprobe.$VARIANT" "$PLIST"
plutil -insert CFBundleName -string "HolzBarCalendarProbe-$VARIANT" "$PLIST"
plutil -insert CFBundleExecutable -string "calendar-access-probe" "$PLIST"
plutil -insert CFBundlePackageType -string "APPL" "$PLIST"
plutil -insert CFBundleVersion -string "1" "$PLIST"
plutil -insert CFBundleShortVersionString -string "1" "$PLIST"
plutil -insert LSMinimumSystemVersion -string "14.0" "$PLIST"
plutil -insert LSUIElement -bool YES "$PLIST"
plutil -insert NSCalendarsFullAccessUsageDescription \
    -string "This is a test of holzBar's calendar access. It reads counts only." "$PLIST"

SIGN=(codesign --force --options runtime --sign "$IDENTITY")
if [ "$WITH_ENTITLEMENT" = yes ]; then
    ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/probe-entitlements.XXXXXX")"
    trap 'rm -f "$ENTITLEMENTS"' EXIT
    # Written as text: plutil reads the dots of the key as a key path.
    cat > "$ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>$ENTITLEMENT</key>
    <true/>
</dict>
</plist>
PLIST
    plutil -lint "$ENTITLEMENTS" >/dev/null
    SIGN+=(--entitlements "$ENTITLEMENTS")
fi
echo "==> Signing as $VARIANT"
"${SIGN[@]}" "$APP"

echo "==> What was built"
echo "Entitlements:"
codesign -d --entitlements - --xml "$APP" 2>/dev/null | sed -e 's/^/    /' || true
echo
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|flags=|Signature=|Authority=|TeamIdentifier=' | sed -e 's/^/    /'
echo
echo "App: $APP"
