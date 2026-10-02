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

open "holzbar://profile/$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
