---
phase: 28-settings-sync-redesign
plan: 03
subsystem: profiles
tags: [swift, layout-profiles, hotkeys, profile-identity, sha256, typecheck]

requires:
  - phase: 28-settings-sync-redesign
    provides: "D-04, D-05, D-12 decisions (CONTEXT.md); sync stays paused"
provides:
  - "Stable layout profile IDs (deterministic legacy derivation, random for new profiles) and a one-time, idempotent migration of profiles and profile hotkeys"
  - "Profile hotkeys keyed ApplyProfile:<profileID>; loading never writes the Hotkeys setting back"
  - "Generation-split profile save, apply(_:byUser:), ID-based rename/delete/bindings/undo"
  - "Scripts/typecheck-app.sh: whole-app type check with the Command Line Tools"
affects: [28-05, 28-09, 28-16]

actuals:
  tokens: 7800
  tasks: 3
  commits: 3
plan_head_before: ca75e120f96a2e7406eb94409a70cab9bcbef79a
plan_head_after: d729449057667bc33f495b9b74d03e3eccc77701

tech-stack:
  added: []
  patterns:
    - "Core enum with a pure migration function over raw JSON (unknown fields survive), run in AppDelegate.init before sync"
    - "Profile identity string passed through ProfileBinding.Profile.name"

key-files:
  created:
    - Scripts/typecheck-app.sh
    - holzBar/Core/ProfileIdentity.swift
    - Tests/HolzBarCoreTests/ProfileIdentityTests.swift
  modified:
    - holzBar/MenuBar/Profiles/LayoutProfiles.swift
    - holzBar/Main/AppDelegate.swift
    - holzBar/Core/HotkeyTarget.swift
    - Tests/HolzBarCoreTests/HotkeyTargetTests.swift
    - holzBar/Settings/Models/HotkeysSettings.swift
    - holzBar/Settings/SettingsPanes/HotkeysSettingsPane.swift
    - holzBar/Hotkeys/HotkeyActionPerform.swift
    - holzBar/Main/URLCommands.swift
    - holzBar/Main/HolzBarIntents.swift
    - holzBar/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift

key-decisions:
  - "Legacy profile ID = SHA-256 of 'com.holzcloud.holzBar.LayoutProfile:' + name, first 16 bytes, version 8 and RFC 4122 variant bits, uppercase UUID string (locked by D-05, one-way)"
  - "Duplicate names derive from name + '#2', '#3' in stored order, so the result is deterministic and idempotent"
  - "ProfileBinding keeps its API; LayoutProfiles passes the profile ID in its name field"

requirements-completed: [SYNC-R05, SYNC-R07]

duration: 35min
completed: 2026-10-07
status: complete
---

# Phase 28 Plan 03: Profile identity and hotkey companion fixes Summary

**Layout profiles carry a stable ID (deterministic from the name for existing ones, so two Macs agree), profile hotkeys follow the ID, hotkey loading no longer rewrites its setting, saves keep the other macOS generation's part, and every profile application says whether the user did it.**

## Performance

- **Duration:** about 35 min
- **Tasks:** 3 of 3
- **Files:** 3 created, 10 modified

## Accomplishments

- `ProfileIdentity` (Core): `legacyProfileID(forName:)`, `newProfileID()`, `migrate(profilesData:hotkeys:)`; JSON-level migration keeps unknown fields, re-keys only exact-name `ApplyProfile:<name>` hotkeys whose name belongs to a profile, is idempotent and leaves malformed data untouched (T-28-07). Nine tests.
- `LayoutProfiles.migrateStoredProfileIdentities()` runs in `AppDelegate.init` right after the previous-settings import and before `SettingsSync.pullIfNeeded()`.
- `LayoutProfile.profileID` (stored, `id` returns it); a rename keeps the ID and no longer moves a hotkey; `delete(profileID:)`, `profile(withID:)`, `apply(profileID:byUser:)`, `apply(named:byUser:)`, `applicableProfiles`; `profile(named:)` picks the smallest ID among exact matches; profiles sort by name then ID; bindings, bound application and undo go by ID.
- `saveCurrentLayout` records only the running generation's part: on macOS 27 the application sections and known applications, before 27 the item sections, keeping the other part of the existing profile with that ID.
- `apply(_:byUser:)`: Space and display bindings pass false; menu/Settings, hotkey, Shortcuts, holzbar:// pass true. The call into the paused old sync's layout counter was removed from `apply`.
- `HotkeysSettings.loadInitialState` no longer writes the Hotkeys setting (duplicate combinations are dropped at registration only); hotkeys of unknown profile IDs stay stored but unregistered (T-28-08). `name(of:)` returns the profile name by ID, else the existing string "Layout Profile".
- `Scripts/typecheck-app.sh`: copies `holzBar/` and `Shared/` to a temp dir, adds asset-symbol stubs, runs `swiftc -emit-sil -wmo` against the 26.5 SDK, prints `==> holzBar type-checks`; never writes into the repo. SwiftLint 0.65.1 portable binary installed at `$HOME/.cache/holzbar/swiftlint-0.65.1/swiftlint` (not committed).

## Task Commits

1. **Task 1 (tracer): profile IDs, migration, type-check script** - `b49c01c8`
2. **Task 2: profile hotkeys by ID, no write-back at load** - `7547ca4d`
3. **Task 3: generation-split save, apply(byUser:), ID-based rename/delete/bindings/undo, call sites** - `d7294490`

Note: `git rev-list ca75e120..HEAD` counts 4 because plan 28-01 committed (`0285d779`) in the same tree between my commits; `commits: 3` counts this plan's own commits.

## Verification

- `swift test --filter ProfileIdentityTests`: 9 tests passed. `--filter HotkeyTargetTests`: 4 passed. `--filter HolzBarCoreTests`: 452 tests in 63 suites passed.
- `Scripts/typecheck-app.sh` and SwiftLint `--strict` (with `TOOLCHAIN_DIR`): clean for all files of this plan (see Issues for the one parallel-plan caveat).
- `python3 .github/scripts/strings-check.py` and `python3 .github/scripts/privacy-check.py logs` exit 0.
- Acceptance greps: `migrateStoredProfileIdentities` precedes `SettingsSync.pullIfNeeded()` in AppDelegate; no `Defaults.set` in `loadInitialState`; no `moveHotkey` in LayoutProfiles; `byUser: true` appears in URLCommands, HolzBarIntents, MenuBarLayoutSettingsPane and HotkeyActionPerform; `SettingsSyncPause.isPaused` is still `true`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hotkeys load before the profiles, so the registration check cannot ask `appState.profiles`**
- **Found during:** Task 2
- **Issue:** `AppState` runs `settings.performSetup` (which loads hotkeys) before `profiles.performSetup`, so `profiles.profile(withID:)` would be empty at load and every profile hotkey would go unregistered.
- **Fix:** Added `LayoutProfiles.storedProfileIDs()` (decodes the stored profiles) and used it in `loadInitialState` for the registration check. `name(of:)` still uses `profiles.profile(withID:)` (runtime, after setup).
- **Files:** `holzBar/MenuBar/Profiles/LayoutProfiles.swift`, `holzBar/Settings/Models/HotkeysSettings.swift`
- **Commits:** `7547ca4d`, `d7294490`

**2. [Rule 3 - Blocking] `ProfileBinding` identifies profiles by a name string**
- **Fix:** Left `ProfileBinding` (not in the plan's file list) unchanged and passed the profile ID in its `name` field and the current profile's ID as `currentProfile`, with a comment.
- **Files:** `holzBar/MenuBar/Profiles/LayoutProfiles.swift`

### Other notes

- The hotkey behaviors "duplicate leaves the stored dictionary unchanged" and "unknown profile stays stored but unregistered" live in `HotkeysSettings` (app target, `@MainActor`, `Defaults`), which `swift test` cannot compile. They are covered by the acceptance grep and the type check, not by a unit test. `HotkeyTargetTests` was updated for ID-shaped keys.
- The type-check script printed the existing deprecation warning of `ScreenCapture.swift` (CGWindowList); out of scope.
- Task 2 alone leaves the app not compiling until Task 3 adds `apply(profileID:byUser:)`, `profile(withID:)` and `storedProfileIDs()`, as the plan states.

## Issues Encountered

- `Scripts/typecheck-app.sh` currently fails on the untracked work-in-progress `holzBar/Core/Sync/SyncReplica.swift` of a parallel plan (`cannot find 'SyncDeviceFile'`). With that folder excluded the app type-checks, so this plan's changes are clean. Re-run the script once 28-01/28-02 settle.
- Plain `swift test` (all targets) fails to build `Tests/SharedCodeSigningTests` ("plugin for module 'TestingMacros' not found") in this Command Line Tools environment. Those files are not touched by this plan; `--filter HolzBarCoreTests` runs and passes. `HolzBarMacOS27CoreTests` was not run for the same reason.
- Profile hotkeys that arrive after launch (a later sync) are not registered until the hotkeys load again; plans 28-09/28-16 own that wiring.

## Known Stubs

None.

## Threat Flags

None. T-28-07 to T-28-09 and T-28-SC are mitigated as planned (malformed input leaves data unchanged and is tested; unknown-profile hotkeys unregistered; profile names and IDs logged `.private`; SwiftLint binary from the official 0.65.1 release, outside the repository).

## Self-Check: PASSED

Files exist: Scripts/typecheck-app.sh, holzBar/Core/ProfileIdentity.swift, Tests/HolzBarCoreTests/ProfileIdentityTests.swift. Commits `b49c01c8`, `7547ca4d`, `d7294490` are on `planning/sync-redesign`.
