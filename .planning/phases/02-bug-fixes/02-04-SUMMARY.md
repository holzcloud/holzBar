---
phase: 02-bug-fixes
plan: 04
subsystem: menu-bar-items-and-macos27-concealment
status: complete
tags: [bug-fix, concurrency, data-race, macos27, allowlist, swift-testing]
requires:
  - "02-03: complete (wave order), draft PR #35"
provides:
  - "MenuBarItemManager.getEventSource(with:): cache guarded by one OSAllocatedUnfairLock"
  - "holzBar/MenuBar/MacOS27/Core/SystemItems27.swift: drawn, highestMeasured (127), allowed (0...127)"
  - "Tests/HolzBarMacOS27CoreTests/SystemItems27Tests.swift (suite \"SystemItems27\", 3 tests)"
  - "Final PR body of #35 covering BUG-01 to BUG-08 and the open human checks"
affects:
  - "MenuBarAssessmentAssertion27 (configuration built from SystemItems27.allowed)"
  - "Phase 2 verification and PR merge (orchestrator)"
tech-stack:
  added: []
  patterns:
    - "Function-local enum holding a static OSAllocatedUnfairLock(uncheckedState:) for non-Sendable cached state (macOS 14 target, Mutex needs macOS 15)"
    - "Measured macOS 27 constants live in a pure Core file and are pinned by Swift Testing"
key-files:
  created:
    - holzBar/MenuBar/MacOS27/Core/SystemItems27.swift
    - Tests/HolzBarMacOS27CoreTests/SystemItems27Tests.swift
  modified:
    - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
    - holzBar/MenuBar/MacOS27/MenuBarAssessmentAssertion27.swift
decisions:
  - "BUG-08 (D-03): the macOS 27 system item allowlist is 0 through 127, the widest range MenuBarAgent was measured to accept (one at a time and all 128 at once in one live assertion); 63 had been chosen only to match jordanbaird/Ice#1001 and avoid a merge conflict"
  - "BUG-04: lookup, creation and store of event sources happen under one OSAllocatedUnfairLock via withLockUnchecked, because CGEventSource is not Sendable; callers and signature unchanged"
metrics:
  duration: 12min
  completed: 2026-10-02
actuals:
  tokens: 1600
  tasks: 2
  commits: 3
plan_head_before: 1e6d98b2ace0c2b87b9255a4c8b0076daf865c48
plan_head_after: af48d9aad9173cc07b401acf9d469091728c89d2
---

# Phase 2 Plan 04: Event source cache lock and measured macOS 27 allowlist Summary

The event source cache in `MenuBarItemManager` is now read and filled only inside one `OSAllocatedUnfairLock` (BUG-04), and the macOS 27 system item allowlist is the measured 0 through 127, held once in the Core file `SystemItems27.swift`, pinned by Swift Testing and described truthfully in the assertion's comment (BUG-08). PR #35's body now covers all of Phase 2.

## What was done

### Task 1: the event source cache is guarded by a lock (BUG-04) — commit 14a6dd4

- `getEventSource(with:)` keeps its function-local `enum Context`, now with `static let sources = OSAllocatedUnfairLock(uncheckedState: [CGEventSourceStateID: CGEventSource]())`.
- The lookup, `CGEventSource(stateID:)` creation (throwing `EventError.invalidEventSource` on failure) and the store run inside one `Context.sources.withLockUnchecked { ... }`; the closure rethrows, so the signature and the three callers (`permitLocalEvents()` and two move/click paths) are unchanged.
- The doc comment says why: moves and clicks call it concurrently from nonisolated code, and the unchecked API is used because `CGEventSource` is not Sendable.
- `import os` added above `import OSLog`.
- CI on 14a6dd4: build, test (137 tests in 25 suites) and swiftlint (0 violations) green, no warning in `MenuBarItemManager.swift`.

### Task 2: the allowlist is the measured range (BUG-08) — commits d584f45 (test), af48d9a (fix)

- New `holzBar/MenuBar/MacOS27/Core/SystemItems27.swift` (Foundation only, no `@available`): `drawn: Set<Int> = [0, 2, 6, 8]`, `highestMeasured = 127`, `allowed: ClosedRange<Int> = 0...highestMeasured`.
- New `Tests/HolzBarMacOS27CoreTests/SystemItems27Tests.swift`, suite "SystemItems27": "Every drawn system item is allowed", "The allowlist is the measured range, 0 through 127", "Nothing beyond the measurement is allowed".
- `MenuBarAssessmentAssertion27.systemItems` is built from `SystemItems27.allowed` (each number as `NSNumber`, as an `NSArray`). The first paragraph of its doc comment now states the drawn numbers, the measured accepted range (up to 127, one at a time and all at once), why holzBar keeps it whole, and that jordanbaird/Ice#1001 (@carlossantos74) keeps 0 to 63, which lies inside it. The sentence claiming the ranges match is gone; the capture-indicator paragraph and the measurement line are unchanged.
- CI on af48d9a: build (BUILD SUCCEEDED), test (140 tests in 26 suites passed, including SystemItems27, SpacingRelaunch, Modifiers, CodeSignature), swiftlint (0 violations in 133 files), former-name and cask green; no warning in the changed files.
- PR #35 body updated through `gh api -X PATCH`: completion paragraph, one bullet per BUG-01 to BUG-08 plus the cleanup, a "Verified by" line, all open human checks, attribution. The PR is still a draft, base `main`, mergeable state `clean`.

## Allowlist decision and evidence (D-03)

- `MenuBarAssessmentAssertion27.swift` (before): on macOS 27.0 only 0 (battery), 2 (clock), 6 (Wi-Fi) and 8 (Control Centre) draw; "All of them are accepted, though, up to 127 at least"; the capture-indicator test held a live assertion with every number to 127.
- `Scripts/macos27/system-item-probe.swift`: measured on macOS 27.0 (2026-09-29) with every number from 0 to 127 offered one at a time; MenuBarAgent accepts them all and draws five; a live assertion held all 128 numbers.
- History: a0c27a7 allowed 0...8; d1858fb widened to 0...31; 15f59a9 set 63 only to match jordanbaird/Ice#1001 so the branches would not collide ("the difference is only a difference").
- `.planning/codebase/CONCERNS.md` (Scaling Limits): a system item numbered above 63 in a later macOS 27.x would be concealed; widen to the measured 127.
- Decision: 0 through 127 — the widest measured range, matching the comment's own reason (never conceal a system item a later build adds). Reversible: one constant.

## Final state

- PR: holzcloud/holzBar#35 (draft), head af48d9aad9173cc07b401acf9d469091728c89d2 for the code; the docs commit of this SUMMARY follows on the same branch.
- Tests: 140 tests in 26 suites pass in CI.

## TDD Gate Compliance

- RED: `test(02-04)` commit d584f45 adds the suite before `SystemItems27` exists, so it cannot compile without the GREEN commit. It was not pushed on its own: there is no compiler here, and the plan type is `execute`, not `tdd`, so the plan-level RED-evidence gate does not apply. RED evidence is therefore by construction (missing symbol), not a CI run.
- GREEN: `fix(02-04)` commit af48d9a; all 3 SystemItems27 tests pass in CI.
- REFACTOR: not needed.

## Deviations from Plan

None - plan executed exactly as written. (Task 2's test and fix are two commits, test first, following the task's `tdd="true"`.)

## Open human checks (whole phase)

- macOS 26.7.1: with several apps that have menu bar items running, change "Menu bar item spacing" and press Apply. Every app with a menu bar item quits and reopens, including when Control Center or holzBar would have come first. Repeat once: the same set relaunches. (02-01)
- macOS 26.7.1: run an app that asks before quitting (leave the question unanswered) and apply spacing. The app is not killed; after about 10 s holzBar shows "did not quit within 10 seconds and were not restarted" naming it; the other apps relaunch. (02-01)
- macOS 27: apply spacing. No alert names MenuBarAgent, and the apps with menu bar items relaunch. Note whether the spacing changes; if not, open a follow-up. (02-01)
- macOS 26.7.1, Settings, Hotkeys: Option-H shows "macOS does not allow this hotkey" (Command or Control needed), the recorder still records after OK; Option-Shift-H the same; Command-Option-H records and fires from another app. Hotkeys set before the update still work. (02-02)
- Permissions window with Screen Recording reset (`tccutil reset ScreenCapture com.holzcloud.holzBar`): Grant, Reset and Grant Again, grant in System Settings: the window comes to the front once and shows it granted. Reset again, Grant, do not grant, Continue: the window does not reopen by itself. (02-02)
- macOS 26.7.1 ad hoc build: with `log stream --level info --predicate 'process == "MenuBarItemService" OR subsystem BEGINSWITH "com.holzcloud.holzBar"'`, launch holzBar and open Settings, Menu Bar Layout: the service logs "Listener requires the app's exact code (N code directory hashes)" with N ≥ 1, the layout shows the items, and no "looking up source processes in the app instead" line appears. (02-03)
- macOS 26.7.1, Settings, Menu Bar Layout: drag several items between sections in quick succession and click hidden items in the holzBar Shelf while a move runs. Items move and open as before; no crash. (02-04, BUG-04)
- macOS 27: hide a few apps' items. Battery, clock, Wi-Fi and Control Centre stay on the bar while the hidden apps' items disappear. (02-04, BUG-08)

## Known Stubs

None.

## Threat Flags

None. T-02-11 is mitigated as planned (one lock around lookup, creation and store; no unguarded static state remains). T-02-12 accepted: only MenuBarAgent's own system items stay visible. T-02-SC: no package or dependency change; the new Core file joins the existing `HolzBarMacOS27Core` target.

## Self-Check: PASSED

- FOUND: holzBar/MenuBar/MacOS27/Core/SystemItems27.swift, Tests/HolzBarMacOS27CoreTests/SystemItems27Tests.swift
- FOUND commits: 14a6dd4, d584f45, af48d9a
