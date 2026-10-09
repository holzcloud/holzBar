# Phase 28 Plan 13 addendum: closing the open items of gate G1 (2026-10-09, time-boxed to three hours)

G1 is **not passed**. This addendum says what the second pass fixed, what it decided was a gap of the model, and what stands. The gate record `28-G1-GATE.md` has the numbers.

## Engine fault found and fixed (one)

A join into a folder whose files claim this Mac's own entries, though this Mac never read the writer of those files, was taken for a join into another group. Another Mac B had read Mac A's entry and relayed it in its own file; A's own file was gone from the folder. A turned sync off, deleted the setting, turned sync on again in the folder: A joined dot-less, saw its own old entry as a value of the group that A holds none of, and brought it back (`SyncJoin.onJoinRead`, `knowsFolder`). The deletion the user made while sync was off was undone, and nothing was published to say so. The fix: a file whose context covers a dot of this Mac's current or earlier identity is evidence that the folder is this Mac's group (`claimsEntriesOfThisMac`). Regression test `G1FixTests.folderThatHoldsTheMacsOwnEntriesIsItsGroup` (failed before, passes now). Found by INV-S5 (nextcloud seed 201, iCloud seed 814), minimal trace in `SimTriageTests`.

## Model gaps fixed (three), each narrow and with its reason in the code

1. **INV-C1 and INV-C6, a conflict that no running Mac is a party of.** Eight of the eleven recorded entries (six of INV-C6, two of INV-C1) were a conflict between Macs that had turned sync off. The Macs that remain are bystanders (D-09, D-10, INV-P7): no hint and no sheet, only a Settings line with Choose Settings, applying neither value. The drain answers hints and sheets and never presses Choose Settings, so the Macs stay as they were and the oracle saw a disagreement. `SimDrain.isOrphanConflict` now also holds for a conflict none of whose live values was made by a redesigned Mac that still has sync on (`hasNoPartyThatRuns`). **What this does not cover:** the engine side of a bystander answer is not driven by the drain; the unit tests of the answers cover it, but no seeded run proves that a bystander can bring the group back to agreement. That would be a drain extension and was not done.
2. **INV-S5, a deletion of a value that was lost with its folder.** The oracle asked for the deletion whenever the Mac's own earlier file had held the value. It now asks only when that version can still be read: the file the write replaces is that version, or another Mac read it. A file that went with a deleted folder before any Mac read it leaves nothing to delete.
3. **INV-B4, a sheet that the app's restart closed.** The first sheet was open and unanswered when the drain restarted the Mac; the pending question came back at launch and the oracle called it a second question. The oracle now compares with answered sheets only (the unit test of the oracle, which answers Later before the repeat, still fires).

None of the three weakens an oracle for a case where a user or another Mac could be hurt: the first leaves out units that nobody can answer, the second values that nobody can read, the third questions the user never answered.

## What stands

See the gate record. In short: INV-S5 hostile seed 861; INV-C6 nextcloud 912 and hostile 731 with INV-C1 hostile 731 (the last follows a deleted and restored folder; the first two are not read); INV-B4 nextcloud 920; INV-P1, F5, S3, L6, P3, F1, Z4 were not triaged in this pass (several of their seeds no longer show after the fix, which is not an explanation); the six classes of the disturbed worlds and the two pair tests (INV-A1 seed 17, INV-F2 seed 7) were not triaged: the time went to the four exclusions and to the mutation gate.

## Mutation gate

19 of 26 mutations confirmed killed, no confirmed survivor, 7 undecided (shard 1 had not ended; `digest-unsorted` was in the run of all suites). One mutation (`answer-without-fresh-dot`) was stale, its mutated source did not build; the table was repaired and it is killed. `capture-during-join` is killed only by the simulation suites, so a unit test at the level of the engine is missing. Details in `28-G1-GATE.md`.

## Tooling added

`Tests/HolzBarCoreTests/Sync/Simulation/SimTriageTests.swift`: `SYNC_TRIAGE="<invariant> <preset> <seed> [clean|disturbed] [steps]"` reproduces and shrinks a seed and prints the A1-style scenario, the writes with what each file says, the final settings, the prompts and the hooks of the steps that asked; `SYNC_SWEEP="<preset>:<seed>[:disturbed],..."` runs seeds in parallel and says which invariants each trips. Both do nothing unless the variable is set. Hint for the next pass: a minimal trace takes seconds in a release build (`swift test -c release --scratch-path <dir> -Xswiftc -enable-testing`) and minutes in a debug build; shrinking a trace of a hostile preset hits the 600-run limit of the shrinker, which leaves 25 to 30 events.

## Files touched outside holzBar/Core/Sync and Tests/HolzBarCoreTests/Sync

None. The engine change is `holzBar/Core/Sync/SyncJoin.swift`; everything else is under `Tests/HolzBarCoreTests/Sync`.


---

# Third pass (2026-10-09, the "second and final pass" of the gate review)

G1 is **still not passed**. `28-G1-GATE.md` has the exact list of what is open and what a pass would take; this section records what the pass did and the reasoning for every model change.

## Engine faults found and fixed (two), each with a regression test that failed before

1. **A late file brought back an earlier identity's entry beside the Mac's own newer one** (INV-C4 syncthing 88 and oneDrive 83). A copied account carries a state whose first launch re-identifies; the Mac remembers the old identity and the counter it had reached (`previousMacIDs`, `previousCeilings`). When the file of the old identity (still in the folder, written by the Mac it was copied from) arrived after the user's first change, the join put its entry next to the Mac's new one: two entries of one Mac in conflict, a sheet whose answers decided nothing (15 sheets in a row, a hint for ever). An entry of an earlier identity at or below that ceiling was made before the current identity existed, so it is older than any entry the current identity made: `SyncMerge.supersedeEarlierIdentities` drops it when the current identity holds an entry of the unit. The context keeps covering the dot, so the readers of this Mac's file see it superseded. Entries above the ceiling are another installation's and stay. Test: `MergeTests.earlierIdentityEntryDoesNotCompeteWithTheCurrentOne`.
2. **An untrusted state became trusted by being persisted** (INV-A6 nextcloud 77). Reinstall (the defaults are gone), then Sigma comes back alone: the generation of the defaults is lower, the state is untrusted, and the launch with sync off persists it under the identity and generation it settled on. The next launch finds both equal and trusts the baselines, and turning sync on captures every setting that the reinstall took away as the user's deletion and publishes it. The launch now forgets the baselines of an untrusted state when sync is off, as a join with dot-less values would (`SyncLaunch`); the replica stays, so the join into the group still recognises its own entries and takes the group's value where the settings hold none. Test: `LaunchTests.untrustedStateWithSyncOffDoesNotBecomeTrustedAtTheNextLaunch`.

## Model gaps fixed (three), none relaxes an oracle

1. **INV-F7 smb 79, smb 5, hostile 71.** `SimWorld` copied `folderID` and `enabled` to a clone, a copied account and a duplicated installation, but not `pendingFolderID`, which is the folder of the waiting join and part of the sync state (it is derived from `pendingJoin.folderIdentity` at the end of every hook). The copy then ran its join against an empty, always mounted replica of its own and wrote into a folder that the provider had unmounted. A clone carries every preference, so the model now carries the waiting folder too. The restores of Sigma carry it with the backup.
2. **INV-A1 seed 17 (pair).** The pair inserted automatic events (a new application placed by holzBar, a learned set, a flag) on every Mac, including a beta2 Mac that the trace later updates to the redesigned build. A beta2 Mac has no intent report: what it placed is in its settings like a user's move, and the redesigned build that replaces it takes everything it finds as a value from before sync, which is what the join with dot-less values is for. Decision D-04 (automatic stores create no dots) binds the builds that report intents. The pair now draws automatic events only for Macs on such a build. Justification: D-04 (CONTEXT, "Intent capture on macOS 27 only from user actions ... `placeNewApplications` ... are automatic and never create dots"), S-6 (builds before the redesign are another group). The oracle INV-A1 on redesigned Macs is unchanged and still checks every write.
3. **INV-F2 seed 7 (pair).** An older version that arrived after a newer one replaced it for good in the simulated provider, and nothing delivered the newer one again: one Mac ended without a change that every other Mac got, for no decision of any engine. The provider is eventually consistent (A2, RC1 "an eventually consistent folder"): after a late older delivery the newer version is delivered again. The provider's unit test now expects the convergence.

## Tried and removed

A reset of the join bookkeeping of a replaced state in the simulator (for INV-J1 dropbox 74) did not change the result and was removed; no unexplained model change was kept.

## The mutation gate found a defect of its own

The copy of the sources lacked `.github/sync-synced-keys.txt`, so `UnitTableTests.syncedKeyFileMatchesTable` failed in every copy and every mutation looked killed. See `28-G1-GATE.md`; the script now copies the file and names every failing test of a kill. The unit test of "nothing is minted while a join waits" was added for `capture-during-join`, which only the simulation suites killed. `digest-unsorted` was killed by the unit tests all along (`SyncValueTests` fails under it when run alone): the mutated digest makes other suites livelock, the run never ended, and the earlier pass read that as "passed the unit suites" (the commit message of the iteration-order test repeats that misreading; the test is kept as the sharper one). The script now stops a run that does not end (`SYNC_MUTATION_TIMEOUT`) and names the tests that failed by then. Final count: 26 of 26 killed.

## Tooling added

`SYNC_PAIR="<automatic|delivery> <preset> <seed>"` reproduces and shrinks a metamorphic pair (`SYNC_PAIR_DUMP=1` dumps the baseline and the variants of a delivery pair); `SYNC_TRIAGE_HOOKS="A,B"` adds a trace of every hook of those Macs (reads, ingests, writes) to a triage; `SYNC_TRIAGE_SCENARIOS=a6|s6` runs the hand-kept scenarios of the open seeds. `Scripts/sync-mutation-gate.py --only a,b,c` takes several mutations in one copy.
