# Raycast

[Script commands](https://github.com/raycast/script-commands) that control holzBar from Raycast.

1. In Raycast, open **Settings → Extensions → Script Commands → Add Directories** and choose this folder (or copy the scripts into your own script folder).
2. Run "Toggle Hidden Items", "Search Menu Bar Items", "Apply holzBar Profile", …

The scripts open `holzbar://` URLs, so the same commands work from Alfred, Shortcuts or a terminal:

| URL | Action | Changes |
|---|---|---|
| `holzbar://toggle/hidden` | Show or hide the hidden section (`show/…`, `hide/…` also work) | Nothing persistent |
| `holzbar://toggle/always-hidden` | Show or hide the always-hidden section | Nothing persistent |
| `holzbar://search` | Open the menu bar item search | Nothing persistent; ignored while Zen mode is on |
| `holzbar://settings` | Open the settings | Nothing persistent; ignored while Zen mode is on |
| `holzbar://shelf/toggle` | Turn the holzBar Shelf on or off | A setting that syncs, asks first |
| `holzbar://auto-rehide/toggle` | Turn auto-rehide on or off | A setting that syncs, asks first |
| `holzbar://application-menus/toggle` | Hide or show the application menus | Nothing persistent |
| `holzbar://zen/on` | Turn Zen mode on: hidden items stay hidden until it is off | Nothing persistent |
| `holzbar://zen/off`, `holzbar://zen/toggle` | Turn Zen mode off (or on, while it is off) | Asks first; refused while the screen is shared |
| `holzbar://profile/<name>` | Apply a saved layout profile | Rearranges items, asks first |

Any app can open these URLs, and a web page can once your browser has asked, so every command that changes something lasting asks first: holzBar shows a question such as "Apply the layout profile …?" or "Turn off the holzBar Shelf?", and only a click on the button acts (Return answers nothing, Escape cancels). The question names only profiles you saved, never text from the URL; one question is open at a time, and after you cancel one, holzBar ignores such commands for 30 seconds.

While Zen mode is on, no URL reveals hidden items or changes a setting: `show` and `toggle` of a hidden section, the search, Settings, the Shelf and auto-rehide toggles and profiles are ignored. A URL can always turn Zen mode on. Turning it off asks first, and while the screen is shared (Zen mode turned on by "Turn on Zen mode while the screen is mirrored or shared"), only you can turn it off, from holzBar's menu, its hotkey or Shortcuts.

## Shortcuts

The Shortcuts app offers the same actions without a script: **Toggle Zen Mode**, **Change Section** (show, hide or toggle the hidden or always-hidden section), **Apply Layout Profile**, **Open Menu Bar Item** (by name) and **Search Menu Bar Items**. They run inside holzBar without the question, because you built the shortcut yourself, and need no extra permission.

`holzbar://ice-bar/toggle`, the command's name in Ice, still works.
