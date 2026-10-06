---
phase: audit-remediation-sync-fix
plan: sync-fix-r2
subsystem: settings-sync
tags: [sync, layout, beta1-compat, macos26, macos27]
requirements: [SA-05, F-02, F-60]
status: complete
key-files:
  created:
    - Tests/HolzBarCoreTests/SettingsSyncStateTests.swift
  modified:
    - holzBar/Core/SettingsSyncPolicy.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/MenuBar/MenuBarItems/SectionRestore.swift
    - holzBar/MenuBar/Profiles/LayoutProfiles.swift
    - Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
    - Tests/HolzBarMacOS27CoreTests/SectionLayout27Tests.swift
    - docs/release-notes/v0.0.7-beta2.md
    - docs/features.md
    - .planning/audit/REMEDIATION-2026-10-05.md
    - .planning/audit/remediation/sync-fix-SUMMARY.md
decisions:
  - "A joining Mac takes in the layout of its own written version like a newer one, so a kept layout is never recorded as synced without being applied."
  - "Keep This Mac's Settings writes only over the version the user answered (Local.keepsOver), an older one or this Mac's own."
  - "A version from another Mac that is not newer asks when it holds changes this Mac has not synced; it is never applied silently. The state keeps the digest of the version last synced (SettingsSyncVersionSettingsDigest), and such a version's date never becomes the last sync."
  - "A kept layout waits without pending (new action takeInLayout); only the layout is taken in, by Restart or at launch, and other changes keep syncing."
  - "The last eight synced layout digests are remembered (SettingsSyncRecentLayoutDigests); an unlisted layout equal to one of them is an old copy of this Mac's and is written over without a question."
  - "Before macOS 27, a bar save counts as the user's edit only when a saved section changed; reconciliation records where macOS put an item as holzBar's own placement."
  - "F-60 is not fixable from this side: the copy stays, is logged at notice level, and every case is documented."
  - "Write planning, state storage, the migration seed and the captured edit count live in Core and are tested."
metrics:
  completed: 2026-10-06
commits: 12
plan_head_before: 5699fec7705c9bfb270f81af0f9e154f491653ab
---

# Sync fix round 2: the review of round 1

A Mac that turns sync off and on before restarting still takes in a kept arrangement instead of later overwriting it. Another Mac's change dated before this Mac's last sync is asked about instead of being overwritten. "Keep This Mac's Settings" replaces only the version it asked about. A kept layout no longer pauses pushes. An old copy of this Mac's own layout from a beta 1 Mac no longer asks. Command-clicks near new items (macOS 26) and profiles applied again (macOS 27) no longer count as edits. F-60 is logged and fully documented. The remaining app glue moved into tested Core code.

Maintainer policy (2026-10-05):
- When two Macs' settings differ, holzBar asks.
- holzBar's own placements never count (SA-05).
- The other macOS version's layout is taken in silently.
- Nothing in the sync file is overwritten with a stale copy, and no change of the user's is lost or reverted silently (F-02, F-60).

## Commits

| Commit | Issue |
|---|---|
| `7f923e78` | Issue 13: the tests cannot catch regressions in the `SettingsSync.swift` wiring |
| `9cc17194` | Issue 1 (major): a Mac that re-joins before restarting records a kept layout as synced without applying it |
| `92302f58` | Issues 3 + 8: Keep This Mac's Settings writes over a version that arrived while the sheet was open |
| `4e2995bc` | Issue 10: after a write that keeps another Mac's layout, pushes stop and an ordinary change asks |
| `a8f59dd2` | Issue 2: a "not newer" version from another Mac is ignored and then overwritten |
| `a940db58` | Issues 6 + 11: a beta 1 Mac of the other macOS version triggers the question, and "Use" reverts to a stale copy |
| `92d34d08` | Issues 4 + 9 (bar): a Command-click without a move counts as an edit while an unsaved item exists |
| `5b107e81` | Issues 5 + 9 (profile): a macOS 27 profile counts as an edit without changing the layout |
| `fa10465a` | Issues 7 + 12: F-60, log and documentation |
| `5b301828` | Issue 2 follow-up: a not-newer version's date never becomes the last sync |
| `72859b02` | Docs: release notes, features, remediation record |
| this commit | This summary |

## Issues and fixes

### Issue 13: the tests could not see the app glue (minor), `7f923e78`

This was done first, because the later fixes build on it.

- `Local.layoutEdits` carries the count the decision saw. `State.recordWrite` and `State.recordAdoption` record that count, so the app can no longer pass a fresher one.
- `SettingsSyncPolicy.planWrite` returns the written settings, the layout digest to record and whether a kept layout waits. It replaces the app's own calls to `fileToWrite`, `syncedLayoutDigest` and `takesInKeptLayout`. The file's current layout is computed from the file, not passed in.
- `State.init(reading:)`, `State.changes(from:)`, `State.migration(reading:layouts:)` and `State.leaveFolder(forgetsLastSync:)` own the defaults keys, the migration seed and the turn-off/join/copied-Mac bookkeeping.
- New `SettingsSyncStateTests` pins the stored key names, the round trip and the migration reads. It also checks that an edit made between building the request and recording the result still counts, for both writes and adoptions, and covers `planWrite`.

### Issue 1: re-join before restart (major), `9cc17194`

`ownLayoutToTakeIn` now takes the `Version` and takes in a version this Mac wrote like a newer one (`version.isNewer || version.isFromThisMac`). A version holding this Mac's own layout still yields nothing through the digest check. The app passes `remote.version`, and the unused `RemoteVersion.isNewer` is gone. The new test runs the whole sequence:
1. Keep.
2. `leaveFolder` (as when sync is turned off and on).
3. Adopt, which takes the kept layout in.
4. Restart or launch, which takes it in.
5. A drag before then, which asks.

### Issues 3 + 8: Keep only over the answered version (minor), `92302f58`

`keepThisMac(over:join:)` stores the answered version's date. `makeRequest` puts it into `Local.keepsOver`. `keepsThisMac(over:local:)` allows the forced write only over this Mac's own version, the answered one or an older one. A later version goes through the usual rules, which ask when this Mac has changes. The join path passes the answered version the same way.

### Issue 10: a kept layout no longer pauses pushes (minor), `4e2995bc`

- New action `takeInLayout`, for this Mac's own version with a kept layout to take in:
  - Running without changes, and at every launch, only that layout is taken in (`keptLayoutToTakeIn`), and the user's other unpushed changes stay changes.
  - Running with changes, they are written as usual, keeping the layout.
  - After a layout change of the user's, holzBar asks.
- `recordWrite` and `recordAdoption` set no `pending` for this Mac's own version.
- `hint(for:version:)` bases the hint for it on layout edits only.
- `settingsToUse` and `State.recordUse` / `recordLayoutTakeIn` apply and record only the layout of an own version and keep the base, so other changes are still pushed after the restart.

### Issue 2: a "not newer" version asks (minor), `a8f59dd2` and `5b301828`

- `decide` asks about another Mac's version that is not newer when `isUnsyncedChange` holds:
  - its user settings differ from this Mac's base and from the version this Mac last synced, or
  - its layout for this macOS version differs from the one last synced.
- It is never applied silently: it may lack this Mac's own last change, which a silent apply at launch would revert. "Later" waits, Keep writes over it, and the hint is a choice.
- The digest of the version last synced (`State.versionDigest`, key `SettingsSyncVersionSettingsDigest`) is needed because after applying a version that lacks some of this Mac's keys, the base differs from the version's digest. Without it, holzBar would ask forever. `recordApplied` (launch apply and "Use") records the version's digest, and `markSynced` records the base. Without the key, as an earlier build leaves the state, the date rule decides until the next sync.
- Follow-up: `Version.syncedDate` keeps a not-newer version's date, which may lie far in the future, from becoming the last sync. Otherwise every later version of the other Macs would ask instead of applying.

This deviates from the review's proposal, which applied such a version when this Mac had no changes. Applying would silently revert this Mac's own last change in the conflict case the issue describes, so it asks instead.

### Issues 6 + 11: old copy of this Mac's own layout (minor), `a940db58`

- `State.recentLayouts` holds the last 8 layout digests this Mac wrote, applied, adopted or took in (key `SettingsSyncRecentLayoutDigests`). The list is kept when this Mac leaves the folder.
- An unlisted layout equal to one of them is an old copy of this Mac's: a Mac that kept it unchanged loses nothing. So `replacesUnlistedLayout` does not ask, `settingsToUse` never applies it, and `fileToWrite` writes this Mac's layout over it, listed.
- An unlisted layout this Mac never synced is still passed on and asked about.

### Issues 4 + 9, bar part (minor), `92d34d08`

- `countsAsSectionSaveEdit`: before macOS 27, a save counts only when an item that already had a saved section moved to another section.
- `performReconciliation` records the current section of candidates without a saved section that it leaves in place, as holzBar's own placement (`byUser: false`). It skips this while the user drags or a save is pending. A later move of the user's then changes a saved section and counts.
- With the default placement, new items were never stored. If only the first change were made, a user's first drag of such an item would no longer count, which is why both changes are needed.

### Issues 5 + 9, profile part (minor), `5b107e81`

`LayoutProfiles.apply` on macOS 27 calls `userChangedLayout()` only when `countsAsLayoutEdit` sees a change. A new `SectionLayout27` test checks that applying the same profile again is idempotent.

### Issues 7 + 12: F-60 (minor), `fa10465a`

The code stays: beta 1 deletes every key missing from a file it applies (`v0.0.7-beta1:holzBar/Utilities/SettingsBackup.swift:66-68`), so leaving the copy out would delete that Mac's layout. `WritePlan.insertsCopy` makes the app log a value-free notice when it adds the copy. The known issue and `docs/features.md` now cover deleted, damaged, recreated and beta 1-rewritten files.

## Tests

- `swift test --filter SettingsSync`: 120 tests in 6 suites (104 before this round).
- Full `swift test`: 469 + 196 + 3 tests pass.

New tests:
- `SettingsSyncStateTests` (10 tests): keys, round trip, migration, captured edits, `recordUse` / `recordLayoutTakeIn`, own adoption, recent layouts, not-newer dates, `leaveFolder`, `planWrite` with `insertsCopy`.
- In `SettingsSyncLayoutTests`:
  - re-join take-in
  - the take-in walk-through in the keep test
  - the older version from another Mac
  - the old copy of this Mac's own layout
  - section saves
- In `SettingsSyncPolicyTests`:
  - keep only over the answered version, and a version that arrived later
  - not-newer unsynced change
- In `ApplyingProfile27Tests`: re-applying a profile.

Mutation check: `syncfix-mutate.py` applied each mutation alone, re-ran the tests and restored the file. All 57 mutations are caught. One was missed at first (`Local` not copying `versionDigest` from the state); a new test now catches it. They covered:
- the captured edit count in `recordWrite` and `recordAdoption`
- `Local.layoutEdits`, `keepsOver`, `versionDigest` and `recentLayouts` copied from the state
- the `planWrite` file layout
- `leaveFolder`
- each storage key mapping and the migration reads
- the `isNewer || isFromThisMac` take-in (both halves)
- every condition of `keepsThisMac`
- the own-version `takeInLayout` / `writesChanges` choice
- `pending` set again on a kept write
- the own-version hint
- `settingsToUse`, `recordUse` and `recordAdoption` for own versions
- `syncedLayoutEdits` in `recordLayoutTakeIn`
- `isUnsyncedChange`: each clause, the own-version guard and the hint
- `recordApplied`'s version digest and `syncedDate`
- the recent-layouts check in `replacesUnlistedLayout` and in `fileToWrite`
- each `rememberLayout` call, the de-duplication and the limit
- `countsAsSectionSaveEdit`, with each part dropped

Not covered by unit tests, because they are app glue that cannot be compiled into the test package:
- `keepsOver` being set from the answered version
- the reconciliation storing unsaved sections
- the profile compare
- the notice log

They are checked by the app type-check and the two-Mac steps below.

## Gates

Before each commit:
- `appcheck.sh … syncfix` reported `ERRORS: 0`.
- `swift test --filter SettingsSync` passed. The CLT "TestingMacros plugin not found" flake was retried. The full `swift test` ran before the docs commit and before this one.
- `swiftlint lint --strict --quiet` printed nothing.
- The privacy checks (network, logs) and the strings check passed.
- The former-name grep found nothing.

No new user-facing strings.

## Deviations

- Issue 2 asks instead of applying when this Mac has no changes (see above), and needs a new state key.
- Issue 4 combines the review's two alternatives: only changed saved sections count, and reconciliation records unsaved sections as holzBar's own.
- Issue 10 adds an action (`takeInLayout`) instead of a `takeInModified` state field: whether an own version waits follows from the state already (`holdsLayoutToTakeIn`).
- An extra commit, `5b301828`, fixes the future-date case that issue 2's question opened up.

## Known risks

- Before macOS 27, a known item that macOS moved and reconciliation has not yet put back is still saved where macOS put it at the next Command-click, and that counts as an edit. Neither of the review's fixes covers this.
- A user's first drag of an item that appeared during a drag, before any reconciliation recorded it, does not count as an edit. The save still stores it; it syncs with the user's next change.
- After the update, until a Mac syncs once, `versionDigest` is missing and the old date rule applies to not-newer versions.
- A sync app that brings back a version this Mac already applied and then wrote over now asks. "Keep" rewrites this Mac's version. Before, the file silently stayed at the old version.

## Two-Mac test steps (round 2)

Use two Macs that sync the same folder, both on this build unless a step says otherwise. Check the layout in holzBar's Layout pane and the hint in Settings → Advanced. Steps A to H of round 1 below still apply. In round 1's step C.5, quitting and reopening now takes in the arrangement also when other changes are unpushed.

**I. Keep, then turn sync off and on before restarting** (issue 1), same macOS version:
1. On B, Command-drag an item and change "Show on hover".
2. On A, without touching the layout, change "Show on hover" the other way.
3. On A, choose "Choose Settings…" → "Keep This Mac's Settings". Do not restart.
4. On A, turn sync off and on again in Settings → Advanced. A shows the Restart hint.
5. Click Restart. A shows B's arrangement.
6. Alternatively, Command-drag on A before restarting. A asks.
7. Quit and reopen B. B keeps its arrangement.

**J. Change dated before the last sync** (issue 2):
1. Set B's clock about 10 minutes behind.
2. On A, change a setting and wait until B has applied it.
3. On B, change "Show on hover".
4. On A, the hint reads "Choose Settings…", not Restart, also after relaunching A. A's next change does not write over B's.
5. "Use Settings from Sync Folder" applies B's change; "Keep This Mac's Settings" keeps A's.
6. Set B's clock back.

**K. A version that arrives while the question is open** (issue 3):
1. Make A ask: both Macs change "Show on hover".
2. With the sheet open on A, change another setting on B and wait for it to reach A.
3. Click "Keep This Mac's Settings" on A. A does not write over B's new version: the hint returns as "Choose Settings…".

**L. An ordinary change after Keep** (issue 10):
1. After step I.3, toggle another setting on A. The hint stays Restart, and B receives the change.
2. Quit and reopen A. A takes in B's arrangement, and the toggle stays.

**M. Command-click next to a new item** (macOS 26, issue 4):
1. With "Restart" showing and the default new-items placement, start an app that adds a new menu bar item. Wait a few seconds.
2. Command-click an item without moving it. The hint stays Restart.
3. Command-drag the new item into Hidden. The hint becomes "Choose Settings…".

**N. Re-applying a profile** (macOS 27, issue 5): with "Restart" showing, apply the current layout profile again by its hotkey. The hint stays Restart.

**O. A Mac of the other macOS version still on 0.0.7 beta 1** (issues 6 and 7): A on macOS 27 with this build, C on macOS 26 with 0.0.7 beta 1.
1. On A, arrange L1 and let it write. Quit and reopen C; C now holds A's L1.
2. On A, arrange L2.
3. On C, change any setting. C rewrites the file with L1 unlisted.
4. On A, Command-drag again. There is no question, and the file holds A's layout as current. "Choose Settings…", if shown for anything else, never brings back L1.
5. F-60 (documented): delete `holzBar/Settings.plist` from the sync folder and change a setting on A. The log shows "The sync file had no layout for the other macOS version; wrote this Mac's copy of it…". C may get an older `ItemSections` at its next launch. Updating C first avoids this.

**P. A Mac of the same macOS version still on 0.0.7 beta 1:** round 1's step A still applies unchanged. A drag on A asks only while the file holds a layout B arranged that A never synced.

## Threat surface

No new network, file or permission surface. Two new defaults keys start with "SettingsSync", so they are never exported, imported or synced: `SettingsSyncVersionSettingsDigest` (a string) and `SettingsSyncRecentLayoutDigests` (at most 8 strings). Both are read with type checks. Logs carry no digests, ids or values.

## Self-Check: PASSED

- All eleven commits above exist on `audit-manual/sync-fix` after `5699fec7` (`git merge-base --is-ancestor`).
- All created and modified files exist.
- The gates passed before each commit. The full `swift test` passed before the docs commit and this one.

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
- Before this build, a not-newer version with different user settings, or with a different layout combined with a user layout edit on this Mac, is written over (the `!isNewer → write` rule from F-02). This is unchanged and needs clock skew around near-simultaneous writes. Fixed in round 2 (`a8f59dd2`): such a version now asks.

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
