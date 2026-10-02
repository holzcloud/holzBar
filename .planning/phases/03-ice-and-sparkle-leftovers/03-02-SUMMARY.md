---
phase: 03-ice-and-sparkle-leftovers
plan: 02
subsystem: repository-hygiene-and-logging
status: complete
tags: [cleanup, dead-code, pbxproj, logging, settings-backup]
requires:
  - "03-01: complete, draft PR #37 open"
provides:
  - "Repository without the Ice README media, Resources/Icon.png, RunLoopLocalEventMonitor and ObjectStorage"
  - "project.pbxproj without the Copy to Applications stub phase and without ENABLE_USER_SELECTED_FILES"
  - "ItemCache read only through its subscript"
  - "Click bridge logger through Logger(category:); no subsystem string literal left"
  - "Commented SU exclusion in SettingsBackup"
affects:
  - "Every build: one warning fewer (9 to 8)"
tech-stack:
  added: []
  patterns:
    - "Core (SwiftPM) code derives the logger subsystem from Bundle.main.bundleIdentifier like Shared's Logger(category:)"
key-files:
  created: []
  modified:
    - holzBar.xcodeproj/project.pbxproj
    - Scripts/install.sh
    - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
    - holzBar/MenuBar/LayoutBar/LayoutBarContainer.swift
    - holzBar/MenuBar/MenuBarItems/MenuBarItemImageCache.swift
    - holzBar/MenuBar/Search/MenuBarSearchPanel.swift
    - holzBar/MenuBar/Shelf/HolzBarShelf.swift
    - holzBar/Events/HIDEventManager.swift
    - holzBar/MenuBar/MacOS27/Core/ConcealmentController27.swift
    - holzBar/Utilities/SettingsBackup.swift
  deleted:
    - Resources/rearranging.mov
    - Resources/rearranging.gif
    - Resources/Icon.png
    - holzBar/Events/RunLoopLocalEventMonitor.swift
    - holzBar/Utilities/ObjectStorage.swift
decisions:
  - "LEFT-04: unused media, dead types, the echo-only Copy to Applications phase, ENABLE_USER_SELECTED_FILES and ItemCache.managedItems(for:) removed"
  - "LEFT-07: the click bridge logs through Logger(category:); ConcealmentController27 derives its subsystem from the bundle because the Core package cannot see Shared/"
metrics:
  duration: 10min
  completed: 2026-10-02
actuals:
  tokens: 4200
  tasks: 3
  commits: 3
plan_head_before: ad4334d6de4d7da3ea35354349a87f74cf1662c7
plan_head_after: 4ad4304ead4e63065e2bf69f42b708c9f5cb860d
---

# Phase 3 Plan 02: Unused files, dead code, the stub build phase and one shared logger Summary

The original Ice README media (about 15.7 MB; `Resources/` went from 21 MB to 5.1 MB), `Resources/Icon.png`, two dead types, the echo-only "Copy to Applications" phase and a sandbox-only setting are gone, the item cache is read only through its subscript (LEFT-04), the click bridge logs through `Logger(category:)` with no subsystem literal left, and the `"SU"` settings exclusion is explained (LEFT-07). PR #37 is green with one build warning fewer.

## What was done

### Task 1: unused media, dead types, stub phase, sandbox setting — commit d6ce648

- `git rm` of `Resources/rearranging.mov`, `Resources/rearranging.gif`, `Resources/Icon.png`, `holzBar/Events/RunLoopLocalEventMonitor.swift`, `holzBar/Utilities/ObjectStorage.swift` after `git grep` found no reference outside the files themselves.
- `project.pbxproj`: the `PBXShellScriptBuildPhase` `17F71BB62B880B4500905CBB` and its `buildPhases` line removed, both `ENABLE_USER_SELECTED_FILES = readonly;` lines removed; "SwiftLint" and "Embed XPC Services" untouched.

### Task 2: the item cache is read through its subscript — commit daaf5a8

- `ItemCache.managedItems(for:)` and its TODO removed; the six call sites (`LayoutBarContainer.swift`, `MenuBarItemImageCache.swift` x2, `MenuBarSearchPanel.swift`, `HolzBarShelf.swift` x2) read `cache[section]`, `itemCache[section]`, `itemCache[name]` and `itemCache[.visible]`; the parameterless `managedItems` property stays.

### Task 3: one shared logger, a commented SU exclusion — commit 4ad4304

- `HIDEventManager.swift`: `bridgeLogger = Logger(category: "ClickBridge27")`, doc comment kept.
- `ConcealmentController27.swift`: `Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "ConcealmentController27")` with a comment that the Core package cannot see `Shared/Utilities/Logging.swift`.
- `SettingsBackup.swift`: comment above `"SU"` (Sparkle updater keys of the original Ice; holzBar updates through Homebrew).
- Pushed once (12129ad..4ad4304, which also carried the 03-01 SUMMARY commit ad4334d) and updated the PR #37 body with LEFT-04 and LEFT-07.

## CI (PR #37, head 4ad4304)

| Job | Result |
|-----|--------|
| build | success, `** BUILD SUCCEEDED **`, `==> Acknowledgements: 5 license files in the app` |
| test | success, `Test run with 145 tests in 27 suites passed` |
| swiftlint | success, `Done linting! Found 0 violations, 0 serious in 133 files` (135 before; two Swift files deleted) |
| former-name | success |

Build warnings: 9 before (12129ad), 8 after (4ad4304). The "Run script build phase 'Copy to Applications' will be run during every build" warning is gone. The remaining ones are pre-existing: HIDEventManager `:6` and `:575` (the two the plan names), ItemClicker27 `:7` and `:76`, the ScreenCapture deprecation, two AppIntents metadata notes, "SwiftLint not installed". No warning in any other file this plan touched.

CI fixes: none needed; the push was green.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Stale comment in Scripts/install.sh**
- **Found during:** Task 1
- **Issue:** The script's header said it "Replaces the project's 'Copy to Applications' build phase", which no longer exists after this plan.
- **Fix:** The header now says it replaces the "Copy to Applications" build phase the project used to have; the explanation why such a phase cannot work stays.
- **Files modified:** Scripts/install.sh
- **Commit:** d6ce648

## Open human checks

- On the Mac (macOS 27): `log stream --level info --predicate 'subsystem == "com.holzcloud.holzBar" AND category == "ClickBridge27"'`, then click the clock while items are concealed; the bridge's timing lines still appear under holzBar's subsystem.
- Settings, Menu Bar Layout, the holzBar Shelf and the menu bar search still show the items of each section.

## Self-Check: PASSED

- The five deleted files are absent; d6ce648, daaf5a8 and 4ad4304 are on origin/claude/ice-fork-development-hzdl1d; all three task verify commands passed on 4ad4304.
