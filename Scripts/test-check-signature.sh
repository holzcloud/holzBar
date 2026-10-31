#!/bin/bash
#
# Proves what Scripts/check-signature.sh accepts and refuses, with small fixture apps.
#
# The signature check is a security promise: holzBar.app carries exactly one entitlement,
# com.apple.security.personal-information.calendars (macOS lets a hardened app ask for
# Calendar access only with it), and every other key must fail the build and the release.
# It also holds exactly one piece of nested code, the Now Playing helper framework
# Contents/Frameworks/NowPlayingRemote.framework, and nothing else.
# A check that is never shown to fail proves nothing, so this script builds a tiny app per
# case, signs it ad hoc and runs the check on it:
#
#   1  hardened, no entitlement                       passes
#   2  hardened, only the Calendars entitlement       passes
#   3  hardened, Calendars plus the camera            fails, names the camera key
#   4  hardened, get-task-allow                       fails, says a debugger could attach
#   5  hardened, a network entitlement                fails, names it
#   6  not hardened                                   fails
#   7  a second Mach-O file inside the bundle         fails on the nested-code rule
#   8  the helper framework, hardened, no entitlement passes, names the helper
#   9  a second framework beside the helper          fails: only the helper may be nested
#  10  the helper with an entitlement                 fails, names the key
#  11  the helper's signature removed after signing   fails: does not pass codesign --verify
#  12  the helper under Contents/Resources            fails: only the helper's place may be nested
#  13  a second Mach-O file inside the helper         fails: must hold exactly one Mach-O file
#  14  the helper without the hardened runtime        fails
#
# It builds everything in a temporary folder, removed when it ends, and touches nothing in the
# repository. Run by .github/workflows/build.yml next to the signature check.
#
# Usage: Scripts/test-check-signature.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/Scripts/check-signature.sh"
CALENDARS="com.apple.security.personal-information.calendars"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-signature-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One tiny executable, copied into every fixture.
printf 'int main(void) { return 0; }\n' > "$WORK/main.c"
cc -o "$WORK/holzBar" "$WORK/main.c"

# entitlements FILE KEY... writes a property list with each KEY set to true. Written as text:
# plutil reads the dots of a key as a key path.
entitlements() {
    local file="$1"
    shift
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0">'
        echo '<dict>'
        local key
        for key in "$@"; do
            echo "    <key>$key</key>"
            echo '    <true/>'
        done
        echo '</dict>'
        echo '</plist>'
    } > "$file"
    plutil -lint "$file" > /dev/null
}

# fixture NAME RUNTIME(yes|no) [KEY...] builds $WORK/NAME/holzBar.app.
fixture() {
    local name="$1" runtime="$2"
    shift 2
    local app="$WORK/$name/holzBar.app"
    mkdir -p "$app/Contents/MacOS"
    cp "$WORK/holzBar" "$app/Contents/MacOS/holzBar"
    local plist="$app/Contents/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleExecutable -string holzBar "$plist"
    plutil -insert CFBundleIdentifier -string com.holzcloud.holzBar "$plist"
    plutil -insert CFBundlePackageType -string APPL "$plist"
    local args=(--force --sign -)
    [ "$runtime" = yes ] && args+=(--options runtime)
    if [ "$#" -gt 0 ]; then
        entitlements "$WORK/$name/entitlements.plist" "$@"
        args+=(--entitlements "$WORK/$name/entitlements.plist")
    fi
    codesign "${args[@]}" "$app" 2> /dev/null
}

# framework APP_DIR FOLDER NAME [executable] builds a framework bundle in the real layout:
# Versions/A with one dynamic library and Resources/Info.plist, the Versions/Current link and
# the top-level links to the executable and the resources. codesign embeds an entitlement only
# in an executable, never in a dynamic library, so the fixture that needs an entitlement on the
# helper passes `executable` and gets a plain executable as the framework's code.
framework() {
    local app="$1" folder="$2" name="$3" kind="${4:-dylib}"
    local fw="$app/$folder/$name.framework"
    mkdir -p "$fw/Versions/A/Resources"
    printf 'int helper(void) { return 0; }\n' > "$WORK/$name.c"
    if [ "$kind" = executable ]; then
        printf 'int main(void) { return 0; }\n' > "$WORK/$name.c"
        cc -o "$fw/Versions/A/$name" "$WORK/$name.c"
    else
        cc -dynamiclib -o "$fw/Versions/A/$name" "$WORK/$name.c"
    fi
    local plist="$fw/Versions/A/Resources/Info.plist"
    plutil -create xml1 "$plist"
    plutil -insert CFBundleExecutable -string "$name" "$plist"
    plutil -insert CFBundleIdentifier -string "com.holzcloud.holzBar.$name" "$plist"
    plutil -insert CFBundlePackageType -string FMWK "$plist"
    ln -s A "$fw/Versions/Current"
    ln -s "Versions/Current/$name" "$fw/$name"
    ln -s Versions/Current/Resources "$fw/Resources"
}

# sign_framework APP_DIR FOLDER NAME RUNTIME(yes|no) [KEY...] signs it ad hoc.
sign_framework() {
    local app="$1" folder="$2" name="$3" runtime="$4"
    shift 4
    local args=(--force --sign -)
    [ "$runtime" = yes ] && args+=(--options runtime)
    if [ "$#" -gt 0 ]; then
        entitlements "$WORK/$name-entitlements.plist" "$@"
        args+=(--entitlements "$WORK/$name-entitlements.plist")
    fi
    codesign "${args[@]}" "$app/$folder/$name.framework" 2> /dev/null
}

# seal_app APP re-signs the app (hardened) so that its seal covers what was added to it.
seal_app() {
    codesign --force --sign - --options runtime "$1" 2> /dev/null
}

FAILURES=0
TOTAL=0

# expect NUMBER NAME EXPECTED_EXIT WORD APP runs the check and compares exit code and output.
expect() {
    local number="$1" name="$2" exit_code="$3" word="$4" app="$5"
    local output status=0
    output=$("$CHECK" "$app" 2>&1) || status=$?
    TOTAL=$((TOTAL + 1))
    if [ "$status" -ne "$exit_code" ]; then
        echo "FAIL: fixture $number $name: exit $status, expected $exit_code"
        echo "$output" | sed 's/^/      /'
        FAILURES=$((FAILURES + 1))
    elif ! grep -qF -- "$word" <<< "$output"; then
        echo "FAIL: fixture $number $name: the output lacks \"$word\""
        echo "$output" | sed 's/^/      /'
        FAILURES=$((FAILURES + 1))
    else
        echo "ok: fixture $number $name"
    fi
}

fixture none yes
expect 1 "no entitlements" 0 "entitlements: none" "$WORK/none/holzBar.app"

fixture calendars yes "$CALENDARS"
expect 2 "only the Calendars entitlement" 0 "entitlements: $CALENDARS" "$WORK/calendars/holzBar.app"

fixture camera yes "$CALENDARS" com.apple.security.device.camera
expect 3 "Calendars plus the camera" 1 "com.apple.security.device.camera" "$WORK/camera/holzBar.app"

fixture debug yes com.apple.security.get-task-allow
expect 4 "get-task-allow" 1 "lets a debugger attach" "$WORK/debug/holzBar.app"

fixture network yes com.apple.security.network.client
expect 5 "a network entitlement" 1 "com.apple.security.network.client" "$WORK/network/holzBar.app"

fixture plain no
expect 6 "not hardened" 1 "not signed with the hardened runtime" "$WORK/plain/holzBar.app"

fixture nested yes
cp "$WORK/holzBar" "$WORK/nested/holzBar.app/Contents/MacOS/helper"
codesign --force --sign - --options runtime "$WORK/nested/holzBar.app" 2> /dev/null
expect 7 "a second Mach-O file" 1 "ships no nested code" "$WORK/nested/holzBar.app"

# The helper: a hardened app that contains the one allowed framework.
HELPER=Contents/Frameworks

fixture helper yes
framework "$WORK/helper/holzBar.app" "$HELPER" NowPlayingRemote
sign_framework "$WORK/helper/holzBar.app" "$HELPER" NowPlayingRemote yes
seal_app "$WORK/helper/holzBar.app"
expect 8 "the helper framework" 0 "NowPlayingRemote.framework: hardened runtime, entitlements: none" "$WORK/helper/holzBar.app"

fixture second yes
framework "$WORK/second/holzBar.app" "$HELPER" NowPlayingRemote
sign_framework "$WORK/second/holzBar.app" "$HELPER" NowPlayingRemote yes
framework "$WORK/second/holzBar.app" "$HELPER" Other
sign_framework "$WORK/second/holzBar.app" "$HELPER" Other yes
seal_app "$WORK/second/holzBar.app"
expect 9 "a second framework" 1 "only Contents/Frameworks/NowPlayingRemote.framework may be nested" "$WORK/second/holzBar.app"

fixture entitled yes
framework "$WORK/entitled/holzBar.app" "$HELPER" NowPlayingRemote executable
sign_framework "$WORK/entitled/holzBar.app" "$HELPER" NowPlayingRemote yes com.apple.security.device.camera
seal_app "$WORK/entitled/holzBar.app"
expect 10 "the helper with an entitlement" 1 "com.apple.security.device.camera" "$WORK/entitled/holzBar.app"

fixture stripped yes
framework "$WORK/stripped/holzBar.app" "$HELPER" NowPlayingRemote
sign_framework "$WORK/stripped/holzBar.app" "$HELPER" NowPlayingRemote yes
seal_app "$WORK/stripped/holzBar.app"
codesign --remove-signature "$WORK/stripped/holzBar.app/$HELPER/NowPlayingRemote.framework" 2> /dev/null
expect 11 "the helper's signature removed" 1 "does not pass codesign --verify" "$WORK/stripped/holzBar.app"

fixture misplaced yes
framework "$WORK/misplaced/holzBar.app" Contents/Resources NowPlayingRemote
sign_framework "$WORK/misplaced/holzBar.app" Contents/Resources NowPlayingRemote yes
seal_app "$WORK/misplaced/holzBar.app"
expect 12 "the helper in the wrong folder" 1 "may be nested" "$WORK/misplaced/holzBar.app"

fixture twin yes
framework "$WORK/twin/holzBar.app" "$HELPER" NowPlayingRemote
cp "$WORK/holzBar" "$WORK/twin/holzBar.app/$HELPER/NowPlayingRemote.framework/Versions/A/Resources/second"
sign_framework "$WORK/twin/holzBar.app" "$HELPER" NowPlayingRemote yes
seal_app "$WORK/twin/holzBar.app"
expect 13 "a second Mach-O file in the helper" 1 "must hold exactly one Mach-O file" "$WORK/twin/holzBar.app"

fixture soft yes
framework "$WORK/soft/holzBar.app" "$HELPER" NowPlayingRemote
sign_framework "$WORK/soft/holzBar.app" "$HELPER" NowPlayingRemote no
seal_app "$WORK/soft/holzBar.app"
expect 14 "the helper without the hardened runtime" 1 "not signed with the hardened runtime" "$WORK/soft/holzBar.app"

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES of $TOTAL fixtures did not match" >&2
    exit 1
fi
echo "==> all $TOTAL fixtures match"
