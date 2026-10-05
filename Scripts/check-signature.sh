#!/bin/bash
#
# Checks the signature of a built holzBar.app and of every piece of code inside it.
#
# holzBar ships no nested code: Contents/MacOS/holzBar is its only Mach-O file, and there
# is no XPCServices, PlugIns, Helpers or Frameworks folder. Any other code would run with
# holzBar's Accessibility and Screen Recording permissions, and the release workflow's
# sign job would not sign it with holzBar's certificate.
#
# Every item must be validly signed, every bundle (app, XPC service, app extension) must
# carry the hardened runtime, and no item may carry an entitlement. holzBar needs none.
# Xcode adds com.apple.security.get-task-allow to code it signs to run locally; with it,
# any process of the same user can attach a debugger to holzBar and act with its
# Accessibility and Screen Recording permissions. The builds turn that off
# (CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO); this script proves it.
#
# Usage: Scripts/check-signature.sh path/to/holzBar.app
#
# Called by Scripts/install.sh before installing, by the build job of
# .github/workflows/build.yml and by the build job of .github/workflows/release.yml.
# Exits with status 1 if any check fails.
#
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -d "$1" ]; then
    echo "usage: $0 path/to/holzBar.app" >&2
    exit 2
fi
APP="${1%/}"
FAILED=0

report() {
    if [ "${GITHUB_ACTIONS:-}" = true ]; then
        echo "::error::$1"
    else
        echo "error: $1" >&2
    fi
    FAILED=1
}

if ! codesign --verify --deep --strict "$APP"; then
    report "$(basename "$APP") does not pass codesign --verify --deep --strict"
fi

for FOLDER in XPCServices PlugIns Helpers Frameworks; do
    if [ -e "$APP/Contents/$FOLDER" ]; then
        report "$(basename "$APP")/Contents/$FOLDER exists; holzBar ships no nested code"
    fi
done
while IFS= read -r -d '' FILE; do
    if [ "$FILE" = "$APP/Contents/MacOS/holzBar" ]; then
        continue
    fi
    # Captured first, like codesign below, so SIGPIPE cannot hide a match under pipefail.
    KIND=$(file -b "$FILE")
    if [[ "$KIND" == Mach-O* ]]; then
        report "$(basename "$APP")/${FILE#"$APP"/} is code outside holzBar's main executable; holzBar ships no nested code"
    fi
done < <(find "$APP" -type f -print0)

# The nested code, deepest first, then the app itself.
ITEMS=()
while IFS= read -r -d '' ITEM; do
    ITEMS+=("$ITEM")
done < <(find "$APP/Contents" -depth \( -name '*.xpc' -o -name '*.appex' -o -name '*.framework' -o -name '*.app' -o -name '*.dylib' \) -print0)
ITEMS+=("$APP")

for ITEM in "${ITEMS[@]}"; do
    if [ "$ITEM" = "$APP" ]; then
        NAME=$(basename "$APP")
    else
        NAME="$(basename "$APP")/${ITEM#"$APP"/}"
    fi
    # Captured first and grepped from here-strings: piped into grep -q, codesign may get
    # SIGPIPE and fail the pipeline under pipefail (see Scripts/install.sh).
    if ! DETAILS=$(codesign -dv "$ITEM" 2>&1); then
        report "$NAME is not signed"
        continue
    fi
    ITEM_FAILED=0
    RESULT="signed"
    case "$ITEM" in
        *.app | *.xpc | *.appex)
            RESULT="hardened runtime"
            if ! grep -qE '^CodeDirectory.*flags=0x[0-9a-f]+\([^)]*runtime' <<< "$DETAILS"; then
                report "$NAME is not signed with the hardened runtime"
                ITEM_FAILED=1
            fi
            ;;
    esac
    ENTITLEMENTS=$(codesign -d --entitlements - --xml "$ITEM" 2> /dev/null || true)
    if grep -q 'com.apple.security.get-task-allow' <<< "$ENTITLEMENTS"; then
        report "$NAME carries com.apple.security.get-task-allow, which lets a debugger attach to it"
        ITEM_FAILED=1
    elif grep -q '<key>' <<< "$ENTITLEMENTS"; then
        KEYS=$(grep -oE '<key>[^<]*</key>' <<< "$ENTITLEMENTS" | sed -E 's|</?key>||g' | tr '\n' ' ')
        report "$NAME carries entitlements; holzBar has none: ${KEYS% }"
        ITEM_FAILED=1
    fi
    if [ "$ITEM_FAILED" -eq 0 ]; then
        echo "==> $NAME: $RESULT, no entitlements"
    fi
done

exit "$FAILED"
