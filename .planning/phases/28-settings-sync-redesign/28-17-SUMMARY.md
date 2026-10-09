---
phase: 28-settings-sync-redesign
plan: 17
subsystem: sync-ui
tags: [swift, swiftui, appkit, nsalert-sheet, string-catalog, localization]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-13 gate G1 (not fully passed; a second pass runs in parallel) and the engine's SyncView and SyncQuestion; 28-15 the host (SettingsSync, questionPresenter, SettingsSyncPendingFolderBookmark)"
provides:
  - SyncRowOrdering and SyncRowCategory (Core): deterministic row order by sidebar category, label and unit key
  - SyncStatusText (app): the status lines, tones, hint texts, row labels, value texts and the date format
  - SyncQuestionSheet, SyncQuestionRows (app): the NSAlert sheet and its rows
  - The quiet hint and status lines in Settings -> Advanced and in holzBar's menu
  - The Profiles pane footnote, the applicable-profiles list and the delete sentence
  - The sync texts of the UI contract in en, de, fr, it and rm, and the old texts removed
affects: [28-18 removing the pause and the UAT script]

actuals:
  tokens: 34600
  tasks: 3
  commits: 4
plan_head_before: 35d08171c6dfb6fd525666082a7caf65b9d4b8a1
plan_head_after: 997ef091b515cad525f6d7096fd66f51da8bb5f4 (the four code commits; the docs commit follows)

tech-stack:
  added: []
  patterns:
    - "The views render the engine's view and decide nothing: SyncStatusText turns SyncView into lines in the contract's order, the sheet turns SyncQuestion into rows and the pressed button into the engine's SyncAnswerRequest"
    - "An open sheet learns that a row was decided elsewhere without polling: SettingsSync.questionRevision counts engine steps, an ObservationLoop watches it, and SettingsSync.currentQuestion(of:) is compared with the shown dots"
    - "Choice enums gain a plain-string `title` next to their `localized` key, so a value text is never hard-coded in the sync code"

key-files:
  created:
    - holzBar/Core/Sync/SyncRowOrdering.swift
    - Tests/HolzBarCoreTests/Sync/QuestionOrderingTests.swift
    - holzBar/Utilities/Sync/SyncStatusText.swift
    - holzBar/Utilities/Sync/SyncQuestionSheet.swift
    - holzBar/Utilities/Sync/SyncQuestionRows.swift
  modified:
    - holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift
    - holzBar/MenuBar/ControlItem/ControlItem.swift
    - holzBar/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift
    - holzBar/Main/AppState.swift
    - holzBar/Resources/Localizable.xcstrings
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/Settings/Models/AdvancedSettings.swift
    - holzBar/Settings/Models/GeneralSettings.swift
    - holzBar/MenuBar/Shelf/HolzBarShelfDisplays.swift
    - holzBar/MenuBar/Shelf/HolzBarShelfLocation.swift

key-decisions:
  - "The row categories follow the plan and the UI contract literally (General, Advanced, Hotkeys, Appearance, Groups, Items, Menu bar arrangement, Profiles) and the unit grouping of the unit table (ShowOnHoverDelay and TempShowInterval are General, RevealRules are Items). The real sidebar of the Settings window is General, Menu Bar Layout, Menu Bar Appearance, Hotkeys, Advanced, and those two settings and RevealRules appear in the Advanced pane; the order is one enum, SyncRowCategory, if the maintainer wants it to follow the panes"
  - "Choose Settings… is shown next to Cancel while a join waits for its answer (chooseAfterJoin), so a user who closed the sheet can still back out; while a join reads the folder Cancel is the only button"
  - "Two engine lines had no text in the contract and got one, plain and secondary: skippedFiles (plural) and tooLargeToPublish"
  - "A profile row whose name and layout both differ reads 'Profile “x”: name and macOS 27 layout' (a third string beside the contract's two)"
  - "Labels the contract calls existing but that had none as a static text got a new string: Rehide interval, Spacer width, Low battery threshold; values App icon, Custom image, Custom icon, Not set, Changed, Deleted, On"
  - "A row counts as decided elsewhere when the unit is no longer a row of the engine's current question of the same kind, or the dots the sheet showed are not all live; Done writes nothing (no answer)"
  - "Return does nothing: no button of the sheet is the default, the first button's key equivalent is empty, Escape is the last button's"

patterns-established:
  - "A Core file that orders or categorizes units has an exhaustive switch over Defaults.Key, so a new key does not compile until it has a category"

requirements-completed: [SYNC-R08, SYNC-R09]

duration: long session
completed: 2026-10-09
status: complete
---

# Phase 28 Plan 17: The sync interface Summary

**The quiet hint, the status lines, the conflict and join sheet and the Profiles footnotes now render from the engine's view, in five languages: one sentence and one button, never a dialog by itself. Sync stays paused (`isPaused` is still `true`).**

## What was built

- **Tracer (Task 1): the hint and the status lines.** `SyncStatusText` (`holzBar/Utilities/Sync/`) turns a `SyncView` into the label stack of the sync row in the order of the contract: the folder line, then the join, the hint sentence and the bystander line, then the notes (waiting files, newer format, older holzBar, oversize icon, unreadable file, unusable value, and two lines the contract did not cover). Orange is used for exactly the folder that cannot be found and a sync file that cannot be read. `SettingsSyncToggle` shows one hint button before Change… (Choose Settings… or Restart, as the engine decided), hides Change… and Turn Off during a join, and keeps the paused note and the disabled state as they were. `ControlItem.createMenu` shows the header and one item for the three hint states only. The three counted lines and the skipped-files line have plural variations in all five languages; the old annotation is replaced by the contract's new one.
- **The question sheet (Task 2).** `SyncQuestionSheet` is an `NSAlert` shown with `beginSheetModal(for:)` on the Settings window, rows in an `NSHostingView` accessory 480 pt wide (the list scrolls above 240 pt, found by measuring the grid first). Rows come ordered by `SyncRowOrdering` (category, `localizedStandardCompare` of the label, unit key). Two-way rows show This Mac and Sync folder with the date as a second line (`Date.FormatStyle`, year only outside this year); rows with three or more values and every bystander row show one `.menu` pop-up with no default ("Choose a Value"), this Mac's own value marked "(this Mac)"; a hotkey clash is one sentence; a row decided on another Mac is dimmed and reads "Already decided on another Mac"; with every row decided the last button reads Done and nothing is written. Use and Keep stay disabled until every pop-up has a choice; the pop-up choice is what the answer writes whichever button is pressed. Use and Keep have `hasDestructiveAction`, none is the default, Escape is the last button. The bystander sheet has Use Chosen Settings and Later. The other Mac is named by a date only. AppState sets `settingsSync.questionPresenter`.
- **Profiles pane (Task 3).** `LayoutProfilesSection` lists `applicableProfiles`, takes the host, shows one footnote under the list while sync is on (the macOS 27 or the macOS 26 wording), and the delete confirmation gains "Your other Macs with macOS 27 delete it too." on macOS 27 with sync on.
- **Strings.** 429 entries, all complete in en, de (Swiss spelling), fr, it and rm. Removed: the old sheet body and the old annotation. The paused note stays until plan 28-18. Every string the sync code uses is now used; no stale sync entry is left (the 11 stale entries the check can find are older and not sync texts: permission explanations and navigation titles that are read through enum raw values).

## Verification

- `swift test` (full, SDKROOT 26.5 SDK, machine at load 28 to 44): `HolzBarCoreTests` 919 tests in 117 suites passed in 722 s, `HolzBarMacOS27CoreTests` 195 tests in 35 suites and `SharedCodeSigningTests` 3 tests passed; no failure (the timing suites passed too). The new `QuestionOrdering` suite has 8 tests.
- `Scripts/typecheck-app.sh`: "==> holzBar type-checks". SwiftLint `--strict`: 0 violations in 250 files.
- `python3 .github/scripts/strings-check.py`: "String Catalogs complete: 429 strings in 5 languages". A separate check of the catalog against the code (every key matched by a literal the code uses) leaves no stale sync entry.
- `privacy-check.py logs`: "Every log interpolation names its privacy"; `privacy-check.py network`: "No network code".
- `sync-lint.py`: "Sync code rules hold"; `sync-lint.py --self-test`: 62 fixtures passed.
- `Scripts/check-sync-app.sh`: "The sync host ran as two Macs on real files" (third run; see the deviations).
- `SettingsSyncPause.isPaused` is still `true` (D-12). The acceptance greps hold: `sync.view` in the pane, `questionPresenter` once in AppState, `beginSheetModal` once and no `runModal` in `holzBar/Utilities/Sync/`, `hasDestructiveAction` twice, `applicableProfiles` in the Profiles pane, the new delete sentence in the pane and the catalog, and 0 hits for the old sheet body.

## Deviations from Plan

### Auto-fixed Issues

None needed beyond the additions below.

### Rule 2 - missing functionality that the contract did not word

1. **Two status lines without text.** The engine's view has `skippedFiles(Int)` and `tooLargeToPublish`; the contract's table has no row for them. They got plain secondary sentences ("holzBar skipped %lld sync files in the folder because there are too many." with plurals, and "This Mac's settings are too large to sync. The folder keeps the previous ones.").
2. **A third profile label** ("name and macOS 27 layout") for a row where both differ.
3. **New labels and value words** listed in the key decisions.
4. **Choose Settings… and Cancel together while a join waits for its answer.**

### Files touched outside the plan's list

- `holzBar/Utilities/SettingsSync.swift`: `questionRevision` (an observable step counter bumped in `refreshView()`), `currentQuestion(of:)`, and two comments. Needed so an open sheet notices rows decided elsewhere without polling (the contract's dimmed rows); no behavior of the host changes.
- `holzBar/Settings/Models/AdvancedSettings.swift`, `holzBar/Settings/Models/GeneralSettings.swift`, `holzBar/MenuBar/Shelf/HolzBarShelfDisplays.swift`, `holzBar/MenuBar/Shelf/HolzBarShelfLocation.swift`: a `title: String` next to each choice enum's `localized` key (the plan asked for a small label function next to an enum that has none instead of hard-coded text). Additive.
- None of the capture-wiring files of plan 28-16 (Layout pane move handlers, SectionRestore, Concealer27, profile apply paths, SettingsBackup import) and nothing in `holzBar/Core/Sync` besides the new `SyncRowOrdering.swift`, nothing in `Tests/HolzBarCoreTests/Sync` besides the new `QuestionOrderingTests.swift`, no script.

### Other

- **TDD (Task 2).** The ordering and its tests were written and committed together, not as a RED commit first; the ordering is a small pure function and the tests pin its contract (categories, order, stability under every permutation, equal labels).
- **The sheet and the pane were not run.** The machine has the Command Line Tools only (no Xcode), so SwiftUI and AppKit are type-checked, not drawn. The layout, the focus, VoiceOver and the German minimum-width checks are left to the UAT script of plan 28-18 (T-28-45). Known soft spots for that run: the initial focus on the first pop-up (`initialFirstResponder` is the hosting view and a `@FocusState` sets the pop-up), and the measured list height.
- **The acceptance one-liner "no entry lacks de, fr, it or rm" prints 2**, for the two entries that were already `shouldTranslate: false` (`holzBar`, `brew update && brew upgrade --cask holzbar`); `strings-check.py` skips them and passes.
- **`Scripts/check-sync-app.sh` is timing-sensitive under load.** With the load average between 11 and 44 (other agents' mutation gates) it failed twice on its 15 s waits ("the arrival of the file is heard and asks", "the change is captured and written") and passed on the third run; the plan changes nothing it exercises except the step counter.

## Known Stubs

None.

## Threat Flags

None. No new network endpoint, file access, stored key or schema. The sheet renders the other Mac as a date only (T-28-43), neither destructive button is the default and pop-up rows need a choice (T-28-44), and `strings-check.py` guards the five languages (T-28-45).

## Self-Check

PASSED

- Files exist: `SyncRowOrdering.swift`, `QuestionOrderingTests.swift`, `SyncStatusText.swift`, `SyncQuestionSheet.swift`, `SyncQuestionRows.swift`.
- Commits exist: ff96cc26 (Task 1), 81f7955f (Task 2), b59baa86 (Task 3), 997ef091 (cleanup); 4 commits since `plan_head_before`, measured from the ledger.
