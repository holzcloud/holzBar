---
phase: 28-settings-sync-redesign
plan: 13
subsystem: sync
tags: [swift, sync-engine, simulator, exploration, fuzzing, mutation-gate, determinism-lint, gate-g1]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-06 to 28-09 simulator, oracles and the real engine; 28-10 to 28-12 catalogues"
provides:
  - seeded exploration of the real engine over seven provider presets in two families of worlds (clean and disturbed), with a drain, shrinking and a ready-to-paste scenario for every failure
  - bounded exhaustive families, codec fuzzing of the device file, the state and the legacy reader, a determinism lint with a CI step
  - the mutation gate (26 mutations), the six control engines, Scripts/sync-gate.sh and the gate record 28-G1-GATE.md
  - engine faults that the exploration found, each fixed with a test at the level of the fault (G1FixTests, Layout27Tests)
affects: [28-14 and later (the app may not use the engine until G1 passes)]

actuals:
  tokens: 400000
  tasks: 3
  commits: 5
plan_head_before: f9f2e6fc
plan_head_after: 74893795 (the four task commits; the docs commit follows)

key-files:
  created:
    - Tests/HolzBarCoreTests/Sync/Simulation/SimExploration.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimGateSupport.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimulationTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimExhaustiveTests.swift
    - Tests/HolzBarCoreTests/Sync/CodecFuzzTests.swift
    - Tests/HolzBarCoreTests/Sync/CanonicalPlist.swift
    - Tests/HolzBarCoreTests/Sync/G1FixTests.swift
    - .github/scripts/sync-lint.py
    - Scripts/sync-mutation-gate.py
    - Scripts/sync-gate.sh
    - .planning/phases/28-settings-sync-redesign/28-G1-GATE.md
  modified:
    - holzBar/Core/Sync (SyncAnswer, SyncJoin, SyncLaunch, SyncEngine, SyncCapture, SyncState, SyncLayout27, SyncPlan, SyncIdentity, SyncMerge and the lint markers)
    - Tests/HolzBarCoreTests/Sync/Simulation (simulator, ground truth, oracles, generator, adapter)
    - .github/workflows/build.yml

key-decisions:
  - "Two families of worlds. A clean world draws no event that destroys what a Mac's sync state knows and is judged by every invariant; a disturbed world draws them too (clone, copied account, restore of preferences, Sigma or home, lost Sigma, reinstall) and leaves out the invariants listed with a reason in SimExploration.evidenceLossExclusions"
  - "Open exclusions are explicit. The invariants that the 400-step exploration of a clean world still trips at a low rate are listed with their rates in SimExploration.openExclusions, are repeated in the gate record, and keep the gate from saying G1 passed"
  - "A later change on a unit by the same Mac inside the capture delay is one change (the engine coalesces it); the pairs of the metamorphic tests and the oracles use the net effect, and a pair of runs is compared on an ideal provider, where one more write cannot shift the random streams of the provider"
  - "A Mac that ran a redesigned build is never moved back to a build that reports no intents in a clean world; downgrades belong to the disturbed family"
  - "A move to the visible section removes the entry in the simulated defaults, as the app does (D-04); a move to where the application already is changes nothing"

requirements-completed: []

duration: not measured (several sessions)
---

# Phase 28 Plan 13: Gate G1, the simulator against the real engine Summary

Exploration, fuzzing, lint, mutation gate and the gate record are in place and the engine is much better for them, but **G1 did not pass**: the clean worlds still show a low rate of violations in eleven invariants, which are left out and listed, and the gate was run at a bounded budget, not the plan's.

## What was built

- **Seeded exploration** (`SimulationTests`, `SimExploration`, `SimGateSupport`): worlds of one to four Macs drawn from the seed (redesigned of both generations, a skewed build, a beta1, a beta2), seven provider presets, 60 steps in CI and 400 at the gate, a drain with one answer at a time, the oracles of plans 28-07 to 28-09 at every step, the liveness checks after the drain, and a shrinker (`SimShrinker`, ddmin) that prints the A1-style scenario and the test to paste. Two families of worlds (see the decisions). One seed gives one trace hash, which a second process reproduces.
- **Bounded exhaustive families** (`SimExhaustiveTests`) with visited-state hashing, depth 6 in CI and `SYNC_SIM_DEPTH` at the gate.
- **Codec fuzzing** (`CodecFuzzTests`, `CanonicalPlist`): arbitrary bytes, truncations, type swaps and oversize collections against the device file, the state and the legacy reader, `SYNC_FUZZ_INPUTS` inputs, deterministic by seed.
- **Determinism lint** (`.github/scripts/sync-lint.py`, markers `// sync-lint: ordered <reason>`, CI step "Sync code rules" in `build.yml`) with a self-test.
- **Mutation gate** (`Scripts/sync-mutation-gate.py`): 26 guard mutations at exact unique anchors, applied to a copy of the sources.
- **`Scripts/sync-gate.sh`** (`--quick`, `--full`, `--record`; `SYNC_GATE_SEEDS`, `_STEPS`, `_DEPTH`, `_FUZZ` lower the budgets) and the record `28-G1-GATE.md`, which says `G1: PASSED` only when every part passed, no open exclusion stands and the budgets are the plan's.

## Engine faults found by the exploration and fixed

Each has a test at the level of the fault (`G1FixTests`, `Layout27Tests`) and was found by a minimized seed.

1. A conflict whose own entry the settings no longer hold (preferences that went back) was a row that could not be answered; it is now a choice among the values (`SyncAnswer.conflictRow`).
2. An answer did not drop the queued change of the unit it wrote, so the change came after the answer and undid it (`writeAnswers`).
3. A join that asks stayed open when the user's own change left nothing to ask (`resolveAskingJoin`, also at a timer, a defaults change and an import).
4. A join that waits did not remember what the settings held when it started, so a deletion made while it waited was not captured after the commit (`localAtDecision`, `settleDotless`).
5. A launch that finds the preferences rolled back under a join that asks rebuilt nothing; it now reads the folder again (`SyncLaunch`).
6. A running Mac whose applied entry was replaced by another's of the same value was not a party of the conflict that value is in (`SyncCapture.settle`).
7. The arrangement changes made while sync is off lived in the session and were lost with it; they are in the state (`queuedIntents`), one change per unit, and all waiting changes of a unit merge into one (a stale one used to be minted later).
8. The own entries of an earlier identity and the counter ceilings of the earlier identities (`previousCeilings`).
9. A mark that a value is the user's (`preexisting`) outlived the change that made it, so a value that holzBar placed later was published as the user's arrangement (A3); the mark goes with a deletion or a no-change (`SyncLayout27.onIntent`).
10. A Mac that holds nothing for an application (the visible section) and matches another Mac's entry of that value was made a party of a conflict it took no part in, and was asked (`SyncPlan.plan`).

## Model gaps fixed in the simulator (not engine faults)

The ground truth, the adapter and the pair comparisons were wrong in about forty places that the exploration showed; the main ones: a user move to the visible section is an entry removal; an answer that restates a deletion is concurrent with a later edit; a row that the engine left out of an answer informs nobody and an answer that decided nothing is no answer; a Mac that is updated to a redesigned build keeps what the harness knew of its join and the values of the old build are `pre`; the build of a writer is the build at the time of the write; the own file is written in the background, not at launch (INV-R2); the metamorphic pairs run on an ideal provider with automatic stores the app really makes and compare what each file finally says; INV-Z4 has a measured bound (2048 + 384 per device + 256 per unit + 64 per entry + values).

## Gate result

See `28-G1-GATE.md` (the record is written by the script and is the authority): G1: FAILED. Bounded run (100 seeds per preset at 400 steps, depth 6, 20,000 fuzz inputs): the 700 clean worlds passed outside the open exclusions, all six control engines were caught at seed 1, the exhaustive families and the fuzzing passed, 70 trace hashes were reproduced by a second process. Failed: the disturbed worlds of five presets (INV-C4, F7, A6, J1, ID1, S6, one seed each, listed in the record) and two metamorphic pairs (INV-A1 seed 17, INV-F2 seed 7), which pass at the CI budget. The mutation gate (26 mutations, four shards) had not ended when the plan was closed, so **no kill count is claimed**; the record says so.

## Open exclusions (clean worlds, 400 steps)

Each is a class that the exploration still finds and that was not explained within the time of the gate; none is a verdict that the engine is right. The rates are per world of 400 steps over 7,000 worlds. **Possible real engine faults among them** are INV-C6 and INV-C1 (a fresh Mac or another Mac differs from the agreed state after the drain), INV-S5 (a deletion made while sync is off or a join waits, followed by a join into a deleted folder, is not in the published file) and INV-B4 (a second question about the same content of the older peer's file). The others (INV-P1, F5, S3, L6, P3, F1, Z4) are probably gaps of the model, but the same is not proven. The minimized traces are in the working notes of this plan and are reproduced by seed: `SimExploration.run(seed:preset:steps: 400, evidenceLoss: false)`.

- INV-S5: seeds hostile 173, 334, 392, 413, 431, 569, 570, 704, 709, 861, 894, 937; iCloud 230, 814; nextcloud 201.
- INV-C6: iCloud 252; nextcloud 419, 689, 912; dropbox 439, 628; oneDrive 700; hostile 731.
- INV-C1: dropbox 689, 945; hostile 731.
- INV-P1: nextcloud 278, 747, 889; dropbox 300, 423; syncthing 583; smb 624; iCloud 684.
- INV-B4: dropbox 157; nextcloud 410, 920; smb 856.
- INV-F5: iCloud 276; dropbox 505. INV-S3: nextcloud 256; iCloud 684. INV-L6: dropbox 157. INV-P3: iCloud 737. INV-F1: iCloud 160. INV-Z4: smb 157; dropbox 845.

## Deviations from the plan

- **G1 not passed; budgets bounded.** The plan's 10,000 seeds per preset at 400 steps, depth 8 and 1,000,000 fuzz inputs was not run: the open exclusions would keep it from passing, and the time was boxed. The record says what ran.
- **The traces that found the faults are not in a `G1FoundTests` file.** The faults are pinned in `G1FixTests` and `Layout27Tests` at the level of the fault; the generator of the found traces (a script outside the repository) was not run for lack of time.
- **Disturbed worlds leave out invariants** (`evidenceLossExclusions`, each with its reason): identity-loss events destroy the evidence the invariants compare with, and the catalogue asserts those cases one by one.
- **Timing tests** (`BlockingWork`, `Task timeout`, `SpacingRelaunch`) fail under load and pass alone; they are not part of this plan.

## Self-Check

The four task commits exist (the history after f9f2e6fc), the files named above exist, and the simulator and engine suites pass at the CI budget except the timing tests that fail under load. The gate record and this summary agree on every number, and the mutation count is the one thing neither claims.
