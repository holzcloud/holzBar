#!/bin/bash
#
# Builds holzBar and installs it, signed.
#
# Replaces the "Copy to Applications" build phase the project used to have, which cannot work:
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

# Builds into a new private folder (mktemp -d creates it with mode 0700, in the per-user
# TMPDIR), removed when the script ends. A fixed path in /tmp let another account on the
# Mac create it first and swap the app between the build and the install. Set DERIVED to
# build into a folder of your own instead; it is kept.
if [ -z "${DERIVED:-}" ]; then
    DERIVED="$(mktemp -d "${TMPDIR:-/tmp}/holzbar-build.XXXXXX")"
    trap 'rm -rf "$DERIVED"' EXIT
fi

echo "==> Building"
# Signs the app ad hoc with the same overrides as CI (.github/workflows/build.yml), so it
# builds for anyone, without an Apple developer team. The project sets no team, and
# Automatic signing without one refuses to sign at all.
#
# The hardened runtime stays on, as in the project and the release. With an ad hoc
# signature, library validation refuses any embedded framework that carries a team of its
# own ("mapping process and mapped file (non-platform) have different Team IDs", reported on
# jordanbaird/Ice#1006 by @Theralley), and `codesign --verify` would not notice. holzBar
# embeds no framework and links no package, and the system framework it opens at runtime is
# a platform binary, so everything it needs loads.
#
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps Xcode from adding get-task-allow, which would
# let any process of yours attach a debugger to holzBar and use its permissions (as in CI).
xcodebuild -project "$ROOT/holzBar.xcodeproj" -scheme holzBar -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$DERIVED" build \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    | tail -3

APP="$DERIVED/Build/Products/Release/holzBar.app"
[ -d "$APP" ] || { echo "error: no product at $APP" >&2; exit 1; }

echo "==> Verifying the signature before installing"
# The whole point: never install something that will not launch. The check also fails on
# any entitlement or a missing hardened runtime.
"$ROOT/Scripts/check-signature.sh" "$APP"
codesign -dv "$APP" 2>&1 | grep -E 'Identifier=|TeamIdentifier=|^CodeDirectory' | sed 's/^/    /'

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
#
# The details are captured first and grepped from a here-string: piped straight into
# `grep -q`, codesign usually got SIGPIPE once grep had matched, and under pipefail the
# reset was then skipped without a word.
SIGNATURE_DETAILS="$(codesign -dv "$DEST/holzBar.app" 2>&1)"
if grep -q 'Signature=adhoc' <<< "$SIGNATURE_DETAILS"; then
    BUNDLE_ID="$(defaults read "$DEST/holzBar.app/Contents/Info" CFBundleIdentifier)"
    echo "==> Ad hoc signature: resetting the permissions of the previous build"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    tccutil reset ScreenCapture "$BUNDLE_ID" >/dev/null 2>&1 || true
fi

open -a "$DEST/holzBar.app"
echo "==> Running from $DEST/holzBar.app"
