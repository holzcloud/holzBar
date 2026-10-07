---
gsd_state_version: "1.0"
milestone: v0.0.7
current_phase: 8
current_phase_name: Triggers
status: planned
stopped_at: Completed 28-03-PLAN.md
last_updated: "2026-10-07T12:49:07.586Z"
last_activity: 2026-10-07
last_activity_desc: 0.0.7-beta2 released; sync redesign analysis finished and the maintainer's decisions recorded
state_head: d729449057667bc33f495b9b74d03e3eccc77701
progress:
  total_phases: 33
  completed_phases: 13
  total_plans: 99
  completed_plans: 33
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-02)

**Core value:** The menu bar items a user hides stay hidden and come back when asked, on every supported macOS version, without the app ever locking up the Mac.
**Current focus:** Phase 7 - Release 0.0.6-beta1

## Current Position

Milestone: 0.0.7 "Automation" (planned, not started); 0.0.6 is released (stable)
Phase: 8 of 14 (Triggers), next to plan
Status: Competitor research (`research/COMPETITORS.md`), 65 requirements, roadmap phases 8 to 27, phase outlines and the user's first 11 decisions are written. Phase list: 8 Triggers (Focus-filter spike first; the milestone is held if it fails), 9 Layout snapshots, 10 Item conditional visibility, 11 Scripts, 12 Widgets, 13 AppleScript dictionary, 14 Command palette, 15 Share profiles, 16 First-launch clean-up assistant, 17 Local usage suggestions, 18 Lock hidden items, 19 Smooth show and hide, 20 Copy diagnostics, 21 Accessibility showcase, 22 macOS 27 native overflow button, 23 Liquid Glass follows transparency, 24 SwiftUI reorder spike, 25 Control Center control (optional), 26 Swift 6.4 adoption, 27 Release 0.0.7-beta1 (one beta at the end). Open design questions 12 to 35 are indexed in `research/AUTOMATION-QUESTIONS.md`. Next: `/gsd-plan-phase 8`, starting with the Focus-filter spike on the user's macOS 26 and 27.
Last activity: 2026-10-04 — Automation milestone planned

Progress: [█████████████░░░░░░░░░░░░░░░] 13 of 33 phases (milestone 0.0.7: 0 of 20)

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
| Phase 05.1.1.1.1 P01 | 73min | 5 tasks | 19 files |
| Phase 28 P03 | 35min | 3 tasks | 13 files |

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
- [Phase 05.1.1.1.1]: CI and releases build with Xcode 27.0 on the xcode-27 runner (public preview) with Swift 6.4.0 from swift.org
- [Phase 05.1.1.1.1]: swift test compiles Core with the app's isolation settings (main actor default, approachable concurrency, member import visibility)
- [Phase 05.1.1.1.1]: URL-command question has no default button: Return answers nothing, Escape cancels, Apply needs a click (HIG order)
- [Phase 06]: Fixed M-1 to M-4, L-1 to L-5, L-8 (06-SUMMARY.md); L-6 and L-7 open; signing and attestation run in release.yml, the stable signature needs the user's SIGNING_CERTIFICATE_* secrets
- [Phase 06.1]: User decision 2026-10-03: keep macOS 14 and later (cask depends_on macos: :sonoma, deployment target 14.0)
- [Phase 06.1]: CI compat job launches the built app on macOS 14, 15, 26 and 27 (xcode-27 added in Phase 7) and runs the unit tests on 14, 15 and 26; the test job runs them on 27
- [Phase 06.1]: macOS 14 launch crash (openWindow inside the scene update) found by the compat job and fixed before any release
- [Phase 07]: README and website keep the stable signature and attestation at 🔜 until the first release signed with holzBar's own certificate
- [Phase 07]: 0.0.5 was a different cask and bundle id; the release notes tell its users to export, uninstall it, install holzbar and import (no automatic migration)
- [Phase 28]: Legacy profile ID is a version-8 UUID from SHA-256 of 'com.holzcloud.holzBar.LayoutProfile:' + name (one-way, D-05); duplicate names derive from name#2, #3
- [Phase 28]: Profile hotkey registration checks stored profile IDs because hotkeys load before LayoutProfiles.performSetup

### Roadmap Evolution

- Phase 28 added: Settings sync redesign (per-Mac causal replicas; settings on macOS 26 and 27, arrangement and profiles on macOS 27), for 0.0.7-beta3

### Pending Todos

- [2026-10-05] [release] Move the signing secrets into the release environment (F-10) — [todo file](.planning/todos/pending/2026-10-05-move-the-signing-secrets-into-the-release-environment-f-10.md)
- [2026-10-07] [sync] Redesign settings sync (paused in 0.0.7-beta2) — [todo file](.planning/todos/pending/2026-10-07-redesign-settings-sync-paused-in-0-0-7-beta2.md)

### Blockers/Concerns

None yet.

## Deferred Items

Items acknowledged and deferred at milestone close, most recent first:

| Category | Item | Status | Deferred At | Milestone |
|----------|------|--------|-------------|-----------|
| *(none)* | | | | |

## Session Continuity

Last session: 2026-10-07T12:49:07.562Z
Stopped at: Completed 28-03-PLAN.md
Resume file: None
