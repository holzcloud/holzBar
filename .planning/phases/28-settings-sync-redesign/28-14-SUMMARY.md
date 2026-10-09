---
phase: 28-settings-sync-redesign
plan: 14
subsystem: sync
tags: [swift, defaults-store, alias-rule, normalizers, lint, swift-testing]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-04 unit table, projection and normalizers; 28-13 gate G1 (not fully passed) and the determinism lint"
provides:
  - SyncDefaultsStore: the preferences domain as a SyncSnapshot, validated unit applies, generation and counter mirror, read-only tripwire
  - SyncAlias: the alias rule for item-keyed units (INV-A6)
  - SyncModelNormalizers: appearance, groups and the holzBar icon normalized by the models
  - SettingsBackup.excludedKeyPrefixes single-sourced from the unit table
  - .github/sync-synced-keys.txt with its test, and the writer rule of sync-lint.py
affects: [28-15 host, 28-16 arrangement capture, 28-17, 28-18 privacy doc]

actuals:
  tokens: 12500
  tasks: 3
  commits: 3
plan_head_before: 39cf9a1deca416f8d89fd7bc8319acdc00b076b1
plan_head_after: 0a909bde222b60832f62e9e8d93f1a66d7612333

tech-stack:
  added: []
  patterns:
    - "The store reads the persistent domain and filters excluded prefixes before projecting; it writes only keys that have a synced class, through SyncProjection.defaultsWrites"
    - "App normalizers assume the main actor (MainActor.assumeIsolated) because the models' Codable conformances are main-actor isolated"
    - "The writer lint reads the key list and the Defaults.Key case names from Defaults.swift, and compares each file with a justified allow-list"

key-files:
  created:
    - holzBar/Core/Sync/SyncAlias.swift
    - holzBar/Core/Sync/SyncDefaultsStore.swift
    - Tests/HolzBarCoreTests/Sync/AliasTests.swift
    - Tests/HolzBarCoreTests/Sync/DefaultsStoreTests.swift
    - holzBar/Utilities/Sync/SyncModelNormalizers.swift
    - .github/sync-synced-keys.txt
  modified:
    - holzBar/Utilities/SettingsBackup.swift
    - Tests/HolzBarCoreTests/Sync/UnitTableTests.swift
    - .github/scripts/sync-lint.py

key-decisions:
  - "SyncApplyReport (applied, skipped) is defined next to the store; the plan named the type but no earlier plan declared it"
  - "The store mirrors the acceptance check of SyncProjection.defaultsWrites to report skipped units, instead of changing SyncProjection (no edit of Core/Sync files other plans touch)"
  - "flush() is CFPreferencesAppSynchronize(domainName), which works for the app domain and for a test suite"
  - "The holzBar icon unit's icon field is the stored ControlItemImageSet JSON (not raw image data): it is normalized like the JSON units, its name must be one this build knows, and custom image data must be a bitmap CustomIconData accepts, checked from the header only"
  - "A JSON unit is applicable only when the re-encoded value has every key the raw value has at any depth (null counts as absent); the canonical form is the model's encoder with sorted keys and unescaped slashes"
  - "The writer lint flags any preferences write in holzBar/Core/Sync except SyncDefaultsStore, and allows MacOS27Layout writes only in Concealer27, LayoutProfiles, SettingsBackup, Migration and the store"
  - "An allowed site or layout writer that no longer exists fails the lint, so the allow-list cannot go stale silently"

patterns-established:
  - "A new Defaults.Key class change means rerunning SYNC_WRITE_KEYS=1 swift test --filter UnitTableTests and committing the list"

requirements-completed: [SYNC-R05]

duration: 50min
completed: 2026-10-09
status: complete
---

# Phase 28 Plan 14: App adapter for the unit table Summary

**A Core store that turns the preferences domain into a validated SyncSnapshot and unit payloads into preference writes, the alias rule for re-keyed items, model-based normalizers for appearance, groups and the icon, one list of excluded prefixes, and a lint that keeps every other writer of a synced key out.**

## What was built

- **SyncAlias**: `isAliased` and `aliasedUnits` for the families `ItemIcons`, `RevealOnChangeItems` and the `OpenItem:` hotkeys; a unit is aliased when `ItemIdentity.storedKey` maps its item key to another key with the learned owners. The re-key sites (`ItemIconStore.setChoice`, `ItemChangeWatcher.setRevealedOnChange`) are unchanged.
- **SyncDefaultsStore** (`@unchecked Sendable` struct over `UserDefaults` and a domain name): `snapshot(table:generation:baselineKeys:)` drops the excluded prefixes, projects with `SyncProjection.snapshot`, fills `known27` on generation 27 and marks aliased units including baseline-only ones; `apply(_:table:)` reports applied and skipped units and writes only through `SyncProjection.defaultsWrites`, only for keys with a synced class; `applyKnownApplications`; `generation`, `counterMirror` and `lastSyncedSeen` (read only, no function writes or removes `SettingsSyncLastSynced`); `flush()`. No logger.
- **SyncModelNormalizers** (app target, `@MainActor enum`): `make()` gives `SyncNormalizers` whose appearance, groups and icon closures decode with the models, encode canonically and refuse a value with fields this build does not know.
- **SettingsBackup.excludedKeyPrefixes** is `SyncUnitTable.excludedKeyPrefixes`.
- **.github/sync-synced-keys.txt** (38 keys) with `UnitTableTests.syncedKeyFileMatchesTable` (`SYNC_WRITE_KEYS=1` rewrites it).
- **sync-lint.py writer rule**: a write of a synced key (by case name or raw value, in `Defaults.set`/`removeObject`, `UserDefaults` set/removeObject/setValue, `CFPreferencesSetValue`) outside `WRITER_ALLOWED` fails; a new `MacOS27Layout` writer fails with a message that names the user paths of plan 28-16; self-test fixtures for each rule (44 in total).

## Verification

- `swift test --filter "AliasTests|DefaultsStoreTests"`: 18 tests pass. `swift test --filter UnitTableTests`: 11 pass.
- Full `swift test`: 959 tests in 114 suites; the only failures are the known timing suites (BlockingWork, SpacingRelaunch, Task timeout) and MainRunLoop (the same family, a 60 s time limit in the full run). No other failure.
- SwiftLint `--strict`: 0 violations in 244 files. `Scripts/typecheck-app.sh`: "==> holzBar type-checks". `strings-check.py`: 383 strings in 5 languages complete. `privacy-check.py logs` and `network`: pass. `sync-lint.py --self-test` and `sync-lint.py`: pass.
- `SettingsSyncPause.isPaused` is still `true`. Nothing built here is called from the app: the store and the normalizers are not referenced yet (plan 28-15 hosts them).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SyncApplyReport` did not exist**
- **Found during:** Task 1
- **Issue:** The interface names `SyncApplyReport (applied, skipped)`, but no earlier plan declared it.
- **Fix:** Defined it in `SyncDefaultsStore.swift` as two `Set<SyncUnitKey>`.
- **Commit:** 91a6c9a1

**2. [Plan arithmetic] `.github/sync-synced-keys.txt` has 38 lines, not at least 40**
- **Issue:** The acceptance criterion asks for at least 40 lines, but the keys whose class is not local are exactly 38 (27 whole, 2 JSON, 2 icon parts, 4 split families, `MacOS27Layout`, `LayoutProfiles`, `KnownApplications27`). The must-haves say `min_lines: 30`, which holds. The file is exactly the table; padding would fail its own test.
- **Commit:** 0a909bde

**3. [Plan wording] The icon unit's field is the image set, not raw image data**
- **Issue:** The plan says the unit's value holds the icon data and `CustomIconData.accepts` is applied to it. `IceIcon` stores the JSON of a `ControlItemImageSet`; only its custom case embeds bitmap data.
- **Fix:** The normalizer applies the model rule to the image set and the `CustomIconData` checks to each embedded bitmap (header only, through ImageIO).
- **Commit:** 622e6db8

### Touching Core/Sync

Only new files in `holzBar/Core/Sync` (`SyncAlias.swift`, `SyncDefaultsStore.swift`) and the plan's own tests; no existing Core/Sync file or test was edited. `sync-lint.py` was extended in a new section (rule documentation in the header, a block before `SELF_TEST`, two small edits in `self_test` and `main`), which may need a trivial merge if another worktree edits the script.

## Notes for later plans

- The normalizers use `MainActor.assumeIsolated`: the models' `Codable` conformances are main-actor isolated, and the table is used by the engine on the main actor. A call off the main actor would trap, which is the intent (a nil would read as an invalid value and keep a setting local silently). The app normalizers cannot be unit tested in the Core package (they name app models); they are covered by the type check only, so plan 28-15 or an app-level check should exercise them once.
- Order of a remote apply (analysis section 4.4): `apply`, `setGeneration`, `flush`, then persist the state; the store offers the three steps, the host sequences them.
- The writer lint allows `Concealer27`, `LayoutProfiles`, `SettingsBackup`, `Migration` and the store to write `MacOS27Layout`; plan 28-16 may narrow or extend `LAYOUT_WRITERS`.

## Known Stubs

None.

## Threat Flags

None. The store writes preferences only for validated, synced keys (T-28-33), the lint guards the writers (T-28-34), and neither the store nor the normalizers log (T-28-35).

## Self-Check: PASSED

- Files exist: SyncAlias.swift, SyncDefaultsStore.swift, AliasTests.swift, DefaultsStoreTests.swift, SyncModelNormalizers.swift, .github/sync-synced-keys.txt.
- Commits exist: 91a6c9a1, 622e6db8, 0a909bde.
