---
phase: audit-remediation-events
plan: capture
subsystem: menu bar item images (before macOS 27), menu bar search
tags: [F-13, concurrency, watchdog, image-capture, search]
requires: [audit-manual/events at e8eff47e (timeouts part, F-01)]
provides: [bounded BlockingWork.run(on:timeout:fallback:_:), ItemCapturePolicy (timeout, watchdog, on-screen rule), CoalescedRun, bounded and coalesced item image capture, search panel that shows first]
affects: [MenuBarItemImageCache, MenuBarSearchPanel, Bridging.getActiveDisplayList (visibility only), all waiters of the image cache]
tech-stack:
  added: []
  patterns: [resume-once continuation behind OSAllocatedUnfairLock raced by a DispatchQueue.global().asyncAfter timer, abandon-and-replace serial queue, single-flight run with a union re-run]
key-files:
  created:
    - holzBar/Core/ItemCapturePolicy.swift
    - holzBar/Core/CoalescedRun.swift
    - Tests/HolzBarCoreTests/ItemCapturePolicyTests.swift
    - Tests/HolzBarCoreTests/CoalescedRunTests.swift
  modified:
    - holzBar/Core/BlockingWork.swift
    - holzBar/Core/Defaults.swift
    - holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift
    - holzBar/MenuBar/Search/MenuBarSearchPanel.swift
    - Shared/Bridging/Bridging.swift
    - Tests/HolzBarCoreTests/BlockingWorkTests.swift
    - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
decisions:
  - "capture-queue-1: Watchdog und Auslöser meiden. Every capture call is given up after 2 s on a fresh queue, the hung window is skipped, and capture stops for the session after 3 abandoned queues with the last images kept. One pass runs at a time, and single captures skip items that are not entirely on one display. The search shows first, and the Shelf keeps the 1 s wait from e8eff47e."
  - "P-07 taken: local-only debug default DebugHangsItemImageCapture"
  - "P-09 fallback taken: the timer is not cancelled when the work wins"
status: complete
actuals:
  tasks: 3
  commits: 2
plan_head_before: e8eff47e
---

# Phase audit-remediation-events Plan capture: F-13 bounded item image capture and search that shows first Summary

On macOS 26 (and 14/15), a stuck item image capture now costs at most about 2 s and one thread. Later captures continue on a fresh queue. After three stuck calls, capture stops until relaunch, the last images stay, and one error is logged. Only one capture pass runs at a time. Single captures no longer touch items that are off screen, which removes the known trigger. The search panel appears at once. macOS 27 is unchanged except that the search now shows before the refresh.

## Commits

| Commit | Message |
|---|---|
| 84de2f53 | fix(images): resolve F-13 — give up stuck item captures and run one at a time (helper, policy, coalescing, cache, Bridging visibility, debug default, tests) |
| (this commit) | fix(search): resolve F-13 — show the search panel before the image refresh (search panel plus this summary) |

Both commits are local only. Nothing was pushed.

## Per finding

### F-13: fixed

- **Bounded helper (D-01).** `BlockingWork.run(on:timeout:fallback:_:) -> (value:, timedOut:)` is new in `holzBar/Core/BlockingWork.swift`. The continuation sits in an `OSAllocatedUnfairLock`. The work block (after `work()` returns) and a `DispatchQueue.global().asyncAfter` timer each take it out, and only the first one resumes it. The existing `run(on:_:)` and its callers are unchanged.
- **Watchdog (D-02, P-01, P-02, P-05, P-06).** `ItemCapturePolicy` provides:
  - `timeout` (2 s), `maxAbandonedQueues` (3) and `displayTolerance` (1 pt);
  - `isOnScreen(_:displays:)`;
  - `Watchdog`, which tracks the abandoned count and the hung window IDs, returns `replaceQueue` or `stop`, and forgets windows that are gone.

  In `MenuBarItemImageCache`:
  - The capture queue is now an instance property, and `onCaptureQueue(windowID:_:)` is the only `BlockingWork` caller.
  - A timeout runs `captureDidTimeOut(on:windowID:)`. It enqueues a `.notice` marker on the abandoned queue, then either:
    - replaces the queue and logs a `.warning` with the "n of 3" count; or
    - on the third timeout, stops capture, cancels the 3 s refresh and logs one `.error`.
  - Hung windows are filtered out per section, and `forgetWindows(notIn:)` runs before each pass.
  - `releaseAllImages()` and `refreshNeededDidChange(_:)` do nothing once capture has stopped.
- **One pass at a time (D-03).** `CoalescedRun<MenuBarSection.Name>`:
  - `updateCacheWithoutChecks` awaits `captureRun.run(sections)` after the unchanged macOS 27 branch.
  - The old body moved into `captureAndStoreImages(for:)`, which re-checks the guards (permission, pause, stop) and walks the sections in `allCases` order.
  - A request during a pass joins one union re-run, so the queue never holds more than one call.
- **Off-screen rule and per-item hop (D-04, P-03, P-04).**
  - `individualCapture(_:displays:scale:)` now captures one item. Items whose live bounds are not entirely on one active display (`Bridging.getActiveDisplayList().map(CGDisplayBounds)`, 1 pt tolerance) go to `CaptureResult.offScreen` without a capture.
  - `captureIndividually(_:scale:)` awaits `onCaptureQueue(windowID:)` once per item.
  - After a move, `captureMissingOffScreen(in:scale:)` takes the off-screen items that have no cached image from one composite capture.
  - In the composite fallback path, off-screen items are not captured again (the composite just failed for them). Those without a cached image are added to `excluded`, so the existing error log names them (hashed).
- **Search shows first (D-05, P-08).** `MenuBarSearchPanel.show(on:)` installs the hosting view, positions the panel, orders it front and starts the monitors synchronously. Only then does it start an unawaited `Task { await appState.imageCache.updateCache() }`. `showGeneration` and `isShowPending` are removed, and `toggle()` checks `isVisible` again.
- **Shelf (D-06).** Verified only: `HolzBarShelf.swift` is byte-identical to e8eff47e, and `Task(timeout: .seconds(1))` and `await refresh.value` each appear once. Its background refresh now ends within a bounded time through D-02 and D-03.
- **Debug default (P-07).** `Defaults.Key.debugHangsItemImageCapture = "DebugHangsItemImageCapture"`, of kind `.bool`, is listed in `localOnlyKeys`. `onCaptureQueue` reads it once per call on the main actor. When it is set, the work first waits on a semaphore that nothing signals.
- **Unchanged (D-07).** CGWindowList stays: `ScreenCapture.swift` and the other CGWindowList call sites are untouched. The macOS 27 branch of `updateCacheWithoutChecks` is byte-identical to e8eff47e (checked with `diff`).
- No new user-facing strings. The String Catalog still has 369 strings.

## TDD gate

- **RED, Task 1:** `swift test --filter "BlockingWorkTests|ItemCapturePolicyTests"` failed to compile with `cannot find 'ItemCapturePolicy' in scope` (and the missing overload).
- **GREEN, Task 1:** 13 tests in 2 suites passed after the first build. Before that, one geometry case failed because the plan's test case contradicts the plan's own tolerance (deviation 1).
- **RED, Task 2:** `swift test --filter CoalescedRunTests` failed to compile with `cannot find 'CoalescedRun' in scope`.
- **GREEN, Task 2:** 4 tests in 1 suite passed.
- **Tracer gate (Task 1):** re-ran the filtered tests and appcheck end to end before expanding: `ERRORS: 0`, one `private var captureQueue`, and one `BlockingWork.run(on:` in the cache.

## Gates (run before each commit, all passed)

| Gate | Commit A (84de2f53) | Commit B |
|---|---|---|
| appcheck.sh (whole app module, Swift 6, target macOS 14.0, 26.5 SDK) | ERRORS: 0 (no new warnings in the touched files) | ERRORS: 0 |
| servicecheck.sh | SERVICE EXIT: 0 | SERVICE EXIT: 0 |
| `swift test` (full) | 295 + 136 + 6 tests passed (baseline 280 + 136 + 6) | 295 + 136 + 6 tests passed |
| SwiftLint `--strict --quiet` | no output, exit 0 | no output, exit 0 |
| privacy-check network / logs, strings-check | pass (369 strings, 5 languages) | pass (369 strings) |
| Former-name grep | no match | no match |
| Diff scope vs e8eff47e | only `files_modified` | plus the SUMMARY; `HolzBarShelf.swift` unchanged ("SHELF UNCHANGED"); in `show(on:)`, `makeKeyAndOrderFront` (line 135) comes before `updateCache()` (line 148) |

## Deviations from Plan

1. **[Rule 1 - Bug in plan] Test case for the straddling item.** The plan wanted `x 1488.5, width 24` to be off screen. That item overshoots display 1 by only 0.5 pt, which is inside the plan's own 1 pt tolerance (P-03), and the plan treats the same 0.5 pt overshoot at the outer left edge as on screen. The test now uses `x 1500` (12 pt overshoot) for the straddling case, which is off screen, and keeps `x 1488.5` as on screen. `isOnScreen` is implemented exactly as the plan says.
2. **P-09 fallback taken.** With the 26.5 SDK, capturing a `DispatchWorkItem` in the `@Sendable` queue block gives a Sendable warning in Swift 6 mode. As P-09 allows, the timer is a plain `asyncAfter` closure and is not cancelled. A timer that fires after the work has won finds the continuation gone and does nothing (one no-op wake-up per call).
3. **Extra guard in `captureDidTimeOut`.** It returns before `recordTimeout` when capture has already stopped, so the `.error` line can never repeat, even if a future caller bypasses `CoalescedRun`. The P-05 marker is still enqueued.
4. **Quieter section warning.** Within 2 s of a move, a hidden section whose items are all off screen yields no new images, by design (D-04). The existing persisted `.warning` "Failed item image cache for …" would have fired on every such pass. It now fires only when an item in the section has no image at all. The `.error` "Some items failed capture" is unchanged.
5. **Loop stop.** `captureAndStoreImages` breaks out of its section loop, and `captureIndividually` out of its item loop, once capture has stopped, so a stop mid-pass does not log a warning per remaining section.
6. **P-05 wording.** The notice reads "An abandoned item image capture returned after X s". X is the time since abandonment plus the 2 s timeout, which approximates the call's total duration.
7. **`CoalescedRun` isolation.** It is explicitly `@MainActor` (like `Debouncer`) with a `nonisolated init()`, so the cache can create it as a stored-property default.
8. **Task order.** Tasks 1 and 2 changed the cache in two steps, as planned. Commit A holds both, as the plan says.

The worktree branch is `audit-manual/events`, as the orchestrator set it up, so the generic GSD `agent-*` branch allow-list does not apply. No GSD STATE.md, ROADMAP.md or requirements updates: this audit-remediation chain has no phase state, and the PLAN files stay untracked.

## Known stubs

None.

## Threat flags

None beyond the plan's threat model. The new log lines carry only counts and durations (`.public`). No window ID, tag or app name is logged publicly, and the excluded-item lists stay `.private(mask: .hash)`. The debug key is local-only and pinned by `SettingsSchemaTests`.

## User test steps (maintainer, macOS 26.7.1, after CI)

**Signing the test build ("Können wir das mit dem signieren nicht doch anders lösen?").** Yes, without changing the repository or CI. Re-sign the CI build of this branch locally with holzBar's own release certificate, in a temporary keychain that you delete right afterwards. The test build then has the release's designated requirement (`identifier "com.holzcloud.holzBar" and certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"`), so macOS keeps Screen Recording and Accessibility, both for the test build and for the release afterwards. The exact commands are in `events-timeouts-PLAN.md`, section "Getting a test build without granting permissions again". One such build covers the hand tests of both the timeouts part and this part. Never put the key into the login keychain or the repository. This chain ran none of these commands.

Normal path:
1. Settings › Menu Bar Layout. Every section shows its item images.
2. Drag 2-3 items between Visible, Hidden and Always Hidden. Within 1-2 s of each drop, open the Shelf (it opens within about 1 s, with images), open the search (it appears at once), and switch back to Menu Bar Layout. There is no beachball, and within about 3 s the images match the new layout.
3. Repeat step 2 five times quickly. holzBar stays responsive, and the images keep updating.
4. With a second display: place it left of the built-in display (the 5e316dc scenario) and repeat step 2 with the active menu bar on each display. Images keep the right size and update, and nothing freezes.
5. Close every holzBar view, wait over 60 s, then open the search. The panel appears at once. Some rows may show app icons for a moment before the pictures appear.
6. `log show --last 15m --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "MenuBarItemImageCache"' | grep -E "did not return|abandoned|stopped"` prints nothing. If it prints lines, report them: that is real evidence of hangs.

Watchdog path:
7. Open the Shelf once so images are cached, then close it. Run `defaults write com.holzcloud.holzBar DebugHangsItemImageCapture -bool true`. Within 60 s, open the Shelf (within about 1 s, with the last images), then the search (at once, with images), and keep the search open for about 10 s.
8. The log command from step 6 shows two warnings ("… 1 of 3 abandoned", "… 2 of 3 abandoned") and exactly one error ("Item image capture stopped until holzBar is relaunched"). There is no beachball at any point.
9. Close every view, wait over 60 s, and open the Shelf. It still shows the last images, not "Unable to display menu bar items". Menu Bar Layout shows images, and moving an item still works.
10. Run `defaults delete com.holzcloud.holzBar DebugHangsItemImageCapture`, then quit and relaunch holzBar. Capture stays stopped until relaunch by design. After the relaunch, steps 1-2 work normally.

macOS 27 (if available):
11. Open the search. It appears at once and stays open while missing items are photographed. The Shelf behaves as before.

## doc_updates_needed (not done here)

- `docs/upstream-bugs.md:22`, row "Main thread hangs in screen capture" (#777). Status: "Captures run on their own queue (`macos-26` base). A capture that does not return is given up after 2 s, later captures continue on a new queue, and single captures skip items off screen (F-13)."
- `docs/release-notes/v0.0.7-beta2.md` (to be written), under Fixed:
  - "On macOS 26, an item picture that cannot be captured no longer stops all item pictures from updating, or keeps the search and the holzBar Shelf from opening, until holzBar is quit."
  - "The search opens at once and fills in item pictures as they arrive."
- Optional: in `docs/build-and-troubleshooting.md`, the hidden `DebugHangsItemImageCapture` default next to `DebugDropsBarrierExitEvent`.
- Optional: a maintainer section in `docs/signing.md` on re-signing a CI build for hand tests (same as in the timeouts summary).

## Self-Check: PASSED

- `holzBar/Core/ItemCapturePolicy.swift`, `holzBar/Core/CoalescedRun.swift`, `Tests/HolzBarCoreTests/ItemCapturePolicyTests.swift` and `Tests/HolzBarCoreTests/CoalescedRunTests.swift` exist.
- Commit 84de2f53 is an ancestor of HEAD.
- `captureRun.run(`, `ItemCapturePolicy.isOnScreen(` and the uncommented `BlockingWork.run(on:` each appear once in the cache.
- `showGeneration` and `isShowPending` no longer appear in `holzBar/MenuBar/Search`.
