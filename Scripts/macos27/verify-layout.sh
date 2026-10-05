#!/bin/bash
#
# Verifies the Menu Bar Layout window on macOS 27: while it is open every item is shown;
# dragging an item into the Hidden row moves its application to the Hidden section, which
# is concealed after the window closes and stays so after holzBar restarts. The layout is
# restored afterwards.
#
# Requirements: holzBar installed with Scripts/install.sh, EXT_APP with a window on the
# external display, TEST_LABEL/TEST_BUNDLE naming a visible application with a menu bar
# item. Leave the mouse and keyboard alone.
#
# Usage: Scripts/macos27/verify-layout.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_APP="${EXT_APP:-Safari}"
TEST_LABEL="${TEST_LABEL:-Pritunl}"
TEST_BUNDLE="${TEST_BUNDLE:-com.electron.pritunl}"
REGION="700,0,1220,34"
WORK="$(mktemp -d /tmp/holzbar-verify-layout.XXXXXX)"
mkdir -p "$WORK/bin" "$WORK/steady"
for tool in pointer input layout-ax analyze-frames; do
    swiftc -O "$ROOT/Scripts/macos27/$tool.swift" -o "$WORK/bin/$tool"
done
# Only the layout key is saved and put back. Exporting the whole domain and importing it
# again carried any earlier damage forward: a second run saved the already-changed layout
# as its "before" and restored that, which is how a real layout was lost once.
#
# The key is saved and compared as an XML plist, which keeps its value types. Saved as
# `defaults read` text and written back, every rank came back as a string; holzBar reads
# the layout as [String: Int], so it then saw none, while the text still compared equal.
as_bool() { case "$1" in 1|true|YES|yes) echo true ;; *) echo false ;; esac; }
ORIGINAL_SHELF=$(as_bool "$(defaults read com.holzcloud.holzBar UseIceBar 2>/dev/null || echo 1)")
layout_xml() {
    defaults export com.holzcloud.holzBar - 2>/dev/null \
        | plutil -extract MacOS27Layout xml1 -o "$1" - >/dev/null 2>&1
}
LAYOUT_BEFORE="$WORK/layout-before.plist"
HAD_LAYOUT=false
if layout_xml "$LAYOUT_BEFORE"; then HAD_LAYOUT=true; fi
# The seeded flag goes back with it. holzBar seeds a missing layout once and then sets the
# flag, so a run that began without a layout and left the flag set left holzBar with no
# layout that it would never seed again, concealing nothing.
seeded() { defaults read com.holzcloud.holzBar MacOS27LayoutSeeded 2>/dev/null || echo absent; }
SEEDED_BEFORE=$(seeded)

quit_holzbar() {
    osascript -e 'tell application id "com.holzcloud.holzBar" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x holzBar >/dev/null || return 0; sleep 0.25; done
}
activate() { osascript -e "tell application \"$1\" to activate" >/dev/null; sleep 2.5; }
external_leftmost() {
    screencapture -x -R "$REGION" "$WORK/steady/$1.png"
    "$WORK/bin/analyze-frames" "$WORK/steady" 700 1220 | awk -v n="$1" '$1 == n { print $2 }'
}
start_holzbar() {
    open "$HOME/Applications/holzBar.app"
    for _ in $(seq 1 40); do pgrep -x holzBar >/dev/null && return 0; sleep 0.25; done
}
# Leave holzBar running, the way the run found it. A run that ended with holzBar down left the
# machine concealing nothing, and whatever was looked at next showed nothing worth seeing.
restore() {
    quit_holzbar
    if [ "$HAD_LAYOUT" = true ]; then
        defaults export com.holzcloud.holzBar "$WORK/domain.plist"
        plutil -replace MacOS27Layout -xml "$(cat "$LAYOUT_BEFORE")" "$WORK/domain.plist"
        defaults import com.holzcloud.holzBar "$WORK/domain.plist"
    else
        defaults delete com.holzcloud.holzBar MacOS27Layout 2>/dev/null || true
    fi
    if [ "$SEEDED_BEFORE" = absent ]; then
        defaults delete com.holzcloud.holzBar MacOS27LayoutSeeded 2>/dev/null || true
    else
        defaults write com.holzcloud.holzBar MacOS27LayoutSeeded -bool "$(as_bool "$SEEDED_BEFORE")"
    fi
    defaults write com.holzcloud.holzBar UseIceBar -bool "$ORIGINAL_SHELF"
    local restored=false
    if layout_xml "$WORK/layout-after.plist"; then
        if [ "$HAD_LAYOUT" = true ] && cmp -s "$LAYOUT_BEFORE" "$WORK/layout-after.plist"; then
            restored=true
        fi
    elif [ "$HAD_LAYOUT" = false ]; then
        restored=true
    fi
    if [ "$restored" = true ]; then
        echo "PASS  the saved layout is back as it was"
    elif [ "$HAD_LAYOUT" = true ]; then
        echo "FAIL  the saved layout was left changed; it was:"
        cat "$LAYOUT_BEFORE"
    else
        echo "FAIL  the saved layout was left changed; there was none"
    fi
    local seeded_after
    seeded_after=$(seeded)
    if [ "$seeded_after" != "$SEEDED_BEFORE" ]; then
        echo "FAIL  MacOS27LayoutSeeded was left changed; it was $SEEDED_BEFORE, it is $seeded_after"
    fi
    start_holzbar
}
trap restore EXIT

quit_holzbar
defaults write com.holzcloud.holzBar UseIceBar -bool true
open "$HOME/Applications/holzBar.app"
sleep 10
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
BEFORE=$(external_leftmost before)

# Reopening holzBar shows its settings; select Menu Bar Layout.
open "$HOME/Applications/holzBar.app"
sleep 3
"$WORK/bin/layout-ax" > "$WORK/settings.txt"
SIDEBAR=$(awk '/^sidebar/ { print $2, $3; exit }' "$WORK/settings.txt")
if [ -n "$SIDEBAR" ]; then
    "$WORK/bin/pointer" glide ${SIDEBAR}; "$WORK/bin/pointer" hold 0.3
    "$WORK/bin/input" click
fi
sleep 4
OPEN_LEFTMOST=$(external_leftmost layout-open)
"$WORK/bin/layout-ax" > "$WORK/layout.txt"
SOURCE=$(awk -v l="$TEST_LABEL" '$1 == "image" && $2 == 0 && index($0, l) { print $3, $4; exit }' "$WORK/layout.txt")
TARGET=$(awk '$1 == "image" && $2 == 1 { print $3, $4; exit }' "$WORK/layout.txt")
echo "layout window: sidebar=${SIDEBAR:-none} source=${SOURCE:-none} target=${TARGET:-none}"
if [ -n "$SOURCE" ] && [ -n "$TARGET" ]; then
    "$WORK/bin/input" drag ${SOURCE} ${TARGET}
fi
sleep 3
STORED=$(defaults read com.holzcloud.holzBar MacOS27Layout | sed -nE "s/^ *\"?${TEST_BUNDLE//./\\.}\"? = ([0-9]);/\1/p")
"$WORK/bin/input" close-window
sleep 3
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
AFTER_CLOSE=$(external_leftmost after-close)
quit_holzbar
open "$HOME/Applications/holzBar.app"
sleep 10
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
AFTER_RESTART=$(external_leftmost after-restart)
STORED_AFTER_RESTART=$(defaults read com.holzcloud.holzBar MacOS27Layout | sed -nE "s/^ *\"?${TEST_BUNDLE//./\\.}\"? = ([0-9]);/\1/p")

echo "before=$BEFORE layout-open=$OPEN_LEFTMOST after-close=$AFTER_CLOSE after-restart=$AFTER_RESTART stored=${STORED:-none} stored-after-restart=${STORED_AFTER_RESTART:-none}"
FAILED=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check "every item is shown while the layout window is open" "[ ${OPEN_LEFTMOST:-9999} -lt $((BEFORE - 20)) ]"
check "dragging into the Hidden row moves the application to Hidden" "[ '${STORED:-}' = 1 ]"
check "the moved application is concealed after the window closes" "[ ${AFTER_CLOSE:-0} -gt $((BEFORE + 10)) ]"
check "the move survives a restart" "[ '${STORED_AFTER_RESTART:-}' = 1 ] && [ ${AFTER_RESTART:-0} -gt $((BEFORE + 10)) ]"
echo "work: $WORK"
exit $FAILED
