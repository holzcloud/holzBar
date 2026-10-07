---
phase: 28-settings-sync-redesign
plan: 06
subsystem: testing
tags: [swift, swift-testing, simulation, oracles, metamorphic, delta-debugging, control-engines, settings-sync]

requires:
  - phase: 28-settings-sync-redesign
    provides: "SimWorld, SimGroundTruth, SimMac brains and the hostile provider (plan 28-02)"
provides:
  - "48 safety oracles by invariant ID (S1 to S9, PR2, N1, A6, P1 to P7, ID1 to ID6, J1, F1, F4 to F7, R2, R3, Z1 to Z6, B1 to B9), each run at its moment and charged to redesigned Macs only"
  - "Liveness drain (quiescence rounds, adversarial answers, fresh Mac) with INV-C1 to C6 and INV-P6 as oracles over the drain facts"
  - "Metamorphic pairs: INV-A1, INV-F9, INV-F2, INV-F3, INV-A5"
  - "SimGenerator per preset, SimBudget (SYNC_SIM_SEEDS, SYNC_SIM_STEPS, SYNC_SIM_DEPTH, SYNC_FUZZ_INPUTS), SimRunner with random and exhaustive modes"
  - "SimShrinker (ddmin), SimScenarioPrinter (A1 style and a ready-to-paste Swift test), SimScenario DSL"
  - "Control engines LastWriterWinsByClock and SharedFileBeta1StyleEngine, both caught"
affects: [28-07, 28-08, 28-09, 28-10, 28-11, 28-12, 28-13]

actuals:
  tokens: 57300
  tasks: 3
  commits: 3
plan_head_before: c4104e29525ee428403244584d48de4f8f9c6684
plan_head_after: 2146f7e1faecf68a60ada95332351ab66bc964c2

tech-stack:
  added: []
  patterns:
    - "Oracles are closures over a focus (the step, write, read, prompt or answer just observed) and the ground truth; none reads engine metadata except through the optional SimBrainIntrospection hooks"
    - "A SimScriptedBrain test double misbehaves on command, so every oracle has one test that makes it fire and one that keeps it quiet"
    - "Metamorphic comparisons use tokens, never counters or bytes, which is the comparison modulo counter renaming"

key-files:
  created:
    - Tests/HolzBarCoreTests/Sync/Simulation/SimOracles.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimSafetyOracles.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimLiveness.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMetamorphic.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimGenerator.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimShrinker.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimScenarioPrinter.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimScenario.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimControlEngines.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimOracleTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimControlEngineTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimHarnessTests.swift
  modified:
    - Tests/HolzBarCoreTests/Sync/Simulation/SimWorld.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMac.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimProvider.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimWorldTests.swift

key-decisions:
  - "Oracles read observation records the world keeps per step (hooks, transitions, writes, reads, prompts, answers, before and after snapshots), not engine state; the engine is asked only through optional SimBrainIntrospection hooks, and a brain that cannot answer is simply not checked by that oracle"
  - "A change is charged to a redesigned engine when the Mac runs one or when it applied a version a redesigned Mac wrote (INV-B1); beta1 and beta2 peers run through every oracle quietly"
  - "Control engines sit in the redesigned slot (kind .redesign), so their violations are charged"
  - "The liveness oracles read facts the drain collects (SimDrainFacts), so a later plan can register more oracles over the same drain"
  - "Visited-state hashing in the exhaustive mode covers settings, replicas, queue, timers, pending tokens and the open sheet, not a brain's private fields"

patterns-established:
  - "SimOracleSet.safety.adding([...]) is how a later family (macOS 27, profiles in plan 28-09) registers; .only and .without select by ID"
  - "Printed failures use the SimScenario builder names, so a shrunk trace pastes into a test and runs"

requirements-completed: [SYNC-R03]

duration: 3h
completed: 2026-10-07
status: complete
---

# Phase 28 Plan 06: Oracles, drain, metamorphic pairs and control engines Summary

**The simulation world now judges: 48 safety oracles and the C1 to C6 drain run against the ground truth, five metamorphic pairs and a ddmin shrinker with an A1-style printer sit on top, and both control engines are caught within the plan's seed bounds (usually in the first seeds).**

## Accomplishments

- **Oracle framework (Task 1, tracer).** `SimOracle`, `SimInvariantID`, `SimCheckMoment`, `SimViolation`, `SimOracleSet`. `SimWorld` records every hook with its transitions, key changes, reads, writes (with what the writer's replica held before and whether it read it this session), prompts, answers and before and after snapshots of each Mac, and runs the oracles at the step, write, read, prompt and answer moments. INV-S1 is judged by ground-truth liveness over the changes that existed when the hook began plus the justification (an answer that showed the value as losing, or an ingested version whose past holds a later user change); INV-S1g reuses the ground truth's global loss. The tracer: `LastWriterWinsByClock` is caught by INV-S1 at seed 1, shrunk by ddmin to 8 events and printed as Setup, Steps, Wrong, Must plus a Swift test.
- **The remaining safety oracles (Task 2).** 48 IDs in `SimSafetyOracles` (the acceptance grep counts 48). Each has a positive and a negative test in `SimOracleTests` (50 tests), built with the `SimScriptedBrain` test double. The privacy scan renders each written file once and searches it raw and decoded for every planted marker and for the SHA-256 (lower hex, upper hex, base64, raw) of each marker alone, salted both ways, and of the salt. Two mutation spot checks (dropping the S6 read-in-session condition, dropping the F5 dominated condition) were each killed; the F5 one exposed a missing negative case, which was then added.
- **Drain, metamorphic pairs, generator, DSL (Task 3).** `SimDrain` runs rounds of relaunch, settle, answer until two quiet rounds, then checks agreement (C1), writes and hints from relaunches alone (C2, C4), the question bound (C3), progress (C5), a fresh Mac joining (C6) and unanswered conflicts (P6). `SimMetamorphic` has A1, F9, F2 and F3, A5. `SimGenerator` draws per preset with fault rates from the preset and a quiescent mode; `SimRunner` runs a seed randomly or exhaustively with visited-state hashing; `SimBudget` reads the four environment variables with CI defaults. `SimScenario` is the builder DSL with the seven expectations; printed failures use the same builder names (a printed test was pasted into a scratch file and ran).
- **Control engines.** `LastWriterWinsByClock` is caught by INV-S1 (seed 1) and by INV-F9 (within the first seeds of the clock pair); `SharedFileBeta1StyleEngine` by INV-S1 and INV-S6 within seeds 1 through 200 (found in the first handful). A converging test engine is not caught by the same oracles on 30 seeds.

## Test results

- `swift test --filter "SimControlEngineTests|SimHarnessTests|SimOracleTests|SimWorldTests|SimProviderTests|SimGroundTruthTests"`: 117 tests in 6 suites, all passed, about 1.2 s.
- Full `swift test` (SDK 26.5, testing plugin path flag): 685 tests in `HolzBarCoreTests`, 195 in the macOS 27 core target, 3 in code signing. The last of three runs passed completely. The first two runs each failed one or two pre-existing timing tests (`BlockingWorkTests` "returns the fallback on time", `TaskTimeoutTests` "ends the wait at once") while other plans were building on the same machine; they are unrelated to this plan.
- Acceptance greps: 48 distinct `"INV-..."` IDs in `SimSafetyOracles.swift` (at least 30), 50 `@Test` in `SimOracleTests.swift` (at least 30), the four budget variable names appear 6 times, the three invariant IDs 14 times, `protocol SimOracle`, `struct LastWriterWinsByClock`, `struct SharedFileBeta1StyleEngine` and `struct SimScenario` once each.

## Task Commits

1. **Task 1: tracer, oracle framework, INV-S1/S1g, shrinker, printer, last-writer-wins control engine** - `fb3e678a` (test)
2. **Task 2: remaining safety oracles, privacy marker scan, per-oracle tests** - `84bcb73c` (test)
3. **Task 3: drain, metamorphic pairs, generator, runner, DSL, shared-file control engine** - `2146f7e1` (test)

The ledger range `plan_head_before..plan_head_after` holds 5 commits because plan 28-04 committed two (`70cf2798`, `e3c9c1dd`) in the same working tree between mine; `commits: 3` counts this plan's commits (`git log --grep "(28-06)"`), as in the plan 28-02 summary.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `SimViolation` already existed in `SimProvider.swift`**
- **Found during:** Task 1
- **Issue:** Plan 28-02 named the provider's write-on-unmounted-folder record `SimViolation`; this plan's interface block needs `SimViolation { id, seed, stepIndex, description, trace }`.
- **Fix:** Renamed the provider one to `SimWriteViolation` (`SimProvider.swift`, `SimWorld.violations`); nothing else used the name.
- **Commit:** `fb3e678a`

**2. [Rule 3 - Blocking] The context had no record of reads**
- **Found during:** Task 1
- **Issue:** INV-F1, INV-Z2 and INV-S6 need to know which reads a hook made and whether the content was partial.
- **Fix:** `SimMacContext.read` appends to a `readLog` (`SimMac.swift`, one new struct and a private helper); behavior unchanged.
- **Commit:** `fb3e678a`

**3. [Rule 3 - Blocking] The real-time lint in `SimWorldTests` forbids the plan's `SimRunMode.random(steps:)`**
- **Found during:** Task 3
- **Issue:** The lint rejected every file containing `.random(`, which the plan-mandated run mode case name contains.
- **Fix:** The lint now flags a call of `random` on a type (`Int.random(in:)` and the like) and still forbids the real clock, dispatch queues, tasks and threads; the run mode is the one allowed owner.
- **Commit:** `2146f7e1`

**4. [Rule 2 - Missing critical functionality] Introspection hooks beyond plan 28-02's**
- **Found during:** Task 2
- **Issue:** The plan says the oracles get engine knowledge "only through the SimSyncBrain query hooks of plan 28-02", which offer `claimedPast`, `heldTokens`, `hint` and `openPrompt`. INV-S5, ID1 to ID6, J1, Z3, Z4, A6, P7 and B6 need the device ID, join state, re-identification reason, deletions in a file and similar.
- **Fix:** A separate optional protocol `SimBrainIntrospection` (one `report()` plus four file decoders, all defaulting to nil). The plan 28-07 adapter implements it; a brain that does not conform is not checked by those oracles.
- **Commit:** `fb3e678a`, `84bcb73c`

### Other differences from the plan

- **An extra test file.** `SimHarnessTests.swift` (budget, generator, runner, drain, metamorphic pairs, DSL) was added next to the two test files the plan lists, together with the `SimConvergentTestBrain` test double the drain and metamorphic tests need. The shared-file and last-writer-wins checks the plan names live in `SimControlEngineTests` as asked.
- **File placement.** `SimBudget`, `SimRunner` and `SimRunMode` are in `SimGenerator.swift` (the plan names `SimGenerator.swift` as one of the three files that read the budget variables). The minimal event helper of Task 1 stayed in the test file; the generator arrived in Task 3.
- **`SimLiveness.swift` exists from Task 1** as an empty stub so that `SimOracleSet.liveness` compiles; Task 3 filled it.

### Approximations and limits (read before relying on a green run)

- INV-P1 accepts a unit as witnessed by a ground-truth conflict, a join difference, a `pre` value or any shown hotkey row; it does not recompute hotkey clashes.
- INV-B4 recognises a question as caused by an older peer's file when every shown folder token is held by `holzBar/Settings.plist` in the Mac's replica.
- INV-B5 and INV-B3 overlap INV-S1 on purpose (different IDs for different release criteria). INV-B7 checks the join after redesign, older build, redesign and that the older build never writes `holzBar/Macs/`.
- INV-Z5 uses the bound 16 + 4 files per redesigned Mac; INV-Z4 uses 4096 + 512 bytes per device seen. Plans 28-07 and 28-08 should tighten both to the real engine.
- The simulator's key model has no device tuning key, so `SimLocalKeys.tuning` is empty and INV-N1 checks the keys of D-05 and D-06 only.
- INV-A4 (provenance labels), INV-R1 and INV-SEC1 are not oracles here (A4 needs the engine's labels, R1 is a source lint, SEC1 belongs to the fuzz plan).
- Visited-state hashing in the exhaustive mode ignores a brain's private fields, so it can prune two states that differ only there.

## Known Stubs

None. `SimLivenessOracles` and the drain are complete; the only placeholder-like value is the empty `SimLocalKeys.tuning`, recorded above.

## Threat Flags

None (test code only, no network, no new trust boundary). T-28-15 (oracle strength) is mitigated by the positive and negative test per oracle, the two control engines and the mutation spot checks; T-28-16 (marker scan) by INV-S8, INV-PR2 and INV-ID5 over every written byte.

## Self-Check: PASSED

- All twelve created files exist under `Tests/HolzBarCoreTests/Sync/Simulation/`.
- Commits `fb3e678a`, `84bcb73c` and `2146f7e1` are ancestors of HEAD.
- Only files under `Tests/HolzBarCoreTests/Sync/Simulation/` changed.
