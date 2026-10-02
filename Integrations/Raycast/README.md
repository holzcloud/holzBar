# Raycast

[Script commands](https://github.com/raycast/script-commands) that control holzBar from Raycast.

1. In Raycast, open **Settings → Extensions → Script Commands → Add Directories** and choose this folder (or copy the scripts into your own script folder).
2. Run "Toggle Hidden Items", "Search Menu Bar Items", "Apply holzBar Profile", …

The scripts open `holzbar://` URLs, so the same commands work from Alfred, Shortcuts or a terminal:

| URL | Action |
|---|---|
| `holzbar://toggle/hidden` | Show or hide the hidden section (`show/…`, `hide/…` also work) |
| `holzbar://toggle/always-hidden` | Show or hide the always-hidden section |
| `holzbar://search` | Open the menu bar item search |
| `holzbar://settings` | Open the settings |
| `holzbar://shelf/toggle` | Turn the holzBar Shelf on or off |
| `holzbar://auto-rehide/toggle` | Turn auto-rehide on or off |
| `holzbar://application-menus/toggle` | Hide or show the application menus |
| `holzbar://profile/<name>` | Apply a saved layout profile |

The `holzice://` URLs from holzIce, including `holzice://ice-bar/toggle`, still work.
