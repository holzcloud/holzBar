---
phase: 28-settings-sync-redesign
plan: 09
subsystem: sync
tags: [swift, sync-engine, macos-27, layout, profiles, known-applications, intent-capture, simulator, swift-testing]

requires:
  - phase: 28-settings-sync-redesign
    provides: "28-04 unit table and projection (l27, prof, known27 scoped to macOS 27), 28-07 engine core, 28-08 launch, join and answers, 28-06 simulator oracles"
provides:
  - SyncLayout27 (SyncIntent, SyncUnitIntent, move, layout and profile intents, protectedApplications, upgrade note) and SyncEvent.intent
  - Intent-only capture of l27 and prof (SyncCapture.capture(intents:)), a queue for intents the state cannot mint yet, the relayOnly outcome
  - known27 as a silent union (SyncSnapshot.known27, the learned timer, SyncEffect.applyKnownApplications at launch and Restart only)
  - SyncState.systemGeneration and the upgrade from macOS 26 to 27 (seeded entries are automatic)
  - SimLayout27Oracles (INV-L1 to INV-L4, INV-L6, INV-K1, INV-A3, and INV-L5 as a metamorphic pair) in SimOracleSet.layout27 and the safety set
affects: [28-10 to 28-18, 28-13 mutation gate, 28-14 app adapter, 28-15 app glue, 28-16 layout pane wiring]

actuals:
  tokens: 36900
  tasks: 3
  commits: 3
plan_head_before: 1e1e9f42092f16711e4e0a8a123ede42bf9872b8
plan_head_after: 5dcaa972d1c8fc0b6bbe0bb04cba5a5e5bc31a25

tech-stack:
  added: []
  patterns:
    - "A change of l27 or prof is never found by diffing the defaults: the app reports one SyncIntent per user action (a move, the entries a user-applied profile changes, an import, a profile saved, renamed or deleted), and the engine mints from it"
    - "An intent that cannot be minted yet (a join waits, the state is not trusted, capture is deferred) waits in the session and is minted by the next capture"
    - "A value of l27 or prof that this Mac applied is the user's intent: a local value that differs (a Space-bound profile, a displacement) neither mints nor waits as a Restart"
    - "known27 is a set in the replica: the engine adds what this Mac knows, the host adds what the group knows at launch and Restart, nothing is ever removed"

key-files:
  created:
    - holzBar/Core/Sync/SyncLayout27.swift
    - Tests/HolzBarCoreTests/Sync/Layout27Tests.swift
    - Tests/HolzBarCoreTests/Sync/ProfileSyncTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimLayout27Oracles.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimLayout27Tests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimLayout27OracleTests.swift
  modified:
    - holzBar/Core/Sync/SyncEngine.swift
    - holzBar/Core/Sync/SyncCapture.swift
    - holzBar/Core/Sync/SyncPlan.swift
    - holzBar/Core/Sync/SyncJoin.swift
    - holzBar/Core/Sync/SyncLaunch.swift
    - holzBar/Core/Sync/SyncPublish.swift
    - holzBar/Core/Sync/SyncState.swift
    - Tests/HolzBarCoreTests/Sync/MergeTests.swift
    - Tests/HolzBarCoreTests/Sync/PlanTests.swift
    - Tests/HolzBarCoreTests/Sync/StateCodecTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMacRedesign.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimOracles.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimSafetyOracles.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimWorld.swift

key-decisions:
  - "An intent mints through the same path as capture (SyncCapture.recordChange): an unusable value stays local, a value the group already holds is adopted, anything else is a new entry that supersedes only the dots this Mac had applied. A move to Visible is the explicit value 0, never a deletion; a deletion of a profile nobody published mints no tombstone"
  - "For l27 and prof a local value that differs from the single live value is no waiting Restart when this Mac applied every live dot (outcome equal): holzBar's own stores never overwrite intent, and a binding that did so is not a change of another Mac"
  - "A deletion this Mac applied no longer makes it a party of a later conflict between others (conflict(mine:) counts applied dots only for values): its user never saw a deletion, so it is a bystander"
  - "A join treats an absent l27 entry as no value to protect (it reads as visible) and an entry holzBar placed after an upgrade as no value either; a present, user-owned entry that differs is a row (D-10). SyncJoin.preview gets hasValue for this"
  - "The upgrade from macOS 26 to 27 is recognised at launch (and at a join) from SyncState.systemGeneration: the entries of the families that came into scope without applied intent are marked automatic, so the group's arrangement arrives silently, and the state is never emptied"
  - "known27 is learned in capture, published at the latest after an hour (a learned-only change schedules no capture) or with the next write, and applied by the host at launch and at Restart only; a macOS 26 Mac never touches it"

patterns-established:
  - "SimLayout27Oracles read the ground truth, the write log and the hooks: tokens name their unit, so a relay, a drop or an automatic placement is judged without the engine's metadata"
  - "A seeded control engine per defect (no generation scope, automatic stores read as intents) is caught within 60 seeds"

requirements-completed: [SYNC-R03, SYNC-R06, SYNC-R07]

duration: not measured (one run, several hours)
completed: 2026-10-08
status: complete
---

# Phase 28 Plan 09: macOS 27 families Summary

**The engine now carries the macOS 27 arrangement, the layout profiles and the known applications between macOS 27 Macs from user intents only, a macOS 26 Mac relays all of it byte for byte, and the three-Mac simulation (seeds 1 to 100 of the iCloud and hostile presets) ends with no layout-oracle violation and with the arrangement agreed.**

## Accomplishments

- **Tracer (Task 1).** A move on macOS 27 becomes one explicit `l27/<bundleID>` entry: Mac B shows Restart and holds the token after its restart, Mac C (macOS 26) shows no hint and no sheet, keeps its defaults and writes the entry back to its own file with A's dot unchanged (12 seeds of the iCloud preset). `SyncLayout27` holds the intents, `SyncEvent.intent` the engine entry, `SyncCapture.capture(intents:)` the minting, `relayOnly` the plan outcome of a family this Mac neither authors nor applies.
- **Rules (Task 2).** Explicit visible, intent-only capture (an entry that disappears from the defaults mints nothing), automatic stores that never mint and never win (`protectedApplications`, the `equal` outcome over an applied entry), joins (present differing entry is a row, absent entry takes the group's value, group lacks it: published), the OS upgrade through `systemGeneration`, `known27` as a silent union (learned timer, `applyKnownApplications` at launch and Restart), and a queue for intents that cannot be minted yet.
- **Profiles and oracles (Task 3).** `prof/<profileID>` intents (save, rename as one change of one ID, delete), a conflict row labeled by name, and an apply that keeps itemSections, bindings and unknown fields end to end through the engine. The layout oracles INV-L1, INV-L2, INV-L3, INV-L4, INV-L6, INV-K1 and INV-A3 are registered in `SimOracleSet.layout27` (and `SimOracleSet.safety`); INV-L5 is the clock-offset metamorphic pair `SimLayout27Oracles.relayIndependence`.

## Test results

- `Layout27Tests` 32, `ProfileSyncTests` 10, `SimLayout27Oracles` 16 (hand-built positive and negative worlds, INV-L5 caught on a clock-driven engine), `SimLayout27` (the tracer on 12 seeds, the two control engines, the random worlds).
- Three Macs (A and B on macOS 27, C on macOS 26; C upgrades in some traces) with user moves, profile saves, renames, deletes and applications (by user and by binding), seeding, placement, restarts, answers and time, plus a drain of relaunches and Use answers: `SYNC_L27_SEEDS=100` runs seeds 1 to 100 on the iCloud and hostile presets, 200 worlds, no oracle violation, the generation-27 Macs agree on every unit the user made, the macOS 26 Mac holds none of the families unless it upgraded (870 s on 10 cores). A plain run uses seeds 1 to 10 per preset.
- Control engines: an engine whose families have no generation scope is caught (INV-L1, INV-N1, INV-L2 or INV-L3), an engine that reads automatic stores as intents is caught (INV-A3, INV-S1 or INV-S2), both within 60 seeds.
- Mutation spot check: removing the intent-capture skip in `SyncCapture.capture` fails 8 tests of `Layout27Tests` and `ProfileSyncTests` (then reverted).
- Full `swift test` (SDK 26.5, testing plugin path flag): 885 tests; the only failures are the timing tests of `BlockingWork`, `SpacingRelaunch` and `Task timeout` while the machine is loaded; the same 31 tests pass alone.
- SwiftLint `--strict`: no violation. `Scripts/typecheck-app.sh`: passes.
- Acceptance greps: `enum SyncIntent` once; `isIntentCaptured` in `SyncCapture.swift`; `relayOnly` in `SyncPlan.swift`; `systemGeneration` in `SyncState.swift` and `SyncJoin.swift`; `applyKnownApplications` in `SyncEngine.swift`; 7 distinct quoted `INV-[LK]` IDs in `SimLayout27Oracles.swift`; `layout27` in `SimOracles.swift`; `SettingsSyncPause` does not occur in `holzBar/Core/Sync/`.

## Task Commits

1. **Task 1: Tracer** - `f713e329` (feat)
2. **Task 2: Rules of the 27 families** - `2c70ee2c` (test)
3. **Task 3: Profiles, layout oracles, three-Mac simulation** - `5dcaa972` (test)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The worktree started on `main`** - fast-forwarded to `planning/sync-redesign` (1e1e9f42).

**2. [Process] RED commits.** Tasks 2 and 3 are `tdd="true"`, but the engine was written whole in the tracer pass (as in 28-07 and 28-08), so their tests were written against existing code. The mutation spot check shows they can fail. No separate RED commits.

**3. [Rule 1 - Bug] An automatic store looked like a change of another Mac.** A profile bound to a Space replaces the user's entry locally; the plan then planned a Restart for the entry the Mac had applied itself. Fix: for `l27` and `prof` a unit whose live dots are all applied is `equal` (`SyncPlan`).

**4. [Rule 1 - Bug] An automatic change counted as a difference at an identity change.** `SyncLaunch.differsFromBaseline` compared the intent-captured units too, so seeding could make a re-identified state untrusted. Fix: it skips them.

**5. [Rule 1 - Bug] A Mac that applied a deletion became a party of a later conflict** (found by seed 17 of the hostile preset: a profile deleted on one Mac and saved on another). Its user never saw the deletion. Fix: `conflict(mine:)` counts applied dots only for values.

**6. [Rule 3 - Blocking] The simulator and its oracles needed four corrections** (`SimWorld.swift`, `SimMacRedesign.swift`, `SimSafetyOracles.swift`):
- `deleteProfile` acted on a Mac of macOS 26 and on a profile that does not exist, which INV-S5 then read as an unpublished deletion; it is now macOS 27 and existing profiles only.
- A profile applied by a Space or display binding overwrote entries the user had made, against D-04; it now leaves them alone, like the other automatic stores.
- A sheet row with three or more values lost the values the engine's answer supersedes in the oracles' model; the adapter now lists each token on the side that loses it, so INV-S1, INV-S3, INV-S7 and INV-S9 judge the engine's answer.
- INV-F5 blamed a dominated version for a hint that a version taken in at the same step caused.

**7. [Rule 3 - Blocking] The random worlds use a layout generator of their own** (`SimLayout27Tests.events`), not `SimGenerator`: the simulator's engine table holds `S1` to `S6` and one hotkey family, so the full generator's other units (and the oversize icon) have no synced unit behind them and trip INV-S5, INV-Z3 and INV-P1 for reasons that have nothing to do with this plan. The plan's event kinds are all there; `Later` answers are left out (see Known issues).

**8. [Rule 3 - Blocking] Files outside `files_modified`:** `SyncJoin.swift` gained `hasValue` in `preview`; `SyncLaunch.swift`, `SyncPublish.swift` (the `learned` trigger), `SimWorld.swift`, `SimSafetyOracles.swift`, `SimOracles.swift`, the test files `MergeTests`, `PlanTests`, `StateCodecTests`, and the new `SimLayout27OracleTests.swift` (the hand-built oracle worlds).

**9. [Scope] INV-L5 is a metamorphic function, not a registered oracle,** like INV-F9; the automatic-store rule is registered as INV-A3. The 100-seed run is behind `SYNC_L27_SEEDS=100` (a plain run does 10 per preset), because one world with its drain takes seconds and the whole run 14 minutes.

## Known issues and notes for the following plans

- **App wiring (28-14 to 28-16).** The host must fill `SyncSnapshot.known27` (the local `KnownApplications27`, sorted, empty before macOS 27), send `SyncEvent.intent(.userSet([...]))` for every user action on the families (`SyncLayout27.moveIntent`, `layoutIntents`, `profileIntents`, `profileValue`; `from` for an application without a stored section is `SyncLayout27.visible`), run `SyncEffect.applyKnownApplications` through `SyncProjection.knownApplicationsUnion`, execute `SyncTimer.learned` (one hour), and let automatic stores skip `SyncLayout27.protectedApplications(in:)`. A profile bound to a Space or display must send no intent.
- **A move while sync is off is not minted.** Nothing is lost: the entry is a present value at the next join and is asked about there (D-10). An intent made while a join waits is queued in the session (not persisted) and minted when the join commits.
- **`Later`, then a move.** A move supersedes only what the Mac applied, so a value the sheet showed and the user then moved past stays a live sibling, and the question returns at the next launch. The simulator's ground truth counts the move as superseding it (INV-P1); this is not specific to the macOS 27 families and the layout generator avoids `Later`. Plan 28-13 should decide which side is right.
- **Performance of the simulator.** A world with 100 events costs 1 to 20 seconds, nearly all of it the plan 28-06 safety oracles (the layout oracles take under a tenth).

## Known Stubs

None.

## Threat Flags

None beyond the plan's register: T-28-24 (the generation scope gates every family: INV-L1 to INV-L4, the macOS 26 Mac of every layout simulation and the control engine without the scope), T-28-25 (intent-only capture, `protectedApplications`, the `equal` outcome and INV-A3 with a control engine), T-28-26 (hostile profile values are refused and stay local: `ProfileSyncTests`).

## Self-Check: PASSED

- All created files exist (`[ -f ]`): SyncLayout27.swift, Layout27Tests.swift, ProfileSyncTests.swift, SimLayout27Oracles.swift, SimLayout27Tests.swift, SimLayout27OracleTests.swift.
- Commits `f713e329`, `2c70ee2c`, `5dcaa972` are ancestors of HEAD.
