# Feature decisions: release assignment (2026-10-09)

Decided by the maintainer, one by one, after the research in BARTENDER.md, ALTERNATIVES.md and VORSSAINT.md. 0.0.7 is the bugfix release (settings sync redesign, Phase 28); the features formerly planned for 0.0.7 "Automation" move to 0.0.8 and 0.0.9.

## 0.0.7 (bugfix release; the settings sync was withdrawn on 2026-10-09 and moved to 1.0.0)
- Native macOS 27 overflow button support (was Phase 22)
- Liquid Glass follows Reduce Transparency (was Phase 23)

## 0.0.8
- Rules: Wi-Fi, app, time, power, display, Focus (Phase 8; Focus filter spike first)
- Layout snapshots with one-click restore (Phase 9)
- Per-item conditions (Phase 10)
- Scripts as rule condition or action (Phase 11)
- Share profiles as a file (Phase 15)
- First-launch assistant (Phase 16)
- Touch ID to show hidden items (Phase 18)
- Copy diagnostics (Phase 20)
- Keyboard and VoiceOver audit (Phase 21)
- SwiftUI reordering spike (Phase 24)
- New: works without Screen Recording (app icons instead of live snapshots, Bartender 7)
- New: keep system items (Clock, Wi-Fi, Battery) pinned visible (OverflowBar)
- New: more menu bar styles, pills, outlines, gradients (limited on macOS 27)
- New (added 2026-10-09): move icons directly in the menu bar by drag and drop, without Command, across the divider and to reorder visible items (todo `2026-10-09-drag-icons-in-the-menu-bar.md`; spike on macOS 26 and 27 first)

## 0.0.9
- Widgets: text from permission-free sources, Shortcut button (Phase 12)
- AppleScript dictionary (Phase 13)
- Command palette (Phase 14)
- Opt-in usage suggestions (Phase 17)
- Smooth show and hide (Phase 19)
- Control Center control spike, optional (Phase 25)
- New: App Intents for Shortcuts and Siri
- New: replacement items for Apple items macOS 27 cannot hide (Thaw 3.0)
- New: hide system items such as Clock and Control Center (Bartender 7)
- New: "Focus mode" hotkey that hides everything except chosen items
- New: keep-awake action (IOPMAssertion, no permission)
- New: CPU, memory, battery and free-disk widget sources
- New: countdown widget

## Later (no release yet)
- Item swapping and a list of disabled items
- Audio output switch and microphone mute actions
- Network throughput widget
- Notch dock with widgets, clipboard and AirDrop (Bartender Pro)
- Clipboard history in the palette
- Quick toggles such as dark mode (needs Automation permission)
- vorssaint's other tools (window management, input remapping, screenshots, cleaner, fan control, Dynamic Island)

## No
- Local HTTP interface for AI agents (Lounge): conflicts with "never opens anything"

## Consequences for the roadmap
- Phase 26 (Swift 6.4 adoption) is technical and not in this list; place it with the 0.0.8 work.
- Phase 27 (release `0.0.7-beta1`) becomes the release of 0.0.8; the 0.0.7 betas carry Phase 28 plus the two macOS 27 items.
- New phases are needed for the new 0.0.8 items (no-Screen-Recording mode, pinned system items, menu bar styles).

## 1.0.0 (decided 2026-10-09)
- Settings sync between Macs (Phase 28 redesign, work on branch `sync/1.0.0`), withdrawn from the app and the docs until then
- Optional all-in-one modules (see MODULES-DECISIONS.md)
