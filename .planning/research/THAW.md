# Thaw comparison (2026-10-03)

Thaw (https://github.com/thaw-app/Thaw, GPL-3.0) is another Ice fork. This comparison is based on its CHANGELOG (2.0 to 3.0.0-beta.1), its README and its git history. A shallow clone is at /home/user/thaw-app/thaw. The same license means code can be adapted with credit, one NOTICE line per adapted file.

## Chosen by the user (all of it)

### Fixes (Phase 05.1.1)
- THAW-01 Item identity survives title changes: learn which apps change their menu bar title (counts, dates) and keep one identity for several items of one app. Restore items by one deterministic path and re-check after app launches. (Thaw 3.0.0-alpha.7 #973 #1125 #1175, 2.0.0 "Item identity & restoration"; holzBar's open group "Items lose their section".)
- THAW-02 Menus and clicks:
  - Auto-rehide no longer sticks on another app's small floating windows; only real menus count (#1158).
  - Clicks near or under the clock only count inside the menu bar rectangle, and Notification Center follows the click instead of a fixed timer (#1171 #1191 #1152).
  - No Dock icon while Settings or items are shown (#1197).
- THAW-03 Robustness:
  - Event monitors health-check and recover, and the first click after monitoring starts is not missed.
  - Back-off after repeated failed moves.
  - Pause while the screen is locked; settle after wake and display reconnect.
  - Re-apply the appearance after sleep and launch at login.
  - Tint and shape follow the icons immediately, step aside in full screen, and show during a reveal (#1139).
- THAW-04 Second display and notch (macOS 27):
  - Pointer and click hit-testing against the correct display; menus no longer close on the second display (#1159 #1138 #1137).
  - Notch overflow comes back on a wider display, and the icon is never under the notch (#1106 #1195 #1153).
  - Spacing no longer relaunches every app when a display is unplugged (apply at the next launch or on "Reapply Spacing"), and there is no spacing prompt after sleep/wake (#1215 #1180).
- THAW-05 Faster reveal: a click on empty bar space reveals in about 70 ms instead of waiting for a fresh bar picture, and the first click works with double-click Always Hidden.
- THAW-06 No screenshot before hiding or showing on macOS 27 (no recording indicator, no flash; draw the cover from what is behind) (#1161 #1181).
- THAW-07 The event-tap path never blocks on other apps' AX trees (no freeze when an app hangs).
- THAW-08 Audit the `holzbar://` commands: anything that changes the layout without a user step is removed or needs a user step.

### Features (Phase 05.1.1.1)
- THAW-10 Zen mode: one action or hotkey conceals everything and locks reveal gestures; optionally on while presenting or screen sharing (no extra permission).
- THAW-11 Profiles bound to a display (auto-switch on connect), then to a Space.
- THAW-12 Briefly reveal a hidden item when its icon blinks or changes (event-driven through AX notifications, no polling).
- THAW-13 Hide items opened from the Shelf or search again after 0–30 s; optionally open them in place in the bar (#342).
- THAW-14 Keyboard control:
  - Open an item by letter (item hints).
  - Tab, arrows and Option-arrows in the Layout editor and the Shelf.
  - Undo (⌘Z) for layout moves and profile changes.
  - VoiceOver actions.
- THAW-15 More hotkeys: per profile, per item menu, Zen mode. Shortcuts integration through App Intents (no scripts, no CLI).
- THAW-16 Folders: a group shown as a folder with its own icon and colour. Choose an own image for an item, or use the app's icon when there is no capture (#912 #1087).
- THAW-17 Appearance extras: adaptive tint from the wallpaper, dashed or dotted borders, system glass (Liquid Glass) on macOS 26+, accent-colour fills.

## Excluded by holzBar's principles
- Sparkle update channel, Crowdin, Discord links.
- AppleScript or shell hooks and a CLI (privilege and attack surface).
- Location triggers, script triggers and anything that polls.

# Ice upstream scan (2026-10-03)

Ice's `main` has had no commits since 2025-09-20. Everything new is in open PRs and new issues, which `gh api` cannot reach (403); a shallow clone is in the scratchpad.

## Chosen by the user
- ICE-01 (05.1.1) Hardening from jordanbaird/Ice#985:
  - Hotkey decoding rejects out-of-range key codes, so a hostile defaults write cannot cause a crash loop.
  - Colour arrays are validated.
  - Window titles are kept out of the logs.
- ICE-02 (05.1.1) Small fixes:
  - #900: no crash when every show mode is off.
  - #933: show on click is skipped while an overlay covers the menu bar.
  - #911: clicks in the Shelf are reliable on macOS 26.
  - #923: spacing restarts every app on Apply (reconcile with THAW-04).
- ICE-03 (05.1.1) #1007 (macOS 27): an app that launches while items are concealed gets a squashed 3 pt item. On `didLaunchApplicationNotification`, release the app from the assertion until its status item exists, then conceal again.
- ICE-04 (05.1.1) The rest of #1001 (macOS 27):
  - Hidden items opened from search or the layout go through `ItemClicker27`.
  - System and bundleless items are disabled, with tooltips.
  - Settings that do nothing on 27 are hidden.
  - Wallpaper window ownership.
  - Hover and click frames on several displays.
  - Its known issue to check: MenuBarAgent removes the control item while assertions are active.
- ICE-05 (05.1.1.1) Localization (#1000, #1002) through a String Catalog: English, German, French, Italian and Romansh, matching the website; no language switcher download.
- ICE-06 (05.1.1) Bring docs/upstream-bugs.md up to date:
  - Add #1005 to the fixed macOS 27 row, and #1007 as a new open row (or fixed).
  - Add #974 and #968 to the auto-rehide group, #988 and #959 to the wrong-place group, #979 to the lost-section group, and #961 to the Dock group.
  - #976 is not a bug.

## User decisions (2026-10-03)

- Dock icon: never show it ("Keep the Dock icon hidden", on by default), as planned in 05.1.1-02.
- Zen mode locks the same things as in Thaw, as planned in 05.1.1.1-01.
- Translations: machine-written; the user checks them before the release.
