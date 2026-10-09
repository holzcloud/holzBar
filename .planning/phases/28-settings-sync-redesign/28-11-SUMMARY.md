---
phase: 28-settings-sync-redesign
plan: 11
subsystem: sync
tags: [swift, sync-engine, simulator, regression-catalogue, swift-testing, a1-catalogue]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-10 CatalogueScenario/Catalogue harness and S-01 to S-33, 28-06 to 28-09 simulator, oracles and the real engine in the simulator"
provides:
  - S-34 to S-70 of the A1 catalogue as fixed tests on the real engine (groups G6 to G10), SCOPE scenarios in a generation-26 and a generation-27 form
  - CatalogueCoverage.scenarios and a coverage test: S-01 to S-70 once each, classed as Appendix B, 33 PASS, 27 SCOPE, 10 BOUNDARY
  - two engine fixes found by S-48 and S-65 (a move made while sync is off, a hint for the Mac's own uncaptured edit)
affects: [28-12, 28-13 gates and mutation run]

actuals:
  tokens: 41000
  tasks: 3
  commits: 5
plan_head_before: 569f595b57b6def373dd4d74b988b46c26d2094d
plan_head_after: 3f9b67750483cd3ef9a7e2e026a9c9b7c3652bf2

tech-stack:
  added: []
  patterns:
    - "The provider's own fault operations drive every file-lifecycle scenario: deleteFile(of:), provider(.deleteFolder()), markFile/restoreFile, foreignFile(of:_:); no scenario edits a Mac's state"
    - "An answer is driven through SimScenario.answer(_:); CatalogueG7Answers.answer(_:_:_:) answers only when a sheet is open, expectFreshAnswer asserts one fresh own entry and exactly that entry live"
    - "askedWorld/keptWorld (G6) are the shared world of S-37 to S-54: B arranges and changes a setting while A, offline, changes it the other way; A is asked, then answers"

key-files:
  created:
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG6FileFaults.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG7Answers.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG8Automatic.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG9Races.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueG10Convergence.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueCoverageTests.swift
  modified:
    - holzBar/Core/Sync/SyncPlan.swift
    - Tests/HolzBarCoreTests/Sync/PlanTests.swift
    - Tests/HolzBarCoreTests/Sync/Layout27Tests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/CatalogueSupport.swift

key-decisions:
  - "The answer of the redesigned engine takes in every non-conflicting entry at once, so the A1 wording 'A takes L2 in at its restart' became 'A holds L2 after the answer' in the generation-27 forms (S-45, S-47 to S-49), and 'a drag before the restart asks' became: a drag made while the sheet is open returns as a question after the answer, a drag made after the answer is a newer change that B takes in at its restart"
  - "S-43 covers the five foreign-file kinds the provider offers plus a decode check for an empty file; a symbolic link has no size in the simulator and never counts as a lasting refusal (isLastingRefusal needs size > 0), so B keeps waiting and never writes over the link instead of re-identifying"
  - "S-65 is a sequence of events around the 2 s capture timer and a stalled provider (the simulator runs one event at a time and cannot interleave an edit into an exchange); S-70 case 5 uses sigmaLost, not reinstall, because a reinstalled Mac has no memory of its old identity and reads its own old file as another Mac's"
  - "Texts for S-34 to S-70 are registered in Catalogue.a1Tables with one appended line per group; the coverage test also requires an A1 text for every id"

patterns-established:
  - "A group file exposes scenarios and texts; CatalogueCoverage.scenarios unions the ten group files, and CatalogueCoverage.problems(in:) is the check that plan 28-13's gate script can reuse"

requirements-completed: [SYNC-R04]

duration: not measured (one run)
completed: 2026-10-08
status: complete
---

# Phase 28 Plan 11: A1 catalogue S-34 to S-70 Summary

**S-34 to S-70 of the A1 regression catalogue (file faults, answers, automatic versus user changes, races, convergence) run as fixed tests on the real engine, every SCOPE scenario in a generation-26 and a generation-27 form, and a coverage test proves S-01 to S-70 are present once each and classed 33 PASS, 27 SCOPE, 10 BOUNDARY. The run found and fixed two real engine bugs.**

## Accomplishments

- **Tracer (Task 1), G6, S-34 to S-44 (16 entries).** Every fault is the provider's own: a deleted file (`deleteFile(of:)`), a deleted folder (`.deleteFolder()`), a restored older version (`markFile`/`restoreFile`), a foreign file over the file. S-34 and S-39 run with the other Mac offline so it never reads the lost write; S-37 and S-38 (Keep, then the file goes away, then a second write) assert in the generation-27 form that A's automatic placement is never promoted over B's intent and that every Mac ends with B's newest arrangement; S-40 to S-42 assert INV-S3 and INV-F5 through the oracles and the entries A publishes; S-43 runs the five foreign kinds (symbolic link, oversize, truncated plist, wrong-shape plist, garbage) plus the empty file; S-44 joins a second Mac to the new folder with S-01 behaviour.
- **G7, S-45 to S-54 (16 entries).** Answers are driven through `SimScenario.answer`, with the shown rows asserted (`expectShown`) and the answer asserted to leave one fresh entry (`expectFreshAnswer`). S-45 has three variants (the plain Keep, a move of the same application while the sheet is open, a move after the answer), S-48 three ways to re-join (off and on, Change… to the same folder, off then drag then on), S-51 and S-52 both buttons, S-54 four losses of the record (state lost, older state restored, crash right after the answer, sync turned off).
- **G8 to G10, S-55 to S-70 (26 entries) and the coverage test.** Automatic events (`placeNewApp27`, `seed27`, `autoPlace`, `applyProfile(byUser: false)`, `learn`, `setFlag`) never create a dot, a hint on another Mac or a question; S-62 runs a real `SimMacBeta2` Mac that updates to the new build; S-65 repeats an edit at seven distances around the capture timer, with and without a stalled provider; S-69 relays an arrangement through a macOS 26 Mac whose writer is gone and has a third Mac join later; S-70 runs the five bookkeeping-gap cases including 70 re-identifications of one Mac (more than 64 files in the folder). `CatalogueCoverage.problems(in:)` reports a missing, duplicate or misclassed id, a scope scenario without both forms and a scenario without its A1 text; a third test shows it catches each of them.

## Test results

- Catalogue: G6 16, G7 16, G8 16, G9 6, G10 4 entries pass; G1 to G5 (28-10) pass; coverage 3 tests pass. The whole catalogue runs in about 25 s.
- Full `swift test` (SDK 26.5, testing plugin path flag): 902 tests in 104 suites. The only failures were the six known load-sensitive timing checks of `Task timeout` and `SpacingRelaunch`; `TaskTimeout|SpacingRelaunch|BlockingWork` pass alone (31 tests).
- SwiftLint `--strict`: no violation. `Scripts/typecheck-app.sh`: passes.
- Acceptance greps: 16, 16, 16, 6 and 4 `CatalogueScenario(id: "S-` lines in G6 to G10; 13 lines with `deleteFolder|restore` in G6; 18 lines with `answer(` in G7; `S-70` in the coverage file.
- Mutation spot checks (the full gate is plan 28-13): treating every Mac's automatic store as an intent (`automaticStoresAreIntents`) is killed by 11 scenarios (S-45, S-47 to S-49, S-54 to S-56, S-59, S-61, S-67, S-69); removing the S-48 fix is killed by S-48/27; removing the S-65 fix is killed by S-65 and S-70. One guard survives: `SyncPublish`'s `ownFileNotDominated` (28-10 hoped the restore scenarios would kill it). The own file is joined into the state in the same read that sets the flag (`SyncMerge`, `dominated` is computed right after the join), so the guard cannot be false from any event the simulator has; it is defence in depth for a join that is not idempotent, an equivalent mutation here, left to the gate of plan 28-13.

## Task Commits

1. **Task 1: Tracer, G6** - `b7558c23` (test)
2. **Engine fix found by S-48** - `637a27bd` (fix)
3. **Task 2: G7** - `d52f4e6b` (test)
4. **Engine fix found by S-65** - `d38596cb` (fix)
5. **Task 3: G8 to G10 and coverage** - `3f9b6775` (test)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The worktree started on `main`** - reset to `planning/sync-redesign` (569f595b).

**2. [Rule 1 - Bug] A move made while sync is off was settled as equal at the next join** (found by S-48/27, "off, drag, on").
- **Found during:** Task 2. After Keep, A took B's arrangement in; A turned sync off, moved the application and turned sync on. The Macs ended with different arrangements, nothing asked, no hint on A.
- **Issue:** 28-10's fix marks such a move `preexisting`, but `SyncPlan` has a branch for intent-captured units whose live entries are all applied, which says `equal`, and `settle` then records the user's value as the baseline: the move was neither published nor asked about.
- **Fix:** that branch publishes a unit the user marked as theirs (`.publishPreexisting`, minted over exactly the entry this Mac applied). A value that holzBar itself stored (no mark) is still `equal`.
- **Files modified:** `holzBar/Core/Sync/SyncPlan.swift`, test in `Layout27Tests.swift`.
- **Commit:** `637a27bd`

**3. [Rule 1 - Bug] A hint for the Mac's own uncaptured edit** (found by S-65 and S-70, INV-L1; the cosmetic issue 28-10 noted and left).
- **Issue:** between a user's edit and its capture (two seconds) the plan read the new local value against the Mac's own live entry as a fast-forward, so the Mac showed "Settings changed on another Mac" for its own change. It would also have applied the own entry over the edit if a restart reached the plan before the capture.
- **Fix:** a new outcome `.pendingLocal`: the only live entries are this Mac's own (`isOwn`, which includes earlier identities) and the local value differs from the captured baseline. It is no fast-forward, no row and no hint, and `settle` leaves it alone, so the capture still finds the edit.
- **Files modified:** `holzBar/Core/Sync/SyncPlan.swift`, test in `PlanTests.swift`.
- **Commit:** `d38596cb`

**4. [Scope] Catalogue wording adapted to the engine's design** (each with a comment in the test): see key-decisions. S-45/27, S-47/27, S-48/27 and S-49/27 assert that the answer takes B's arrangement in at once (no Restart hint on A) and that a later drag is a newer change B takes in at its restart; a drag made while the sheet is open returns as a question after the answer (S-45 moved, S-64 same application). S-46 accepts "taken in with the answer or offered as a hint" for the entry that arrived while the sheet was open (the engine takes it in). S-35 and S-36 assert "applied or still offered" after a relaunch with the file missing.

**5. [Scope] Files outside `files_modified`:** `CatalogueSupport.swift` (one appended line per group in `Catalogue.a1Tables`, as the shared-file instruction for plan 28-12 asked), `SyncPlan.swift`, `PlanTests.swift` and `Layout27Tests.swift` for the two fixes.

**6. [Process] TDD.** Tasks 2 and 3 are `tdd="true"` but the engine existed, so the scenarios were written against it; S-48/27 and S-65 were red before their fixes. No separate RED commits.

## Known issues and notes for the following plans

- **Simulator limits, asserted around rather than through.** The simulator cannot make an empty file or a folder in place of the file or of the `Macs` folder (S-43 asserts the empty case on the decoder and covers the symbolic link, which the simulator models with no size), cannot interleave an edit into a running exchange (S-65 uses event sequences around the capture timer and a stalled provider).
- **Symbolic link at the Mac's own path.** `isLastingRefusal` requires `size > 0`, so a link of no size never makes the Mac re-identify: it waits and never writes over the link. In the app a link has a size, so this only shows in the simulator.
- **Plan 28-12** adds its texts with one appended line in `Catalogue.a1Tables`; `CatalogueCoverage.problems(in:)` and `.scenarios` are ready for its own coverage test and for plan 28-13's gate script.
- **Plan 28-13 mutation run:** `ownFileNotDominated` (SyncPublish) survives as an equivalent mutation, see above.

## Known Stubs

None.

## Threat Flags

None beyond the plan's register: T-28-28 (the coverage test fails on a missing, duplicate or misclassed id, a scope scenario without both forms and a missing A1 text; every scenario asserts its Must and ends with `expectNoViolation` over the safety and layout oracles; three engine mutations are killed by these tests).

## Self-Check: PASSED

- Created files exist: the six files under `Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/` (G6 to G10 and coverage).
- Commits `b7558c23`, `637a27bd`, `d52f4e6b`, `d38596cb`, `3f9b6775` are ancestors of HEAD.
