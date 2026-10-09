---
phase: 28-settings-sync-redesign
plan: 04
subsystem: sync
tags: [swift, unit-table, projection, identity, counters, swift-testing]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-01 data model (SyncValue, SyncReplica, SyncState, SyncDeviceFile) and 28-03 profile IDs and ApplyProfile:<profileID> hotkeys"
provides:
  - SyncUnitTable version 1 with an exhaustive class for every Defaults.Key (R-CLASS-1)
  - SyncNormalizers (canonical JSON) and SyncProjection (snapshot, validated minimal defaults writes, legacy mapping)
  - macOS 27 families l27, prof and the known27 set, scoped to macOS 27
  - SyncIdentity (identity decision, counters, reuse check, collision signals, lasting refusals, re-identification)
  - SettingsSyncDevice.hardwareHash(of:uid:salt:) bound to the user ID
affects: [28-07 engine, 28-08, 28-09, 28-14 app adapter, 28-18 privacy doc]

actuals:
  tokens: 26500
  tasks: 3
  commits: 3
plan_head_before: f953cdb76096d32e41d923bc7877793386ebf9b1
plan_head_after: 70cf27988e6d9e310cf9607335c0d159ea96f5f9

tech-stack:
  added: []
  patterns:
    - "keyClass(_:) is one exhaustive switch over Defaults.Key without default, so a new key does not compile until it has a class"
    - "Per-value validation on the way into the defaults: an invalid unit is skipped, never the whole dictionary (F-59)"
    - "A local value is clamped to its number rule before comparing; a remote value out of range is invalid, not clamped, so no apply/capture ping-pong"
    - "Profile writes edit LayoutProfiles as JSON, so the macOS 26 part, bindings and unknown fields survive"

key-files:
  created:
    - holzBar/Core/Sync/SyncUnits.swift
    - holzBar/Core/Sync/SyncNormalizers.swift
    - holzBar/Core/Sync/SyncProjection.swift
    - holzBar/Core/Sync/SyncIdentity.swift
    - Tests/HolzBarCoreTests/Sync/UnitTableTests.swift
    - Tests/HolzBarCoreTests/Sync/ProjectionTests.swift
    - Tests/HolzBarCoreTests/Sync/IdentityTests.swift
    - Tests/HolzBarCoreTests/Sync/CounterTests.swift
  modified:
    - holzBar/Core/SettingsSyncDevice.swift
    - Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift

key-decisions:
  - "The synced set is 27 whole settings units, HolzBarIcon (image plus template flag, cap 256 KiB of image data), appearance and groups (64 KiB), four split families, l27, prof and the known27 set; everything else is local with a reason"
  - "The HolzBarIcon unit value is a dictionary with icon (data) and template (bool); either may be absent, an empty dictionary is invalid"
  - "Hotkey values are JSON data; a cleared hotkey stores JSON null and is a valid value; a hotkey item whose storage key is no known HotkeyTarget is relayed, never applied"
  - "RevealOnChangeItems projects marked items as true only; apply true adds, deletion or false removes; the stored array is written sorted"
  - "l27 absent is the value 0 (localValue); applying 0 or a deletion removes the entry, the stored dictionary stays a dictionary even when empty"
  - "Applying prof keeps itemSections, bindings and unknown fields, appends unknown IDs with empty itemSections, sorts by name (localizedStandardCompare) then ID like LayoutProfiles"
  - "known27 is also addressable as the descriptor .whole(known27) with isSet, only to answer isAuthoredHere/isApplicableHere; it holds no register entries"
  - "A missing hash and a uid-less hash both rotate the identity once (legacy ID kept); a malformed stored ID rotates too"
  - "reidentified resets the published record because the own file under the new ID does not exist yet; replica, applied, baseline and the counters stay"
  - "Legacy ApplyProfile:<name> hotkeys are dropped from the legacy mapping, because they are keyed by name and the units are keyed by profile ID"

patterns-established:
  - "A present value that cannot be represented as a SyncValue projects to SyncProjection.unrepresentable, which no unit accepts, so it is kept local as invalid instead of looking absent"

requirements-completed: [SYNC-R02, SYNC-R05, SYNC-R06, SYNC-R07]

duration: 45min
completed: 2026-10-07
status: complete
---

# Phase 28 Plan 04: Unit table, projection and identity Summary

**Unit table version 1 (every Defaults.Key classified by an exhaustive switch), validated defaults-to-units projection with the macOS 27 families, and a uid-bound identity with counters, reuse check and collision rules, all pure Core functions.**

## What was built

- **SyncUnits.swift**: `SyncGeneration`, `SyncKeyClass`, `SyncLocalReason`, `SyncUnitDescriptor`, `SyncUnitTable.version1`. Descriptors carry the stored keys, the cap (with a per-unit `size(of:)`), the item limit of families, the generation scope and a validate closure. `descriptor(for:)` is `nil` for units this build does not know (and for unknown RevealRules entries and unknown hotkey actions), so they are relayed and never applied. `excludedKeyPrefixes` lists the prefixes that never sync.
- **SyncNormalizers.swift**: canonical JSON (sorted keys, container only) for appearance and groups, a structural check for the icon unit. The app swaps in model-based normalizers in plan 28-14.
- **SyncProjection.swift**: `snapshot`, `localValue`, `defaultsWrites`, `knownApplicationsUnion`, `knownApplications(in:)`, `units(fromLegacySettings:)`. Writes return only keys that change; `nil` removes a key.
- **SyncIdentity.swift**: `check`, `nextCounter`, `suspectReusedDots`, `collisionSignals`, `isLastingRefusal`, `reidentified`.
- **SettingsSyncDevice**: `hardwareHash(of:uid:salt:)` (SHA-256 of salt, UUID bytes, uid as 4 big-endian bytes) and `identity(storedHash:salt:hardwareID:uid:)`; the uid-less functions stay to read old hashes.

## Verification

- `swift test` (whole package): 616 tests in 77 suites pass (plus 195 and 3 in the other two test targets). The filtered runs `ProjectionTests`, `UnitTableTests`, `IdentityTests`, `CounterTests`, `SettingsSyncDeviceTests` pass.
- SwiftLint `--strict` is clean for every new file. `SettingsSyncDeviceTests.swift` has one `file_header` violation that existed before this plan (the file never had the header comment); left alone.
- `keyClass` has no `default:`; `grep SettingsSyncPause holzBar/Core/Sync/` prints nothing (D-12).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1 commit already holds the full projection code**
- **Found during:** Task 1
- **Issue:** The tracer's three Core files are one design (every key class, every projection), so splitting Task 2's code out of them would have meant writing half-classes first.
- **Fix:** Task 1 (d4c3171c) commits the complete Core code with the tracer tests; Task 2 (c4104e29) adds the remaining behavior tests, the R-CLASS-1 test and one fix (`l27` sections are written as `Int`, not `Int64`).
- **Files modified:** holzBar/Core/Sync/SyncProjection.swift
- **Commit:** c4104e29

**2. [Rule 2 - Missing critical functionality] Descriptor size measure and item validation**
- **Found during:** Task 2
- **Issue:** `cap` alone cannot say that the 256 KiB limit counts the icon image and not the dictionary envelope, and families need to refuse bad item keys and unknown reveal-rule entries.
- **Fix:** `SyncUnitDescriptor.size(of:)` / `isOverCap(_:)` and a `validate(item, value)` closure; item keys must be non-empty and at most 1,024 UTF-8 bytes; `descriptor(for:)` is `nil` for unknown RevealRules entries and hotkey actions.
- **Files modified:** holzBar/Core/Sync/SyncUnits.swift
- **Commit:** d4c3171c

**3. [Rule 1 - Bug] Test fixtures used a modifier value holzBar rejects**
- **Found during:** Task 1
- **Issue:** First test fixtures used modifier bits 256, which `HotkeyStorage.isValid` correctly refuses (bits 0 to 3 only).
- **Fix:** Fixtures use 8 (command).
- **Commit:** d4c3171c

**Total deviations:** 3, none changing the plan's behavior.

## Notes for the following plans

- `commits: 3` is measured with `git log --grep "(28-04)"`; `plan_head_before..HEAD` also contains 28-06's commit because 28-05/28-06 commit to the same branch in parallel.
- 28-14 must replace `SyncNormalizers.appearance` and `itemGroups` with model-based ones and feed `SyncProjection` real defaults; `SettingsSync…` identity code must switch to the uid-bound hash and `SyncIdentity.check`.
- The engine decides what to do with `SyncProjection.unrepresentable` values: they fail every validator, so mark the unit `localOnly(.invalid)`.
- `known27` merges through `SyncReplica.sets["known27"]`; `SyncProjection.knownApplications(in:)` feeds it and `knownApplicationsUnion` writes it back.

## Known Stubs

None.

## Threat Flags

None. The new surface (values from other Macs into defaults) is the one T-28-10 covers: every value passes `SyncUnitDescriptor.validate` and the cap before `defaultsWrites` produces a write, and keys without a synced class cannot be written.

## Self-Check: PASSED

Files exist: SyncUnits.swift, SyncNormalizers.swift, SyncProjection.swift, SyncIdentity.swift, the four new test files. Commits d4c3171c, c4104e29, 70cf2798 are on the branch.
