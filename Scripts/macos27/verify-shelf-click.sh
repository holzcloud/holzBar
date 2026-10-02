#!/bin/bash
#
# Verifies clicking an item in the holzBar Shelf on macOS 27: the item's menu or panel opens on
# the holzBar Shelf's display — also when the other display's menu bar is active — and the
# application is concealed again once it closes.
#
# Requirements: holzBar installed with Scripts/install.sh, EXT_APP with a window on the
# external display. CLICK_LABEL names a hidden item whose click opens a menu that Escape
# closes (list the labels with shelf-ax while the holzBar Shelf is open). Leave the mouse and
# keyboard alone.
#
# Usage: Scripts/macos27/verify-shelf-click.sh <ext-empty-x> <ext-empty-y> <builtin-empty-x> <builtin-empty-y>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT_X="$1"; EXT_Y="$2"; BUILTIN_X="$3"; BUILTIN_Y="$4"
EXT_APP="${EXT_APP:-Safari}"
CLICK_LABEL="${CLICK_LABEL:-Kiro}"
REGION="700,0,1220,34"
WORK="$(mktemp -d /tmp/holzbar-verify-shelf-click.XXXXXX)"
mkdir -p "$WORK/bin" "$WORK/steady"
for tool in pointer shelf-ax new-windows input analyze-frames; do
    swiftc -O "$ROOT/Scripts/macos27/$tool.swift" -o "$WORK/bin/$tool"
done

quit_holzbar() {
    osascript -e 'tell application id "com.holzcloud.holzBar" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 40); do pgrep -x holzBar >/dev/null || return 0; sleep 0.25; done
}
activate() { osascript -e "tell application \"$1\" to activate" >/dev/null; sleep 2.5; }
external_leftmost() {
    screencapture -x -R "$REGION" "$WORK/steady/$1.png"
    "$WORK/bin/analyze-frames" "$WORK/steady" 700 1220 | awk -v n="$1" '$1 == n { print $2 }'
}
as_bool() { case "$1" in 1|true|YES|yes) echo true ;; *) echo false ;; esac; }
ORIGINAL_SHELF=$(as_bool "$(defaults read com.holzcloud.holzBar UseIceBar 2>/dev/null || echo 1)")
ORIGINAL_HOVER=$(as_bool "$(defaults read com.holzcloud.holzBar ShowOnHover 2>/dev/null || echo 1)")
start_holzbar() {
    open "$HOME/Applications/holzBar.app"
    for _ in $(seq 1 40); do pgrep -x holzBar >/dev/null && return 0; sleep 0.25; done
}
# Leave holzBar running, the way the run found it. A run that ended with holzBar down left the
# machine concealing nothing, and whatever was looked at next showed nothing worth seeing.
restore() {
    "$WORK/bin/input" escape || true
    quit_holzbar
    defaults write com.holzcloud.holzBar UseIceBar -bool "$ORIGINAL_SHELF"
    defaults write com.holzcloud.holzBar ShowOnHover -bool "$ORIGINAL_HOVER"
    start_holzbar
}
trap restore EXIT

quit_holzbar
defaults write com.holzcloud.holzBar UseIceBar -bool true
defaults write com.holzcloud.holzBar ShowOnHover -bool true
open "$HOME/Applications/holzBar.app"
sleep 10
activate "$EXT_APP"
"$WORK/bin/pointer" glide 960 540; "$WORK/bin/pointer" hold 1
HIDDEN=$(external_leftmost hidden)

# Opens the holzBar Shelf at (x, y), clicks CLICK_LABEL, records the new windows, closes the menu,
# and reads the external bar after bringing EXT_APP back to the front.
click_on() {
    local name="$1" x="$2" y="$3" away_y="$4"
    activate "$EXT_APP"
    "$WORK/bin/pointer" glide "$x" "$away_y"; "$WORK/bin/pointer" hold 1
    "$WORK/bin/pointer" glide "$x" "$y"; "$WORK/bin/pointer" hold 2.5
    "$WORK/bin/shelf-ax" > "$WORK/$name-shelf.txt"
    local target
    target=$(grep '^item ' "$WORK/$name-shelf.txt" | grep -F "$CLICK_LABEL" | head -1 || true)
    [ -n "$target" ] || target=$(grep '^item ' "$WORK/$name-shelf.txt" | head -1 || true)
    if [ -z "$target" ]; then
        echo "no item in the $name holzBar Shelf" > "$WORK/$name-windows.txt"
        return
    fi
    local item_x item_y
    item_x=$(echo "$target" | awk '{print $2}'); item_y=$(echo "$target" | awk '{print $3}')
    echo "$name: clicking $(echo "$target" | cut -d' ' -f4-)"
    "$WORK/bin/new-windows" snapshot "$WORK/$name-before.txt"
    "$WORK/bin/pointer" glide "$item_x" "$item_y"; "$WORK/bin/pointer" hold 0.3
    "$WORK/bin/input" click
    sleep 2.5
    "$WORK/bin/new-windows" diff "$WORK/$name-before.txt" > "$WORK/$name-windows.txt"
    "$WORK/bin/input" escape
    sleep 2.5
    "$WORK/bin/pointer" glide "$item_x" "$away_y"; "$WORK/bin/pointer" hold 1
    activate "$EXT_APP"
    external_leftmost "$name-after" > "$WORK/$name-after.txt"
}
click_on ext "$EXT_X" "$EXT_Y" 540
click_on builtin "$BUILTIN_X" "$BUILTIN_Y" 589

EXT_AFTER=$(cat "$WORK/ext-after.txt" 2>/dev/null || echo -1)
BUILTIN_AFTER=$(cat "$WORK/builtin-after.txt" 2>/dev/null || echo -1)
echo "hidden=$HIDDEN external-after=$EXT_AFTER built-in-after=$BUILTIN_AFTER"
echo "external click opened: $(tr '\n' ';' < "$WORK/ext-windows.txt")"
echo "built-in click opened: $(tr '\n' ';' < "$WORK/builtin-windows.txt")"
FAILED=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; FAILED=1; fi; }
check "clicking an item in the external holzBar Shelf opens its interface on the external display" "grep -q '^external ' '$WORK/ext-windows.txt'"
check "clicking an item in the built-in holzBar Shelf opens its interface on the built-in display" "grep -q '^builtin ' '$WORK/builtin-windows.txt'"
check "the application is concealed again after the external click" "[ $EXT_AFTER -ge $((HIDDEN - 3)) ]"
check "the application is concealed again after the built-in click" "[ $BUILTIN_AFTER -ge $((HIDDEN - 3)) ]"
echo "work: $WORK"
exit $FAILED
