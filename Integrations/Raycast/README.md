# Raycast

[Script commands](https://github.com/raycast/script-commands) that control holzIce from Raycast.

1. In Raycast, open **Settings → Extensions → Script Commands → Add Directories** and choose this folder (or copy the scripts into your own script folder).
2. Run "Toggle Hidden Items", "Search Menu Bar Items", "Apply holzIce Profile", …

The scripts open `holzice://` URLs, so the same commands work from Alfred, Shortcuts or a terminal:

| URL | Action |
|---|---|
| `holzice://toggle/hidden` | Show or hide the hidden section (`show/…`, `hide/…` also work) |
| `holzice://toggle/always-hidden` | Show or hide the always-hidden section |
| `holzice://search` | Open the menu bar item search |
| `holzice://settings` | Open the settings |
| `holzice://ice-bar/toggle` | Turn the holzIce Bar on or off |
| `holzice://auto-rehide/toggle` | Turn auto-rehide on or off |
| `holzice://application-menus/toggle` | Hide or show the application menus |
| `holzice://profile/<name>` | Apply a saved layout profile |
