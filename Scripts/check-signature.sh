#!/bin/bash
#
# Checks the signature of a built holzBar.app and of every piece of code inside it.
#
# holzBar ships one executable and one piece of nested code. Contents/MacOS/holzBar is the
# main executable; the only nested item allowed is the helper framework NowPlayingRemote.framework of
# the Now Playing module's "Read all apps" (ALLOWED_NESTED below), which Apple's perl loads and which holds
# exactly one Mach-O file. There is no XPCServices, PlugIns or Helpers folder, no other entry in
# Contents/Frameworks, and no other bundle, library or Mach-O file anywhere. Any other code
# would run with holzBar's Accessibility and Screen Recording permissions, and the release
# workflow's sign job would not sign it with holzBar's certificate. The app is valid without the
# helper too: it is optional.
#
# Every item must be validly signed, every bundle (app, framework, XPC service, app extension)
# must carry the hardened runtime, and no item may carry an entitlement except the app itself,
# and it only the one in ALLOWED_ENTITLEMENTS below. Xcode adds com.apple.security.get-task-allow
# to code it signs to run locally; with it, any process of the same user can attach a debugger
# to holzBar and act with its Accessibility and Screen Recording permissions. The builds turn
# that off (CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO); this script proves it.
#
# Usage: Scripts/check-signature.sh path/to/holzBar.app
#
# Called by Scripts/install.sh before installing, by the build job of
# .github/workflows/build.yml and by the build job of .github/workflows/release.yml.
# Exits with status 1 if any check fails.
#
set -euo pipefail

# The only entitlement holzBar may carry: Calendar access for the Calendar module of the notch
# hub. A hardened app needs it before macOS will let it ask for Calendar access at all; it grants
# nothing by itself (macOS still asks the user, who can revoke it). Every other key fails the
# check, network ones and get-task-allow included. Adding a key needs the maintainer's decision.
ALLOWED_ENTITLEMENTS=("com.apple.security.personal-information.calendars")

# The only nested code holzBar may contain, relative to the app: the helper framework that the
# Now Playing module's "Read all apps" runs through Apple's perl. Adding an entry needs the
# maintainer's decision and a named exception in CLAUDE.md (Private API in modules). The
# release workflow mirrors the rules below between its "nested code rules" comments.
ALLOWED_NESTED=("Contents/Frameworks/NowPlayingRemote.framework")

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

# is_allowed_nested RELATIVE_PATH succeeds when the path is in ALLOWED_NESTED.
is_allowed_nested() {
    local ok
    for ok in "${ALLOWED_NESTED[@]}"; do
        if [ "$1" = "$ok" ]; then
            return 0
        fi
    done
    return 1
}

for FOLDER in XPCServices PlugIns Helpers; do
    if [ -e "$APP/Contents/$FOLDER" ]; then
        report "$(basename "$APP")/Contents/$FOLDER exists; only ${ALLOWED_NESTED[*]} may be nested"
    fi
done
if [ -d "$APP/Contents/Frameworks" ]; then
    while IFS= read -r -d '' ENTRY; do
        if ! is_allowed_nested "${ENTRY#"$APP"/}"; then
            report "$(basename "$APP")/${ENTRY#"$APP"/} is in Contents/Frameworks; only ${ALLOWED_NESTED[*]} may be nested"
        fi
    done < <(find "$APP/Contents/Frameworks" -mindepth 1 -maxdepth 1 -print0)
fi

# The Mach-O files: the main executable, and the ones inside an allowed nested item (counted
# per item, exactly one each). Any other is code outside both.
COUNTS=()
for _ in "${ALLOWED_NESTED[@]}"; do
    COUNTS+=(0)
done
while IFS= read -r -d '' FILE; do
    if [ "$FILE" = "$APP/Contents/MacOS/holzBar" ]; then
        continue
    fi
    # Captured first, like codesign below, so SIGPIPE cannot hide a match under pipefail.
    KIND=$(file -b "$FILE")
    if [[ "$KIND" == Mach-O* ]]; then
        INSIDE=0
        for INDEX in "${!ALLOWED_NESTED[@]}"; do
            if [[ "$FILE" == "$APP/${ALLOWED_NESTED[$INDEX]}/"* ]]; then
                COUNTS[INDEX]=$((COUNTS[INDEX] + 1))
                INSIDE=1
            fi
        done
        if [ "$INSIDE" -eq 0 ]; then
            report "$(basename "$APP")/${FILE#"$APP"/} is code outside holzBar's main executable and the helper; holzBar ships no nested code besides the helper"
        fi
    fi
done < <(find "$APP" -type f -print0)
for INDEX in "${!ALLOWED_NESTED[@]}"; do
    if [ -d "$APP/${ALLOWED_NESTED[$INDEX]}" ] && [ "${COUNTS[$INDEX]}" -ne 1 ]; then
        report "$(basename "$APP")/${ALLOWED_NESTED[$INDEX]} must hold exactly one Mach-O file, not ${COUNTS[$INDEX]}"
    fi
done

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
    if [ "$ITEM" != "$APP" ] && ! is_allowed_nested "${ITEM#"$APP"/}"; then
        report "$NAME is nested code; only ${ALLOWED_NESTED[*]} may be nested"
        ITEM_FAILED=1
    fi
    case "$ITEM" in
        *.app | *.framework | *.xpc | *.appex)
            RESULT="hardened runtime"
            if ! grep -qE '^CodeDirectory.*flags=0x[0-9a-f]+\([^)]*runtime' <<< "$DETAILS"; then
                report "$NAME is not signed with the hardened runtime"
                ITEM_FAILED=1
            fi
            ;;
    esac
    FOUND=()
    ENTITLEMENTS=$(codesign -d --entitlements - --xml "$ITEM" 2> /dev/null || true)
    if grep -q 'com.apple.security.get-task-allow' <<< "$ENTITLEMENTS"; then
        report "$NAME carries com.apple.security.get-task-allow, which lets a debugger attach to it"
        ITEM_FAILED=1
    elif grep -q '<key>' <<< "$ENTITLEMENTS"; then
        while IFS= read -r KEY; do
            ALLOWED=0
            for OK in "${ALLOWED_ENTITLEMENTS[@]}"; do
                if [ "$KEY" = "$OK" ] && [ "$ITEM" = "$APP" ]; then
                    ALLOWED=1
                fi
            done
            if [ "$ALLOWED" -eq 1 ]; then
                FOUND+=("$KEY")
            else
                report "$NAME carries the entitlement $KEY; holzBar may carry only: ${ALLOWED_ENTITLEMENTS[*]}"
                ITEM_FAILED=1
            fi
        done < <(grep -oE '<key>[^<]*</key>' <<< "$ENTITLEMENTS" | sed -E 's|</?key>||g')
    fi
    if [ "$ITEM_FAILED" -eq 0 ]; then
        if [ "${#FOUND[@]}" -eq 0 ]; then
            echo "==> $NAME: $RESULT, entitlements: none"
        else
            echo "==> $NAME: $RESULT, entitlements: ${FOUND[*]}"
        fi
    fi
done

exit "$FAILED"
