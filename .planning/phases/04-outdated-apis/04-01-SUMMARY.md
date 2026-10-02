---
phase: 04-outdated-apis
plan: 01
subsystem: system-apis
status: complete
tags: [cfpreferences, settings-sync, relaunch, nsworkspace, url-api, privacy]
requires:
  - "03-02: complete, draft PR #37 green"
provides:
  - "SpacingRelaunch.spacingPreferenceKeys / defaultSpacing / spacingPreferenceValue(forOffset:) (Core, tested)"
  - "Menu bar item spacing written through CFPreferences in the current host's global domain"
  - "SettingsSyncDevice.isFromThisMac(file:deviceID:computerName:) (Core, tested)"
  - "Settings sync by a stored per-Mac UUID plus SCDynamicStoreCopyComputerName"
  - "Relaunch.environment(previousPID:) / previousPID(in:) (Core, tested)"
  - "SettingsBackup.relaunch() through NSWorkspace.openApplication; AppDelegate waits for the previous instance"
affects:
  - "The sync file gains a deviceID field read by every Mac of the user"
  - "SettingsBackup.excludedKeyPrefixes gains SettingsSync (exports, imports, sync, Ice import)"
  - "AppDelegate.applicationDidFinishLaunching delegates setup to finishLaunching()"
tech-stack:
  added: [SystemConfiguration (system framework)]
  patterns:
    - "KVO of NSRunningApplication.isTerminated into an AsyncStream plus SpacingRelaunch.waitUntil(timeout:), now also used at launch"
key-files:
  created:
    - holzBar/Core/SettingsSyncDevice.swift
    - holzBar/Core/Relaunch.swift
    - Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift
    - Tests/HolzBarCoreTests/RelaunchTests.swift
  modified:
    - holzBar/Core/SpacingRelaunch.swift
    - Tests/HolzBarCoreTests/SpacingRelaunchTests.swift
    - holzBar/MenuBar/Spacing/MenuBarItemSpacingManager.swift
    - holzBar/Utilities/Constants.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/Utilities/SettingsBackup.swift
    - holzBar/MenuBar/MacOS27/ItemImageStore27.swift
    - holzBar/Main/AppDelegate.swift
decisions:
  - "API-04: spacing preferences are written and removed through CFPreferencesSetValue/CFPreferencesSynchronize (any application, current user, current host); a failed synchronize throws 'The menu bar item spacing could not be saved.'"
  - "API-03: a sync file's deviceID decides alone; only id-less files from older builds fall back to the computer name, and only when this Mac has a non-empty name"
  - "API-03: the SettingsSync key prefix is excluded from export, import, replace and sync so a copied id never makes two Macs ignore each other"
  - "API-02: relaunch opens a new instance through NSWorkspace with HOLZBAR_PREVIOUS_INSTANCE=<pid>; the new instance waits at most 10 s for that pid (same bundle id only) before it sets up; on failure the old instance stays and shows an alert"
  - "API-01: appending(path:) and path(percentEncoded: false) everywhere; settings file paths are logged as private"
metrics:
  duration: 18min
  completed: 2026-10-02
actuals:
  tokens: 6400
  tasks: 3
  commits: 3
plan_head_before: c0e8478b3f1bad3efb04a0108228f7ddf3713888
plan_head_after: 654c05d2d847383a3b6fa3010280aac47d8b55ee
---

# Phase 4 Plan 01: CFPreferences spacing, sync by device id, NSWorkspace relaunch and current URL APIs Summary

Spacing is written through CFPreferences instead of a `defaults` process found through `PATH` (API-04), settings sync tells Macs apart by a UUID kept on each Mac plus the computer name from `SCDynamicStoreCopyComputerName`, so the blocking host lookup is gone (API-03), holzBar relaunches itself through `NSWorkspace.openApplication` and the new instance waits up to 10 s for the old one to quit (API-02), and no soft-deprecated URL path API is left (API-01). PR #37 is green on 654c05d.

## What was done

### Task 1 (tracer): spacing through CFPreferences, commit 28b9713

- `SpacingRelaunch`: `spacingPreferenceKeys` (`NSStatusItemSpacing`, `NSStatusItemSelectionPadding`), `defaultSpacing = 16`, `spacingPreferenceValue(forOffset:)` (nil for 0). Three new tests.
- `MenuBarItemSpacingManager`: the key enum, `runCommand` (`/usr/bin/env defaults ...` through `Process`), `removeValue` and `setOffset` are gone. `writeSpacingPreferences()` sets or removes both keys with `CFPreferencesSetValue(..., kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)` and flushes with `CFPreferencesSynchronize`. Everything after it in `applyOffset()` (pauses, owner collection, relaunch, Control Center) is unchanged.
- `Constants`: `issuesURL` and `releasesURL` use `appending(path:)`.
- Tracer gate: verified end to end by the CI run after Task 3's push (test "No offset removes the spacing preferences" passed, build succeeded).

### Task 2: sync by a stored device id, current URL APIs, commit c0f28bc

- New `holzBar/Core/SettingsSyncDevice.swift` with `deviceIDKey` (`deviceID`), `deviceNameKey` (`device`) and `isFromThisMac(file:deviceID:computerName:)`; four tests in `@Suite("SettingsSyncDevice")`.
- `SettingsSync`: `deviceID` (created once as `UUID().uuidString` under `SettingsSyncDeviceID`), `computerName` (`SCDynamicStoreCopyComputerName(nil, nil)`); `push()` writes both; `newerSettings()` skips files `SettingsSyncDevice.isFromThisMac` attributes to this Mac; `iCloudDriveURL` uses `path(percentEncoded: false)`.
- `SettingsBackup.excludedKeyPrefixes` gains `"SettingsSync"` with a comment; both path log lines use `path(percentEncoded: false)` with `privacy: .private`.
- `ItemImageStore27`: all seven `appendingPathComponent` calls became `appending(path:)` (the folder with `directoryHint: .isDirectory`); locations unchanged.

### Task 3: NSWorkspace relaunch with a pid hand-off, commit 654c05d

- New `holzBar/Core/Relaunch.swift`: `previousInstanceKey` (`HOLZBAR_PREVIOUS_INSTANCE`), `waitTimeout` (10 s), `environment(previousPID:)`, `previousPID(in:)` (positive `Int32` only); three tests in `@Suite("Relaunch")`.
- `SettingsBackup.relaunch()`: `CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)`, then `NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration:)` with `createsNewApplicationInstance = true`, `addsToRecentItems = false` and the hand-off environment. The completion hops to the main actor: success terminates, an error is logged and shown ("holzBar could not restart itself. Quit holzBar and open it again.") and the app keeps running. No `Process`, shell or `synchronize()` left.
- `AppDelegate`: menu hiding, cursor property and the preview guard stay first; the conflicting-app check and permissions switch moved into `finishLaunching()`. When the environment names a running app with holzBar's bundle identifier, a task waits for its termination (KVO of `isTerminated` with `.initial, .new` into an `AsyncStream`, `SpacingRelaunch.waitUntil(timeout: Relaunch.waitTimeout)`), logs at debug level on timeout, then calls `finishLaunching()`.
- PR #37 body: API-01 to API-04 added to "Landed so far".

## CI

Head 654c05d: build (BUILD SUCCEEDED, 8 compiler warnings, none in a file this plan touched: HIDEventManager and ItemClicker27 AXUIElement Sendable, ScreenCapture deprecation), test (155 tests in 29 suites passed, up from 145; "No offset removes the spacing preferences", "Two Macs with the same name are told apart", Suite "SettingsSyncDevice" and Suite "Relaunch" passed), swiftlint (0 violations in 135 files), former-name: all success on the first run. No CI fix was needed.

## Reversibility

The sync file now carries `deviceID`. Older holzBar builds keep working (they compare `device`, which is still written), and newer builds accept name-only files from older ones, so undoing this means keeping both readers.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Correctness] Explicit `@Sendable` completion in `relaunch()`**
- **Found during:** Task 3
- **Issue:** `openApplication`'s completion runs on a background queue; a closure written inside a `@MainActor` method could be inferred main-actor isolated.
- **Fix:** the completion is marked `@Sendable` and hops to the main actor with `Task { @MainActor in }`.
- **Files modified:** holzBar/Utilities/SettingsBackup.swift
- **Commit:** 654c05d

Otherwise the plan was executed as written.

## Open human checks (on a Mac)

- Spacing: Settings, General, "Menu bar item spacing" +4, Apply: `defaults -currentHost read -globalDomain NSStatusItemSpacing` prints 20 (and `NSStatusItemSelectionPadding` 20); back to 0 and Apply removes both keys.
- Two Macs with the same computer name and sync on: a change on one is offered on the other within 5 minutes; exported settings files do not contain `SettingsSyncDeviceID`.
- Import and restart: Settings, Advanced, import a file, "Import and Restart": holzBar comes back once with the imported settings, one icon, and the hotkeys work (no registration failure in `log stream --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "Hotkeys"'`).

## Self-Check: PASSED

- FOUND: holzBar/Core/SettingsSyncDevice.swift, holzBar/Core/Relaunch.swift, Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift, Tests/HolzBarCoreTests/RelaunchTests.swift
- FOUND: commits 28b9713, c0f28bc, 654c05d
