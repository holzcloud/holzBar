---
phase: audit-remediation-events
plan: timeouts
type: execute
wave: 1
depends_on: []
files_modified:
  - holzBar/Utilities/ConcurrencyHelpers.swift          # moved (git mv) to holzBar/Core/ConcurrencyHelpers.swift
  - holzBar/Core/ConcurrencyHelpers.swift
  - holzBar/Core/EventBarrierPolicy.swift               # new
  - holzBar/Core/Defaults.swift
  - holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift
  - holzBar/MenuBar/Shelf/HolzBarShelf.swift
  - Tests/HolzBarCoreTests/TaskTimeoutTests.swift       # new
  - Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift # new
  - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
autonomous: true
requirements: [F-01]
user_setup: []

estimate:
  tokens: 120000
  raw_tokens: 120000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "On macOS 26 a move or click whose entry or exit event never comes back returns an error after a bounded time: about 2 s for a click, under 2 s for a move (two attempts at most)"
    - "After such a failure the pointer is visible again, show on hover, click and scroll work again, and the next move or click runs (eventLock released, HID monitors restored, cursor hide count balanced)"
    - "No event tap of a barrier stays enabled after the barrier ends, whether it succeeded, timed out, failed fast or was cancelled"
    - "A successful move or click is timed exactly as before: a main barrier returns as soon as its exit event arrives"
    - "Task(timeout:) throws TaskTimeoutError within the timeout (plus scheduling slack) even when the operation ignores cancellation"
    - "On macOS 26 the holzBar Shelf opens after at most about 1 s, with the cached images, when the refresh hangs; the refresh still finishes in the background and updates the caches"
    - "A settings file or settings sync can never turn on the debug default that drops barrier exit events"
  artifacts:
    - path: holzBar/Core/ConcurrencyHelpers.swift
      provides: "TaskTimeoutError, ResumeOnce, Task(timeout:), Task.detached(timeout:) that return at the timeout"
    - path: holzBar/Core/EventBarrierPolicy.swift
      provides: "minimumMainWait (500 ms), Bound.main/.fallback, AttemptBudget, moveTimeout(afterFailure:barrierTimedOut:)"
    - path: Tests/HolzBarCoreTests/TaskTimeoutTests.swift
      provides: "regression test for the helper (cancellation-ignoring operation) plus success, error, cancel and resume-once cases"
    - path: Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift
      provides: "bounds, retry cap and adaptive-timeout rule"
  key_links:
    - from: "MenuBarItemEventPoster.postEventWithBarrier / scrombleEvent"
      to: "ResumeOnce + withTaskCancellationHandler"
      via: "the exit tap, onCancel and the fail-fast check resume the same ResumeOnce; taps are disabled in a main-actor defer"
    - from: "MenuBarItemEventPoster.move / click"
      to: "EventBarrierPolicy.AttemptBudget"
      via: "at most one further attempt after EventError.eventOperationTimeout"
    - from: "HolzBarShelfPanel.show (before macOS 27, or with MacOS27IceBarWaitsForRefresh)"
      to: "Task(timeout: .seconds(1)) { await refresh.value }"
      via: "the rewritten helper; the refresh is its own task and is not cancelled"
---

# F-01 — bounded event barriers and a bounded Shelf wait (chain "events", part "timeouts")

Branch `audit-manual/events` (worktree `scratchpad/wt2/events`), based on `audit/remediation-2026-10-05` at `7e7ed6bf`, which already contains the 66 automatic fixes. Finding text: `.planning/audit/FULL-AUDIT-2026-10-05.md`, `#### F-01`. Decisions: `scratchpad/decisions/event-timeouts-1.md` and `event-timeouts-2.md`.

<objective>
Close F-01 exactly as the maintainer decided:

- **event-timeouts-1, "Sicherheitsnetz, Timing unverändert" (option A):** a lost event round trip ends a move or click after a bounded time instead of hanging holzBar until it quits. The successful path keeps today's timing. Only a really lost round trip is bounded: main barriers wait `max(timeout * count, 500 ms)`.
- **event-timeouts-2, "Höchstens 1 s warten":** on macOS 26 the Shelf keeps its pre-show refresh wait, now really bounded to 1 s. The refresh is not cancelled, so its result still reaches the caches.

Purpose: every move and click on macOS 26 (and 14/15) goes through `MenuBarItemEventPoster`. Today one lost null event leaves the pointer hidden system-wide, show on hover, click and scroll off, `eventLock` held, and a Shelf that may never open again.

Output: a rewritten timeout helper in `holzBar/Core` (so `swift test` compiles it), cancellation-correct event barriers with fail-fast checks and a retry cap, a local-only debug default for the hand test, a bounded Shelf wait, and new unit tests. Two local commits, no push.
</objective>

## Decisions (traceability IDs used below)

| ID | Source | Decision |
|---|---|---|
| D-01 | timeouts-1, common core (1) | Rewrite `Task.value(of:timeout:tolerance:clock:)`. A timeout returns without awaiting the operation. Use one `CheckedContinuation` behind an `OSAllocatedUnfairLock` resume-once state, which also records a cancellation that arrives before the continuation is stored. A waiter task resumes it with `await operationTask.result`. A sleeper task, on expiry, cancels `operationTask` and resumes it with `TaskTimeoutError`. The winner cancels the sleeper. Outer cancellation (`withTaskCancellationHandler`) cancels `operationTask` and resumes with `CancellationError`. Fix the doc comment. Move the file into `holzBar/Core` (synchronized group, no pbxproj edit). Add `TaskTimeoutTests`. |
| D-02 | timeouts-1, common core (2) | In `postEventWithBarrier` and `scrombleEvent`: delete the inner unstructured task, and wrap the continuation in `withTaskCancellationHandler`. Keep the continuation in a lock and resume it exactly once, from the exit tap, `onCancel` or a fail-fast check. Enable the taps and post the entry event synchronously in the continuation body (main actor). Fail fast when a tap is not valid or the pid is gone (`kill(pid, 0) == -1 && errno == ESRCH`). Disable all taps in a main-actor `defer`. Put a cancellation handler around `try await timeoutTask.value` that cancels `timeoutTask`. |
| D-03 | timeouts-1, common core (3) | In `move()` and `click()`, allow at most one further attempt after `EventError.eventOperationTimeout`. |
| D-04 | timeouts-1, common core (3) | Do F-21 (same file) in the same change. **Already resolved on the base branch:** commits `32065b86`, `f4cc7583`, `54237c97` and `4e62a66b`. Verify only, change nothing. |
| D-05 | timeouts-1, option A | Main barriers wait `max(timeout * count, 500 ms)`, as a named constant. The fallback double mouse-up keeps its designed bound (100 ms x2 for moves, 250 ms x2 for clicks). `waitForMoveEventResponse` keeps its adaptive timeout. An `eventOperationTimeout` must not grow the adaptive move timeout. |
| D-06 | timeouts-1, option A | Log each barrier's round-trip duration at debug level, with public numbers only. |
| D-07 | timeouts-1, optional | A hidden debug default, following the `macOS27ShelfWaitsForRefresh` pattern, that drops the exit event, so the maintainer can watch the pointer come back. **Planned (taken).** It is the only way to exercise the timeout path on the maintainer's Mac. It is local-only, so no imported or synced file can set it. |
| D-08 | timeouts-1 | No new user-facing strings. Gates: CI and `swift test`. The maintainer then tests on macOS 26.7.1. Doc updates come afterwards (listed below; this chain does not edit docs). |
| D-09 | timeouts-2 | Keep the pre-show wait in `HolzBarShelfPanel.show` (also the `macOS27ShelfWaitsForRefresh` path). Start the refresh as its own `Task`, bound only the wait with `Task(timeout: .seconds(1)) { await refresh.value }`, and never cancel the refresh. The macOS 27 default path stays unchanged. |
| D-10 | timeouts-2 | F-83's show-generation check after the await. **Already resolved on the base branch:** commits `b6b6e371` and `1b427190` (`showGeneration`, guard at `HolzBarShelf.swift:228-232`). Keep it intact. |

The audit's fix step 3 ("show first, as on macOS 27") is replaced by D-09 by maintainer decision. It would flash "Unable to display menu bar items" on macOS 26.

## Verified current state (worktree at 7e7ed6bf)

- `holzBar/Utilities/ConcurrencyHelpers.swift:33-57`: the task-group helper. Its group waits for the child that awaits `operationTask.value`. Lines 60-119 hold the `Task(timeout:)` and `Task.detached(timeout:)` initializers. Only Foundation and `os.lock` are imported, so the file compiles unchanged in the `HolzBarCore` package target (checked).
- `holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift`:
  - `postEventWithBarrier`: 163-271, inner task 248-261, catch 264-270.
  - `scrombleEvent`: 285-417, inner task 392-407, catch 410-416.
  - `waitForMoveEventResponse`: 515-556. It works and is not changed.
  - `postMoveEvents`: 564-646. The fallback is at 630-642, `timeout += timeout / 2` at 643.
  - `move()`: 653-709, retry loop 684-708, `maxAttempts = 8`.
  - `postClickEvents`: 730-796, fallback 781-793.
  - `click()`: 803-840, retry loop 819-839, `maxAttempts = 4`.
  - F-21 is in place: `NSEvent.heldModifierFlags` at 40, 5 s bound and `userInputNotPaused` at 51-64.
- `holzBar/Events/EventTap.swift`:
  - `enable()` (269-274) first calls `recreateIfInvalid()` and then returns silently when there is no port.
  - `isValid` (93-96).
  - `disable()` is idempotent.
  - `Resources.deinit` invalidates the port when the tap is released.
- `holzBar/MenuBar/Shelf/HolzBarShelf.swift:190-267`: `show(section:on:)`. The macOS 27 default branch is at 204-214, the bounded wait at 215-226, the F-83 guard at 228-232.
- All `Task(timeout:)` call sites:
  - EventPoster 190, 312 and 533;
  - HolzBarShelf 216;
  - `MenuBarOverlayPanel.swift:41` (`Task.detached(timeout:)`, wallpaper updates, 5 s). Its operation is cancellation-aware and nothing awaits these tasks, so it needs no change.
- `AppDelegate.swift:53` sets `SetsCursorInBackground`, so an unbalanced `CGDisplayHideCursor` hides the pointer system-wide.
- Installed release (read-only check): `/Applications/holzBar.app` 0.0.7-beta1, `designated => identifier "com.holzcloud.holzBar" and certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"`; the XPC service has the same leaf; host macOS 26.7.1, Command Line Tools only (no Xcode).

## Prototype evidence (scratchpad only, not in the repository)

The whole design below was prototyped in `scratchpad/events-timeouts-probe/` (copies; the worktree is untouched):
- `tree/`: modified app sources.
- `pkg/Tests/HolzBarCoreTests/{TaskTimeoutTests,EventBarrierPolicyTests}.swift`: the tests.

Results:
- The whole app module (holzBar/ + Shared/) passes a SIL type-check with the app's flags (Swift 6, default MainActor isolation, NonisolatedNonsendingByDefault, InferIsolatedConformances, target macOS 14.0): **0 errors**, with only the pre-existing CGWindowList deprecation warning.
- `swift test` with the new suites plus SettingsSchemaTests: **27 tests passed**.
- `swiftlint lint --strict` on the touched files: **clean**.
- RED check: the current helper raised `TaskTimeoutError` **3.19 s** after a 100 ms timeout (when the test's safety gate let the operation finish). The rewrite raised it after **0.11 s**.

The executor may diff against the prototype for orientation. This plan stays authoritative, and the prototype does not yet have `store(_:)` returning `Bool` (see Task 2).

## Design

### Helper (D-01): `holzBar/Core/ConcurrencyHelpers.swift`

- `git mv holzBar/Utilities/ConcurrencyHelpers.swift holzBar/Core/ConcurrencyHelpers.swift`. Keep the header (the SwiftLint `file_header` rule uses the file name, which does not change) and keep `TaskTimeoutError` unchanged.
- New `nonisolated final class ResumeOnce<Success: Sendable>: Sendable`, the resume-once state D-01 and D-02 ask for, written once and tested:
  - State `OSAllocatedUnfairLock<State>`, with `enum State { case waiting(CheckedContinuation<Success, any Error>?), early(Result<Success, any Error>), resumed }`.
  - `@discardableResult func store(_ continuation:) -> Bool` stores the continuation and returns `true` while it waits. When a result arrived first, it resumes the continuation with that result at once and returns `false`. That covers a cancellation that arrives before the continuation is stored.
  - `@discardableResult func resume(with: Result<Success, any Error>) -> Bool` resumes the stored continuation and returns `true` if this call won. Without a stored continuation it records the result as `early`. After that every call is a no-op.
  - Convenience: `resume(throwing:)`. For `Void`, callers use `resume(with: .success(()))`.
  - Doc comments in the style of `BlockingWork.swift`: what it is for, the race it settles, and the fact that later resumes do nothing.
- `Task.value(of:timeout:tolerance:clock:)` (stays `fileprivate`). It creates `let outcome = ResumeOnce<Success>()`, then `try await withTaskCancellationHandler { try await withCheckedThrowingContinuation { … } } onCancel: { operationTask.cancel(); outcome.resume(throwing: _Concurrency.CancellationError()) }`. In the body:
  1. `outcome.store(continuation)`.
  2. A sleeper `_Concurrency.Task<Void, Never>` sleeps `timeout` (tolerance, clock) and returns quietly when the sleep throws. On expiry it calls `operationTask.cancel()` **first**, then `outcome.resume(throwing: TaskTimeoutError())`. The order matters, because the cancelled operation's continuation is then enqueued on the main actor before the caller's resumption. So a barrier's taps are disabled (its `defer`) before the caller starts the fallback barrier. Say so in a comment.
  3. A waiter `_Concurrency.Task<Void, Never>` runs `let result = await operationTask.result; outcome.resume(with: result); sleeper.cancel()`.

  Qualify `_Concurrency.Task` inside the generic `Task` extension, as the file already does for `sleep`. A bare `Task` there means `Task<Success, Failure>`.
- Doc comments:
  - `value(of:)`: "Waits for the given task, but no longer than `timeout`: when the timeout fires first, the task is cancelled and ``TaskTimeoutError`` is thrown at once, without waiting for the task to end (an operation that ignores cancellation goes on in the background and its result is dropped). Cancelling the waiting task cancels the task and throws `CancellationError`."
  - Both initializers' doc comments: add "at once, even if the operation ignores cancellation".

### Event barriers (D-02, D-05, D-06, D-07): `MenuBarItemEventPoster.swift`

`postEventWithBarrier(_:to:timeout:repeating:bound:)` and `scrombleEvent(_:item:timeout:repeating:bound:)` share one shape. They differ only in their taps: two taps, versus three (EventTap 3 at the pid). The new parameter is `bound: EventBarrierPolicy.Bound = .main`.

1. `hideCursor` / `defer showCursor`, the entry and exit event creation, `pid` and `setTargetPID` and the two locations stay as they are.
2. Before shadowing `count`: `let wait = bound.wait(timeout: timeout, count: count)`, `let dropsExitEvent = Defaults.bool(forKey: .debugDropsBarrierExitEvent)` (D-07) and `let startedAt = ContinuousClock.now`. Then `var count = count`, as today.
3. `let timeoutTask = Task(timeout: wait) { … }`. The operation inherits the main actor, as today. Inside it:
   - `let barrier = ResumeOnce<Void>()`.
   - Create the taps exactly as today, with two changes in EventTap 1's exit branch. First, `guard !dropsExitEvent else { return nil }`: it consumes the exit event without resuming (D-07). Second, it calls `tap.disable(); barrier.resume(with: .success(()))` instead of `continuation.resume()`.
   - `let eventTaps = [eventTap1, eventTap2(, eventTap3)]`, then `defer { for eventTap in eventTaps { eventTap.disable() } }`. That defer runs on the main actor, in every exit path (D-02). The `eventTaps` array that stays alive today goes away: the local array and the defer keep the taps alive until the barrier ends.
   - `try await withTaskCancellationHandler { try await withCheckedThrowingContinuation { continuation in … } } onCancel: { barrier.resume(throwing: CancellationError()) }`. The continuation body runs synchronously on the main actor and does this:
     1. `guard barrier.store(continuation) else { return }`. If the barrier was already cancelled (the task was cancelled before the body ran, for example during a main-thread stall longer than `wait`), no tap is enabled and nothing is posted.
     2. If `kill(pid, 0) == -1 && errno == ESRCH`, call `barrier.resume(throwing: EventError.cannotComplete)`, log `notice` "The target process of the event barrier is gone" (no pid, no name) and `return`.
     3. Enable every tap.
     4. If any tap is not `isValid` after `enable()` (which already retried creating it), call `barrier.resume(throwing: EventError.eventCreationFailure(item))`, log `error` "\(label, privacy: .public) is not valid" and `return`.
     5. `entryEvent.post(to: firstLocation)`.

     Put steps 2 and 4 into one private helper, `barrierStartFailure(eventTaps:pid:item:) -> EventError?`, and call it at the right points, or inline them if that reads better. Both errors are existing `EventError` cases with existing localized texts (D-08: no new strings).
   - The old unstructured task with its `withTaskCancellationHandler` and the nested main-actor hop is deleted entirely (D-02).
4. Waiting, all on the caller's main actor:
   - `do { try await withTaskCancellationHandler { try await timeoutTask.value } onCancel: { timeoutTask.cancel() }`.
   - On success, log `debug` "Event barrier round trip took \(startedAt.duration(to: .now), privacy: .public) of \(wait, privacy: .public)" (D-06).
   - `catch is TaskTimeoutError`: log `notice` "Event barrier timed out after \(wait, privacy: .public)", then `throw EventError.eventOperationTimeout(item)`.
   - `catch let error as EventError { throw error }`: new, so that fail-fast errors pass through.
   - `catch { throw EventError.cannotComplete }`.

   The notice level is persisted, so `log show` after the hand test reveals every real timeout. The same reasoning is behind the F-21-R2 review fix (`54237c97`).

New pure policy, `holzBar/Core/EventBarrierPolicy.swift`. It is a `nonisolated enum EventBarrierPolicy`, like `MoveBackoff` / `BlockingWork`, with the file header and doc comments:
- `static let minimumMainWait = Duration.milliseconds(500)` (D-05, the named constant).
- `enum Bound: Sendable { case main, fallback }` with `func wait(timeout: Duration, count: Int) -> Duration`. `main` returns `max(timeout * count, minimumMainWait)`; `fallback` returns `timeout * count` (the designed bound).
- `struct AttemptBudget: Sendable` with `init(maxAttempts:)` and `mutating func allowsRetry(afterFailedAttempt attempt: Int, barrierTimedOut: Bool) -> Bool`. A timeout lowers the limit to `min(limit, attempt + 1)`, and the function returns `attempt < limit` (D-03).
- `static func moveTimeout(afterFailure timeout: Duration, barrierTimedOut: Bool) -> Duration`. It returns `timeout` unchanged after a barrier timeout and `timeout + timeout / 2` otherwise (D-05).

Call sites:
- The `postMoveEvents` fallback passes `bound: .fallback` (100 ms x2 = 200 ms). The catch replaces `timeout += timeout / 2` with `timeout = EventBarrierPolicy.moveTimeout(afterFailure: timeout, barrierTimedOut: Self.isBarrierTimeout(error))`. The success path's `timeout -= timeout / 4` and the averaging and clamping in `updateMoveOperationTimeout` stay.
- The `postClickEvents` fallback passes `bound: .fallback` (250 ms x2 = 500 ms). The main click barriers use `.main`: mouse-down `max(250 ms, 500 ms)` = 500 ms, mouse-up x2 `max(500 ms, 500 ms)` = 500 ms.
- In `move()` and `click()`, add `var budget = EventBarrierPolicy.AttemptBudget(maxAttempts: maxAttempts)`. In the catch, replace `if n < maxAttempts` with `if budget.allowsRetry(afterFailedAttempt: n, barrierTimedOut: Self.isBarrierTimeout(error))`. Everything else stays: the buffer or `eventSleep`, the final `EventError` mapping and the `Task.isCancelled` guard.
- Add `private static func isBarrierTimeout(_ error: any Error) -> Bool`, true for `EventError.eventOperationTimeout`.
- `waitForMoveEventResponse` is not touched (D-05).

Debug default (D-07), `holzBar/Core/Defaults.swift`:
- `// MARK: Debugging` after the macOS 27 keys: `case debugDropsBarrierExitEvent = "DebugDropsBarrierExitEvent"`. Its doc comment: "Drops the exit event of every move and click event barrier before macOS 27, so each barrier times out; shows that holzBar recovers from a lost event. Hidden: `defaults write com.holzcloud.holzBar DebugDropsBarrierExitEvent -bool true`. Never exported, imported or synced."
- Add it to the `.bool` group of `settingsKind`, next to `.macOS27ShelfWaitsForRefresh`.
- Add it to `localOnlyKeys`, so it stays out of `importableKinds`, out of `SettingsBackup.currentSettings()` and away from sync. Extend that property's doc comment by one clause: debug defaults stay on this Mac too.

### Worst-case bounds after the change (lost round trip)

| Path | One attempt | With the one further attempt (D-03) |
|---|---|---|
| Click, mouse-down or mouse-up barrier lost | 500 ms main + 500 ms fallback ≈ 1.0 s | ≈ 2.0 s + 25 ms `eventSleep` |
| Move, mouse-down barrier lost | 500 ms + 200 ms fallback ≈ 0.7 s | ≈ 1.4 s + 25 ms buffer |
| Move, mouse-up barrier lost | ≤ 150 ms response + 500 ms + 200 ms ≈ 0.85 s | ≈ 1.7 s |
| Pid gone or tap invalid | fails at once (fallback fails at once too) | move up to 8 instant attempts, click up to 4 |
| Successful round trip | unchanged: returns when the exit event arrives | — |

This matches "nach höchstens etwa zwei Sekunden". The pointer is hidden, the HID monitors are stopped and `eventLock` is held for at most these times.

### Shelf (D-09, D-10): `HolzBarShelf.swift:215-226`

- In the else branch, replace the operation of `Task(timeout: .seconds(1)) { cacheItemsIfNeeded(); updateCache() }` with `let refresh = Task { await appState.itemManager.cacheItemsIfNeeded(); await appState.imageCache.updateCache() }` and `let cacheTask = Task(timeout: .seconds(1)) { await refresh.value }`. Add a two-line comment: the refresh is its own task, so a timeout ends only the wait and the refresh still lands in the observable caches; awaiting `.value` does not pass the cancellation on.
- Split the catch:
  - `catch is TaskTimeoutError` logs `Logger.default.notice("holzBar Shelf shown with the cached images: the refresh took longer than 1 s")`.
  - Any other error keeps the existing `error` log.
- The F-83 guard (228-232), the macOS 27 default branch (204-214) and everything after them stay unchanged.

### How each part of the F-01 failure scenario is closed

| Failure (audit) | After the fix |
|---|---|
| Item's app quit between the item read and the move | Before posting: `ESRCH` means an instant `cannotComplete`. During the barrier: a 500 ms timeout, the bounded fallback, then at most one more attempt (which fails at once). |
| `tapCreateForPid` failed, so `enable()` silently does nothing | `isValid` is false after `enable()`, so an instant `eventCreationFailure`. No enabled session tap is left behind (the defer disables them). |
| Tap disabled by `tapDisabledByTimeout` during a main-thread stall; event dropped by another session tap | Main barrier timeout of 500 ms, then the fallback double mouse-up (200/500 ms), then at most one more attempt. |
| `eventLock` held forever | `postMoveEvents`/`postClickEvents` return within the bounds above. Their `defer { eventLock.unlock() }` runs. |
| `CGDisplayHideCursor` never balanced | Every `defer { showCursor() }` (barrier, `postMoveEvents`/`postClickEvents`, `move()`) runs once the functions return. |
| `hidEventManager.stopAll()` never undone | `move()`/`click()` (and `temporarilyShow`) return, so their `defer { startAll() }` pops the state stack. |
| Mouse-down without mouse-up | The fallback double mouse-up now runs after a timeout, bounded as designed. |
| 2-3 listen-only session taps and a suspended task per lost round trip | The taps are disabled in the main-actor defer and released with the operation. `onCancel` resumes the continuation, so no task stays suspended. |
| Shelf never opens (a capture blocks the refresh) | The Shelf opens after 1 s with the cached images. The refresh finishes later (or stays blocked until F-13's fix, the "capture" chain), without blocking the Shelf. |
| Caps Lock blocks every move and click (F-21, same path) | Already fixed on the base branch. Unchanged and verified. |
| Closing the Shelf during the wait leaves an orphan panel (F-83) | Already fixed on the base branch. The guard stays after the bounded wait. |

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
</execution_context>

<context>
@CLAUDE.md
@.planning/audit/FULL-AUDIT-2026-10-05.md (sections F-01, F-13, F-21, F-83)
@holzBar/Utilities/ConcurrencyHelpers.swift
@holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift
@holzBar/Events/EventTap.swift
@holzBar/MenuBar/Shelf/HolzBarShelf.swift
@holzBar/Core/Defaults.swift
@holzBar/Core/BlockingWork.swift (style of a nonisolated Core helper)
@Tests/HolzBarCoreTests/AsyncLockTests.swift (Swift Testing style, OSAllocatedUnfairLock in tests)
@Tests/HolzBarCoreTests/SettingsSchemaTests.swift
@Package.swift
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Rewrite the timeout helper and bound the click barrier end to end (Core helper, then the click path)</name>
  <files>holzBar/Utilities/ConcurrencyHelpers.swift (git mv), holzBar/Core/ConcurrencyHelpers.swift, holzBar/Core/EventBarrierPolicy.swift, Tests/HolzBarCoreTests/TaskTimeoutTests.swift, Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift, holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift</files>
  <read_first>holzBar/Utilities/ConcurrencyHelpers.swift; MenuBarItemEventPoster.swift lines 151-271 and 711-840; holzBar/Events/EventTap.swift 84-96 and 264-281; Tests/HolzBarCoreTests/AsyncLockTests.swift 1-30; Package.swift</read_first>
  <behavior>
    - TaskTimeoutTests "An operation that ignores cancellation times out on time": `Task(timeout: .milliseconds(100)) { await gate.wait() }` throws TaskTimeoutError, and the elapsed time is under 500 ms (D-01).
    - "A result within the timeout is returned": the value 42 comes back.
    - "The operation's error is passed on": a custom error is rethrown unchanged.
    - "Cancelling the task ends the wait at once": cancel right after creation; CancellationError in under 1 s, while the gate never opens during the wait.
    - "A detached task times out too": the same check through Task.detached(timeout:).
    - "Only the first resume reaches the continuation": store returns true, the first resume returns true, later resumes return false, and the value is the first one.
    - "A resume before the continuation is stored is kept": resume(throwing: CancellationError()) first returns false; store then returns false and the await throws CancellationError.
    - EventBarrierPolicyTests: main wait is 500 ms for (50 ms, 1) and (250 ms, 2) and 600 ms for (300 ms, 2). Fallback wait is 200 ms for (100 ms, 2) and 500 ms for (250 ms, 2). Without timeouts the budget allows retries after attempts 1..max-1 but not after max. A timeout after attempt k (k = 1, 3, 7 of 8) allows one retry, and after attempt k+1 none. A timeout in the last attempt allows none. moveTimeout returns 100 ms after a barrier timeout and 150 ms after another failure.
  </behavior>
  <action>
    RED first, per D-01 and D-08. Run `git mv holzBar/Utilities/ConcurrencyHelpers.swift holzBar/Core/ConcurrencyHelpers.swift` without changing its contents. The synchronized `holzBar` folder group picks the file up, so do not edit holzBar.xcodeproj. Add Tests/HolzBarCoreTests/TaskTimeoutTests.swift (Swift Testing, `@testable import HolzBarCore`, `import os`). The test needs a small private Gate: a final Sendable class holding `OSAllocatedUnfairLock<(isOpen: Bool, waiter: CheckedContinuation<Void, Never>?)>`, with `wait()` (resumes at once when already open) and `open()`. Write only the first behavior test for now, with a safety task that opens the gate after 3 s, so a broken helper fails the test instead of hanging it. In a defer, open the gate and cancel the safety task, which resumes the test's continuation so nothing leaks. Run `swift test --filter TaskTimeoutTests` and confirm that it FAILS, with the error arriving after about 3 s; the prototype measured 3.19 s. Record the observed time in the summary.

    GREEN. In holzBar/Core/ConcurrencyHelpers.swift, add `ResumeOnce` and rewrite `Task.value(of:timeout:tolerance:clock:)` exactly as the plan's Design section "Helper (D-01)" describes. The sleeper cancels the operation BEFORE it resumes with TaskTimeoutError, and a comment explains why. Qualify the nested task types as `_Concurrency.Task<Void, Never>`. Fix the doc comments of `value(of:)` and both initializers. Then add the remaining helper tests from `<behavior>`. Keep the elapsed-time bound at timeout + 400 ms rather than the decision's "about 100 ms". The decision asks to prove that the helper no longer waits for the operation, and the old helper takes the full 3 s. Shared macOS CI runners (compat job: macos-14, macos-15, macos-26, xcode-27) can add more than 100 ms of scheduling jitter, which would make a tighter bound flaky. Note this choice in the summary.

    Add holzBar/Core/EventBarrierPolicy.swift as described in Design ("New pure policy"), with the file header `//\n//  EventBarrierPolicy.swift\n//  holzBar\n//`, doc comments on every member, and `nonisolated` on the enum, as in BlockingWork. Add Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift. Swift Testing's #expect cannot call a mutating method on a struct, so store the result of `allowsRetry` in a `let` first and then expect on it.

    Tracer through the app, click path only. In MenuBarItemEventPoster.swift, rewrite `postEventWithBarrier` per Design steps 1-4 (D-02, D-05, D-06). Add the `bound` parameter. Add the private `barrierStartFailure(eventTaps:pid:item:)` helper and `isBarrierTimeout(_:)`. Set `bound: .fallback` on the click fallback in `postClickEvents`, and add the AttemptBudget to `click()` (D-03). Leave the debug default (D-07) for Task 2, but read it already as `Defaults.bool(forKey: .debugDropsBarrierExitEvent)` only if you add the key in this task. Otherwise wire it in Task 2. Do not touch `scrombleEvent` and `move()` yet.

    Do NOT commit after this task. Commit A in Task 2 must contain the helper and both barrier functions. A commit with the rewritten helper but the old `scrombleEvent` would leave the move path's dead cancellation handler behind a helper that now cancels it, and the decision rules out a helper-only state (taps and a suspended task leak per lost round trip).
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events && swift test --filter "TaskTimeoutTests|EventBarrierPolicyTests" 2>&1 | grep -E "Test run|error:|✘" ; zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events f01-t1</automated>
  </verify>
  <done>The new suites pass (RED observed first with the unchanged helper, then GREEN). appcheck prints "ERRORS: 0". `test -f holzBar/Core/ConcurrencyHelpers.swift && ! test -e holzBar/Utilities/ConcurrencyHelpers.swift` is true. `postEventWithBarrier` contains no nested unstructured task, and its taps are disabled in a defer. Nothing is committed yet.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Move path, debug default and retry cap; gates; commit A (F-01 barriers)</name>
  <files>holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift, holzBar/Core/Defaults.swift, Tests/HolzBarCoreTests/SettingsSchemaTests.swift</files>
  <read_first>MenuBarItemEventPoster.swift lines 273-417 and 558-709 (after Task 1, the line numbers have shifted; find `private func scrombleEvent(`, `private func postMoveEvents(`, `func move(item:`); holzBar/Core/Defaults.swift 200-210, 264-300, 375-386; Tests/HolzBarCoreTests/SettingsSchemaTests.swift 86-104 and 164-173</read_first>
  <behavior>
    - SettingsSchemaTests, new test "A settings file cannot drop event barrier exits": localOnlyKeys contains .debugDropsBarrierExitEvent; importableKinds["DebugDropsBarrierExitEvent"] is nil; validatedSettings(["DebugDropsBarrierExitEvent": true, "ShowOnHover": true]) accepts only ShowOnHover.
    - "Stored key names never change" also expects Defaults.Key.debugDropsBarrierExitEvent.rawValue == "DebugDropsBarrierExitEvent".
    - "Every stored key but the local ones is importable" still passes without changes.
  </behavior>
  <action>
    Debug default (D-07). In holzBar/Core/Defaults.swift, add `case debugDropsBarrierExitEvent = "DebugDropsBarrierExitEvent"` under a new `// MARK: Debugging` block after the macOS 27 keys, with the doc comment from Design. Add it to the `.bool` group of `settingsKind` and to `localOnlyKeys`, and extend that property's doc comment by one clause. Never rename an existing key. Add the two SettingsSchemaTests expectations from `<behavior>`. Wire the default into `postEventWithBarrier`: read it once per barrier, and in EventTap 1's exit branch `guard !dropsExitEvent else { return nil }`.

    Move path (D-02, D-05, D-06). Rewrite `scrombleEvent` with the same shape as the Task 1 `postEventWithBarrier`: the bound parameter, ResumeOnce, the three taps in a local array, the main-actor defer that disables all of them, the continuation body (store, pid check, enable, validity check, entry post), onCancel resuming the barrier, the cancellation handler that forwards to `timeoutTask`, the debug and notice logs, and the EventError pass-through catch. EventTap 2 and EventTap 3 keep their exact current logic, including when they disable themselves and what they post. Only EventTap 1's exit branch changes, as in Task 1. In `postMoveEvents`, pass `bound: .fallback` to the fallback `scrombleEvent` call; it keeps its fixed 100 ms with `repeating: 2`. Replace the unconditional growth with `EventBarrierPolicy.moveTimeout(afterFailure:barrierTimedOut:)`, so an `eventOperationTimeout` no longer grows the adaptive timeout. `itemResponseTimeout` still grows it, because that is the working adaptive mechanism. Add the AttemptBudget to `move()` (D-03). Leave `waitForMoveEventResponse`, `getMoveOperationTimeout`, `updateMoveOperationTimeout` and `waitForMoveOperationBuffer` unchanged.

    F-21 (D-04). Confirm without editing: `hasUserPausedInput` uses `NSEvent.heldModifierFlags`, `waitForUserToPauseInput` loops in the calling task with a 5 s deadline and throws `userInputNotPaused`, and `MenuBarItemManager.move` skips the back-off for it.

    Match the surrounding comment density: one short comment per non-obvious step, such as why the body checks `store`, why the sleeper cancels first, and why the fallback has its own bound. No new user-facing strings (D-08); log texts are English and every interpolation names its privacy.

    Then run every gate in the plan's "Gates" section. If a gate fails and you cannot fix it, revert all uncommitted changes (`git -C <worktree> reset --hard HEAD` restores the moved file as well), report fix-failed with the reason, and stop. Otherwise create commit A with the message from the plan's "Commits" section. Stage explicitly: the moved file (both paths), the new Core and test files, MenuBarItemEventPoster.swift, Defaults.swift and SettingsSchemaTests.swift.
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events && swift test 2>&1 | grep -E "Test run|error:|✘" ; zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events f01-t2 ; grep -v '^ *//' holzBar/MenuBar/Backends/MenuBarItemEventPoster.swift | grep -c "bound: .fallback"</automated>
  </verify>
  <done>The full `swift test` passes. appcheck reports "ERRORS: 0". The `bound: .fallback` count is 2 (one move fallback, one click fallback). Every gate in "Gates" passes. Commit A exists on audit-manual/events, and `git status` is clean apart from Task 3's files.</done>
</task>

<task type="auto">
  <name>Task 3: Bound the Shelf's pre-show wait to 1 s without cancelling the refresh; gates; commit B</name>
  <files>holzBar/MenuBar/Shelf/HolzBarShelf.swift</files>
  <read_first>holzBar/MenuBar/Shelf/HolzBarShelf.swift lines 180-290</read_first>
  <action>
    Per D-09, in `HolzBarShelfPanel.show(section:on:)`'s else branch (before macOS 27, or on macOS 27 with the MacOS27IceBarWaitsForRefresh default), start the refresh as its own task: `let refresh = Task { await appState.itemManager.cacheItemsIfNeeded(); await appState.imageCache.updateCache() }`. Bound only the wait, with `let cacheTask = Task(timeout: .seconds(1)) { await refresh.value }`. Keep `do { try await cacheTask.value }`. Split the catch: a TaskTimeoutError logs a notice that the Shelf is shown with the cached images because the refresh took longer than 1 s; any other error keeps the existing error log line. Add the two-line comment from Design about why the refresh is its own task. Do not cancel `refresh` anywhere.

    Per D-10, leave the F-83 generation guard right after the wait, the macOS 27 default branch and the rest of `show()` exactly as they are. No new strings.

    Run all gates. On an unfixable failure, revert this task's uncommitted change, report fix-failed and stop; commit A stays. Otherwise create commit B with the message from "Commits".
  </action>
  <verify>
    <automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events && zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events f01-t3 ; grep -c "await refresh.value" holzBar/MenuBar/Shelf/HolzBarShelf.swift ; grep -c "guard generation == showGeneration, currentSection == section" holzBar/MenuBar/Shelf/HolzBarShelf.swift</automated>
  </verify>
  <done>appcheck reports "ERRORS: 0". Both greps print 1. All gates pass. Commit B exists, and the worktree is clean except for this plan file (which the orchestrator handles).</done>
</task>

</tasks>

## Commits (local only; never push)

The git identity is configured; do not change git config. Use `git -C <worktree> add <explicit paths>` and `git -C <worktree> commit -F <message file in scratchpad>`.

Commit A (Tasks 1 and 2):
```
fix(backends): resolve F-01 — bound lost event barriers on macOS 26

The maintainer chose a safety net that leaves successful timing unchanged.
Task(timeout:) waited for the operation even after the timeout fired, and the
barriers' cancellation handler sat in a task that ended after posting, so a lost
round trip hung moves and clicks with the pointer hidden. The helper (now in
holzBar/Core, unit tested) returns at the timeout. The barriers resume once from
the exit tap, cancellation or a fail-fast check, disable their taps on exit and
wait at least 500 ms; a timeout allows one more attempt and does not grow the
move timeout. A local-only debug default drops exit events for testing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

Commit B (Task 3):
```
fix(shelf): resolve F-01 — open the Shelf after at most 1 s on macOS 26

The maintainer chose to keep the pre-show refresh wait but bound it to 1 s. The
wait never ended while an item capture hung, because Task(timeout:) waited for
the operation. With the helper fixed, the refresh now runs as its own task and
only the wait is bounded, so the Shelf opens with the cached images and the
refresh still updates the caches. F-83's show-generation check stays after it.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

## Gates (run from the worktree before each commit; all must pass)

`S=/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`, `W=$S/wt2/events`.

1. `cd $W && swift test`: all suites pass. A run that stops with "plugin for module 'TestingMacros' not found" / "error: fatalError" and no compiler error is a known transient of the build system; run it once more.
2. `zsh $S/appcheck.sh $W <label>`: "ERRORS: 0". This is the SIL type-check of the whole app module with the app's Swift settings and target macOS 14.0. It is the only local check of the app target, because the host has no Xcode.
3. `zsh $S/servicecheck.sh $W`: "SERVICE EXIT: 0" (unaffected, sanity check).
4. `cd $W && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools $S/swiftlint/swiftlint lint --strict --quiet`: no output, exit 0. Without `TOOLCHAIN_DIR`, SwiftLint cannot load sourcekitd on this host.
5. `cd $W && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/strings-check.py`: all pass, with the string count unchanged (369).
6. Former name: `cd $W && git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'` prints nothing (exit 1).
7. `git -C $W diff --stat HEAD~2` touches only the files in `files_modified` (plus the rename).

CI (build on the `xcode-27` image, `swift test` on macos-14/15/26, SwiftLint image, launch check) runs after the orchestrator pushes the combined remediation branch. Per CLAUDE.md, this chain does not push.

## Tests added

- `Tests/HolzBarCoreTests/TaskTimeoutTests.swift`: 7 tests. They cover the regression (an operation that ignores cancellation, with a timing bound), success, error propagation, cancellation of the waiting task, `Task.detached(timeout:)`, `ResumeOnce` resume-once, and an early resume before `store`.
- `Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift`: 6 tests, 3 of them parameterised. They cover the main and fallback bounds, the retry budget with and without timeouts (including a timeout in the last attempt), and the adaptive move timeout rule.
- `Tests/HolzBarCoreTests/SettingsSchemaTests.swift`: the debug key is local-only, cannot be imported or synced, and its raw value is pinned.
- Not unit-testable here: the EventTap and CGEvent paths, on any OS, and HolzBarShelf. These are covered by appcheck, CI and the maintainer's hand test below.

## Risks (macOS 26 and 27; 14/15 must keep compiling)

1. **macOS 26: spurious timeouts under a long main-thread stall.** If holzBar's main thread stalls for more than 500 ms during a barrier, the tap callbacks run late and the barrier times out. A fallback double mouse-up and one retry follow; before, holzBar just waited. For a move that already started, the fallback ends the drag in place and the retry repeats it. Mitigation: the floor is 500 ms, far above the 25-150 ms adaptive values, and every round trip is logged at debug and every timeout at notice, so real data can tune the constant later.
2. **macOS 26: semantics of `Task(timeout:)` for every caller.** After a timeout the operation may still be running. Callers that assumed "the error means the operation has finished" were checked:
   - EventPoster: the sleeper cancels first, and the barrier's onCancel and defer clean up before the caller's fallback runs on the main actor.
   - `waitForMoveEventResponse`: the operation's onCancel cancels the polling task, as before.
   - HolzBarShelf: intended (D-09).
   - `MenuBarOverlayPanel:41`: nothing awaits these tasks, and the operation is cancellation-aware.
3. **macOS 26: refresh pile-up while F-13 wedges the capture queue.** Each Shelf open while a capture hangs starts another refresh that suspends behind the queue, and each open costs the full 1 s. This is not a regression (today each open hangs forever). It ends with the "capture" chain's coalescing and watchdog (decision capture-queue-1, items (b) and (c)).
4. **macOS 26: the debug default ships in release builds**, like `MacOS27IceBarWaitsForRefresh`. It is local-only (an imported or synced file cannot set it) and needs `defaults write`. Anyone who can write holzBar's defaults can already break holzBar in other ways, so there is no new attack surface. Risk: the maintainer forgets to delete it after the test, and every move and click then fails within about 2 s. The hand-test steps end with deleting it.
5. **macOS 26: a fail-fast check on a pid the tap still accepts.** `kill(pid, 0)` returns `EPERM` for a process that exists but is not ours, so only `ESRCH` counts. `getEventPID` falls back to the owner (Control Center) when there is no source pid. That process is always alive, so the check never misfires there.
6. **macOS 27:** `AccessibilityBackend27` never uses `MenuBarItemEventPoster`, and the Shelf's default path does not wait. The only effects are the helper's new semantics (`MenuBarOverlayPanel` wallpaper updates, covered by Risk 2) and the Shelf wait with `MacOS27IceBarWaitsForRefresh` set (bounded now). Low risk; nothing to test by hand beyond a Shelf open.
7. **macOS 14/15:** `WindowListBackend` uses the same poster, so the same behaviour applies. No new API: `OSAllocatedUnfairLock` needs macOS 13, and `kill`, `errno` and `Task(name:)` are already in use with deployment target 14.0. appcheck compiles for macOS 14.0, and CI runs `swift test` on macos-14 and macos-15.
8. **Merge coordination with other chains:**
   - The "capture" chain's decision item (f) may also edit `HolzBarShelfPanel.show`'s wait. This chain owns that wait (D-09). The capture chain should keep `Task(timeout: .seconds(1)) { await refresh.value }` and not replace it, or whichever lands second must rebase onto the other.
   - `ConcurrencyHelpers.swift` moves from `Utilities/` to `Core/`. A chain that edits the old path conflicts; none does, per the decisions (mac27-clicks-2 only avoids the helper).
   - `Defaults.swift`'s `.bool` group and `localOnlyKeys` may conflict textually with another chain that adds keys (hotkey-conflicts); trivial to resolve.
9. **The `swift test` timing bound** (timeout + 400 ms) could still flake on an extremely loaded runner. If CI ever flakes, raise the slack rather than the timeout. The old helper's failure mode is about 3 s, so even a 1 s bound keeps the test meaningful.

## Maintainer hand test (after CI; macOS 26.7.1)

### Getting a test build without granting permissions again (answer to "Können wir das mit dem signieren nicht doch anders lösen?")

The decision's default was the ad hoc CI build. Its designated requirement is the code hash, so macOS treats it as a different app. Accessibility and Screen Recording would have to be granted to it, and then granted again to the release afterwards: two rounds. There is a better way that changes nothing in the repository or CI.

**Recommended: re-sign the CI build locally with holzBar's own release certificate** (the `holzBar Release Signing` `.p12` from the password manager; `docs/signing.md` already describes this "to try it"). The test build then has exactly the release's designated requirement, `identifier "com.holzcloud.holzBar" and certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"` (checked read-only on `/Applications/holzBar.app` 0.0.7-beta1). macOS keeps both permissions, for the test build and for the release afterwards, with no `tccutil` and no new grants. The XPC service pins the cdhash of the app it is embedded in when it starts, so re-signing both inside out keeps it working.

```sh
# 1. The PR build (artifact "holzBar-app", kept 1 day): Actions run page → Artifacts, or
mkdir -p ~/holzBar-test && cd ~/holzBar-test
gh run download <run-id> -R holzcloud/holzBar -n holzBar-app -D holzBar.app
chmod +x holzBar.app/Contents/MacOS/holzBar holzBar.app/Contents/XPCServices/*.xpc/Contents/MacOS/*(N)   # the zip loses the x bits
xattr -dr com.apple.quarantine holzBar.app

# 2. A temporary keychain with the certificate (the p12 exported from the password manager)
KEYCHAIN="$PWD/test-signing.keychain-db"; KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import holzbar-signing.p12 -k "$KEYCHAIN" -f pkcs12 -T /usr/bin/codesign   # asks for the p12 password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
IDENTITY=$(security find-identity -p codesigning "$KEYCHAIN" | awk '/^ *1\)/ && !found { print $2; found = 1 }')

# 3. Sign inside out, exactly like release.yml
sign() { codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --options runtime --timestamp=none \
  --preserve-metadata=identifier,entitlements,flags,runtime "$1"; }
for nested in holzBar.app/Contents/XPCServices/*.xpc(N); do sign "$nested"; done
sign holzBar.app
codesign --verify --deep --strict holzBar.app && codesign -d -r- holzBar.app   # must show the leaf above

# 4. Remove the key again
security delete-keychain "$KEYCHAIN"; rm -f holzbar-signing.p12
```

Then quit holzBar (`/Applications` copy) and run `open ~/holzBar-test/holzBar.app`. It must start without any permission prompt. If macOS asks anyway, the signature is not the release's: stop and compare `codesign -d -r-` of both apps. Afterwards, quit the test build, `open /Applications/holzBar.app` and `rm -rf ~/holzBar-test`, so Launch Services forgets the second copy. The `(N)` glob is zsh; it also works once the XPC service is gone (decision xpc-trust-1).

Alternatives (not recommended):
- (b) Ad hoc CI build, granting Accessibility and Screen Recording to it and then again to the release.
- (c) Publish a numbered beta from the release workflow first. It would reach every Homebrew user before the test.
- (d) Let CI sign PR builds with the certificate. This contradicts decision release-1, which allows the signing secrets only in a `release` environment for `v*` tags (F-05/F-10).

Security of (a): whoever has the key can sign code that macOS treats as holzBar. Keep it only in the temporary keychain (random password, deleted right away) and delete the exported `.p12` after signing. Never put it into the login keychain or the repository.

### Steps (each with the expected result)

Normal path, no regression (timing must feel exactly as before):
1. Settings › Menu Bar Layout: drag 3-4 items between Visible, Hidden and Always Hidden, including a Control Center item and a third-party item. Each move completes at today's speed, and the pointer reappears where it was.
2. Shelf: click the holzBar icon, then click a hidden item. Its menu opens, and the pointer comes back.
3. Search (search hotkey): open a hidden item from the results. Its menu opens.
4. Wait for the rehide interval. The temporarily shown item goes back to its section.
5. Shelf after a pause of over 60 s (the image cache was released): it opens within about 1 s, with images, and does not show "Unable to display menu bar items".
6. Caps Lock on, then repeat step 2 (F-21). It works. Then double-click the holzBar icon quickly (F-83): no orphaned Shelf remains.

Lost-event path (D-07):
7. In Terminal: `defaults write com.holzcloud.holzBar DebugDropsBarrierExitEvent -bool true`, then repeat step 2. Within about 2 s the pointer is visible again, show on hover works, and a second click also gives up within about 2 s instead of queueing. A drag in Menu Bar Layout shows the existing alert "Event operation timed out for …" after about 1.5 s.
8. `defaults delete com.holzcloud.holzBar DebugDropsBarrierExitEvent`. Without relaunching, repeat step 2: it works normally, which proves that no lock, monitor state or cursor count was left behind. (If the running app still seems to drop events, relaunch it once. The key is read on every barrier, so a running app normally sees the change at once.)
9. Optional, for tuning: during steps 1-3 run `log stream --level debug --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "MenuBarItemEventPoster"'` and note the "Event barrier round trip took …" values. Timeouts persist at notice level: `log show --last 30m --predicate 'subsystem == "com.holzcloud.holzBar" AND eventMessage CONTAINS "timed out"'`.
10. On macOS 27, if available: open the Shelf and change the wallpaper with a tint active. Both behave as before.

## doc_updates_needed (not done by this chain: docs/, README, SECURITY.md and release notes are out of bounds)

- `docs/upstream-bugs.md:31`, "Pointer gone or stuck after clicking an item in the Shelf" (#640, #751, #757): the status should say that holzBar now also recovers when an event round trip is lost. It gives up after about 2 s, so the pointer and the input monitors come back (F-01), on top of the 0.0.6 fix.
- `docs/release-notes/v0.0.7-beta2.md` (does not exist yet; write it with the beta), under Fixed:
  - "On macOS 26, a lost event no longer hides the pointer and stops moving, clicking and showing items on hover until holzBar is quit; holzBar gives up after about two seconds."
  - "On macOS 26, the holzBar Shelf opens after at most a second even when an item image cannot be captured."
- Optional, `docs/signing.md`: a short maintainer section, "Test a pull-request build without granting permissions again", with the re-signing steps above, so they need not be rediscovered.
- Optional, `docs/build-and-troubleshooting.md`: mention the hidden `DebugDropsBarrierExitEvent` default. The existing `MacOS27IceBarWaitsForRefresh` is not documented either, so this can be skipped.

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| holzBar → window server event stream | synthetic CGEvents posted to other apps' item windows; session and pid event taps see other apps' mouse events |
| defaults domain → holzBar | any process of the user, an imported settings file or settings sync can write holzBar's defaults |
| maintainer's Mac → release signing key | the hand test temporarily brings the release private key onto the Mac |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-F01-01 | Denial of service | MenuBarItemEventPoster barriers | high | mitigate | ResumeOnce plus withTaskCancellationHandler, a 500 ms minimum main wait, bounded fallbacks, AttemptBudget (one retry after a timeout), fail-fast on an invalid tap or a gone pid (Tasks 1 and 2) |
| T-F01-02 | Information disclosure | listen-only session taps (see every mouse event of their type) | medium | mitigate | every tap is disabled in a main-actor defer on every exit path and released with the operation; none outlives its barrier (Tasks 1 and 2) |
| T-F01-03 | Tampering | Defaults.Key.debugDropsBarrierExitEvent | medium | mitigate | listed in localOnlyKeys, so it is never exported, imported or synced; pinned by SettingsSchemaTests (Task 2) |
| T-F01-04 | Information disclosure | new log lines | low | mitigate | only durations and holzBar's own tap labels, privacy .public; no pid, item or app name; privacy-check.py logs gate |
| T-F01-05 | Spoofing | release signing key during the hand test | high | mitigate | temporary keychain with a random password, deleted right after signing; the exported .p12 deleted; never in the login keychain or the repository (hand-test step 4) |
| T-F01-06 | Denial of service | HolzBarShelfPanel.show refresh wait | medium | mitigate | the wait is bounded to 1 s by the rewritten helper; the refresh runs as its own task (Task 3) |
| T-F01-SC | Tampering | npm/pip/cargo installs | high | accept | not applicable: this plan installs no package and adds no dependency |
</threat_model>

<verification>
- Every gate in "Gates" passes before each commit; there are two commits on audit-manual/events (A: barriers and helper, B: Shelf).
- `swift test` includes TaskTimeoutTests (RED with the old helper observed and recorded, GREEN after the rewrite) and EventBarrierPolicyTests.
- Code check against the decisions:
  - no nested unstructured task in either barrier function (D-02);
  - `bound: .fallback` at both fallbacks (D-05);
  - `AttemptBudget` in `move()` and `click()` (D-03);
  - `moveTimeout(afterFailure:barrierTimedOut:)` in `postMoveEvents` (D-05);
  - debug and notice logs with public numbers (D-06);
  - the debug key is local-only (D-07);
  - no new String Catalog entries (D-08);
  - Shelf refresh task plus a 1 s wait (D-09);
  - F-21 and F-83 code unchanged (D-04, D-10).
- After CI: the maintainer's hand-test steps 1-8 on macOS 26.7.1, with the re-signed build.
</verification>

<success_criteria>
- A lost event round trip on macOS 26 ends a click within about 2 s and a move within about 1.7 s. The pointer, show on hover and later moves and clicks work again at once.
- Successful moves and clicks feel unchanged (hand-test steps 1-4).
- The Shelf on macOS 26 opens within about 1 s even when the refresh hangs (step 5).
- Two atomic local commits; all local gates green; no new user-facing strings; docs untouched (listed above).
</success_criteria>

## Source audit

| Source | ID | Item | Plan | Status |
|---|---|---|---|---|
| GOAL | F-01 | A lost round trip must not hang moves and clicks; the Shelf wait must be bounded | Tasks 1-3 | COVERED |
| REQ | F-01 | audit fix 1 (barriers), fix 2 (helper), fix 4 (regression test) | Tasks 1-2 | COVERED |
| REQ | F-01 | audit fix 3 (show first) | replaced by D-09 per the maintainer's decision | COVERED (as decided) |
| CONTEXT | D-01 | helper rewrite, move to Core, tests | Task 1 | COVERED |
| CONTEXT | D-02 | barrier continuation, fail-fast, defer, cancellation handler | Tasks 1-2 | COVERED |
| CONTEXT | D-03 | one further attempt after a timeout | Tasks 1-2 | COVERED |
| CONTEXT | D-04 | F-21 in the same change | already resolved on the base; verified in Task 2 | COVERED |
| CONTEXT | D-05 | 500 ms main floor, fallback bounds, adaptive timeout rule | Tasks 1-2 | COVERED |
| CONTEXT | D-06 | debug round-trip logs | Tasks 1-2 | COVERED |
| CONTEXT | D-07 | debug default that drops the exit event (optional) | Task 2 | COVERED |
| CONTEXT | D-08 | no new strings; CI and swift test; hand test; docs afterwards | Gates, hand test, doc_updates_needed | COVERED |
| CONTEXT | D-09 | Shelf: refresh task plus a bounded wait, macOS 27 default unchanged | Task 3 | COVERED |
| CONTEXT | D-10 | F-83 guard after the await | already resolved on the base; kept in Task 3 | COVERED |
| RESEARCH | — | fifth call site MenuBarOverlayPanel:41 | checked: no change needed (Risk 2) | COVERED |

<output>
After execution, write `.planning/audit/remediation/events-timeouts-SUMMARY.md` with:
- the commits;
- the RED time observed with the old helper;
- the gate results;
- any deviation from this plan, with its reason;
- the hand-test steps;
- doc_updates_needed.
</output>
