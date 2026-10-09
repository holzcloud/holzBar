# MODULE-RECTANGLE: research for a holzBar window-management module

Researched 2026-10-09, web only. Markers: [V] verified in a primary source (repo file, API, README), [U] uncertain or inferred.

## 1. Identity, version, licence, maintenance

- Rectangle, by Ryan Hanson, Swift, based on Spectacle. Repo: https://github.com/rxhanson/Rectangle. Site: https://rectangleapp.com. [V]
- Latest release: v2.0.3, published 2026-10-05. Earlier: v2.0 (2026-09-25, UI redesign), v2.0.1 and v2.0.2 (crash fixes on macOS 15 and below 26), v1.100 (2026-08-26), v0.99 (2026-08-20), v0.98 and v0.97 (July 2026). Source: https://api.github.com/repos/rxhanson/Rectangle/releases [V]
- Maintenance: very active. Last push was 2026-10-09, about 30k stars, about 70 open issues, many first-time contributors per release. [V]
- Licence: MIT, "Copyright (c) 2019-2026 Ryan Hanson", derived from Spectacle (Eric Czarny, MIT). Source: https://raw.githubusercontent.com/rxhanson/Rectangle/main/LICENSE [V]
  - GitHub's API reports the licence as "NOASSERTION", only because the LICENSE file has an extra "based on Spectacle" line. The text is MIT. [V]
  - MIT code can be ported into a GPL-3.0 project. Keep the MIT notice and the Spectacle attribution for anything copied. [V on compatibility, general knowledge]
  - Contributors' PRs are under the same licence. Check git blame for anything copied verbatim. [U]
- Rectangle Pro is closed source and paid. It is "entirely built on top of Rectangle" according to the README. Do not copy anything from it. [V]
- Requirements: macOS 14 or later for the current release. Legacy builds exist for older systems. [V]

## 2. Complete feature list

### Rectangle (free, MIT)

Sources: README https://github.com/rxhanson/Rectangle#readme and TerminalCommands.md in the same repo. [V]

- Keyboard shortcuts (recorded with a MASShortcut fork). About 569 enum cases in `WindowAction.swift`, which include many hidden or extra actions:
  - Halves: left, right, top, bottom, center half.
  - Quarters: the four corners.
  - Thirds: first, center and last third; first and last two thirds. Repeating a third cycles through thirds.
  - Fourths: first through last, plus first and last three-fourths.
  - Sixths, ninths and eighths (including the new full-height vertical eighths); extra thirds. Some of these are off by default and are enabled through "Extras" or a `defaults write`.
  - Maximize, almost maximize, maximize height, center, center prominently, restore.
  - Smaller and larger. There are "curtain resize" options, width-only and height-only variants, and increment settings.
  - Move left, right, up, down without resizing.
  - Next and previous display. Repeated left or right can optionally traverse displays.
  - Specified (a custom size) and reverse-all.
- Snap areas: drag a window to an edge or corner.
  - Left or right edge gives a half. Top gives maximize. Corners give quarters. Just above or below a corner gives a top or bottom half.
  - Bottom thirds give thirds. Dragging from a bottom third to the bottom center gives two thirds.
  - A footprint preview window is shown. Optional blur and optional animation (both off by default).
  - Options: margin, a modifier key required to snap, drag to restore the previous size.
- Tiling (new in 2.x): tile-all, cascade-all, cascade-active-app, tile-active-app, tile rows, tile columns. Rows and columns cycle through grid layouts with configurable maximum windows per row or column.
- Stacked windows: cycle stacked windows forward and backward (v2.0.3), plus a hover badge and switcher (v0.99).
- Multi-display: next and previous display, cross-display traversal, option to keep window size when moving a maximized window to another display, combined-display mode (only when "Displays have separate Spaces" is off), Dock and menu bar insets, portrait orientation handling. [V]
- Gaps: window gaps, screen-edge gaps, and a skip-top-gap option.
- Todo mode: a hidden feature. It keeps one chosen app as a sidebar on the right of the primary display, and all other actions treat the screen as shrunken by the sidebar width. Enable it with `defaults write com.knollsoft.Rectangle todo -int 1`. Wiki: https://github.com/rxhanson/Rectangle/wiki/Todo-Mode [V]
- Stage Manager: a stage-strip width setting (`stageSize`, default 190) so actions do not overlap the strip. The code reads `com.apple.WindowManager` defaults (`GloballyEnabled`, `AutoHide`) and the Dock orientation. Source: `Utilities/StageUtil.swift`. [V]
- Ignore app: unregisters the shortcuts while a chosen app is frontmost.
- URL scheme: `rectangle://execute-action?name=...` and `rectangle://execute-task?name=ignore-app`.
- JSON config import and export. Settings are stored in `~/Library/Preferences/com.knollsoft.Rectangle.plist`.
- Launch at login, a debug log viewer, localization, a green-button override (v0.97), and a minimum-window-size HUD.
- Pitfalls the README lists: apps with a minimum window size make windows overlap; iTerm2 character-cell snapping; a rare Notification Center freeze linked to snap-drag (issue 317).

### Rectangle Pro (paid, closed source)

Source: https://rectangleapp.com/pro [V]

- Window Throw (16 sizes with one shortcut), custom snap targets, custom sizes and behaviours, workspace arrangements (restore whole app layouts), Stash mode, app pinning, menu customization, iCloud sync of config, next and previous Space actions.
- 10-day trial. One-time purchase for 3 devices. Paddle is the payment processor. Requires macOS 13.5 or later.
- None of this is needed. The README says Rectangle has "no plans" for Space-switching because Apple has no public API for it. [V]

## 3. Permissions and technical mechanism

- Permission: Accessibility only. The code calls `AXIsProcessTrusted()` in `AccessibilityAuthorization`. The README troubleshooting tells users to reset with `tccutil reset All com.knollsoft.Rectangle`. [V]
  - I did not find a Screen Recording or Input Monitoring requirement. Drag-snap uses `NSEvent.addGlobalMonitorForEvents` for mouse and key events (`EventMonitor.swift`, `SnappingManager.swift`). A global monitor for key events may involve Input Monitoring. [U]
  - There is also a `CGEventTap` callback in `EventMonitor.swift`, whose purpose I did not trace. [U]
  - Entitlements files are empty, which means no App Sandbox (a sandboxed app cannot use the AX API against other apps). [V]
- Window movement uses the Accessibility API. Source: `AccessibilityElement.swift`. [V]
  - `AXUIElementCopyAttributeValue` and `AXUIElementSetAttributeValue` read and write position and size, and the code handles `AXEnhancedUserInterface` (disabled while resizing).
  - It uses the private function `_AXUIElementGetWindow` to get a window ID, and `AXUIElementPerformAction(kAXRaiseAction)` to raise windows.
  - Screen geometry comes from `NSScreen`. `ScreenDetection.swift` handles multi-display layouts and `StageUtil` handles Stage Manager.
- Global shortcuts: MASShortcut (a Carbon `RegisterEventHotKey` wrapper, which needs no extra permission). [U on the exact mechanism; MASShortcut is known to be Carbon hotkey based]
- Network: Sparkle checks https://rectangleapp.com/downloads/updates.xml every 2 days (`SUScheduledCheckInterval` 172800). An `InternetAccessPolicy.plist` declares this one connection ("Rectangle checks for new versions"). [V]
- Dependencies: Sparkle and the MASShortcut fork, both through Swift Package Manager. [V]

## 4. macOS 26 and 27 behaviour

- Apple's native tiling (macOS 15 Sequoia, extended in 26): drag to an edge, option-drag, tiled-window margins, Fn+Ctrl+arrow shortcuts, and the Window menu "Move & Resize". Settings are in System Settings > Desktop & Dock. Sources: https://support.apple.com/guide/mac-help/mchlef287e5d and https://tinyapps.org/blog/macos-native-window-management.html [V that the feature exists; U for details in 26]
- Overlap with Rectangle:
  - Both react to the same edge-drag gesture, so the result is unpredictable. The fix is to switch off the native drag-to-tile options. Source: https://dev.to/appish/mac-window-tiling-shortcuts-not-working-whats-actually-going-on-and-how-to-fix-it-4ckc [V]
  - Rectangle detects this itself. `Utilities/MacTilingDefaults.swift` reads (and can set) the following keys in the `com.apple.WindowManager` domain:
    - `EnableTilingByEdgeDrag`
    - `EnableTilingOptionAccelerator`
    - `EnableTiledWindowMargins`
    - `EnableTopTilingByEdgeDrag`
  - Rectangle asks the user, or auto-disables top-edge tiling, when it finds a conflict. [V]
  - The native keyboard shortcuts (Fn+Ctrl+arrows) do not conflict with Rectangle's defaults. Native tiling has no gaps, no thirds beyond what Apple gives, no multi-display cycling and no Todo mode. [U on exact feature gaps in 26]
- Tahoe issues in the Rectangle tracker: #1642 "Supporting macOS Tahoe 26" and #1648 "Keyboard shortcuts not working in Tahoe 26.0", both closed. Source: https://github.com/rxhanson/Rectangle/issues?q=tahoe [V, summary from the issue list only]
- The v2.0 and later releases carry a Liquid Glass app icon with a fallback for older macOS, and the blur footprint has a code path for macOS 26 and above. [V]
- The README troubleshooting says windows misbehaving "after system updates" is usually fixed by locking and unlocking, or by a restart. [V]
- A general third-party article claims window-resizing problems on Tahoe (https://mewayz.com/is/blog/resizing-windows-on-macos-tahoe-the-saga-continues). I could not fetch it (HTTP 403), so I did not use it. [U]
- macOS 27: I found nothing specific about window-management changes or Rectangle compatibility. Treat it as untested. Release notes of 2.0.x do not call out 27. [U]

## 5. Minimal, permission-light version inside holzBar

Likely holzBar already has an Accessibility grant for menu bar work, so a window module may not add a new permission. Check this. [U]

Take (core, small and useful):
1. Keyboard-driven actions on the focused window through AX (halves, quarters, thirds, maximize, center, next and previous display, restore). Use public AX attributes only (`kAXPositionAttribute`, `kAXSizeAttribute`, `kAXFocusedWindowAttribute`). Compute rectangles from `NSScreen.visibleFrame`, which already respects the Dock and menu bar.
2. Global shortcuts via Carbon `RegisterEventHotKey`, or a small `SwiftUI` or `KeyboardShortcuts`-style recorder written in-house. This needs no Input Monitoring and no third-party package.
3. A per-window "restore" memory (in memory only).
4. Optional gaps, and the Todo and Stage Manager reservation (reading `com.apple.WindowManager` defaults is read-only and needs no permission).
5. A detection and hint for the native-tiling conflict. Read the `com.apple.WindowManager` keys and show instructions. Do not write to them without consent (Rectangle writes them itself; avoid that).
6. Optionally a URL scheme or App Intents action instead of `rectangle://`.

Optional second step (more permission cost): snap areas by drag. This needs a global mouse monitor (`NSEvent.addGlobalMonitorForEvents`), which is passive. It does not need an event tap, but verify whether it triggers Input Monitoring prompts on 26 and 27. [U] Add a footprint overlay window. This feature is the one that collides with Apple's native tiling.

Do not take:
- Sparkle and the Sparkle feed, or any update check. holzBar never uses the network. Rectangle's one declared connection is only this check.
- MASShortcut fork and any SPM dependency (no third-party packages).
- The private `_AXUIElementGetWindow` unless it is really needed. It is an undocumented symbol and a stability and review risk. Prefer matching windows by AX element comparison or by `AXUIElement` identity for the short time needed.
- Writing to `com.apple.WindowManager` defaults without the user's explicit click (Rectangle auto-disables top tiling).
- Animation and the experimental drag-restore logic, cooperative corner resize, and the long list of about 569 action cases. They add complexity and edge-case bugs (README calls animation "experimental").
- Everything from Rectangle Pro (closed source, paid): workspaces, Stash mode, app pinning, window throw, iCloud sync, Space switching.
- Rows and columns tiling and stacked-window switcher: only as later opt-in extras.
- Telemetry or logging that leaves the machine (Rectangle's debug log is local; the module can keep a similar in-app log).

Licence handling: write the module's code fresh, using Rectangle only as a behavioural reference. If any Rectangle source is copied, keep the MIT notice and the Spectacle attribution in a NOTICE file, and note that the combined work is GPL-3.0. [V on MIT, general knowledge on the compatibility]

## 6. Open points to verify before building

1. Whether `NSEvent.addGlobalMonitorForEvents` for `.leftMouseDragged` and `.keyDown` needs Input Monitoring on macOS 26 and 27 (the key-down part is the likely trigger).
2. Whether the native tiling keys and the `com.apple.WindowManager` defaults are unchanged in macOS 27.
3. The purpose of the `CGEventTap` in `EventMonitor.swift` (shortcut-recording suppression or snap-drag).
4. How AX behaves in 26 with Liquid Glass window chrome: window size limits, and apps that refuse AX resizing (Electron, some Catalyst apps).
5. macOS 27 behaviour in general: nothing found.

## Sources

- https://github.com/rxhanson/Rectangle (README, LICENSE, TerminalCommands.md, `Rectangle/*.swift`, `InternetAccessPolicy.plist`, `Info.plist`)
- https://api.github.com/repos/rxhanson/Rectangle/releases and https://api.github.com/repos/rxhanson/Rectangle
- https://github.com/rxhanson/Rectangle/wiki/Todo-Mode
- https://github.com/rxhanson/Rectangle/issues?q=tahoe
- https://rectangleapp.com and https://rectangleapp.com/pro
- https://support.apple.com/guide/mac-help/mchlef287e5d
- https://tinyapps.org/blog/macos-native-window-management.html
- https://dev.to/appish/mac-window-tiling-shortcuts-not-working-whats-actually-going-on-and-how-to-fix-it-4ckc
