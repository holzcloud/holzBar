---
phase: 28-settings-sync-redesign
plan: 01
subsystem: sync
tags: [swift, crdt, lattice-join, property-list, swift-testing]

requires:
  - phase: 28-settings-sync-redesign
    provides: CONTEXT.md decisions D-01 (one file per Mac) and D-02 (legacy file read-only)
provides:
  - SyncValue, SyncDigest: closed property-list value type with canonical SHA-256 digest
  - SyncMacID, SyncDot, SyncContext, SyncPayload, SyncEntry
  - SyncReplica with the lattice join, collisions reported, capped sets
  - SyncDeviceFile codec (whole-file refusal, limits, pass-through), name filter, conflict-copy owner
  - SyncState and SyncStateCodec (Sigma)
  - SyncLegacyInput, a read-only reader of the 0.0.6/0.0.7-beta1 Settings.plist
  - SYNC-R01 to SYNC-R10 in REQUIREMENTS.md
affects: [28-04 unit table, 28-05 engine, simulator plans, app glue]

actuals:
  tokens: 26550
  tasks: 3
  commits: 3
plan_head_before: 7547ca4dedc2d326485e1264a6d430c877dcf0b2
plan_head_after: e611d3bc775c3ceaefe6722030aa74665322c124

tech-stack:
  added: []
  patterns:
    - "Foundation + CryptoKit only, every type `nonisolated` and `Sendable` (Core defaults to the main actor)"
    - "Typed throws (`throws(SyncRefusal)`) for all decoders; any defect refuses the whole file"
    - "Dictionaries and sets are always iterated sorted (UTF-8 byte order), so output is deterministic"

key-files:
  created:
    - holzBar/Core/Sync/SyncValue.swift
    - holzBar/Core/Sync/SyncDot.swift
    - holzBar/Core/Sync/SyncReplica.swift
    - holzBar/Core/Sync/SyncDeviceFile.swift
    - holzBar/Core/Sync/SyncState.swift
    - holzBar/Core/Sync/SyncLegacyInput.swift
    - Tests/HolzBarCoreTests/Sync/SyncTracerTests.swift
    - Tests/HolzBarCoreTests/Sync/SyncValueTests.swift
    - Tests/HolzBarCoreTests/Sync/JoinLawsTests.swift
    - Tests/HolzBarCoreTests/Sync/DeviceFileCodecTests.swift
    - Tests/HolzBarCoreTests/Sync/StateCodecTests.swift
    - Tests/HolzBarCoreTests/Sync/LegacyInputTests.swift
  modified:
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Join keeps an entry when the other replica holds the same dot (any payload) or has not seen it, so a same-dot/different-payload pair keeps both entries and is reported in `collisions`; this stays commutative, associative and idempotent"
  - "Two entries with the same identity (dot, payload digest) but different display fields resolve to the later `at`, then the larger digest of `extra`, so the join stays commutative"
  - "`SyncReplica.live(key)` returns every current entry of the unit, deletions included; `distinctValues` dedupes by payload digest"
  - "Sets are normalised (sorted, unique, capped at 2,000 by smallest SHA-256) in the replica initializer, so the cap is a lattice operation"
  - "`SyncValue` refuses non-finite numbers, integers above Int64.max and nesting deeper than 32; a device file with such a value is refused whole"
  - "Conflict-copy detection requires a name that begins with a known MacID and ends in `.plist` but is not exactly `<MacID>.plist`"

patterns-established:
  - "Device file and Sigma share `SyncDeviceFile.replicaFields` and `decodeReplica` for the replica encoding"
  - "Refusal records are keyed by MacID, never by raw file names (OneDrive conflict names contain the computer name)"

requirements-completed: [SYNC-R01, SYNC-R09]

duration: 60min
completed: 2026-10-07
status: complete
---

# Phase 28 Plan 01: Sync core data model Summary

**Pure Foundation-only data model of the redesigned settings sync: causal dots and contexts, multi-value registers with a lattice join (2,000-seed property tests per law), a hardened per-Mac device file codec with pass-through, the Sigma codec and a read-only legacy file reader.**

## Performance

- **Duration:** about 60 min
- **Completed:** 2026-10-07
- **Tasks:** 3 (1 tracer, 2 TDD-style)
- **Files:** 12 created, 1 modified

## Accomplishments

- Tracer: one entry travels from two replicas through the join and a device-file round trip with the single expected live value; REQUIREMENTS.md carries a "Settings sync redesign (Phase 28)" section with SYNC-R01 to SYNC-R10, ten traceability rows and a Coverage line.
- Join laws hold over 2,000 seeded random replica triples each: commutative, associative, idempotent, `join(x, older(x)) == x` (both orders), contexts only grow, and coalescing over all permutations of a real history. Mutation checks (dropping the same-dot clause, an off-by-one in `covers`) make the suite fail.
- Device files are refused whole on: more than 1 MiB (exactly 1 MiB parses), not a property list, a non-dictionary root, a newer major format (even when the rest is garbage), a name that differs from the `mac` field, counters outside 1...2^34 (context 0...2^34), a family with more than 1,024 items, a set with more than 2,000 elements, an entry the file's own context has not seen, an entry with both or neither of `value` and `deleted`. Encoding above 1 MiB throws `tooLarge` before any byte is returned.
- Unknown top-level fields, units, families, entry fields and a newer minor round-trip unchanged.
- Sigma (`SyncState`, `SyncStateCodec`) round-trips every field; damaged bytes, wrong types and an empty plist decode as `unreadable`, a newer format as `newerFormat(n)`.
- `SyncLegacyInput.read` returns `modified`, `deviceID`, the convertible settings and an `identityDigest` over `(modified, deviceID)` only; it has no encoder or write function.

## Task Commits

1. **Task 1: Tracer** - `0285d779` (feat)
2. **Task 2: Device file hardening and Sigma codec** - `79f355a5` (feat)
3. **Task 3: Join law tests and legacy reader** - `e611d3bc` (feat)

(`plan_head_before` is the branch head when this plan started. Plans 28-02 and 28-03 committed to the same branch in parallel, so `git rev-list` over that range also counts their commits; the three above are this plan's commits, found with `--grep '(28-01)'`.)

## Verification

- `swift test` in the repository (all three targets, with the workaround below): 3 + 195 + 512 tests passed, including this plan's 52 sync tests and the 28-02 simulator tests that were in the tree.
- Isolated run of the whole `HolzBarCoreTests` target on HEAD plus this plan's files: 502 tests in 68 suites passed.
- `grep` acceptance checks: `SettingsSyncPause` does not occur in `holzBar/Core/Sync/`; `SyncLegacyInput.swift` has no `func encode` or `func write`; `JoinLawsTests` has 11 `@Test`.
- SwiftLint is not installed on this Mac and was not run. Files were checked by hand against `.swiftlint.yml` (file header, trailing commas, no force unwrap, multiline arguments).
- The app's `swiftc -emit-sil` type check was not run separately: the files are Foundation/CryptoKit only and compile in the package target with the app's flags (Swift 6 mode, main-actor default isolation, the same upcoming features).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `swift test` could not build the tests with the Command Line Tools alone**
- **Found during:** Task 1 and Task 3
- **Issue:** `swift test` intermittently fails with "plugin for module 'TestingMacros' not found" (the testing macro plugin directory is not passed to the compiler), and a parallel plan's unfinished simulator files in the shared working tree broke the test target for a while.
- **Fix:** Run with `-Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing`, and for isolated runs build a private copy of the package (HEAD plus only this plan's files) in the scratchpad. No repository file was changed.
- **Files modified:** none

**2. [Process] No separate RED commit for Task 2 and Task 3**
- **Issue:** The plan marks Tasks 2 and 3 `tdd="true"`. Tests were written first, but a failing (non-compiling) test commit in the shared working tree would have broken the parallel plans' builds, so tests and implementation were committed together. For Task 3 the join-law tests passed at once because the join already existed from Task 1; mutation checks confirm the tests can fail.
- **Files modified:** none

**3. [Rule 1 - Design] The join keeps same-dot entries with different payloads by dot, not by identity**
- **Issue:** The pseudocode keeps an entry only if the other replica holds the same (dot, payload) or has not seen the dot. Applied literally, two entries with the same dot and different payloads would both be dropped (each replica has seen the dot and lacks the other's entry), contradicting the plan's truth "keeps both entries and reports a collision".
- **Fix:** An entry is kept when the other replica holds the same dot with any payload, or has not seen the dot. Verified commutative, associative and idempotent by the property tests and by the dedicated collision test.
- **Files modified:** holzBar/Core/Sync/SyncReplica.swift
- **Commit:** 0285d779

---

**Total deviations:** 3 (1 blocking tooling workaround, 1 process, 1 design clarification)
**Impact on plan:** None on scope. The device file bytes are not canonical across processes (binary plist key order follows Swift dictionary iteration), so later plans must compare replicas by `SyncReplica.digest` and never by raw file bytes.

## Known Stubs

None.

## Threat Flags

None. The new surface (device file and legacy file decoders, Sigma decoder) is exactly the trust boundaries in the plan's threat model; T-28-01 (size, item and counter limits), T-28-02 (whole-file refusal, name equals `mac`, own-context coverage), T-28-03 (refusals keyed by MacID, comment forbids logging names) and T-28-04 (damaged or newer Sigma never decodes as empty) are mitigated and tested.

## Self-Check: PASSED

- Created files exist (all 12 listed in key-files, verified with `[ -f ]`).
- Commits `0285d779`, `79f355a5`, `e611d3bc` are ancestors of HEAD.
