---
phase: 02-bug-fixes
verified: 2026-10-02T17:00:00Z
status: human_needed
score: 5/5 must-haves verified in code and CI (runtime behaviour on macOS 26/27 needs human checks)
covered_files:
  - MenuBarItemService/Listener.swift
  - Shared/CodeSigning/CodeSignature.swift
  - holzBar/Core/Modifiers.swift
  - holzBar/Core/SpacingRelaunch.swift
  - holzBar/MenuBar/MacOS27/Core/SystemItems27.swift
  - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
  - holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift
  - holzBar/Permissions/Permission.swift
  - holzBar/UI/Views/HotkeyRecorder.swift
covered_digest: "v2:sha256:4f7529a850bd7afc9bea049a1f603e16f3e7fcc67a91f30cabc4c5aa4c461ef3"
behavior_unverified: 3
behavior_unverified_items:
  - truth: "Waiting for a permission twice never hangs (Permission.waitForPermission, one AsyncStream per waiter)"
    test: "Reset Screen Recording, click Grant twice (Grant, Reset and Grant Again), grant in System Settings"
    expected: "Both waits return; the permissions window comes to the front once; a wait ended by stopCheck() does not reopen it"
    why_human: "No test exercises Permission; the invariant is cleanup/ordering across timer, stopCheck and cancellation"
  - truth: "The event source cache has no data race (OSAllocatedUnfairLock around lookup, create, store)"
    test: "Drag several items between sections quickly while clicking hidden items in the Shelf"
    expected: "Items move and open as before, no crash"
    why_human: "A data race is not visible to grep or a unit test; the lock is present and wraps the whole critical section"
  - truth: "The XPC service accepts the ad hoc build and rejects foreign processes"
    test: "Ad hoc build on macOS 26, `log stream` for MenuBarItemService, open Settings > Menu Bar Layout"
    expected: "Service logs \"Listener requires the app's exact code (N code directory hashes)\", layout shows items, no fallback line"
    why_human: "The accept/reject decision runs inside XPC on macOS 26 only; CI proves the cdhash matches a running process, not the listener"
human_verification:
  - test: "macOS 26: change menu bar item spacing and Apply with several apps that own items running"
    expected: "Every owner relaunches (also when Control Center or holzBar would be first); repeat gives the same set"
    why_human: "Real app quit/launch cycle"
  - test: "macOS 26: apply spacing with an app that asks before quitting, leave unanswered"
    expected: "App is not killed; after about 10 s the alert names it; the others relaunch"
    why_human: "Timing and real app behaviour"
  - test: "macOS 27: apply spacing"
    expected: "No alert names MenuBarAgent, the owning apps relaunch; note whether spacing changes"
    why_human: "Needs macOS 27 and live Accessibility"
  - test: "macOS 26 Settings > Hotkeys: Option-H, Option-Shift-H, Command-Option-H"
    expected: "First two show \"macOS does not allow this hotkey\" and keep recording; the third records and fires; earlier hotkeys still work"
    why_human: "UI alert and global hotkey firing"
  - test: "Permissions window (Grant twice, grant in System Settings; Continue without granting)"
    expected: "Window comes front once when granted; does not reopen when not granted"
    why_human: "See behavior_unverified_items"
  - test: "Ad hoc build XPC log check (see above) plus a foreign-process rejection if feasible"
    expected: "Accepted for holzBar, rejected for others"
    why_human: "See behavior_unverified_items"
  - test: "Fast item moves plus Shelf clicks"
    expected: "No crash"
    why_human: "See behavior_unverified_items"
  - test: "macOS 27: hide some apps' items"
    expected: "Battery, clock, Wi-Fi, Control Centre stay; hidden apps' items disappear"
    why_human: "Live MenuBarAgent assertion"
---

# Phase 2: Bug fixes Verification Report

**Phase Goal:** The real bugs found by the audit are fixed so spacing, hotkeys, XPC and permissions behave correctly on every supported macOS version
**Verified:** 2026-10-02
**Status:** human_needed
**Re-verification:** No, initial verification
**Evidence head:** PR #35 head `799e386ddf422e7f44a6ea350611b8ffd2a8702c` (draft, mergeable_state clean). Check runs via REST: build, test, former-name, swiftlint, cask all `success`. Test log: "Test run with 140 tests in 26 suites passed"; `** BUILD SUCCEEDED **`; 5 compiler warnings, all in pre-existing files (HIDEventManager, ItemClicker27, ScreenCapture), none in files touched by this phase.

## Goal Achievement

### Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Spacing relaunch relaunches every affected app, waits without force-terminating after 1 s, works on macOS 27 | VERIFIED (code + CI); runtime on human list | `SpacingRelaunch.processesToRelaunch` filters with `compactMap` (no `break`; skips only own pid, Control Center, MenuBarAgent), `quitTimeout` = 10 s, `waitUntil` is a task group of event vs sleep (no continuation, always returns). `MenuBarItemSpacingManager.quit` uses KVO on `isTerminated` plus `app.terminate()`, never `forceTerminate` (only `ConflictingApps` uses it, unrelated). macOS 27 branch uses `MenuBarItemProvider27.items()`, owners via `sourcePID ?? ownerPID`. 10 `SpacingRelaunch` tests pass in CI. |
| 2 | Hotkey recorder rejects Option / Option+Shift on macOS 15+ and tells the user; signature identical | VERIFIED (code + CI) | `Modifiers.rejection(refusesOptionOnly:)` returns `.optionOnly`; `HotkeyRecorderModel.handleKeyDown` calls it with `#available(macOS 15.0, *)`, sets `presentedProblem = .optionOnly`, shows alert with message, keeps recording. `HotkeyRegistry` also refuses to register. `signature = OSType(1231250720)` unchanged; raw values 1/2/4/8 pinned by test. 7 `Modifiers` tests pass. |
| 3 | Ad hoc build accepted by XPC service, foreign processes rejected | VERIFIED in code; runtime PRESENT_BEHAVIOR_UNVERIFIED | `Listener.peerRequirement()`: team build uses `.isFromSameTeam(andMatchesSigningIdentifier:)`; ad hoc builds require `SigningIdentifier` plus `CodeDirectoryHash.in(hashes of embedding app)`; throws (service does not listen) when the host bundle id is wrong or the signature invalid (fail closed). App side only sets its same-team requirement when it has a team. `CodeSignature` suite (6 tests) proves in CI that the hashes match a running process via audit token and that other identifiers/hashes do not match. |
| 4 | Waiting for a permission twice never hangs; event source cache has no data race | VERIFIED in code; runtime PRESENT_BEHAVIOR_UNVERIFIED | `Permission.waitForPermission() -> Bool` uses one `AsyncStream` per waiter in a `[UUID: Continuation]`, ended by `endWaits` on grant, `stopCheck()` or cancellation (`defer` removes the waiter); no `withCheckedContinuation` left; `PermissionsView` handles the Bool. `getEventSource` does lookup, create and store inside one `OSAllocatedUnfairLock.withLockUnchecked`; no unguarded static state. No automated test covers either. |
| 5 | macOS 27 system item allowlist comment and code agree | VERIFIED | `SystemItems27.allowed = 0...127`; `MenuBarAssessmentAssertion27.systemItems` is built from it; the comment now says 0 to 127 and mentions Ice#1001's 0 to 63 as inside it. 3 `SystemItems27` tests pin it. |

Score: 5/5 truths implemented and CI-green; 3 are behavior-dependent (permissions, data race, XPC accept/reject) with no behavioral test, so they are routed to human verification and not counted as behavior-verified.

### Requirements Coverage

| Requirement | Status | Evidence |
|-------------|--------|----------|
| BUG-01 `continue` instead of `break` | SATISFIED | `processesToRelaunch` plus `SpacingRelaunchTests` "A skipped owner does not stop the others" |
| BUG-02 long wait, no force-terminate, continuation always resumed | SATISFIED | 10 s `quitTimeout`, `waitUntil` task group, tests for timeout and cancellation |
| BUG-03 macOS 27 owner collection | SATISFIED in code; macOS 27 runtime unproven | `MenuBarItemProvider27.items()` branch in `applyOffset()` |
| BUG-04 event source cache race | SATISFIED in code; no test (human) | `OSAllocatedUnfairLock` in `MenuBarItemManager.getEventSource` |
| BUG-05 hotkey recorder | SATISFIED | See truth 2 |
| BUG-06 XPC ad hoc | SATISFIED in code and cdhash proof; listener runtime on macOS 26 unproven | See truth 3 |
| BUG-07 permission continuation | SATISFIED in code; no test (human) | See truth 4 |
| BUG-08 allowlist | SATISFIED | See truth 5 |

No orphaned requirements: BUG-01..08 are all claimed by 02-01..02-04. REQUIREMENTS.md already marks them Complete.

### Anti-Patterns

No TBD/FIXME/XXX introduced in covered files. No stubs: all new files are real implementations wired into the app (Core files are compiled by the synchronized `holzBar` group and by the test-only `Package.swift`).

## Gaps (non-blocking)

1. WARNING: BUG-04, BUG-07 and the XPC accept/reject path have no automated behavioural test (see `behavior_unverified_items`); only the human checks cover them.
2. WARNING: The ad hoc XPC design pins exact cdhashes of the embedding app. An ad hoc app re-signed after install (e.g. by `xattr`-free `codesign --force`) still works because the service reads the hashes at runtime, but a foreign process with the same identifier is rejected only if the framework enforces `CodeDirectoryHash` as documented; this is what the human log check confirms.
3. INFO: ROADMAP.md still shows Phase 2 as `[ ]` (and the Phase 2 line in the progress list); tick it when PR #35 is merged. Spacing writes still use the `defaults` process; that is Phase 4 scope (API-01), not a Phase 2 gap.
4. INFO: Draft PR #35 is not merged yet.

## Human Verification Required

See the `human_verification` list in the frontmatter (8 items, the same as the "Open human checks" in 02-04-SUMMARY.md). The three most valuable on the fewest devices: macOS 26 spacing Apply with a "will not quit" app, the macOS 26 ad hoc XPC log check, and the macOS 27 spacing plus hide-items check.

---

_Verified: 2026-10-02_
_Verifier: Claude (gsd-verifier)_
