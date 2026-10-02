---
phase: 02-bug-fixes
plan: 01
subsystem: menu-bar-spacing
status: complete
tags: [bug-fix, spacing, relaunch, swift-concurrency, kvo, swift-testing, macos27]
requires: []
provides:
  - "holzBar/Core: pure, unit-tested folder compiled into the app and into the test-only package (HolzBarCore / HolzBarCoreTests)"
  - "SpacingRelaunch.processesToRelaunch, quitTimeout and waitUntil"
  - "Draft phase PR #35 (claude/ice-fork-development-hzdl1d -> main)"
affects:
  - "Every later Phase 2 plan adds its tests to Package.swift next to HolzBarCoreTests and lands in PR #35"
tech-stack:
  added: []
  patterns:
    - "Event-or-timeout wait as a two-child task group (no continuation, no polling)"
    - "Key-value observation of NSRunningApplication.isTerminated feeding an AsyncStream"
    - "Task group children return their result instead of mutating a captured array"
key-files:
  created:
    - holzBar/Core/SpacingRelaunch.swift
    - Tests/HolzBarCoreTests/SpacingRelaunchTests.swift
  modified:
    - Package.swift
    - holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift
decisions:
  - "Spacing relaunch: skip only holzBar itself, Control Center and MenuBarAgent; every other owner is relaunched, sorted by pid"
  - "Apps get SpacingRelaunch.quitTimeout (10 s) to quit and are never force terminated; one still running is left alone and named in the alert"
  - "The KVO change handler is @Sendable and reads change.newValue, so it touches neither the app nor the main actor"
metrics:
  duration: 16min
  completed: 2026-10-02
  tasks: 2
  files: 4
estimate:
  tokens: 60000
  tasks: 2
actuals:
  tokens: 5000
  tasks: 2
  commits: 4
plan_head_before: b4f4bd9a065e157bc962540d516b4639f881d47f
plan_head_after: 652b1e6b93e91256898378a0fa3a28a514b5e278
---

# Phase 2 Plan 01: Spacing relaunch Summary

Applying menu bar item spacing now relaunches every app that owns a menu bar item (the loop no longer stops at the first skipped process), waits up to 10 seconds for each to quit through key-value observation of `isTerminated` instead of killing it after 1 second, and on macOS 27 reads the owners through Accessibility and never quits MenuBarAgent. The decisions live in a new pure, unit-tested `holzBar/Core/SpacingRelaunch.swift`; the draft phase PR is open.

## Phase PR

- **PR #35**, draft: https://github.com/holzcloud/holzBar/pull/35 (head `claude/ice-fork-development-hzdl1d`, base `main`)
- Last CI head: `652b1e6b93e91256898378a0fa3a28a514b5e278`: `build`, `test` and `swiftlint` all success.
- Last `test` run: "Test run with 124 tests in 23 suites passed" (114 on main before this plan; +10 in the new `SpacingRelaunch` suite).
- Build: `** BUILD SUCCEEDED **`, 9 compiler warnings, none in `holzBar/Core` or `MenuBarItemSpacingManager.swift` (the 9 are the pre-existing ones, e.g. `HIDEventManager.swift`, `ItemClicker27.swift`).
- SwiftLint: "Done linting! Found 0 violations".

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 (tracer) | A skipped process no longer stops the spacing relaunch | 232fbc5 | Package.swift, holzBar/Core/SpacingRelaunch.swift, Tests/HolzBarCoreTests/SpacingRelaunchTests.swift, MenuBarItemSpacingManager.swift |
| 2 RED | Failing tests for the quit wait and its timeout | fd2ada5 | SpacingRelaunch.swift (stubs), SpacingRelaunchTests.swift |
| 2 GREEN | Wait for apps to quit instead of killing them | 652b1e6 | SpacingRelaunch.swift, MenuBarItemSpacingManager.swift |

Tracer gate: after Task 1, CI on 232fbc5 was green (119 tests, "A skipped owner does not stop the others" passed, no warning in the changed files), so the expansion (Task 2) went ahead.

## What changed

- **BUG-01**: `SpacingRelaunch.processesToRelaunch(owners:ownPID:)` returns every distinct owner except holzBar, Control Center and MenuBarAgent, sorted by pid. `applyOffset()` loops over that list and `continue`s past a process that is gone, so no owner is left out depending on a `Set`'s order.
- **BUG-02**: `quit(_:)` observes `isTerminated` (`.initial, .new`) into an `AsyncStream`, calls `terminate()` and waits through `SpacingRelaunch.waitUntil(timeout: SpacingRelaunch.quitTimeout)`. The wait is a two-child task group (event and sleep). It returns true at the event, false at the timeout, and false at once on cancellation, and it never leaks a continuation. The force-termination fallback, `forceTerminateDelay`, the Combine sink, the checked throwing continuation and `import Combine` are gone. The alert reads "did not quit within 10 seconds and were not restarted". The Control Center tail reports Control Center when it does not quit.
- **BUG-03**: on macOS 27 the owners come from `MenuBarItemProvider27.items()` (Accessibility names the owner of every item, concealed ones included); MenuBarAgent is never relaunched.
- Failures are collected from `withTaskGroup(of: String?.self)` results instead of being appended to a captured array from child tasks.
- `Package.swift` adds `HolzBarCore` (`holzBar/Core`) and `HolzBarCoreTests`; the existing macOS 27 targets are unchanged.

## TDD Gate Compliance

- RED: `test(02-01)` commit fd2ada5 added the five wait/timeout tests against stubs (`waitUntil` returning false, `quitTimeout` 1 s). CI `test` job 110889397319 failed on assertions: "Waiting returns as soon as the event happens", "Waiting returns at once when the event has already happened" (`Expectation failed: happened`) and "An app gets 10 seconds to quit" (`1.0 seconds == 10.0 seconds`). The other two passed against the stub, as expected (it returns false). Swift Testing does not print TAP, so I converted the job log's per-test results to TAP. `check tdd-red-evidence` on the converted results gave `RED_EVIDENCE_OK` (target "Waiting returns as soon as the event happens").
- GREEN: `fix(02-01)` commit 652b1e6. All 10 `SpacingRelaunch` tests pass in CI.
- REFACTOR: not needed.

## Deviations from Plan

- **[Rule 3 - Blocking] Task 2 commit sequence.** Task 2 is `tdd="true"`, so I split it into a RED commit (tests plus compiling stubs, pushed so CI could show the assertion failures) and a GREEN commit, not one commit. So CI on the PR was red for one run (fd2ada5), as planned.
- **[Rule 1 - Correctness] KVO handler reads `change.newValue`.** The `isTerminated` change handler is marked `@Sendable` and reads `change.newValue` instead of the app, so it is safe whichever thread KVO calls it on and captures only the stream's continuation.
- **Plan verification note, not a code change:** `git diff origin/main -- .github holzBar.xcodeproj` is no longer empty. `main` has moved ahead since the branch point: PR #34 (cms-version) added `.github/cms-version.py` and changed `release.yml`. This plan changes neither; the three-dot diff `origin/main...HEAD -- .github holzBar.xcodeproj` is empty. The orchestrator will need to bring `main` into the branch (or merge through GitHub) before the phase PR is merged.
- `commits: 4` counts every commit in `b4f4bd9..652b1e6`. Three are this plan's; 6a03218 ("docs: insert phase 06.1 compatibility check") is the coordinator's planning commit, which I picked up by rebasing.

## Open human checks

- macOS 26.7.1: with several apps that have menu bar items running, change "Menu bar item spacing" and press Apply. Every app with a menu bar item quits and reopens, including when Control Center or holzBar would have come first. Repeat once: the same set relaunches.
- macOS 26.7.1: run an app that asks before quitting (leave the question unanswered) and apply spacing. The app is not killed. After about 10 s holzBar shows "did not quit within 10 seconds and were not restarted" naming it. The other apps relaunch.
- macOS 27: apply spacing. No alert names MenuBarAgent, and the apps with menu bar items relaunch. Note whether the spacing between items changes; if it does not, MenuBarAgent reads the setting itself, so open a follow-up.

## Known Stubs

None. The RED stubs were replaced in the GREEN commit.

## Self-Check: PASSED

- FOUND: holzBar/Core/SpacingRelaunch.swift, Tests/HolzBarCoreTests/SpacingRelaunchTests.swift
- FOUND commits: 232fbc5, fd2ada5, 652b1e6
- Both task verify commands pass on 652b1e6 (CI readback green, static checks green).
