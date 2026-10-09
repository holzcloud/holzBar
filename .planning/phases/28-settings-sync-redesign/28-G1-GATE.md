# Gate G1: the simulator proves the sync engine

- Date: 2026-10-09
- Commit: 74893795 (tests of the squashed plan commits; the run started at the commit before the squash, with the same tree)
- Result: **G1: FAILED** (G1: PASSED is written only when every part passed; this record was written by hand because the run did not end inside the time box, see "Mutation gate")

Not passed because: the sync suites failed at the bounded budget (disturbed worlds and two pair tests, below); eleven invariants are open exclusions of the clean worlds; the budgets are below the plan's (100 seeds per preset instead of 10,000, depth 6 instead of 8, 20,000 fuzz inputs instead of 1,000,000); the mutation gate had not ended.

## Budgets that ran

`SYNC_GATE_SEEDS=100 SYNC_GATE_STEPS=400 SYNC_GATE_DEPTH=6 SYNC_GATE_FUZZ=20000 SYNC_GATE_MUTATION_SHARDS=4 Scripts/sync-gate.sh --full --record`, release build, 500 tests in 51 suites in 1387 s.

## Seeded runs of the real engine (seeds 1 to 100 of every preset, 400 steps, each with its drain)

- Clean worlds (no event that destroys what a Mac's sync state knows; every invariant but the open exclusions): iCloud, Dropbox, OneDrive, Nextcloud, Syncthing, SMB, hostile: 100 seeds each, **700 worlds, no violation** outside the open exclusions.
- Disturbed worlds (clone, copied account, restore of preferences, Sigma or home, lost Sigma, reinstall drawn too; the invariants of `SimExploration.evidenceLossExclusions` left out): the blocks of iCloud (100 seeds) and hostile (50 seeds) passed; the other blocks failed on the first seed shown below, so their seed counts are not recorded:
  - INV-C4 relaunches alone keep a hint or a sheet open: syncthing seed 88 (step 722), oneDrive seed 83.
  - INV-F7 a Mac wrote while its folder was unmounted: smb seeds 79 and 5, hostile seed 71.
  - INV-A6 a deletion that no user made (a re-key): nextcloud seed 77, oneDrive seed 45, dropbox seed 45.
  - INV-J1 a join committed with an unread file: dropbox seed 74.
  - INV-ID1 two Macs with one device ID after a launch: nextcloud seed 31.
  - INV-S6 a write over an own file not read in the session: syncthing seed 22.
- Trace hashes: 70 reproduced by a second process.

## Metamorphic and delivery pairs (failed at this budget)

- INV-A1 "Mac B published the automatic change auto-B-5": seed 17, every preset (the check that no file says a value no user made; whether the engine or the pair is wrong is not decided).
- INV-F2 another delivery order ended differently: seed 7, every preset (B ends with `u3@ItemSpacingOffset` in one order and `u2@UseIceBar` in the other).
- At the CI budget both pairs pass.

## Control engines (each must be caught within seeds 1 to 200)

All six caught at seed 1: last writer wins by clock, shared file written beta1-style, no applied-context rule, overwriting an unread own file, minting at launch for an untrusted state, equal-to-default as unset.

## Bounded exhaustive families (depth 6)

- edits and answers: alphabet 15, 154,575 runs, 64,436 distinct states
- file events: alphabet 11, 64,801 runs, 30,576 states
- identity events: alphabet 12, 52,800 runs, 18,760 states
- a beta1 Mac: alphabet 12, 162,372 runs, 73,161 states
- arrangement moves: alphabet 12, 118,644 runs, 52,369 states
- No violation. Depth 8 was not run.

## Fuzzing

The `CodecFuzz` suite (device file, state, legacy reader) passed with 20,000 inputs configured. The suite does not report how many inputs went to each codec, so the per-codec counts are not in this record (a gap of the report, not of the run).

## Determinism lint

`.github/scripts/sync-lint.py` (self-test of 27 fixtures, then the sources) passed; it runs in the CI job "Sync code rules".

## Open exclusions

These invariants are left out of the seeded runs, in both families, until their causes are known (`SimExploration.openExclusions` has the reason and the rate of each). The exploration of 7,000 worlds of 400 steps found them at about 0.65 % of the worlds in total:

- INV-S5 (a deletion made while sync is off or a join waits, followed by a join into a deleted folder, is not in the published file): hostile 173, 334, 392, 413, 431, 569, 570, 704, 709, 861, 894, 937; iCloud 230, 814; nextcloud 201.
- INV-C6 (a fresh Mac differs from the agreed state after the drain): iCloud 252; nextcloud 419, 689, 912; dropbox 439, 628; oneDrive 700; hostile 731.
- INV-C1 (two Macs disagree after the drain): dropbox 689, 945; hostile 731.
- INV-P1 (a question without a witness in the truth): nextcloud 278, 747, 889; dropbox 300, 423; syncthing 583; smb 624; iCloud 684.
- INV-B4 (a second question about the same content of the older peer's file): dropbox 157; nextcloud 410, 920; smb 856.
- INV-F5, INV-S3, INV-L6, INV-P3, INV-F1, INV-Z4: iCloud 276, dropbox 505 (F5); nextcloud 256, iCloud 684 (S3); dropbox 157 (L6); iCloud 737 (P3); iCloud 160 (F1); smb 157, dropbox 845 (Z4).

The seeds are of the exploration with `SimExploration.run(seed:preset:steps: 400, evidenceLoss: false)`.

## Mutation gate

26 mutations are defined (`Scripts/sync-mutation-gate.py --list`); the gate ran in four shards after the suites, and had not ended when this record was written. **No kill count is claimed.** Earlier, one mutation (`ownFileNotDominated`) was known to survive the unit suites and was addressed with `MergeTests.publishPreconditions`; whether it is killed now is not confirmed by a full run.

## What to do next

Triage the open exclusions in the order S5, C6, C1, B4 (the four that may be faults of the engine), then the pair failures and the disturbed-world classes; run `Scripts/sync-gate.sh --full --record` at the plan's budgets when the exclusions are empty.
