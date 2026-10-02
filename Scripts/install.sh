#!/bin/bash
#
# Builds holzBar and installs it, signed.
#
# Replaces the project's "Copy to Applications" build phase, which cannot work:
# Xcode signs a target *after* its script phases run, so that phase always copies
# an unsigned bundle. macOS then refuses to launch it — "Launchd job spawn
# failed" — and the freshly built app appears simply broken.
#
# Installs to ~/Applications by default, which needs no administrator rights.
# Set DEST=/Applications to install system-wide; that path needs a password.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-$HOME/Applications}"
DERIVED="${DERIVED:-/tmp/holzbar-build}"

echo "==> Building"
# Signs the app ad hoc with the same overrides as CI (.github/workflows/build.yml), so it
# builds for anyone, without an Apple developer team. The project sets no team, and
# Automatic signing without one refuses to sign at all.
#
# The hardened runtime is turned off on purpose. With an ad hoc signature the hardened
# runtime refuses to load any embedded framework that carries a team of its own (Sparkle
# did, until this fork dropped it): "mapping process and mapped file (non-platform) have
# different Team IDs". `codesign --verify --deep --strict` passes all the same, so the
# script used to install a bundle that could not launch for anyone without a team
# (reported on jordanbaird/Ice#1006 by @Theralley). A copy installed from here is run by
# its builder, not distributed, so it loses nothing by it.
xcodebuild -project "$ROOT/holzBar.xcodeproj" -scheme holzBar -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    ENABLE_HARDENED_RUNTIME=NO \
    | tail -3

APP="$DERIVED/Build/Products/Release/holzBar.app"
[ -d "$APP" ] || { echo "error: no product at $APP" >&2; exit 1; }

echo "==> Verifying the signature before installing"
# The whole point: never install something that will not launch.
codesign --verify --deep --strict "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=' | sed 's/^/    /'

echo "==> Installing to $DEST"
if pgrep -x holzBar >/dev/null 2>&1; then
    osascript -e 'quit app "holzBar"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x holzBar >/dev/null 2>&1 || break
        sleep 0.3
    done
    pgrep -x holzBar >/dev/null 2>&1 && pkill -x holzBar || true
fi

mkdir -p "$DEST"
rm -rf "${DEST:?}/holzBar.app"
# ditto, not cp: it preserves the code signature.
ditto "$APP" "$DEST/holzBar.app"

echo "==> Verifying the installed copy"
codesign --verify --deep --strict "$DEST/holzBar.app"

# An ad hoc signature changes with every build, and macOS keeps the permissions it
# granted to the previous one: System Settings shows them as on while holzBar is denied,
# and holzBar never gets past its permissions window (jordanbaird/Ice#1004). Clear them
# so that the new build is asked for them afresh.
if codesign -dv "$DEST/holzBar.app" 2>&1 | grep -q 'TeamIdentifier=not set'; then
    BUNDLE_ID="$(defaults read "$DEST/holzBar.app/Contents/Info" CFBundleIdentifier)"
    echo "==> Ad hoc signature: resetting the permissions of the previous build"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

open -a "$DEST/holzBar.app"
echo "==> Running from $DEST/holzBar.app"
