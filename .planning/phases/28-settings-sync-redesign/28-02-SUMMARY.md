---
phase: 28-settings-sync-redesign
plan: 02
subsystem: testing
tags: [swift, swift-testing, simulation, deterministic, xoshiro, vector-clocks, file-provider, settings-sync]

requires:
  - phase: 28-settings-sync-redesign
    provides: "D-04..D-07 and D-11 decisions (CONTEXT.md); analysis section 5 and A2 sections 2, 6 and 8 as the model"
provides:
  - "Deterministic multi-Mac simulation world (seeded xoshiro256**, virtual clock with per-Mac offsets, canonical SHA-256 trace hash)"
  - "Hostile file provider with seven presets and per-Mac folder replicas (delays, offline, reorder, coalesce, duplicates, conflict copies per provider, last-writer-wins, iCloud per-device winners, restore, delete, evict, partial, stall, unmount, foreign bytes)"
  - "Exact 0.0.7-beta1 peer (A2 section 2.6) and 0.0.7-beta2 peer with its load-time writers"
  - "SimSyncBrain protocol and SimMacContext that the real-engine adapter of plan 28-07 plugs into"
  - "SimGroundTruth: Past, justified supersession, liveness, global loss with the INV-S1g exclusion, per-unit conflict, generation scope, origins"
affects: [28-06, 28-07, 28-08, 28-09, 28-10, 28-11, 28-12]

actuals:
  tokens: 48500
  tasks: 3
  commits: 3
plan_head_before: 79f355a5537edd665a7de7b66d551c3f87e26615
plan_head_after: 42a714653fd358c3cbaaff6cf59f630538aa76f2

tech-stack:
  added: []
  patterns:
    - "One seeded generator per concern, derived by fork(label) from the seed with an FNV-1a hash (never hashValue); all iteration over sorted keys"
    - "Brains act only through an inout SimMacContext that records ordered actions; the world carries them out and feeds the ground truth"
    - "Ground truth is a class with a holderSource closure, so hand-built traces and the world use the same queries"

key-files:
  created:
    - Tests/HolzBarCoreTests/Sync/Simulation/SimRandom.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimClock.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimValue.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimWorld.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimFolder.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimProvider.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimProviderPresets.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimEvents.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMac.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMacBeta1.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimMacBeta2.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimGroundTruth.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimWorldTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimProviderTests.swift
    - Tests/HolzBarCoreTests/Sync/Simulation/SimGroundTruthTests.swift
  modified: []

key-decisions:
  - "Every hook gets an inout SimMacContext that records ordered actions (write, ingest, prompt, timer, download, automatic write, relaunch); the world executes them after the hook, so ground-truth clocks see ingests before the writes that follow them"
  - "A read returns .data(bytes, version:) so a brain can report the provider version it ingested; foreign bytes and unknown content carry version 0 and have an empty past"
  - "The provider keeps one cloud-current version per path; catch-up on join and on mount delivers it, stale deliveries are dropped with the coalesce probability, duplicates never change a replica"
  - "Non-sync causes (provider faults, user and automatic events, identity events, beta2 launches) are what INV-S1g excludes; hooks of beta1 and redesigned Macs are sync causes"
  - "Version IDs are unique across folders (a range of one million per folder) so the ground truth can key versions globally"

patterns-established:
  - "Scenario tests build a SimWorld from SimMacSpec values, run SimEvent lists and assert on defaults, replicas, trace and ground truth"
  - "A policy argument (or a preset) selects the provider; without one the provider is ideal (zero delay, no faults), which keeps simple scenarios exact"

requirements-completed: [SYNC-R03]

duration: 35min
completed: 2026-10-07
status: complete
---

# Phase 28 Plan 02: Simulation world Summary

**A seeded, trace-hashed multi-Mac world with a seven-preset hostile file provider, literal beta1 and beta2 peers, and a vector-clock ground truth that answers Past, liveness, global loss and per-unit conflict from the event trace alone.**

## Performance

- **Duration:** about 35 min
- **Tasks:** 3 of 3
- **Files:** 15 created (about 4,300 lines, test target only)

## Accomplishments

- **Determinism (T-28-05).** `SimRandom` is xoshiro256** seeded through SplitMix64; `fork(label)` uses an FNV-1a hash of the label and the seed, never the running state. `SimClock` keeps global virtual milliseconds and per-Mac offsets of at most 7 days. The trace hash is SHA-256 over canonical text (sorted keys, plists decoded to a canonical form). The same seed gives the same hash over 200 random events, another seed another hash. A self-test greps the simulation sources for real time, system randomness and real concurrency.
- **Exact beta1 peer.** `SimMacBeta1` follows A2 section 2.6: at launch with sync on it applies an acceptable file silently with remove-missing (`removesMissing`), sets `HasImportedIceSettings`, records `SettingsSyncLastSynced`, then pushes; it pushes 5 s after any defaults change without reading; Turn On and Change push without reading; it ignores files over 1 MiB, from its own device, not newer than its last sync, or more than 1 h ahead; a folder signal with an acceptable file opens an alert where Restart applies and relaunches and Later records nothing. The XML plist date resolution (whole seconds) is kept, so equal-second pushes behave as they would for real.
- **Beta2 peer.** Inert towards the folder; at every launch it drops duplicate hotkey combinations and writes the dictionary back, clamps `ItemSpacingOffset` and `RehideInterval`, and re-encodes the appearance, groups and icon values (fills missing fields, drops unknown ones, sorts keys). Each write is an automatic write in the trace, with `changed=true|false`.
- **Provider.** Heavy-tailed delivery, offline windows for sender and receiver, reordering across paths (`retime`), coalescing, duplicates, concurrent-write resolution per preset (Dropbox, OneDrive with the `MARKER-NAME-<mac>` computer name, Nextcloud copy only on the losing Mac, Syncthing `sync-conflict` copy, iCloud per-device winners with unresolved versions readable through the context, SMB last writer wins), restore, delete, delete folder, evict to dataless with requested download, partial exposure, stalls (short ones delay and are accounted, long or endless ones time out), unmount (a write attempt is a violation candidate) and mount (catch-up), and five kinds of foreign bytes. Presets: iCloud, Dropbox, OneDrive, Nextcloud, Syncthing, SMB (no folder signals), hostile.
- **Ground truth.** Vector clock per Mac over program order and ingest edges; `past(ofVersion:)`, `past(ofMac:)`, `isLive(token:unit:)`, `globallyLost(at:)`, `conflict(mac:unit:)` and `conflictingVersions`, `origin(of:)`, and generation scope (`l27/*`, `prof/*`, `known27` only on generation-27 Macs). Global loss scans defaults, every readable file (brains decode them through `heldTokens(inFile:data:)`, unresolved iCloud versions included) and pending holdings, and excludes a loss only when every holder that ever held the token was destroyed by non-sync events. The world reproduces the classic beta1 loss: A edits, B pushes a second later without reading, A restarts into B's file and its change is globally lost.

## Test results

- `swift test --filter "SimGroundTruthTests|SimProviderTests|SimWorldTests"`: 46 tests in 3 suites, all passed.
- Full Core suite (`swift test`, SDK 26.5): all three test targets pass, including 548 tests in `HolzBarCoreTests` (that count includes tests plan 28-01 added in parallel).
- Mutation spot checks: removing the clock check from supersession, or making every destruction count as non-sync, fails several tests; making an equal-version duplicate delivery re-apply survives, which is correct because a duplicate changes nothing visible.

## Task Commits

1. **Task 1: tracer, seeded two-Mac world with the beta1 peer** - `6f7baf60` (test)
2. **Task 2: provider fault model, presets, beta2 peer** - `8a9df29b` (test)
3. **Task 3: ground truth** - `42a71465` (test)

The ledger range `plan_head_before..plan_head_after` holds 5 commits because plan 28-01 committed two (`e611d3bc`, `9e535ab3`) in the same working tree between mine; `commits: 3` counts this plan's commits (`git log --grep "(28-02)"`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Task 1 also commits SimEvents.swift, SimFolder.swift and a minimal SimProvider.swift**
- **Found during:** Task 1
- **Issue:** The task text asks for the full `SimEvent` enum and an immediate-delivery provider in Task 1, but the plan lists SimEvents, SimFolder and SimProvider only under Task 2. The world cannot compile without them.
- **Fix:** Task 1 carries the full enum, the folder types and a minimal provider; Task 2 replaces the provider behind the same surface.
- **Commit:** `6f7baf60`

**2. [Rule 3 - Blocking] Verification through a scratch package while plan 28-01 left HolzBarCore uncompilable**
- **Found during:** Task 1
- **Issue:** Parallel plan 28-01 was writing Core files, so `swift build` of `HolzBarCore` failed for a while. The simulation does not use any HolzBarCore type.
- **Fix:** Iterated in a scratch SwiftPM package with the same Swift settings that symlinks the Simulation folder; every task was then verified with the plan's own command in the real package.

**3. [Rule 1 - Bug] Test infrastructure flake**
- **Issue:** After a file changes, the first `swift test` sometimes fails with "plugin for module 'TestingMacros' not found" (also for unrelated test targets); a retry succeeds. Not caused by this plan.

### Interface refinements (the interfaces block named the contracts, not exact signatures)

- `defaultsChanged(origin:units:_:)` also receives the changed units, `timerFired(tag:_:)` the timer tag, and `SimUserCommand` has `importFile(set:removed:)` (the world applies the import with remove-missing first).
- A read returns `SimReadResult.data(Data, version:)`; `SimMacAction` is the ordered action log of a context.
- `heldTokens` has two forms: the property (pending holdings) and `heldTokens(inFile:data:)` (the file decoder); `claimedPast(ofFile:data:)` returns the claimed user tokens.
- `globallyLost(at:)` reads holders through a `holderSource` closure that returns a `SimHolderSnapshot`; the world sets it, hand-built traces set it directly.
- Provider events carry a `folder` (default `F1`) and relative durations.

### Not modelled

- Syncthing's temporary `.syncthing.*.tmp` files and Google Drive's `Settings (1).plist` name (A2 section 6.2 calls the names illustrative and the plan's behaviour list does not include them).
- A stall shorter than the I/O bound only adds to the context's accounted blocked time; no virtual time passes inside a hook.

## Known Stubs

None. `SimInertBrain` is the deliberate stand-in for the redesigned engine until plan 28-07 plugs in the adapter.

## Threat Flags

None (test code only, no network, no new trust boundary). T-28-05 (determinism) and T-28-06 (planted identity markers: hardware ID, computer name, user name, home path and salt per Mac, with the OneDrive and Dropbox copy names carrying the computer name) are covered.

## Self-Check: PASSED

- All 15 files exist under `Tests/HolzBarCoreTests/Sync/Simulation/`.
- Commits `6f7baf60`, `8a9df29b` and `42a71465` are ancestors of HEAD.
- Acceptance greps: `protocol SimSyncBrain` (1), `removesMissing` (present), no `Date()`, `.random(`, `DispatchQueue` or `Task {` in the folder, `MARKER-NAME` in the provider, 21 provider-operation lines, 12 `@Test` in the ground-truth suite, 15 `groundTruth.` uses in the world.
