---
phase: audit-remediation-events
plan: timeouts
subsystem: menu bar item events (before macOS 27), holzBar Shelf
tags: [F-01, concurrency, timeouts, event-taps, shelf]
requires: [audit/remediation-2026-10-05 at 7e7ed6bf (F-21, F-83 already fixed)]
provides: [ResumeOnce, a Task(timeout:) that returns at the timeout, EventBarrierPolicy, bounded event barriers, bounded Shelf wait]
affects: [MenuBarItemEventPoster, HolzBarShelfPanel.show, MenuBarOverlayPanel (helper semantics only)]
tech-stack:
  added: []
  patterns: [resume-once continuation behind OSAllocatedUnfairLock, withTaskCancellationHandler around continuations, main-actor defer for tap clean-up]
key-files:
  created:
    - holzBar/Core/EventBarrierPolicy.swift
    - Tests/HolzBarCoreTests/TaskTimeoutTests.swift
    - Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift
  modified:
    - holzBar/Core/ConcurrencyHelpers.swift (moved from holzBar/Utilities)
    - holzBar/Core/Defaults.swift
    - holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift
    - holzBar/MenuBar/Shelf/HolzBarShelf.swift
    - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
decisions:
  - "event-timeouts-1: option A (Sicherheitsnetz, Timing unverändert), main barriers wait max(timeout * count, 500 ms); fallbacks keep 200/500 ms"
  - "event-timeouts-1 optional debug default taken: DebugDropsBarrierExitEvent, local-only"
  - "event-timeouts-2: Shelf waits at most 1 s; the refresh is its own task and is never cancelled"
status: complete
actuals:
  tasks: 3
  commits: 2
plan_head_before: 7e7ed6bf
---

# Phase audit-remediation-events Plan timeouts: F-01 bounded event barriers and Shelf wait Summary

A lost event round trip on macOS 26 (and 14/15) now ends a click after about 2 s and a move after about 1.7 s, instead of hanging holzBar until it quits. Successful moves and clicks keep today's timing. The holzBar Shelf opens after at most 1 s on macOS 26.

## Commits

| Commit | Message |
|---|---|
| f14aed13 | fix(backends): resolve F-01 — bound lost event barriers on macOS 26 (helper, policy, both barriers, retry cap, debug default, tests) |
| (this commit) | fix(shelf): resolve F-01 — open the Shelf after at most 1 s on macOS 26 (Shelf wait plus this summary) |

Both are local only. Nothing was pushed.

## Per finding

### F-01: fixed

- **Timeout helper (D-01).** `holzBar/Utilities/ConcurrencyHelpers.swift` moved with `git mv` to `holzBar/Core/ConcurrencyHelpers.swift`. `swift test` now compiles it, and the app still picks it up through the synchronized folder group.
  - New `ResumeOnce<Success>` type: only the first racer resumes the continuation, and a result that arrives before `store(_:)` is kept.
  - `Task.value(of:timeout:tolerance:clock:)` is rewritten. A sleeper cancels the operation first and then resumes with `TaskTimeoutError`. A waiter resumes with the operation's result. Outer cancellation cancels the operation and resumes with `CancellationError`. The doc comments are corrected.
- **Event barriers (D-02, D-05, D-06).** `postEventWithBarrier` and `scrombleEvent`:
  - The nested unstructured task, whose cancellation handler never ran, is deleted.
  - The continuation sits in a `ResumeOnce` that one of three things resumes: the exit tap, `onCancel`, or a fail-fast check.
  - The fail-fast check runs in `enableBarrierTaps(_:pid:item:)`. It fails with `cannotComplete` when `kill(pid, 0)` reports `ESRCH`, and with `eventCreationFailure` when a tap is not valid after `enable()`.
  - All taps are disabled in a `defer` on the main actor.
  - The caller's wait is wrapped in a cancellation handler that cancels `timeoutTask`.
  - Main barriers wait `max(timeout * count, 500 ms)` (`EventBarrierPolicy.minimumMainWait`). Both fallbacks pass `bound: .fallback`, so they keep 100 ms ×2 and 250 ms ×2.
  - Each round trip is logged at debug level and each timeout at notice level, with public durations only. `EventError`s pass through unchanged.
- **Retry cap (D-03).** `move()` and `click()` use `EventBarrierPolicy.AttemptBudget`, which allows at most one more attempt after `eventOperationTimeout`. In `postMoveEvents`, `EventBarrierPolicy.moveTimeout(afterFailure:barrierTimedOut:)` keeps a barrier timeout from growing the adaptive move timeout. `waitForMoveEventResponse` is unchanged.
- **Debug default (D-07).** `Defaults.Key.debugDropsBarrierExitEvent = "DebugDropsBarrierExitEvent"`, of kind `.bool`. It is listed in `localOnlyKeys`, so it is never exported, imported or synced, and `SettingsSchemaTests` pins this. EventTap 1 consumes the exit event without resuming when the default is set. The value is read once per barrier.
- **Shelf (D-09).** `HolzBarShelfPanel.show`, in the branch before macOS 27 (or with `MacOS27IceBarWaitsForRefresh` set): the refresh runs as its own `Task`, and only the wait is bounded with `Task(timeout: .seconds(1)) { await refresh.value }`. A timeout is logged at notice level, and any other error keeps the existing error log. The refresh is never cancelled. The macOS 27 default branch is unchanged.
- **F-21 (D-04)** and **F-83 (D-10)** were verified intact, with no changes:
  - Commits 32065b86, f4cc7583, 54237c97, 4e62a66b, b6b6e371 and 1b427190 are ancestors of HEAD.
  - `NSEvent.heldModifierFlags` is still used, as is the 5 s `userInputNotPaused` bound.
  - The `guard generation == showGeneration, currentSection == section` check still follows the bounded wait.
- No new user-facing strings (D-08). The String Catalog still has 369 strings.

## TDD gate

- **RED:** with the unchanged helper, after the move to Core, `TaskTimeoutTests` "An operation that ignores cancellation times out on time" failed. `TaskTimeoutError` arrived **3.10 s** after a 100 ms timeout, when the 3 s safety gate let the operation finish. The prototype measured 3.19 s.
- **GREEN:** after the rewrite, all 13 tests in the new suites passed. The whole run took 0.110 s, and the regression case returns in about 0.1 s.
- The timing bound is timeout + 400 ms, not about +100 ms, to leave room for the scheduling jitter of shared CI runners (as the plan says). The old failure mode takes about 3 s, so the test stays meaningful.

## Gates (run before each commit, all passed)

| Gate | Commit A | Commit B |
|---|---|---|
| appcheck.sh (whole app module, Swift 6, target macOS 14.0, 26.5 SDK) | ERRORS: 0 (only the existing CGWindowList deprecation warning) | ERRORS: 0 |
| servicecheck.sh | SERVICE EXIT: 0 | SERVICE EXIT: 0 |
| `swift test` (full) | 280 + 136 + 6 tests passed | 280 + 136 + 6 tests passed |
| SwiftLint `--strict --quiet` | no output, exit 0 | no output, exit 0 |
| privacy-check network / logs, strings-check | pass (369 strings, 5 languages) | pass (369 strings) |
| Former-name grep | no match | no match |

`swift test` sometimes stops with "plugin for module 'TestingMacros' not found" and no compiler error. This is the known transient from the plan, and a rerun passed each time. I used a small retry wrapper in the scratchpad, `swifttest-retry.sh`.

## Deviations from Plan

1. **Name of the fail-fast helper.** It is called `enableBarrierTaps(_:pid:item:) -> EventError?` instead of `barrierStartFailure(eventTaps:pid:item:)`, because it also enables the taps. The order is still the plan's: pid check, enable, validity check, and the entry event is posted only after it returns `nil`. The plan explicitly left the helper's shape open.
2. **Order of Tasks 1 and 2.** Both barrier functions were rewritten in one pass, because the plan's commit A has to contain both anyway. The RED/GREEN steps of Task 1 ran first, as planned.
3. **Extra test assertion.** The detached-timeout test also checks that the wait ends in under 1 s. A small strengthening, with no change in behavior.
4. **Staging detail.** `git mv` had already staged the deletion of the old path, so commit A staged only the new path. The commit still records the rename.

No GSD STATE.md, ROADMAP.md or requirements updates: this audit-remediation chain has no phase state, and the orchestrator owns the plan file, which stays untracked.

## Known stubs

None.

## Threat flags

None beyond the plan's threat model. The new log lines contain only durations and holzBar's own tap labels, all `.public`. The debug key is local-only.

## User test steps (maintainer, macOS 26.7.1, after CI)

**Signing the test build ("Können wir das mit dem signieren nicht doch anders lösen?").** Yes. Re-sign the CI build locally with holzBar's own release certificate, in a temporary keychain that is deleted right afterwards. The plan has the exact commands under "Getting a test build without granting permissions again". The test build then has the release's designated requirement, `certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"`, so macOS keeps Accessibility and Screen Recording, both for the test build and for the release afterwards. This chain ran none of these commands: no keychain, signing, `defaults` or app launch was touched.

1. Settings › Menu Bar Layout: drag 3-4 items between Visible, Hidden and Always Hidden, including a Control Center item and a third-party item. Each move completes at today's speed, and the pointer reappears.
2. Shelf: click the holzBar icon, then click a hidden item. Its menu opens, and the pointer comes back.
3. Search: open a hidden item from the results. Its menu opens.
4. Wait for the rehide interval. The item goes back to its section.
5. Open the Shelf after a pause of more than 60 s. It opens within about 1 s, with images, and without "Unable to display menu bar items".
6. Turn Caps Lock on and repeat step 2: it works (F-21). Then double-click the holzBar icon quickly: no orphaned Shelf remains (F-83).
7. `defaults write com.holzcloud.holzBar DebugDropsBarrierExitEvent -bool true`, then repeat step 2. Within about 2 s the pointer is visible again and show on hover works. A second click also gives up within about 2 s. A drag in Menu Bar Layout shows the alert "Event operation timed out for …" after about 1.5 s.
8. `defaults delete com.holzcloud.holzBar DebugDropsBarrierExitEvent`, then repeat step 2 without relaunching. It works normally, so no lock, monitor state or cursor count was left behind.
9. Optional: `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "MenuBarItemEventPoster"'` during steps 1-3 shows "Event barrier round trip took …". Timeouts are persisted at notice level.
10. macOS 27, if available: open the Shelf and change the wallpaper with a tint active. Both behave as before.

## doc_updates_needed (not done here)

- `docs/upstream-bugs.md:31` (#640, #751, #757): holzBar now also recovers when an event round trip is lost. It gives up after about 2 s, and the pointer and the input monitors come back (F-01).
- `docs/release-notes/v0.0.7-beta2.md` (to be written), under Fixed:
  - "On macOS 26, a lost event no longer hides the pointer and stops moving, clicking and showing items on hover until holzBar is quit; holzBar gives up after about two seconds."
  - "On macOS 26, the holzBar Shelf opens after at most a second even when an item image cannot be captured."
- Optional: in `docs/signing.md`, a maintainer section "Test a pull-request build without granting permissions again", with the re-signing steps from the plan.

## Self-Check: PASSED

- holzBar/Core/ConcurrencyHelpers.swift, holzBar/Core/EventBarrierPolicy.swift, Tests/HolzBarCoreTests/TaskTimeoutTests.swift and Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift exist, and holzBar/Utilities/ConcurrencyHelpers.swift is gone.
- Commit f14aed13 is an ancestor of HEAD.
- `bound: .fallback` appears twice, and the barrier functions contain no nested `Task {`.
- `await refresh.value` and the F-83 guard each appear once in HolzBarShelf.swift.
