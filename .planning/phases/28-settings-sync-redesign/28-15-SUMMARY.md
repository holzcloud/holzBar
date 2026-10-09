---
phase: 28-settings-sync-redesign
plan: 15
subsystem: sync
tags: [swift, host, file-io, state-store, file-coordination, lint, swift-testing]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-13 gate G1 (not fully passed; a second pass runs in parallel) and the engine; 28-14 SyncDefaultsStore and the app normalizers"
provides:
  - SyncFolderReader and SyncFolderWriter (Core): bounded read of holzBar/Macs, atomic write of the own device file only
  - SyncStateStore (Core): atomic State.plist, counter high-water file in Caches
  - SettingsSync (app): the host of the engine, replacing the old exchange class as a whole
  - SyncFileCoordination (app, nonisolated): coordinated reads and writes for iCloud Drive, watcher, presenter, downloads
  - The launch call in AppDelegate.init and the quit hook in applicationWillTerminate
  - The main-thread rule of sync-lint.py
  - Scripts/check-sync-app.sh: the app normalizers on the main actor and the host as two Macs on real files
affects: [28-16 arrangement capture and import wiring, 28-17 sheet and views, 28-18 removing the pause]

actuals:
  tokens: 40000
  tasks: 3
  commits: 3
plan_head_before: 7dec37c1bc3ef1d13ab89201ae7d8709d86262dd
plan_head_after: f6d3e4c11cd3b3da19349227b4a2fbff3569774e

tech-stack:
  added: []
  patterns:
    - "The host feeds events to SyncEngine.handle and queues the effects of each step with the state of that step; one pump carries them out strictly in order, a result that comes back from a read or a write goes to the front of the queue"
    - "Two serial queues: the folder (time limits, may stall on a provider) and the state file plus the preferences flush (local files only, never stalls)"
    - "A launch that blocks does so only for the state file, the persist and one folder read of at most a second; everything else waits for performSetup"
    - "A path is made without a trailing slash before lstat: a trailing slash makes lstat follow a symbolic link"

key-files:
  created:
    - holzBar/Core/Sync/SyncFolderAccess.swift
    - holzBar/Core/Sync/SyncStateStore.swift
    - Tests/HolzBarCoreTests/Sync/FolderAccessTests.swift
    - Tests/HolzBarCoreTests/Sync/StateStoreTests.swift
    - holzBar/Utilities/Sync/SyncFileCoordination.swift
    - Scripts/check-sync-app.sh
  modified:
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/Main/AppDelegate.swift
    - holzBar/Main/AppState.swift
    - holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift
    - holzBar/MenuBar/ControlItem/ControlItem.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Core/SettingsSyncDevice.swift
    - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift
    - .github/scripts/sync-lint.py
  deleted:
    - holzBar/Core/SettingsSyncPolicy.swift
    - Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift

key-decisions:
  - "A state file of a newer format makes the host inert for the session (no engine, no read, no write): the engine reads a newer Sigma as no state, so letting it run would join anew and persist over the newer file; SyncStateStore.persist also refuses to replace such a file (newerFormatOnDisk) as the second line of defense"
  - "No state file and sync off means nothing runs at launch (a Mac that never synced pays nothing); a Mac with a state file runs the engine while sync is off, so recordIntent still records the moves made meanwhile; Turn On… on a Mac without a state starts the engine then (runLaunch(creatingState:))"
  - "The state file and the preferences flush run on their own queue, apart from the folder queue: a provider that hangs stalls the folder queue, and the launch persist and the persists of every capture must not wait for it"
  - "A queued persist carries the state of its own step, and a persist or a device-file write whose generation is below what was persisted is skipped, so an older state never replaces a newer one and no file is written before its state was persisted"
  - "The folder identity the engine carries is the SHA-256 of the stored bookmark (a fixed token for the iCloud Drive default of 0.0.6); a folder the user chose is kept as SettingsSyncPendingFolderBookmark until its join commits, so a join survives a relaunch"
  - "A join holzBar started itself (a Mac from the pause, 0.0.6 or 0.0.7-beta1) never opens a sheet: only Turn On… or Change… set continuesIntoSheet, and only while the Settings window is on screen"
  - "The clock rule of sync-lint.py exempts the two I/O files of Core/Sync (the reader bounds its work with a deadline of the host's clock); the random, hashing and unsorted rules still apply to them"
  - "isEnabled of SettingsSync is private(set); the Turn Off button calls turnOff() (the one-line change the new hint type did not cover)"

patterns-established:
  - "A new Core file that does file I/O declares every top-level type and function nonisolated, or sync-lint fails"
  - "Scripts/check-sync-app.sh is the way to run the host before plan 28-18 removes the pause: it switches the pause off in a temporary copy only"

requirements-completed: [SYNC-R01, SYNC-R09]

duration: long session
completed: 2026-10-09
status: complete
---

# Phase 28 Plan 15: The host of the engine Summary

**The old exchange class is gone and a host that only builds events and carries out the engine's effects in order took its place: real folder reader and writer, an atomic state store, coordinated iCloud access, the launch in AppDelegate.init, and a lint rule that keeps file access off the main thread. Sync stays paused.**

## What was built

- **SyncFolderReader / SyncFolderWriter** (`holzBar/Core/Sync/SyncFolderAccess.swift`, Foundation only, nonisolated, blocking). The reader checks with `lstat` that the folder, `holzBar` and `Macs` are real folders, lists `Macs`, keeps only names `SyncDeviceFile.isDeviceFileName` accepts (conflict copies of a known Mac become `.conflictCopy(owner:)`), takes at most 64 files (most recently modified, then by name), skips a file that is not downloaded (`.dataless`), gives up at its deadline (`.pending`), reads with `SettingsSyncFile.readContents` (no link followed, 1 MiB) and decodes with `SyncDeviceFile.decode`. The legacy file is read only for a join or when the engine asks (metadata only for a `.metadata` request). The writer creates `holzBar/Macs` only inside an existing folder, writes a dot-prefixed temporary file (created exclusively, flushed), renames it onto `<MacID>.plist`, reads it back, refuses a link or a file where `holzBar` or `Macs` must be and an own file that is not what the session read.
- **SyncStateStore** (`SyncStateStore.swift`): `State.plist` under the support folder, replaced atomically (temporary file in the same folder, `F_FULLFSYNC`, rename); `load()` gives `missing` or the decode result (`forEngine` hands a missing file to the engine as unreadable); `persist` refuses to replace a newer-format file; `CounterHighWater` in the caches folder only grows.
- **SettingsSync** (`holzBar/Utilities/SettingsSync.swift`, replaced as a whole, `@MainActor @Observable`): `launch()`, `forAppState()`, `performSetup(with:)`, `settingsDidChange()`, `recordIntent(_:)`, `finishImport()`, `prepareForTermination()`, `chooseFolder()`, `turnOff()`, `cancelJoin()`, `restartWithWaitingSettings()`, `chooseSettings()`, `currentQuestion()`, `submit(_:)`, `refreshFolder()`, `protectedApplications`, `questionPresenter` and `SyncQuestionPresenting`; observable `isEnabled`, `isTurnedOnWhilePaused`, `folderDisplayName`, `view`, `hint`. Effects: `applyUnits`/`applyKnownApplications` through `SyncDefaultsStore`; `persist` as generation key and counter mirror, then high-water file, preferences flush, state file; reads and writes on the file queue with a 30 s limit (coordinated for iCloud Drive); one cancellable `Task` per timer (poll 15 min, 2 min on a network volume); `relaunch`; `requestDownload`; `storeIdentity`; `commitFolder`/`forgetFolder`. Observers (defaults, activation, wake, mount, unmount, a watcher on `holzBar/Macs` and a presenter for iCloud Drive) exist only while sync is on or a join is pending.
- **SyncFileCoordination** (`holzBar/Utilities/Sync/SyncFileCoordination.swift`, every type nonisolated): coordinated read and `.forReplacing` write with a time limit (the coordinator is cancelled), watcher, presenter, downloads, the places the host needs from `FileManager`.
- **Removed**: `SettingsSyncPolicy` with its tests and `SettingsSyncLayoutTests`; the file-contents decision of `SettingsSyncFile` (`Contents`, `contents(of:)`, layouts key, clock skew) and the file-against-computer-name check and the non-uid identity of `SettingsSyncDevice` with their tests. Kept in `SettingsSyncFile`: `modifiedKey`, `settingsKey`, `maximumFileSize`, `ReadResult`, `Refusal`, `readContents`, `isUsableFolder`, `isLocal`. No code of this build reads or removes a `SettingsSync…` key of an earlier build as evidence (`SettingsSyncLastSynced` is only read).
- **sync-lint.py**: the main-thread rule (file access in a main-actor sync type fails; Core/Sync and SyncFileCoordination accept it only when every top-level declaration is nonisolated), 15 fixtures for it and 3 for the I/O-layer exemption of the clock rule (62 fixtures in all).
- **Scripts/check-sync-app.sh**: builds the app module without Xcode in a temporary copy (pause off, state folders redirected, own preferences domain), runs the app normalizers on the main thread, and plays Mac A (from the pause: found, conflict with Keep, edit) and Mac B (join, apply at launch) on real files. Nothing outside temporary folders and its own domain is touched.

## Verification

- `swift test --filter "FolderAccessTests|StateStoreTests"`: 21 tests pass (FolderAccess 14 including the tracer, StateStore 7).
- Full `swift test` (machine at load 30): the three test targets pass, HolzBarCoreTests 911 tests in 116 suites, 416 s, no failure (the timing suites passed too).
- `Scripts/typecheck-app.sh`: "==> holzBar type-checks". SwiftLint `--strict`: no violation. `strings-check.py`: 383 strings in 5 languages complete. `privacy-check.py logs` and `network`: pass. `sync-lint.py --self-test` (62 fixtures) and `sync-lint.py`: pass.
- `Scripts/check-sync-app.sh`: passes ("The sync normalizers ran on the main actor", "The sync host ran as two Macs on real files").
- `SettingsSyncPause.isPaused` is still `true`. The acceptance greps hold: 18 uses of `SettingsSyncPause.isActive()` in the host; no `FileManager`, `NSFileCoordinator` or `contentsOf` in `SettingsSync.swift`; `fileComponents` only in `SettingsSyncLocation.swift` and `SyncFolderAccess.swift`; `SettingsSync.launch()` follows `migrateStoredProfileIdentities()` in `AppDelegate.init`; `SettingsSyncLastSynced` is never set or removed.

## Tracer (Task 1)

`FolderAccessTests.twoMacsExchangeASetting`: two `SyncDefaultsStore` suites, two state stores and one shared temporary folder, a hand-driven `SyncEngine.handle`. Mac A comes from the pause (stored ID, bookmark, a hash without the user ID, bookkeeping keys of 0.0.7-beta1, sync on) and founds the group; fresh Mac B joins with Turn On…, shows the Restart hint, and ends with A's value after Restart. The folder holds exactly the two device files and the legacy file; the legacy file is byte-identical with the same date; `SettingsSyncLastSynced` and every old bookkeeping key of A are unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] A trailing slash made lstat follow a symbolic link**
- **Found during:** Task 1 (the link tests failed)
- **Issue:** `URL.appending(path:directoryHint: .isDirectory).path(percentEncoded: false)` ends in `/`, and `lstat("link/")` follows the link, so a link where `holzBar` or `Macs` must be passed the check and a file there read as unreadable.
- **Fix:** every path of the reader, the writer and the state store goes through `SyncFolderLayout.path(of:)`, which strips the slash; `kind(atPath:)` strips it too.
- **Commit:** d5528983

**2. [Rule 1 - Bug] The first draft of the host erased the folder a join was started for**
- **Found during:** review of Task 2
- **Issue:** the cleanup of the pending folder ran at every step without a pending join, and the step that feeds the snapshot before `turnOn` has none yet, so the stored bookmark of the chosen folder was removed before the join began.
- **Fix:** the cleanup runs only when a step ends a join that was pending (and at launch, for a join that is gone).
- **Commit:** 3a041b70

**3. [Rule 1 - Bug] The first watcher missed files in `holzBar/Macs`**
- **Found during:** the app check (a file written by another Mac was not heard)
- **Issue:** after the launch the host watched the sync folder itself, which hears nothing that happens two levels below.
- **Fix:** the watch target (`Macs`, else `holzBar`, else the folder) is looked up on the file queue when the watcher starts and after every read.
- **Commit:** 3a041b70

### Plan wording that did not fit

- **`SyncFolderReader.read` and `SyncFolderWriter.write` have more parameters than the interface block lists.** The block has no way to say what to read of the legacy file or how many files, nor which counter a write publishes (the receipt needs it). Both gained defaulted parameters (`legacy`, `maximumFiles`; `counter`, `isDownloaded`) and a convenience overload that takes the engine's `SyncReadRequest` or `SyncWriteRequest`; calls with the listed labels compile unchanged. Plans 28-16 to 28-18 can use either form.
- **`SyncStateStore.Loaded`** is `missing` or `read(SyncStateDecodeResult)` with `forEngine`; `raiseHighWater(to:)` returns whether the floor is at least that value (discardable).
- **The lint exemption of the clock rule** for `SyncFolderAccess.swift` and `SyncStateStore.swift` was not in the plan: the interface block fixes `deadline: ContinuousClock.Instant?`, which the determinism rule forbids in Core/Sync.
- **`AppState.swift` and `Scripts/check-sync-app.sh` are not in the plan's file list.** `AppState` takes the host the launch built (`SettingsSync.forAppState()`); one line. The script is the app-level check the notes of plan 28-14 asked for.

## Notes for later plans

- **28-16 / 28-17:** `finishImport()` exists but `SettingsBackup.importFromFile` does not call it yet (that file is not this plan's); wire it before the relaunch that follows an import, together with the import intents. `recordIntent(_:)` is ready for the arrangement paths; `protectedApplications` is current after every step. `SyncQuestionPresenting` is declared in `SettingsSync.swift`; set `questionPresenter` and the host shows the sheet through `chooseSettings()`. A join the user started opens it by itself while the Settings window is on screen; `currentQuestion()` falls back to the bystander question.
- **28-17:** the views read `view` (hint and status lines), `hint`, `folderDisplayName`, `isEnabled`; the Turn Off button now calls `turnOff()`. The strings of the old alert ("Which settings should holzBar use?", "Use Settings from Sync Folder", …) are no longer used in code; their catalog entries are stale until the new sheet uses or removes them.
- **28-18:** removing the pause needs `SettingsSyncPause.isPaused = false` and nothing else in this host; run `Scripts/check-sync-app.sh` first (it does the same in a copy). The privacy document should list `SettingsSyncPendingFolderBookmark` (a new stored key, excluded from export by the `SettingsSync` prefix) and the files `holzBar/Sync/State.plist` (Application Support) and `holzBar/Sync/CounterHighWater` (Caches).
- **The normalizers (28-14 risk):** the host builds the unit table and takes every snapshot on the main actor, and no code that runs off the main thread touches the table (the reader, the writer and the state store never do). `Scripts/check-sync-app.sh` exercises the normalizers once on the main thread and the host's snapshots exercise them again.
- **Quit:** `prepareForTermination()` is called from `applicationWillTerminate` and waits at most 2 s for the own file; it persists before it writes.
- **iCloud Drive coordination** is exercised only by the type check (a Mac without an iCloud account cannot run it here): the coordinated read covers `holzBar/Macs`, the coordinated write covers the own file with `.forReplacing` and the host's presenter; both are cancelled after the time limit.

## Files touched outside holzBar/Core/Sync and Tests/HolzBarCoreTests/Sync

Inside them: only two new files and their tests (`SyncFolderAccess.swift`, `SyncStateStore.swift`, `FolderAccessTests.swift`, `StateStoreTests.swift`). No existing file of either folder was edited, so nothing conflicts with the second G1 pass. Outside them (all named in the plan except `AppState.swift` and the script): `SettingsSync.swift`, `SyncFileCoordination.swift`, `AppDelegate.swift`, `AppState.swift`, `AdvancedSettingsPane.swift`, `ControlItem.swift`, `SettingsSyncFile.swift`, `SettingsSyncDevice.swift` and their tests, `sync-lint.py`.

## Known Stubs

None.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: new-stored-key | holzBar/Utilities/SettingsSync.swift | `SettingsSyncPendingFolderBookmark` holds the bookmark of a folder the user chose until its join commits; it stays on this Mac (the `SettingsSync` prefix is excluded from export, import and sync) and is removed when the join ends |

The threats of the plan are mitigated as written: T-28-36 (no link followed, real folders only, size limit before parsing, strict names, 64 files, the writer refuses any destination but the own file; FolderAccessTests cover a link, a folder, an oversize and a damaged file), T-28-37 (one file queue with limits, a launch bounded to one second, dataless files never read, the lint rule), T-28-38 (the legacy file is only read; the tracer and the app check assert it is byte-identical and `SettingsSyncLastSynced` unchanged), T-28-39 (the host logs counts and enum names only; `privacy-check.py logs` passes).

## Self-Check: PASSED

- Files exist: SyncFolderAccess.swift, SyncStateStore.swift, FolderAccessTests.swift, StateStoreTests.swift, SettingsSync.swift, SyncFileCoordination.swift, Scripts/check-sync-app.sh; deleted: SettingsSyncPolicy.swift and its two test files.
- Commits exist: d5528983, 3a041b70, f6d3e4c1.
