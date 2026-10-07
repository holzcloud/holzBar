# A3: Proven designs for serverless, folder-based settings sync

Research input for the holzBar settings-sync redesign (after the 0.0.7-beta2 pause). Written 2026-10-07. Read-only: nothing in the repository or its git state was changed.

**Inputs read:** the paused code on `audit/remediation-2026-10-05`, which includes `holzBar/Utilities/SettingsSync.swift` (1909 lines), `holzBar/Core/SettingsSyncPolicy.swift` (717 lines), `SettingsSyncFile/Device/Location/Pause.swift` and `SettingsBackup.swift`. Also: the six fix-and-review rounds on `audit-manual/sync-fix` (the `sync-fix-SUMMARY.md` and 60 commits), the three review JSONs, audit findings F-02, F-15, F-38, F-59, F-60 and F-61, the decisions `sync-1.md` and `modal-alerts-1.md` together with the rejected options in `manual-questions.json`, the sync section of `docs/features.md`, the pause requirement in commit `77ab5629`, and the `v0.0.7-beta1` sync code. Web lookups are listed in §11.

**About the scenario classes:** §3 defines classes C1–C16, drawn from the audit and the review rounds. A1's taxonomy (`A1-failure-taxonomy.md`) appeared while this document was being written. §7.1 maps the recommended design to its root causes RC-1 to RC-11, its invariants INV-1 to INV-16, its scenario groups G1 to G10, and its pairs of histories that look the same.

---

## 1. Summary

1. **The six rounds rebuilt textbook mechanisms one patch at a time.** Each one maps to an existing technique:
   - the `base` digest is a three-way-merge base;
   - "pending" plus "Later" is an unresolved multi-value register;
   - the sync-fix `seen` record (each Mac's newest write, dated by its own clock) is a version vector;
   - `writeStamp` reproduces Syncthing's `counter = max(old+1, now)`;
   - `currentLayouts`, `copiedLayouts`, the kept-layout record and the 64 "recent layouts" rebuild per-key provenance by heuristics;
   - the union/OR merge of learned keys is a grow-only-set or flag CRDT.

   The pieces are sound. What they sit on is not.
2. **The root cause is structural: one shared, mutable file that every Mac overwrites,** carried by sync apps that offer no compare-and-swap. The design then has to infer causality from contents and wall-clock dates, and every inference rule had a counterexample in the next round. Each provider also loses a concurrent write differently:
   - Dropbox moves the *later* save into a "conflicted copy";
   - Nextcloud keeps the local conflict copy off the server by default;
   - Syncthing renames the version with the older modification time;
   - iCloud hides the losers as `NSFileVersion` conflict versions;
   - SMB keeps whichever rename came last.

   holzBar reads only `Settings.plist`, so in every case it sees one write and silently misses the other.
3. **The proven alternative has three parts:**
   - **(a) Single-writer files.** One file per Mac: each Mac writes only its own and reads all the others.
   - **(b) Causal metadata per conflict unit.** Each value carries a *dot* (Mac ID and counter), and each file carries a version vector.
   - **(c) A merge that is a lattice join**, meaning it is commutative, associative and idempotent.

   With all three:
   - a stale, restored, duplicated or late file can never move state backwards, because joining an older state changes nothing;
   - deleting a file loses nothing that the other Macs have already merged;
   - arrival order does not matter;
   - providers create no conflict copies in normal operation. A conflict copy of a Mac's own file means two Macs share an ID, which is a signal for F-38.
4. **"Ask on real conflicts" requires multi-value registers.** Examples are the Dynamo/Riak siblings, Shapiro's MV-register and Automerge's `getConflicts`.
   - Concurrent values are all kept and shown.
   - The user's answer is written with a causal context that covers exactly the values that were shown. A value that arrives while the question is open is therefore asked about again, never overwritten.
   - The answer reaches every Mac, and the question disappears everywhere.

   Last-writer-wins registers converge but silently drop one of two concurrent writes, which conflicts with the maintainer's policy. That holds whether they order by wall clock, Lamport clock or hybrid logical clock (HLC). With wall clocks they can even drop the causally *later* write.
5. **"holzBar's own placements are not user changes" is about capturing intent, not about merging.** Only user operations create dots. Automatic or derived state (seeding, placing new items, learned lists) stays in a local layer underneath the synced intent layer, so it can never cause a conflict or a remote change. VS Code Settings Sync is precedent: it never syncs machine-scoped settings, and it syncs keybindings per platform by default.
6. **The macOS 26 and macOS 27 layouts become two key namespaces** (`ItemSections/…` and `MacOS27Layout/…`). Each Mac writes only its own, and the other travels along as ordinary state. There are no "copies", no "current" lists and no stale-copy recognition.
7. **Joining and resuming compare per key.** This covers turning sync on, changing the folder, a re-identified Mac, and resuming after the beta2 pause.
   - Local values that have no dots are compared with the folder state key by key.
   - Differences are asked about *before anything is published*.
   - **Keep This Mac's** writes the local values with a context that covers the folder's values. **Use Folder** adopts the folder's values. In neither case is anything left half-written on other Macs.
8. **A local write takes the *applied* context, not the received one.** The applied context is what `UserDefaults` reflects. With this rule, "the user changed X while another Mac's change to X waits" is detected as a conflict on X, while waiting changes to other keys stay mergeable.
9. **Legacy files and mixed fleets:**
   - Never write `holzBar/Settings.plist`: 0.0.7-beta1 applies it silently at launch and removes every key it lacks.
   - Read it only as input when joining.
   - A fleet that mixes beta1 and new builds forms two separate sync groups until every Mac is updated. That is safe, it just does not sync across the two.
10. **No wall clock in any decision.** Counters are `max(last+1, unix seconds, own file's counter)`, which also covers preferences restored from a backup. Wall-clock time is kept for display only.
11. **The Apple APIs do not provide correctness across Macs:**
   - `NSFileCoordinator` and `NSFilePresenter` coordinate only processes on one Mac, plus the iCloud and File Provider daemons on that Mac.
   - FSEvents does not report another computer's writes to an SMB share.
   - `NSFileVersion` conflict information is inconsistent across devices (confirmed by Apple DTS in 2025).

   Use these APIs for safe local I/O and for change notifications only.
12. **Cost is small:**
   - The state is about 70 keys plus one layout entry per item per macOS version.
   - Each Mac's file is about 10–40 KB, as a binary plist or JSON, once custom icons are capped or stored outside it.
   - The Core logic is roughly 400–700 lines of Swift plus property-based tests. It replaces most of `SettingsSyncPolicy.swift` and much of `SettingsSync.swift`.
13. **Testing gets easier.** Because the merge is a join, correctness can be checked with randomized and model-based tests over generated histories (stale restores, deletions, duplicates, clones, mixed macOS versions, N Macs) against a handful of invariants. Scenarios no longer have to be enumerated one review round at a time.
14. **The research raises policy questions that need the maintainer** (§10):
   - Should changes to *different* settings merge silently? The rejected "Pro Einstellung zusammenführen" option merged per setting *and never asked*.
   - Should non-conflicting keys apply while others wait for an answer?
   - How fine-grained should the questions be?
   - At join, does a value equal to its default count as "no user value"?

---

## 2. Diagnosis: what the paused design rebuilt, and what is missing

| Mechanism in the paused code / sync-fix branch | Textbook concept | Gap that produced review findings |
|---|---|---|
| `base`: SHA-256 of the user settings, plus a layout digest for this macOS version | Three-way-merge base (Unison archive, VS Code "last synced" copy) | It is a digest per *document*, so it shows *that* something changed but not *which key*. Any concurrent change, even to unrelated keys, becomes a whole-document question, and either answer discards the other side's unrelated changes. |
| `pending` version, "Later", paused pushes | Unresolved siblings of a multi-value register | It blocks *all* pushes. It was lost when the file went away (round 3, issue 2) or on relaunch (round 5 known issue), and needed a guard while the alert was open (decision `modal-alerts-1`, point 4). |
| `seen`: per Mac, the date of its newest write that a version holds, capped at 64; `missesLastWrite` | Version vector (Parker et al. 1983) with counters from each Mac's clock, as in Syncthing | It lives inside a file that any Mac overwrites, so a provider conflict can still drop a write. It is per document, and the 64-entry cap can hide a missing write (round 6 known risk). |
| `writeStamp`: each write at least 1 s after the previous one | Syncthing `Vector.Update`: `max(old+1, unix now)` | The idea is right. It was needed only because the version's identity was a wall-clock date in whole seconds (XML plist dates have one-second precision). |
| `isNewer` = `modified > lastSynced`; `allowedClockSkew` = 1 h | Last-writer-wins by wall clock | Clock skew, backward steps and two writes in the same second. A file dated in the future is ignored. |
| `currentLayouts`, `copiedLayouts`, kept-layout record, `recentLayouts` (8, then 64 digests), `isOldOwnLayout` | Per-key provenance: which write produced this key's value | Reconstructed by heuristics, and each heuristic had a counterexample in the next round: negative evidence (round 3, issue 4), the 64-entry limit and a beta1 user's return to an earlier arrangement (round 3, issue 7), copies promoted to current (round 5). |
| Union and OR merge of learned keys | G-Set and enable-wins flag, both join-semilattices | Correct. Keep it. |
| `SettingsSyncLayoutEdits` count versus the synced count | Capturing intent as operations | Coarse: one count per Mac, not per item. On macOS 26 the attribution errors (round 3/4, issue 3) are input problems that no merge rule can fix. |
| beta1 `apply` removes missing keys (F-60); the redesign passes `removesMissingKeys: false` | Absence is not deletion; a deletion is an explicit write or a tombstone | `false` is right. In a CRDT, absence carries no meaning by construction. |

**Why the patches kept coming.** A single shared file is one register that every replica overwrites. The transports here are iCloud Drive, Dropbox, OneDrive, Nextcloud, Syncthing and SMB, and none of them offers an atomic compare-and-swap that would reject a write based on a stale read. That is the classic *lost update*. On top of it the design has to guess causality from contents and dates, and under stale delivery or missing files every guess can be wrong. The literature has three proven remedies, and they work together:

- **single-writer data**, so no overwrite is possible;
- **causal metadata per conflict unit**, so "newer", "older" and "concurrent" are facts rather than guesses;
- **merges that are joins**, so the order of delivery, duplicates and stale inputs cannot matter.

---

## 3. Scenario classes (C1–C16)

| ID | Class | Examples from the audit and the reviews |
|---|---|---|
| C1 | **Join, re-join and resume.** Covers Turn On…, Change…, a re-identified Mac, sync turned off and on, and the first launch after the beta2 pause; the folder may be empty or hold this Mac's own, an equal, or a different file. | F-02 (a); round 1, issue 1 (re-join before restart); round 2, re-join after a drag; round 3, issue 5 (joining adopts a version that is not newer); the pause requirement (`77ab5629`): a layout edited during the pause must count as edited. |
| C2 | **A change on one side, propagated**: at launch, while running (restart hint), and relayed through a third Mac. | F-02 (b): a push at every launch causing ping-pong; round 6, a third Mac (`dadb3801`). |
| C3 | **Concurrent changes to *different* settings.** | Today this is a whole-document question; whichever button is chosen loses one side's changes. |
| C4 | **Concurrent changes to the *same* setting** (a real conflict), including races while answering: a version arriving while the sheet is open, or answers given on two Macs. | F-02 (c), after "Later"; round 1, issues 3 and 8 ("Keep" over an unasked version); round 2, a third Mac's version dated at or before the answered one. |
| C5 | **Automatic versus user changes**: learned keys, automatic placement of new items, macOS 27 seeding, migrations, items macOS displaces. | SA-05; round 1, issues 4/9/5 (a Command-click without a move, a profile that changes nothing); round 3/4, issue 3 (the first move of an unsaved item on macOS 26, displacement saved). |
| C6 | **Layouts for macOS 26 and 27** (`ItemSections` and `MacOS27Layout`). | F-60; rounds 3–6: a stale copy of the other macOS version's layout taken in, promoted to current, or replaced. |
| C7 | **Stale inputs**: an old version brought back by the provider (version history, Recently Deleted, Rewind, Time Machine), a Mac returning after weeks offline, delayed delivery, this Mac's own old file. | Round 2: an older own version taken in at launch; round 4, issue 1: a stale other-OS layout written back as current. |
| C8 | **Missing, damaged or unusable file**: deleted, truncated, not a plist, over 1 MB, malformed values, a symlink. | Round 3, issue 2: a write over a missing file silently reverts another Mac's change; F-61; F-59. |
| C9 | **Conflict artefacts made by the provider**: Dropbox "conflicted copy", OneDrive "-ComputerName", Nextcloud "(conflicted copy …)" kept local, Syncthing `.sync-conflict-…`, iCloud conflict versions or "Name 2". | Not handled today: every such file is ignored, so the write moved aside is lost silently. |
| C10 | **Identity**: Migration Assistant, restore or clone copying the ID; preferences reset or restored from a backup (counter going back); retired Macs. | F-38; round 6, `writeStamp`. |
| C11 | **Clocks**: skew, backward steps, two writes in the same second, files dated in the future. | Round 6, issue 6 (`47c4f09e`); the `allowedClockSkew` rule. |
| C12 | **Mixed builds**: beta1 (silent apply with key removal at launch, push at every launch), beta2 (paused), future file formats, unknown keys. | Round 1, issues 6/11/7/12 and blocker #1 of the SA-05 review (beta1 writes over a same-OS drag). |
| C13 | **Availability and latency**: online-only (dataless) files, a stalled provider, an unmounted share, the launch time bound, missing change notifications. | F-15, F-18. |
| C14 | **Deletion semantics**: a key missing versus reset to its default, removing a profile, forgetting an item. | F-60; a cleared `CurrentLayoutProfile` (from the rejected option's note). |
| C15 | **Size and growth**: the custom icon, metadata growth, number of Macs, files of retired Macs. | F-61; round 6, the 64-entry limit. |
| C16 | **Untrusted folder writers and privacy**: shared folders, crafted files, identifying metadata. | The threat model in the `SettingsSyncFile` doc comment; the computer name dropped in beta1; the F-38 hash that never leaves the Mac. |

---

## 4. Techniques

Each technique below is described under the same headings: how it works, guarantees, what it cannot do, cost, and which scenario classes it handles. §7 then compares complete candidate designs across all classes.

### 4.1 Single-writer files: one file per Mac, every Mac reads all

**How it works.**
- Each Mac writes only `holzBar/<dir>/<deviceID>.<ext>`, replacing it atomically. It lists the folder and reads every other Mac's file.
- Every Mac derives the synced state from the set of files with the same deterministic function.
- There are two variants:
  - **(a) Own-values files.** Each file holds only the values that Mac wrote, each with its causal context.
  - **(b) Replica files.** Each file holds the Mac's *whole merged state*: all keys with their metadata, including values other Macs wrote.

**Prior art.**
- **Ensembles** (Core Data and SwiftData sync): each device exports change events as files to "storage your users already have": iCloud, Dropbox, WebDAV, a local folder and more. In its own words it "requires no custom server".
- **Core Data + iCloud (2011–2016):** a transaction log per peer in the ubiquity container, periodically "baselined". It was deprecated in iOS 10 and macOS 10.12. The lesson: the hard part was compacting logs across devices, not the layout of one directory per device.
- **automerge-repo storage:** incremental chunks and snapshots stored under content-hash keys. It is "safe for multiple processes to use the same data directory" because a process only ever deletes keys it has loaded itself.
- **Per-device records in Firefox Sync** (the `clients` and `tabs` collections, server-based), and **per-writer append-only logs** in Hypercore/Autobase and Secure Scuttlebutt.

**Guarantees.**
- No write–write conflict on any file, so providers create no conflict copies unless two Macs share an ID. A conflict copy of a device file is therefore exactly the F-38 signal.
- No Mac's latest output is ever overwritten by another Mac.
- Combined with a join (§4.5), arrival order and duplicate delivery do not matter.
- With variant (b):
  - losing a file loses only that Mac's writes that no other Mac has merged yet;
  - a Mac can always rewrite its own file from its local state, so the file heals itself;
  - a retired Mac's file can be deleted once every live file's version vector covers it.

**What it cannot do.**
- Say which value is newer. That needs §4.2–§4.3.
- Give an atomic snapshot across files, so each file must be self-contained.
- Avoid stale reads; delivery stays eventual.
- Tell user changes from automatic ones.
- Stop someone who can write the folder from forging a file.
- Variant (a) has one more weakness: if a Mac's file is lost and no other Mac's file relays its values, a Mac that joins later never learns them. This is why (b) is preferred.

**Cost.**
- N files, where N is every Mac that ever joined, typically 2–4.
- With (b) each file is the full state: a few to a few tens of kilobytes for holzBar (§8.11).
- A directory listing on each check.
- Optional clean-up of retired Macs' files.

**Fit with the providers.** Every provider in scope handles single-writer files cleanly. Each file uploads and downloads on its own, and nothing depends on the order in which they arrive.

**Scenario classes.**
- Removes C9 and the "write over a missing file reverts another Mac" part of C8 *structurally*.
- With a join, makes C7 harmless.
- C10 needs unique IDs (F-38).
- C5, C6 and C14 depend on the state model (§4.5).

### 4.2 Version vectors (VV)

**How it works.**
- A map from Mac ID to counter. A Mac increments its own entry when it writes.
- Merging two vectors takes the maximum of each entry.
- Comparing two versions gives one of four results: equal, older, newer, or *concurrent* (neither covers the other).
- References: Parker et al. 1983; Syncthing's BEP protocol keeps one per file, with counters keyed by the first 64 bits of the device ID.

**Guarantees.**
- Exact detection of "happened before" versus "concurrent", independent of wall clocks.
- Size grows with the number of Macs, not the number of writes.

**What it cannot do.**
- Resolve anything. It only classifies.
- Work below the object it is attached to. One vector per file makes *every* concurrent edit a conflict, which is today's whole-document problem.
- Survive duplicate writer IDs or reused counters:
  - preferences restored from a backup reset a counter, so two different versions carry the same `(id, n)`;
  - Syncthing guards against this with `Value = max(Value+1, unix now)` (`lib/protocol/vector.go`), and holzBar can additionally take the maximum with its own file's counter (§8.9).
- Tolerate pruning: removing entries, such as a 64-entry cap, can invent concurrency or hide a missing write.

**Cost.** About 44 bytes per Mac (UUID plus a 64-bit counter). Comparing and merging take a few lines of code.

**Scenario classes.**
- Detection for C2, C3, C4, C7, C10 and C11, and relaying through a third Mac in C2.
- Nothing for C5 or C6 by itself.

### 4.3 Dotted version vectors (DVV, DVVSet)

**How it works.**
- Each value carries a *dot*: the single event `(Mac, counter)` that created it.
- A write also carries the *context*, a version vector of what the writer had seen.
- The receiver drops exactly the stored values whose dots the context covers, and keeps every concurrent value as a sibling.
- References: Preguiça, Baquero, Almeida, Fonte, Gonçalves 2010; Almeida et al. 2014 (DVVSet). Riak 2.0 uses it (`dvv_enabled`) to stop "sibling explosion".

**Why it exists.** In client–server stores, clients do not own counters. Plain vectors on the servers then either over-report concurrency or lose updates.

**What matters for holzBar.** Each Mac is both writer and replica, so plain vectors with *one dot per value* are enough. The key ideas are "every value carries its dot" and "every write carries the context it saw". They make two of the hardest round findings exact instead of heuristic:
- "Keep This Mac's Settings" covers only the version that was shown (round 1, issues 3 and 8; round 2);
- the parent-version record (rounds 4 and 5, date only, then per Mac).

**Guarantees.** No false conflicts and no lost concurrent updates, with a compact context.

**What it cannot do.** Decide anything. It also needs dots *per key* (or per entry) to give per-key conflicts.

**Cost.** One dot per stored value, about 44 bytes, or a small index into a Mac table.

**Scenario classes.** C4 including the races while answering, C7, and relaying through a third Mac in C2.

### 4.4 Clocks for last-writer-wins: wall clock, Lamport, hybrid logical clock (HLC)

| Clock | Guarantee | Failure that matters here |
|---|---|---|
| **Wall clock** (Thomas write rule, RFC 677, 1975; Akka `LWWRegister` by default; Syncthing's choice of which copy to rename; "last save" in iCloud and Dropbox) | Converges. Easy to show "changed at 14:03". | A Mac whose clock is behind loses its *later* edit silently. Backward clock steps, two writes in the same second (XML plist dates have one-second precision), and files dated in the future (hence holzBar's 1 h skew cap). This violates "never revert silently". |
| **Lamport timestamp** (Lamport 1978), ties broken by Mac ID | If a happened before b, then L(a) < L(b), so a causally later write always wins. | Of two concurrent writes, an *arbitrary* one wins and the other is dropped *silently*. It also cannot *detect* concurrency, because L(a) < L(b) does not imply that a happened before b. |
| **HLC** (Kulkarni, Demirbas et al. 2014; CockroachDB; per-field last-writer-wins in local-first apps such as Actual Budget, from the talk "CRDTs for Mortals") | Lamport's guarantees, while staying within the clock-synchronisation error of physical time. Good for display and for a rough order. | Same as Lamport for concurrent writes: silent loss. |

**Conclusion for holzBar.** Clocks exist to *order* last-writer-wins registers. The maintainer's policy allows no silent loss on any user-facing key, so no clock should ever decide which value is applied.
- Keep wall-clock time *only for display*.
- Generate counters with Syncthing's time floor. That is safe because a counter is only ever compared with counters of the same Mac.
- XML-plist precision and clock skew then stop mattering, which fixes C11 by construction.

### 4.5 State-based CRDT maps

**General idea.** In a state-based CRDT (CvRDT; Shapiro, Preguiça, Baquero, Zawirski 2011), the states form a join-semilattice and the merge is the join.
- Any delivery order, duplicates, stale states or lost intermediate states converge.
- Joining a state with an older one changes nothing.
- Delta-state CRDTs (Almeida, Shoker, Baquero 2018) only cut down what is sent. At holzBar's sizes they are unnecessary.

| Type | Semantics | Guarantees | Cannot | Fit in holzBar |
|---|---|---|---|---|
| **Last-writer-wins register map** | Each key holds (timestamp, value); merge keeps the larger timestamp. A delete is a tombstone with a timestamp. | Convergent and tiny. With Lamport or HLC timestamps it respects causality. | Keep concurrent values; it always drops one silently. | Only for keys where silent loss is acceptable. Under the policy, that is none of the user keys. |
| **OR-Set and OR-Map** (observed-remove, add-wins; the optimised OR-Set without tombstones by Bieniusa et al. 2012; Riak DT map; Akka `ORMap`) | Elements are tagged with dots. A remove deletes only the dots it has observed. Of a concurrent add and remove, the add wins. Values can be nested CRDTs. | Clean semantics for removals and nesting. | Express "remove wins"; it also needs causal contexts. | Layout entries per item and profiles by ID, if removal is ever needed. holzBar rarely deletes. |
| **Multi-value (MV) register** (Shapiro's MV-Register; Dynamo's shopping cart, where reads return every version with its context; Riak siblings; Automerge `getConflicts`) | Keeps every concurrent value. A write made with the observed context replaces exactly the values that context covers. | Convergent, *no silent loss of concurrent writes*, and conflicts become data that can be shown on every Mac and resolved on any of them. | Choose a value: someone has to answer. Unanswered siblings persist (at most one per Mac). | **Every user-facing key or group.** Siblings with equal values are not a conflict and collapse. |
| **G-Set and enable-wins flag** | Union and OR. | Trivially convergent; never conflicts. | Remove anything. | The learned keys (`KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners`, `hasMigrated*`, …), as the paused design already does. |

**Recommended shape:** a map of MV-registers that shares one causal context per file. This is the "DotMap" or causal-context formalism of Almeida et al. 2018 (dot stores: DotSet, DotFun, DotMap).

**A critical pitfall** follows from the shared context. A Mac must never drop an entry it cannot interpret while still advancing its context. Examples of such entries are an unknown key from a newer build, a value that fails validation, or anything over a size limit. If that happens, the other Macs read "seen and superseded" and delete the entry. That is F-59 and F-60 in CRDT form. The rule:
- the replicated state passes such entries through *opaquely, byte for byte*;
- validation happens only when values are applied to `UserDefaults`, and only locally.

**Cost.**
- Per entry: the value plus a dot. Per file: one version vector.
- For about 70 keys plus about 2 × N_items layout entries: roughly 5–40 KB per file before icons (§8.11).
- Join, write and resolve together are roughly 200–400 lines of Swift.

**Scenario classes.**
- MV-registers give C3 and C4 exactly.
- The join gives C7 and the "missing file" part of C8.
- Separate keys per macOS version give C6.
- G-Sets give the learned part of C5.
- Explicit writes give C14.

### 4.6 Three-way merge against a stored base (Unison, VS Code Settings Sync, git)

**How it works.** Keep the state from the last sync, called the archive or base. For each key:
- changed only remotely: take the remote value;
- changed only locally: keep the local value;
- changed on both sides to different values: a conflict, so ask.

Unison has a formal specification of exactly this: Balasubramaniam & Pierce 1998, Pierce & Vouillon 2004. VS Code Settings Sync merges settings against the last synced copy, offers *Accept Local*, *Accept Remote* or *Show Conflicts* with a merge editor, and on the first sync of a new machine "automatically merges your local and cloud data".

**Guarantees.** It is predictable and easy to explain ("both Macs changed X"). It is exactly "ask on real conflicts" *for two replicas*, or for a hub that offers compare-and-swap. The VS Code service rejects a write whose ref is stale.

**What it cannot do.**
- It is not safe with N Macs sharing one file without compare-and-swap. That is the lost update of §2.
- With per-Mac files it needs one base per peer, plus causal information to know which peer's value is newest, which brings it back to §4.2 + §4.5.
- A base kept only as digests cannot merge per key.
- The rejected option "Pro Einstellung zusammenführen" was this technique with "the folder wins" instead of asking. Its description called it "deutlich mehr Logik und schwerer vorhersehbar" ("much more logic and harder to predict").

**Cost.** One base snapshot of the settings, per peer with per-Mac files. Little logic, but correctness depends on compare-and-swap, which the providers do not offer.

**Scenario classes.** C3 and C4 with two Macs. With N Macs and a shared file, C2, C7 and C8 come back. C6 only per key.

### 4.7 Operation logs: event files per device

**Ensembles.** Every save is recorded as an event, exported as a file and replayed on the other devices.
- Revision numbers per store, plus the revisions of the other stores known at the time (effectively a vector clock).
- In its own words: "a change made with knowledge of another change beats it, and truly concurrent edits to the same attribute fall back to last-writer-wins with a deterministic tiebreaker".
- To-many relationships are add-wins.
- "Old events are automatically compacted into a baseline snapshot", and the files it supersedes are cleaned up.
- A delegate hook lets the app repair merges.

**Core Data + iCloud (deprecated).** Per-peer transaction logs with system "baselining" led to years of reliability problems and its deprecation. The lesson: compacting logs across devices without coordination is the hard part.

**automerge-repo storage.** Chunks and snapshots are stored under content hashes ("two nodes will independently compress the same events and write to the same key, but that's fine as it will contain the same data"). A process deletes only the keys it has loaded itself.

**Guarantees.** History, user intent as operations ("moved item X to Hidden"), and fine-grained merges.

**What it cannot do cheaply.** Bound its growth without compaction, compact safely across devices, and keep replay simple. It is much more code than holzBar's tiny state warrants.

**What to borrow:**
- capture user intent as *operations* at the moment it happens (§8.4);
- store large values as content-addressed, immutable blobs, deleting only blobs that have been loaded (§8.11).

### 4.8 Libraries

**Automerge** (`automerge-swift`, a Swift wrapper over the Rust core):
- JSON-like CRDT documents. Concurrent assignments to the same map key keep a deterministic winner by (counter, actor ID), and `getConflicts` returns both the winner and the losers.
- The next assignment resolves the conflict.
- Whole documents can be saved, loaded and merged, so the per-Mac-file pattern works: each Mac saves its document and merges everyone else's.

*Against it for holzBar:*
- a binary dependency of several MB in an ad hoc signed menu bar app;
- an opaque binary file format;
- mapping the schema to and from `UserDefaults`;
- the winner is applied *by default*, so honouring the policy means checking for conflicts everywhere;
- history grows and needs compaction.

A hand-written DotMap of about 300 lines is easier to audit and to test exhaustively. Other references for semantics, not as dependencies: the Rust `crdts` crate (`MVReg`, `Map`, `Orswot`, `VClock`), Akka Distributed Data (`ORMap`, `LWWMap`) and `riak_dt`. Yjs has no Swift port.

### 4.9 Ruled out, with reasons

- **A lock or lease file in the folder.** Eventually consistent sync has no atomic test-and-set, so two Macs can both "hold" the lock, and a crash leaves a stale lock behind.
- **Read-back checking** ("write, then check the file is still mine"). Providers move a write aside *later*, and may never deliver the conflict copy (Nextcloud's default), so the loss cannot be detected. The sync-fix branch's `missesLastWrite` approximates this, but only on the Mac that wrote.
- **A primary Mac or leader election.** That needs reliable membership, and Macs go offline for weeks.
- **`NSUbiquitousKeyValueStore`, CloudKit, or `NSMetadataQuery` ubiquitous scopes.** All need an iCloud entitlement that an ad hoc signed app cannot have (noted in the beta1 code), and they would work with iCloud only.
- **Relying on `NSFileVersion` conflict versions to find lost writes.** They exist only for iCloud and are inconsistent across devices: in a 2025 Apple Developer Forums thread, one device saw the other's version and the other did not, and Apple DTS called it inconsistent with the documentation. Versions can also disappear (a macOS 14.4 bug deleted versions along with evicted files).
- **Writing `Settings.plist` as well, for beta1 Macs.** beta1 applies that file silently at launch and removes every key it lacks (F-60). It also overwrites a beta1 Mac's own unsynced changes, which beta1 never checks for. Both violate the policy (C12).

---

## 5. How the sync providers behave

| Provider | Integration on macOS | Two Macs write the same file | Deletion and restore | Online-only files | How holzBar hears about changes |
|---|---|---|---|---|---|
| **iCloud Drive** | System daemon, File Provider; coordinated writes | iCloud picks a "conflict winner" that Apple documents as "the same across all devices". The losers stay as `NSFileVersion` *conflict versions* until an app resolves them. Document apps show a dialog, and keeping both gives "Name 2". In practice the winner can differ between devices (Apple Developer Forums 2025, confirmed by DTS). Uncoordinated readers see only the winner. | Recently Deleted keeps files 30 days; restoring brings back the *old* file. | "Optimize Mac Storage" evicts files, leaving them dataless (`SF_DATALESS`). A read triggers a download, which blocks and can time out offline. | `NSFilePresenter` works, because the daemon coordinates. |
| **Dropbox** | File Provider (`~/Library/CloudStorage/Dropbox`) | A conflicted copy named with the editor's name, "conflicted copy" and the date. "The last version saved will always appear as the conflicted copy": the *newest* write is the one moved aside. | Version history and deleted files are restorable for a period that depends on the plan. Restoring makes an old version current again. | Online-only files are dataless and download when opened. | FSEvents or `DispatchSource` on the folder. Presenter notifications are not documented for File Provider domains; test them. |
| **OneDrive** | File Provider (Files On-Demand) | Both are kept; one copy is renamed with the computer name appended ("MyFile-ComputerName.txt"). Office files may be merged instead. | Recycle bin; version history. | Dataless. | FSEvents. |
| **Nextcloud** | Desktop client: a classic sync folder, or virtual files through File Provider | The server version keeps the name, and the local version becomes "name (conflicted copy YYYY-MM-DD HHMMSS).ext". **By default the conflict file is not uploaded**, so it stays only on the Mac that wrote it. | Trash bin and versions on the server. | Only with virtual files. | FSEvents. |
| **Syncthing** | A user-space daemon that writes plain files | Version vector per file. On concurrent changes, "the older file gets renamed" to `<name>.sync-conflict-<date>-<time>-<modifiedBy>.<ext>`; with equal times, the device with the larger ID loses. Conflict copies are synced to every device. Delete against modify: when the delete wins, the modified file is kept as a conflict copy. | Optional local versioning (`.stversions`). Nothing is "restored" across the cluster unless someone copies it back. | None; files are always complete. | FSEvents. Delivery can lag for days while peers are offline. |
| **SMB, AFP or NFS share** | One shared copy, no replication | The last rename wins; no conflict copies. | Only server snapshots, if any. | None, but the volume can be unmounted or stalled (F-15, F-18). | FSEvents does **not** report other computers' changes, and `NSFileCoordinator` does not span machines. Poll. |

**What this means for one shared file (beta1 and the paused design).** In every provider, a concurrent write is moved aside, hidden, or replaced, and holzBar reads only `Settings.plist`. Whether a Mac's write ever reaches the others then depends on the provider and on timing:
- Dropbox and OneDrive keep the moved-aside write in a file holzBar ignores. Dropbox moves the *newest* write aside.
- Nextcloud keeps it on the writing Mac only.
- Syncthing decides by wall-clock modification time.
- iCloud may disagree between devices.
- SMB keeps the last rename.

**What this means for one file per Mac.** Each file has a single writer, so none of these mechanisms is triggered in normal operation. Restores, version history, Rewind and Syncthing's eventual delivery only ever bring back *older replica states*, which a join absorbs without effect (C7). The provider is reduced to a transport, as local-first designs recommend. Kleppmann et al. (2019) point out that conflicted copies from file sync leave merging to the user.

**Practical rules that follow:**
- Accept only files named exactly `<UUID>.<ext>`. Ignore everything else: conflict copies (and log them as a signal for C10), `.sync-conflict-*`, `.syncthing.*.tmp`, `* 2.*`, `.DS_Store`, `Icon\r`, and Nextcloud's or OneDrive's renamed copies.
- Write atomically (a temporary file in the same folder, then rename), with a temporary name that starts with a dot.
- Never follow symlinks, and bound every read. `readContents(atPath:)` and `isUsableFolder(atPath:)` in the paused code already do this.
- Never block launch on a read.
- Treat every file as possibly old.

---

## 6. macOS file APIs: what to use them for

| API | What it does | Where its scope ends | Use in the redesign |
|---|---|---|---|
| `NSFileCoordinator` | Serialises reads and writes among processes on **this** Mac, including the iCloud and File Provider daemons. A coordinated read of a dataless ubiquitous file waits for the download (F-15). Useful options: `.immediatelyAvailableMetadataOnly`, `.withoutChanges`, and `.forReplacing` for writes. Can be cancelled. | It does nothing across Macs. On an SMB share the other Macs do not take part. A coordinated operation on the main thread can block or deadlock. | Coordinated `.forReplacing` writes of this Mac's own file, off the main actor with a time bound (for iCloud, so the daemon never uploads half a file). Coordinated reads only in the background. |
| `NSFilePresenter` | Notifies about coordinated changes by other processes: `presentedSubitemDidChange(at:)` and `presentedSubitemDidAppear(at:)` on the folder, and `presentedItemDidGain`, `presentedItemDidLose` and `presentedItemDidResolveConflict` for versions. | Writers that do not coordinate (Syncthing, classic Dropbox and Nextcloud clients, other Macs on SMB) send no notification. Doing coordinated I/O for the same item inside a presenter callback can deadlock. | Fast change notification for iCloud Drive. Nothing correctness-related. |
| FSEvents / `DispatchSource` on the folder | Reports local changes, including files written by the sync clients on this Mac. | Advisory only, and blind to remote writes on network volumes. | Change notification for every provider except SMB. Also check on wake, on app activation and on a slow timer, and poll more often when the folder is on a network volume. |
| `NSFileVersion` | iCloud conflict versions (`unresolvedConflictVersionsOfItem`, `isResolved`, `removeOtherVersionsOfItem`). | iCloud only; inconsistent across devices; versions can be lost. | A conflict version of a device file means two Macs share an ID, so re-identify (C10). Clean the versions up so they do not accumulate. Never use them as history. |
| Dataless detection: `lstat` `st_flags & SF_DATALESS`; `ubiquitousItemDownloadingStatus` | Tells whether a read would wait for a download. `SettingsSyncFile.isLocal` already does this. | A download needs a user session; otherwise the read eventually fails with "Operation timed out" (Arq's documentation of dataless files). | At launch, read only files that are local. Request downloads of the rest in the background: a coordinated read, or `FileManager.startDownloadingUbiquitousItem(at:)` for iCloud (verify this works without an entitlement). Merge whatever is local now and the rest later; a join makes partial sets safe. |

---

## 7. Candidate designs compared across the scenario classes

**Designs compared:**
- **A**: the paused design (one shared file, digests per document; sync-fix adds `seen`, `currentLayouts` and `copiedLayouts`).
- **B**: one file per Mac, with a last-writer-wins map ordered by HLC.
- **C**: one replica file per Mac, with a map of MV-registers carrying dots and a version vector per file (**recommended**).
- **D**: one file per Mac, with a three-way merge against a base per peer and no dots.
- **E**: one Automerge document per Mac.

**Legend:**
- ✓ handled structurally;
- ◐ handled with extra rules, or only partly;
- ✗ fails, or depends on heuristics that the reviews broke.

| Class | A | B | C | D | E |
|---|---|---|---|---|---|
| C1 join, re-join, resume | ◐ one question for the whole document; layout heuristics (`ownLayoutToTakeIn`, kept records) | ✗ silently takes the newest per key (or the folder wins) | ✓ compares per key *before* publishing; asks only about keys that differ; layouts edited during the pause have no dots, so they are asked about | ◐ no base, so asks about every difference | ◐ the merge picks winners; the app must check conflicts |
| C2 one-sided change, third Mac | ◐ works per document; a third Mac needed `seen` | ✓ | ✓ | ◐ needs causal information to know which peer is newest | ✓ |
| C3 different settings changed concurrently | ✗ whole-document question; either answer loses one side | ✓ | ✓ merged (or asked, if the policy says so, §10) | ✓ | ✓ |
| C4 same setting changed concurrently, answer races | ◐ asks, for the whole document; the "Keep" scope needed rounds 1–3 | ✗ silent loss | ✓ siblings; the answer's context covers exactly the values shown | ✓ for 2 Macs, ◐ for N | ◐ the winner applies unless the app checks |
| C5 automatic versus user changes | ◐ edit counter per Mac, coarse | ◐ | ✓* automatic state never gets dots (*given correct intent capture, especially on macOS 26) | ◐ | ◐ |
| C6 layouts of macOS 26 and 27 | ✗ "current" and "copied" lists, stale-copy rules (bugs in 4 rounds) | ✓ separate keys | ✓ separate namespaces; the other one passes through as state | ◐ | ✓ |
| C7 stale input (restore, old own file, late Mac) | ✗ heuristics (`recentLayouts`, `isOldOwnLayout`, not-newer rules) | ✓ with HLC, ✗ with wall clock | ✓ joining an older state changes nothing | ◐ | ✓ |
| C8 missing, damaged or oversize file | ◐ a write over a missing file reverted others (patched) | ✓ | ✓ each Mac re-creates its own file; others keep their merged state | ◐ | ✓ |
| C9 provider conflict artefacts | ✗ the moved-aside write is lost silently | ✓ none in normal use | ✓ none in normal use; a copy of a device file is the clone signal | ✓ | ✓ |
| C10 identity (clone, restore, retired Mac) | ◐ F-38 hash; dates as identity | ◐ | ✓ with F-38 plus counter = max(last+1, now, own file); a retired Mac's file is dominated and can be removed | ◐ | ◐ actor IDs must be unique too |
| C11 clocks | ✗ skew rule, `writeStamp` patch | ◐ HLC bounded; ✗ wall clock | ✓ no clock in any decision | ✓ | ✓ |
| C12 mixed builds, unknown keys | ◐ writes `Settings.plist` that beta1 applies silently; copies for beta1 | ◐ | ✓ new files are invisible to beta1; unknown keys pass through opaquely (§4.5) | ◐ | ◐ the format is opaque to older builds |
| C13 availability and latency | ◐ all or nothing on one file | ✓ merges partial sets | ✓ merges partial sets | ◐ | ✓ |
| C14 deletion semantics | ◐ never removes keys; no real deletes | ◐ tombstones | ✓ a reset is a write; absence means nothing | ◐ absence compared with the base | ✓ |
| C15 size and growth | ◐ 1 MB limit, icon (F-61) | ✓ | ✓ N small files; icons capped or stored as blobs | ◐ a base per peer kept locally | ✗/◐ history growth, binary size |
| C16 untrusted writers, privacy | ◐ bounded reads | ◐ | ◐ bounded reads plus opaque pass-through; a forged context can still supersede values, as any folder writer can today | ◐ | ◐ |

**Reading the table.** C is the only candidate without ✗ that also delivers "ask on real conflicts" exactly (C4). B fails the policy in C1 and C4. D is C without dots, and getting it right for N Macs re-creates dots. E is C with a heavy dependency, and its default resolves conflicts silently.

### 7.1 Design C against A1's taxonomy

`A1-failure-taxonomy.md` appeared while this document was being written. The tables below map design C to its root causes (RC), invariants (INV), scenario groups (G) and the pairs of "histories that look the same" (§5.2 of A1). C1–C16 above are coarser and cover the same ground.

**Root causes.**

| A1 root cause | Technique in design C that removes it | Result |
|---|---|---|
| RC-1 Whole-state writes into one shared file | Single-writer files (§4.1) | Removed |
| RC-2 Ordering and identity by wall clock | Dots and version vectors, counters `max(last+1, now, own file)` (§4.2–4.4, §8.9) | Removed |
| RC-3 A file lifecycle holzBar does not control | Replica files plus a join: stale input changes nothing, this Mac's own file heals itself, partial sets merge, dataless files are skipped (§4.5, §8.10) | Removed for correctness; delivery stays eventual |
| RC-4 Two per-OS layouts in one file, and a legacy peer that deletes missing keys | Per-item units in separate namespaces per macOS version; a new folder beta1 never reads (§8.1, §8.8) | Removed |
| RC-5 Provenance inferred from digests and missing records | A dot per unit. The replica's context is what this Mac has *seen*; `appliedDots` is what it has *taken in* (§8.4) | Removed |
| RC-6 Automatic and user changes mixed in one snapshot | Only intent writes get dots; automatic state lives in a local layer (§8.4) | Narrowed to capturing the event, chiefly on macOS 26 |
| RC-7 Peers on other versions | The boundary (§8.8), opaque pass-through for future keys (§4.5), joining for the pause | Addressed, with a stated limitation: beta1 and new builds do not sync with each other |
| RC-8 Questions and answers cover the whole state | Siblings per unit; an answer observes exactly the dots it showed (§8.5) | Removed |
| RC-9 Async and UI races, bookkeeping that is not atomic | Answer scope by dots; one serial writer; pushes never paused; **one local state file written atomically** (§8.14) | Addressed |
| RC-10 Identity, I/O and content robustness | F-38, detection of dot collisions and conflict copies, bounded background I/O, validation per entry with pass-through | Addressed |
| RC-11 Verification that could not see the defects | Pure Core functions, algebraic and model-based tests that call the real Core entry points (§8.12) | Addressed |

**Invariants.**

| A1 invariant | How design C meets it | |
|---|---|---|
| INV-1 No silent loss or revert | MV-registers. A join never drops an entry the other side's context does not cover. An answer removes only the dots it showed. | ✓ |
| INV-2 No stale value comes back | A stale value carries a covered dot whatever brings it (a restore, a copy, a late Mac), so the join ignores it. beta1 writes never enter the group. | ✓ |
| INV-3 Causality, not clocks | Dots and contexts; counters are compared only within one Mac. | ✓ |
| INV-4 Only the user's intent counts | Dots only for intent operations. Moves made during the pause count, because joining treats an existing layout as the user's. | ◐ needs correct capture on macOS 26 |
| INV-5 Per-OS authority | A Mac writes only its own namespace; the other travels along unchanged and is never deleted or replaced. | ✓ |
| INV-6 Merge, never remove | Absence carries no meaning; `removesMissingKeys: false`; union and OR for learned keys. | ✓ |
| INV-7 Ask exactly on real conflicts | Only units with two or more different sibling values, or a join with different user values. Several missed writes fast-forward because their contexts cover each other. Writes happen only for intent or merges, and unchanged bytes are never written, so there is no ping-pong. | ✓ |
| INV-8 Answer scope | The observed set is exactly the dots shown. | ✓ |
| INV-9 A waiting change lasts | Waiting changes are entries in the persisted replica and in the other Macs' files, so they survive relaunches, file loss and pushes. | ✓ |
| INV-10 Atomic, recoverable bookkeeping | §8.14. A lost local state is treated as joining (dot-less values), never read as evidence. The replica can be rebuilt from this Mac's own file in the folder. | ✓ if implemented as in §8.14 |
| INV-11 One identity per Mac | F-38, plus the collision and conflict-copy signals (§8.9). | ✓ |
| INV-12 Non-blocking I/O | §8.6 and §8.10. | ✓ |
| INV-13 Size and validation | A size check at the writer with a visible warning (F-61 strings); validation per entry when applying; pass-through; never writing back a loss. | ✓ |
| INV-14 Mixed versions are safe | beta1 never sees the new folder, and the new build never writes the old file. | ✓ (no sync between beta1 and the new build) |
| INV-15 Convergence | The states form a join-semilattice; only open siblings wait, for an answer; nothing waits as a "copy". | ✓ |
| INV-16 Verifiability | §8.12; the glue does only I/O. | ✓ |

**Histories that look the same (A1 §5.2).** Design C records the fact that tells each pair apart:

| Pair | Fact that tells them apart in design C |
|---|---|
| 1 A beta1 write-back of an old copy against a beta1 user returning to L1 | beta1 never writes into the group. The old file is only an input when joining, and a difference is asked about. |
| 2 The file was deleted after B's unseen write, against a new folder | There is no shared file. B's write lives in B's file and in every replica that merged it, and nothing this Mac writes can remove it. An empty `Macs/` folder means a new group. |
| 3 B's clock lags on a new change, against an old version restored | A new change has a dot this Mac's context does not cover; a restored version has only covered dots. No clock is involved. |
| 4 beta1 may have arranged the layout, against no current layout | As pair 1 (the boundary). |
| 5 The kept-layout record was lost, against a real old copy | There are no kept records. The replica and `appliedDots` are persisted atomically, and a lost state means joining. |
| 6 The user moved items, against macOS displacing them | Not a merge question. The move is captured where the user makes it (§8.4). |
| 7 The user moved an unsaved item, against holzBar placing it | As pair 6. |
| 8 This Mac applied B's change, against adopting B's version but keeping its own layout | `appliedDots` per unit is the "taken in" fact; the context is the "seen" fact. |
| 9 Nothing changed, against A→B→A or the clock set back | Each write has a new dot, so a revert is visible as a new write (harmless: equal values do not conflict). Counters never go back. |

**Scenario groups G1–G10 of A1:**
- G1 (joining, identity, routine writes): §8.7, §8.9.
- G2 (infrastructure): §8.10.
- G3 (two macOS versions): the namespaces.
- G4 (beta1 on the same macOS): the boundary.
- G5 (clocks): no clocks in decisions.
- G6 (missing, restored, unusable): the join plus replica files.
- G7 (answers): §8.5.
- G8 (automatic versus user): §8.4.
- G9 (races): answer scope, a serial writer, the atomic state of §8.14.
- G10 (convergence and how often holzBar asks): INV-7 and INV-15 above, with the I1–I4 checks of §8.12.

**A1's optional "stop syncing the arrangement":** in design C this is a switch in the schema (leave out the two layout namespaces), not a redesign. Design C also makes it unnecessary.

---

## 8. Sketch of the recommended design (C), for the planner

This is a sketch to plan against, not a specification. The names are illustrative.

### 8.1 On disk

```
<sync folder>/holzBar/Settings.plist          # beta1's file: never written, read only when joining (§8.8)
<sync folder>/holzBar/Macs/<MacID>.plist      # one per Mac, written only by that Mac (binary plist or JSON)
<sync folder>/holzBar/Macs/blobs/<sha256>.png # optional: large immutable values (§8.11)
```

- beta1 reads only `holzBar/Settings.plist`, so it never sees `Macs/`.
- The beta1 presenter on `holzBar/` may notice changes in the subfolder, re-read `Settings.plist` and find nothing newer. That is harmless.
- A future change that older readers could not handle uses a new folder name. Smaller additions rely on the pass-through rule (§4.5).

### 8.2 State model

```swift
struct Dot: Hashable { let mac: MacID; let counter: UInt64 }            // Mac IDs stored as an index into a table in the file
struct Entry { let dot: Dot; let value: OpaqueValue }                   // canonical bytes plus kind, passed through unchanged
struct Replica {                                                         // what one Mac's file holds
    var context: [MacID: UInt64]                                         // version vector: every dot this replica has seen
    var registers: [UnitKey: [Entry]]                                    // MV-register per conflict unit (usually 1 entry)
    var sets: [Key: Set<String>]                                         // grow-only learned lists
    var flags: [Key: Bool]                                               // enable-wins learned flags
    var written: Date                                                    // display only
}
```

**Conflict units** are defined in one schema table in Core. A unit is the smallest set of keys that must change together:
- a scalar key is its own unit;
- `holzBarIcon` with `customHolzBarIconIsTemplate`;
- `LayoutProfiles` (one per profile ID, or the whole list) with `CurrentLayoutProfile`;
- the appearance keys as a group;
- one unit per hotkey action;
- **one unit per item in each macOS version's layout namespace** (`Layout26/<itemTag>`, `Layout27/<bundleID>`);
- one unit per item icon.

The rejected per-setting option already called for atomic groups such as `LayoutProfiles` with `CurrentLayoutProfile`. Learned keys are sets and flags, never units.

### 8.3 Merge: the join

```swift
func covers(_ c: [MacID: UInt64], _ d: Dot) -> Bool { (c[d.mac] ?? 0) >= d.counter }

func join(_ a: Replica, _ b: Replica) -> Replica {
    var out = Replica(context: a.context.merging(b.context, uniquingKeysWith: max), ...)
    for unit in Set(a.registers.keys).union(b.registers.keys) {
        let ea = a.registers[unit] ?? [], eb = b.registers[unit] ?? []
        let dotsA = Set(ea.map(\.dot)), dotsB = Set(eb.map(\.dot))
        let keep = ea.filter { dotsB.contains($0.dot) || !covers(b.context, $0.dot) }
                 + eb.filter { !dotsA.contains($0.dot) && !covers(a.context, $0.dot) }
        if !keep.isEmpty { out.registers[unit] = keep.sorted(by: dotOrder) }   // deterministic order
    }
    out.sets  = a.sets.merging(b.sets) { $0.union($1) }
    out.flags = a.flags.merging(b.flags) { $0 || $1 }
    return out
}
```

**Properties to test:** the join is commutative, associative and idempotent, and `join(x, older(x)) == x`.

**Each Mac's view** is the join of its persisted replica with every readable file in `Macs/`, including its own file there (§8.9). Files that are unreadable, refused or still dataless are simply left out for now.

### 8.4 Writes: only user intent creates dots

**User intent creates dots:**
- a control in the Settings window;
- a move in the Layout pane;
- a Command-drag in the menu bar;
- applying a profile;
- importing settings;
- resetting to defaults (written as values, never as deletions).

**Automatic state creates no dots:**
- seeding the macOS 27 layout;
- placing new items;
- reconciling the bar;
- migrations;
- learned lists, which are sets or flags instead.

It lives in a local layer. The effective layout entry is the synced intent if there is one, and the local automatic placement otherwise. Another Mac's intent therefore replaces this Mac's automatic placement without a question, which is exactly the SA-05 rule. On macOS 26, attribute a move where the user makes it (the drag handler, with the item's identity), not by comparing saved sections afterwards. When the attribution is uncertain, treating the move as automatic is the safe default: it never overwrites another Mac, though a real move then stays on this Mac until the next deliberate edit. The maintainer should decide this trade-off.

**The applied-context rule** (the key subtlety). Each Mac keeps, per unit, the dots its *applied* value reflects (`appliedDots[unit]`): what the user saw. A local write replaces only those:

```swift
counter = max(counter + 1, unixSecondsNow, ownFileCounter)                 // never reuses a dot (§8.9)
let new = Entry(dot: Dot(mac: me, counter: counter), value: v)
replica.registers[u] = (replica.registers[u] ?? []).filter { !appliedDots[u].contains($0.dot) } + [new]
replica.context[me] = counter
appliedDots[u] = [new.dot]
```

A remote entry that was received but not yet applied (one waiting for a restart) therefore stays as a sibling, and the unit becomes a question. This is the per-unit form of the maintainer's rule (b): another Mac's newer version arrived while this Mac had user changes. Waiting remote changes to *other* units stay non-conflicting.

### 8.5 Conflicts: detecting, showing and answering them

- **A conflict** is a unit whose entries hold two or more *different* values. Equal values are not a conflict, and the next write collapses them.
- **While it is open,** each Mac keeps the value it has applied. Nothing is applied silently. Pushes are *not* paused: other units keep syncing. This replaces "pending blocks all pushes".
- **The hint follows decision `modal-alerts-1`:** a quiet hint ("Choose Settings…") and a sheet in Settings. The sheet lists the conflicting units, with "this Mac" against "another Mac" and the other Mac's wall-clock time for display.
- **An answer** is a write whose observed set is *exactly the entries shown in the sheet*: `filter { !shown.contains($0.dot) } + [new]`. An entry that arrived while the sheet was open survives as a sibling and is asked about again. That closes rounds 1–3 by construction. If the answers are bulk "Use Settings from Sync Folder" or "Keep This Mac's Settings", each one becomes one write per unit.
- **Answers on two Macs at once** create a new pair of siblings and one more question. Once anyone answers, it converges.

**Example timeline:**
1. Mac A sets `ShowIcon` to false, with dot (A, t1).
2. Mac B reads A's file and shows "Restart". Before restarting, B's user sets `ShowIcon` to true: dot (B, t2), which observed only B's old entry. Both entries now exist, so both Macs show "Choose…".
3. The user answers "true" on Mac A: dot (A, t3), which observed (A, t1) and (B, t2). B merges A's file, both old entries are covered, and the question disappears on B. No restart is needed there, because B already applies true.

### 8.6 Launch and while running

**At launch** (in `AppDelegate.init`, bounded to about 1 s in total, reading only local, non-dataless files):
- join;
- apply silently every unit whose merged value is single and differs from the applied one (allowed by the maintainer's policy because none of these is a user change on this Mac);
- leave conflicts for the hint after setup;
- never show a dialog during init.

**While running:**
- a merge that brings non-conflicting changes shows the "Restart" hint;
- one that brings conflicts shows "Choose…".

Apply with `SettingsBackup.apply(_:removesMissingKeys: false)`, and only for the units that changed.

**Writing this Mac's file:**
- debounced by about 2 s;
- skipped when the canonical bytes are unchanged;
- an atomic write, coordinated with `.forReplacing` for iCloud, off the main actor and time-bounded;
- the file is the merged replica, so this Mac also relays other Macs' values (C2, third Mac).

### 8.7 Join, re-join, folder change, sync off and on, and the pause

**Joining.** This covers Turn On…, Change…, the first launch of the redesign, and any Mac with dot-less local values. Compare per unit, and publish nothing until it is decided:

| Local value (no dot) | Folder | Result |
|---|---|---|
| equal to the folder's | any | adopt; `appliedDots` = the folder's dots |
| set by the user | missing | written as a new entry, no question |
| default or never set | present | adopt the folder's value silently (**policy question**, §10) |
| set by the user and different | present | **join question** (the maintainer's chosen option). "Use Settings from Sync Folder" adopts. "Keep This Mac's Settings" writes with observed = the folder's dots, so the local value dominates. "Cancel" leaves sync off and publishes nothing. |

**The pause requirement (`77ab5629`).** An existing layout on a Mac migrating from any earlier build counts as the user's, in both macOS namespaces. If it differs from the folder's, it is asked about, never silently replaced.

**Sync off and on with the same folder.** Keep recording dots for user writes while sync is off; it costs nothing. Turning sync on again is then an ordinary merge: changes made in the meantime are concurrent with the other Macs' and are asked about only when the same unit changed on both sides. No "base reset" special case is needed.

**Changing to a different folder.** That folder's group is joined (the table above). The persisted replica is kept, because dots are globally unique.

**A re-identified Mac (F-38).** Keep the replica, start using a new Mac ID, and continue. A copied state is a valid replica state, so nothing needs asking unless local values differ without dots.

### 8.8 beta1 files and mixed fleets

- **Never write `holzBar/Settings.plist`** (§4.9).
- **Read it only to join,** when `Macs/` holds no other Mac's file yet: its settings act as a dot-less remote state, and the join table applies. Afterwards, ignore it.
- **Optional hint:** if it changes after the group exists, "A Mac with holzBar 0.0.7 beta 1 still uses this folder; update it to sync with it." This is detected by its `modified` date or by a `deviceID` this Mac does not know.
- **Mixed fleets are two separate groups.** beta1 Macs keep syncing among themselves through the old file, with its known bugs. The release notes must say: update every Mac; Macs on beta 1 and on this build do not sync with each other. Beta2 Macs are paused and touch nothing.
- **Continuously importing beta1 changes** would need a per-key three-way diff against the last imported legacy snapshot. It is possible but not worth it for a beta.

### 8.9 Identity and counters

- **Mac ID:** a random UUID, re-issued when the salted hash of the hardware UUID does not match. Reuse the F-38 code and `SettingsSyncDevice` as they are.
- **Counter:** `max(last + 1, unix seconds, counter in own file)`, the Syncthing rule plus the folder as a backup. Counters are compared only within one Mac, so clock skew between Macs is irrelevant.
- **Own file found ahead of the local state** (preferences restored from a backup): join it, because it is this Mac's own newer state.
- **Own file holding the same dot with a different value** (a collision, so two writers share the ID): re-identify and log it.
- **Conflict copies of a device file** (Dropbox, OneDrive, Nextcloud, Syncthing, or iCloud conflict versions): treat them as the same collision signal.
- **"Forget a Mac" (optional):** delete its file only when every live Mac's version vector covers its counter, deleting only files this Mac has loaded (the automerge-repo rule).

### 8.10 I/O and notifications by provider

**Reading:**
- List `Macs/` (metadata only) and accept names that match the UUID pattern only.
- For each file, `lstat`: it must be a regular file, within the size limit, and not a symlink.
- If it is local (`SettingsSyncFile.isLocal`), read it bounded and off the main actor. If it is dataless, request a background download and check again later. A file that cannot be read now counts as "unreadable", never as "missing".
- Cap the number of Mac files (for example 32) and the number of entries, for C16.

**Notifications:**
- `NSFilePresenter` on `Macs/` for iCloud.
- FSEvents or `DispatchSource` for every other provider.
- A slow timer, plus wake and app activation, for everyone; a faster timer on network volumes. Never mount anything (F-18 rules stay).

**Writing:** one serial writer (an actor), an atomic replace with a temporary name that starts with a dot, and coordination for iCloud. Never on the main actor (F-15).

### 8.11 Size, icons, validation

**File size** (estimates):
- about 70 units at about 30–60 B each, plus JSON blobs for appearance and profiles of about 1–10 KB;
- layout entries of about 50–60 B, so roughly 12 KB for 100 items in both macOS namespaces;
- Mac table and version vector under 0.5 KB;
- **about 10–40 KB per Mac file** as a binary plist (XML is 2–3 times larger).

**Custom icon (F-61):**
- *First choice:* cap it and convert it once at migration (store the image once, as PNG, ≤ 128 KB); it stays inline.
- *Only if a cap is not acceptable:* content-addressed blobs in `Macs/blobs/<sha256>`, immutable and therefore never in conflict. Delete a blob only when no loaded Mac file references it and it is older than 30 days.

**Size limit at the writer (F-61, INV-13):** check the encoded size before writing. If the file would exceed the readers' limit, do not write it, and show a visible warning in the sync settings (new strings in the five languages). Never write a file that the other Macs would refuse.

**Validation (F-59):** decode per entry when applying to `UserDefaults`. Skip and log bad entries locally, keep them unchanged in the replica, and never "repair" them by writing an empty value (§4.5 pitfall).

### 8.12 Tests that replace review rounds

**Algebraic properties on random replicas:**
- the join is commutative, associative and idempotent;
- joining an older state changes nothing;
- `write` grows the context monotonically.

**Model-based simulation** (Swift Testing with a seeded random generator; plus exhaustive enumeration of small cases, such as 2 Macs, 2 units and up to 5 events):
- 2–4 Macs on macOS 26 and 27;
- events: user writes, automatic placements, publishing, delivery with delays, **stale restores of older files**, deleting files, conflict copies, relaunches (apply at launch), answers (including concurrent ones), sync off and on, folder change, clones, restoring preferences from a backup, clock jumps.

**Invariants:**
- **I1 Convergence.** Once every Mac has read the same files and no question is open, every Mac has the same replica and the same applied values.
- **I2 No silent loss.** Every user write is applied everywhere, or covered by a later user write or answer whose context included it, or a sibling in a question shown on every Mac that holds it.
- **I3 Stale input changes nothing.** Delivering an older file never changes applied values and never opens a question.
- **I4 No question without a real conflict.** A question exists only for a unit with two or more different values, or a join with different user values.
- **I5 Automatic state stays quiet.** Automatic placements never create dots, questions or remote changes.
- **I6 Layout namespaces stay separate.** A Mac never writes the other macOS version's layout namespace, and passes it through unchanged.
- **I7 A Mac's published context never goes backwards,** across relaunches and restored preferences.

A failing seed is a reproducible bug report. Mutation testing (already used in rounds 1–6) then checks that the invariants catch broken guards. The simulated Macs must call the same Core entry points the app calls, never a copy of the glue: the round 6 known risk and A1's RC-11. The app's glue should only do I/O and present the UI.

### 8.13 Cost and reuse

**New code in Core:**
- replica, join, write and resolve: about 250–400 lines;
- schema (conflict units, namespaces, defaults): about 100–150 lines;
- launch, apply and join plans as pure functions: about 150–250 lines;
- tests: about 800–1500 lines.

**App glue:**
- file actor (list, read, write, dataless handling, notifications): about 300–500 lines;
- hint and sheet, reusing the existing strings where they fit ("Settings changed on another Mac", "Restart", "Choose Settings…", "Use Settings from Sync Folder", "Keep This Mac's Settings").

**Keep from the paused code:**
- `SettingsSyncFile.readContents`, `isUsableFolder` and `isLocal`;
- `SettingsSyncDevice` (F-38);
- `SettingsSyncLocation`;
- the learned-key merge;
- the canonical encoding in `SettingsSyncPolicy.digest`, for testing whether two values are equal;
- `SettingsSyncPause`;
- `SettingsBackup.apply(_:removesMissingKeys:)`;
- the F-14 run-loop helper.

**Remove:**
- the base digests and the pending state;
- `seen` and `writeStamp`;
- `currentLayouts`, `copiedLayouts`, the kept records and `recentLayouts`;
- `allowedClockSkew` and `isNewer`;
- the layout-edit counter (replaced by capturing intent).

### 8.14 This Mac's sync state, stored atomically (INV-10)

Store the replica, `appliedDots`, the counter and the joining state in **one** local file (for example `~/Library/Application Support/holzBar/SyncState.plist`, written atomically), or in one encoded `SettingsSync…` value, never in several keys that a quit can leave half updated.

- **Order of operations:** apply the settings, then store the state that records them as applied. A crash in between applies the same values again, which is harmless because applying is idempotent.
- **Rebuilding:** a missing or unreadable state is rebuilt from this Mac's own file in the folder, and otherwise treated as joining (dot-less values). It is never read as evidence that something was "already synced".
- **Export and import:** the `SettingsSync` prefix keeps the state out of exported, imported and synced settings, as today.

---

## 9. Risks that remain with design C

- **Attributing intent on macOS 26** (C5) still decides whether a move counts. No merge design removes this; it needs work at the input.
- **Units that are too coarse** produce questions about unrelated changes; units that are too fine produce mixed states nobody made. The schema table is a product decision, made once.
- **Someone who can write the folder** can forge a context that supersedes values. That is no worse than today, where such a writer can replace `Settings.plist`. Authenticity is out of scope without keys.
- **Mixed fleets** do not sync with beta1 Macs. This must be stated in the release notes and the UI.
- **Open siblings persist** until someone answers, at most one per Mac and unit. The hint must stay visible.
- **A real two-Mac test is still required**: dataless files at login, presenter events, Syncthing delays, and an SMB share that is not mounted. The scope of the human check in `sync-1.md` stays.

---

## 10. Policy questions this research raises for the maintainer

1. **Different settings changed on two Macs:** merge them silently (recommended; nothing is overwritten or reverted) or ask, the stricter reading of `sync-1.md`, which chose "ask" for the whole settings? The rejected option "Pro Einstellung zusammenführen" merged per setting *but never asked, even when the same setting changed on both Macs*, and its description called it "schwerer vorhersehbar" (harder to predict). Design C asks for the same setting and merges different ones.
2. **Partial apply:** at launch, apply non-conflicting units while others wait for an answer, or hold everything until the question is answered?
3. **How fine-grained the question is:** per unit, per group (Appearance, Layout for this macOS, Hotkeys, Profiles, Icon), or one bulk choice ("Use folder" or "Keep this Mac") with a list of details?
4. **Defaults at join:** does a value equal to its default count as "no user value", so the folder's value is adopted silently? Layouts are excluded by the pause requirement.
5. **A third Mac while a conflict is open:** keep its value until the question is answered (recommended), or apply a deterministic interim winner?
6. **Mixed fleets:** accept that beta1 and new builds do not sync with each other (recommended), or build a one-way import of beta1 changes?
7. **Naming the other Mac in the sheet:** with nothing ("another Mac"), with the model ("MacBook Pro"), or with a name the user chooses? The computer name usually contains the owner's name and was removed from the file in beta1.
8. **Custom icon:** cap and convert (recommended), or content-addressed blobs?
9. **Rolling back on purpose:** a provider restore or Dropbox Rewind is deliberately ignored, because the folder is only a transport. Rollback goes through Export and Import, which are user writes and therefore propagate. Document this.

---

## 11. References

### Fetched or looked up for this research (2026-10-07)

- Syncthing, "Understanding Synchronization" (conflict naming, delete versus modify, temporary files): https://docs.syncthing.net/users/syncing.html
- Syncthing, Block Exchange Protocol v1 (version vectors, deleted flag): https://docs.syncthing.net/specs/bep-v1.html
- Syncthing `lib/protocol/vector.go` (`Value = max(Value+1, now)`): https://github.com/syncthing/syncthing/blob/main/lib/protocol/vector.go
- Dropbox Help, conflicted copies: https://help.dropbox.com/organize/conflicted-copy
- Dropbox Help, online-only files on macOS: https://help.dropbox.com/sync/online-only-mac
- TidBITS, "Apple's File Provider Forces Mac Cloud Storage Changes" (2023): https://tidbits.com/2023/03/10/apples-file-provider-forces-mac-cloud-storage-changes/
- OneDrive conflict copies with the computer name: https://natechamberlain.com/2017/09/20/onedrive-and-sharepoint-sync-issue-you-now-have-two-copies-of-a-file-we-couldnt-merge-the-changes-in-filename-appended-with-computer-name/ and https://www.digitalcitizen.life/cloud-sync-conflicts-explained-why-files-duplicate-or-overwrite-themselves/
- Nextcloud desktop manual, conflicts (conflict file not uploaded by default): https://github.com/nextcloud/documentation/blob/master/user_manual/desktop/conflicts.rst
- Apple, "Resolving Document Version Conflicts" (conflict winner, `NSFileVersion`): https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/DocumentBasedAppPGiOS/ResolveVersionConflicts/ResolveVersionConflicts.html
- Apple, "The Role of File Coordinators and Presenters": https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileCoordinators/FileCoordinators.html
- Apple Support, "If document versions conflict in iCloud Drive on Mac": https://support.apple.com/en-ca/guide/mac-help/mh40780/mac
- Apple Developer Forums, "NSFileVersion.currentVersionOfItem not consistent across devices after simultaneous edit" (DTS reply): https://developer.apple.com/forums/thread/804253
- AppleInsider, macOS 14.4 bug deleting iCloud Drive file versions: https://forums.appleinsider.com/discussion/235819/new-macos-sonoma-14-4-bug-kills-file-versions-in-icloud-drive
- Arq, "Backing Up Dataless Files": https://www.arqbackup.com/documentation/arq7/English.lproj/datalessFiles.html
- Eclectic Light, "Watching macOS file systems: FSEvents and volume journals": https://eclecticlight.co/2017/09/12/watching-macos-file-systems-fsevents-and-volume-journals/
- Ensembles 3 (event files, causal ordering, add-wins, baselines, "requires no custom server"): https://github.com/mentalfaculty/Ensembles3; Ensembles 1/2: https://github.com/drewmccormack/ensembles
- objc.io, "iCloud and Core Data": https://www.objc.io/issues/10-syncing-data/icloud-core-data/; Apple, "Using Core Data with iCloud" (retired): https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/UsingCoreDataWithiCloudPG/Introduction/Introduction.html
- Automerge, conflicts (`getConflicts`): https://automerge.org/docs/reference/documents/conflicts/; storage: https://automerge.org/docs/reference/repositories/storage/; "Concurrent Compaction in Automerge Repo": https://patternist.xyz/posts/concurrent-compaction-in-automerge-repo/
- VS Code, Settings Sync (conflicts, keybindings per platform, ignored and machine settings): https://code.visualstudio.com/docs/configure/settings-sync
- Kulkarni, Demirbas et al., "Logical Physical Clocks and Consistent Snapshots in Globally Distributed Databases" (HLC, 2014): https://cse.buffalo.edu/tech-reports/2014-04.pdf

### Cited from memory (standard literature, not fetched)

- D. S. Parker et al., "Detection of Mutual Inconsistency in Distributed Systems", IEEE TSE 9(3), 1983.
- L. Lamport, "Time, Clocks, and the Ordering of Events in a Distributed System", CACM 1978.
- P. R. Johnson, R. H. Thomas, "The Maintenance of Duplicate Databases", RFC 677, 1975: https://www.rfc-editor.org/rfc/rfc677
- M. Shapiro, N. Preguiça, C. Baquero, M. Zawirski, "Conflict-free Replicated Data Types", SSS 2011, and "A comprehensive study of Convergent and Commutative Replicated Data Types", INRIA RR-7506, 2011 (MV-Register, OR-Set, LWW).
- A. Bieniusa et al., "An Optimized Conflict-free Replicated Set", arXiv:1210.3368, 2012.
- P. S. Almeida, A. Shoker, C. Baquero, "Delta State Replicated Data Types", JPDC 2018, arXiv:1603.01529 (dot stores, causal contexts).
- N. Preguiça, C. Baquero, P. S. Almeida, V. Fonte, R. Gonçalves, "Dotted Version Vectors: Logical Clocks for Optimistic Replication", arXiv:1011.5808, 2010; P. S. Almeida et al., "Scalable and Accurate Causality Tracking for Eventually Consistent Stores", DAIS 2014.
- G. DeCandia et al., "Dynamo: Amazon's Highly Available Key-value Store", SOSP 2007 (siblings, client reconciliation).
- S. Balasubramaniam, B. C. Pierce, "What is a File Synchronizer?", MobiCom 1998; B. C. Pierce, J. Vouillon, "What's in Unison? A Formal Specification and Reference Implementation of a File Synchronizer", 2004.
- M. Kleppmann, A. Wiggins, P. van Hardenberg, M. McGranaghan, "Local-first software: You own your data, in spite of the cloud", Onward! 2019: https://www.inkandswitch.com/local-first/
- J. Long, "CRDTs for Mortals" (dotJS 2019), on Actual Budget's HLC-based per-field last-writer-wins sync.
- Riak 2.0 (`allow_mult` siblings, `dvv_enabled`), the `riak_dt` map; Akka Distributed Data (`LWWRegister`, `ORMap`); the Rust `crdts` crate.
