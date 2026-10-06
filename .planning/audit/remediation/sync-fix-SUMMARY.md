---
phase: audit-remediation-sync-fix
plan: sync-fix-r6
subsystem: settings-sync
tags: [sync, layout, keep, seen-record, beta1-compat, macos26, macos27]
requirements: [SA-05, F-02, F-60]
status: complete
key-files:
  created:
    - Tests/HolzBarCoreTests/SettingsSyncScenarioTests.swift
  modified:
    - holzBar/Core/SettingsSyncPolicy.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Utilities/SettingsSync.swift
    - Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncStateTests.swift
    - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
    - docs/release-notes/v0.0.7-beta2.md
    - docs/features.md
    - .planning/audit/REMEDIATION-2026-10-05.md
    - .planning/audit/remediation/sync-fix-SUMMARY.md
decisions:
  - "Keep This Mac's Settings over another Mac's answered version that lists another layout and is not newer than this Mac's last sync, or misses a write this Mac holds, writes this Mac's layout as current (keepsOwnLayoutOverStale); over a newer version that holds this Mac's writes it still keeps and takes in that version's layout."
  - "missesLastWrite compares every entry of Local.seen with the version's record, not only this Mac's own write."
  - "Over a missing file, or one without its macOS version's layout, a Mac without a layout edit writes its layout as a copy also when its last sync held that layout only as a copy (base noLayoutDigest, and it has synced), and when Keep answers another Mac's arrangement that the keep would have kept. The broader 'any Mac that has synced' rule was not taken."
  - "Keep over a missing file merges the answered version's record of writes."
  - "Each Mac's writes are recorded in its seen entry and lastWritten at least one second after the one before (writeStamp); the file's date stays the clock's."
  - "SettingsSyncFile.fileToWrite(plan:deviceID:modified:) builds the written file in Core."
metrics:
  completed: 2026-10-06
commits: 10
plan_head_before: 032ba55ffa0770a9f50443ab93db44bf9d62c6ce
plan_head_after: 542d2ccc
actuals:
  tasks: 9
  commits: 10
---

# Sync fix round 6: the review of round 5

**One-liner:** "Keep This Mac's Settings" over another Mac's version that may be stale now keeps this Mac's arrangement instead of putting the stale one back on every Mac, a Mac that took another Mac's change asks about a version without it, and a Mac whose last sync held its layout only as a copy writes its layout as a copy over a missing file. Also in this round:
- Keep answered while the file is missing records the answered version.
- Each Mac's writes are recorded in order whatever its clock says.
- The file the app writes is built in Core and tested through a round trip.
- The `fileToWrite` docs are corrected.
- A scenario suite drives several Macs through the Core decisions as the app does.

Maintainer policy (2026-10-05), unchanged: holzBar asks when two Macs' settings differ; its own placements never count (SA-05); the other macOS version's layout is taken in silently; nothing in the sync file is overwritten with a stale copy, and no change of the user's is lost or reverted silently (F-02, F-60); Macs are updated one at a time.

`commits: 10` counts the commits before this summary. The summary is the eleventh commit.

## Commits

| Commit | Issue |
|---|---|
| `f238cabe` | Blocker: Keep over a version not newer than the last sync relists its stale layout (review issues 1 and 6, merged) |
| `bc4d8a81` | Blocker: Keep over a version without this Mac's last write keeps the stale layout |
| `dadb3801` | Major: a third Mac applies a version without a write its settings hold |
| `383a5405` | Blocker: the seen record claims a write whose layout this Mac never took in |
| `0d3a717e` | Minor: Keep while the file is missing does not record the answered version |
| `a9fa5b50` | Minor: the file the app writes is untested glue |
| `47c4f09e` | Minor: a clock set back, or two writes in one second, hides a missing write |
| `34786f18` | Minor: stale `fileToWrite` docs |
| `7cd02fd8` | Follow-up: tests for five guards the mutation check found untested |
| `542d2ccc` | Docs: release notes, features, remediation record |

## Issues and fixes

### Blockers: Keep over a stale version, `f238cabe` and `bc4d8a81`

- `keepsOwnLayoutOverStale(_:local:)` holds when:
  - the user's Keep answers another Mac's version (`keepsThisMac(over:)`, not this Mac's own);
  - that version lists a layout other than the one this Mac last synced;
  - and the version is not newer than this Mac's last sync, or misses a write this Mac holds (`missesLastWrite`).
- `planWrite` passes it into `keepsOwnLayout`. This Mac's layout, the one it last synced plus only holzBar's placements since, is listed as current. `takesInLayout` is then false, so nothing waits for the restart. The rule holds for a joining Mac (the `66bb63a0` path) and for one that is not joining.
- Over a newer version that holds this Mac's writes, Keep still keeps and takes in that version's layout (round 1's SA-05 rule). So does Keep over a version whose layout is the one this Mac last synced.
- Tests:
  - `keepOverOlderVersionWritesOwnLayout`: both paths, the third Mac's view, and each guard.
  - `keepOverVersionWithoutLastWriteKeepsArrangement`: the review's `keepLosesArrangement`, now expecting the arrangement to survive.
  - Scenarios `keepOverRestoredVersion(rejoins:)` and `keepAfterLostWrite`.
  - `joiningAsksAboutOlderLayout` now expects this Mac's layout.

### Major: a third Mac, `dadb3801`

`missesLastWrite` also compares each entry of `Local.seen` (the newest write of each other Mac that this Mac's settings hold) with the version's record, in whole seconds; a missing entry counts as older. The writer's own entry is compared too: it also catches an older version of that Mac brought back. The writer's clock being set back is covered by `writeStamp` below. Test: `versionWithoutHeldWriteOfAnotherMacAsks`; scenario `keepAfterLostWrite` (C asks at launch and keeps A's arrangement).

### Blocker: a record without the layout, `383a5405`

`writesOwnLayoutAsCopy` also holds when this Mac's last sync had no current layout of its macOS version (`baseLayoutDigest == noLayoutDigest`) and it has synced with the folder (`lastSynced != nil`), without a layout edit. Both of the review's variants reach that state: a version holding the layout only as a copy was applied, and `recordApplied` records no layout. A Mac that has not synced with the folder, as one that sets up a new folder, still lists its layout. Scenarios `copyAfterAppliedCopy` (variant 2) and `copyByDateThenLostFile` (variant 1).

### Minor: Keep while the file is missing, `0d3a717e`

- `seen(writingOver:local:)` uses `local.keepsOver` when there is no file version and the write is the user's Keep, so the answered Mac's write counts as held.
- With that, the other Mac would apply this Mac's layout silently. So `writesOwnLayoutAsCopy` also holds when the answered version lists another arrangement that the keep would have kept had the file been there (`keepsOwnLayoutOverStale` does not hold). This Mac's layout is then written as a copy, and the other Mac keeps its arrangement.
- When the answered version's layout may be stale, this Mac's layout is listed as current, as with the file there.
- Scenarios `keepWhileFileMissing(rearrangedThere:)` and `keepStaleWhileFileMissing`.

### Minor: the glue, `a9fa5b50`

`SettingsSyncFile.fileToWrite(plan:deviceID:modified:)` builds the file: date, sync id, settings, `currentLayouts`, `copiedLayouts` and `seen`. `SettingsSync.write`, the layout test helper and the scenario Macs use it. `plannedWriteRoundTrip` goes from `planWrite` to the file, through an XML property list and `contents(of:)`, to `seen`, `seenWrite` and `missesLastWrite` for the reader and the writer. Dropping any key, or the id, fails tests.

### Minor: clock set back, `47c4f09e`

`writeStamp(_:after:)` returns the write's date, or one second after this Mac's last write when that date is not later in whole seconds. `fileToWrite` writes it as this Mac's `seen` entry (`WritePlan.writeStamp(at:)`, from `local.lastWritten`). `recordWrite` stores it as `lastWritten`, from the same `Local`. The file's `modified` stays the clock's date, as the other Macs compare it with their own clocks. Tests: `writeStamp` and the scenario `writeAfterClockSetBack` (a clock set back by 50 s, and a second write within one second).

### Minor: docs, `34786f18`

The `fileCopiedLayouts` and `keepsOwnLayout` parameter docs of `fileToWrite` now describe what the code does. Related docs (`writesOwnLayout`, `takesInKeptLayout`, `holdsOlderLayoutToJoin`, `planWrite`, `seen(writingOver:)`, `missesLastWrite`, `SettingsSyncFile.seenKey`) were corrected in the commits that changed their behaviour.

## Tests

`swift test --filter SettingsSync`: 157 tests in 7 suites (145 before this round). Full `swift test`: 506 + 196 + 3 tests, all passing.

New: `SettingsSyncScenarioTests` drives several Macs through the Core decisions the way `SettingsSync` does: exchange, `outcome`, launch, Use and Keep, with the file built by `fileToWrite`. It holds the review's scenarios with expectations of the fixed behaviour (eight tests, eleven cases).

The review's harness (`syncfix-verify-5` `ReviewSimTests` and `VerifySimTests`, copied to `scratchpad/r6sim`) passes against this round's code:
- D, A and B keep `L_base` after Keep over the restored `V_old`, both re-joining and not.
- In S2 and S3, D keeps `L2`.
- In S4, B shows Restart.
- In V4, A's Keep writes `L2`.
- In V5, C asks and keeps `L2`.
- In V7, A asks and keeps `ShowOnClick` false.

`ReviewR5Tests` and `ReviewR5KeepOlderTests` now fail exactly at the expectations that described the defects.

Mutation check (`scratchpad/r6mut.py` on `scratchpad/r6sim`, never in the worktree; 30 mutations, each applied alone). Each of these made `swift test --filter SettingsSync` fail:
- `keepsOwnLayoutOverStale`:
  - off, not-newer only, missed-write only;
  - without its base, `keepsThisMac` and own-version guards.
- `missesLastWrite`:
  - without the `seen` loop;
  - `<=`, a missing entry counted as held, and the whole-second comparison dropped.
- `writesOwnLayoutAsCopy`:
  - without the no-layout branch, its `lastSynced` guard and the edit guard;
  - the keep branch off or always;
  - without its base, own-version and `forcesWrite` guards.
- `seen(writingOver:)`: without `keepsOver`, and with it also outside a keep.
- `writeStamp`:
  - off, `<` instead of `<=`, and `+0`;
  - `recordWrite` storing the clock's date, and the plan without `lastWritten`.
- `fileToWrite`: `seen` with the clock's date, and without `seen`, the id, `copiedLayouts` or `currentLayouts`.

Five of the 30 survived the first run (the own-version guard of `keepsOwnLayoutOverStale`; the `lastSynced`, own-version and `forcesWrite` guards of the keep copy; `keepsOver` used outside a keep). `7cd02fd8` added tests, and all five now fail. Two of them cannot be reached through the app, which sets `keepsOver` only for a keep, but the tests pin them anyway.

## Gates

Before each commit:
- `appcheck.sh … syncfix` gave `ERRORS: 0`.
- `swift test --filter SettingsSync` passed (the CLT `TestingMacros` plugin error was retried).
- `swiftlint lint --strict --quiet` printed nothing.
- `privacy-check.py network`, `privacy-check.py logs` and `strings-check.py` passed.
- The name grep found nothing.

The full `swift test` passed before the docs commit and this summary.

## Deviations

- Issues 1 and 6 of the review were merged by the reviewer and are one commit (`f238cabe`). Issue 2 (missed write) is its own commit on the same rule.
- Issue 3: the reviewer's minimal form, with a `lastSynced != nil` gate on the no-layout branch, so a Mac setting up a new folder still lists its layout. The broader "any Mac that has synced" rule was not taken: after a lost file it would also stop a Mac's own newest arrangement, which it wrote before the loss, from reaching the Mac that missed it, which applies it correctly today. Issue 2's enabling write (a Mac behind lists its unedited layout over a missing file) is therefore not changed. Every Mac that holds the lost write now asks (issue 4), and Keep keeps that write (issue 2), so nothing is reverted silently.
- Issue 4 keeps the writer's own entry in the comparison (see above) instead of excluding it, which would need the writer's id in `Version`.
- Issue 5 goes beyond the review's one line: recording the answered version alone would have let the other Mac apply this Mac's layout over its arrangement silently. The keep over a missing file therefore writes a copy when the answered version's arrangement is the one Keep would have kept.
- Issue 6 stamps only the `seen` entry and `lastWritten`, not the file's date. A stamped file date could lie ahead of the other Macs' clocks, past `allowedClockSkew`, and turn every later version into a "not newer" one.
- Changed test expectation: `joiningAsksAboutOlderLayout` (Keep writes this Mac's layout).
- No new user-facing strings.

## Known risks

- More arrangements wait as a copy for the next rearrangement: a Mac whose last sync held its layout only as a copy writes a copy over a deleted or damaged file, and so does Keep answered over another Mac's arrangement while the file is missing. In both, each Mac keeps its own arrangement (documented in Known issues).
- Keep over a stale version writes this Mac's layout, with holzBar's own placements since its last sync, over the version's. The user asked for this, and those placements are of items that layout already lacked or that holzBar placed after the last sync.
- `missesLastWrite` may ask once more than needed:
  - when a Mac's clock was set back after its `lastWritten` was reset (an applied version without its newest write, or a forgotten folder);
  - when a version's record dropped an entry past the 64-Mac limit.
- `writeStamp` after a write dated far in the future (a wrong clock) keeps that Mac's record ahead until its clock catches up. It only affects that Mac's own entries, which are compared only with each other.
- The scenario Macs copy the glue in `SettingsSync.swift`. A change there has to be mirrored in `SettingsSyncScenarioTests`; the Core functions they call are the app's.
- The round 5 risks still apply.

## Two-Mac test steps (round 6)

Use Macs that sync the same folder, all on this build and the same macOS version unless a step says otherwise. In `holzBar/Settings.plist`, check `currentLayouts`, `copiedLayouts` and `seen`. The earlier rounds' steps still apply, except round 5's AH: Keep on re-join now keeps this Mac's arrangement.

**AK. Keep over a restored older version** (blocker):
1. On D, Command-drag an item. A and B restart with D's arrangement.
2. Put back a copy of `Settings.plist` saved before step 1 (as a sync app restoring it).
3. On A, choose "Choose Settings…" → "Keep This Mac's Settings". A keeps D's arrangement and shows no Restart, and `currentLayouts` lists it.
4. D and B, after a restart, still show D's arrangement.
5. Repeat with sync turned off and on on A before step 3.

**AL. Keep after a lost write** (blocker):
1. On A, Command-drag an item. Before B reads it, delete `Settings.plist`.
2. On B, change "Show on hover".
3. On A, choose "Keep This Mac's Settings". A keeps its arrangement, and B shows it after a restart.

**AM. Third Mac** (major): repeat AL with a third Mac C that restarted with A's arrangement before step 1's deletion. After step 2, C shows "Choose Settings…", not Restart, and its arrangement stays after a relaunch.

**AN. Record without the layout** (blocker):
1. Do round 5's AE.1 and AE.2.
2. On B, change a setting, and on A, restart with it. A keeps its own arrangement.
3. Delete `Settings.plist`, and on A, change a setting. `copiedLayouts` lists the layout.
4. B keeps its arrangement after a relaunch.

**AO. Keep while the file is missing** (minor):
1. On B, Command-drag an item and change a setting. On A, change a setting: A shows "Choose Settings…".
2. Delete `Settings.plist`, then on A choose "Keep This Mac's Settings". `copiedLayouts` lists the layout.
3. B shows Restart, not "Choose Settings…". After the restart, B keeps its arrangement and has A's setting.

**AP. Clock set back** (minor):
1. On A, change a setting.
2. Set A's clock back a minute and change the setting back. `seen` holds A's entry a second after the first write.
3. Delete `Settings.plist`; on B, change a setting.
4. A shows "Choose Settings…".

## Threat surface

There is no new network, file or permission surface. The file's keys are unchanged; `seen` may now hold a date up to a second past the write's for this Mac's own entry. No log line carries ids, digests or dates.

## Self-Check: PASSED

- The ten commits `f238cabe` to `542d2ccc` exist on `audit-manual/sync-fix` after `032ba55f` (`git merge-base --is-ancestor`).
- All created and modified files exist.
- The gates passed before each commit, and the full `swift test` passed before the docs commit and this one.

---

# Sync fix round 5: the review of round 4

**One-liner:** each write now records the newest write of every Mac it holds, so a Mac whose last change is missing asks however many writes follow, and no Mac lists its own, possibly stale or holzBar-placed, layout as current over a copy without a rearrangement of the user's. Also in this round:
- An arrangement kept with Keep This Mac's Settings survives repeated writes over a missing file.
- Keep This Mac's Settings works for a re-joining Mac asked about an older version.
- A beta 1 Mac's return to an earlier arrangement is passed on.
- The guards of `passesOtherAsCopy` are tested.
- The docs say a waiting version stays offered only while holzBar runs.

Maintainer policy (2026-10-05), unchanged: holzBar asks when two Macs' settings differ; its own placements never count (SA-05); the other macOS version's layout is taken in silently; nothing in the sync file is overwritten with a stale copy, and no change of the user's is lost or reverted silently (F-02, F-60); Macs are updated one at a time.

`commits: 7` counts the commits before this summary. The summary is the eighth commit.

## Commits

| Commit | Issue |
|---|---|
| `66bb63a0` | Major: Keep for a re-joining Mac asked about an older version |
| `1f52adbd` | Blockers: a copied layout promoted to current (variant b of `226db335`; a Mac behind relisting its stale layout over a copy) |
| `815726d9` | Blocker and minor: the date-only parent record; a question turned into a Restart by a descendant |
| `14f77476` | Minor: an unlisted recent layout replaced on any write |
| `21f381da` | Minor: `passesOtherAsCopy` guard tests |
| `c5e09be3` | Blocker follow-up: a file without this macOS version's layout while a kept layout waits; the kept-record condition the mutation check found untested |
| `304412d2` | Minor: docs (waiting version only while holzBar runs) and the round's docs |

## Issues and fixes

### Blockers: a copy promoted to current, `1f52adbd` and `c5e09be3`

Both share one cause: `fileToWrite` treated a layout of this Mac's macOS version that the file marks as a copy like no layout, and listed this Mac's layout as current.
- `fileToWrite` has a branch for that copy: without a layout change of the user's (and without `overwritesOldOwnLayout`) the file's copy is passed on unchanged and stays marked. Only a rearrangement lists this Mac's layout as current again.
- Variant b: A's first write over a missing file marks A's layout as a copy. Its second write, now over its own version, passes the copy on, so B never applies holzBar's placements. `WriteRecord.keepsLayoutToTakeIn` keeps `keptLayoutDigest` across such writes. An older own version holding the kept arrangement is then still taken in, not overwritten as an old copy, and later writes over a missing file still write a copy.
- The mutation check showed that the record's "left unlisted" condition was untested. Testing it brought up a related case: a file that is there but holds no layout for this macOS version. `writesOwnLayoutAsCopy(fileSettings:layouts:local:)` now covers it too (`c5e09be3`).
- Three Macs (A on one macOS version, C and D on the other): a copy demoted by date after A's Keep, a copy passed on from an older version, and a copy inserted over a missing file. In each, D's write keeps the copy, and C keeps `newC`.
- The optional date-free demotion (demote only digests known to be older) was not done. Once nobody relists a copy, a demoted newest arrangement is no longer reverted; it waits for the next rearrangement (documented).

### Blocker: the date-only parent record, `815726d9` (also fixes the descendant minor)

The full fix from the review, the per-Mac record:
- File key `seen`: sync id to date of that Mac's newest write the version holds, with the writer's own (`SettingsSyncFile.seenToWrite`). It replaces `basedOn`, which was never released.
- `SettingsSyncFile.Contents` splits it into `seen` (the other Macs) and `seenWrite` (this Mac), with type checks, keeping at most 64 entries (`limitedSeen`, the newest; the writer's own entry is always kept).
- `missesLastWrite`: the version records writes, and `seenWrite` is older than `lastWritten`, in whole seconds. Each Mac's dates come from its own clock, so clock skew does not matter.
- `seen(writingOver:local:)` merges `Local.seen` with the file version's record; over a missing file only this Mac's own counts.
- `State.seen` (`SettingsSyncSeenWrites`):
  - A write and an adoption merge into it (not an adoption whose layout waits for a restart).
  - An apply replaces it and sets `lastWritten` to this Mac's newest write the applied version holds (`nil` for an earlier build's version), so a version the user chose does not ask again.
  - Forgotten with the folder.
- P4 (second write over its own version), a third Mac writing on top, and the V4 descendant of an asked-about version all ask now. Tests: `versionWithoutLastWriteAsks`, `descendantOfAskedVersionAsks`, `seenRecorded`, `contentsSeen`, `seenRecordLimit`.

### Major: Keep for a re-joining Mac, `66bb63a0`

In `decide`, the `holdsOlderLayoutToJoin` branch writes when `keepsThisMac(over:)` holds (nothing at launch). The write keeps the version's layout and takes it in at the restart, as for a Mac that is not joining. A version that was not asked about still asks. This is narrower than moving the keep check to the top, which would also have turned adoptions into writes.

### Minor: unlisted recent layout, `14f77476`

`fileToWrite` no longer skips the pass-through for layouts in `recentLayouts`; `isRecentLayout` and the `recentLayouts` parameter are gone. A drag still writes over an old copy without a question (`replacesUnlistedLayout` unchanged), and `oldCopyDigest` is remembered on every write. Trade-off (documented): an old copy written back by a beta 1 Mac of the other macOS version stays until the next rearrangement on this Mac.

### Minor: the release-notes claim, `304412d2`

"while holzBar runs", plus a known issue: a relaunch while the file is missing drops the waiting version, and the other Mac asks before this Mac's next change replaces it. The waiting version is not persisted, so `pending` is not kept at launch, as the review advised.

### Minor: `passesOtherAsCopy` tests, `21f381da`

`staleOtherLayoutPassedOnAsCopy` checks three cases: an older version without the other layout, one that lists it without holding it, and one that holds it only as a copy. The review's mutation and each single-condition drop now fail.

## Tests

`swift test --filter SettingsSync`: 144 tests (141 before). Full `swift test`: 493 + 196 + 3 tests, all passing.

Mutation check (`scratchpad/r5mut.py` and `r5mutate.sh` on `scratchpad/r5mut`, never in the worktree). Each mutation was applied alone, and `swift test --filter SettingsSync` failed for:
- the keep in the re-join branch
- the copy branch, off, and taken also after a user edit
- the kept record not kept; each term of `keepsLayoutToTakeIn`
- `writesOwnLayoutAsCopy` back to a missing file only
- `missesLastWrite`: without its record guard, and with `<=`
- `seen(writingOver:)`: only local, only the file; the merge taking the minimum
- `recordWrite` and the adoption: not recording, or always or never merging
- the apply keeping the record or `lastWritten`, or keeping `lastWritten` for an earlier build's version
- `leaveFolder` and `changes(from:)` dropping the record
- `Contents`: keeping this Mac in `seen`, no `seenWrite`
- `limitedSeen` keeping the oldest; `seenToWrite` without room for its own entry
- the three `passesOtherAsCopy` guard drops
- a revert of the unlisted-recent fix (emulated in `planWrite`)

One mutation survived and is equivalent: `seenToWrite` keeping an old own entry. The function filters this Mac out before adding its write, so the mutated line cannot change the result.

## Gates

Before each commit:
- `appcheck.sh … syncfix` gave `ERRORS: 0`.
- `swift test --filter SettingsSync` passed (the CLT `TestingMacros` plugin error was retried).
- `swiftlint lint --strict --quiet` printed nothing.
- `privacy-check.py network`, `privacy-check.py logs` and `strings-check.py` passed.
- The name grep found nothing.

The full `swift test` passed before the docs commit and this summary.

## Deviations

- Issues 3 and 5 got the full per-Mac record rather than the minimal `lastSyncedFromOthers`, as only it also closes the third-Mac and descendant cases. It replaces the unreleased `basedOn` key and `SettingsSyncFile.noParent`.
- Issue 4 checks the keep inside the re-join branch instead of moving it above every rule (see above).
- Issues 1 and 2 share the fix and the first commit; the mutation check led to the follow-up `c5e09be3`.
- Changed test expectations:
  - `joiningAcrossVersionsNeverAsks`: an other-OS Mac's copy is passed on as a copy without a rearrangement.
  - `keptLayoutNotReplacedOverMissingFile`: B's next write without a rearrangement passes the copy on.
  - `staleCopyOfOwnLayoutWrittenOver` and the planned-write state test: a recent unlisted layout is passed on unless the user rearranged.
- The review's scratch tests in `syncfix-verify-4` target the `basedOn` API and were not copied; their scenarios are in the new tests.
- No new user-facing strings.

## Known risks

- An arrangement the folder holds only as a copy is not synced until the user rearranges the menu bar on a Mac of that macOS version: after a sync app brings back an older version, after a write over a deleted file while a kept layout waited, and in a folder a Mac of the other macOS version set up. Each Mac keeps its own meanwhile; nothing is lost (documented).
- An old copy that a beta 1 Mac of the other macOS version writes back stays in the folder until this Mac's next rearrangement, and same-OS beta 1 Macs apply it at their launch, as they already did after the beta 1 write (documented).
- Both choices are conservative, at the cost of rare extra questions:
  - An adoption does not move `lastWritten`, so after a version that holds this Mac's settings but not its write record, a later version from another Mac can ask once more.
  - A newer version that changed nothing is not merged into `seen`, so a later write over a missing file makes that Mac ask.
- A Mac that ran a round 4 build keeps a `lastWritten` date; the first file of this build that lacks its entry asks once.
- A beta 1 Mac's writes record nothing, as before (documented). The macOS 26 settle-window residual of round 4 is unchanged.

## Two-Mac test steps (round 5)

Use Macs that sync the same folder, on this build unless a step says otherwise. In `holzBar/Settings.plist`, check the new `seen` dictionary (one date per Mac) and `copiedLayouts`. The round 4 steps X to AD, the round 3 steps Q to W, the round 2 steps I to P and the round 1 steps A to H still apply, except that Y.2 now checks `seen` instead of `basedOn`.

**AE. Keep, then the file goes away twice** (blocker): A and B on the same macOS version.
1. Do round 3's Q.1 and Q.2, so A shows Restart after "Keep This Mac's Settings".
2. Delete `Settings.plist`. On A, change "Show on hover"; then change it back. Both writes list A's layout under `copiedLayouts`.
3. Quit and reopen B. B keeps its arrangement and takes A's setting.
4. On B, Command-drag an item. B's layout is listed under `currentLayouts` again.

**AF. Three Macs** (blocker): A on macOS 26, C and D on macOS 27.
1. Turn sync off on D.
2. On C, Command-drag an item. Copy `Settings.plist` aside before C writes, and put it back after A has read C's file.
3. On A, change a setting. `MacOS27Layout` is under `copiedLayouts`.
4. Turn sync on again on D, and change a setting there. `MacOS27Layout` stays under `copiedLayouts`.
5. On C, restart through the hint. C keeps its arrangement.

**AG. Several writes without the other Mac's change** (blocker): A and B on the same macOS version.
1. On B, change "Show on hover". Before A reads it, delete `Settings.plist`.
2. On A, change a setting, then another. B shows "Choose Settings…", not "Restart".
3. Variant: a third Mac applies A's file and changes a setting. B still asks.

**AH. Keep on re-join** (major): repeat round 4's AA. Choose "Keep This Mac's Settings". A writes, does not ask again, and shows Restart. After the restart, A shows B's arrangement and keeps A's other settings.

**AI. A beta 1 Mac's return** (minor): C on 0.0.7 beta 1 and the same macOS version as A.
1. On C, move the items back to exactly an arrangement both had before.
2. On A, change "Show on hover". Quit and reopen C: C keeps its arrangement.
3. On A, Command-drag an item. A's arrangement replaces C's, without a question.

**AJ. Relaunch while the file is missing** (docs):
1. On B, change a setting. A shows Restart.
2. Delete `Settings.plist`, and quit and reopen A. The hint is gone.
3. On A, change a setting. B shows "Choose Settings…".

## Threat surface

There is no new network or permission surface.
- The sync file's new key `seen` replaces the unreleased `basedOn`. It is a dictionary read with type checks (string keys, date values; anything else is dropped) and capped at 64 entries, the newest kept. It holds the Macs' sync ids, which each Mac already writes into the file as `deviceID`.
- The new defaults key `SettingsSyncSeenWrites` is read with the same checks. It starts with "SettingsSync", so it is never exported, imported or synced.
- No log line carries ids, digests or dates.

## Self-Check: PASSED

- The seven commits `66bb63a0` to `304412d2` exist on `audit-manual/sync-fix` after `0fa5a4bc` (`git merge-base --is-ancestor`).
- All modified files exist.
- The gates passed before each commit, and the full `swift test` passed before the docs commit and this one.

---

# Sync fix round 4: the review of round 3

**One-liner:** each write now records the version it was based on, so a Mac whose last change a newer version lacks asks instead of losing it, and a layout of the other macOS version from an older version never comes back as current. Also in this round:
- A waiting version survives the sync file going away.
- An arrangement this Mac keeps is not replaced over a missing file.
- Before macOS 27, the user's moves are told from macOS's.
- An own version is an old copy only on positive evidence.
- A re-joining Mac asks about an older arrangement it never took.
- More of the glue is decided in Core.

Maintainer policy (2026-10-05):
- When two Macs' settings differ, holzBar asks.
- holzBar's own placements never count (SA-05).
- The other macOS version's layout is taken in silently.
- Nothing in the sync file is overwritten with a stale copy, and no change of the user's is lost or reverted silently (F-02, F-60).
- Users update one Mac at a time, so a Mac still on 0.0.7 beta 1 must be handled safely.

`commits: 8` counts the commits before this summary. The summary is the ninth commit.

## Commits

| Commit | Issue (severity) |
|---|---|
| `a42f8c59` | A stale layout of the other macOS version, from an old own version or a not-newer version, is taken in, written back as current, and applied silently by the other Mac (blocker) |
| `226db335` | Writing over a missing or unusable file: a waiting version is dropped (a'), and holzBar's own layout replaces a kept arrangement (b) (major) |
| `d0488e5e` | Writing over a missing or unusable file reverts another Mac's last change (a), via the parent-version record (major; design guidance) |
| `62ee8bb4` | Before macOS 27, a first move of an unsaved item does not count, and a Command-click after macOS displaced items syncs the displacement (major) |
| `e77271bf` | isOldOwnLayout uses negative evidence (minor) |
| `dc5bd356` | A joining Mac adopts another Mac's not-newer version and records its layout as synced without taking it in (minor) |
| `44ee0fb8` | Issue 13 only partly fixed: the glue that feeds the Core decisions is untested (minor) |
| `1bf75b1d` | Docs, including the minor that is documented rather than fixed (64-layout recognition and a beta 1 user's return to an earlier arrangement) |
| this commit | This summary |

## Issues and fixes

### Design: the parent-version record, `d0488e5e`

The review asked for a parent-version record if it closes the remaining issues' common cause. It closes the one that needs it: a write by a Mac that had not seen another Mac's last write. Each write stores `basedOn`, the date of the newest version the write accounts for: the newest of this Mac's last sync and the file's version it writes over, or `SettingsSyncFile.noParent` when it knew neither. The decision writes only over a version whose changes this Mac holds or the user chose to replace, so this date is honest. Each Mac keeps the date of its own last write (`State.lastWritten`, key `SettingsSyncLastWritten`). A newer version from another Mac whose `basedOn` is older than that write, compared in whole seconds as the plist stores dates, lacks the write. `missesLastWrite` then makes it ask (at launch through the check after it), and the hint offers the choice.

Only the Mac whose write is missing asks. The other Macs, whose own changes are in the version, apply it as before. That avoids extra questions after adoptions and other Macs' writes.

A full parent digest per version was considered and not used. The digest would not fix contents copied from a stale file (the blocker below), and a date is enough to tell "based on my last write" from "not".

Files of 0.0.7 beta 1 carry no `basedOn` and are decided exactly as before. Beta 1 ignores the new top-level key, as it reads only `modified` and `settings`.

What remains: a beta 1 Mac's write over a deleted file. Also a chain where a third Mac writes on top of a concurrent write that the sync app kept before this Mac saw it, and clock skew between Macs. These are in Known issues.

### Blocker: the other macOS version's layout from an older version, `a42f8c59`

`isBeforeLastSync` compares a version's date with this Mac's last sync, in whole seconds. When the version is older, the launch tail and an adoption take in nothing of its other macOS version's layout (`takesInOtherLayout`). That covers every older version of this Mac's own. `planWrite` now takes the file's version (`fileVersion`, replacing `fileIsFromThisMac`). It passes that layout on marked as a copy (`passesOtherLayoutAsCopy`), so updated Macs of that version ignore it and keep their arrangement, and it never substitutes this Mac's own copy, which can lag. The write logs that it did so, without values.

So that a version brought back later is known to be older, a newer version from another Mac that changed nothing this Mac uses, met with nothing to write at launch or on a check, now counts as the last sync (`State.recordUnchanged`). An adoption already did.

In the two-backend test, A adopts C's V2, V1 comes back, A changes a setting and writes, and C applies A's change while keeping its arrangement. Listed as current, C would have applied the stale one.

### Major: a missing or unusable file, `226db335` and `d0488e5e`

- (a') A check that finds the file missing or unusable while a version waits now returns `.wait`. The hint keeps the in-memory version, nothing is pushed, and Keep This Mac's Settings still writes. The launch is unchanged: a version that waits is in memory only, so after a relaunch with the file gone nothing can be offered.
- (b) `writesOwnLayoutAsCopy`: over a missing or unusable file, while this Mac keeps another Mac's layout without a layout edit, this Mac's layout is written marked as a copy. The Mac that made the arrangement keeps it and lists it again with its next write, and this Mac then takes it through the usual Restart hint.
- (a) The parent-version record above.

### Major: macOS 26 first move and displaced items, `62ee8bb4`

Each reconciliation read that the user cannot be arranging during records the section of every candidate item as `sectionsBeforeArrangement`, updated with holzBar's own moves. "Cannot be arranging" means no drag, no pending save, no Layout pane move running (`userMovesInProgress`), and neither Command nor a mouse button held (`capturesBarBeforeArrangement`). `saveSections(byUser: true)` decides with `SettingsSyncPolicy.sectionsToSave`:
- An item in another section than recorded moved. It is saved, and it counts when that changes its saved section, also on its first move.
- An item still in its recorded section keeps its saved section (the restore brings it back), so macOS's displacement is never saved or synced.
- Items without a record are saved as before.

The save uses the record up.

Why the read must come before the arrangement: a snapshot taken at the save could already hold the user's move, and would then revert it. That is why mouse buttons and Command count, and why a Layout pane move blocks capture until its save.

Residual (Known issues): during the 2 s settle window after a display change or wake, holzBar does not read the bar. A displacement and an arrangement both within that window are decided as before, and so are items that appear during a drag or are temporarily shown.

### Minor: positive evidence for an old own copy, `e77271bf`

`isOldOwnLayout` takes the version and requires it to be dated before the last sync. When the kept-layout record was lost (sync turned off while the write ran, a quit right after it, or branch-build state), the version is not older. A write then keeps its layout and offers it to be taken in, and does not write holzBar's own layout over it.

### Minor: a joining Mac and an older version, `dc5bd356`

`holdsOlderLayoutToJoin` asks while joining, without a layout edit, about another Mac's version that is not newer and whose layout is neither the base (kept across leaving the folder) nor this Mac's. Comparing with the base keeps holzBar's own placements from asking. This mirrors `isUnsyncedChange` for a Mac that is not joining.

### Minor: the glue, `44ee0fb8`

`settingsToApplyAtLaunch`, `settingsToTakeInAtLaunch` and `otherLayoutToTakeIn` move pullIfNeeded's per-decision application, its take-in tail and the adoption's take-in into Core. `planWrite` reads the file's version itself, so the old `fileIsFromThisMac` flag in the glue is gone. Still in the app, which the test package does not build: reading and writing the file, `request.kind == .check`, the hint dispatch and the logs.

### Minor, documented: 64-layout recognition and a beta 1 return, `1bf75b1d`

A beta 1 Mac writing back an old copy and a beta 1 user who moves the menu bar back to exactly an arrangement this Mac synced recently look the same to this build. Narrowing recognition would bring the old-copy question back for the common write-back. Documented in Known issues.

## Tests

Each new or changed condition was mutated in a scratch copy (`scratchpad/r4mut`, never in the worktree), and `swift test --filter SettingsSync` failed for every mutation:
- `isBeforeLastSync` (`<` → `<=`; whole seconds dropped)
- `passesOtherLayoutAsCopy` off
- the copy mark in `fileToWrite`
- `takesInOtherLayout` always true
- `recordUnchanged`: its newer guard, and both calls
- the `.wait` for a missing file, and its `forcesWrite` and launch conditions
- every term of `writesOwnLayoutAsCopy`, and its use in `fileToWrite`
- `missesLastWrite` (`<=`, whole seconds, the joining and own guards), and its use in `decide` and the hint
- the `lastWritten` record and its reset
- `basedOn` ignoring the file's version
- the file's `basedOn` read
- the date term of `isOldOwnLayout`, and its use in `planWrite`
- each guard term of `holdsOlderLayoutToJoin`, both comparisons, and its call in `decide`
- each branch of `sectionsToSave` and each term of `capturesBarBeforeArrangement`
- each case of `settingsToApplyAtLaunch`, the stale guard of `otherLayoutToTakeIn`, and the learned part of `settingsToTakeInAtLaunch`

New tests:
- `SettingsSyncLayoutTests`: `staleOtherLayoutPassedOnAsCopy` and `unchangedNewerVersionRecordedAtLaunch` (blocker); `keptLayoutNotReplacedOverMissingFile`; `versionWithoutLastWriteAsks` and `writeRecordsBasedOn` (parent record); `joiningAsksAboutOlderLayout`; `sectionSaveWithBarBeforeArrangement` and `barBeforeArrangementCapture`; `settingsToApplyAtLaunch` and `settingsToTakeInAtLaunch`. Also extended: `oldOwnVersionNotTakenIn` (positive evidence) and `sectionSaveCountsOnlyChangedSections`.
- `SettingsSyncPolicyTests`: `missingFileKeepsWaitingVersion`.
- `SettingsSyncFileTests`: `contentsBasedOn`, with a plist round trip of the no-parent date.
- `SettingsSyncStateTests`: the `SettingsSyncLastWritten` key in the stored-keys and round-trip tests.

`swift test --filter SettingsSync`: 141 tests. Full `swift test`: 490 + 196 + 3 tests, all passing.

## Gates

Before each commit:
- `appcheck.sh … syncfix` gave `ERRORS: 0`.
- `swift test --filter SettingsSync` passed (the CLT `TestingMacros` plugin error was retried).
- `swiftlint lint --strict --quiet` printed nothing.
- `privacy-check.py network`, `privacy-check.py logs` and `strings-check.py` passed.
- The name grep found nothing.

Before this summary, the full `swift test` passed.

## Deviations

- The design guidance was applied where a parent record closes the cause (the general missing-file case). The blocker needs a rule about stale contents, which a parent record cannot express, so it uses the version's date against the last sync. A newer version that changed nothing now counts as the last sync, which makes that rule hold.
- `planWrite` takes the file's version instead of `fileIsFromThisMac` (default `nil`), part of the glue fix.
- `countsAsSectionSaveEdit` was replaced by `sectionsToSave`, which also returns the sections to save. Its test now calls the new function.
- No new user-facing strings.

## Known risks

- The 2 s settle window before macOS 27, and items that appear during a drag or are temporarily shown (documented).
- A beta 1 Mac's write over a deleted or damaged file; a chain of concurrent writes; clock skew between Macs, which can make a version look based on this Mac's last write or not (documented).
- The 64-layout recognition and a beta 1 user's return to an arrangement this Mac synced recently (documented).
- At launch, a version that waited before a relaunch is gone if the file is missing: there is nothing to offer, and the other Mac asks thanks to the parent record.
- The capture of the bar before an arrangement relies on `NSEvent.modifierFlags` and `NSEvent.pressedMouseButtons` at the reconciliation read. It was type-checked, not run on a Mac (two-Mac step AD).

## Two-Mac test steps (round 4)

Use Macs that sync the same folder, on this build unless a step says otherwise. In `holzBar/Settings.plist` also check the new `basedOn` date and the `copiedLayouts` array. The round 3 steps Q to W, the round 2 steps I to P and the round 1 steps A to H still apply.

**X. A stale layout of the other macOS version** (blocker): A on macOS 26, C on macOS 27.
1. On A, change a setting so A writes. Copy `Settings.plist` aside.
2. On C, Command-drag an item; C writes. Wait until A has read it (A shows no hint).
3. Put the copy back over `Settings.plist`.
4. Quit and reopen A. On A, change "Show on hover". The file lists `MacOS27Layout` under `copiedLayouts`, not `currentLayouts`, and the log says the older layout for the other macOS version was passed on as a copy.
5. On C, restart through the hint. C takes A's setting and keeps its arrangement.

**Y. The sync file goes away** (major): A and B on the same macOS version.
1. On B, change "Show on hover". Before A shows the hint, delete `Settings.plist` (or replace it with an empty file).
2. On A, change another setting. A writes; `basedOn` is older than B's write.
3. B shows "Choose Settings…" instead of "Restart". "Keep This Mac's Settings" keeps B's change.
4. Repeat with A showing B's Restart hint before the file goes away: the hint stays, and A does not write until you answer.
5. Keep variant: do round 3's Q.1 and Q.2, delete the file, and change a setting on A. The file lists A's layout under `copiedLayouts`. Quit and reopen B; it keeps its arrangement.

**Z. A Mac still on 0.0.7 beta 1** (compatibility): C on beta 1 and the same macOS version as A. Repeat Y.1 to Y.3 with C writing the file in Y.2 by changing a setting. B applies C's file without asking, as before (Known issues). C applies A's files with `basedOn` without complaint.

**AA. Re-join with an older version** (minor): A and B on the same macOS version.
1. Set B's clock a few minutes back. On B, Command-drag an item; B writes.
2. On A, turn sync off and on. A asks "Which settings should holzBar use?" instead of joining silently.
3. Set B's clock back.

**AB. Old own copy without a record** (minor): not manually reproducible on purpose (needs sync turned off within milliseconds of a write). The unit tests cover it.

**AC. First move and displaced items** (major, macOS 26, timing-dependent):
1. Connect or disconnect a display, and wait about three seconds. If macOS moves items, holzBar starts putting them back.
2. While it moves them, Command-click any item. Nothing is synced, and the moved items go back to their saved sections with the next restore.
3. Make an item appear that has never been saved (launch an app with a menu bar item while you Command-drag another). Then Command-drag that item into another section. Another Mac's newer settings no longer move it back: this Mac writes its layout.

**AD. A move in the Layout pane during a restore** (major): drag an item in the Layout pane right after a wake. The move is saved and synced, never reverted by the next restore.

## Threat surface

There is no new network or permission surface. The sync file has one new top-level key, `basedOn`, a date read with a type check; beta 1 ignores it. There is one new defaults key, `SettingsSyncLastWritten`, a date read with a type check. It starts with "SettingsSync", so it is never exported, imported or synced. The new log line carries no values, digests or ids.

## Self-Check: PASSED

- The eight commits `a42f8c59` to `1bf75b1d` exist on `audit-manual/sync-fix` after `1af35114` (`git merge-base --is-ancestor`).
- All modified files exist.
- The gates passed before each commit, and the full `swift test` passed before this one.

---

# Sync fix round 3: the review of round 2

**One-liner:** these fixes close the gaps the round 2 review found:
- A kept arrangement from another Mac is recorded as such. It never counts as this Mac's own synced layout, a re-join asks before a drag writes over it, and an older own version that a sync app brings back is never taken in.
- "Keep This Mac's Settings" recognizes the answered version by its contents.
- Old-copy detection survives many rearrangements.
- holzBar's own section placements never overwrite a section the user just saved.
- What happens after each sync decision is decided and tested in Core.

Maintainer policy (2026-10-05):
- When two Macs' settings differ, holzBar asks.
- holzBar's own placements never count (SA-05).
- The other macOS version's layout is taken in silently.
- Nothing in the sync file is overwritten with a stale copy, and no change of the user's is lost or reverted silently (F-02, F-60).
- Users update one Mac at a time, so a Mac still on 0.0.7 beta 1 must be handled safely.

`commits: 8` counts the commits before this summary. The summary is the ninth commit.

## Commits

| Commit | Issue (severity) |
|---|---|
| `88a8ac31` | A kept-but-not-taken-in layout counts as recently synced, so after a beta 1 write-back holzBar's own layout replaces the other Mac's arrangement (blocker) |
| `b9e981e2` | Re-joining after a layout edit writes this Mac's layout over another Mac's kept layout without asking (major) |
| `bf742362` | An older version this Mac wrote, brought back by the sync app, is taken in silently at launch and reverts the layout (major) |
| `9e62214d` | Keep This Mac's Settings writes over an unasked version from a third Mac dated at or before the answered one (major) |
| `ab28fc08` | Stale-copy detection keeps only the last 8 layouts (minor) |
| `aa6e6ef5` | Before macOS 27, reconciliation can store an item's old section over the one the user just saved (minor) |
| `f5895cb6` | Issue 13 only partly fixed: the dispatch of sync decisions is outside the test package (minor) |
| `94412993` | Docs, including the two minors that are documented rather than fixed |
| this commit | This summary |

## Issues and fixes

### Blocker: a kept layout counted as recently synced, `88a8ac31`

`State.recordWrite` now calls `rememberLayout` only when the write did not keep another Mac's layout to take in. `State.recordAdoption` calls it only when it takes nothing in. `recordLayoutTakeIn` and `recordApplied` remember a layout once it is taken in.

After a beta 1 Mac writes the kept layout back unlisted, the next non-layout push on this Mac passes it on unlisted instead of writing holzBar's own placements over it, and a drag asks. The adoption of the beta 1 write-back still withdraws the Restart hint. This Mac then keeps its own layout, and the other Mac's arrangement stays in the file and on that Mac, so nothing is lost.

### Major: re-join after a drag, `b9e981e2`

New `State.keptLayoutDigest`, stored under `SettingsSyncKeptLayoutDigest`, which starts with "SettingsSync" and is never synced. It holds the other Mac's layout that this Mac's own version holds and this Mac has not taken in.
- A write with `takesInLayout`, or a joining adoption of this Mac's own version that takes its layout in, sets it.
- `markSynced` clears it, so every other write, adoption or apply clears it. So does `recordLayoutTakeIn`.
- `leaveFolder` keeps it.
- `Local.keptLayoutDigest` copies it from the state.

`holdsLayoutToTakeIn` now requires `version.layoutDigest == local.keptLayoutDigest` (and `!= baseLayoutDigest`) and no longer excludes a joining Mac. A layout edit then asks (or waits after "Later") for both `forgetsLastSync` values and every trigger. Without an edit, a joining Mac with other changes takes the kept layout in at launch and keeps it in its writes while it runs.

### Major: an older own version brought back by the sync app, `bf742362`

With the explicit record, an own version whose layout is neither the base nor the kept one is no longer taken in. That holds at launch, on a check and on a local change. The new `isOldOwnLayout(_:local:)` names that case. `planWrite` takes `fileIsFromThisMac` and writes this Mac's layout, listed as current, over such a copy (`keepsOwnLayout`), so the stale arrangement does not spread. The app passes `inspection.remote?.version.isFromThisMac`.

While joining, the own version's layout stays the folder's arrangement. Taking it in is the documented join rule, so the reviewer's P2 variant is unchanged.

### Major: Keep only over the answered version, `9e62214d`

`Local.keepsOver` is now the answered `Version`, not its date. `keepsThisMac` accepts this Mac's own version or one that `isSame(as:)` the answered version. `isSame` compares writer, date, user digest, layout digest and unlisted layout digest. It leaves out `isNewer`, which depends on when the file is read.

Any other version from another Mac goes through the usual rules, which ask when this Mac has changes:
- one dated earlier,
- the same date with other settings,
- the same settings written later,
- an older one a sync app brought back.

The test "an older version is written over too" was replaced by tests of these cases.

### Minor: 8 recent layouts, `ab28fc08`

`recentLayoutLimit` is now 64, about 4 KB in defaults. `planWrite` records the file's unlisted layout of this macOS version when it is one this Mac synced (`WriteRecord.oldCopyDigest`), and `recordWrite` remembers it anew. A beta 1 Mac that keeps writing the same stale copy back therefore keeps it recognized however often the user rearranges between its writes. I chose this over a separate list of own layouts: one list also covers applied layouts, which a beta 1 Mac writes back the same way.

### Minor: reconciliation over a fresh user save, `aa6e6ef5`

The new `SettingsSyncPolicy.ownPlacementsToStore(_:savedNow:wanted:)` keeps only items that still have no saved section and that no profile places. `performReconciliation` re-reads `savedSections()` right before it stores `placedSections` and `unsavedSections`.

### Minor: the dispatch in Core, `f5895cb6`

- `SettingsSyncPolicy.outcome(of:isCheck:version:local:state:takesInOwnLayout:written:)` returns, for every `Action`, the state to store, a `HintChange` (`unchanged`, `withdraw`, `offerFileVersion`, `offerWrittenVersion`) and whether a push follows.
- `launchApplication(for:)` says what the launch applies, and `State.recordLaunch(_:version:local:appliedBase:)` says what it records.
- `SettingsSync.handle` and `finishJoin` share `act(on:of:)`, which only executes the outcome. `adopt()`, `recordWrite()` and `setPending()` are gone, and `pullIfNeeded` uses the two launch functions.
- Hints are now offered with this Mac's current side in all cases. Before, `.apply`, `.ask` and `.takeInLayout` used the request's side, which a change made during the exchange could leave stale.

Still in the app, and not unit-tested:
- calling `ownLayoutToTakeIn` to compute `takesInOwnLayout`
- mapping a `HintChange` to `offer` or `withdrawHint`
- applying the dictionaries at launch
- `keepsOver = remote.version`
- `fileIsFromThisMac` in `write`
- the `savedSections()` re-read in `SectionRestore`

### Not fixed (minor): writing over a missing or unusable file

Documented as a known issue (release notes, features). A safe fix needs each write to carry its parent version. A single parent digest makes a Mac that was offline while another Mac wrote twice ask about a plain fast-forward, which is common (a closed laptop). Avoiding that needs a version history in the file. The file format, beta 1 compatibility and every write path would change for a case that needs the file lost between two Macs' syncs. This is not a regression: base `d7c01063` had the same rule.

### Not fixed (minor): macOS 26 first move of an unsaved item, and a displaced item saved by a Command-click

Documented as known issues in the release notes. Both fixes need the item's section at the start of the user's drag. holzBar does not see the drag start when its drag monitors do not run (they run only for "Show all sections on drag" or a custom appearance). Section records from cache reads can be taken mid-drag. For (b), such a record could make a save skip the user's real move, which the restore would then undo, which is worse than the residual. For (a), it could count holzBar's own Live Activity moves as the user's (SA-05). Both residuals are narrower than at base `d7c01063`.

## Tests

- `swift test --filter SettingsSync`: 129 tests in 6 suites (120 before this round).
- Full `swift test`: 478 + 196 + 3 tests pass.

New tests:
- In `SettingsSyncLayoutTests`:
  - the beta 1 write-back of a kept layout (blocker)
  - a re-join after a drag, for both `forgetsLastSync` values and every trigger, with the hint, "Later", and the joining take-in and write without a drag
  - the old own version, for every trigger, the write over it, another Mac's version, a kept layout and a joining Mac
  - an old copy after twenty rearrangements
  - `ownPlacementsToStore`
- In `SettingsSyncStateTests`:
  - the kept layout's lifetime and storage
  - an old copy remembered anew over three rounds of 63 writes
  - `planWrite`'s `oldCopyDigest`
  - `outcome` for every action
  - `launchApplication` and `recordLaunch` for every action
- In `SettingsSyncPolicyTests`:
  - Keep only over the answered version, including one read again as not newer
  - unasked versions dated later, earlier or the same, with other settings, layout or unlisted layout, an older one, and the same settings rewritten later

Mutation check: `scratchpad/r3mut.py` applied each mutation alone, re-ran `swift test --filter SettingsSync` and restored the file. All 43 mutations are caught. Two of them were missed at first; I strengthened the tests and re-ran all 43:
- `isSame` without the date
- `keepsThisMac` using `==`, which includes `isNewer`

The mutations covered:
- both `rememberLayout` guards
- the kept-layout check in `holdsLayoutToTakeIn`, and a joining guard added back
- `markSynced` clearing the kept layout, `recordWrite` and `recordAdoption` setting it, `recordLayoutTakeIn` clearing it, and `leaveFolder` clearing it
- `Local` copying the kept layout, its storage key, and reading it back
- every part of `isOldOwnLayout`, and of `planWrite`'s `overwritesOldOwnLayout`
- `keepsThisMac` going back to a date bound, and each field of `isSame`
- the 64 limit, the old-copy refresh and the old-copy condition
- both conditions of `ownPlacementsToStore`
- every branch of `outcome` (pending for apply/ask, no pending for takeInLayout, the adoption hint and record, the push after a check, the written-version hint, wait/retry unchanged)
- `launchApplication(.takeInLayout)`
- `recordLaunch` for ask, none, takeInLayout and adopt

## Gates

Before each commit:
- `appcheck.sh … syncfix` reported `ERRORS: 0`.
- `swift test --filter SettingsSync` passed. The CLT TestingMacros flake was retried by script.
- `swiftlint lint --strict --quiet` printed nothing.
- The privacy checks (network, logs) and the strings check passed. The strings check reported 382 strings in 5 languages.
- The former-name grep found nothing.

The full `swift test` passed before this summary commit. No new user-facing strings. No new log line carries a digest or id.

## Deviations

- The round 3 review's Issue 1 and Issue 7 share `State.keptLayoutDigest`. `b9e981e2` adds it, and with it the own version no longer takes in a non-kept layout, which is part of Issue 7. `bf742362` adds the write over the old copy and Issue 7's tests.
- For Issue 7, `ownLayoutToTakeIn` keeps taking in any own version while joining (no layout edit). That is the documented join rule, which the review called by design. A joining Mac's write over such a version also keeps it, and it is taken in.
- For Issue 4, I kept one list and refresh entries on use, instead of the review's separate list of own layouts (see above).
- For Issue 9, the hint is now offered with this Mac's current side throughout, a small behaviour change.

## Known risks

- The adoption of a beta 1 write-back of a kept layout withdraws the Restart hint, so this Mac never takes the kept arrangement in. The other Mac keeps it, and a drag on this Mac asks before replacing it.
- An own version restored by a sync app stays in the file until this Mac's next change writes over it. Other Macs that synced a later version of this Mac's ask about it, as a version that is not newer, instead of applying it.
- The two documented minors above.
- Before an update, a Mac running an unreleased build of round 2 has no `SettingsSyncKeptLayoutDigest`, so a kept layout waiting on it is not taken in. Its next push keeps the layout in the file and records it.

## Two-Mac test steps (round 3)

Use Macs that sync the same folder, on this build unless a step says otherwise. Check the layout in holzBar's Layout pane, the hint in Settings → Advanced, and `holzBar/Settings.plist` in the sync folder (its `currentLayouts` array and its `ItemSections` / `MacOS27Layout`). The round 2 steps I to P and the round 1 steps A to H below still apply.

**Q. Keep, drag, then join again** (Issue 1), A and B on the same macOS version:
1. On B, Command-drag an item and change "Show on hover".
2. On A, without touching the layout, change "Show on hover" the other way. Choose "Choose Settings…" → "Keep This Mac's Settings". Do not restart.
3. On A, Command-drag an item. The hint reads "Choose Settings…".
4. Turn sync off and on in Settings → Advanced. The hint again reads "Choose Settings…", and nothing is written: B's arrangement is still in the file. Quit and reopen B; it keeps its arrangement.
5. Repeat steps 1 to 3, then choose the same folder again with "Change…". holzBar asks "Which settings should holzBar use?" before it joins.
6. Repeat steps 1 and 2. Turn sync off, Command-drag on A, then turn sync on. The result is the same as step 4.
7. In the question, "Keep This Mac's Settings" writes A's dragged layout. "Use Settings from Sync Folder" restarts A with B's arrangement.

**R. A sync app brings back an older version of this Mac's** (Issue 7):
1. On A, change a setting so A writes the file. Copy `Settings.plist` aside.
2. On A, Command-drag an item; A writes again.
3. Put the copy back over `Settings.plist`.
4. Quit and reopen A. A keeps the dragged layout, and no hint appears.
5. On A, change "Show on hover". The file now holds A's dragged layout, listed as current.

**S. Keep with a version dated earlier** (Issue 2):
1. Make A ask: both Macs change "Show on hover". Leave the sheet open on A.
2. Set B's clock a few minutes back, change another setting on B and wait for it to reach A. A's last sync must be older than that change's date.
3. Click "Keep This Mac's Settings" on A. A does not write over B's new version, and the hint returns as "Choose Settings…".
4. Set B's clock back.

**T. A kept arrangement that a Mac still on 0.0.7 beta 1 writes back** (blocker): A and B on this build, C on 0.0.7 beta 1, all on the same macOS version.
1. Do steps Q.1 and Q.2.
2. Quit and reopen C, which applies the file. Change a setting on C, which writes the file back without `currentLayouts`.
3. On A, change "Show on hover". The file still holds B's arrangement under the layout key, not listed. Quit and reopen B; it keeps its arrangement.
4. On A, Command-drag. A asks.

**U. Many rearrangements while a beta 1 Mac of the other version writes an old copy back** (Issue 4): A on macOS 27 with this build, C on macOS 26 with 0.0.7 beta 1.
1. On A, arrange and let it write. Quit and reopen C.
2. On A, Command-drag ten or more times, letting each write.
3. On C, change a setting.
4. On A, Command-drag again. There is no question.

**V. An item you move while holzBar restores** (Issue 8, macOS 26, timing-dependent):
1. Wake the Mac or connect a display so holzBar puts several items back.
2. While it moves them, Command-drag an item that has never been saved (for example one that just appeared).
3. After a few seconds, and after the next restore (for example after another wake), the item stays where you put it.

**W. Dispatch** (Issue 9): repeat round 2's steps I, K and L and round 1's step C. The hints, the take-in at Restart or launch, and the push after a check behave as described there.

## Threat surface

There is no new network, file or permission surface. One new defaults key, `SettingsSyncKeptLayoutDigest`, holds a string read with a type check. It starts with "SettingsSync", so it is never exported, imported or synced. `SettingsSyncRecentLayoutDigests` now holds up to 64 strings. The sync file format is unchanged. Logs carry no digests, ids or values.

## Self-Check: PASSED

- The eight commits `88a8ac31` to `94412993` exist on `audit-manual/sync-fix` after `c537deff` (`git merge-base --is-ancestor`).
- All modified files exist.
- The gates passed before each commit, and the full `swift test` passed before this one.

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
