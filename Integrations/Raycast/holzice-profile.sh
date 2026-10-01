#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Apply holzIce Profile
# @raycast.mode silent
# @raycast.packageName holzIce
# @raycast.argument1 { "type": "text", "placeholder": "Profile name" }

# Optional parameters:
# @raycast.icon 🧊
# @raycast.description Apply a saved menu bar layout profile.

open "holzice://profile/$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
