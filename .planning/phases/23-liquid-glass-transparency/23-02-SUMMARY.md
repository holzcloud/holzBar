---
phase: 23-liquid-glass-transparency
plan: 02
subsystem: ui
tags: [accessibility, reduce-transparency, increase-contrast, liquid-glass, appkit, swiftui]
requires: []
provides:
  - TransparencyOptions and TransparencyTreatment, a pure tested policy in holzBar/Core
  - TransparencyObserver, a start/stop follower of the NSWorkspace display-options notification
  - Shelf and System Glass overlay that go opaque with a visible border under Reduce Transparency or Increase Contrast
  - Scripts/typecheck-app.sh, byte-identical to the copy on sync/1.0.0
affects: [23-03]
tech-stack:
  added: []
  patterns:
    - "Public NSWorkspace API read on a payload-free notification, stored only on change, observed only while a surface needs it"
key-files:
  created:
    - Scripts/typecheck-app.sh
    - holzBar/Core/TransparencyTreatment.swift
    - Tests/HolzBarCoreTests/TransparencyTreatmentTests.swift
    - holzBar/Utilities/TransparencyObserver.swift
  modified:
    - holzBar/MenuBar/Shelf/HolzBarShelf.swift
    - holzBar/MenuBar/Appearance/MenuBarOverlayPanel.swift
    - holzBar/MenuBar/Appearance/MenuBarAppearanceEditor/MenuBarAppearanceEditor.swift
    - holzBar/Resources/Localizable.xcstrings
key-decisions:
  - "A configured border wins over the visible one: it is the user's own line and a second one would double it"
  - "Window background colour is the opaque fill of System Glass; it follows light, dark and Increase Contrast by itself"
status: complete
actuals:
  tokens: 11000
  tasks: 3
  commits: 3
plan_head_before: 0c6033a59aeefc04e55092faac064fa58e931ea7
plan_head_after: ef040d9da75f9c8ba61640f18fc91d0fb05c5f74
requirements-completed: [M27-03]
completed: 2026-10-09
---

# Phase 23 Plan 02: Reduce Transparency and Increase Contrast Summary

**System Glass tint and the holzBar Shelf turn opaque with a visible border while Reduce Transparency or Increase Contrast is on, decided by a tested pure `TransparencyTreatment` and followed live through one NSWorkspace notification, public API only.**

## Tasks

| Task | Name | Commit |
| ---- | ---- | ------ |
| 1 | Tracer: policy, observer and Shelf, plus Scripts/typecheck-app.sh | 0e67bf7a |
| 2 | System Glass as opaque fill with visible border in the overlay | c6df8056 |
| 3 | Appearance pane explanation in five languages | ef040d9d |

## What was built

- `TransparencyTreatment` (Core, `nonisolated`) maps (options, glass or not, configured border or not) to (fill, border, border opacity) per the plan's decision table; named constants for the 0.9 and 0.6 opacities and the 1 pt width. Six Swift Testing tests (parameterised where the plan asked).
- `TransparencyObserver` reads `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and `...ShouldIncreaseContrast`, follows `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification` on the workspace's notification center between `start()` and `stop()`, and assigns only when the two options differ. No timer, no polling, no logging.
- Shelf: observer started in `show(section:on:)`, stopped in `close()`; the content view forces the background colour's alpha to 1 while the fill is opaque and draws the visible or configured border from one `border` value. `MenuBarItemContainer` untouched.
- Overlay: observer started only while System Glass is the tint in use (inside `updateGlassView()`); the `NSGlassEffectView` is added only when the fill is as designed; `drawTint` fills `NSColor.windowBackgroundColor` inside the shape's clip otherwise; `strokeBorder` and `draw` take the line from one `BorderLine`, so the visible line is drawn exactly like a configured one. One more `ObservationLoop` on `transparency.options` redraws and swaps glass and fill.
- Appearance pane: one sentence under the tint picker for System Glass; catalog entry inserted as a 28-line pure insertion (no re-serialisation) between "Width: %lld pt" and "Zen Mode", de/fr/it/rm.

## Verification (this Mac, no Xcode)

- `swift test --filter TransparencyTreatmentTests`: 6 tests passed.
- `Scripts/typecheck-app.sh`: exit 0, "==> holzBar type-checks", 0 errors, no warning in the touched files (one pre-existing deprecation warning in ScreenCapture.swift).
- Full `swift test` (26.5 SDK, with the testing plugin path): 354 tests in 56 suites passed, no failures. It ran after Task 2; Task 3 touched no Core file.
- SwiftLint `--strict`: 0 violations in 216 files after each task.
- `strings-check.py`: 367 strings in 5 languages, exit 0. `privacy-check.py logs` and `network`: exit 0.
- Acceptance greps: typecheck script executable and `cmp`-identical to `origin/sync/1.0.0:Scripts/typecheck-app.sh`; 6 `@Test`; one `accessibilityDisplayOptionsDidChangeNotification` line and `notificationCenter` present; 0 Timer/sleep/asyncAfter/DispatchSource in the observer; one `transparency.start()` and one `transparency.stop()` in the Shelf; 2 start/stop in `updateGlassView`; 0 `configuration.` in `strokeBorder`; 0 configured-border reads in `draw`; one `windowBackgroundColor`; no private-API or preference-domain pattern in any touched Swift file; catalog has one `"strings"` root, the entry in `"key" : {` formatting and the languages `['de', 'fr', 'it', 'rm']`.

Not verified (cannot be seen without a running app): the look on macOS 26 and 27, that the application menu and items stay visible and clickable under the opaque fill, and live switching. These are UAT items of plan 23-03 (U-02 and the live-change items; U-14 for the Romansh wording).

## Deviations from Plan

None - plan executed exactly as written. Environment notes: the full test run needed `-Xswiftc -plugin-path ...` for Swift Testing, as the task instructions said; the worktree sandbox refuses compound commands that name git paths, so some checks were run as separate commands.

## Known Stubs

None.

## Threat Flags

None. No new network, auth, file-access or schema surface; no log line added.

## Self-Check: PASSED

All created files exist and the three commits are ancestors of HEAD.
