---
gsd_state_version: "1.0"
milestone: v0.0.6
current_phase: 1
current_phase_name: CI and build
status: verifying
stopped_at: Completed 03-01-PLAN.md
last_updated: "2026-10-02T17:50:07.361Z"
last_activity: 2026-10-02
last_activity_desc: Roadmap created (6 phases, 37 requirements mapped)
state_head: 12129ad2e0dcfe8a2a0ef8d54818a4e867332c56
progress:
  total_phases: 10
  completed_phases: 0
  total_plans: 20
  completed_plans: 14
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

Last session: 2026-10-02T17:50:07.301Z
Stopped at: Completed 03-01-PLAN.md
Resume file: None
