#!/bin/bash
# Renders the design illustrations in Resources/Mockups/design-*.png from
# Resources/Mockups/design-mockups.html with headless Chrome (transparent corners, 2x).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
render() { # name width height
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --force-device-scale-factor=2 --window-size="$2,$3" \
    --screenshot="$ROOT/Resources/Mockups/design-$1.png" \
    "file://$ROOT/Resources/Mockups/design-mockups.html#$1" >/dev/null 2>&1
}
render general-dark 1000 700
render automation-light 1000 500
