---
phase: 05-security-and-performance
plan: 02
subsystem: performance-and-search
status: complete
tags: [performance, energy, hover, permissions, iokit, nwpathmonitor, fuzzy-search, typos]
requires:
  - "05-01: complete, PR #37 green on 1dc43e5"
provides:
  - "HoverSchedule<Action> (Core, tested): one pending delayed hover action"
  - "RevealTrigger (Core, tested): edge trigger and battery percentage"
  - "FuzzyMatch.typoEdits(query:in:) and allowedEdits(forQueryLength:) (Core, tested)"
  - "Permission checks that stop once granted"
  - "Reveal rules on IOKit power-source notifications and NWPathMonitor, no timer"
  - "Final PR #37 body for Phases 3 to 5"
affects:
  - "Show on hover starts one task per action instead of one per mouse move"
  - "The menu bar search finds misspelt names again, below every in-order match"
  - "README: Private principle explains NWPathMonitor; the search feature mentions abbreviations and typos"
tech-stack:
  added: []
  patterns:
    - "IOPSNotificationCreateRunLoopSource with a file-level C callback that posts a Notification.Name"
    - "Optimal string alignment distance in two reused rows with an early exit once a row exceeds the bound"
key-files:
  created:
    - holzBar/Core/HoverSchedule.swift
    - holzBar/Core/RevealTrigger.swift
    - Tests/HolzBarCoreTests/HoverScheduleTests.swift
    - Tests/HolzBarCoreTests/RevealTriggerTests.swift
  modified:
    - holzBar/Events/HIDEventManager.swift
    - holzBar/Permissions/Permission.swift
    - holzBar/MenuBar/RevealRules/RevealRules.swift
    - holzBar/Core/FuzzyMatch.swift
    - Tests/HolzBarCoreTests/FuzzyMatchTests.swift
    - docs/upstream-bugs.md
    - README.md
decisions:
  - "PERF-01: hover actions go through HoverSchedule; the same action pending starts nothing, the opposite one cancels and replaces the stored task"
  - "PERF-02: a permission polls once a second only while missing; performRequest() checks again, since a reset can revoke a granted permission"
  - "PERF-03 (D-10): IOKit power-source notifications on the main run loop and NWPathMonitor; while charging the battery level is unknown and the low-battery trigger keeps its state"
  - "PERF-04 (USER DECISION): typo fallback = optimal string alignment distance to a word or a word's start (continuing into the following words), 1 edit for 4-7 characters, 2 for 8+, none below 4; typo matches rank below every in-order match, fewer edits first"
metrics:
  duration: 16min
  completed: 2026-10-02
actuals:
  tokens: 8500
  tasks: 3
  commits: 4
plan_head_before: e455c8b1516bbeb98ffbd0ec5ea27a44794d5dd5
plan_head_after: af5906b2793e181fccdd03ee82f7992ca3e4ce22
---

# Phase 5 Plan 02: One hover task, no permission or battery polling, typo-tolerant search Summary

Show on hover keeps one cancellable task (tested `HoverSchedule`), permissions stop polling once granted, the reveal rules react to IOKit power notifications and `NWPathMonitor` through a tested `RevealTrigger` instead of a 60 s timer, and, by the user's decision, the menu bar search tolerates typos again with holzBar's own bounded Damerau–Levenshtein fallback. PR #37 is green on af5906b and its body covers Phases 3 to 5.

## What was done

### Task 1: one hover task, commit e9a2ec4

- `holzBar/Core/HoverSchedule.swift`: `pending`, a generation counter, `request(_:)` (nil when the same action is pending), `finish(_:)` (clears only the current generation), `cancel()`.
- `HIDEventManager`: private `HoverAction`, `hoverSchedule`, `hoverTask`. Each branch of `handleShowOnHover`, after its guards (and after recording the empty-space point), asks the schedule; on a new generation it cancels `hoverTask` and stores `Task { [weak self] in ... }`, which sleeps (`try? await`), returns when cancelled, calls `finish(generation)`, re-checks the pointer as before and shows or hides. `isEnabled = false` calls `cancelHoverAction()`. The `showOnHoverAllowed` comment is unchanged.
- `docs/upstream-bugs.md`: the "High CPU, energy or memory" row (still open) notes the hover task, the permission polling and the power events, and that it needs profiling.
- `@Suite("HoverSchedule")`, 5 tests.

### Task 2: no permission or battery polling, commit 6c17fd6

- `Permission`: `startCheck()` sets `hasPermission = check()`, stops the timer and returns when granted, otherwise starts (once) a 1 s `Timer.publish` without the `Just` merge, whose sink stops it when the permission arrives; `stopTimer()`; `init`, `waitForPermission()` and `performRequest()` call `startCheck()`; `stopCheck()` calls `stopTimer()` and still ends waits with false.
- `holzBar/Core/RevealTrigger.swift`: `update(_:)` (true only on false to true), `percent(current:maximum:)`. `@Suite("RevealTrigger")`, 5 tests.
- `RevealRules`: the 60 s timer is gone. `performSetup` observes a file-level `powerSourcesDidChange` notification (main queue) calling `checkBattery()`, creates the IOKit run loop source with a file-level C function that posts it, adds it to the main run loop in `.commonModes`, keeps it in `powerSource`, and checks the battery once. `revealsOnLowBattery` and `lowBatteryThreshold` re-check in `didSet` (after setup, not while loading). Both rules decide through a `RevealTrigger`; `NWPathMonitor` is unchanged and documented as observing path status only.
- README, Principles, Private: holzBar only watches whether a network path is available (NWPathMonitor) and never opens a connection.

### USER DECISION task: typo-tolerant search, commit 693d8f2

- `FuzzyMatch.typoEdits(query:in:)`: when the in-order match fails, the optimal string alignment distance (Damerau–Levenshtein with adjacent swaps) between the folded query and a prefix of the candidate's letters and digits starting at a word (continuing into the following words, punctuation skipped). `allowedEdits(forQueryLength:)`: 0 below 4 characters, 1 for 4 to 7, 2 for 8 or more. Case and diacritics are ignored through the same folding as the in-order match.
- Cost: two `Int` rows of query length + 1 per candidate, reused for every word start and swapped in place; the row two characters back is read through two scalars before it is overwritten. A word is left as soon as every entry of a row exceeds the bound (the row minimum never decreases), so at most query length + bound + 1 characters are read per word start.
- `rank` folds the query once per search (it was folded per candidate before), computes each candidate's positions once for both passes, and sorts in-order matches first (by score), then typo matches (fewer edits first), ties in their order.
- `score(query:in:)` is unchanged in meaning (in order only), so the existing "A query whose letters are missing has no score" test still holds ("abcd" in "abc" is a typo match, not a score).
- Tests in `FuzzyMatchTests.swift` (16 now): "A misspelt name finds Spotify" (also "spotlihgt" finds Spotlight), "A misspelt name finds Bluetooth", "A query of three letters does not match with a typo", "An in-order match ranks above a typo match" ("contorl": "Contoso Remote Launcher" in order before "Control Centre" by typo), "Swapped neighbours find Control Centre", "A query too many edits away does not match". The algorithm was checked before pushing against a brute-force Python reference (full distance matrix per word start): 0 mismatches in 20,000 random cases, and the expected values of every test case.
- README feature list: "Search menu bar items — by abbreviation ("cc" for Control Centre) and despite typos".

### Push, CI and PR

- One push (`1dc43e5..693d8f2`), then one fix push (`693d8f2..af5906b`).
- PR #37 body rewritten: a summary paragraph for Phases 3 to 5, "What changed" per phase with one bullet per requirement (LEFT-01 to LEFT-08 with LEFT-08 superseded, API-01 to API-08, DEP-01 with each package's version and the search decision, SEC-01 to SEC-03, PERF-01 to PERF-04), "Verified by" and every open human check of 03-01 to 05-02; it ends with the attribution lines. Still a draft, not merged.

## CI

- 693d8f2: build, swiftlint, former-name success; test failed to compile: `#expect(schedule.request(.show) ...)` and `#expect(trigger.update(true))` call a mutating method inside the macro ("cannot use mutating member on immutable value: '$0' is immutable").
- Fix af5906b (`fix(05-02): mutate the schedule and the trigger outside #expect`): the tests call `request(_:)` / `update(_:)` first and check the results; same assertions, nothing skipped.
- af5906b: build (BUILD SUCCEEDED; only the pre-existing warnings: HIDEventManager `:6` and the `AXUIElement` capture, now at line 595, ItemClicker27, ScreenCapture), test (200 tests in 35 suites passed, up from 184 in 33; Suites "HoverSchedule", "RevealTrigger" and "FuzzyMatch" passed), swiftlint (0 violations in 141 files), former-name: all success. The plan's Task 2 verify printed "05-02 green on af5906b...". App size 14,892 KB.
- `git grep 'Timer.publish' -- holzBar/MenuBar/RevealRules holzBar/Permissions` shows only the permission timer that runs while a permission is missing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tests mutated values inside `#expect` / `#require`**
- **Found during:** Task 2 CI
- **Issue:** Swift Testing's macro expansion captures the expression immutably, so mutating calls do not compile.
- **Fix:** call first, assert on the result.
- **Files modified:** Tests/HolzBarCoreTests/HoverScheduleTests.swift, Tests/HolzBarCoreTests/RevealTriggerTests.swift
- **Commit:** af5906b

**2. [Rule 1 - Bug] Plugging in and out re-fired the low-battery rule**
- **Found during:** Task 2
- **Issue:** today a charging Mac counts as 100 %, which ends the condition; with power notifications an unplug would show the items again at once, against the plan's human check ("plug in and unplug: it does not show again while the level stays below").
- **Fix:** while the level is unknown (charging or no battery) `checkBattery()` leaves the trigger as it is; charging above the threshold still ends the condition.
- **Files modified:** holzBar/MenuBar/RevealRules/RevealRules.swift
- **Commit:** 6c17fd6

**3. [Rule 2 - Correctness] A request checks the permission again**
- **Found during:** Task 2
- **Issue:** with the timer stopped once granted, "Reset and Grant Again" (tccutil reset) or "Grant Permission" in Settings, Advanced, after setup would leave `hasPermission` stale.
- **Fix:** `performRequest()` calls `startCheck()`, which polls only while the permission is missing and stops when it is granted.
- **Files modified:** holzBar/Permissions/Permission.swift
- **Commit:** 6c17fd6

**4. [Rule 3 - Blocking risk] Named C callback instead of a closure literal**
- The IOKit callback is a file-level function (`postPowerSourcesDidChange`) rather than a closure literal inside the main-actor class, so no actor isolation can be inferred for a `@convention(c)` value. Behaviour is as planned.

**5. [Rule 2 - Docs] README search feature**
- The feature list mentions abbreviations and typos (CLAUDE.md: keep the feature list up to date).

## Open human checks (on a Mac)

- Hover: with "Show on hover", move back and forth in empty menu bar space: the hidden section appears once after the delay, counted from entering, and hides after leaving for the delay. Activity Monitor: holzBar's CPU while moving the pointer outside the menu bar for 30 s with the section shown is lower or unchanged, never rising with the number of moves.
- Battery (MacBook, on battery): turn on "show hidden items when the battery is low" with a threshold above the current charge: the section shows at once and hides after the temporary-show interval; plug in and unplug: it does not show again while the level stays below.
- Offline: Wi-Fi off with the offline rule on: the section shows once.
- No permission timer: with all permissions granted, `sample holzBar 5` (or Instruments, Time Profiler) shows no 1 s permission timer firing.
- Search: "spotlihgt" finds Spotlight, "contorl" finds Control Centre (below in-order matches), "cc" still ranks Control Centre first.

## Self-Check: PASSED

- FOUND: holzBar/Core/HoverSchedule.swift, holzBar/Core/RevealTrigger.swift, Tests/HolzBarCoreTests/HoverScheduleTests.swift, Tests/HolzBarCoreTests/RevealTriggerTests.swift
- FOUND: commits e9a2ec4, 6c17fd6, 693d8f2, af5906b
