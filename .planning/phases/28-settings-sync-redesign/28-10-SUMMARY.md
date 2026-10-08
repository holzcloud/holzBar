---
phase: 28-settings-sync-redesign
plan: 10
subsystem: sync
tags: [swift, sync-engine, simulator, regression-catalogue, swift-testing, a1-catalogue]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-06 simulator DSL and oracles, 28-07 to 28-09 the real engine in the simulator (settings, join, macOS 27 families), SimMacBeta1 peer"
provides:
  - CatalogueScenario, Catalogue (worlds, settle, quiet, boundary checks, A1 texts, failure messages) and the SimScenario DSL additions the following catalogue plans reuse
  - S-01 to S-33 of the A1 catalogue as fixed tests on the real engine, SCOPE scenarios in their generation-26 and generation-27 forms, BOUNDARY scenarios with a real 0.0.7-beta1 peer
  - an engine fix found by S-17 (a move made while sync is off)
affects: [28-11, 28-12, 28-13 gates and mutation run]

actuals:
  tokens: 50000
  tasks: 3
  commits: 4
plan_head_before: 46c8196e26a303d66d1de199cf7d5d362cabafef
plan_head_after: 28de59b4a9f753344880243e5e3d44c2653c9185

tech-stack:
  added: []
  patterns:
    - "A catalogue scenario is a CatalogueScenario whose run builds one or more SimScenario worlds, ends each with expectNoViolation over the safety and layout oracles, and returns the failures; the failure message prints the A1 Setup, Steps, Wrong and Must"
    - "G5 scenarios are plain event lists (time passes with advance), so SimMetamorphic.clockIndependence repeats them under generated clock offsets and steps"
    - "A BOUNDARY scenario asserts through Catalogue.boundary: the redesigned build never writes the legacy file, shows only the old-group status line, and opens the sheets the scenario names"

key-files:
  created:
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueSupport.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG1Joining.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG2Infrastructure.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG3Generations.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG4BetaPeers.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG5Clocks.swift
  modified:
    - holzBar/Core/Sync/SyncLayout27.swift
    - Tests/HolzBarCoreTests/Sync/Layout27Tests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimScenario.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMacRedesign.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimSafetyOracles.swift

key-decisions:
  - "The catalogue uses its own unit table (the real setting names the beta1 peer's file carries, the icon with its 256 KiB cap, three large-cap units, the Hk family with a validator, the macOS 27 families scoped to generation 27), and a lax copy of it for the skewed build that makes a value unusable on the other Macs (S-12)"
  - "A scope scenario is two literal CatalogueScenario entries, S-15/26 and S-15/27, that call one function with the generation; Catalogue.forms(of:) exists for the plans that want it but this plan writes the pairs out so the acceptance greps count them"
  - "A BOUNDARY scenario runs on generation-26 and on generation-27 Macs inside one CatalogueScenario (one id, two worlds), because Appendix B classes it once"
  - "The beta1 boundary only counts writes of the legacy file that the redesigned build made (WriteRecord.brainKind), so a Mac that was on beta1 before its update is not charged for its beta1 writes"

patterns-established:
  - "perform(label) is the free step of the DSL: it drives or reads the world and returns one text per failure; settle, expectQuiet, expectBoundary, evictFile, restoreFile and the other catalogue steps are built on it"

requirements-completed: [SYNC-R04]

duration: not measured (one run, several hours)
completed: 2026-10-08
status: complete
---

# Phase 28 Plan 10: A1 catalogue S-01 to S-33 Summary

**S-01 to S-33 of the A1 regression catalogue now run as fixed tests on the real engine in the simulator, each asserting its Must and no oracle violation, with the macOS 27 arrangement form of every SCOPE scenario and a real 0.0.7-beta1 peer in every BOUNDARY scenario; the run found and fixed one real engine bug (a move made while sync is off was replaced silently at the next Restart).**

## Accomplishments

- **Tracer (Task 1).** `CatalogueSupport` holds the types of the plan's interface block (`CatalogueScenario`, `CatalogueSource`, `CatalogueKind`, `Catalogue.world`, `settle`, `quiet`, `a1Text`, `forms(of:)`), the unit table, the builders, the beta1 boundary check and the A1 failure message. `CatalogueG1Joining` covers S-01 to S-08 (S-01 in four worlds: absent keys, Keep, Use, Cancel; S-08 in two forms).
- **G2 and G3 (Task 2).** S-09 to S-12 (a dataless file and a hung provider at login, an unmounted share, files over the limit including the oversize icon and an oversize beta1 file, malformed entries both local and synced). S-13 to S-17 (S-15 to S-17 in their two forms) and S-18 and S-19 with a real beta1 peer.
- **G4 and G5 (Task 3).** S-20 to S-27 each on generation-26 and generation-27 Macs with a beta1 peer; S-28 to S-33 (S-29 and S-31 in two forms), every one repeated under two generator seeds of clock offsets and steps with equal decisions asserted (INV-F9).

## Test results

- `swift test --filter Catalogue`: G1 9 cases, G2 4, G3 10, G4 8, G5 8; all pass (about 7 s).
- Full `swift test` (SDK 26.5, testing plugin path flag): 892 tests in 98 suites. The only failures were the six known load-sensitive timing checks of `Task timeout` and `SpacingRelaunch` while `Scripts/typecheck-app.sh` ran next to it; the same 31 tests of `TaskTimeout`, `SpacingRelaunch` and `BlockingWork` pass alone.
- SwiftLint `--strict`: no violation. `Scripts/typecheck-app.sh`: passes.
- Acceptance greps: 9, 4, 10, 8 and 8 `CatalogueScenario(id: "S-` lines in G1 to G5; `struct CatalogueScenario` once; 12 lines with `SimMacBeta1` in G4 and one in G3; no `Date()`, `.random(`, `DispatchQueue` or `Task {` in the folder.
- Mutation spot check (the full gate is plan 28-13): removing the usability check in `SyncPlan` is killed by S-12; removing the intent mark of the fix is killed by S-17/27. Two guard removals (`ownFileNotDominated` in `SyncPublish`, the unavailable-folder guard in `SyncMerge`) survive the catalogue; the first belongs to the restore scenarios of plan 28-11 (S-34 and later), the second is an equivalent mutation here because the write path already fails on a read of an unmounted folder.

## Task Commits

1. **Task 1: Tracer, harness and G1** - `a0210dd6` (test)
2. **Engine fix found by S-17** - `33a227eb` (fix)
3. **Task 2: G2 and G3** - `6bc17a36` (test)
4. **Task 3: G4 and G5** - `28de59b4` (test)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The worktree started on `main`** - fast-forwarded to `planning/sync-redesign` (46c8196e).

**2. [Rule 1 - Bug] A move made while sync is off was replaced silently at the next Restart** (found by S-17/27, INV-S1 and INV-S1g).
- **Found during:** Task 2, S-17 "both rearrange": D turns sync off, the user moves an application on D, C moves it again and syncs, D turns sync on.
- **Issue:** `SyncEngine.onIntent` dropped every intent while sync is off. D had applied the older entry, so the group's newer entry was a fast-forward: D showed a Restart hint and applied C's section at its restart, and the user's move was gone without a question. 28-09 had assumed the join would ask; a Mac that keeps its state is joined through the plan, which only knows a unit as the user's present value when `localOrigin` says so, and intent-captured units are never found by diffing.
- **Fix:** an intent that arrives while sync is off marks the unit `preexisting` for a value (not for a deletion, not for a unit this Mac does not author). The plan then reads it as a pre row, so the join asks about it where the group differs and publishes it where the group has none. A plain setting already asked correctly.
- **Files modified:** `holzBar/Core/Sync/SyncLayout27.swift`, regression tests in `Layout27Tests.swift`.
- **Commit:** `33a227eb`

**3. [Rule 3 - Blocking] Files outside `files_modified`** (test infrastructure, all additive or an oracle correction):
- `SimScenario.swift`: a free `perform(label, body)` step and its builder, which every catalogue step (settle, quiet, boundary, evict, restore) is built on.
- `SimMacRedesign.swift`: `statusLines` and `folderAvailability` accessors for the status line and the "folder cannot be found" assertions.
- `Layout27Tests.swift` and `SyncLayout27.swift`: the fix above.
- `SimSafetyOracles.swift`, INV-ID6: it compared a file's claim on the Mac's own counter with the counter at the start of the step. A step that lets time pass can mint two dots and take in the relay that covers them, which flagged S-33 in its first form. It now uses the larger of the counter at the start and at the end of the step; a claim above both is still a dot the Mac never minted (`SimOracleTests` pass).

**4. [Scope] Oracles left out of single worlds, each with a comment in the test.** The first three read the simulator's ground truth, not the engine, and are open items for plan 28-13:
- **S-04, the world where A changes the same setting after Later: INV-P1 and INV-P7.** The ground truth reads Later as "the user was informed", so it sees no conflict at the question that returns at the next launch, which the engine shows by design (the open item 28-09 left).
- **S-11 writer (a state over 1 MiB): INV-Z3 and INV-Z4.** INV-Z3 reads the settings at the step of the edit, where the warning that follows the capture two seconds later is not there yet; INV-Z4 bounds the state by the devices seen and ignores a megabyte of values. The same property is asserted after the capture instead.
- **S-11 lasting refusal (a file of the Mac's own over the limit for ten minutes): INV-ID2.** The engine goes on under a new identity and marks the units of the old one as pre-existing instead of opening a join, which the oracle does not read as joining again; the scenario asserts that the refused path is never written.

**5. [Scope] A1 steps modelled for the per-device design.** S-18 to S-27 cannot show a beta1 write reaching a redesigned Mac, because the two builds never share a file (Appendix B); they assert the boundary instead (the legacy file never written, the old-group line as the only trace, no sheet, no hint, every arrangement untouched). S-23 gen-27: the answer's apply already takes B's non-conflicting arrangement in, so A's later drag is a new change and B keeps its own with a Restart hint, not a question. S-32: a missing write cannot cause a loss any more (Appendix B), so the Must asserted is that the last write is never reverted.

**6. [Process] TDD.** Tasks 2 and 3 are `tdd="true"`, but the engine existed already, so the scenarios were written against it. S-17 and S-12 were red before the fix and the mutation spot check; no separate RED commits.

## Known issues and notes for the following plans

- **Transient hint after the user's own change.** Between a user's change and its capture (two seconds) `SyncEngine.view` plans the new local value against the old live entry as a fast-forward, so a Mac shows "Settings changed on another Mac" for up to two seconds after its own change (found while writing S-11; INV-P7 excuses it, INV-L1 does not). Restart captures first, so nothing is lost; it is cosmetic and not fixed here.
- **`Later` then a move or edit.** Open since 28-09: the engine keeps B's value as a live sibling (a question at the next launch), the ground truth treats the change as superseding it (INV-P1, INV-P7). S-04 asserts the engine's behaviour, which is what A1 S-04 says ("a user change after Later turns into a question").
- **Plan 28-11 and 28-12.** Add their texts to `Catalogue.a1Tables`; `Catalogue.forms(of:)` is available but this plan writes its SCOPE pairs out as literal entries (the acceptance greps count literals). The scenario files avoid the settle helpers where a scenario is repeated under clocks (G5 uses `advance`), and any world with a long `advance` should be read with the INV-ID6 note above in mind.
- **Slow worlds.** None: the whole catalogue runs in about 7 s.

## Known Stubs

None.

## Threat Flags

None beyond the plan's register: T-28-27 (every scenario asserts its A1 Must plus `expectNoViolation` over the safety and layout oracles, prints its A1 text when it fails, and one engine fix and two mutation kills show the tests catch regressions).

## Self-Check: PASSED

- All created files exist (`[ -f ]`): the six files under `Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/`.
- Commits `a0210dd6`, `33a227eb`, `6bc17a36`, `28de59b4` are ancestors of HEAD.
