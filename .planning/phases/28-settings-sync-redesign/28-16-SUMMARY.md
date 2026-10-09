---
phase: 28-settings-sync-redesign
plan: 16
subsystem: sync
tags: [swift, arrangement, layout-profiles, import, intents, lint, swift-testing]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-03 apply(_:byUser:) and profile IDs, 28-09 SyncLayout27 intents, 28-15 host with recordIntent, protectedApplications and finishImport"
provides:
  - "Concealer27.setSection sends one explicit l27 intent for a user's move in the Layout pane"
  - "LayoutProfiles sends prof intents from the change of the synced fields (save, rename, delete, undo) and l27 intents for a profile the user applies"
  - "SettingsBackup.importFromFile records layout and profile intents and calls finishImport before the relaunch"
  - "SectionLayout27.fillingMissing and canSeed: seeding that never overwrites intent; placement skips protected applications"
  - "The D-04 re-check recorded (no other user arrangement path on macOS 27) and a lint that names any new writer of MacOS27Layout"
affects: [28-17 UI, 28-18 removing the pause]

actuals:
  tokens: 6000
  tasks: 3
  commits: 3
plan_head_before: 35d08171c6dfb6fd525666082a7caf65b9d4b8a1
plan_head_after: 679ed3e5e7ebf9bb3eae2b714d08870c4fbb756d

key-files:
  created: []
  modified:
    - holzBar/MenuBar/MacOS27/Concealer27.swift
    - holzBar/MenuBar/Backends/AccessibilityBackend27.swift
    - holzBar/MenuBar/Profiles/LayoutProfiles.swift
    - holzBar/Utilities/SettingsBackup.swift
    - holzBar/MenuBar/MacOS27/Core/SectionLayoutEditing27.swift
    - Tests/HolzBarMacOS27CoreTests/SectionLayout27Tests.swift
    - .github/scripts/sync-lint.py

key-decisions:
  - "LayoutProfiles.syncValues(of:) builds the prof value with SyncLayout27.profileValue from the decoded profiles (name, applicationSections, knownApplications), the same three fields and sorted known array that SyncProjection.profileItems reads, so the app does not need the unit table; the first of two profiles with one ID counts, as in the snapshot"
  - "placeNewApplications keeps recording every new application as known (knownApplications27) and subtracts the protected ones only from the applications it places, so a protected application is not seen as new again at every read"
  - "The seeding rule is a second pure function, SectionLayout27.canSeed(into:except:), next to fillingMissing, so both halves of the rule are tested in the package"
  - "LAYOUT_WRITERS of sync-lint.py became a list of (path, reason) like WRITER_ALLOWED; the five writers keep their paths, each now with its reason"

patterns-established:
  - "A user path of the macOS 27 arrangement sends one SyncIntent.userSet from the place where the defaults change, after the write; an automatic store reads settingsSync.protectedApplications once per call"

requirements-completed: [SYNC-R05, SYNC-R06, SYNC-R07]

completed: 2026-10-09
status: complete
---

# Phase 28 Plan 16: Arrangement capture, profiles and Import Summary

**Every user path to the macOS 27 arrangement and to layout profiles now sends an explicit intent (Layout-pane move, profile save/rename/delete/undo, a profile the user applies, Import), holzBar's own seeding and placement no longer overwrite intent, and the absence of any other user path is proven in the code and guarded by the lint. Sync stays paused.**

## D-04 verification

Re-run against the code as it is on this branch (tip of planning/sync-redesign with plan 28-15). Result: **no other user arrangement path exists on macOS 27; a Command-drag on the bar saves nothing.** The sentence with its reason is in the doc comments of `AccessibilityBackend27.canMoveItems` and `Concealer27.setSection`.

1. Every reference to the layout key in the app (`grep -rn "macOS27Layout" holzBar --include='*.swift'`):
   - Writers: `Concealer27.swift` `placeNewApplications` (automatic), `setSection` (user), `seedLayoutIfNeeded` (automatic); `LayoutProfiles.swift` `apply` (user unless bound); `SyncProjection.swift` `writeFamily` and the sync gateway (the engine's own apply); Import through `SettingsBackup.apply` (generic key loop, no named reference). This is the expected list.
   - Readers only: `Concealer27.savedLayout`, `LayoutProfiles.saveCurrentLayout`, `LayoutBarPaddingView.swift:298`, `Migration.swift:80-85` (reads the layout and the seeded flag), `Defaults.swift`, `SyncUnits.swift`.
2. `canMoveItems`: `AccessibilityBackend27.swift` `var canMoveItems: Bool { false }`; the protocol requirement in `MenuBarBackend.swift`; `WindowListBackend` true, `ServiceBackend26` forwards. Uses: `HIDEventManager.swift:190` (`savesUserArrangement: MenuBarBackends.current.canMoveItems`, so `InputMonitors` adds no arrangement mouse-up monitor), `MenuBarItemManager.swift:160, 569, 586`, and the three guards of `SectionRestore.swift` (`saveSections` line 52, `saveSectionsSoon` line 84, `reconcileSections` line 159), each `guard backend.canMoveItems ... else { return }`. A Command-drag on the bar still reaches `handleMenuBarItemDragStop` / `handleArrangementEnd` (`HIDEventManager` 493 and 512) when "Show all sections on drag" or a custom appearance is on, but both only call `saveSectionsSoon()`, which returns first on macOS 27.
3. Callers of `Concealer27.setSection`: only `LayoutBarPaddingView.swift:314` (`setSection27`), reached from `LayoutBarMoves.setSection(of:to:appState:)` (drop, keyboard move, undo) which `LayoutBarItemView.swift:376` and `LayoutBarPaddingView.swift:86` call.
4. Every other command that touches sections or profiles: `HotkeyActionPerform` (`profiles.apply(profileID:byUser: true)`), `URLCommands` (`apply(named:byUser: true)` after the confirmation; the section commands only show, hide or toggle, a visibility change), `HolzBarIntents` (`apply(named:byUser: true)`; the section intent shows or hides), the Layout pane (`save`, `rename`, `apply(_, byUser: true)`, `bind`, `unbind`, `delete`), and the Space/display bindings (`applyBoundProfile` passes `byUser: false`). All end in `LayoutProfiles` methods or in a visibility change. There is no command that stores a section.
5. The plan's acceptance grep `grep -rn "forKey: .macOS27Layout" holzBar ... | grep -v Concealer27|LayoutProfiles|Core/Sync` prints three reads and one flag (`Migration.swift:80, 81, 85`, `LayoutBarPaddingView.swift:298`): no write. The sync lint is the real guard, it checks writes only.

## What was built

- **Task 1 (tracer).** `Concealer27.setSection` reads the section before (`savedLayout[bundleID] ?? .visible`), stores, and when it changed sends `SyncLayout27.moveIntent(bundleID:from:to:)` with the integer raw values through `settingsSync.recordIntent(.userSet([...]))` (the helper returns `nil` for no change, so a drop on the same section or an undo to the same value sends nothing). The macOS 26 Layout pane has no such call and `ItemSections` stays local. `sync-lint.py`: `LAYOUT_WRITERS` carries each of the five writers with its reason, the message of a new writer names the D-04 result.
- **Task 2.** `SectionLayout27.fillingMissing(_:into:except:)` keeps every saved entry and adds seeded entries only for applications with no entry that are not protected; `canSeed(into:except:)` is the new seeding rule (saved layout empty, or every key protected). `seedLayoutIfNeeded` uses both, with the seeded flag as before; `placeNewApplications` places only new applications that are not in the saved layout and not protected. 5 new tests (22 in the file).
- **Task 3.** `LayoutProfiles`: `syncedValues` (not observed) set in `load()`; `save()` on macOS 27 computes the new values, sends `SyncLayout27.profileIntents(old:new:)` when non-empty and stores them, so save, rename, delete and undo follow one rule and bind, unbind, current profile and any save on macOS 26 send nothing. `apply(_:byUser:)` sends `layoutIntents(old:new:)` of the stored layout before and after when `byUser`, none for a binding. `replaceProfiles(with:)` had no caller and is removed. `SettingsBackup.importFromFile`: takes the layout and profile values before `apply`, records both intents after, calls `AppState.current?.settingsSync.finishImport()`, then `relaunch()`.

## Verification

- `Scripts/typecheck-app.sh`: "==> holzBar type-checks" after each task.
- `swift test --filter SectionLayout27Tests`: 22 tests in 4 suites pass.
- Full `swift test` (heavy sync tests gated, 409 s): the three test targets pass, HolzBarCoreTests 911 tests in 116 suites, HolzBarMacOS27CoreTests 200 tests in 36 suites, no failure.

## Self-Check: PASSED

The three commits (b92492b1, cc8f0f6b, 679ed3e5) are ancestors of HEAD; the seven modified files exist and carry the strings the acceptance criteria grep for (`recordIntent`, `func fillingMissing`, `profileIntents`, `layoutIntents`, `finishImport` before `relaunch()` in `importFromFile`, `byUser`).
- SwiftLint `--strict`: 0 violations in 246 files.
- `strings-check.py`: 383 strings in 5 languages complete. `privacy-check.py logs` and `network`: pass. `sync-lint.py --self-test` (62 fixtures) and `sync-lint.py`: pass.
- `Scripts/check-sync-app.sh`: "The sync host ran as two Macs on real files".
- `SettingsSyncPause.isPaused` is still `true`.

## Deviations from Plan

### Auto-fixed Issues

None.

### Plan wording that did not fit

- **The acceptance grep for writers** (`grep ... "forKey: .macOS27Layout" ... | grep -v ...` prints nothing) also matches reads: it prints `Migration.swift:80, 81, 85` and `LayoutBarPaddingView.swift:298`, all reads of the layout or the seeded flag. No other file writes the layout (the lint proves it).
- **`placeNewApplications` still records protected applications as known**; only the placement subtracts them (see key decisions). The plan's wording ("subtract the protected applications from the new bundle IDs") would have left a protected application new at every read.
- **`LayoutProfiles.syncValues(from:)` does not use `SyncProjection`** (its profile code is private and needs a unit table); it builds the same three fields with `SyncLayout27.profileValue`. It is app-side code and has no package test; the shape matches `SyncProjection.profileItems` by reading (name, applicationSections, knownApplications sorted and unique, first profile of an ID).
- **Files outside the plan's list:** none. `MenuBarLayoutSettingsPane.swift` and the String Catalogs were not touched, nor `holzBar/Core/Sync`, `Tests/HolzBarCoreTests/Sync` or `Scripts/sync-*.py`.

## Known Stubs

None.

## Threat Flags

None: no new endpoint, file access or schema at a trust boundary.
