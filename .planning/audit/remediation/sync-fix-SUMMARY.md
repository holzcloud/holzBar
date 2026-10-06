---
phase: audit-remediation-sync-fix
plan: sync-fix-r1
subsystem: settings-sync
tags: [sync, layout, beta1-compat, macos26, macos27]
requirements: [SA-05, F-02, F-60]
status: complete
key-files:
  created:
    - .planning/audit/remediation/sync-fix-SUMMARY.md
  modified:
    - holzBar/Core/SettingsSyncPolicy.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/MenuBar/MenuBarItems/SectionRestore.swift
    - holzBar/MenuBar/MacOS27/Concealer27.swift
    - Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
    - docs/release-notes/v0.0.7-beta2.md
    - docs/features.md
    - .planning/audit/REMEDIATION-2026-10-05.md
decisions:
  - "A layout of this Mac's macOS version that a sync file holds but does not list (0.0.7 beta 1) is passed on unchanged; only a user layout change replaces it, and that asks unless this Mac holds it or last synced it."
  - "This build marks the copy of the other macOS version's layout it writes for earlier builds (copiedLayouts), so no Mac takes it for an arrangement."
  - "A sync file over 1 MB is treated as unreadable (never written over, never applied); holzBar never writes one."
  - "Only a user layout change writes this Mac's layout, also for Keep This Mac's Settings; a kept layout of another Mac that this Mac has not taken in waits as its own written version, applied by Restart or at launch."
  - "The sync bookkeeping lives in SettingsSyncPolicy.State (Core), so its rules are unit tested."
metrics:
  completed: 2026-10-06
commits: 9
plan_head_before: d7c0106341ea8cec609d7f75d84d42f2940cdd91
---

# Sync fix round 1: the second SA-05 review's sync issues

An updated Mac no longer overwrites a layout that a Mac still on 0.0.7 beta 1 arranged. A sync file over 1 MB is left alone. "Keep This Mac's Settings" and writes over a version that is not newer keep another Mac's arrangement and take it in. Restart asks while a drag is unsaved. A Command-click without a move and an unsynced Mac's migration no longer count as synced or edited. The bookkeeping moved into tested Core code.

## Commits

| Commit | Issue |
|---|---|
| `0320c839` | The tests miss mutations of the layout state machine (race and wrap tests tautological) |
| `4ddb0e98` | A Mac on this build writes its old layout over a same-OS drag made on a Mac still on 0.0.7 beta 1 (blocker) |
| `b3da7f87` | A sync file over 1 MB counts as unusable and is overwritten unasked (blocker) |
| `a43c23f6` | "Keep This Mac's Settings" writes an untouched layout over another Mac's (major), and a "not newer" version's layout is recorded as synced without being applied (minor). One fix covers both |
| `29a73434` | Restart within about 1.5 s of a drag on macOS 26 loses that drag |
| `44d0347b` | Before macOS 27, a Command-click without a move counts as a layout edit |
| `7255b104` | The migration seed treats "sync switched on" as "layout came from the folder" |
| `6a61e075` | Docs: release notes, features, remediation record; F-60 for a missing or unusable file documented as a known issue |
| this commit | This summary |

## Issues and fixes

### 1. Beta 1 same-OS drag overwritten (blocker), `4ddb0e98`

Files written by 0.0.7 beta 1 have no `currentLayouts` key. This build dropped their layouts as stale, so it wrote its own layout over a beta 1 Mac's arrangement, listed as current, and the beta 1 Mac then applied it silently at launch.

- `fileToWrite`: when the user did not change this Mac's layout and the file holds an unlisted, unmarked layout under this Mac's key, that layout is passed on unchanged and unlisted.
- `syncedLayoutDigest(afterWriting:…)` records such a layout as synced only when it is the one this Mac last synced. Otherwise it records none, so the next user change still checks it.
- `Version.unlistedLayoutDigest` and `unlistedLayoutDigest(in:currentLayouts:copiedLayouts:layouts:)` carry the unlisted layout into the decision. `replacesUnlistedLayout` makes `decide` return `.ask` (or `.wait` after "Later"). It does this when the user changed this Mac's layout and the unlisted layout is neither this Mac's current layout nor the one it last synced. This covers running Macs, joining Macs and this Mac's own file.
- "Use Settings from Sync Folder" (`settingsToUse`) takes that layout in and records it as synced, so the next drag does not ask again. "Keep This Mac's Settings" writes this Mac's layout, as the user chose.
- New file key `copiedLayouts`: when this build writes its own copy of the other macOS version's layout for earlier builds (F-60), it marks the copy, and the mark is passed on. A marked copy is not counted as an arrangement and is not asked about; a Mac of that macOS version writes its own layout over it. Earlier builds ignore the key.

### 2. Sync file over 1 MB (blocker), `b3da7f87`

- `SettingsSyncPolicy.File(refusal:)` maps `.tooLarge` to `.unreadable`, so nothing is written over the file and nothing is applied. `.notRegularFile` stays `.unusable`.
- `write` refuses settings whose file would exceed `SettingsSyncFile.maximumFileSize` (`fitsSizeLimit(byteCount:)`). It logs a public, value-free message and retries with the next change.
- The release note now says that sync stops in this case and that a smaller icon makes it sync again.

### 3 and 6. Keep This Mac's Settings (major) and the "not newer" version (minor), `a43c23f6`

- `writesOwnLayout(_:)` is `editsLayout` only. `forcesWrite` no longer writes an untouched layout.
- `takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)`: a write that kept the file's current layout, when that layout is not the one this Mac last synced and not this Mac's own, leaves a layout to take in.
- `State.recordWrite(…, takesInLayout:)` then records this Mac's own layout as synced and sets pending. The app offers the written version with the quiet Restart hint.
- `decide` for this Mac's own version (`holdsLayoutToTakeIn`): without changes it returns `.apply` (Restart, or silently at the next launch). After a user layout change it returns `.ask` (`.wait` after "Later"), never `.write`. After a user-setting change only it writes, keeping that layout.

### 5. Restart within 1.5 s of a drag, `29a73434`

`hint(for:savesLayoutSoon:)` counts a pending section save (`MenuBarItemManager.needsSectionSave`) as a user layout edit. `restartWithWaitingSettings` therefore opens the question instead of relaunching. By the time the user answers, the arrangement is saved and "Keep This Mac's Settings" writes it. The imported other-OS layout not being synced is by design (D-02); no change.

### 7. Command-click without a move, `44d0347b`

`countsAsLayoutEdit(byUser:saved:before:)`. `saveSections` and `storeSections` compare the saved sections with those before and count only a real change. On macOS 27, `Concealer27.setSection` does the same.

### 8. Migration seed, `7255b104`

`initialLayoutEdits(hasLayout:syncs:hasSynced:)`: an existing layout counts as unchanged only when sync is on and the Mac has a last-sync date.

### 9. Test quality, `0320c839`

`SettingsSyncPolicy.State` holds the base, layout digest, edit counts, last sync and pending, with `countLayoutEdit`, `markSynced`, `recordAdoption` and (later) `recordWrite`. `SettingsSync` reads it once and stores only changed fields (`updateState`). The tautological race and wrap assertions were replaced by tests of the state. A new test covers the `comparedLayout` mutation from the review.

### 4. F-60 for a missing or unusable file (minor), documented, `6a61e075`

No code change. A write into a missing or unusable file still carries this Mac's copy of the other layout, or none. A beta 1 Mac of the other macOS version applies the file with remove-missing, so it can lose its layout or get an older one back. Skipping or asking would break setting up a new folder, and nobody can answer a question about another macOS version's layout. Known issue: update every Mac before changing or recreating the sync folder. Once every Mac runs this build, the copy is marked and harmless.

## Tests

`swift test --filter SettingsSync`: 104 tests in 5 suites (88 before). Full `swift test`: 453 + 195 + 3 tests pass. New or changed tests are in `SettingsSyncLayoutTests` (sync state, earlier-build layouts, the copy mark, kept layouts, the restart hint, the layout-edit predicate, the migration seed) and `SettingsSyncFileTests` (size limit, refusal mapping, `copiedLayouts` parsing).

Mutation check (scratch script `syncfix-mutate.py`: each mutation applied alone, the tests re-run, the file restored). All 39 mutations were caught, including:
- `comparedLayout` returning the local digest
- `&+` changed to `+`
- `markSynced` recording the current instead of the captured edit count
- `lastSynced` not taking the max
- every branch of `fileToWrite`'s pass-through and copy marks
- `replacesUnlistedLayout` with either comparison dropped
- the postponed wait
- `.tooLarge` mapped to `.unusable`, and the size limit off by one
- `writesOwnLayout` changed back to `forcesWrite || editsLayout`
- each condition of `takesInKeptLayout`, `holdsLayoutToTakeIn` and the own-file `.apply` / `.ask`
- `hint(for:savesLayoutSoon:)` ignoring the pending save
- `countsAsLayoutEdit` without either condition
- the migration seed changed back to `syncs` only

## Gates

Before each commit:
- `appcheck.sh … syncfix` reported `ERRORS: 0`.
- `swift test --filter SettingsSync` passed. The full `swift test` ran before the docs and summary commits.
- `swiftlint lint --strict --quiet` printed nothing.
- The privacy checks (network, logs) and the strings check passed.
- The former-name grep found nothing.

No new user-facing strings.

## Deviations

- Issues 3 and 6 share one fix and one commit (`a43c23f6`), since the take-in rule is the same.
- Beyond the review's proposal, a `copiedLayouts` file key keeps the beta 1 fix from asking spuriously between a macOS 26 and a macOS 27 Mac that both run this build (SA-05's no-cross-version-question rule).
- For issue 5, holzBar does not flush a pending section save at Quit (`applicationWillTerminate`): saving from a possibly stale item cache could record the old arrangement as the user's. A plain Quit within 1.5 s of a drag still loses the drag, as before. That is not a sync issue.

## Known risks

- While a Mac of the same macOS version is still on beta 1, each drag on an updated Mac asks if the beta 1 Mac rewrote the file with a different layout. Beta 1 pushes on any change, including its own placements. This is documented, and ends when every Mac is updated.
- Before this build, a not-newer version with different user settings, or with a different layout combined with a user layout edit on this Mac, is written over (the `!isNewer → write` rule from F-02). This is unchanged and needs clock skew around near-simultaneous writes.

## Two-Mac test steps

Use two Macs that sync the same folder. In each case, check the layout in holzBar's Layout pane and the hint in Settings → Advanced.

**A. Same macOS version, Mac B still on 0.0.7 beta 1, Mac A on this build** (blocker 1):
1. Both Macs sync. On B (beta 1), Command-drag an item into another section. B writes the file.
2. On A, wait for the check. There is no question and no hint, and A's layout is unchanged.
3. On A, change a non-layout setting (for example "Show on hover"). A writes the file.
4. Quit and reopen B. B keeps its drag.
5. On A, Command-drag an item. A asks "Which settings should holzBar use?". Choose "Later": nothing is written, and the hint shows "Choose Settings…".
6. Choose "Choose Settings…" → "Use Settings from Sync Folder". A restarts with B's arrangement, keeping any items B never saw.
7. Drag again on A. No question appears unless B changed its layout since.
8. Repeat step 5 and choose "Keep This Mac's Settings". After B relaunches, B shows A's arrangement.

**B. Mac C on this build with its own arrangement joins a folder last written by beta 1 B:** turn on sync on C. C asks; it does not write over B's layout.

**C. Keep This Mac's Settings** (major 3), both Macs on this build and the same macOS version:
1. On B, Command-drag an item and change "Show on hover".
2. On A, without touching the layout, change "Show on hover" another way.
3. A shows "Choose Settings…". Choose "Keep This Mac's Settings". The folder keeps B's arrangement with A's setting, and A shows the Restart hint.
4. Click Restart. A shows B's arrangement and keeps A's setting.
5. Alternatively, quit A and reopen it: the same happens silently.
6. Alternatively, Command-drag on A before restarting: A asks instead of writing.

**D. Sync file over 1 MB** (blocker 2): on A, set a custom holzBar icon of about 800 KB. The log shows "This Mac's settings are larger than the sync file may be…" and the file is unchanged. With a file over 1 MB placed by hand, B neither writes nor applies anything, and the log shows "Ignoring the sync file: tooLarge".

**E. Restart right after a drag** (macOS 26, minor 5): let B change a setting so A shows "Restart". On A, Command-drag an item and click Restart within a second. A asks instead of restarting, and "Keep This Mac's Settings" keeps the drag.

**F. Command-click without a move** (macOS 26, minor 7): with "Restart" showing, Command-click an item without moving it. The hint stays "Restart".

**G. Mixed macOS versions, both on this build:** A (macOS 26) and B (macOS 27). On B, change the sync folder (Change…) to an empty folder; B writes its copy of `ItemSections`, marked as a copy. Then on A, join it and Command-drag. There is no question about the layout, and A's layout becomes current in the file.

**H. Mac still on beta 1 of the other macOS version:** do not change or recreate the folder. This is the known issue (F-60).

## Threat surface

No new network, file or permission surface. The new file key `copiedLayouts` is an array of strings read with a type check (`as? [String]`); an unknown or wrong value is ignored. Logs carry no digests or ids.

## Self-Check: PASSED

- All eight commits above exist on `audit-manual/sync-fix` after `d7c01063`.
- All modified files exist.
- The gates passed before each commit.
