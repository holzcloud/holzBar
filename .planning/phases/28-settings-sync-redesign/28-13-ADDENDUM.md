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
