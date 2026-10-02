---
phase: 02-bug-fixes
plan: 02
subsystem: hotkeys-and-permissions
status: complete
tags: [bug-fix, hotkeys, macos15, permissions, swift-concurrency, asyncstream, swift-testing]
requires:
  - "02-01: holzBar/Core with the HolzBarCore / HolzBarCoreTests targets, draft PR #35"
provides:
  - "holzBar/Core/Modifiers.swift: the Modifiers option set (raw values 1, 2, 4, 8 unchanged) with Rejection and rejection(refusesOptionOnly:)"
  - "holzBar/Hotkeys/ModifierFlags.swift: the Cocoa, CoreGraphics and Carbon conversions"
  - "Permission.waitForPermission() -> Bool, safe to call any number of times"
affects:
  - "MOD-02 (Phase 05.1) converts HotkeyRecorderModel and Permission to @Observable"
  - "PERF-02 (Phase 5) stops the 1 s permission check once everything is granted"
tech-stack:
  added: []
  patterns:
    - "One AsyncStream per waiter, kept in a [UUID: Continuation] dictionary and ended by a single endWaits(with:)"
    - "One @Published optional problem plus a computed isPresenting Bool driving alert(_:isPresented:presenting:actions:message:)"
key-files:
  created:
    - holzBar/Core/Modifiers.swift
    - Tests/HolzBarCoreTests/ModifiersTests.swift
  modified:
    - holzBar/Hotkeys/ModifierFlags.swift (renamed from holzBar/Hotkeys/Modifiers.swift)
    - holzBar/UI/Views/HotkeyRecorder.swift
    - holzBar/Hotkeys/HotkeyRegistry.swift
    - holzBar/Permissions/Permission.swift
    - holzBar/Permissions/PermissionsView.swift
decisions:
  - "Option-only and Option+Shift-only hotkeys are refused on macOS 15+ in the recorder (alert, recording continues) and in HotkeyRegistry (logged, RegisterEventHotKey not called); the Carbon signature OSType(1231250720) is unchanged (D-01)"
  - "A permission wait returns false when stopCheck() ends it or its task is cancelled, and the Grant buttons only reopen the permissions window on true"
metrics:
  duration: 15min
  completed: 2026-10-02
  tasks: 2
  files: 7
estimate:
  tokens: 55000
  tasks: 2
actuals:
  tokens: 4400
  tasks: 2
  commits: 3
plan_head_before: 3b65dc3fb916cd210076f57c9de7753cbeb379bc
plan_head_after: b66fe376939c4d2dca91cb8b118528b003182242
---

# Phase 2 Plan 02: Option-only hotkeys and permission waits Summary

On macOS 15 and later the hotkey recorder refuses a combination whose only modifiers are Option, or Option and Shift, explains in an alert that Command or Control is needed and keeps recording; `HotkeyRegistry` logs the reason instead of calling `RegisterEventHotKey` for it. The rule lives in the new pure, unit-tested `holzBar/Core/Modifiers.swift`. `Permission.waitForPermission()` now returns a Bool from its own `AsyncStream`, so any number of waits end (true on grant, false when the checks stop or the task is cancelled).

## Phase PR

- **PR #35**, draft: https://github.com/holzcloud/holzBar/pull/35 (head `claude/ice-fork-development-hzdl1d`)
- Final head `b66fe376939c4d2dca91cb8b118528b003182242`: `build`, `test` and `swiftlint` all success (both the push and the pull_request runs).
- `test`: "Test run with 131 tests in 24 suites passed" (124 in 23 suites before; +7 in the new `Modifiers` suite).
- `build`: `** BUILD SUCCEEDED **`; the only warnings are the pre-existing ones in `HIDEventManager.swift`, `ItemClicker27.swift` and `ScreenCapture.swift`, none in a file of this plan.
- `swiftlint`: "Done linting! Found 0 violations".

## Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 RED | Failing tests for the hotkey modifier rule | 8eb7f92 | holzBar/Core/Modifiers.swift (stub), holzBar/Hotkeys/ModifierFlags.swift, Tests/HolzBarCoreTests/ModifiersTests.swift |
| 1 GREEN | Refuse Option-only hotkeys on macOS 15 and tell the user | ab6d3fc | holzBar/Core/Modifiers.swift, ModifierFlags.swift, HotkeyRecorder.swift, HotkeyRegistry.swift |
| 2 | Every permission wait returns | b66fe37 | Permission.swift, PermissionsView.swift |

## What changed

- **BUG-05** (D-01, recorder only):
  - `Modifiers` (struct, conformances and raw values control 1, option 2, shift 4, command 8 unchanged), `canonicalOrder` and `symbolicValue` moved to `holzBar/Core/Modifiers.swift` (Foundation only). `holzBar/Hotkeys/Modifiers.swift` became `ModifierFlags.swift` (git rename) with only the `nsEventFlags`, `cgEventFlags`, `carbonFlags` conversions and their initializers. `KeyCombination`, its coding and `Migration.swift` are untouched, so stored and imported hotkeys decode as before.
  - `Modifiers.Rejection` (`missing`, `shiftOnly`, `optionOnly`) and `rejection(refusesOptionOnly:)`.
  - `HotkeyRecorderModel`: `presentedProblem: Problem?` (`systemReserved`, `optionOnly`, each with title and message) and a computed `isPresentingProblem`. `handleKeyDown` switches over the rejection: no modifier keeps the Escape/beep behavior, Shift alone beeps, Option-only shows "macOS does not allow this hotkey" and keeps recording, otherwise the system-reserved check (now with a message) and the store as before. The view uses `alert(_:isPresented:presenting:actions:message:)`.
  - `HotkeyRegistry.register`: on macOS 15+ an Option-only combination is logged ("macOS 15 and later do not register hotkeys whose only modifiers are Option, or Option and Shift") and nil is returned. The signature line and the comment above it are byte for byte unchanged; `git diff origin/main` of the file touches no `OSType` line.
- **BUG-07**: the stored single waiter (`hasPermissionCancellable`) and the checked continuation are gone. `waiters: [UUID: AsyncStream<Bool>.Continuation]`, `endWaits(with:)`, a `didSet` on `hasPermission` that ends all waits with true, and `stopCheck()` ending them with false. `waitForPermission()` is `@discardableResult async -> Bool`, removes its entry in a `defer` and returns `hasPermission` after a cancelled iteration. Both Grant buttons in `PermissionsView` use `guard await permission.waitForPermission() else { return }`. No Combine pipeline was added.

## Tests that ran (CI, suite "Modifiers")

- "No modifier is always refused"
- "Shift alone is always refused"
- "Option alone is refused from macOS 15"
- "Option with Command or Control is accepted"
- "Command or Control combinations are accepted"
- "Raw values keep the stored hotkeys"
- "Symbols follow the system order"

`Permission` imports Cocoa and calls the Accessibility and screen capture checks, so Task 2 is covered by the CI build and the human check (D-04).

## TDD Gate Compliance

- RED: `test(02-02)` commit 8eb7f92 with a stub `rejection(refusesOptionOnly:)` returning nil. CI `test` job 110896387763 failed on assertions in "Option alone is refused from macOS 15" (`(modifiers.rejection(refusesOptionOnly: true) → nil) == .optionOnly`), "No modifier is always refused" and "Shift alone is always refused"; the other four passed against the stub, as expected. The Swift Testing per-test results were converted to TAP; `check tdd-red-evidence` gave `RED_EVIDENCE_OK` (target "Option alone is refused from macOS 15", 131 tests, 3 failing).
- GREEN: `fix(02-02)` commit ab6d3fc. All 7 `Modifiers` tests pass in CI.
- REFACTOR: not needed.

## CI fixes needed

1. RED run (8eb7f92), `swiftlint`: three "Colon Spacing Violation" errors in `ModifierFlags.swift` (`init(nsEventFlags:NSEvent.ModifierFlags)` etc.): the space after the colon was lost when the doc comments were added to the three initializers. Fixed in the GREEN commit ab6d3fc; `swiftlint` green from then on.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Lost space after the colon in the ModifierFlags initializers**
- **Found during:** Task 1 (RED CI run)
- **Issue:** adding `///` docs to the three initializers dropped the space after `nsEventFlags:`, `cgEventFlags:` and `carbonFlags:`; SwiftLint `--strict` failed.
- **Fix:** restored the spaces.
- **Files modified:** holzBar/Hotkeys/ModifierFlags.swift
- **Commit:** ab6d3fc

Otherwise the plan was executed as written. The `///` docs on the three conversion initializers are an addition following the SwiftLint convention in the plan.

## Open human checks

- On the Mac (macOS 26.7.1), Settings, Hotkeys: Record Hotkey, Option-H shows "macOS does not allow this hotkey" saying Command or Control is needed, and after OK the recorder still records; Option-Shift-H shows the same alert; Command-Option-H records and fires from another app.
- Hotkeys set before the update still work.
- Permissions window with Screen Recording reset (`tccutil reset ScreenCapture com.holzcloud.holzBar`): "Grant Permission", then "Reset and Grant Again", then grant in System Settings: the permissions window comes to the front once and shows it as granted. Reset again, "Grant Permission", do not grant, click Continue: the window does not reopen by itself later.

## Known Stubs

None.

## Threat Flags

None. No new endpoint, permission, entitlement, network call or log line with personal data; T-02-04 and T-02-05 are mitigated as planned.

## Self-Check: PASSED

The three created files and the commits 8eb7f92, ab6d3fc and b66fe37 exist; both task verify commands pass on b66fe37.
