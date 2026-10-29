#!/bin/bash
#
# Proves what Scripts/check-signature.sh accepts and refuses, with small fixture apps.
#
# The signature check is a security promise: holzBar.app carries exactly one entitlement,
# com.apple.security.personal-information.calendars (macOS lets a hardened app ask for
# Calendar access only with it), and every other key must fail the build and the release.
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

if [ "$FAILURES" -ne 0 ]; then
    echo "$FAILURES of $TOTAL fixtures did not match" >&2
    exit 1
fi
echo "==> all $TOTAL fixtures match"
