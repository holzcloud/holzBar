#!/bin/bash
#
# Answers one question from the SDK alone: does a public API report or set the user's
# system-wide Liquid Glass clarity level (the slider of macOS 27, System Settings,
# Appearance), so that holzBar's System Glass tint could follow it (M27-04)?
#
# It reads only the public headers and Swift interfaces below the SDK's
# System/Library/Frameworks, never the SDK's folder of private frameworks: whatever lives
# there is by definition not public. "Public" means a documented symbol in the SDK.
#
# How to read the result:
#   exit 0  VERDICT: no public signal ...   every glass, transparency and contrast
#                                           identifier is on a known list below.
#   exit 1  VERDICT: <k> unlisted ...       read each UNLISTED declaration in the SDK before
#                                           deciding; a documented symbol that reports the
#                                           user's glass choice is the finding the spike
#                                           exists to make and must NOT be added to a list.
#   exit 2  VERDICT: scan invalid ...       wrong SDK path or a moved file; the six anchors,
#                                           symbols that are known to be public, were not
#                                           all found. This never reads as "nothing found".
#
# Re-run it with every new SDK or Xcode; a new unlisted identifier reopens the decision.
#
# Usage: Scripts/macos27/scan-glass-api.sh
#        SDK=/path/to/MacOSX27.0.sdk Scripts/macos27/scan-glass-api.sh
set -euo pipefail

SDK="${SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk}"
FRAMEWORKS="$SDK/System/Library/Frameworks"

if [ ! -d "$FRAMEWORKS" ]; then
    echo "VERDICT: scan invalid, no SDK at $SDK"
    exit 2
fi

SDK_VERSION="$(plutil -extract Version raw "$SDK/SDKSettings.plist" 2>/dev/null || echo unknown)"
echo "SDK: $SDK (version $SDK_VERSION)"

# Public identifiers that are not a signal of the user's glass choice.
KNOWN_GLASS="
glass
nsglasseffectview
nsglasseffectviewstyle
nsglasseffectviewstyleregular
nsglasseffectviewstyleclear
nsglasseffectcontainerview
nsbezelstyleglass
glasseffect
glasseffectid
glasseffectunion
glasseffecttransition
glasseffectcontainer
defaultglasseffectshape
glassbuttonstyle
glassprominentbuttonstyle
glassprominent
"

KNOWN_TRANSPARENCY="
_transparent
transparent
istransparent
transparency
translucent
nstransparentbinding
nsimagedithertransparency
dithertransparency
titlebarappearstransparent
colorschemecontrast
_colorschemecontrast
_contrasteffect
contrast
contrasting
accessibilityreducetransparency
_accessibilityreducetransparency
accessibilitydisplayshouldreducetransparency
accessibilitydisplayshouldincreasecontrast
nsapplicationpresentationdisablemenubartransparency
nsappearancenameaccessibilityhighcontrastaqua
nsappearancenameaccessibilityhighcontrastdarkaqua
nsappearancenameaccessibilityhighcontrastvibrantlight
nsappearancenameaccessibilityhighcontrastvibrantdark
"

APPKIT="$FRAMEWORKS/AppKit.framework"
SWIFTUICORE="$FRAMEWORKS/SwiftUICore.framework"

# first_file <directory> <file name>: the first file with that name below the directory.
first_file() {
    find "$1" -type f -name "$2" 2>/dev/null | head -n 1
}

# Step 1, anchors: symbols known to be public, each in a named file.
ANCHORS_OK=1
check_anchor() { # <symbol> <directory> <file name>
    local file
    file="$(first_file "$2" "$3")"
    if [ -n "$file" ] && grep -q -F -- "$1" "$file"; then
        echo "ANCHOR ok: $1"
    else
        echo "ANCHOR MISSING: $1"
        ANCHORS_OK=0
    fi
}
check_anchor accessibilityDisplayShouldReduceTransparency "$APPKIT" NSAccessibility.h
check_anchor accessibilityDisplayShouldIncreaseContrast "$APPKIT" NSAccessibility.h
check_anchor accessibilityDisplayOptionsDidChangeNotification "$APPKIT" AppKit.apinotes
check_anchor NSGlassEffectViewStyleRegular "$APPKIT" NSGlassEffectView.h
check_anchor accessibilityReduceTransparency "$SWIFTUICORE" arm64e-apple-macos.swiftinterface
check_anchor colorSchemeContrast "$SWIFTUICORE" arm64e-apple-macos.swiftinterface
if [ "$ANCHORS_OK" -ne 1 ]; then
    echo "VERDICT: scan invalid, anchors missing"
    exit 2
fi

# The focused file set for steps 2 and 3, one path per line.
FOCUSED="$(mktemp)"
trap 'rm -f "$FOCUSED"' EXIT
{
    find "$APPKIT" -type f \( -name '*.h' -o -name 'AppKit.apinotes' -o -name 'arm64e-apple-macos.swiftinterface' \)
    find "$FRAMEWORKS/SwiftUI.framework" "$SWIFTUICORE" -type f -name 'arm64e-apple-macos.swiftinterface'
    find "$FRAMEWORKS/Accessibility.framework" -type f -name '*.h'
} | sort -u > "$FOCUSED"
echo "Focused files: $(wc -l < "$FOCUSED" | tr -d ' ')"

# identifiers <extended regex> <file list>: distinct lowercase identifiers matching the
# regex, with counts, without compiler-mangled names (s<digit>... and $s...).
identifiers() {
    xargs grep -o -h -i -E "[A-Za-z0-9_\$]*($1)[A-Za-z0-9_\$]*" < "$2" 2>/dev/null \
        | tr '[:upper:]' '[:lower:]' \
        | grep -v -E '^(s[0-9]|\$s)' \
        | sort | uniq -c | sort -k2 \
        || true
}

UNLISTED=0
GLASS_COUNT=0
TRANSPARENCY_COUNT=0

report() { # <label> <known list> <identifier counts>
    local count name
    while read -r count name; do
        [ -n "$name" ] || continue
        if printf '%s\n' "$2" | grep -q -x -F -- "$name"; then
            echo "known $1 identifier: $name ($count)"
        else
            echo "UNLISTED $1 identifier: $name ($count)"
            UNLISTED=$((UNLISTED + 1))
        fi
    done <<< "$3"
}

echo "--- glass identifiers"
GLASS="$(identifiers 'glass' "$FOCUSED")"
GLASS_COUNT="$(printf '%s\n' "$GLASS" | grep -c . || true)"
report glass "$KNOWN_GLASS" "$GLASS"

echo "--- transparency and contrast identifiers"
TRANSPARENCY="$(identifiers 'transparen|translucen|contrast|clarity' "$FOCUSED")"
TRANSPARENCY_COUNT="$(printf '%s\n' "$TRANSPARENCY" | grep -c . || true)"
report transparency "$KNOWN_TRANSPARENCY" "$TRANSPARENCY"

# Step 4, informational sweep over every public framework.
echo "--- informational, does not change the verdict: every public framework"
ALL="$(mktemp)"
trap 'rm -f "$FOCUSED" "$ALL"' EXIT
find "$FRAMEWORKS" -type f \( -name '*.h' -o -name '*.apinotes' -o -name '*.swiftinterface' \) > "$ALL"
identifiers 'liquid|clarity|reducetransparency|increasecontrast|transparencylevel|glass' "$ALL" || true

echo "---"
if [ "$UNLISTED" -eq 0 ]; then
    echo "VERDICT: no public signal for a Liquid Glass slider in $(basename "$SDK") ($GLASS_COUNT glass and $TRANSPARENCY_COUNT transparency/contrast identifiers, all known)"
    exit 0
fi
echo "VERDICT: $UNLISTED unlisted identifiers, inspect them before deciding"
exit 1
