---
phase: 28-settings-sync-redesign
plan: 05
subsystem: settings-sync
tags: [swift, userdefaults, sync, migration]
requires:
  - phase: 28-03
    provides: AppDelegate.init order with LayoutProfiles.migrateStoredProfileIdentities
provides:
  - Four models that load stored synced settings without saving them
  - LayoutSeedRepair predicate and MigrationManager.repairLayoutSeededFlagIfNeeded
  - Removal of the old SettingsSync.userChangedLayout hook
affects: [28-07, 28-15, 28-16]
tech-stack:
  added: []
  patterns: ["isLoadingStoredValues flag (copied from RevealRules) guards every saving didSet"]
key-files:
  created:
    - holzBar/Core/LayoutSeedRepair.swift
    - Tests/HolzBarCoreTests/LayoutSeedRepairTests.swift
  modified:
    - holzBar/Settings/Models/GeneralSettings.swift
    - holzBar/MenuBar/Spacers/MenuBarSpacers.swift
    - holzBar/MenuBar/Appearance/MenuBarAppearanceManager.swift
    - holzBar/MenuBar/Groups/MenuBarItemGroups.swift
    - holzBar/Utilities/Migration.swift
    - holzBar/Main/AppDelegate.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/MenuBar/MenuBarItems/SectionRestore.swift
    - holzBar/MenuBar/MacOS27/Concealer27.swift
    - holzBar/Utilities/SettingsBackup.swift
key-decisions:
  - "Kept the byUser parameter of SectionRestore.saveSections/storeSections although nothing reads it now; plan 28-16 wires the capture of user moves through it"
  - "Left the layout-edit counter keys and their reading code in SettingsSync.swift; plan 28-15 replaces the file as a whole"
requirements-completed: [SYNC-R05, SYNC-R06]
status: complete
commits: 3
plan_head_before: 55ca2f4a69884233352aa9e7c08e97b9ddb51d20
plan_head_after: 235da842adb26bbf204268350c8838473fdf11af
actuals:
  tasks: 3
  commits: 3
duration: 25min
completed: 2026-10-07
---

# Phase 28 Plan 05: Load without saving Summary

**GeneralSettings, MenuBarSpacers, MenuBarAppearanceManager and MenuBarItemGroups now load stored values without writing them back, the old layout-edit hook is gone, and a one-time repair clears the beta1 seeded-flag artifact on macOS before 27.**

## Tasks

1. Tracer: GeneralSettings and MenuBarSpacers (`337240b9`). `isLoadingStoredValues` wraps every saving `didSet`; non-saving side effects (spacing update, `lastCustomHolzBarIcon`, `update()`) still run; clamps stay in memory. Type check passes.
2. Appearance and groups, seeded-flag repair (`bcd30301`). Same flag in both models; `LayoutSeedRepair.shouldClearSeededFlag` with 4 tests; `MigrationManager.repairLayoutSeededFlagIfNeeded()` (only on `#unavailable(macOS 27.0)`, removes only `MacOS27LayoutSeeded`).
3. Removed `SettingsSync.userChangedLayout()` and its four callers; `AppDelegate.init` calls the repair right after `importPreviousSettingsIfNeeded()` (`235da842`).

## Verification

- `Scripts/typecheck-app.sh`: passes.
- `swift test`: 552 tests in 72 suites pass (LayoutSeedRepairTests 4/4).
- `grep -rn userChangedLayout holzBar`: no output.
- `privacy-check.py logs` and `strings-check.py`: exit 0.
- SwiftLint `--strict`: one error, in `holzBar/Core/Sync/SyncReplica.swift:28` (`void_function_in_ternary`, from plan 28-01, not touched here). Logged in `deferred-items.md`. No violation in this plan's files.
- `SettingsSyncPause` untouched; sync stays paused (D-12).

## Deviations from Plan

None in behavior. The RED step of the TDD task was not committed separately (tests and predicate were committed together in one commit, tests passing).

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

Created files exist (LayoutSeedRepair.swift, LayoutSeedRepairTests.swift); commits 337240b9, bcd30301, 235da842 are on the branch.
