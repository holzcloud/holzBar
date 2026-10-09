# Gate G1: the simulator proves the sync engine

- Date: 2026-10-09, second pass (the first record is below, kept as it was written, marked as superseded where this pass changed it)
- Commit of the second pass: see the last commit of the branch `worktree-agent-af6988495e5a00d23` (the tip after this record)
- Result: **G1: FAILED** (G1: PASSED is written only when every part passed; this record was written by hand, not by `Scripts/sync-gate.sh --record`, because the full gate did not fit in the three-hour box)

## What is still open (exactly)

1. **Open exclusions of the clean worlds** (`SimExploration.openExclusions`, 11 invariants, narrowed but not empty):
   - INV-S5: hostile seed 861 (14 of 15 recorded seeds closed).
   - INV-C6: nextcloud seed 912 and hostile seed 731 (6 of 8 closed). INV-C1: hostile seed 731 (2 of 3 closed).
   - INV-B4: nextcloud seed 920 (3 of 4 closed).
   - INV-P1, F5, S3, L6, P3, F1, Z4: not triaged in this pass. Several of their recorded seeds no longer trip after the engine fix (P1 nextcloud 747 and syncthing 583 and Z4 smb 157 and dropbox 845 no longer trip; F1 iCloud 160, F5 iCloud 276 and dropbox 505, S3 nextcloud 256 and iCloud 684, L6 dropbox 157, P3 iCloud 737 and P1 on five seeds still do); that is not an explanation and they stay excluded.
2. **Disturbed worlds** (not triaged in this pass; the failing seeds are the same as in the first record, so the engine fix changed none of them): INV-C4 syncthing 88 and oneDrive 83; INV-F7 smb 79 and 5, hostile 71; INV-A6 nextcloud 77, oneDrive 45, dropbox 45; INV-J1 dropbox 74; INV-ID1 nextcloud 31; INV-S6 syncthing 22.
3. **Pair tests** (not triaged in this pass): INV-A1 "Mac B published the automatic change auto-B-5" at seed 17, INV-F2 "another delivery order ended differently" at seed 7, in every preset, at the budget of 100 seeds (they pass at the CI budget).
4. **Budgets** below the plan's (10,000 seeds per preset, depth 8, 1,000,000 fuzz inputs); the second pass ran 100 seeds per preset and family at 400 steps, and did not re-run the exhaustive families and the fuzzing (their engine code is untouched except `SyncJoin.onJoinRead`, which neither covers).
5. The mutation gate is complete only if the line "Mutation gate" below says so.

## Second pass: what ran

- Reproduction and sweeps of the recorded seeds of the open exclusions with a release build (`SimTriageTests`, see `28-13-ADDENDUM.md`): 29 seeds of S5, C6, C1 and B4 before the fixes, 22 after, and the 22 seeds of the other exclusions.
- One engine fault fixed (a join into a folder whose files claim this Mac's own entries, `SyncJoin`, regression test `G1FixTests.folderThatHoldsTheMacsOwnEntriesIsItsGroup`) and three model gaps fixed (C1/C6 bystander-only conflict, S5 deletion of a value that can no longer be read, B4 sheet closed by a restart); details and the reasoning in `28-13-ADDENDUM.md`.
- The seeded runs at the bounded budget (release build, `SYNC_SIM_SEEDS=100 SYNC_SIM_STEPS=400`, the suite `SimulationTests`, 484 s): **clean worlds, all seven presets, seeds 1 to 100, 700 worlds, no violation outside the open exclusions.** Disturbed worlds: the blocks of iCloud (both halves) and hostile seeds 1 to 50 passed; the others failed on the seeds listed under 2 above (the first violation of each block only). Metamorphic and delivery pairs failed as listed under 3. Control engines: all six caught at seed 1 as before; 70 trace hashes recorded (not reproduced by a second process in this pass).
- The full `swift test` (debug build, CI budgets, 945 tests in 114 suites, with the machine at a load of 80 to 100 because the mutation gate ran beside it): the only failures are the known timing tests `BlockingWork`, `Task timeout` and `SpacingRelaunch` (7 issues); every sync and simulation suite passed. SwiftLint `--strict`: 0 violations in 241 files. `Scripts/typecheck-app.sh`: the app type-checks.

## Mutation gate (26 mutations, 4 shards of the unmodified table, baseline of 51 suites passed in every shard)

**Kill count: 19 of 26 confirmed killed, 0 confirmed survivors, 7 not decided (shard 1 had not ended at the end of the time box).**

- Shard 0 (7): killed applied-filter-removed, tripwire-check-skipped, clash-check-skipped, bystander-menu-hint, writer-limit-raised, profile-apply-replaces-sections. `answer-without-fresh-dot` was **stale** (its mutated source did not build: a closure that captured an inout parameter), so the table was repaired (`state.baseline[...] = digest; guard true else`) and the mutation was re-run alone with `--no-baseline` (the baseline of the same sources had passed in the other shards): killed by "Keep gives A a Restart hint, and A has B's value after it restarts".
- Shard 2 (6): killed reuse-check-skipped, passthrough-dropped, unread-own-file-overwritten, counter-floors-ignored, absent-equals-default, automatic-store-mints.
- Shard 3 (6): killed generation-check-skipped, local-only-applied, own-file-not-dominated, capture-during-join, aliased-unit-captured, absent-l27-as-deletion. `capture-during-join` was killed only by the simulation suites (the unit suites alone let it through, 967 s): a unit test of "nothing is minted while a join waits" is missing at the level of the engine.
- Shard 1 (7: covers-strict, refused-file-as-missing, join-with-unread-files, answer-supersedes-everything, pre-row-suppressed, generation-26-authors-l27, digest-unsorted): the script prints a shard's lines when it ends, and it had not ended after 53 minutes because `digest-unsorted` (SyncValue.swift) passed the unit suites and was in the run of all suites for more than 20 minutes. **No result is claimed for these seven.** `own-file-not-dominated`, the survivor of the first record, is killed now.
- Machine note: four shards plus the full `swift test` and the seeded runs ran at once (load 50 to 100); the baseline took 744 to 766 s. Run the shards one after another, or give a lone `digest-unsorted` its own run: `python3 Scripts/sync-mutation-gate.py --only digest-unsorted`.

## First record (before the second pass; superseded where the text above differs)

The first record said: the sync suites failed at the bounded budget (disturbed worlds and two pair tests); eleven invariants were open exclusions of the clean worlds; the budgets were below the plan's; the mutation gate had not ended. Of that, the second pass changed the open exclusions (narrowed as above) and the mutation gate (run, below); the disturbed worlds, the pair tests and the budgets are as they were.

Bounded exhaustive families of the first record (depth 6; edits and answers 154,575 runs, file events 64,801, identity events 52,800, a beta1 Mac 162,372, arrangement moves 118,644; no violation) and the CodecFuzz run (20,000 inputs, passed) and the determinism lint (passed) were not repeated.
