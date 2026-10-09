# MODULE: Flameshot replacement (capture + annotate)

Research date: 2026-10-09. Web only, no code. Confidence marks: [V] verified in a fetched source, [U] uncertain / secondhand.

## 1. Flameshot facts
- Current version: v14.0.0, published 2026-06-19 [V] https://api.github.com/repos/flameshot-org/flameshot/releases/latest
  - macOS items in the notes: new icon set, clipboard fixes, permission request via CGRequestScreenCaptureAccess, fullscreen overlay behaviour configurable, multi-monitor selection.
- Licence: GPLv3+ for main code; logo Free Art License 1.3, icons Apache 2.0 [V] https://github.com/flameshot-org/flameshot . Compatible with holzBar GPL-3.0 for ideas; do not copy code/icons without checking per-file licence (Apache icons are GPL-3 compatible, but attribute).
- Maintenance: active (2,373 commits, ~671 open issues, ~75 open PRs at fetch time; v14 six months ago) [V]. Project is large and Linux-first.
- Features [V unless marked]: region capture GUI (`flameshot gui`), full screen (`full`), per-screen (`screen`), delay, save path, copy to clipboard flags, config UI, screenshot history, DBus interface (Linux), tray icon, dock icon when config open.
- Annotation tools and keys [V] https://flameshot.org/docs/guide/key-bindings/ : Pencil p, Line d, Arrow a, Selection s, Rectangle r, Circle c, Marker m, Text t, Pixelate (blur) b, colour picker g, right-click colour wheel, wheel = thickness, undo/redo, move/resize selection with arrows, spacebar sidebar. Numbered counter bubbles exist in Flameshot (counter tool) [U: not in the fetched key table]. Also "invert", "rectangle selection" tools [U].
- Outputs: copy (Ctrl+C), save (Ctrl+S), pin to screen, open in other app (Ctrl+O), upload to Imgur (Return) [V for all but pin: pin is a known Flameshot feature, U for source].
- Imgur upload: this is the network feature. Drop entirely (see section 5).

## 2. macOS version of Flameshot
- Qt based; macOS build is second-class. Install needs right-click Open / quarantine removal on macOS 15+ (unsigned/not notarised) [V, repo README].
- Known issues in tracker (115 hits for macOS 26/27 search at fetch time) [V via issue list summary]: repeated permission prompts despite grant; capture shows only wallpaper; overlay not above menu bar/Dock; Dock overlaps tools; multi-monitor scaling skew with mixed DPI; clipboard publishes TIFF not PNG; tray-menu silent quit; global shortcuts failing (#3933, Sequoia 15.4.1, unconfirmed) https://github.com/flameshot-org/flameshot/issues/3933 ; Gatekeeper "could not verify" on dmg; translations missing in bundle.
- These are exactly the pain points a native module can fix (overlay window level, Retina, clipboard types).

## 3. Permissions
- Screen Recording (TCC "ScreenCapture"). v14 uses CGRequestScreenCaptureAccess [V]. For holzBar: CGPreflightScreenCaptureAccess to check, CGRequestScreenCaptureAccess to prompt, deep link to System Settings > Privacy > Screen & System Audio Recording. Request only when the module is switched on / first capture, never at launch.
- macOS 15+ shows recurring "allow/continue" re-confirmation prompts for apps that use the legacy capture path or ScreenCaptureKit continuous capture [U, from Apple 15 behaviour; verify on 26/27]. SCContentSharingPicker and system screenshot UI avoid needing the standing permission [U-verify].

## 4. macOS 26 / 27 API situation
- CGWindowListCreateImage / CGDisplayCreateImage: deprecated 14.0, marked obsoleted in 15.0 [V-ish, secondhand] https://developer.apple.com/forums/thread/748798 ; Chromium tracking https://issues.chromium.org/issues/40275728.
- macOS 27 ("Golden Gate"): per publicspace.net, "the desktop screenshot call is gone" - it returns nothing and raises no error; broke wallpaper-painting menu bar tools (Boring Old Menu Bar 1.28, TopNotch) [V as claim of that article] https://www.publicspace.net/blog/macos-27-menu-bar/ . The article does not name the exact function. A different aggregator says the symbols "still exist and work in macOS 27" but are obsoleted [U, conflicting, https://tools.webstarted.com/macos-27/]. Conclusion: assume legacy CG capture is unreliable/empty on 27; this matches Flameshot's "only wallpaper"/blank-capture class of bugs. Must be re-tested on a real 27 machine (user cannot test 14/15 only; has 26/27?).
- Replacement path (public): ScreenCaptureKit.
  - SCShareableContent (displays/windows), SCContentFilter, SCStreamConfiguration (pixelFormat, scale, colorSpace, showsCursor).
  - SCScreenshotManager.captureImage(contentFilter:configuration:) -> CGImage (macOS 14+); captureSampleBuffer; macOS 15.2+ adds captureImage(in: CGRect) for a global-coordinate rect [V that API exists: Apple docs page; availability U].
  - SCContentSharingPicker: system-owned picker (macOS 14+); user chooses display/window; app gets a filter without needing the standing Screen Recording grant. Whether it supports a region selection is U. Region selection in holzBar must therefore be own overlay.
  - Caveat: capturing without holzBar's own overlay in the image: exclude own windows via SCContentFilter(excludingWindows:).
- Alternative zero-permission route [U]: shell out to /usr/sbin/screencapture (-i, -R, -c). Public binary, no extra permission for holzBar itself, but no annotation overlay integration and spawns a process; acceptable fallback but not "native".

## 5. What a native Swift/AppKit module needs (public APIs only)
1. Capture: ScreenCaptureKit (SCScreenshotManager) one frozen frame per display at capture start; fall back to nothing (do not use CGWindowListCreateImage on 26/27).
2. Region overlay: borderless NSPanel per NSScreen at level above .mainMenu/.screenSaver, collectionBehavior canJoinAllSpaces + fullScreenAuxiliary, showing the frozen image dimmed, crosshair cursor, drag select, handles, size readout. Handle backingScaleFactor and mixed-DPI displays per screen.
3. Annotation: custom NSView/CALayer or Core Graphics model of shapes (arrow, line, rect, ellipse, pen, marker/highlight, text via NSTextField, numbered counter, pixelate/blur via CIFilter CIPixellate / CIGaussianBlur on the cropped region). Undo via UndoManager. Colour via NSColorPanel/own palette.
4. Output: NSPasteboard (write PNG and TIFF), NSSavePanel/default folder (needs sandbox-less file access or user-selected folder bookmark), pin = floating borderless NSPanel (level .floating) with the image, optional "open with" via NSWorkspace.
5. Hotkey: Carbon RegisterEventHotKey (no Accessibility permission) as holzBar likely already does.
6. Permissions: Screen Recording only, requested lazily; no Accessibility, no Full Disk Access, no network entitlement.
7. No third-party packages: all above is in AppKit, CoreImage, ScreenCaptureKit, UniformTypeIdentifiers.

## 6. Must not be taken
- Imgur upload (network, client id, history of uploads) and any "upload"/URL-share flow; also any Qt update check / telemetry-like features and the DBus/CLI server mode. holzBar has no network: omit the network entitlement so it cannot return.
- Replacing Return-key = upload binding; make Return = copy and close.
- Flameshot source code/translations should not be copied (Qt/C++; GPL-3+ is compatible but tied to Qt design); take only the UX feature set.

## 7. Risks / open questions
- Exact macOS 27 behaviour of CGWindowListCreateImage and whether SCScreenshotManager needs a persistent TCC grant or the picker route suffices: verify on a macOS 27 machine.
- Region capture through SCContentSharingPicker is probably unavailable; own overlay needs Screen Recording.
- Pin feature, counter tool and tool list should be re-confirmed against Flameshot docs (flameshot.org docs 404 for macOS notes page).
- Recurring monthly-style permission re-prompt behaviour on 26/27 for ScreenCaptureKit users: [U].
