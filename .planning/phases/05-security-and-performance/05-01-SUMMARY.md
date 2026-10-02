---
phase: 05-security-and-performance
plan: 01
subsystem: settings-logging-storage
status: complete
tags: [security, settings, import, icloud, logging, caches, privacy]
requires:
  - "04-03: complete, PR #37 green on d23fec1"
provides:
  - "Defaults.Key (Core, CaseIterable) with an exhaustive settingsKind and importableKinds"
  - "SettingsSchema.matches(_:_:) and SettingsSchema.validated(_:kinds:) (Core, tested)"
  - "ItemImageFolder.moveLegacyFolder(from:to:fileManager:) (Core, tested)"
  - "Settings export, file import, iCloud pull and Ice import limited to holzBar's keys and kinds"
affects:
  - "Exports and the iCloud file no longer carry window frames, panel paths or other AppKit keys"
  - "Item images live in ~/Library/Caches/com.holzcloud.holzBar/ItemImages"
  - "URLCommands log lines name only the command"
tech-stack:
  added: []
  patterns:
    - "Exhaustive switch without default as a compile-time schema for stored keys"
    - "CFGetTypeID == CFBooleanGetTypeID to tell plist Booleans from numbers"
key-files:
  created:
    - holzBar/Core/SettingsSchema.swift
    - holzBar/Core/ItemImageFolder.swift
    - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
    - Tests/HolzBarCoreTests/ItemImageFolderTests.swift
  modified:
    - holzBar/Core/Defaults.swift (moved from holzBar/Utilities/Defaults.swift)
    - holzBar/Utilities/SettingsBackup.swift
    - holzBar/Utilities/Migration.swift
    - holzBar/Main/URLCommands.swift
    - holzBar/MenuBar/MacOS27/ItemImageStore27.swift
decisions:
  - "SEC-01: imported, synced and Ice settings are applied only for Defaults.Key raw values whose value has the key's declared kind; others are ignored, counted publicly and named privately in the log"
  - "SEC-01: currentSettings() (export and iCloud push) returns only Defaults.Key keys"
  - "SEC-02: URL commands log 'Performing <command>' only; an unparseable URL is logged without its text"
  - "SEC-03 (D-09): item images move once from Application Support to Caches/<bundle id>/ItemImages; the empty old holzBar folder is removed; a move error is logged privately (it contains the home path)"
metrics:
  duration: 7min
  completed: 2026-10-02
actuals:
  tokens: 6900
  tasks: 2
  commits: 2
plan_head_before: aa6d9969525650da15358bf2ab7537d352f11d8c
plan_head_after: 1dc43e57736f2c8d77e9e00d51d71bd2af8e81d2
---

# Phase 5 Plan 01: Settings validated by key and kind, URL logs without URLs, item images in the caches Summary

Settings from a file, from iCloud Drive or from Ice now pass a tested `SettingsSchema` against holzBar's own `Defaults.Key` list (each key declares its value kind in an exhaustive switch), URL commands log only their name, and captured item images live in the caches, moved there once from Application Support. PR #37 is green on 1dc43e5.

## What was done

### Task 1 (tracer): only known settings with the expected types, commit a0a2288

- `git mv holzBar/Utilities/Defaults.swift holzBar/Core/Defaults.swift`: the file now also builds in the SwiftPM target `HolzBarCore`. `Defaults.Key` is `CaseIterable`; `settingsKind` is a switch over all 59 keys without `default` (27 bool, 14 number, 12 data, 1 string, 2 string array, 3 dictionary, following the plan's table); `importableKinds` maps raw value to kind. No raw value changed.
- `holzBar/Core/SettingsSchema.swift`: `Kind` (bool, number, string, data, date, stringArray, dictionary), `matches(_:_:)` (bool is `CFBoolean`, number is an `NSNumber` that is not a `CFBoolean`), `validated(_:kinds:)` returning the accepted values and the sorted ignored keys.
- `SettingsBackup.currentSettings()` keeps only `importableKinds` keys (still minus the excluded prefixes), so exports and the iCloud file are holzBar's settings only. `apply(_:)` drops the prefixed keys, validates, removes current holzBar keys the accepted set lacks, writes the accepted values, sets `hasImportedPreviousSettings`, logs "Ignored N settings ..." (count public, names `.private`) and returns the ignored keys (`@discardableResult`).
- `MigrationManager.importPreviousSettingsIfNeeded()` writes only the validated part of Ice's prefix-filtered domain; the log line still reports imported of total.
- `@Suite("SettingsSchema")`, 8 tests, named as in the plan.

### Task 2: URL logs by command, item images in the caches, commit 1dc43e5

- `URLCommands.perform`: "Ignoring a URL that is not a holzBar command" (no URL) and "Performing <command.name>" (public); the unknown-command warning already named `command.name`. `absoluteString` is gone from the file.
- `holzBar/Core/ItemImageFolder.swift`: `Outcome` (nothingToMove, moved, removedOldCopy) and `moveLegacyFolder(from:to:fileManager:)`: no old folder does nothing; an existing destination wins and the old copy is removed; otherwise the destination's parent is created and the folder moved; afterwards the old folder's parent is removed when empty.
- `ItemImageStore27`: `directory` is `Caches/<Constants.bundleIdentifier>/ItemImages`; `legacyDirectory` (the only `applicationSupportDirectory` left in the app) is `Application Support/holzBar/ItemImages`; `init` moves the old folder first (outcome at debug level, error at error level with private details), then runs today's version check. Doc comment updated.
- `@Suite("ItemImageFolder")`, 5 tests in their own temporary folders, named as in the plan.
- Pushed once (`81bfbc0..1dc43e5`); PR #37 body lists SEC-01 to SEC-03 under "Landed so far" (the stray "Generated by" footer after the attribution lines was dropped so the body ends with them).

## CI

Head 1dc43e5: build (BUILD SUCCEEDED; the same pre-existing warnings, in HIDEventManager, ItemClicker27 and ScreenCapture, none in a file this plan touched), test (184 tests in 33 suites passed, up from 171; Suite "SettingsSchema" and Suite "ItemImageFolder" passed), swiftlint (0 violations in 139 files), former-name: all success on the first run. No CI fix was needed. The plan's Task 2 verify printed "05-01 green on 1dc43e5...".

Verification: `git grep 'persistentDomain(forName:' -- holzBar` shows `currentSettings()` and the Ice import (both behind the schema), plus two reads that write nothing: `Defaults.globalDomain` and the Ice import's check that holzBar's own domain is empty.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Privacy] Move errors are logged privately**
- **Found during:** Task 2
- **Issue:** a `FileManager` error names the full path, which includes the user's home folder name.
- **Fix:** `logger.error(... \(error, privacy: .private))`; the outcome is logged publicly at debug level.
- **Files modified:** holzBar/MenuBar/MacOS27/ItemImageStore27.swift
- **Commit:** 1dc43e5

**2. [Style] Case lists indented by four spaces**
- `settingsKind` lists continuation patterns 4 spaces deeper than `case` (SwiftLint `indentation_width`), not aligned under the first pattern.

Otherwise the plan was executed as written.

## Open human checks (on a Mac)

- Crafted import: export settings, add `NSQuitAlwaysKeepsWindows` (Boolean) and change `ShowOnHover` to a String with a plist editor, import. holzBar restarts with the other settings applied; `defaults read com.holzcloud.holzBar NSQuitAlwaysKeepsWindows` reports it does not exist; the log shows "Ignored 2 settings". A fresh export has no `NSWindow Frame` or `NSNavLastRootDirectory` entries.
- Image move (macOS 27, existing install): after updating, `~/Library/Caches/com.holzcloud.holzBar/ItemImages` holds the images, `~/Library/Application Support/holzBar` is gone, the holzBar Shelf shows item images at once.
- URL log: `log stream --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "URLCommands"'` while running `open "holzbar://profile/Work"` shows "Performing profile" and no URL.

## Self-Check: PASSED

- FOUND: holzBar/Core/Defaults.swift, holzBar/Core/SettingsSchema.swift, holzBar/Core/ItemImageFolder.swift, Tests/HolzBarCoreTests/SettingsSchemaTests.swift, Tests/HolzBarCoreTests/ItemImageFolderTests.swift
- MISSING as intended: holzBar/Utilities/Defaults.swift (moved)
- FOUND: commits a0a2288, 1dc43e5
