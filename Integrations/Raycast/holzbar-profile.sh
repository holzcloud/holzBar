#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Apply holzBar Profile
# @raycast.mode silent
# @raycast.packageName holzBar
# @raycast.argument1 { "type": "text", "placeholder": "Profile name" }

# Optional parameters:
# @raycast.icon 🪵
# @raycast.description Apply a saved menu bar layout profile.

# Encodes every reserved character, "/" too: holzBar reads only the first path component as
# the name, so "Home/Office" would otherwise ask for "Home". osascript ships with macOS;
# python3 needs the Command Line Tools and, without them, printed nothing. "--" ends
# osascript's options, so a name such as "-Work" reaches the script instead.
[ -n "${1:-}" ] || exit 1
NAME="$(osascript -l JavaScript -e 'function run(argv) { return encodeURIComponent(argv[0]) }' -- "$1")" || exit 1
[ -n "$NAME" ] || exit 1
open "holzbar://profile/$NAME"
