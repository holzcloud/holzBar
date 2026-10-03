---
gsd_state_version: "1.0"
milestone: v0.0.6
current_phase: 1
current_phase_name: CI and build
status: verifying
stopped_at: Completed 05.1.1.1-03-PLAN.md
last_updated: "2026-10-03T08:14:39.348Z"
last_activity: 2026-10-02
last_activity_desc: Roadmap created (6 phases, 37 requirements mapped)
state_head: 37ae8076c04bdf4f1db40d027dddd50e84558ec4
progress:
  total_phases: 13
  completed_phases: 0
  total_plans: 29
  completed_plans: 29
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-02)

**Core value:** The menu bar items a user hides stay hidden and come back when asked, on every supported macOS version, without the app ever locking up the Mac.
**Current focus:** Phase 1 - CI and build

## Current Position

Phase: 1 of 6 (CI and build)
Plan: 0 of 0 in current phase
Status: Phase complete — ready for verification
Last activity: 2026-10-02 — Roadmap created (6 phases, 37 requirements mapped)

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: - min
- Total execution time: 0.0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 01 P01 | 20min | 2 tasks | 2 files |
| Phase 01 P02 | 10min | 2 tasks | 5 files |
| Phase 01 P03 | 12min | 2 tasks | 4 files |
| Phase 01.1 P01 | 15min | 2 tasks | 190 files |
| Phase 01.1 P02 | 20min | 2 tasks | 48 files |
| Phase 01.1 P03 | 11min | 2 tasks | 69 files |
| Phase 01.1 P04 | 20min | 2 tasks | 15 files |
| Phase 01.1 P06 | 20min | 2 tasks | 10 files |
| Phase 02 P01 | 16min | 2 tasks | 4 files |
| Phase 02 P02 | 15min | 2 tasks | 7 files |
| Phase 02 P03 | 20min | 2 tasks | 7 files |
| Phase 02 P04 | 12min | 2 tasks | 4 files |
| Phase 03 P01 | 16min | 2 tasks | 17 files |
| Phase 03 P02 | 10min | 3 tasks | 15 files |
| Phase 04 P01 | 18min | 3 tasks | 12 files |
| Phase 04 P02 | 16min | 3 tasks | 12 files |
| Phase 04 P03 | 20min | 2 tasks | 10 files |
| Phase 05 P01 | 7min | 2 tasks | 9 files |
| Phase 05 P02 | 16min | 3 tasks | 11 files |
| Phase 05.1 P01 | 23min | 3 tasks | 56 files |
| Phase 05.1 P02 | 19min | 3 tasks | 35 files |
| Phase 05.1 P03 | 85min | 3 tasks | 138 files |
| Phase 05.1.1 P01 | 95min | 3 tasks | 34 files |
| Phase 05.1.1 P02 | 80min | 3 tasks | 41 files |
| Phase 05.1.1 P03 | 70min | 3 tasks | 24 files |
| Phase 05.1.1.1 P01 | 180min | 3 tasks | 37 files |
| Phase 05.1.1.1 P02 | 150min | 3 tasks | 32 files |
| Phase 05.1.1.1 P03 | 240min | 4 tasks | 50 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: one pull request per phase, merged only after a green macOS CI build (no local compiler)
- Roadmap: release only at the end as `0.0.6-beta1` (Phase 6)
- Roadmap: hotkey signature stays identical to Ice's (BUG-05 must not change it)
- [Phase 01]: CI pins Xcode 26.6 exactly via .github/actions/select-xcode (inputs.version.default is the single source); no fallback
- [Phase 01]: build.yml runs on every pull request (no paths filter)
- [Phase 01]: Lint runs the official SwiftLint 0.65.1 image pinned by sha256 digest via plain docker run; no lint rule was switched off (legacy_swiftui_aspect_ratio fixed in code)
- [Phase 01]: Source builds sign ad hoc with the CI overrides; the Xcode project sets no DEVELOPMENT_TEAM and carries version 0.0.5 / build 1
- [Phase 01]: release.yml validates the version (0.0.6 / 0.0.6-beta1) before writing it to GITHUB_ENV; no expression inside any run block
- [Phase 01.1]: Phase 01.1 PR is #33 (draft, claude/ice-fork-development-hzdl1d -> main); later plans push to the branch and update its body
- [Phase 01.1]: build.yml 'Check the identifiers' reads MenuBarItemService.name from the Swift source and fails the build when the embedded XPC service's bundle id differs from it or from the app id plus .MenuBarItemService
- [Phase 01.1]: 01.1-02: Identifiers renamed by prefix rule (HolzBar<Name>, HolzBarShelf<Name>/shelf<Name>, holzBarIcon<Name>); every Defaults.Key and HotkeyAction raw value unchanged
- [Phase 01.1]: 01.1-03: comments that mean the upstream project say 'the original Ice'; bare holzBar means this app
- [Phase 01.1]: 01.1-03: ControlItemImageSet.Name decodes the stored holzIce logo name as .logo via an explicit init(from:); unknown names throw
- [Phase 01.1]: holzBar imports holzIce's settings first (copy-only for its Application Support folder and iCloud sync file), Ice's only when holzIce has none; the flag keeps the stored key HasImportedIceSettings
- [Phase 01.1]: holzbar:// is the URL scheme; holzice:// and the ice-bar command stay as aliases; Raycast scripts are holzbar-*.sh with the wood icon
- [Phase 01.1]: holzIce users must trust holzcloud/holzice/holzbar once before brew update: Homebrew 7.0.7 does not carry the holzice trust over to the renamed cask (measured in the cask job)
- [Phase 01.1]: Interim cask holzbar installs holzIce 0.0.5 until the first holzBar release; release.yml switches url, app, postflight and uninstall to holzBar
- [Phase 01.1]: No conflicts_with cask holzice and no tap_migrations.json: the rename mapping would make holzbar conflict with itself, and both tap names are this repository
- [Phase 02]: Spacing relaunch skips only holzBar, Control Center and MenuBarAgent (SpacingRelaunch.processesToRelaunch)
- [Phase 02]: Apps get 10 s (SpacingRelaunch.quitTimeout) to quit and are never force terminated; the wait is KVO-driven and always returns
- [Phase 02]: Option-only and Option+Shift-only hotkeys are refused on macOS 15+ in the recorder (alert, recording continues) and in HotkeyRegistry (logged); the Carbon signature stays OSType(1231250720) (D-01)
- [Phase 02]: A permission wait returns false when stopCheck() ends it or its task is cancelled; the Grant buttons only reopen the permissions window on true
- [Phase 02]: BUG-06: on ad hoc builds the XPC listener requires SigningIdentifier(com.holzcloud.holzBar) plus CodeDirectoryHash.in(hashes of the embedding app); team builds require same team plus identifier; it fails closed (D-02)
- [Phase 02]: BUG-06: the app sets its same-team peer requirement only when it has a team; LightweightCodeRequirements is imported only in MenuBarItemService/Listener.swift
- [Phase 02]: BUG-08 (D-03): macOS 27 system item allowlist is 0 through 127, the measured range, held in SystemItems27; 63 only matched jordanbaird/Ice#1001
- [Phase 02]: BUG-04: event source cache guarded by one OSAllocatedUnfairLock (withLockUnchecked; CGEventSource is not Sendable)
- [Phase 03]: LEFT-01: acknowledgements are pure Core data checked by swift test against Package.resolved, shown in a native SwiftUI sheet; PDF/RTF removed
- [Phase 03]: LEFT-08 superseded by REN-06 (sidebar logo already in place)
- [Phase 03]: LEFT-04: unused media, dead types, the Copy to Applications stub phase, ENABLE_USER_SELECTED_FILES and ItemCache.managedItems(for:) removed
- [Phase 03]: LEFT-07: click bridge logs through Logger(category:); Core derives the subsystem from the bundle (cannot see Shared/)
- [Phase 04]: API-04: spacing written through CFPreferences in the current host's global domain, no defaults process
- [Phase 04]: API-03: sync files carry a per-Mac UUID (SettingsSync prefix never exported or synced) plus SCDynamicStoreCopyComputerName; name-only files still recognised
- [Phase 04]: API-02: relaunch through NSWorkspace.openApplication with a pid hand-off; the new instance waits at most 10 s for the old
- [Phase 04]: API-05: URL commands through application(_:open:) and a tested Core URLCommand; scenes match no external event
- [Phase 04]: API-08: AppState opens windows through the actions captured from the scenes, replaying early requests
- [Phase 04]: API-07: AXHelpers call the AX C API with CFGetTypeID checks; AXSwift imported nowhere
- [Phase 04]: User decision: Ifrit replaced by holzBar's own FuzzyMatch (Core, tested); misspellings no longer match
- [Phase 04]: API-07/DEP-01: AXSwift removed from both targets; CompactSlider 2.1.0, LaunchAtLogin-Modern 1.1.0, Semaphore 0.1.0 are latest; build log lists resolved packages and app size
- [Phase 05]: SEC-01: imported, synced and Ice settings apply only Defaults.Key keys whose value has the declared kind (exhaustive settingsKind); exports carry only holzBar's keys
- [Phase 05]: SEC-03: item images live in Caches/com.holzcloud.holzBar/ItemImages, moved once from Application Support
- [Phase 05]: PERF-01..03: one cancellable hover task (HoverSchedule), permission polling only while missing, reveal rules on IOKit power notifications and NWPathMonitor (RevealTrigger)
- [Phase 05]: PERF-04 (user decision): typo fallback in FuzzyMatch, optimal string alignment distance to word starts, 1 edit for 4-7 chars, 2 for 8+, below every in-order match
- [Phase 05.1]: 05.1-01: privacy-check.py scans Logger literals (raw strings, nested quotes, logger.log) and keeps the plan regex as a second pass
- [Phase 05.1]: 05.1-01: HolzBarSlider exposes a system Slider to VoiceOver via accessibilityRepresentation
- [Phase 05.1]: 05.1-01: the offline rule records a baseline when turned on while offline (does not fire), as before
- [Phase 05.1]: Screen Recording is asked only in context (Shelf, search, Layout pane, menu bar shape); a permission not asked at launch polls at most 300 s after a request
- [Phase 05.1]: Ice settings are migrated once during the import (LegacySettingsMigration); nothing migrates at launch
- [Phase 05.1]: Every build keeps the hardened runtime; CI fails when the app or XPC service lacks it
- [Phase 05.1]: 05.1-03: Swift 6 language mode (SWIFT_VERSION 6.2 = -swift-version 6) with MainActor default isolation; Core, macOS 27 core and Shared explicitly nonisolated
- [Phase 05.1]: 05.1-03: @Observable everywhere; ObservationLoop (dedupes equatable values) and Debouncer replace Combine
- [Phase 05.1]: 05.1-03: per-macOS behaviour through MenuBarBackends.current (WindowListBackend, ServiceBackend26, AccessibilityBackend27); event posting on the main actor
- [Phase 05.1.1]: 05.1.1-01: Accessibility reads of the application menu run off the main thread in ApplicationMenuFrames; timeouts are per element, never on the system-wide element
- [Phase 05.1.1]: 05.1.1-01: CI runs once for plans 01-03 (single push at the end of 05.1.1-03)
- [Phase 05.1.1]: 05.1.1-02: Before macOS 27, item sections are saved by identity (ItemSections) and restored only through reconcileSections; item list changes place new items only
- [Phase 05.1.1]: 05.1.1-02: Keep the Dock icon hidden (default on) stops automatic hiding of application menus; the toggle hotkey still hides them
- [Phase 05.1.1]: 05.1.1-03: On macOS 27 nothing captures the wallpaper; the strip beside a shape comes from the desktop picture file
- [Phase 05.1.1.1]: Zen mode works like Thaw's; presenting is detected from the screen sharing agent and mirrored displays through notifications, no polling
- [Phase 05.1.1.1]: App Intents reach the app through AppState.current; every way of opening an item goes through ItemOpener
- [Phase 05.1.1.1]: The rehide delay starts when the item's menu closes, capped at 30 s; change reveal is opt-in per item
- [Phase 05.1.1.1]: SYNC-01: settings sync through iCloud Drive or any folder the Macs sync, kept as a bookmark; iCloud users migrated without a prompt
- [Phase 05.1.1.1]: holzBar ships machine-written de, fr, it, rm String Catalogs; a strings CI job proves completeness

### Pending Todos

None yet.

### Blockers/Concerns

None yet.

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-03T08:14:39.280Z
Stopped at: Completed 05.1.1.1-03-PLAN.md
Resume file: None
