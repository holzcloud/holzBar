---
phase: audit-remediation-events
plan: capture
type: execute
wave: 2
depends_on: [timeouts]
files_modified:
  - holzBar/Core/BlockingWork.swift
  - holzBar/Core/ItemCapturePolicy.swift                 # new
  - holzBar/Core/CoalescedRun.swift                      # new
  - holzBar/Core/Defaults.swift
  - holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift
  - holzBar/MenuBar/Search/MenuBarSearchPanel.swift
  - Shared/Bridging/Bridging.swift                       # visibility of getActiveDisplayList only
  - Tests/HolzBarCoreTests/BlockingWorkTests.swift
  - Tests/HolzBarCoreTests/ItemCapturePolicyTests.swift  # new
  - Tests/HolzBarCoreTests/CoalescedRunTests.swift       # new
  - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
autonomous: true
requirements: [F-13]
user_setup: []

estimate:
  tokens: 140000
  raw_tokens: 140000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "On macOS 26 an item-image CGWindowList call that has not returned after about 2 s is given up: its waiter resumes with no new images, later captures run on a fresh serial queue, and item images keep updating"
    - "A window whose single capture did not return is not captured again while it is in the item cache; after 3 abandoned queues in one session item-image capture stops until relaunch, the last images stay (also 60 s after the last view closed) and exactly one .error line is logged"
    - "At most one capture pass runs at a time; a request during a pass waits for it and adds its sections to one shared re-run, so the capture queue never holds more than one call and no request (3 s refresh, throttled update, Shelf, search, group panel, settle, Screen Recording grant) waits forever"
    - "Within 2 s after a move, a single capture skips every item whose live bounds are not entirely inside one active display; such an item keeps its cached image, or, without one, takes it from a composite capture"
    - "The search panel appears at once (cached images or app icons) whatever the capture does, and fills in images as the refresh lands"
    - "The holzBar Shelf on macOS 26 still opens after at most about 1 s (e8eff47e, unchanged here), and its background refresh now ends within a bounded time"
    - "macOS 27 never reaches the capture queue: its branch of updateCacheWithoutChecks is unchanged"
    - "A settings file or settings sync can never turn on the debug default that simulates a hung capture"
  artifacts:
    - path: holzBar/Core/BlockingWork.swift
      provides: "run(on:timeout:fallback:_:) -> (value:, timedOut:), resume-once behind OSAllocatedUnfairLock, DispatchQueue.global().asyncAfter timer"
    - path: holzBar/Core/ItemCapturePolicy.swift
      provides: "timeout (2 s), maxAbandonedQueues (3), displayTolerance (1 pt), isOnScreen(_:displays:), Watchdog (abandoned count, hung window IDs, stop)"
    - path: holzBar/Core/CoalescedRun.swift
      provides: "one batch at a time; requests meanwhile join one re-run with the union of their elements"
    - path: holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift
      provides: "instance capture queue, bounded calls, watchdog reaction, coalesced passes, per-item single captures with the off-screen rule"
    - path: holzBar/MenuBar/Search/MenuBarSearchPanel.swift
      provides: "show() orders the panel front before the cache refresh"
    - path: Tests/HolzBarCoreTests/BlockingWorkTests.swift
      provides: "timeout tests with a semaphore-blocked queue"
    - path: Tests/HolzBarCoreTests/ItemCapturePolicyTests.swift
      provides: "watchdog state machine and on-screen geometry tests"
    - path: Tests/HolzBarCoreTests/CoalescedRunTests.swift
      provides: "single-flight and union re-run tests"
  key_links:
    - from: "MenuBarItemImageCache.onCaptureQueue(windowID:_:)"
      to: "BlockingWork.run(on:timeout:fallback:_:)"
      via: "every compositeCapture / individualCapture call, timeout ItemCapturePolicy.timeout; timedOut -> captureDidTimeOut -> Watchdog.recordTimeout -> fresh queue or stop"
    - from: "MenuBarItemImageCache.updateCacheWithoutChecks(sections:) (before macOS 27)"
      to: "CoalescedRun.run(_:operation:) -> captureAndStoreImages(for:)"
      via: "one pass at a time, union re-run"
    - from: "MenuBarItemImageCache.individualCapture(_:displays:scale:)"
      to: "ItemCapturePolicy.isOnScreen(_:displays:)"
      via: "live Bridging.getWindowBounds vs Bridging.getActiveDisplayList().map(CGDisplayBounds)"
    - from: "MenuBarSearchPanel.show(on:)"
      to: "makeKeyAndOrderFront before Task { await appState.imageCache.updateCache() }"
      via: "synchronous show, unawaited refresh"
---

# F-13 — a stuck item capture no longer wedges images, search and Shelf (chain "events", part "capture")

Branch `audit-manual/events` (worktree `scratchpad/wt2/events`), HEAD `e8eff47e`. It is based on `audit/remediation-2026-10-05`, which already contains the 66 automatic fixes, plus the "timeouts" part (F-01: `f14aed13`, `e8eff47e`). Finding text: `.planning/audit/FULL-AUDIT-2026-10-05.md`, `#### F-13`. Decision: `scratchpad/decisions/capture-queue-1.md`, **"Watchdog und Auslöser meiden (Recommended)"**.

<objective>
Close F-13 exactly as the maintainer decided (capture-queue-1, option "Watchdog und Auslöser meiden"):

- The search and the holzBar Shelf always open.
- The known trigger goes away: a single capture of a hidden item off screen, just after a move.
- If a capture hangs anyway, holzBar gives up on it after about 2 s and images keep updating. The cost is one blocked thread per hang, at most 3, then capture stops for the session with the last images kept.

Purpose: today every item-image CGWindowList call runs on one static serial queue behind a continuation that nothing can resume (`MenuBarItemImageCache.swift:65-79`). On macOS 26 one call that never returns blocks every later capture until relaunch:
- images freeze;
- the search never appears (it installs its content after `await updateCache()`);
- each 3 s refresh and throttled update leaks a suspended Task.

Output:
- a bounded variant of `BlockingWork.run` in `holzBar/Core`, unit tested;
- two small tested Core types, `ItemCapturePolicy` and `CoalescedRun`;
- a reworked `MenuBarItemImageCache` (macOS 26/14/15 path only);
- a search panel that shows first;
- a local-only debug default for the hand test.

Two local commits. No push.
</objective>

## Decisions (traceability IDs used below)

| ID | Source (capture-queue-1) | Decision |
|---|---|---|
| D-01 | note (a) | Add a resume-once timeout variant to `holzBar/Core/BlockingWork.swift`: `run(on:timeout:fallback:) -> (value, timedOut)`. The queue block and a `DispatchQueue.global().asyncAfter` timer both take the continuation out of an `OSAllocatedUnfairLock`, and only the first one resumes it. Test it in `Tests/HolzBarCoreTests/BlockingWorkTests.swift` with work blocked on a `DispatchSemaphore`: the fallback comes after the timeout, a late completion does not resume twice, and work on a fresh queue still runs. |
| D-02 | note (b) | `MenuBarItemImageCache`: replace the static capture queue with a main-actor instance queue. Every CGWindowList call goes through the helper with a ~2 s timeout. On a timeout: create a fresh serial `.userInitiated` queue, remember the hung windowID and skip it while it exists, and count abandoned queues. After 3 in one session, stop item-image capture until relaunch, keep the last images (no `releaseAllImages`) and log once at `.error`. `individualCapture` hops once per item, so the timeout applies to each call, not to the whole loop. |
| D-03 | note (c) | Coalesce: keep one in-flight capture Task. Requests during it await it and mark one re-run with the union of their sections, so the queue never holds more than one block. This ends the Task leaked every 3 s. |
| D-04 | note (d) | In the individual path, skip items whose live bounds (`Bridging.getWindowBounds`) are not entirely inside one active display (`CGGetActiveDisplayList` + `CGDisplayBounds`, same global coordinates). They keep their cached image, or come from a composite capture if they have none. |
| D-05 | note (e) | `MenuBarSearchPanel.show`: install the hosting view and order the panel front before awaiting `updateCache()`. F-84 changed the same code. |
| D-06 | note (f) | Shelf on macOS 26: F-01 step 3 ("show first") did **not** land, because event-timeouts-2 chose "Höchstens 1 s warten". So the "otherwise" branch applies: the wait is bounded to at most 1 s. `e8eff47e` already does this with the rewritten `Task(timeout: .seconds(1)) { await refresh.value }`, which returns at the timeout. `cacheFailed(for:)` stays unchanged. Verify only, no edit (the timeouts plan, risk 8, asks this chain to keep that wait). |
| D-07 | context | Keep CGWindowList (APPLE-02): no ScreenCaptureKit and no XPC capture process. The other CGWindowList call sites (`MenuBarManager.swift:337`, `MenuBarSearchModel.swift:72`, `HolzBarShelfColorManager.swift:155`, `MenuBarOverlayPanel.swift:482`) are out of scope. The macOS 27 path (early return in `updateCacheWithoutChecks`) is unchanged. |
| D-08 | note | Update the #777 row in `docs/upstream-bugs.md` and add a Fixed line to the next beta's release notes. This chain may not edit docs or release notes, so they go to `doc_updates_needed`. |
| D-09 | note | Verify with CI (build, `swift test`, SwiftLint `--strict`). Then the maintainer smoke-tests on macOS 26: move items, and within 1-2 s open the Shelf, the search and Settings › Menu Bar Layout, ideally also with a second display placed left of the built-in one (the commit 5e316dc scenario). |

Planner's choices within the decision. None widens scope, and each is cited where it is used:

| ID | Choice | Why |
|---|---|---|
| P-01 | The watchdog state, the on-screen geometry and the coalescing go into `holzBar/Core` (`ItemCapturePolicy`, `CoalescedRun`) | `swift test` does not compile `MenuBarItemImageCache`. Without them, D-02's stop rule, D-03 and D-04 would have no CI coverage. This follows the precedent of `EventBarrierPolicy`. |
| P-02 | A timed-out **composite** call counts toward the 3, but adds no window to the skip list | It covers many windows, so the hung one is unknown. Only single captures record a windowID. |
| P-03 | On-screen test with 1 pt tolerance (`displayTolerance`) | Window bounds carry sub-point values on scaled displays (5e316dc; `StatusItemWindowFrame.tolerance` is also 1). Hidden items sit thousands of points away, so the tolerance never lets one in. |
| P-04 | Off-screen items without a cached image come from **one** composite capture of all off-screen items of that individual batch. Only the missing images are adopted from it. | This keeps the call shaped like the regular composite path, which captures hidden items on every Shelf open. Items with cached images keep them, as D-04 says. |
| P-05 | After a timeout, a marker block on the abandoned queue logs at `.notice` when (and whether) the stuck call returns | It runs only after the stuck call, so normal captures pay nothing. It gives the maintainer evidence of whether "hangs" are permanent or just slow. It does not change the count (D-02 stays literal). |
| P-06 | Once capture has stopped, the 3 s refresh loop is cancelled and not restarted | Lean: no idle wake-ups that can do nothing. |
| P-07 | Local-only debug default `DebugHangsItemImageCapture` (Bool): each capture call blocks its thread forever before capturing | The watchdog is the core of the chosen option, and a real hang cannot be reproduced on demand. Without this, the hand test cannot exercise it. It follows the precedent of `DebugDropsBarrierExitEvent` (event-timeouts-1). It is never exported, imported or synced. |
| P-08 | In `MenuBarSearchPanel`, the pending-show flag and the show generation counter that F-84 added are removed. `toggle()` checks `isVisible` again. | After D-05, `show()` has no await before ordering front, so they guard nothing. |
| P-09 | The timer is a `DispatchWorkItem`, cancelled when the work wins | Avoids one no-op wake-up per call. If the SDK rejects capturing `DispatchWorkItem` in a `@Sendable` closure, drop the cancel: a fired timer finds the lock empty and does nothing. |

**Relayed request ("Können wir das mit dem signieren nicht doch anders lösen?").** Nothing in F-13 concerns code signing; this plan changes no signing, entitlement, CI or release file. The question is answered where it matters for this part: the hand test needs Screen Recording and Accessibility, and the section "Test build" below keeps both by re-signing the CI build locally with holzBar's own release certificate (the same answer as in the timeouts plan; one build of this branch serves both parts' hand tests).

## Interfaces the executor creates (exact names; bodies per the task actions)

- `BlockingWork` (holzBar/Core/BlockingWork.swift, `nonisolated enum`). Keep `run(on:_:)` unchanged and add:
  - `static func run<Value: Sendable>(on queue: DispatchQueue, timeout: Duration, fallback: Value, _ work: @escaping @Sendable () -> Value) async -> (value: Value, timedOut: Bool)`
- `ItemCapturePolicy` (holzBar/Core/ItemCapturePolicy.swift, new; `nonisolated enum`, because its geometry is called from a nonisolated capture closure):
  - `static let timeout = Duration.seconds(2)`
  - `static let maxAbandonedQueues = 3`
  - `static let displayTolerance: CGFloat = 1`
  - `static func isOnScreen(_ bounds: CGRect, displays: [CGRect]) -> Bool`
  - `struct Watchdog: Sendable` with:
    - `enum Action: Equatable, Sendable { case replaceQueue, stop }`
    - `private(set) var abandonedQueues = 0`
    - `private(set) var hungWindowIDs = Set<CGWindowID>()`
    - `var isStopped: Bool`
    - `func skips(_ windowID: CGWindowID) -> Bool`
    - `mutating func recordTimeout(windowID: CGWindowID?) -> Action`
    - `mutating func forgetWindows(notIn existing: Set<CGWindowID>)`
- `CoalescedRun<Element: Hashable & Sendable>` (holzBar/Core/CoalescedRun.swift, new). It is a `final class`, main actor by the Core default isolation. Members:
  - `private(set) var pending = Set<Element>()` (internal getter, read by the tests)
  - `var isRunning: Bool`
  - `func run(_ elements: some Sequence<Element>, operation: @escaping @MainActor (Set<Element>) async -> Void) async`
- `MenuBarItemImageCache` (private members), before macOS 27:
  - `captureQueue` (instance) and `nonisolated static func makeCaptureQueue() -> DispatchQueue`
  - `watchdog: ItemCapturePolicy.Watchdog`
  - `captureRun: CoalescedRun<MenuBarSection.Name>`
  - `onCaptureQueue(windowID:_:) async -> CaptureResult?`
  - `captureDidTimeOut(on:windowID:)`
  - `individualCapture(_:displays:scale:)` (one item, nonisolated)
  - `captureIndividually(_:scale:) async`
  - `captureMissingOffScreen(in:scale:) async`
  - `captureAndStoreImages(for:) async`
  - `CaptureResult.offScreen`
- `Defaults.Key.debugHangsItemImageCapture = "DebugHangsItemImageCapture"`: `.bool`, in `localOnlyKeys`.

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/audit/FULL-AUDIT-2026-10-05.md (sections "#### F-13", "#### F-01", "#### F-84")
@.planning/audit/remediation/events-timeouts-SUMMARY.md (what the timeouts part changed: ResumeOnce, Task(timeout:), Shelf wait)
@/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/decisions/capture-queue-1.md
@holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift (whole file, 545 lines)
@holzBar/Core/BlockingWork.swift
@Tests/HolzBarCoreTests/BlockingWorkTests.swift
@holzBar/Core/ConcurrencyHelpers.swift (ResumeOnce: the lock pattern; not reused, because the D-01 continuation is non-throwing)
@holzBar/Core/EventBarrierPolicy.swift and Tests/HolzBarCoreTests/EventBarrierPolicyTests.swift (style of a Core policy type and its tests)
@Tests/HolzBarCoreTests/TaskTimeoutTests.swift (Gate helper, timing-bound style: timeout + 400 ms)
@holzBar/MenuBar/Search/MenuBarSearchPanel.swift lines 1-185
@holzBar/MenuBar/Shelf/HolzBarShelf.swift lines 185-230 (read only: D-06)
@Shared/Bridging/Bridging.swift lines 80-140 and 270-290 (getActiveDisplayList, getWindowBounds)
@holzBar/Core/Defaults.swift lines 196-216, 255-300 and 380-395 (debug key pattern), Tests/HolzBarCoreTests/SettingsSchemaTests.swift lines 95-115 and 170-185
@Package.swift (Core is compiled with default MainActor isolation and NonisolatedNonsendingByDefault)

Callers that await the cache. Their call shape does not change, and all are bounded after this plan:
- `MenuBarSearchPanel.swift:137`
- `HolzBarShelf.swift:213/220`
- `MenuBarItemGroups.swift:283`
- `AppState.swift:194` (settle) and `AppState.swift:292` (`updateCacheWithoutChecks` when Settings is frontmost; no 1 s move skip)
- `ScreenRecordingAccess.swift:42`
</context>

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1: Tracer — every item capture call is bounded end to end (helper, watchdog, cache)</name>
  <files>holzBar/Core/BlockingWork.swift, Tests/HolzBarCoreTests/BlockingWorkTests.swift, holzBar/Core/ItemCapturePolicy.swift, Tests/HolzBarCoreTests/ItemCapturePolicyTests.swift, holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift</files>
  <read_first>holzBar/Core/BlockingWork.swift, Tests/HolzBarCoreTests/BlockingWorkTests.swift, Tests/HolzBarCoreTests/TaskTimeoutTests.swift, holzBar/Core/EventBarrierPolicy.swift, holzBar/Core/StatusItemWindowFrame.swift (tolerance doc style), holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift</read_first>
  <behavior>
    BlockingWorkTests (keep the three existing tests; add these, @MainActor suite as now):
    - "Work that finishes in time returns its value": run(on: queue, timeout: .seconds(2), fallback: -1) { 7 } gives value 7, timedOut false.
    - "Work that blocks past the timeout returns the fallback on time": the work waits on a DispatchSemaphore(value: 0); run(timeout: .milliseconds(100), fallback: -1) gives value -1, timedOut true, and the elapsed ContinuousClock time is under 100 ms + 400 ms. A defer signals the semaphore, so the test leaves no blocked thread.
    - "A late completion does not resume the caller twice": same setup. After the fallback, signal the semaphore, then await the plain BlockingWork.run(on: queue) { 2 } on the same serial queue. It returns 2 only after the late work has finished and tried to resume. A double resume would trap the test process.
    - "Work on a fresh queue runs while the old one is blocked": block queue A past a 100 ms timeout. Then run(on: freshQueueB, timeout: .seconds(2), fallback: -1) { 5 } gives value 5, timedOut false. A defer releases A.
    ItemCapturePolicyTests (new; plain @Suite struct, like EventBarrierPolicyTests):
    - "Two timeouts replace the queue, the third stops capture": recordTimeout returns .replaceQueue, .replaceQueue, .stop. isStopped is false, false, true, and abandonedQueues is 1, 2, 3.
    - "A timed-out single capture skips its window": recordTimeout(windowID: 42) makes skips(42) true and skips(43) false.
    - "A timed-out composite capture counts but skips no window" (P-02): recordTimeout(windowID: nil) increases abandonedQueues, and hungWindowIDs stays empty.
    - "Windows that are gone are forgotten": with 42 and 43 hung, forgetWindows(notIn: [43, 99]) leaves only 43.
    - isOnScreen, parameterised or as separate tests, with displays [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 2560, height: 1440)]:
      - an item at x 1400, y 0, 24 × 24 is true;
      - an item overshooting the right edge of display 1 by 0.5 pt but within display 2's span (x 1488.5, width 24) is false, because it straddles two displays;
      - an item overshooting the outer left edge by 0.5 pt (x -0.5) is true (P-03 tolerance);
      - an item partly off the left edge (x -10, width 24) is false;
      - a hidden item far left (x -9000) is false;
      - an empty displays list is false;
      - zero-width bounds are false;
      - an item inside display 2 (x 3000) is true.
  </behavior>
  <action>
    Implements D-01 and the D-02 core (P-01, P-02, P-03, P-05, P-09). The tracer wires the existing calls, unchanged in shape, through the new bound. Per-item hops and the off-screen rule come in Task 2.

    RED first:
    - Write the new tests in both test files.
    - Run swift test --filter "BlockingWorkTests|ItemCapturePolicyTests". It must fail to compile, because the overload and the type do not exist yet. Record this for the SUMMARY.

    holzBar/Core/BlockingWork.swift (D-01):
    - Add import os.lock (Core already uses OSAllocatedUnfairLock in ConcurrencyHelpers.swift).
    - Add the overload run(on:timeout:fallback:_:) next to the existing run(on:_:), with the signature from "Interfaces".
    - Body, inside withCheckedContinuation:
      - Keep the continuation in an OSAllocatedUnfairLock whose state is an optional CheckedContinuation of (value: Value, timedOut: Bool).
      - Create a DispatchWorkItem timer that takes the continuation out of the lock (read it, set nil, inside withLock) and resumes it with (fallback, true).
      - Enqueue the work with queue.async. The block runs work(), cancels the timer (P-09), takes the continuation out of the lock the same way, and resumes it with (value, false) if it is still there.
      - Schedule the timer with DispatchQueue.global().asyncAfter at DispatchTime.now() plus the timeout. Convert the Duration once from its components (seconds × 1e9 + attoseconds / 1e9, as nanoseconds).
    - Whichever racer comes first resumes; the other finds nil and does nothing. The work still runs to its end on its queue: a blocking call cannot be cancelled.
    - Doc comment, in the file's prose style:
      - this is the bounded variant;
      - on a timeout the caller gets the fallback at once, but the queue's thread stays blocked until the work returns;
      - a caller that must not queue behind the stuck work has to send later work to another queue (the item image cache does);
      - the first racer wins.
    - Do not change the existing overload or its callers (MenuBarItemServiceConnection.swift:99 and :120).

    holzBar/Core/ItemCapturePolicy.swift (new; file header per .swiftlint.yml; import CoreGraphics; nonisolated enum):
    - Implement the members listed in "Interfaces", each with a short doc comment.
    - Type doc: "Bounds the blocking window captures of item images before macOS 27 (F-13)."
    - isOnScreen:
      - Return false when bounds.isEmpty or bounds.width <= 0.
      - Otherwise return true if any display rect, expanded by displayTolerance on every side (insetBy with negative dx/dy), contains the bounds.
      - Doc: this is the window list's global coordinate space (origin at the top left of the primary display, as CGDisplayBounds and Bridging.getWindowBounds report it).
    - Watchdog:
      - recordTimeout increments abandonedQueues and inserts a non-nil windowID into hungWindowIDs. It returns .stop once abandonedQueues reaches maxAbandonedQueues, otherwise .replaceQueue.
      - isStopped is abandonedQueues >= maxAbandonedQueues.
      - forgetWindows(notIn:) intersects hungWindowIDs with the given set.
      - skips(_:) is set membership.

    holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift (D-02 core; macOS 26/14/15 path only):
    1. Queue.
       - Replace the type-level capture queue property with an @ObservationIgnored private instance var captureQueue, initialised from a new private nonisolated static func makeCaptureQueue() that returns DispatchQueue(label: "com.holzcloud.holzBar.ImageCapture", qos: .userInitiated).
       - Move the existing long doc comment onto the instance property and keep its history.
       - Append a paragraph: each call is now given up after ItemCapturePolicy.timeout. A queue whose call did not return is abandoned with its thread, and later calls go to a fresh queue. After ItemCapturePolicy.maxAbandonedQueues, capture stops for the session (F-13).
    2. State.
       - Add @ObservationIgnored private var watchdog = ItemCapturePolicy.Watchdog().
       - Add a private computed isCaptureStopped that returns watchdog.isStopped.
    3. onCaptureQueue.
       - Rewrite it as a main-actor private func onCaptureQueue(windowID: CGWindowID? = nil, _ work: @escaping @Sendable () -> CaptureResult) async -> CaptureResult?.
       - When the watchdog has stopped, return nil without enqueuing.
       - Otherwise take the current queue into a local constant and await BlockingWork.run(on: that queue, timeout: ItemCapturePolicy.timeout, fallback: nil) with a closure that returns work() as an optional.
       - When timedOut is true, call captureDidTimeOut(on: thatQueue, windowID: windowID) and return nil; otherwise return the value.
       - Doc: nil means no new images; the cached ones stay.
    4. Add private func captureDidTimeOut(on queue: DispatchQueue, windowID: CGWindowID?).
       - P-05: record ContinuousClock.now. Enqueue a marker block on the abandoned queue that captures the logger and that instant. Being serial, the queue runs it only after the stuck call. It logs at .notice "An abandoned item image capture returned after \(seconds, privacy: .public) s".
       - Then switch on watchdog.recordTimeout(windowID:).
       - .replaceQueue: set captureQueue to makeCaptureQueue() and log at .warning "Item image capture did not return within 2 s; later captures use a new queue (\(watchdog.abandonedQueues, privacy: .public) of \(ItemCapturePolicy.maxAbandonedQueues, privacy: .public) abandoned)".
       - .stop: cancel and clear refreshTask (P-06) and log exactly once at .error "Item image capture stopped until holzBar is relaunched: \(ItemCapturePolicy.maxAbandonedQueues, privacy: .public) captures did not return; the last images stay". .stop happens only once, because no call runs after it.
       - Logs carry only numbers. Never log the windowID or the item with .public.
    5. Callers in captureImages(of:scale:appState:).
       - Both existing composite call sites and both individual call sites go through onCaptureQueue. A nil composite result returns an empty CaptureResult(): no new images, cached ones stay.
       - A nil individual result returns the composite images merged as now, or an empty result in the after-move branch.
       - Keep the individual capture as one call over all items for now (windowID nil). Task 2 splits it per item.
    6. Skip list.
       - In captureImages(for:scale:appState:), filter the section's items with !watchdog.skips($0.windowID) before capturing.
       - In updateCacheWithoutChecks, after the macOS 27 branch and before the section loop:
         - add guard !isCaptureStopped else { return };
         - call watchdog.forgetWindows(notIn: Set(appState.itemManager.itemCache.managedItems.map(\.windowID))).
    7. Keep the last images once stopped (D-02).
       - In releaseAllImages(), return early when isCaptureStopped, with a one-line comment: once capture has stopped, these images are all there is until relaunch.
       - In refreshNeededDidChange(_:), do not start the loop when isCaptureStopped (P-06).
    8. Leave the macOS 27 branch, compositeCapture's body, cacheFailed(for:), prune(keeping:) and updateCache(sections:) / updateCache() unchanged.

    GREEN: the filtered swift test passes; then appcheck.
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swifttest-retry.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events --filter "BlockingWorkTests|ItemCapturePolicyTests" ; zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events f13-t1 ; grep -c "private var captureQueue" /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events/holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift ; grep -v '^ *//' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events/holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift | grep -c "BlockingWork.run(on:"</automated>
  </verify>
  <done>
    - RED was observed (a compile failure) and recorded. The filtered run passes, with "SWIFT TEST EXIT: 0".
    - appcheck prints "ERRORS: 0" (the existing CGWindowList deprecation warning is fine).
    - The grep for the instance queue prints 1, and the BlockingWork.run(on: grep prints 1: onCaptureQueue is the only path to the queue.
    - The macOS 27 branch of updateCacheWithoutChecks is byte-identical to e8eff47e (check with git diff).
    - Nothing is committed yet.
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: One capture pass at a time, per-item single captures, and the off-screen rule</name>
  <files>holzBar/Core/CoalescedRun.swift, Tests/HolzBarCoreTests/CoalescedRunTests.swift, Shared/Bridging/Bridging.swift, holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift</files>
  <read_first>holzBar/Core/CoalescedRun.swift does not exist yet; read holzBar/Core/Debouncer.swift and Tests/HolzBarCoreTests/DebouncerTests.swift (main-actor Core type plus test style), Tests/HolzBarCoreTests/TaskTimeoutTests.swift (Gate), Shared/Bridging/Bridging.swift lines 80-140, holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift (as left by Task 1)</read_first>
  <behavior>
    CoalescedRunTests (new; @MainActor @Suite). A recorder class collects batches and the maximum number of operations running at once:
    - "Requests while a batch runs share one re-run":
      - Start run([1]). Its operation, for batch [1], signals "started" and then waits on a gate.
      - Once started, launch Tasks calling run([2]) and run([3, 2]).
      - Yield until pending == [2, 3] (bounded loop, at most 1000 yields, so a bug fails instead of hanging). Then open the gate.
      - Await all three. The batches are exactly [[1], [2, 3]], the maximum concurrency is 1, and isRunning is false afterwards.
    - "Each waiter returns only after its elements ran": in the same setup, when the run([2]) task's value returns, the recorder already holds [2, 3].
    - "A request after the run ended starts a new run": await run([1]), then await run([2]). The batches are [[1], [2]].
    - "An empty request runs nothing": await run([]). No batch, and isRunning is false.
  </behavior>
  <action>
    Implements D-03, D-04 and the per-item hop of D-02 (P-01, P-04).

    RED first: write CoalescedRunTests and run swift test --filter CoalescedRunTests (it fails to compile). Record this.

    holzBar/Core/CoalescedRun.swift (new; file header; import nothing beyond what the compiler needs):
    - A final class CoalescedRun<Element: Hashable & Sendable>, main actor through Core's default isolation.
    - Doc: runs an operation for batches of elements, one batch at a time. A request while a batch runs adds its elements to the next batch and waits until the run ends. So at most one batch runs and at most one waits, however many requests arrive. The operation of the call that starts a run performs every batch of that run; callers pass the same operation.
    - State:
      - private(set) var pending (Set);
      - a private optional Task<Void, Never> named task;
      - isRunning returns task != nil.
    - run(_:operation:):
      - Form the union of the elements into pending.
      - If a task exists, await its value and return.
      - Otherwise, if pending is empty, return.
      - Otherwise create a Task (it inherits the main actor). While pending is not empty, it takes pending as the batch, clears pending and awaits operation(batch). After the loop it sets task to nil, in the same synchronous step as the final emptiness check, so no request can slip between them.
      - Store the task, then await its value.
    - If the compiler rejects the default value of a stored property in the image cache (an isolated initialiser), mark init() nonisolated.
    - If region-isolation diagnostics appear for the operation parameter, add @Sendable to its type.

    Shared/Bridging/Bridging.swift:
    - Remove private from static func getActiveDisplayList(), and give it a one-line doc comment ("Returns the identifiers of the active displays.").
    - No other change. The XPC service also compiles this file, so servicecheck must stay green.

    holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift:
    1. Coalescing (D-03).
       - Add @ObservationIgnored private let captureRun = CoalescedRun<MenuBarSection.Name>().
       - Move the body of updateCacheWithoutChecks after the macOS 27 branch into a new private func captureAndStoreImages(for sections: Set<MenuBarSection.Name>) async. The moved part: the displayID/screen guard, the scale, forgetWindows, the section loop, merge and prune.
       - At the start of captureAndStoreImages, re-check the guards: appState, Screen Recording permission, not paused, not stopped. A re-run can run after these changed.
       - Iterate the sections in a stable order: MenuBarSection.Name.allCases filtered by membership in the batch.
       - updateCacheWithoutChecks keeps its early guards and the macOS 27 branch unchanged. After them it does guard !isCaptureStopped, then awaits captureRun.run(sections) with an operation that weakly captures self and awaits captureAndStoreImages(for: batch).
       - Comment: one pass at a time; a request meanwhile joins it and adds its sections to one re-run, so the capture queue never holds more than one call and no request waits on a stuck one for longer than the watchdog allows (F-13).
       - requestUpdate(), the 3 s loop and every caller stay as they are: their Tasks now end when the run ends.
    2. Off-screen rule and per-item hop (D-04, D-02).
       - Add var offScreen = [MenuBarItem]() to CaptureResult, documented as "items a single capture skipped because they are not entirely on one display".
       - Replace the loop-based individualCapture with a nonisolated func individualCapture(_ item: MenuBarItem, displays: [CGRect], scale: CGFloat) -> CaptureResult for ONE item:
         - Read the live bounds with Bridging.getWindowBounds (keep the existing comment on why live bounds). Missing bounds or zero width puts the item in excluded.
         - If ItemCapturePolicy.isOnScreen(bounds, displays: displays) is false, put the item in offScreen and return without capturing.
         - Otherwise capture exactly as today: transparent or nil goes to excluded; the scale is derived and checked as today.
         - Doc: a single capture of an item that is not entirely on one display can block forever on macOS 26 (see captureQueue). Hidden items sit off screen, left of the menu bar, while their section is hidden.
       - Add a private func captureIndividually(_ items: [MenuBarItem], scale: CGFloat) async -> CaptureResult on the main actor:
         - Compute displays once as Bridging.getActiveDisplayList().map(CGDisplayBounds).
         - Then for each item, await onCaptureQueue(windowID: item.windowID) { individualCapture(item, displays:, scale:) }, so each call is bounded on its own.
         - A nil result puts the item in excluded and breaks out of the loop when isCaptureStopped.
         - Merge each result's images, excluded and offScreen into the batch result.
       - Add a private func captureMissingOffScreen(in result: CaptureResult, scale: CGFloat) async -> CaptureResult (P-04):
         - missing = result.offScreen whose tag has no entry in images (the cache).
         - If missing is empty, return result unchanged: those items keep their cached images.
         - Otherwise await onCaptureQueue() with compositeCapture(result.offScreen, scale:) (all off-screen items of this batch, windowID nil).
         - Adopt only the missing items' images from it. A missing item without an image, or every missing item when the call returned nil, goes to excluded.
       - captureImages(of:scale:appState:):
         - After a move (2 s): await captureIndividually(items), then return await captureMissingOffScreen(in:).
         - Composite path: as now through onCaptureQueue; nil returns an empty result. When items were excluded, keep the existing notice log, then await captureIndividually(compositeResult.excluded).
         - Do NOT re-capture off-screen excluded items with a composite (the composite just failed for them). Add to excluded those offScreen items that have no cached image, so the existing error log names them.
         - Merge the composite images as now.
       - Log at .debug "Kept the cached images of \(count, privacy: .public) items off screen" when a batch skipped any.
    3. Remove the now-unused whole-loop individual capture.
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swifttest-retry.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events --filter "CoalescedRunTests|ItemCapturePolicyTests|BlockingWorkTests" ; zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events f13-t2 ; zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/servicecheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events ; grep -c "captureRun.run(" /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events/holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift ; grep -c "ItemCapturePolicy.isOnScreen(" /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events/holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift</automated>
  </verify>
  <done>
    - RED was recorded, and the three suites pass.
    - appcheck prints "ERRORS: 0", and servicecheck prints "SERVICE EXIT: 0".
    - The two greps each print 1.
    - individualCapture takes one item, and captureIndividually awaits onCaptureQueue inside its loop.
    - The macOS 27 branch is still byte-identical to e8eff47e.
    - Nothing is committed yet.
  </done>
</task>

<task type="auto">
  <name>Task 3: Debug default, commit A; search shows first, Shelf verified, commit B</name>
  <files>holzBar/Core/Defaults.swift, Tests/HolzBarCoreTests/SettingsSchemaTests.swift, holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift, holzBar/MenuBar/Search/MenuBarSearchPanel.swift</files>
  <read_first>holzBar/Core/Defaults.swift lines 196-216, 255-300 and 380-395; Tests/HolzBarCoreTests/SettingsSchemaTests.swift lines 95-115 and 170-185; holzBar/MenuBar/Search/MenuBarSearchPanel.swift lines 1-185; holzBar/MenuBar/Shelf/HolzBarShelf.swift lines 185-230</read_first>
  <action>
    Part A: debug default (P-07), then commit A.
    1. holzBar/Core/Defaults.swift.
       - Under "// MARK: Debugging", below debugDropsBarrierExitEvent, add case debugHangsItemImageCapture = "DebugHangsItemImageCapture".
       - Doc comment in the same style: "Blocks every item image capture before macOS 27 forever, so each one times out; shows that holzBar recovers from a stuck capture and stops capturing after three. Hidden: `defaults write com.holzcloud.holzBar DebugHangsItemImageCapture -bool true`. Never exported, imported or synced."
       - Add the key to the .bool group of settingsKind, next to .debugDropsBarrierExitEvent.
       - Add it to localOnlyKeys, and keep that set's doc comment ("Debug defaults stay on this Mac too").
    2. Tests/HolzBarCoreTests/SettingsSchemaTests.swift.
       - Add the test "A settings file cannot hang item captures", mirroring settingsFileCannotDropBarrierExits: localOnlyKeys contains the key; importableKinds["DebugHangsItemImageCapture"] is nil; validatedSettings ignores it and accepts "ShowOnHover".
       - Pin the raw value in the persisted-names test (next to the DebugDropsBarrierExitEvent line).
    3. MenuBarItemImageCache.onCaptureQueue.
       - Read Defaults.bool(forKey: .debugHangsItemImageCapture) once per call on the main actor, before enqueuing.
       - When it is true, the closure handed to BlockingWork first waits on a fresh DispatchSemaphore(value: 0) that nothing signals, then runs the work.
       - One-line comment: debug only; this simulates a capture that never returns.
    4. Run every gate in "Gates" (full swift test, appcheck, servicecheck, SwiftLint, privacy and strings checks, former name, diff scope).
       - All must pass. Fix any finding.
       - If a gate fails and cannot be fixed: run git -C <worktree> checkout -- . and git -C <worktree> clean -fd -- holzBar Tests Shared. Leave the untracked plan files alone. Report fix-failed with the reason and stop.
    5. Commit A.
       - git -C <worktree> add the Core, test, Bridging and cache files: everything in files_modified except MenuBarSearchPanel.swift.
       - Then git -C <worktree> commit with message A from "Commit messages".
       - Do not change git config. Do not push.

    Part B: search shows first (D-05, P-08), the Shelf is verified (D-06), then commit B.
    6. holzBar/MenuBar/Search/MenuBarSearchPanel.swift, show(on:).
       - Keep the appState and screen guards, and setting isSearchPresented first with its comment.
       - Then, synchronously and in this order:
         - create MenuBarSearchHostingView;
         - set its frame size from intrinsicContentSize (the content is a fixed 600 × 400, so the size does not depend on images);
         - setFrame, assign contentView;
         - compute topLeft as today and cascadeTopLeft;
         - makeKeyAndOrderFront(nil);
         - start mouseDownMonitor and keyDownMonitor.
       - Only after that, start Task { await appState.imageCache.updateCache() } and do not await it.
       - Keep the existing comment on why that task is not cancelled when the panel closes (macOS 27 waits), and add: the panel shows the cached images, or the items' app icons, at once, and the view observes the cache, so new images appear as the refresh lands; a stuck capture can no longer keep the search from opening (F-13).
       - Remove the stored show generation counter and the pending-show flag with their doc comments, since nothing awaits before ordering front (P-08).
       - toggle() becomes: if isVisible, close(); otherwise show().
       - close() loses the two lines that touched those properties; the rest of close() is unchanged.
    7. D-06, verify only.
       - git -C <worktree> diff --quiet e8eff47e -- holzBar/MenuBar/Shelf/HolzBarShelf.swift must succeed.
       - HolzBarShelf.swift must still contain "Task(timeout: .seconds(1))" and "await refresh.value" once each.
       - Do not edit HolzBarShelf.swift or cacheFailed(for:).
    8. Run every gate again.
    9. Write .planning/audit/remediation/events-capture-SUMMARY.md (see "Output").
    10. Commit B.
        - git -C <worktree> add holzBar/MenuBar/Search/MenuBarSearchPanel.swift and the SUMMARY, as the timeouts part did with its summary.
        - Then commit with message B.
        - Leave the untracked PLAN files untracked.
  </action>
  <verify>
    <automated>zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/swifttest-retry.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events ; zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events f13-t3 ; git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events diff --quiet e8eff47e -- holzBar/MenuBar/Shelf/HolzBarShelf.swift && echo "SHELF UNCHANGED" ; awk '/func show\(on screen/{f=1} f&&/makeKeyAndOrderFront/{print "front:" NR} f&&/imageCache.updateCache\(\)/{print "update:" NR; exit}' /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events/holzBar/MenuBar/Search/MenuBarSearchPanel.swift ; git -C /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/events log --oneline e8eff47e..HEAD</automated>
  </verify>
  <done>
    - The full swift test passes ("SWIFT TEST EXIT: 0"), and appcheck prints "ERRORS: 0".
    - "SHELF UNCHANGED" is printed.
    - The awk prints "front:" with a smaller line number than "update:".
    - Two commits follow e8eff47e: A (images) and B (search).
    - Every gate passes before each commit. git status shows only the untracked PLAN files.
  </done>
</task>

</tasks>

## How each part of F-13's failure scenario is closed

| Failure (F-13) | Closed by |
|---|---|
| A single capture of a hidden, off-screen item within 2 s of a move (or for composite-excluded items, or from Settings via `updateCacheWithoutChecks` without the 1 s skip) never returns | D-04: such items are not captured singly at all. They keep their cached image, or come from a composite (Task 2). |
| No item image updates until relaunch | D-01/D-02: the waiter resumes after 2 s, later calls go to a fresh queue, and the hung window is skipped while it exists. The worst case is 3 hangs, then stop with the last images kept (stale images, never none, never a frozen queue). |
| The search opens empty or not at all | D-05: the panel is shown before the refresh starts (Task 3). |
| The Shelf no longer opens | D-06: the 1 s bound from `e8eff47e` (verified). The refresh behind it now also ends, through D-02 and D-03. |
| A suspended Task leaks every 3 s while a panel is shown | D-03: one run at a time; every request joins it, and the run is bounded by the per-call timeout. P-06: after a stop the 3 s loop ends. |
| Other waiters (`MenuBarItemGroups:283`, `AppState:194`, `ScreenRecordingAccess:42`) | Same path. Their awaits now end after at most one pass plus one re-run, each call bounded. |

## Commit messages

A (after Task 3, Part A):
```
fix(images): resolve F-13 — give up stuck item captures and run one at a time

The maintainer chose the watchdog together with avoiding the known trigger. All
item captures ran on one static serial queue behind a continuation nothing could
resume, so one capture that never returned on macOS 26 froze every later one, and
a Task leaked every 3 s. Each call now gives up after 2 s on a fresh queue and skips
the hung window; after three stuck queues capture stops until relaunch, keeping the
last images. One pass runs at a time, single captures skip items not entirely on
one display, and a local-only default simulates a hang for testing.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

B (after Task 3, Part B):
```
fix(search): resolve F-13 — show the search panel before the image refresh

The maintainer chose that search and Shelf always open. The search panel installed
its content and ordered front only after awaiting the image cache, so a stuck
capture kept it from appearing. It now shows at once with the cached images or app
icons and the refresh fills them in. Nothing awaits before the show any more, so
F-84's pending flag and show counter are gone. The Shelf keeps its 1 s wait.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji
```

## Gates (run from the worktree before each commit; all must pass)

`S=/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad`, `W=$S/wt2/events`. These are the commands the timeouts part used successfully.

1. `zsh $S/swifttest-retry.sh $W`: "SWIFT TEST EXIT: 0", and every suite passes. The wrapper retries the known "plugin for module 'TestingMacros' not found" transient. Baseline after the timeouts part: 280 + 136 + 6 tests. Expect about 15 more.
2. `zsh $S/appcheck.sh $W <label>`: "ERRORS: 0". This is a SIL type-check of the whole app module, with target macOS 14.0 and the app's Swift settings. The host has no Xcode, so it is the only local check of the app target.
3. `zsh $S/servicecheck.sh $W`: "SERVICE EXIT: 0". It matters here because `Shared/Bridging/Bridging.swift` changes.
4. `cd $W && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools $S/swiftlint/swiftlint lint --strict --quiet`: no output, exit 0. Watch for these opt-in rules:
   - `force_unwrapping`;
   - `multiline_arguments`;
   - `trailing_comma` (mandatory);
   - `file_header` on the two new Core files.
5. `cd $W && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/strings-check.py`: all pass, and the string count is unchanged (369). Every new log interpolation names its privacy. Only numbers are `.public`.
6. Former name: `cd $W && git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'` prints nothing (exit 1).
7. `git -C $W diff --stat e8eff47e` touches only the files in `files_modified` (plus the SUMMARY in commit B). `HolzBarShelf.swift`, `ScreenCapture.swift` (D-07: CGWindowList stays), the macOS 27 files, docs, README, SECURITY.md and release notes are untouched.

CI (build on the `xcode-27` image, `swift test` on macos-14/15/26, the SwiftLint image) runs after the orchestrator pushes the combined remediation branch. This chain does not push.

## Tests added

- `Tests/HolzBarCoreTests/BlockingWorkTests.swift`: 4 new tests. They cover the in-time value, the fallback on time with a semaphore-blocked queue, no double resume on a late completion, and a fresh queue that runs while the old one is blocked. The 3 existing tests stay.
- `Tests/HolzBarCoreTests/ItemCapturePolicyTests.swift` (new): about 6 tests, the geometry ones parameterised. They cover the stop after 3, the skip list, composite timeouts, forgetting gone windows, and on-screen geometry: one display, two displays, the tolerance, off the left edge, far left, no displays, zero width.
- `Tests/HolzBarCoreTests/CoalescedRunTests.swift` (new): 4 tests. They cover the union re-run, waiter ordering, a fresh run after the end, and an empty request.
- `Tests/HolzBarCoreTests/SettingsSchemaTests.swift`: the debug key is local-only and cannot be imported or synced, and its raw value is pinned.
- Not unit-testable here: the cache's wiring (it is not compiled by `swift test`), real CGWindowList behaviour, and the search panel. These are covered by appcheck, the greps above, CI and the maintainer's hand test.

## Risks (macOS 26 and 27; 14/15 must keep compiling)

1. **macOS 26: the trigger is inferred, not reproduced.** The off-screen rule removes the case the code comment and 5e316dc document. Unknown causes are left to the watchdog. If the hand test logs "did not return within 2 s" without the debug default, that is real evidence. Note the count and the "returned after … s" notices (P-05).
2. **macOS 26: different captures in normal use (D-04).**
   - For about 2 s after a move, hidden items show their previous images, so an icon that changed during the move updates one refresh later (at most about 3 s while a view is open).
   - An off-screen item that the composite excludes (for example a transparent crop) gets no single capture any more. If it has no cached image, the Shelf and search show its app icon instead.
   - If the hand test shows hidden-section items without their picture that had one before, this is the cause.
3. **macOS 26: multiple displays.**
   - "Entirely inside one active display" uses global coordinates. A display left of the menu bar's display does not make hidden items look on screen: they sit about 10,000 pt left (`ControlItem.swift:62`), farther than any display arrangement reaches.
   - An item straddling two displays counts as off screen, and keeps its cached image.
   - The 5e316dc scenario (built-in display left of the external one, negative coordinates) is part of the hand test.
4. **macOS 26: a hang that holds a process-wide lock.** If a stuck `SLSWindowListCreateImageFromArrayProxying` call blocks every CGWindowList call in the process:
   - fresh queues hang too, and capture stops after about 6 s (3 × 2 s);
   - the main-thread on-screen captures outside this queue could block the main thread (D-07 keeps them out of scope). Since D-05, the search panel runs its colour capture (`MenuBarSearchModel.swift:72`) even while an item capture hangs; before, the search simply never opened. The Shelf has done this since `e8eff47e`.
   - The sample in 5e316dc showed ten threads inside the call at once, so it does not look serialised. The hand test with the debug default cannot show this (it blocks before the system call), so a real hang remains the only proof.
5. **macOS 26: a false stop.** A capture that is slow but returns after more than 2 s still counts toward the 3 (D-02 counts abandoned queues per session, by decision). Three such calls in one session stop capture until relaunch. Mitigations:
   - captures are skipped while the Mac sleeps or is locked, and resume only after the bar has settled;
   - 2 s is about 100 times a normal call;
   - the P-05 notice shows whether abandoned calls come back. If they do, the maintainer can decide to count only queues that are still stuck.
6. **macOS 26: images after a stop.** If the stop happens while no images are cached (the first open more than 60 s after the last view closed), the Shelf shows "Unable to display menu bar items" for the rest of the session (`cacheFailed(for:)` is unchanged, D-06), and the search and Layout show app icons. Relaunching recovers.
7. **macOS 26: a waiter can wait one re-run longer.** A request that joins a running pass waits until the run ends, including the re-run it shares with later requests. Normal passes take tens of milliseconds, the Shelf's wait is bounded at 1 s, and the search does not wait. Low.
8. **macOS 27:** the capture queue, the watchdog and the coalescing sit after the macOS 27 early return, which is unchanged. The only change on macOS 27 is D-05: the search appears before `captureActiveMenuBar` and `photographMissing` (which can take seconds the first time). `photographMissing` posts no events (`ItemImageStore27.swift:307-345`), so the panel's click-outside monitor is not triggered. Check this by hand once: the search stays open while items are photographed.
9. **macOS 14/15:** they use the same (non-27) capture path, so D-02 to D-04 apply there too. No new API:
   - `OSAllocatedUnfairLock` needs macOS 13;
   - `CGGetActiveDisplayList`, `CGDisplayBounds` and `DispatchWorkItem` are old;
   - opaque `some Sequence<Element>` parameters need no runtime availability.
   appcheck compiles for macOS 14.0, and CI runs `swift test` on macos-14 and macos-15.
10. **Threads:** each hang keeps one thread blocked until quit, at most 3 (about 512 KB of stack each), as the decision accepts. The debug default deliberately causes exactly that.
11. **Merge coordination with other chains:**
    - `BlockingWork.swift`: F-12's fix (local fallback lookups, `MenuBarItemServiceConnection`) and a later F-37 may reuse or edit it. This plan only adds an overload.
    - `MenuBarSearchPanel.show`: F-07's defence in depth (`sharingType = .none`) touches the same type.
    - `updateCacheWithoutChecks`' macOS 27 branch: F-46 and F-51 may edit it. This plan leaves that branch byte-identical, but moves the code after it into `captureAndStoreImages`.
    - `Defaults.swift`'s `.bool` group and `localOnlyKeys`: textual conflicts with other chains that add keys are trivial.
    - `Bridging.getActiveDisplayList` only loses `private`.

## Maintainer hand test (after CI; macOS 26.7.1)

### Test build (answer to "Können wir das mit dem signieren nicht doch anders lösen?")

Yes, and nothing in the repository or CI has to change for it. This test needs **Screen Recording** (item images) and **Accessibility** (moves). An ad hoc CI build is a different app to macOS, which would mean granting both twice: to the test build, and again to the release.

Instead, re-sign the CI build of this branch locally with holzBar's own release certificate, in a temporary keychain that is deleted right afterwards. The test build then has the release's designated requirement, `identifier "com.holzcloud.holzBar" and certificate leaf = H"c06b72cc76bcfc1c57a00ba5c6bcd59e2a4e7e7e"`, so macOS keeps both permissions, for the test build and for the release.

The exact commands are in `.planning/audit/remediation/events-timeouts-PLAN.md`, section "Getting a test build without granting permissions again":
1. Download the artifact `holzBar-app`, restore the x bits and remove quarantine.
2. Create a temporary keychain with a random password and import `holzbar-signing.p12`.
3. Sign inside out with `--options runtime --preserve-metadata=identifier,entitlements,flags,runtime`, then check `codesign -d -r-`.
4. `security delete-keychain` and delete the `.p12`.

One such build of this branch serves both the timeouts and the capture hand tests. Afterwards:
- quit the test build;
- `open /Applications/holzBar.app`;
- `rm -rf ~/holzBar-test`.

Never put the key into the login keychain or the repository.

### Steps (each with the expected result)

Normal path (D-04, D-05, D-09):
1. Settings › Menu Bar Layout. Every section shows its item images.
2. Drag 2-3 items between Visible, Hidden and Always Hidden. Within 1-2 s of each drop:
   - open the Shelf (click the holzBar icon); it opens within about 1 s, with images;
   - open the search (hotkey); it appears at once;
   - switch back to Menu Bar Layout.
   No beachball. Within about 3 s the images match the new layout.
3. Repeat step 2 five times quickly. holzBar stays responsive, and images keep updating.
4. If a second display is available: in System Settings › Displays › Arrange, place it left of the built-in display (the 5e316dc scenario). Repeat step 2 with the active menu bar on each display. Images stay at the right size and update, and nothing freezes.
5. Close every holzBar view, wait over 60 s, then open the search. The panel appears at once; for a moment some rows may show app icons, then the pictures appear.
6. Check the log: `log show --last 15m --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "MenuBarItemImageCache"' | grep -E "did not return|abandoned|stopped"`. It should print nothing. If it prints lines, report them: that is real evidence of hangs (Risks 1 and 5).

Watchdog path (P-07; D-02):
7. Open the Shelf once, so images are cached, and close it. In Terminal: `defaults write com.holzcloud.holzBar DebugHangsItemImageCapture -bool true`. Within 60 s:
   - the Shelf opens within about 1 s, with the last images;
   - the search appears at once, with images;
   - keep the search open for about 10 s.
8. The log command from step 6 shows two warnings ("did not return within 2 s … 1 of 3", "2 of 3") and exactly one error ("Item image capture stopped until holzBar is relaunched"). No beachball at any point.
9. Close every view, wait over 60 s, and open the Shelf. It still shows the last images, not "Unable to display menu bar items". Menu Bar Layout shows images, and moving an item still works.
10. `defaults delete com.holzcloud.holzBar DebugHangsItemImageCapture`, then quit and relaunch holzBar. Capture stays stopped until relaunch by design. After relaunch, steps 1-2 work normally again.

macOS 27 (if available):
11. Open the search. It appears at once, and stays open while missing items are photographed. The Shelf behaves as before.

## doc_updates_needed (not done by this chain: docs/, README, SECURITY.md and release notes are out of bounds)

- `docs/upstream-bugs.md:22`, row "Main thread hangs in screen capture" (#777). The status could read: "Captures run on their own queue (`macos-26` base). A capture that does not return is given up after 2 s, later captures continue on a new queue, and single captures skip items off screen (F-13)".
- `docs/release-notes/v0.0.7-beta2.md` (to be written with the beta), under Fixed:
  - "On macOS 26, an item picture that cannot be captured no longer stops all item pictures from updating, or keeps the search and the holzBar Shelf from opening, until holzBar is quit."
  - "The search opens at once and fills in item pictures as they arrive."
- Optional, `docs/build-and-troubleshooting.md`: mention the hidden `DebugHangsItemImageCapture` default next to `DebugDropsBarrierExitEvent`. The existing debug defaults are not documented either, so this can be skipped.

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| holzBar → window server (CGWindowList) | captures other apps' item windows; a call can block forever on macOS 26 |
| defaults domain → holzBar | any process of the user, an imported settings file or settings sync can write holzBar's defaults |
| holzBar → unified log | log lines may carry data about other apps' items |
| maintainer's Mac → release signing key | the hand test temporarily brings the release private key onto the Mac |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-F13-01 | Denial of service | MenuBarItemImageCache capture queue | medium | mitigate | each call bounded by BlockingWork.run(timeout: 2 s); fresh queue after a timeout; hung window skipped; single captures skip off-screen items (Tasks 1-2) |
| T-F13-02 | Denial of service | threads of abandoned queues | low | mitigate | at most 3 abandoned queues per session, then capture stops (Watchdog.isStopped); pinned by ItemCapturePolicyTests (Task 1) |
| T-F13-03 | Denial of service | waiters of the image cache (search, Shelf, groups, settle) | medium | mitigate | CoalescedRun: one pass at a time with a union re-run; the search no longer awaits; the Shelf's 1 s bound from e8eff47e (Tasks 2-3) |
| T-F13-04 | Tampering | Defaults.Key.debugHangsItemImageCapture | medium | mitigate | listed in localOnlyKeys, so never exported, imported or synced; pinned by SettingsSchemaTests (Task 3) |
| T-F13-05 | Information disclosure | new log lines | low | mitigate | only counts and durations are .public; no windowID, item, tag or app name; privacy-check.py logs gate |
| T-F13-06 | Information disclosure | item images kept in memory after a stop | low | accept | memory only, as while any view is open; never written to disk; released at quit |
| T-F13-07 | Spoofing | release signing key during the hand test | high | mitigate | temporary keychain with a random password, deleted right after signing; .p12 deleted; never in the login keychain or the repository (Test build section) |
| T-F13-SC | Tampering | npm/pip/cargo installs | high | accept | not applicable: no package install, no new dependency |
</threat_model>

<verification>
- Every gate in "Gates" passes before each commit. There are two commits on audit-manual/events after e8eff47e: A (images) and B (search, plus the SUMMARY).
- `swift test` includes the new BlockingWork, ItemCapturePolicy, CoalescedRun and SettingsSchema tests. RED (compile failure) was recorded before GREEN for Tasks 1 and 2.
- Code check against the decisions:
  - D-01: the BlockingWork overload with a lock-guarded resume-once and a global asyncAfter timer;
  - D-02: an instance captureQueue, onCaptureQueue as the only BlockingWork caller in the cache, captureDidTimeOut with a fresh queue, the skip list, the stop after 3, a single .error, and releaseAllImages guarded;
  - D-03: captureRun.run in updateCacheWithoutChecks;
  - D-04: per-item individualCapture with ItemCapturePolicy.isOnScreen and captureMissingOffScreen;
  - D-05: show() orders front before the refresh;
  - D-06: HolzBarShelf.swift unchanged since e8eff47e;
  - D-07: ScreenCapture.swift unchanged and the macOS 27 branch byte-identical.
- No new String Catalog entries; strings-check count is 369.
- After CI: hand-test steps 1-10 on macOS 26.7.1 with the re-signed build, and step 11 on macOS 27 if available.
</verification>

<success_criteria>
- On macOS 26 a stuck item capture costs at most about 2 s and one thread. Images keep updating, and after 3 stuck calls capture stops with the last images kept and one error logged.
- The search always appears at once. The Shelf opens within about 1 s.
- Within 2 s after a move, no single capture of an item off screen is attempted.
- No request to the image cache waits forever, and no Task leaks every 3 s.
- Two atomic local commits; all local gates green; no new user-facing strings; docs untouched (listed above).
</success_criteria>

## Source audit

| Source | ID | Item | Plan | Status |
|---|---|---|---|---|
| GOAL | F-13 | A stuck capture must not stop images, search and Shelf for the session | Tasks 1-3 | COVERED |
| REQ | F-13 fix 1 | one capture in flight | Task 2 (D-03, refined by the decision to a union re-run) | COVERED |
| REQ | F-13 fix 2 | watchdog about 2 s, resume-once, fresh queue | Task 1 (D-01, D-02) | COVERED |
| REQ | F-13 fix 3 | no single capture of items outside every display | Task 2 (D-04; "entirely inside one display") | COVERED |
| REQ | F-13 fix 4 | search installs its view before awaiting | Task 3 (D-05) | COVERED |
| CONTEXT | D-01 | BlockingWork timeout variant + three named tests | Task 1 | COVERED |
| CONTEXT | D-02 | instance queue, 2 s, fresh queue, skip hung window, stop after 3, keep images, log once, per-item hop | Tasks 1-2 | COVERED |
| CONTEXT | D-03 | coalescing with union re-run | Task 2 | COVERED |
| CONTEXT | D-04 | off-screen rule, cached image or composite | Task 2 | COVERED |
| CONTEXT | D-05 | search show-first (F-84 code) | Task 3 | COVERED |
| CONTEXT | D-06 | Shelf: the "otherwise" branch, bounded wait ≤ 1 s, cacheFailed unchanged | already in e8eff47e; verified in Task 3 | COVERED |
| CONTEXT | D-07 | keep CGWindowList, macOS 27 untouched, other call sites out of scope | Gates 7, verification | COVERED |
| CONTEXT | D-08 | #777 row and release-note line | doc_updates_needed (the chain may not edit docs) | COVERED (as instructed) |
| CONTEXT | D-09 | CI plus the maintainer smoke test incl. a second display on the left | Gates, hand test steps 2-4 | COVERED |
| RESEARCH | — | other waiters (groups, settle, Screen Recording grant) | bounded through D-02 and D-03 | COVERED |
| RESEARCH | — | AppState:292 calls updateCacheWithoutChecks without the 1 s move skip | covered by D-04 (no off-screen single capture on any path) | COVERED |
| RESEARCH | — | F-37 reusing the helper; ScreenCaptureKit; an XPC capture process | not offered or out of scope per the decision | EXCLUDED |

<output>
After execution, write `.planning/audit/remediation/events-capture-SUMMARY.md` (the same frontmatter shape as events-timeouts-SUMMARY.md), with:
- both commits;
- the RED observations for Tasks 1 and 2;
- the gate results per commit (test counts, appcheck, servicecheck, SwiftLint, privacy and strings checks);
- every deviation from this plan, with its reason (for example a dropped timer cancel under P-09, or a nonisolated init for CoalescedRun);
- the hand-test steps above;
- doc_updates_needed.
</output>
