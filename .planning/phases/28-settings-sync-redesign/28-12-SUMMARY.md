---
phase: 28-settings-sync-redesign
plan: 12
subsystem: sync
tags: [swift, sync-engine, simulator, regression-catalogue, swift-testing, d3, judges, a2-catalogue]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-10 CatalogueScenario, Catalogue harness and A1 S-01 to S-33; 28-06 to 28-09 simulator, oracles and the real engine"
provides:
  - D3-S01 to D3-S20 and the judges' J-01 to J-16 as fixed tests on the real engine
  - the 17 scenarios of A2 section 7 that no earlier scenario asserts (SC-08, SC-16, SC-17, SC-24, SC-30 to SC-36 in their macOS 27 form, SC-46, SC-47, SC-64, SC-65, SC-70, SC-71)
  - A2Mapping, which maps every id of A2 section 7 to the scenario that asserts it, and the coverage checks over every catalogue id
  - five engine fixes that the scenarios found (see Deviations)
affects: [28-11 coverage test (union with CatalogueCoverage), 28-13 mutation gate and G1 campaigns]

actuals:
  tokens: 45000
  tasks: 3
  commits: 6
plan_head_before: 569f595b57b6def373dd4d74b988b46c26d2094d
plan_head_after: 676846ede2b00b40182b3a4c082c01568840f891

tech-stack:
  added: []
  patterns:
    - "A world that creates a collision, a hotkey or planted files on purpose names the oracles it leaves out, with the reason, next to its builder"
    - "A build of the engine is a SimMacRedesign with its own table, load-time writer, alias map and hotkey family; a scenario picks builds with .brains { version, mac in ... }"
    - "CATALOGUE_ONLY=<ids> selects scenarios of a catalogue file (CatalogueExtraTables.selected) so a single scenario can be run while it is written"

key-files:
  created:
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueD3.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueJudges.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueA2Residual.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueExtraCoverageTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueExtraTables.swift
  modified:
    - holzBar/Core/Sync/SyncMerge.swift
    - holzBar/Core/Sync/SyncIdentity.swift
    - holzBar/Core/Sync/SyncAnswer.swift
    - holzBar/Core/Sync/SyncEngine.swift
    - holzBar/Core/Sync/SyncLayout27.swift
    - holzBar/Core/Sync/SyncPlan.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMacRedesign.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimWorld.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimEvents.swift

key-decisions:
  - "D3-S10 splits in two: a state restored alone keeps its ID and the counter ends above the own file; a state that is lost is a new installation of one ID, which the own file shows as another installation, so the engine takes a new ID and keeps every entry (no dot repeats either way)"
  - "The A2 mapping targets S-ids by a literal range S-01 to S-70 and checks the S-ids up to S-33 against the files of plan 28-10; once plan 28-11 is merged, CatalogueCoverage.scenarios supersedes the local union of registered scenarios"
  - "SC-04 is mapped to SC-33: the arrangement of a fresh Mac counts as the user's (A1 S-08), so the silent form of SC-04 holds for the upgrade that SC-33 asserts"
  - "The random campaigns (SC-70) drain with one answer at a time and allow each Mac one more question on a provider with faults; the settings and arrangement events they draw are the ones the catalogue table syncs"

patterns-established:
  - "A scenario that finds an engine fault gets a unit test at the level of the fault (MergeTests, IdentityTests, AnswerTests, Layout27Tests) next to its catalogue test"

requirements-completed: [SYNC-R04, SYNC-R06, SYNC-R07]

duration: not measured (one run)
completed: 2026-10-08
status: complete
---

# Phase 28 Plan 12: D3, judge and A2 scenarios Summary

**D3-S01 to D3-S20, J-01 to J-16 and the 17 A2 scenarios that nothing else asserts now run as fixed tests on the real engine in the simulator, every A2 id of section 7 is mapped to the scenario that asserts it, and the scenarios found five real faults in the engine, all fixed with unit tests.**

## Accomplishments

- **Task 1, tracer (D3).** 20 scenarios in `CatalogueD3`: different settings merge, one question per Mac and one answer for both, three values and a fourth that arrives while the sheet is open, simultaneous answers, a bystander, a hotkey clash on the app's real family, a retired Mac, the return from beta1, restored preferences, a lost or restored-alone state, a copied account, crashes between apply and persist, a newer build's units, an oversize icon, founding from a beta1 file, profiles on macOS 27 only, a `defaults write` while quit, a duplicate installation, Turn Off with edits on both sides and seventy Macs in the folder.
- **Task 2 (judges).** 16 scenarios in `CatalogueJudges`, including the version skew of J-03 (`SimMacRedesign.skew`: a second unit table with another appearance normalizer and a load-time writer), beta2's writers (J-04), a restore with the clock set back (J-06), a join with a dataless file (J-07), an item that changes its key (J-09) and two installations under one ID (J-10).
- **Task 3 (A2).** 17 scenarios in `CatalogueA2Residual`, and `CatalogueExtraCoverageTests` with `A2Mapping.covers` (55 ids, one per line, with the place where each meets its scenario) and five checks: every id mapped, nothing else mapped, every target registered, no duplicate id, D3 and J ids exactly as expected.
- **Simulator additions.** `SimMacRedesign.skew`, a load-time writer, an alias map, the hotkey family of the app; events `duplicateInstallation`, `rekeyItem`, `defaultsWriteWhileQuit`, `plant` (a valid file of a Mac that is not simulated); `SimMacSpec.alsoOnDisk`; `SimDrainConfig.answerOneAtATime`; `SimMacBeta2.reencoded`.

## Test results

- `swift test --filter CatalogueD3`: 20 cases pass (1 to 10 s). `CatalogueJudges`: 16 pass (1 to 6 s). `CatalogueA2Residual`: 17 pass (45 to 60 s, almost all of it SC-70: three seeds on the ideal provider and on iCloud, 200 steps each, then a drain). `CatalogueExtraCoverage`: 5 pass.
- Full `swift test` (SDK 26.5, testing plugin path): 904 tests in 102 suites. The only failures were the known load-sensitive timing checks of `BlockingWork`, `Task timeout` and `SpacingRelaunch` (seven expectations, while the simulator suites ran next to them); the same 31 tests pass alone in 0.3 s.
- SwiftLint `--strict`: 0 violations in 241 files. `Scripts/typecheck-app.sh`: passes.
- Acceptance greps: 20 lines `CatalogueScenario(id: "D3-S`, 16 lines `CatalogueScenario(id: "J-`, 17 lines `CatalogueScenario(id: "SC-`, 55 mapping lines with `"SC-` in the coverage file, `D3-S16` present, `duplicateInstallation` in `SimEvents` and `SimWorld`, `func skew` in `SimMacRedesign`.

## Task Commits

1. `c1cbfcb3` test: D3-S01 to D3-S20 and the simulator additions they need (Task 1)
2. `758b1a7d` fix: a re-identification gives every entry of the old identity a dot of the new one (found by D3-S18)
3. `0df04abe` fix: a file that covers an own dot it cannot have seen makes the Mac re-identify (found by J-06 and J-10)
4. `c7d75737` test: J-01 to J-16 (Task 2)
5. `2634fd5b` fix: a user's change made while a sheet is open is never lost to the answer or to a crash (found by SC-70)
6. `676846ed` test: the A2 residual scenarios, the A2 mapping and the coverage checks (Task 3)

## Deviations from Plan

### Auto-fixed Issues (real engine faults, Rule 1)

**1. [Rule 1 - Bug] A collision found through a copy of the own file lost the change of one installation** (D3-S18; `SyncMerge`).
- **Issue:** two installations under one ID mint the same counter for different units. A copy of the own file names the collision but not the dots, so the re-identification marked nothing. The other installation's file then covered the old dot without holding the entry, and the join dropped it: a setting changed on one installation never reached the group.
- **Fix:** the merge mints every entry of the old identity again under the new one, with the same value.
- **Tests:** `MergeTests.reidentificationMintsAgain`.

**2. [Rule 1 - Bug] The reuse check missed a dot below the own file's counter, and the installation that did not re-identify first never noticed** (J-06 and J-10; `SyncIdentity`, `SyncMerge`).
- **Issue:** the check counted from the published counter after the own file had raised it, and only above it. A restore with the clock set back minted a dot that the own file covered without holding; the join dropped the new entry. With per-device winners the second installation kept its dot because a context that covers it without holding anything for the unit was no sign.
- **Fix:** the check counts from what the state had published before the read, lets the own file explain a dot it holds or supersedes, and takes a covered dot with no entry for its unit as a collision (`suspectCollidingDots`).
- **Tests:** `MergeTests.coveredDotWithoutEntryReidentifies`, `IdentityTests.neverSeenDotsAreSuspect`, `IdentityTests.ownFileExplainsDots`.

**3. [Rule 1 - Bug] An answer replaced a value the user had set after the sheet showed the row** (SC-70; `SyncAnswer`).
- **Issue:** while a join waits nothing is captured, so Use applied the folder's value over a newer local value and the baseline took the applied value: the user's change was lost without a question.
- **Fix:** a row whose local value no longer is the one the sheet showed is left out of the answer; the change is captured after it.
- **Tests:** `AnswerTests.rowWithAChangedLocalValueIsLeftOut`.

**4. [Rule 1 - Bug] A move of the macOS 27 arrangement queued while a join waited was lost by a crash** (SC-70; `SyncLayout27`, `SyncPlan`).
- **Issue:** the intent lived only in the session; an intent cannot be found again by comparing the defaults, and the plan took a value over an applied entry for holzBar's own store.
- **Fix:** the unit is marked as a value of the user's while the intent waits; a marked value over an applied entry is asked about.
- **Merge with 28-11:** a marked value over an applied entry is asked about only where the group moved on (an entry that is not applied is live). Where the group holds only the entry this Mac applied, the marked value is published as a newer change of it (28-11, S-48), never taken for holzBar's own store and never asked; `Layout27Tests.markedValueOverOnlyTheAppliedEntryIsPublished` covers that case.
- **Tests:** `Layout27Tests.queuedIntentIsMarked`, `Layout27Tests.markedValueOverAppliedEntryIsAsked`.

**5. [Rule 1 - Bug] A change of a key that does not sync postponed the capture of a user's change** (SC-71; `SyncEngine`).
- **Issue:** every `defaultsChanged` restarted the capture timer, so a learned list or a flag written within two seconds of an edit delayed its publication (and changed the order of writes between two runs that differ only by such writes, which INV-A1 compares).
- **Fix:** a change that alters no synced value and no alias schedules nothing.
- **Tests:** `Layout27Tests.unchangedSnapshotSchedulesNothing`.

### Auto-fixed simulator faults (Rule 3, files outside `files_modified`)

- `SimMacRedesign.snapshot` compared JSON settings raw; the app's projection normalizes them (J-03, J-04). It normalizes now.
- A join's request to download a file never reached the folder the user chose (the Mac has no folder yet), so a dataless file stayed dataless for ever (J-07).
- A crashed Mac went on reporting the hint it had (`cachedView`, `cachedReport.menuHint`).
- New events and spec fields are additive: `duplicateInstallation`, `rekeyItem`, `defaultsWriteWhileQuit`, `plant`, `SimMacSpec.alsoOnDisk`, `SimDrainConfig.answerOneAtATime`, `SimMacBeta2.reencoded`; `SimScenarioPrinter` and the exhaustive switches know them.

### Deviations from the plan's text

**6. [Scope] D3-S10 (lost state).** D3 says the counter goes above the own file. For a state that is lost the engine re-identifies instead (the own file belongs to another installation of the ID), which keeps every dot unique too; the restored-alone half asserts the counter. D3-S13: the engine has no status line for an unknown unit of a newer build (it is relayed silently); the scenario asserts the relay byte for byte, never applied, never deleted, and `unusableValue` for a value the build cannot use. `newerFormat` is asserted in SC-46.

**7. [Scope] Oracles left out of single worlds, each with its reason in the test.** Hotkeys carry no token, so D3-S06, J-02 and J-09 use only the oracles of files and bytes (INV-S6, S8, PR2, B1, B9, N1, Z1, Z6). D3-S04 (both Keep): INV-P1, P3 and P7, because the ground truth has no model of two answers that cross. D3-S18, J-06, J-08, J-10: INV-ID1, ID2, ID3, S3, S7, F5 where the world is a collision or a restore on purpose (the reason 28-10 gave for ID2). D3-S20 (planted files of unsimulated Macs): the oracles that follow the origin of a value. J-14: INV-F5, because `pre` values have no past in the ground truth. These are open items for plan 28-13.

**8. [Scope] The A2 mapping.** SC-04 is mapped to SC-33 (see key decisions). The targets S-34 to S-70 are validated only against the literal range until plan 28-11 is merged; the duplicate-id check sees G1 to G5, D3, J and A2 only. After the merge, `A2Mapping.registered` should be replaced by `CatalogueCoverage.scenarios`.

**9. [Scope] SC-70 and SC-71.** The campaigns use the lax table of the catalogue and leave out icon events and the automatic writes that the engine does not synchronize by decision (`autoPlace`, `seed27`, `placeNewApp27`; SC-24 and SC-33 hold the stores that do exist). SC-70 drains with one answer at a time: with every sheet answered before anything is delivered, two Macs that both press Use for one conflict swap values and are asked again for as long as the answers repeat (D3-S04), which breaks the bound of INV-C3 without breaking safety. On a provider with faults each Mac may ask once more.

**10. [Process] TDD.** Tasks 2 and 3 are `tdd="true"`, but the engine existed, so the scenarios were written against it; every engine fault above was found red by a scenario, fixed, and given a unit test.

## Known issues and notes

- **Transient hint after the user's own change** (open since 28-10): editing a unit that already has an entry shows "Settings changed on another Mac" for up to two seconds. SC-32 avoids it by writing new hotkeys; it is not fixed here.
- **A Mac whose own file is among the files left out** (more than 64 files, the simulated provider reads the first by name) polls for ever. The app reads the most recently modified files, which include the file just written, so D3-S20 gives the reader the first name.
- **Runtime:** SC-70 takes 40 to 55 s; the other 52 scenarios of this plan take about 10 s together. The seeds are in `CatalogueA2Residual.drainSeeds` and `campaignSeeds`.
- **Plan 28-13:** the mutation gate should be run over these scenarios; the engine fixes above add guards that the gate's mutations (skip the reuse check, remove the applied filter) should now find killed by J-06, J-10 and D3-S18.

## Known Stubs

None.

## Threat Flags

None beyond the plan's register: T-28-29 (every scenario asserts its Must, the mapping test fails on an unmapped id, a mapping to an unregistered id, a duplicate id and a missing D3 or J id).

## Self-Check: PASSED

- Created files exist: `CatalogueD3.swift`, `CatalogueJudges.swift`, `CatalogueA2Residual.swift`, `CatalogueExtraCoverageTests.swift`, `CatalogueExtraTables.swift` under `Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/`.
- Commits `c1cbfcb3`, `758b1a7d`, `0df04abe`, `c7d75737`, `2634fd5b`, `676846ed` are ancestors of HEAD.
