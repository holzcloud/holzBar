# Raycast

[Script commands](https://github.com/raycast/script-commands) that control holzBar from Raycast.

1. In Raycast, open **Settings → Extensions → Script Commands → Add Directories** and choose this folder (or copy the scripts into your own script folder).
2. Run "Toggle Hidden Items", "Search Menu Bar Items", "Apply holzBar Profile", …

The scripts open `holzbar://` URLs, so the same commands work from Alfred, Shortcuts or a terminal:

| URL | Action | Changes |
|---|---|---|
| `holzbar://toggle/hidden` | Show or hide the hidden section (`show/…`, `hide/…` also work) | Nothing persistent |
| `holzbar://toggle/always-hidden` | Show or hide the always-hidden section | Nothing persistent |
| `holzbar://search` | Open the menu bar item search | Nothing persistent |
| `holzbar://settings` | Open the settings | Nothing persistent |
| `holzbar://shelf/toggle` | Turn the holzBar Shelf on or off | A setting the same command flips back |
| `holzbar://auto-rehide/toggle` | Turn auto-rehide on or off | A setting the same command flips back |
| `holzbar://application-menus/toggle` | Hide or show the application menus | Nothing persistent |
| `holzbar://profile/<name>` | Apply a saved layout profile | Rearranges items, asks first |

Any app can open these URLs, so the only command that rearranges the menu bar asks first: holzBar shows "Apply the layout profile …?" with Cancel as the default answer. Shortcuts actions (App Intents) will run without the question, because you built them yourself.

`holzbar://ice-bar/toggle`, the command's name in Ice, still works.
