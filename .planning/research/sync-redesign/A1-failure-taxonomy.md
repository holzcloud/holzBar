# A1 · Settings sync: failure taxonomy, why the patches regressed, regression catalogue

Input for the settings-sync redesign (sync paused in 0.0.7-beta2). Read-only analysis, 2026-10-07.

Sources:
- paused code on `audit/remediation-2026-10-05` (`SettingsSync.swift`, `Core/SettingsSync*.swift`, `SettingsBackup.swift`, `SectionRestore.swift`, `Concealer27.swift`, `LayoutProfiles.swift`);
- the 58 commits and `sync-fix-SUMMARY.md` on `audit-manual/sync-fix` (`0320c839` … `9b0f4bb5`);
- the review records `sa05-review2.json`, `syncfix-loop.json` and `syncfix-round4-issues.json`;
- audit findings F-02, F-15, F-38, F-59, F-60 and F-61;
- the decisions `sync-1.md` and `modal-alerts-1.md`;
- the sync section of `docs/features.md` (both branches);
- the pause record in `REMEDIATION-2026-10-05.md` and the todo `2026-10-07-redesign-settings-sync-paused-in-0-0-7-beta2.md`;
- the `v0.0.7-beta1` sync code (`SettingsSync.swift`, `SettingsSyncFile.swift`, `SettingsBackup.swift`).

---

## 0. Conventions

| Term | Meaning |
|---|---|
| **β1** | 0.0.7-beta1, released, in the field. It cannot be changed (§2.1). |
| **β2** | 0.0.7-beta2. Sync is paused: no migration, no layout-edit counting, no version marker. |
| **SA05** | The paused code on `audit/remediation-2026-10-05`: the F-02/F-15/F-38/F-60 base plus SA-05. |
| **R1…R6** | Fix rounds 1–6 on `audit-manual/sync-fix`. Not merged; the reference for the redesign. |
| **V0** | The second SA-05 review (`sa05-review2.json`, 9 confirmed findings), which was the input to R1. |
| **V1…V5** | The reviews of R1…R5, each the input to the next round. The titles of V1–V3 are in `syncfix-loop.json` (the `confirmed` lists of rounds 1–3), V3 in detail is in `syncfix-round4-issues.json`, and V4 and V5 are rebuilt from the R5/R6 commit messages and the summary. R6 was never reviewed: sync was paused instead. |
| **Steps A–AP** | The manual two-Mac steps in `sync-fix-SUMMARY.md`: A–H from R1, I–P R2, Q–W R3, X–AD R4, AE–AJ R5, AK–AP R6. |
| **N** | The redesigned build, which must pass §6. |
| **INV-n / RC-n / P-n / S-nn** | Invariants (§3), root-cause classes (§4), design properties (§5) and regression scenarios (§6). |
| **Layout keys** | `ItemSections` is the macOS 26 key (item identity → section index). It is saved as a **snapshot of every cached item on the bar** (`SectionRestore.saveSections`). `MacOS27Layout` is the macOS 27 key (bundle ID → section). It also holds holzBar's own placements of new apps (`Concealer27`). A Mac's **own** layout is the key for the macOS version it runs. The **other** key it holds only as a copy. |
| **Arrangement** | A layout state the user made on purpose. |
| **Placement** | A layout entry that holzBar or macOS made. |

---

## 1. Executive summary

1. **About 50 confirmed defects (V0 9, V1 9, V2 9, V3 7, V4 ≈8, V5 ≈8) and the six audit findings come down to 11 root-cause classes (§4).** Seven of them are data-model problems, not logic slips:
   - each Mac writes its whole state into one shared file (RC-1);
   - versions are ordered by wall-clock dates (RC-2);
   - the file has a lifecycle holzBar does not control: deleted, restored, damaged, dataless (RC-3);
   - one file holds two per-OS layouts, and a legacy peer deletes the keys a file lacks (RC-4);
   - where a value came from is guessed from content digests and from missing records (RC-5);
   - the layout values are snapshots of the observed bar, not the user's moves (RC-6);
   - legacy peers drop all new metadata and apply silently (RC-7).
2. **After V0, every blocker is a menu-bar arrangement that is silently reverted or lost.** All the classes meet in the two layout keys. User settings alone are affected by RC-1 to RC-3 as well (S-28, S-32–S-35, S-39, S-40, S-46), but less severely.
3. **The rounds did not converge, because the information needed to decide was never recorded.** §5.2 lists nine pairs of histories that look the same to the decision code but need opposite outcomes. Each patch chose one history and broke the other, or added a proxy (a date, a digest or a flag) that had its own failure case.
4. **The trend went the wrong way.**
   - Blockers per review: V0 2, V1 0, V2 1, V3 1, V4 3, V5 3.
   - 25 of about 41 findings in V1–V5 were introduced or only half fixed by the previous round's change (§5.3).
   - From SA05 to R6, `SettingsSyncPolicy.swift` grew from 717 to 2,358 lines and the persisted `SettingsSync*` keys from 11 to 16.
   - The sync-file keys grew from 3 (β1) to 6.
   - The user-facing rule list in `features.md` turned into ten dense paragraphs.
5. **Some required outcomes cannot all be met while β1 Macs read and write the same `Settings.plist` (§5.4).** β1 applies a newer file silently at launch, deletes every key the file lacks, drops unknown keys, and rewrites the file at every launch. The redesign has to set this boundary on purpose. No rule inside the old file format can keep F-60 and "never revert silently" for a β1 peer once the file is lost.
6. **The regression catalogue (§6) has 70 scenarios.** Each gives the Macs, macOS versions, builds, steps, the wrong outcome as observed, and the required outcome. It includes must-not-ask and must-converge scenarios (S-07, S-14, S-44, S-55, S-63, S-68–S-70). These guard against two easy ways out that R5/R6 already partly took:
   - being "safe" by asking every time;
   - being "safe" by never passing a change on. In R5/R6, arrangements wait as copies until the user's next rearrangement.

---

## 2. What the code does (the behaviour the taxonomy refers to)

### 2.1 β1, the legacy peer in the field (`v0.0.7-beta1`)

**The file.** `<folder>/holzBar/Settings.plist` is an XML plist with the keys `{modified: Date.now, deviceID: <UUID>, settings: <every exportable key except SyncsSettingsWithICloud and SettingsSync*>}`.

**When β1 writes (`push()`).** β1 never reads the file before writing. Its only guard is that the bytes differ from `lastPushedData`, which is nil at launch. There is no size check, and the coordinated `.forReplacing` write runs on the main thread. It writes:
- whenever `isEnabled` goes from false to true, which happens at **every launch** through `performSetup` and at Turn On…;
- after Change…, which clears `lastPushedData`;
- 5 s (debounced) after **any** defaults change, including holzBar's automatic writes of `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners`, `ItemSections` and `MacOS27Layout`.

**When β1 reads.**
- At launch, in `AppDelegate.init`, `pullIfNeeded()` does a synchronous coordinated read on the main thread. It applies the file if all three hold:
  - the file is not from this Mac (`deviceID`; for older files, the computer name);
  - `modified > lastSynced`;
  - `modified <= now + 1 h`.
  
  It applies **silently**, through `SettingsBackup.apply`, which **removes every local key that the file lacks or that fails validation**. Then it sets `lastSynced = modified`.
- While running, a presenter or folder-watcher event shows the alert "Settings changed on another Mac" with Restart and Later. It is a `runModal()` inside a main-actor Task.

**Metadata.** β1 ignores unknown top-level keys and **drops them on its next write**, because it writes only `modified`, `deviceID` and `settings`. Any metadata a newer build adds lasts only until the next β1 write, and β1 writes at every launch.

**Identity.** The device ID is a random UUID in the preferences, so Migration Assistant copies it (F-38).

### 2.2 SA05: the paused code

- **File.** The same file plus `currentLayouts`, which lists the layout keys that are current.
- **Local state, all `SettingsSync*` keys.**
  - Base digests: the user settings without the learned keys, and this Mac's own layout.
  - Pending and postponed versions, and a layout-edit counter compared with a synced count.
  - The device hash and salt (F-38).
- **I/O.** The launch read is bounded to about 1 s, and the I/O runs in the background (F-15, F-18).
- **Apply.** No key removal (F-60). Learned keys are merged.
- **Size.** A 1 MiB limit **when reading only**. V0-#1 found the write side unchecked.
- **Decision.** `decide(trigger, local, file)` returns `none / wait / retry / adopt / write / apply / ask`. `fileToWrite` takes the other-OS layout from the file. It lists this Mac's own layout as current when the user edited it or the file has no current own layout. Otherwise it keeps the file's current layout and merges in only this Mac's entries the file has never seen.
- **Silent paths that remain.**
  - apply at launch when there are no local changes;
  - `.adopt`;
  - taking in the other-OS layout;
  - every β1 peer's own silent apply.

### 2.3 What R1–R6 added (reference branch)

- **File keys.** `copiedLayouts` (R1); `basedOn` (R4, replaced in R5); `seen` (R5), which maps each sync ID to the date of that Mac's newest write the version holds.
- **Local keys.**
  - `VersionSettingsDigest` and `RecentLayoutDigests` (R2). The recent-layout list was 8 entries, then 64 in R3, and recognition was dropped in R5.
  - `KeptLayoutDigest` (R3), `LastWritten` (R4) and `SeenWrites` (R5).
  - `sectionsBeforeArrangement` (R4, in memory) and `writeStamp` (R6).
- **New rule concepts.** `takeInLayout`, `keepsOver` (the answered version, identified by its content), `isUnsyncedChange`, `isOldOwnLayout`, `isBeforeLastSync`, `passesOtherLayoutAsCopy`, `writesOwnLayoutAsCopy`, `holdsOlderLayoutToJoin`, `keepsOwnLayoutOverStale`, `missesLastWrite` and `recordUnchanged`.

| Metric | β1 | SA05 | R6 |
|---|---|---|---|
| `SettingsSync.swift` lines | 533 | 1,909 | 1,851 |
| `SettingsSyncPolicy.swift` lines | n/a | 717 | 2,358 |
| `SettingsSyncFile.swift` lines | 138 | 186 | 277 |
| Sync file keys | 3 | 4 | 6 |
| Persisted `SettingsSync*` keys | 3 | 11 | 16 |
| `@Test` functions in sync test files | 22 | 92 | 157 |

### 2.4 Constraints the redesign inherits

- **No network of holzBar's own.** Sync goes only through a folder that the user's own sync app provides: iCloud Drive, Dropbox, OneDrive, Nextcloud, Syncthing or SMB.
- **Privacy.** Nothing that identifies the user leaves the Mac, except what the user syncs.
- **Two macOS versions.** Macs may run macOS 26 (`ItemSections`) and macOS 27 (`MacOS27Layout`) side by side.
- **One Mac at a time.** Updates arrive one Mac at a time, so β1, β2 and N Macs share a folder for weeks.
- **Maintainer policy** (sync-1 decision, SA-05, R4 summary):
  - ask on real conflicts;
  - never overwrite or revert silently;
  - holzBar's own automatic placements are not the user's changes;
  - the other macOS version's layout is taken in silently;
  - nothing in the sync file is overwritten with a stale copy;
  - a β1 Mac must be handled safely.
- **UI** (modal-alerts decision): a quiet hint, never a dialog by itself. Settings-window alerts become sheets. No push while a version from another Mac waits.

---

## 3. Invariants (what "correct" means; each failure in §4 violates at least one)

| ID | Invariant | Origin |
|---|---|---|
| INV-1 | **No silent loss or revert.** A user change made on any Mac is removed from that Mac, from the folder or from another Mac only after a user chose so, in a question that covered it. | F-02, F-60, policy |
| INV-2 | **No stale value comes back.** A value that a newer user change replaced never becomes current again: it is never listed, applied, taken in, or written with a fresh date. This holds whatever carries it: a restored file, a version that is not newer, a copy, or a β1 write. | policy ("never with a stale copy") |
| INV-3 | **Causality, not clocks.** "Newer", "based on", "already seen" and "an old copy" are decided from recorded causal history. They are never decided by comparing different Macs' wall clocks or by date equality to the second, and a clock step does not break them. | V1-#1, V5 clock |
| INV-4 | **Only the user's intent counts.** holzBar's placements, macOS displacements, migrations, seeding, learned keys, re-applying an unchanged profile, and a Command-click without a move never count as the user's change. They never cause a question, a hint on another Mac, or an overwrite. Every real move of the user does count: the first move of an unsaved item, a move in the Layout pane during a restore, and a move made while sync was paused. | SA-05, 77ab5629 |
| INV-5 | **Per-OS authority.** A Mac lists as current only the layout of the macOS version it runs. It takes in the other version's layout silently only when that layout is causally current. Otherwise it passes it on unchanged. It never deletes it, and never replaces it with its own copy. | SA-05, F-60 |
| INV-6 | **Merge, never remove.** Applying never removes a key the sender lacked. Learned keys merge by union or OR. | F-60, sync-1 |
| INV-7 | **Ask exactly on real conflicts.** holzBar asks when the user changed the same unit on two Macs since their common ancestor, or when a joining Mac's user state differs from the folder's. It does not ask about its own writes, fast-forwards (also after missing several writes), equal content, learned keys, the other OS's layout, automatic changes, or a β1 rewrite of unchanged content. There is no ping-pong. | F-02, SA-05 |
| INV-8 | **Answer scope.** Use and Keep apply only to the versions and differences the question covered. A version that arrives later, or a difference the user could not see, is decided anew. An answer never relists or deletes something the question did not cover. | V0-#2, V1-#2, V2-#1, V5 |
| INV-9 | **A waiting change lasts.** A remote change waiting for the user survives a relaunch, the file going away, folder errors, and pushes. Later keeps it, and no write drops it. | F-02(c), V3-#1a', V4 |
| INV-10 | **Atomic, recoverable bookkeeping.** The local sync record and the shared state cannot disagree after a quit, a crash, sync turned off, a cancelled task, or an edit made during an exchange. A lost record is detected, and it is never read as evidence ("a missing record is not proof"). | V3-#3, R2 issue 13 |
| INV-11 | **One identity per Mac.** Copied preferences never merge two Macs into one, and the identity never leaves the Mac in a recognisable form. | F-38 |
| INV-12 | **Non-blocking I/O.** The launch never waits more than about 1 s for the cloud. holzBar never mounts a share itself and never coordinates file access on the main thread. | F-15, F-18 |
| INV-13 | **Size and validation.** A writer refuses, visibly, content that readers would refuse. A malformed entry is dropped on its own and never written back as a loss. A reader never writes over a file it could not interpret, as if no other Mac had written there. | F-61, F-59, V0-#1 |
| INV-14 | **Mixed versions are safe.** While older builds share the folder, nothing an N Mac does makes a β1 Mac lose or revert a change silently, and nothing a β1 Mac writes makes an N Mac do so. A resume after β2's pause treats a layout edited during the pause as the user's. | V0-#0, 77ab5629 |
| INV-15 | **Convergence.** Once nobody changes anything and every Mac is online, all Macs reach the same user settings and the same per-OS layouts. The only action that may be needed is an answer to a real conflict. Nothing waits indefinitely as a copy. | R5/R6 accepted risk |
| INV-16 | **Verifiability.** Every decision input, state change and file field the app uses comes from code the tests run, and multi-Mac scenarios run the real code paths. | V0-#8 … V5 glue |

---

## 4. Failure taxonomy by root cause

Each class lists five things:
- **Mechanism:** the cause in the design.
- **Defects:** the scenarios (§6) and findings.
- **Violates:** the invariants broken.
- **Patches:** what R1–R6 tried.
- **Why it stays open:** the design property behind it (§5).

Many defects belong to more than one class. The class named first is the primary one.

### RC-1 · Whole-state writes into one shared file (lost update)

**Mechanism.** There is one file, `Settings.plist`, and every writer replaces it with its complete state: all user settings, both layout keys and the learned keys. A reader adopts or applies that complete state. So a writer that has not taken in every other Mac's latest change erases that change from the folder. The next reader then applies the erasure, and β1 readers do so silently at launch. SA05 added a read before every write and a merge against one base digest per Mac. The merge works at the level of a whole setting value or a whole layout dictionary. It is correct only if the writer knows its view is complete, and that knowledge has to be inferred (RC-2, RC-3, RC-5).

**Defects.**
- From the audit: F-02(a), joining writes defaults over the file (S-01); F-02(b), every launch rewrites the file and a Mac that is behind overwrites a newer one (S-02, S-03); F-02(c), Later followed by any push (S-04).
- After the F-14 fix: a push while the notice is open makes Restart apply nothing (S-05).
- V0:
  - #0 (blocker) a β1 same-OS drag replaced by an N Mac's non-layout write (S-20);
  - #1 (blocker) a file over 1 MB counted as unusable and overwritten (S-11);
  - #2 (major) Keep writes an untouched layout over a newer arrangement (S-45);
  - #5 a version that is not newer is overwritten by the next drag (S-29).
- V1: #1 a version dated before the last sync is overwritten (S-28); #2 Keep writes over a version that arrived while the sheet was open (S-46).
- V2: #1 Keep writes over a third Mac's version dated earlier (S-33); #2 a write over a missing file reverts another Mac's change (S-34).
- V3-#1: missing or unusable file (S-34, S-35, S-37).
- V4: a parent record by date only hides the missing write (S-39).
- V5: a third Mac (S-40) and Keep after a lost write (S-52).

**Violates.** INV-1, INV-8, INV-9, INV-7 (ping-pong).

**Patches.**
- SA05: read before every write, a base digest, pending, and per-layout-key merge.
- R1: answered-version identity, first by date.
- R3: answered-version identity by content (`isSame`).
- R4: `basedOn`, a date-only parent record.
- R5: `seen`, the per-Mac newest write.
- R6: `missesLastWrite` over every `seen` entry, and `writeStamp`.

**Why it stays open (P-1, P-2).** The shared object can only be replaced as a whole, and there is no atomic compare-and-swap between Macs. Every write therefore rests on the writer's claim that its view is complete. Each patch made that claim more precise for one more history, while the file still could not carry the facts that would prove it (§5.2).

### RC-2 · Ordering and identity by wall clock

**Mechanism.**
- β1 and SA05 order versions by `modified > lastSynced`, allow 1 h of clock skew, and store dates to the whole second.
- `lastSynced` serves two roles at once: the time of the last exchange, and the threshold for "stale". It is compared with dates written by other Macs' clocks.
- From R4 on, "based on" and "already seen" were also dates: `basedOn`, then `seen` holding each Mac's newest write date, plus `isBeforeLastSync` as the proxy for "older".

**Defects.**
- S-28 (V1-#1): a change dated before the last sync is ignored and overwritten.
- S-29 (V0-#5): a version that is not newer is recorded as synced.
- S-30 (follow-up `5b301828`): a version dated in the future becomes the last sync.
- S-31 (V3-#4): a re-joining Mac adopts an older version.
- S-32 (V5): the clock is set back, or two writes fall in the same second.
- S-33 (V2-#1): Keep over a version dated at or before the answered one.
- S-15, S-16, S-51: a restored version looks "not newer", exactly like a lagging clock.
- S-54 (R4 `e77271bf`): the positive evidence for an old copy is itself a date comparison.

**Violates.** INV-3, INV-2, INV-1.

**Patches.**
- `isUnsyncedChange` with `VersionSettingsDigest` (R2), `Version.syncedDate` (R2), `isBeforeLastSync` and `recordUnchanged` (R4).
- Dates per Mac in `seen`, compared only with the same Mac's own dates (R5).
- `writeStamp`, which forces each Mac's own write dates to increase (R6).

**Why it stays open (P-2).** Dates cannot tell a lagging clock from a restored file (§5.2 pair 3). Even R6's per-Mac dates are a version vector built on wall clocks: they rely on increasing clocks, store whole seconds, keep at most 64 entries, and vanish whenever β1 writes. R6's own known risks list the clock cases that are still open.

### RC-3 · A file lifecycle holzBar does not control (missing, restored, damaged, dataless, too large)

**Mechanism.** The design treats "the file" as a register that holds the latest version. Sync apps break that assumption:
- they deliver versions late, or as dataless placeholders;
- they restore older versions;
- they delete or damage the file;
- the user can recreate the folder or choose another one with Change….

Each case reaches `decide` as one of `missing`, `unusable` or `unreadable`, or as a "version" that is really an old one. `missing` and `unusable` lead to a write whenever there are changes, and that write is made without the knowledge the lost file held.

**Defects.**
- F-15 (S-09), F-18 (S-10), F-61 and V0-#1 (S-11).
- V2-#2, V3-#1a, V3-#1a' and V3-#1b (S-34, S-35, S-37).
- V4: a relaunch drops the waiting version (S-36); a copy is promoted to current (S-38); a parent by date only (S-39).
- V5: a third Mac (S-40); a record without the layout (S-41).
- V2-#6: an older version of this Mac's own is restored (S-42).
- V3-#0: a stale other-OS layout from a restore (S-15).
- V5: Keep over a restored version (S-51).
- The unusable variants (S-43).
- The residuals with β1 peers (S-19, S-26).

**Violates.** INV-1, INV-2, INV-9, INV-12, INV-13, INV-15.

**Patches.**
- `.wait` while a version waits (R4).
- A copy written over a missing file while a kept layout waits (R4), extended to "last sync held only a copy" (R6) and to Keep answered while the file is missing (R6).
- A parent record (R4), then `seen` (R5).
- A file over 1 MB is left alone (R1).
- A version that waits is still not persisted (R5: documented).

**Why it stays open (P-1, P-7, P-10).** Losing the file also loses the only record of what other Macs wrote. Each rule for "write over a missing file" has to guess that history: S-44 (a new folder must publish) and S-34 (a lost file must not revert) look the same. The R6 rule "a copy when the last sync held only a copy" is a heuristic over this ambiguity, and it trades safety for a stall (S-69).

### RC-4 · Two per-OS layouts in one file, each with a single authority, and a legacy peer that deletes missing keys

**Mechanism.**
- macOS 26 Macs author `ItemSections` and macOS 27 Macs author `MacOS27Layout`, yet every write has to carry both keys.
- β1 removes every key a file lacks (F-60). So a writer must include the other key even when its own copy of it is stale:
  - leave the key out, and a β1 Mac of the other OS deletes its layout;
  - include a stale copy, and that β1 Mac applies it silently;
  - mark it as a copy (`currentLayouts`/`copiedLayouts`), and β1 ignores the mark and drops it on its next write.
- An N Mac that took in or copied the other key can also write it back with a fresh date (RC-2) and list it as current (RC-5).

**Defects.**
- F-60 (S-13); SA-05 itself, layouts compared across OS versions (S-14).
- V0-#3 and V1-#6, F-60 for a missing file (S-19).
- V1-#5: a β1 Mac of the other OS triggers a question, and Use reverts to a stale copy (S-18).
- V3-#0 (blocker): a stale other-OS layout is taken in and listed as current again (S-15, S-16).
- V4 (blocker): the other-OS copy is replaced by the next same-OS writer's stale layout listed as current (S-17).
- R1 step G: setting up a folder across OS versions (S-14).

**Violates.** INV-5, INV-2, INV-6, INV-14, INV-7.

**Patches.** `currentLayouts` (SA05), `copiedLayouts` and the copy marking (R1), `passesOtherLayoutAsCopy` with `isBeforeLastSync` (R4), copy pass-through (R5), and the "copy over a missing file" rules (R6).

**Why it stays open (P-4, P-7).** Two authorities share one value and one write path, and the legacy peer neither keeps the marks nor tolerates a key being left out. Under β1 this cannot be solved (§5.4 C1). Among N Macs it reduces to RC-2 and RC-5 for the copy.

### RC-5 · Provenance inferred from content digests and from missing records ("synced" vs "taken in")

**Mechanism.** The code decides who wrote a value, whether it is old, and whether this Mac holds it by comparing **digests of whole values**: `baseLayoutDigest`, `keptLayoutDigest`, `recentLayouts` (8, then 64), `VersionSettingsDigest`, `isSame`. It often infers this from the **absence** of a record:
- no `currentLayouts` is read as "no layout";
- no kept record is read as "an old copy";
- a missing `seen` entry is read as "older";
- `noLayoutDigest` is read as "no current layout".

It also lumps together three facts as one, "synced":
- "seen in the file";
- "written by this Mac";
- "held on this Mac".

Equal digests can come from different histories: an old copy and a deliberate return, or A→B→A. Absence can mean "never existed" or "erased by β1 or a lost update".

**Defects.** "Recorded as synced without being taken in" appears five times:
- V0-#5 (S-29);
- V1-#0 (S-47);
- V2-#5, blocker (S-23);
- V3-#4 (S-31);
- V5 `383a5405`, blocker (S-41).

Others:
- V0-#0: a missing `currentLayouts` is read as no layout (S-20, S-22).
- V2-#3 (S-24) and V3-#6 (S-25): recognition of recent layouts.
- V3-#3: negative evidence in `isOldOwnLayout` (S-54).
- V4: a copy promoted to current (S-38, S-17).
- V5: Keep over a stale version listed again (S-51).

**Violates.** INV-2, INV-1, INV-10, INV-15.

**Patches.**
- `RecentLayoutDigests` 8 → 64 (R2/R3), then dropped (R5).
- `KeptLayoutDigest` (R3), the take-in rules (R2/R3), positive evidence by date (R4), `WriteRecord.keepsLayoutToTakeIn` (R5).
- `writesOwnLayoutAsCopy` with a `lastSynced != nil` gate (R6).

**Why it stays open (P-3, P-6).** Content equality cannot carry provenance, because identical bytes have opposite meanings (§5.2 pairs 1, 4, 5, 8, 9). Each digest record is one more piece of state, and every path (write, adopt, apply, take-in, keep, leave and join, launch, migration) has to keep it right. The next review then found the path that did not.

### RC-6 · Automatic and user changes mixed in one observed snapshot

**Mechanism.** On macOS 26, `ItemSections` is written by `saveSections`, which stores "the section of every cached item" as the bar looks at save time. That snapshot mixes four sources:
- the user's move;
- macOS's displacement, for example after a display change or wake;
- holzBar's placements of new items;
- whatever the reconciliation has not yet put back.

On macOS 27, `MacOS27Layout` holds both the user's moves (`setSection`) and holzBar's placements of new apps.

The user's intent is inferred afterwards:
- from a counter of user edits for the whole layout (`layoutEdits` vs `syncedLayoutEdits`);
- from what triggered the save (Command-click, drag, profile, import);
- from R4 on, from a snapshot of the bar taken before the arrangement.

A single "edited since the last sync" bit then lets this Mac write its **entire** layout, with all placements and displacements in it.

**Defects.**
- SA-05 itself (S-55).
- V0-#6 and V1-#3: Command-click without a move (S-56).
- V1-#4: a profile applied again (S-57).
- V0-#7: the migration seed (S-08).
- V2-#4a and V3-#2a: the first move of an unsaved item (S-58).
- V2-#4b and V3-#2b: displaced items saved as the user's (S-59).
- V2-#7: a reconciliation stores over a fresh save (S-60).
- Step AD: a move in the Layout pane during a restore (S-61).
- The β2 pause, edits not counted (S-62).
- Learned keys (S-63, F-02(c)).
- S-45: holzBar's placements are written as "this Mac's settings" on Keep.
- R4 residual: the 2 s settle window (S-67).

**Violates.** INV-4, INV-1, INV-7.

**Patches.**
- R1: `countsAsLayoutEdit` / `countsAsSectionSaveEdit` (changes only), the profile comparison, and the migration seed gated on `lastSynced`.
- R2: unsaved items recorded as holzBar's placements.
- R3: `ownPlacementsToStore`.
- R4: `sectionsBeforeArrangement` and `sectionsToSave`.

Still open: the settle window, items that appear mid-drag, and the pause edits.

**Why it stays open (P-5).** The unit of state is the observed bar, so intent has to be rebuilt from timing and modifier flags. R4 itself relies on `NSEvent.modifierFlags` and `pressedMouseButtons` at read time, and that was never run on a Mac. R3 noted that each fix in this area could count holzBar's Live Activity moves as the user's, or skip a real move that the restore then undoes. With one edit bit per layout, any wrong guess leads to a whole-layout overwrite.

### RC-7 · Peers on other versions (β1 in the field, branch builds, β2 pause)

**Mechanism.**
- β1 never reads before it writes, rewrites the file at every launch and 5 s after any change, applies silently with key removal, orders by clock, and drops all new metadata (§2.1).
- β2 runs no sync code and no edit counting, so a resumed Mac cannot tell what happened during the pause.
- Branch builds leave state that later builds read: R3 notes round-1/2 state, R5 notes the `lastWritten` of a round 4 build.

N has to stay safe against a peer whose writes look exactly like user changes and that removes every safety mark.

**Defects.**
- V0-#0, blocker: S-20, S-21, S-22.
- V0-#3 and V1-#6: S-19.
- V1-#5: S-18.
- V2-#3: S-24.
- V2-#5, blocker: S-23.
- V3-#6 and V4: S-25.
- R4/R5 residual: a β1 write over a deleted file (S-26).
- F-02(b)/(c) with a β1 peer: S-27.
- V0-#7: S-08.
- The pause: S-62.

**Violates.** INV-14, INV-1, INV-2, INV-5.

**Patches.** Pass-through of an unlisted own-OS layout plus a question (R1); old-copy recognition (R1–R3), later removed (R5); the copy key; and documented known issues ("update every Mac first").

**Why it stays open (P-8, §5.4).** As long as N writes the file β1 reads, β1 can delete or revert whatever N writes, and erase every mark N relies on. As long as N reads β1's writes, it cannot tell a β1 user's change from a β1 rewrite (§5.2 pair 1).

### RC-8 · Questions and answers cover the whole state

**Mechanism.** The question offers "Use Settings from Sync Folder", "Keep This Mac's Settings", and "Later" or "Cancel". The answer applies to the **whole** state. The differences that trigger the question are partial: user settings, this Mac's layout, the other OS's layout, learned keys, holzBar's placements. The sheet does not show what differs. To keep an answer from losing what the user did not see, each round redefined what Keep means:
- keep the other Mac's untouched layout and take it in (R1);
- only over the answered version, by date (R2), then by content (R3);
- take in only the layout (R2 `takeInLayout`);
- Keep for a re-joining Mac (R5);
- Keep over a stale version keeps this Mac's layout (R6);
- Keep while the file is missing writes a copy (R6).

**Defects.**
- S-45 (V0-#2), S-46 (V1-#2), S-47 (V1-#0), S-48 (V2-#0), S-49 (V1-#7), S-33 (V2-#1).
- S-50 (V4), S-51 and S-52 (V5 blockers: lost whichever button), S-53 (V5).

**Violates.** INV-8, INV-1, INV-2.

**Why it stays open (P-6).** One button press stands for several decisions, so it needs exceptions. Each exception creates a new state, such as "kept, not taken in", and every other path has to respect it (§5.3 rows 1, 3, 4, 8, 19).

### RC-9 · Async and UI races, and bookkeeping that is not atomic

**Mechanism.**
- The section save is deferred by 1.5 s.
- The reconciliation reads early and stores late.
- An exchange runs asynchronously: read, decide, write, then record on the main actor. A cancelled task drops the record after the file was already written.
- The waiting version lives only in memory.
- The modal alert used to block, and later stopped blocking, the defaults observer and the push debouncer.
- The settle window after a wake or display change is 2 s.

**Defects.**
- F-02(c), Later followed by a push (S-04).
- After the F-14 fix, a push while the notice is open (S-05).
- V0-#4: Restart within 1.5 s of a drag (S-64).
- R2 issue 13: an edit made between the request and the record (S-65).
- R3 `f5895cb6`: a hint built from a stale side (S-66).
- V3-#3: a record lost after a write (S-54).
- V3-#1a' and V4: the waiting version is dropped, or lost on relaunch (S-35, S-36).
- V2-#7: a reconciliation stores over a fresh save (S-60).
- The settle window (S-67).

**Violates.** INV-10, INV-9, INV-1, INV-4.

**Why it stays open (P-6).** The local state is spread over about 16 keys and in-memory fields, and they are updated after the shared write, not with it. No log or journal makes a half-done exchange recoverable.

### RC-10 · Identity, I/O and content robustness

**Mechanism and defects.**
- F-38: the device ID sits in the preferences, so a copied Mac becomes "this Mac" (S-06).
- F-15: coordinated reads and writes on the main thread, and the launch read waiting for dataless files (S-09).
- F-18: holzBar mounts the share itself (S-10).
- F-61: the custom icon is stored twice and base64-encoded twice, so the file passes 1 MiB and other Macs ignore everything; V0-#1 adds that they also overwrite it (S-11).
- F-59: one bad entry empties a whole dictionary or JSON setting, and the loss is written back and synced (S-12).

**Violates.** INV-11, INV-12, INV-13, INV-1.

**Status.**
- F-38, F-15, F-18 and F-60 are fixed in the SA05 code.
- F-61 is open on SA05. The write-side check exists only on R1 (`b3da7f87`).
- F-59 is open: the remediation log says it is not in the chosen scope.

These are local engineering fixes. They do not depend on the replication model, but any redesign must keep them.

### RC-11 · Verification that could not see the defects

**Mechanism.**
- `swift test` builds only `holzBar/Core`. The glue that records state, dispatches outcomes and builds the file stayed in the app target until R6, and the R6 scenario Macs **copy** that glue.
- Mutation testing shows that the rules as written are tested. It cannot show that rules are missing.
- No two-Mac step (A–AP) was ever run on real Macs. The sync-1 decision left the human check open.
- The docs claimed fixed behaviour that the next review disproved: V3-#0 ("never taken in"), V4 `304412d2` (the waiting version survives) and V5 `34786f18` (stale `fileToWrite` docs).

**Defects.** V0-#8 (a tautological race test; mutations of the layout state machine undetected), V1-#8, V2-#8, V3-#5 and V5 `a9fa5b50` (glue untested), and V4 `21f381da` (guards untested).

**Violates.** INV-16.

**Why it stays open.** Every review found its defects by building new adversarial sequences of events: restores, deletions, a third Mac, clock steps, β1 write-backs, re-joins. The test suite had no generator for such sequences and no invariant oracles. It tested the cases that earlier reviews had found.

---

## 5. Why the patches kept regressing

### 5.1 Ten design properties that make the design impossible to patch

All six rounds kept the same decision shape: `decide(trigger, Local, File)`. `Local` is a fixed set of summaries (digests, dates, counters, flags), and `File` is **one** version of **one** shared file.

To decide correctly, a Mac needs four facts for every **unit** (a setting key, an OS layout, or an item inside a layout) and every other Mac:
- (a) whether the file's value is newer (a fast-forward);
- (b) whether it is older (stale);
- (c) whether it is concurrent (a conflict);
- (d) whether a user wrote it, or holzBar or macOS did.

That is a partial order over the history of writes to each unit, plus who wrote each one. Every summary the design kept is a lossy projection of that history:

| Summary used | What it loses |
|---|---|
| `modified` / `lastSynced`, a total order across Macs' clocks | Skew, clock steps, restores; second precision |
| Digests of the whole state or whole layout (equality only) | Order; and identical content from different histories |
| One base per Mac (the last sync) | Per-unit ancestry. It cannot say "I hold B's change to `u1` but not to `u2`" (V5 `383a5405`: "settings hold the write" ≠ "layout taken in") |
| One layout-edit counter per OS layout | Which items the user moved |
| `seen` (R5/R6), each Mac's newest write date | It is a version vector, but on wall clocks, per Mac rather than per unit, capped at 64 entries, absent from β1 files, and erased by every β1 write |

Each review found a pair of histories with the same summary that need different actions. Each fix added a field to tell that pair apart. The new field typically had one of three problems:
- (i) it used another lossy proxy, mostly dates;
- (ii) not every path kept it up to date;
- (iii) β1 destroyed it.

Restores, deletions, more Macs and legacy writers can produce new such pairs without limit. So the sequence of patches cannot converge until the causal history itself is recorded per unit. The ten properties:

- **P-1 · One shared file, replaced as a whole by every writer, with no compare-and-swap.** Correctness depends on every writer's view being complete (RC-1). Mixing a third Mac or a lost file into the history creates a new lost-update path each time: V4, V5 and S-39–S-41.
- **P-2 · No causal metadata. Order and identity come from wall clocks.** Even the late addition (`seen`) is clock-based. It is also per Mac rather than per unit, so it cannot express "B's settings change is held but B's layout is not" (S-41). Clock arithmetic produced its own defects: `Version.syncedDate` for future dates, `writeStamp` for backward steps, and whole-second comparisons (RC-2).
- **P-3 · Provenance from digest equality, and from missing records.** The ABA problem and the old copy vs. deliberate return are impossible to decide by content alone. "No record" is read as a positive claim (old copy, absent, older). Every lost record, whether from a cancelled task, a quit, a β1 write or a missing key, then becomes a wrong positive decision (RC-5).
- **P-4 · Two authorities share one write path, and a legacy reader deletes missing keys.** Every writer must re-emit a value it does not own and cannot vouch for. The copy marking is metadata that β1 strips (RC-4).
- **P-5 · The layout state is a snapshot of the observed bar, with one edit bit per OS layout.** The user's intent is reconstructed afterwards from timing, modifier flags and before/after comparisons. Each heuristic has a counterexample in the other direction (R3 non-fix notes), and a wrong guess overwrites the whole layout (RC-6).
- **P-6 · The decision is an ordered list of rules over a combined input space, and the bookkeeping is spread out and not atomic.**
  - The inputs combine into hundreds of cases: 3 triggers × 4 file states × version flags (own, newer, before last sync, misses last write, own/other layout listed/copied/unlisted/absent) × local flags (joining, forces write, edits layout, pending, postponed, keeps over, kept record, layout taken in).
  - The order of the branches matters. `66bb63a0` notes: "`holdsOlderLayoutToJoin` is checked before `keepsThisMac`". A new branch changes the outcome of neighbouring cases, as R5 `66bb63a0` did by making the R6 blocker `f238cabe` reachable.
  - About 16 persisted keys are updated by eight paths: write, adopt, apply, take-in, keep, leave/join, launch and migrate. Each new concept, such as "kept, not taken in", needed every path to respect it (RC-5, RC-8, RC-9).
- **P-7 · Silent outcomes exist on many paths.** Silent apply at launch, adopt, taking in the other OS's layout, and β1's own apply all exist. So a wrong classification means silent data loss, not an extra question. The policy allows zero silent loss. With the ambiguous inputs of §5.2, no classification is always right. The patches therefore turned silent losses into **stalls** (R5/R6: arrangements "wait as a copy until the next rearrangement", S-69) or into **extra questions** (R5/R6 known risks, S-70). Both were accepted as residual risks rather than fixed.
- **P-8 · The legacy peer shares the file, and the early rounds froze the constraints.**
  - β1 cannot be changed, and it erases and overrides everything N relies on (§5.4).
  - R1–R3 worked under "no file-format change, no new strings, compatible with β1". R3 rejected a parent record explicitly because it "changes the file format, beta 1 compatibility and every write path".
  - When R4 allowed a format change, it went in step by step: `basedOn` (a date), then `seen` (dates per Mac). The clock and β1 weaknesses stayed.
- **P-9 · Verification cannot see the failure space (RC-11).** The glue was outside the test package until R6, and the scenario tests copy it. There are no tests over generated event sequences with invariant oracles, and no real two-Mac run. Every round's gates passed: mutation checks were "all caught" each time, yet the next review found blockers.
- **P-10 · The environment is not a linearisable register.** File providers deliver late, deliver dataless files, restore older versions and delete files. The code coordinates file access only locally. A design that assumes "the file is the latest truth" fails on every provider event (RC-3).

### 5.2 Histories that look the same but need opposite outcomes (the core reason no rule set converges)

| # | History H1 → required outcome | History H2 → required outcome | What the decision sees in both | Scenarios |
|---|---|---|---|---|
| 1 | A β1 Mac writes back an old copy of L1 → keep this Mac's newer arrangement | A β1 user goes back to exactly L1 → keep the β1 user's arrangement | An unlisted own-OS layout equal to a layout this Mac synced before | S-24 / S-25 |
| 2 | The file was deleted after B's unseen write → do not revert B | A new folder was just set up → publish without asking | No file; this Mac has changes | S-34 / S-44 |
| 3 | B's clock lags, and the version is a new change → ask or apply | A sync app restored an old version, which is stale → never take it in or list it | Another Mac's version, dated before this Mac's last sync | S-28, S-31 / S-16, S-51 |
| 4 | β1 wrote the file, so the layout may be the β1 user's new arrangement → protect it | The file has no current layout, so there is nothing to protect | No `currentLayouts` entry for the own key | S-20, S-22 |
| 5 | The kept-layout record was lost (cancelled task, quit) → take the layout in | The version really is an old copy → overwrite allowed | An own version with a layout that matches neither the base nor any record | S-54 |
| 6 | The user moved items → count the move | macOS displaced the items (display change, wake) → do not count | The same observed bar | S-59 |
| 7 | The user moved an item that was never saved → count the move | holzBar or macOS placed the item → do not count | An item without a saved section, now in some section | S-58 / S-55 |
| 8 | This Mac applied B's change, so it holds B's layout → B's write is "held" | This Mac adopted B's version but kept its own layout → the layout is not held | `seen` records B's write in both cases | S-41 |
| 9 | Nothing changed | A change and its revert (A→B→A), or a clock set back between them | Equal digests, or equal or earlier dates | S-32 |

Any `decide` over these inputs is wrong for one column of every row. A patch can only choose which column fails, or ask a question in both, which breaks INV-7 and the fast-forward case S-68. The only real fix is to **record the distinguishing fact**: per-unit causal stamps, who wrote each change and whether a user did, and what a Mac has taken in versus merely seen.

### 5.3 Defects caused or left half fixed by the previous round

| # | Finding | Sev. | Caused or left half fixed by | How |
|---|---|---|---|---|
| 1 | V1-#0: a re-join records the kept layout as synced without applying it | major | `a43c23f6` (R1) | Introduced "Keep keeps the other Mac's untouched layout, taken in at restart", a new state that the join path did not know |
| 2 | V1-#5: a β1 Mac of the other OS triggers the question; Use reverts to a stale copy | minor | `4ddb0e98` (R1) | The new question about an unlisted own-OS layout also fires for an old copy |
| 3 | V1-#7: after a write that keeps another Mac's layout, pushes stop | minor | `a43c23f6` (R1) | Set `pending` for this Mac's own version |
| 4 | V2-#0: a re-join after a drag writes over the kept layout | major | `9cc17194` (R2) | Half fix |
| 5 | V2-#1: Keep over a third Mac's version dated at or before the answered one | major | `92302f58` (R2) | The answered version was identified by date |
| 6 | V2-#3: stale-copy recognition limited to 8 layouts | minor | `a940db58` (R2) | Recognition by a fixed list of digests |
| 7 | V2-#4: the first move of an unsaved item does not count; a displaced item does | minor | `92d34d08` (R2) | Only items with a saved section count |
| 8 | V2-#5: a kept layout is remembered as recent, so holzBar's layout replaces the arrangement (blocker) | blocker | `a940db58` + `a43c23f6` | Two new records interacting |
| 9 | V2-#7: a reconciliation stores an old section over a fresh save | minor | `92d34d08` (R2) | The reconciliation now stores unsaved sections |
| 10 | V3-#0: a stale other-OS layout is taken in and listed as current again | blocker | `bf742362` (R3) | Half fix: the own layout only |
| 11 | V3-#3: `isOldOwnLayout` relies on negative evidence | minor | `b9e981e2` / `bf742362` (R3) | A new kept record, and an old-copy rule that relies on it |
| 12 | V3-#6: recognition of 64 layouts reverts a β1 user's return | minor | `ab28fc08` (R3) | Widened 8 → 64 |
| 13 | V4: a copy over a missing file is promoted to current on the next write | blocker | `226db335` (R4) | Half fix (variant b) |
| 14 | V4: a parent record by date only hides the missing write; a descendant turns the question into Restart | blocker | `d0488e5e` (R4) | `basedOn` as a single date |
| 15 | V4: Keep for a re-joining Mac brings the same question back | major | `dc5bd356` (R4) | A new join branch placed before Keep |
| 16 | V4: an unlisted layout matching a recent one is replaced on any write | minor | `a940db58` / `ab28fc08` | The recognition list |
| 17 | V4: the release notes claim a waiting version survives file loss | minor | `226db335` (R4) | In memory only |
| 18 | V4: the `passesOtherAsCopy` guards are untested | minor | `a42f8c59` (R4) | New guards |
| 19 | V5: Keep over a version that is not newer lists its stale layout on every Mac | blocker | `66bb63a0` (R5), on top of `a43c23f6` | Made the case reachable for re-joining Macs |
| 20 | V5: a third Mac applies a version without a write its settings hold | major | `815726d9` (R5) | `missesLastWrite` checked only this Mac's own entry |
| 21 | V5: the `seen` record claims a write whose layout was never taken in | blocker | `815726d9` (R5) | Writes recorded per Mac, not per unit |
| 22 | V5: Keep while the file is missing does not record the answered version | minor | `815726d9` + `226db335` | Two new rules interacting |
| 23 | V5: a clock set back, or two writes in one second, hides a missing write | minor | `815726d9` (R5) | Write identity is a wall-clock date |
| 24 | V5: the file the app writes, including `seen`, is untested glue | minor | `815726d9` (R5) | A new key built in the app |
| 25 | V5: the `fileToWrite` docs are stale | minor | R5 changes | The docs drifted |

So 25 of the about 41 findings in V1–V5 trace back to the previous round. The others were cases that already existed and that a new adversarial sequence uncovered: the missing file, restores, clock skew, β1 write-backs. Both kinds come from P-1 to P-8.

### 5.4 Constraint conflicts: outcomes no rule can deliver while β1 shares `Settings.plist`

These have to be decided explicitly in the redesign; more patches cannot resolve them.

- **C1 · Missing file plus β1's key removal plus per-OS keys** (S-19). Every option for an N Mac rebuilding the file fails a β1 Mac of the other macOS version:
  - include its copy of the other OS's layout, and a stale copy is applied silently;
  - leave it out, and β1 deletes that layout;
  - mark it as a copy, and β1 ignores the mark.
  
  The way out is to not write the file β1 applies, or to accept a documented limitation the user can see.
- **C2 · β1 drops metadata** (S-25, S-26, S-20). Every β1 write, which happens at every launch and 5 s after any automatic change, produces a version without causal metadata. Under the policy, N must then either ask about every difference in such a version (a storm of questions, against INV-7) or pass it on without listing it (a stall, against INV-15). A β1 user's change and a β1 rewrite cannot be told apart (§5.2 pair 1).
- **C3 · β1 applies silently at launch.** Whatever an N Mac writes into the legacy file, β1 applies at its next launch with key removal. To be safe, every N write would need the newest user value of **every** key, including β1 Macs' own latest changes that N has not seen yet. Without compare-and-swap that cannot be guaranteed.
- **C4 · β1 orders by the clock.** β1 compares N's write dates with its own `lastSynced`, with 1 h of skew allowed. N cannot control what β1 does when the clocks are skewed.
- **C5 · A single file without compare-and-swap.** Concurrent writes go through the provider's last-writer-wins, or produce conflict copies that holzBar never reads. A design where several Macs write the same file has a lost-update window by construction.

### 5.5 What follows for the redesign (non-binding; the design is for other documents)

A design passes §6 by construction only if it removes the ambiguities in §5.2 instead of guessing at them:
- **Each Mac writes only its own file or record.** No Mac ever rewrites another Mac's data. This removes RC-1 and C5.
- **Causal stamps per unit, independent of clocks.** For example per-Mac counters or a version vector per key and per layout item, or parent hashes. This removes RC-2 and RC-5.
- **Changes recorded with who made them and how.** Each change carries the device, whether a user or holzBar made it, and its stamp, at the granularity of a setting key or layout item, not a whole layout. This removes RC-5, RC-6 and RC-8.
- **Layout recorded as the user's actions, not as bar snapshots.** A move or a profile apply is an event; placements and displacements are not. This narrows RC-6 to capturing the event.
- **An explicit boundary with older builds.** The new format lives in a different file or folder that β1 never reads. Legacy `Settings.plist` is input only (or one-way, with stated rules), and the limits are documented. This addresses RC-7 and C1–C4.
- **A durable local journal.** It holds the remote versions waiting for the user, the unsent local changes, and atomic state transitions. This removes RC-9.
- **Optional, the maintainer's call (todo, 2026-10-06):** stop syncing the menu bar arrangement. That removes RC-4 to RC-6 from the sync surface at the cost of the feature.

---

## 6. Regression catalogue (every scenario must pass in N)

**Fields of each scenario.**
- **Setup:** the Macs (A, B, C, D), their macOS version (26 or 27) and their build (β1, β2 or N). Historical wrong outcomes name the build that showed them.
- **Steps:** "Show on hover" stands for any non-layout user setting, and "Command-drag" for any user rearrangement.
- **Wrong:** what was observed or confirmed, and in which build.
- **Must:** the acceptance criterion, which states the policy and not an implementation.
- **Src:** the finding, commit or manual step.

**Unless a scenario says otherwise:**
- All Macs share one sync folder.
- "Must" always includes INV-1 and INV-2 for every Mac involved: nothing silently lost or brought back.
- "Must" also includes INV-7: no question beyond the one named.

**[CONFLICT]** marks a scenario that cannot pass while N writes the file β1 applies (§5.4). The redesign must pass it through its β1 boundary, or name it as a limitation the user can see.

### G1 · Joining, identity, routine writes

**S-01 · A second Mac joins with its defaults** (F-02a, high; RC-1, RC-7)
- Setup: A (any OS) has synced for weeks. B is a fresh install.
- Steps: on B, Settings › Advanced › Sync › Turn On…, and choose A's folder.
- Wrong (β1): B writes its defaults over the file without reading it. A applies them through the alert, or silently at its next launch with key removal. A's configuration is gone on both Macs, and no copy is left.
- Must:
  - B reads before it writes.
  - If B's user settings are defaults or equal to the folder's, B adopts silently.
  - If they differ, B asks: Use / Keep / Cancel.
  - A changes only if B's user chose Keep.

**S-02 · A relaunch with nothing changed** (F-02b, high; RC-1)
- Setup: A and B have synced, any OS.
- Steps: quit and reopen A.
- Wrong (β1): A rewrites the file with a fresh date at every launch. B offers a restart for identical settings, and restarting B rewrites the file and prompts A in turn (ping-pong).
- Must: no write without a change of content, and no hint anywhere.

**S-03 · A Mac behind writes over a newer version** (F-02b, high; RC-1, RC-3)
- Setup: A and B, any OS.
- Steps:
  1. A changes a setting and writes.
  2. Before B's sync app delivers that version, B launches or changes something.
- Wrong (β1): B writes its older state with a newer date, and A then applies it silently at launch.
- Must:
  - B never replaces a version it has not read.
  - If B cannot read the current version (dataless, unreadable), it waits.
  - A's change survives. If both Macs changed the same setting, holzBar asks.

**S-04 · Later, followed by any push** (F-02c, high; RC-1, RC-6, RC-9)
- Setup: A and B, any OS.
- Steps:
  1. B changes a setting; A shows the hint.
  2. On A, choose Later.
  3. A pushes: after a user change, or after holzBar writes `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners` or `ItemSections` by itself.
- Wrong (β1): A's push overwrites B's version and sets `lastSynced = now`. A never applies B's change, and B loses it at its next launch.
- Must:
  - B's version keeps waiting (INV-9), and automatic writes never push over it.
  - A user change on A after Later turns into a question, since both Macs changed something.

**S-05 · The notice is open while pushes run** (modal-alerts decision (4); RC-9, RC-1)
- Setup: A and B on N.
- Steps:
  1. B writes; A shows the notice or sheet.
  2. While it is open, the main actor keeps running (after the F-14 fix), and any defaults change fires the debouncer.
- Wrong (risk named in the decision, before the fix): A pushes its own settings over B's newer file. The file is then "from this Mac", so Restart applies nothing. B's change is lost silently.
- Must: no push while a remote version waits for the user. Restart applies exactly the version that was offered.

**S-06 · A Mac set up by Migration Assistant, a restore or a clone** (F-38, medium; RC-10)
- Setup: iMac A. MacBook B is set up from A by Migration Assistant. Both sync.
- Wrong (β1): both Macs share the same `SettingsSyncDeviceID`. Each takes the other's files for its own: nothing is applied, and the last writer wins.
- Must:
  - B gets its own identity: a salted hardware-hash mismatch gives a new ID and clears the sync state. The hash never leaves the Mac.
  - B then behaves as a joining Mac (S-01, S-07).

**S-07 · Joining without a conflict** (sync-1 test list; must not ask)
- Cases:
  - joining with no file: write, no question;
  - joining with this Mac's own file: adopt;
  - joining with a file whose user settings equal this Mac's: adopt;
  - a re-identified Mac (S-06) with equal settings.
- Wrong (a risk in every round): a question, or an unnecessary write that sends hints to the other Macs.
- Must: no question, and no hint on any Mac.

**S-08 · Sync was on but never reached the folder** (V0-#7, minor; RC-6, RC-7)
- Setup: A on β1, with sync on but iCloud Drive off (or the share not mounted). A never synced. Its layout is hand-made. A updates to the build under test. Later the folder becomes reachable, with user settings equal to A's.
- Wrong (SA05): the migration seeds 0 layout edits because sync is on. The join then takes the folder's layout silently over the user's arrangement.
- Must: a layout on a Mac that never completed a sync counts as the user's. holzBar asks if it differs. (R1 `7255b104` seeds 0 only when `lastSynced` exists.)

### G2 · Infrastructure

**S-09 · An online-only file at login** (F-15, medium; RC-10, RC-3)
- Setup: A uses OneDrive, or iCloud Drive with Optimize Storage. B wrote the file, which is dataless on A.
- Steps: log in to A without network.
- Wrong (β1):
  - `AppDelegate.init` blocks on the coordinated read, with no menu bar icon until the provider gives up.
  - Later, a hung provider stalls the main thread at every push. On macOS 27, every click then waits behind the HID tap.
- Must:
  - The launch waits about 1 s at most, and never reads a dataless or not-yet-current file.
  - The check runs later in the background.
  - No coordinated I/O on the main thread.

**S-10 · The network share is not mounted** (F-18, medium; RC-10)
- Setup: A syncs through an SMB folder that is not mounted.
- Wrong (β1): holzBar mounts the share itself and blocks while the mount times out.
- Must: never mount. Show "The sync folder cannot be found", and resume once the user mounts the share.

**S-11 · A settings file over the size limit** (F-61 low; V0-#1 blocker; RC-10, RC-1, RC-3)
- Setup: A and B on the build under test. A variant: A on β1.
- Steps:
  1. On A, set a custom holzBar icon of about 400–800 KB. Icons imported from Ice keep up to 8 MiB raw. The icon is stored twice and base64-encoded, so it takes about 3.5× its size in the XML file.
  2. A writes a file over 1 MiB.
  3. B changes any setting.
- Wrong:
  - β1: B ignores every synced setting while the UI says it syncs; the log only says `tooLarge`.
  - SA05: B treats the file as unusable and writes over it without asking. A, without changes, then sees B's newer version and applies it silently at launch. A's unsynced changes and its layout are reverted.
- Must:
  - The writer refuses content over the limit and says so in the sync UI.
  - A reader never writes over a file it refused. That is a blocked state, not a missing file.
  - An oversize file written by β1 is left alone.

**S-12 · A malformed entry in a synced setting** (F-59, low, open; RC-10)
- Steps: an imported or synced file holds `MacOS27Layout` with one value of `1.5` or `"1"`. Variants: a `Hotkeys` value that is not `Data`, or profile or group JSON that does not decode.
- Wrong (all builds):
  - The whole dictionary is dropped, so on macOS 27 every app becomes visible. The user's next move writes a layout holding only that app, and it syncs to every Mac.
  - All hotkeys are lost, and lost again at every launch.
- Must: validate each entry. A bad entry is skipped and never written back as a loss, and sync never spreads the loss to other Macs.

### G3 · Two macOS versions (`ItemSections` and `MacOS27Layout`)

**S-13 · Applying a file of the other macOS version** (F-60, low; RC-4)
- Setup: A runs macOS 27. B runs macOS 26 and was the only Mac writing the folder.
- Steps: A applies B's file.
- Wrong (β1):
  - Applying removes the keys B never had: `MacOS27Layout`, `MacOS27LayoutSeeded`, `KnownApplications27`. A reseeds its layout, which may come out empty.
  - In the other direction, the macOS 26 Mac loses `ItemSections`.
- Must: applying never removes a key the sender lacked. Each Mac keeps the layout of its own macOS version.

**S-14 · macOS 26 and 27 with equal settings** (SA-05; step G; must not ask)
- Setup: A runs macOS 26 and B runs macOS 27, both on N, with equal user settings.
- Steps:
  1. On B, choose an empty folder with Change…; B writes, with its copy of `ItemSections` marked as a copy.
  2. A joins, then Command-drags.
- Wrong (before SA-05): the two macOS versions' layouts were compared, which led to questions; placements on either Mac caused hints.
- Must:
  - No question about layouts at any point.
  - A's `ItemSections` becomes the current one for macOS 26.
  - B's `MacOS27Layout` stays as it is.

**S-15 · A stale other-OS layout from a restored own version** (V3-#0, blocker; step X; RC-4, RC-2, RC-3)
- Setup: A runs macOS 26 on N. C runs macOS 27 on N.
- Steps:
  1. A changes a setting and writes V1, which holds C's layout L_C1 as current. Copy `Settings.plist` aside.
  2. On C, Command-drag (L_C2). C writes, and A reads it.
  3. Put the copy back, as a sync app restoring V1 would.
  4. Quit and reopen A, then change "Show on hover" on A.
  5. On C, restart through the hint.
- Wrong (R3):
  - A takes the stale L_C1 into its `MacOS27Layout` copy and writes it back listed as current, with a fresh date.
  - C has no changes and applies it, silently at launch or behind a plain Restart. C's arrangement L_C2 is reverted.
- Must:
  - C keeps L_C2 and gets A's setting.
  - A never takes in or lists again an other-OS layout that a newer version has replaced.

**S-16 · A stale other-OS layout from another Mac's older version** (V3-#0 variant 2; RC-4, RC-2)
- Setup: as S-15, but the stale V1 is an earlier upload by a third Mac B that the sync app keeps or delivers again. It is "not newer" than A's last sync.
- Wrong (R3): same outcome as S-15.
- Must: same as S-15.

**S-17 · Three Macs: the other-OS copy promoted to current** (V4, blocker; step AF; RC-4, RC-5)
- Setup: A runs macOS 26. C and D run macOS 27. All on N.
- Steps:
  1. Turn sync off on D.
  2. On C, Command-drag. Copy `Settings.plist` aside before C writes, and put it back after A has read C's file.
  3. On A, change a setting. `MacOS27Layout` now sits under `copiedLayouts`.
  4. Turn sync on again on D, and change a setting there.
  5. On C, restart through the hint.
- Variants:
  - a copy demoted by date after A's Keep;
  - a copy passed on from an older version;
  - a copy inserted over a missing file.
- Wrong (R4): D's write lists its own older layout as current over the copy. C applies it silently and loses its arrangement.
- Must:
  - C keeps its arrangement.
  - D never lists its unchanged layout over C's newer arrangement.
  - If D's user rearranges as well, holzBar asks.

**S-18 · A β1 Mac of the other OS writes an old copy back** (V1-#5, minor; step O; RC-4, RC-7, RC-5)
- Setup: A runs macOS 27 on N. C runs macOS 26 on β1.
- Steps:
  1. A arranges L1 and writes. Quit and reopen C, which now holds L1 as its `MacOS27Layout` copy.
  2. A arranges L2.
  3. On C, change any setting. β1 rewrites the file with L1, not listed.
  4. On A, Command-drag.
- Wrong (R1): A asks about its own old layout, and Use Settings from Sync Folder reverts A to L1.
- Must:
  - No question, and no revert to L1. The file ends with A's layout current.
  - C never loses its `ItemSections` in the process.

**S-19 · The file is lost while a β1 Mac of the other OS syncs** (V0-#3, V1-#6, minor; steps H, O.5; RC-4, RC-7) [CONFLICT C1]
- Setup: A runs macOS 27 on N, with an old copy of `ItemSections` or none. C runs macOS 26 on β1.
- Steps:
  1. `Settings.plist` is deleted or damaged, or the folder is recreated or changed with Change….
  2. A changes a setting and writes.
  3. C relaunches.
- Wrong (SA05 to R6, documented only):
  - Without a copy, the file lacks `ItemSections`, and β1 deletes C's at launch.
  - With an old copy, C applies it, and its arrangement is reverted.
- Must: C's arrangement survives. No content A can put into the legacy file achieves that (§5.4 C1).

### G4 · Same macOS version with a β1 Mac

**S-20 · A β1 drag overwritten by an N Mac's non-layout write** (V0-#0, blocker; step A; RC-1, RC-7, RC-5)
- Setup: A runs macOS 26 on N and has synced. B runs macOS 26 on β1. Two macOS 27 Macs behave the same.
- Steps:
  1. On B, Command-drag an item (L_B). β1 writes the whole file, without `currentLayouts`.
  2. A checks the file.
  3. On A, change "Show on hover"; A writes.
  4. Quit and reopen B.
- Wrong (SA05):
  - A reads the unlisted `ItemSections` as no layout. It adopts the version and records it as synced without seeing B's drag.
  - A's write lists its own older L_A as current.
  - β1 B applies that silently at launch, and B's drag is reverted.
- Must:
  - B keeps L_B.
  - A's non-layout write never replaces a same-OS layout that A did not arrange.
  - A takes in L_B, or leaves it alone.
  - A drag on A that would replace L_B asks first.

**S-21 · A β1 Mac updated to N adopts the other Mac's layout** (V0-#0 variant; RC-7, RC-6)
- Steps: continue S-20, but update B to the build under test instead of relaunching it on β1.
- Wrong (SA05): the migration seeds 0 edits because B syncs. B joins, `holdsLocalSettings` holds because no layout is compared, and the adopt branch applies L_A silently over B's drag.
- Must: B's arrangement survives. It counts as the user's, and holzBar asks if it differs.

**S-22 · An N Mac with its own arrangement joins a folder written by β1** (V0-#0 joining variant; step B; RC-7, RC-5)
- Setup: B runs macOS 26 on β1 and wrote the folder with L_B. C runs macOS 26 on N and has its own arrangement.
- Steps: turn sync on on C.
- Wrong (SA05): the version lists no layout, so `keepsLayout` holds, and C writes its layout over L_B without asking.
- Must: C asks, because both are user arrangements and they differ.

**S-23 · A kept arrangement written back by β1** (V2-#5, blocker; step T; RC-5, RC-7, RC-8)
- Setup: A and B on N, C on β1, all on the same macOS version.
- Steps:
  1. On B, Command-drag and change "Show on hover". On A, change it the other way. On A, choose Choose Settings… → Keep This Mac's Settings: A keeps B's arrangement, and Restart is pending.
  2. Quit and reopen C, which applies the file. Change a setting on C: β1 writes the kept layout back, not listed.
  3. On A, change "Show on hover".
  4. Quit and reopen B.
- Wrong (R2):
  - A had remembered the kept layout, which it never took in, as recently synced. It therefore read C's write-back as its own old copy.
  - A wrote its own layout, with holzBar's placements, as current. B applied it silently and lost its arrangement.
- Must: B keeps its arrangement, and a drag on A asks.

**S-24 · β1 keeps writing an old copy while N rearranges** (V2-#3, minor; step U; RC-5, RC-7)
- Setup: A runs macOS 27 on N. C runs macOS 26 on β1.
- Steps:
  1. A arranges and writes. Quit and reopen C.
  2. On A, Command-drag ten times or more, letting each write.
  3. On C, change a setting: β1 writes A's old copy back.
  4. On A, Command-drag.
- Wrong (R2): the list of known old copies held only 8 digests, so A asked about its own old layout.
- Must:
  - No question; A's layout is current.
  - C's `ItemSections` stays as it is.

**S-25 · A β1 user goes back to an earlier arrangement** (V3-#6, then V4 `14f77476`, minor; step AI; RC-5, RC-7) [§5.2 pair 1, CONFLICT C2]
- Setup: A on N and C on β1, same macOS version. A synced L1, then L2, and C applied L2.
- Steps:
  1. On C, move the items back to exactly L1. C writes the file, with the layout not listed.
  2. On A, change "Show on hover". Quit and reopen C.
  3. On A, Command-drag.
- Wrong:
  - R3/R4: the 64-digest recognition read L1 as A's own old copy, and A's non-layout write put L2 back over it. C's deliberate return was reverted silently.
  - From R5 on: A passes L1 on until its next drag, which then replaces C's arrangement without a question.
- Must:
  - C's return is never reverted silently.
  - If A's user then rearranges, both Macs changed the layout, so holzBar asks. Otherwise the design must make the case decidable.

**S-26 · A β1 write over a deleted or damaged file** (R4/R5 residual, documented; RC-7, RC-3) [CONFLICT C2]
- Setup: A and B on N, C on β1, same macOS version.
- Steps:
  1. On B, change a setting. Before the others read it, delete `Settings.plist`.
  2. On C, change a setting: β1 writes a file without B's change and without any `seen` record.
  3. A and B check.
- Wrong (R4–R6): C's file carries no causal metadata. B has no changes and takes it without asking, so B's change is reverted silently.
- Must: B's change is not reverted silently. This needs an explicit rule for versions without metadata (§5.4 C2).

**S-27 · β1 rewrites at launch and after automatic changes, in a mixed set of Macs** (derived from F-02(b)/(c) with a β1 peer; not reproduced separately in V0–V5; RC-7, RC-6)
- Setup: A and B on N. C on β1.
- Steps: C relaunches, so β1 rewrites the file with a fresh date. C learns a new item, which is an automatic write, and pushes 5 s later.
- Wrong (risk):
  - N Macs show a hint or a question for content that did not change.
  - Or they treat C's automatic rewrite as C's user change and let it replace their own newer user changes.
- Must:
  - N Macs show nothing for a version with equal content.
  - C's rewrite never displaces A's or B's newer user changes in what N keeps.

### G5 · Clocks and dates

**S-28 · A change dated before the last sync** (V1-#1, minor; step J; RC-2, RC-1)
- Setup: A and B on N, same macOS version. B's clock is about 10 minutes behind.
- Steps:
  1. A changes a setting, and B applies it.
  2. B changes "Show on hover"; the change is dated before A's last sync.
  3. A changes something.
- Wrong (SA05/R1): A takes B's version for "not newer", ignores it, and its next write overwrites B's change silently.
- Must: A treats B's change as concurrent, whatever the dates say. It asks if A also changed something, and otherwise applies it.

**S-29 · An older version's layout recorded as synced, then overwritten by a drag** (V0-#5, minor; RC-2, RC-5)
- Setup: A and B on N. B's version is dated at or before A's `lastSynced` (a lagging clock), or more than 1 h ahead.
- Steps:
  1. B Command-drags (L2) and writes.
  2. A changes only a user setting and writes. The file keeps L2, and A records L2 as synced while it still shows L1.
  3. A Command-drags.
- Wrong (SA05): `changedNothingSinceBase` holds, so A writes L1 plus the drag over L2 without asking.
- Must: A takes L2 in, or asks before replacing it. "Synced" means "held on this Mac".

**S-30 · A version dated far in the future** (R2 follow-up `5b301828`; RC-2)
- Setup: B's clock is days ahead, or a date is corrupt.
- Steps: B writes, and A records or answers about that version.
- Wrong (R2 before the follow-up): the future date became A's last sync, so every later version of the other Macs counted as "not newer".
- Must: one Mac's wrong clock never changes how the other Macs order later versions.

**S-31 · A re-joining Mac adopts an older version** (V3-#4, minor; step AA; RC-2, RC-5)
- Setup: A and B on N, same macOS version. B's clock is a few minutes behind.
- Steps:
  1. B Command-drags and writes; the version is dated before A's last sync.
  2. On A, turn sync off and on. `lastSynced` and the base are kept.
  3. Later, A Command-drags.
- Wrong (R3): the joining A adopts B's version and records L_B as synced without taking it in. A's next drag writes over L_B without asking, and B applies that silently.
- Must: A asks before joining over an arrangement it never took in, or takes it in. It never overwrites it silently later.

**S-32 · A clock set back, or two writes in the same second** (V5, minor; step AP; RC-2) [§5.2 pair 9]
- Setup: A and B on N.
- Steps:
  1. A changes a setting (write W1).
  2. Set A's clock back a minute, and change the setting back (W2, dated before W1). Variant: two writes within one second.
  3. Delete `Settings.plist`. On B, change a setting; B's write lacks W2.
  4. A checks.
- Wrong (R5): a write was identified by its wall-clock date in whole seconds. B's version seemed to hold A's last write, and A applied it silently, reverting W2.
- Must: A asks, because its last write is missing, whatever its clock did.

**S-33 · Keep over a version dated at or before the answered one** (V2-#1, major; step S; RC-8, RC-2)
- Setup: A and B on N.
- Steps:
  1. Both Macs change "Show on hover", and A's sheet is open.
  2. Set B's clock back a few minutes, change another setting on B, and let it reach A.
  3. On A, choose Keep This Mac's Settings.
- Wrong (R2): Keep accepted any version dated at or before the answered one, so A wrote over B's new version, which nobody had asked about.
- Must: Keep replaces only the exact version that was answered. Anything else asks again.

### G6 · The file goes missing, is restored or becomes unusable

**S-34 · A write over a missing file reverts another Mac's change** (V2-#2, V3-#1a, major; step Y.1–3; RC-1, RC-3)
- Setup: A and B on N, same macOS version. Both last synced V1.
- Steps:
  1. B changes "Show on hover" (V2). Before A reads it, delete `Settings.plist`, or replace it with an empty or damaged file.
  2. A changes another setting and writes into the missing file.
  3. B checks.
- Wrong (SA05–R3): B sees A's newer version and has no changes, so it applies A's version (silently at its next launch). B's own change is reverted.
- Must: B asks, because its last change is missing, or the change is merged. Never a silent apply.

**S-35 · A waiting version dropped when the file goes away** (V3-#1a', major; step Y.4; RC-9, RC-3)
- Steps:
  1. B writes V2, and A shows Restart or Choose Settings… (V2 pending).
  2. The file is deleted or damaged.
  3. A checks, or changes a setting.
- Wrong (R3): A withdraws the hint and drops V2. With a change, A also writes, which reverts B.
- Must: V2 stays offered, and nothing is written until the user answers.

**S-36 · A relaunch while the file is missing** (V4, docs; step AJ; RC-9)
- Steps:
  1. B changes a setting, and A shows Restart.
  2. Delete `Settings.plist`, then quit and reopen A.
  3. A changes a setting.
- Wrong (R4/R5): the waiting version was held only in memory, so the hint is gone after the relaunch. Only B's later question prevents the loss.
- Must: a waiting version survives a relaunch (INV-9).

**S-37 · Keep without a layout edit, then the file goes away** (V3-#1b, major; step Y.5; RC-3, RC-5, RC-8)
- Steps:
  1. On B, Command-drag and change "Show on hover". On A, without touching the layout, change it the other way, then choose Keep This Mac's Settings. A keeps L_B, and Restart is pending.
  2. Delete `Settings.plist`.
  3. On A, change a non-layout setting.
  4. Quit and reopen B.
- Wrong (R3): A's write over the missing file lists A's own layout (with holzBar's placements) as current, and B applies it over L_B.
- Must: B keeps its arrangement. A takes L_B in later, or its next drag asks.

**S-38 · A copy over a missing file, then a second write promotes holzBar's layout** (V4, blocker; step AE; RC-5, RC-3)
- Steps:
  1. S-37 step 1.
  2. Delete `Settings.plist`. On A, change "Show on hover", then change it back (two writes).
  3. Quit and reopen B.
  4. On B, Command-drag.
- Wrong (R4): the first write marked A's layout as a copy. The second write, over A's own version, took the copy for "no layout" and listed A's layout with holzBar's placements as current. B applied it silently.
- Must: B keeps its arrangement and takes A's setting. B's drag lists B's layout as current again.

**S-39 · Several writes, or a third Mac, on top of a version without B's change** (V4, blocker, plus a descendant case; step AG; RC-1, RC-2)
- Steps:
  1. B changes "Show on hover". Before A reads it, delete `Settings.plist`.
  2. A changes a setting, then another. Variant: a third Mac applies A's file and changes a setting.
- Wrong (R4): the date-only `basedOn` of A's second write points at A's first write, which hides that B's write is missing. B applied the version and lost its change. A question about a version without B's write also turned into a plain Restart once a later version arrived.
- Must: B asks, however many writes follow.

**S-40 · A third Mac applies a version without a write it holds** (V5, major; step AM; RC-1, RC-5)
- Setup: A, B and C on N, same macOS version. C restarted with A's arrangement before the deletion.
- Steps:
  1. On A, Command-drag. Before B reads it, delete `Settings.plist`.
  2. On B, change "Show on hover"; B's write lacks A's write.
  3. C checks.
- Wrong (R5): `missesLastWrite` compared only C's own entry, so C applied B's version silently and lost A's arrangement, which it already held.
- Must: C shows Choose Settings…, and keeps the arrangement after a relaunch.

**S-41 · The `seen` record claims a write whose layout was never taken in** (V5, blocker; step AN; RC-5, RC-3) [§5.2 pair 8]
- Steps:
  1. S-38 steps 1–2.
  2. On B, change a setting. On A, restart with it: A keeps its own arrangement, and A's `seen` now claims B's write.
  3. Delete `Settings.plist`, and change a setting on A.
  4. Quit and reopen B.
- Wrong (R5): A's write over the missing file listed A's stale layout as current, and B applied it silently.
- Must: B keeps its arrangement.

**S-42 · A sync app restores an older version of this Mac's own** (V2-#6, major; step R; RC-3, RC-5)
- Steps:
  1. A changes a setting and writes. Copy `Settings.plist` aside.
  2. A Command-drags and writes again.
  3. Put the copy back.
  4. Quit and reopen A.
  5. A changes "Show on hover".
- Wrong (R2): at launch, A took in its own older version, which reverted its drag. The next write would have spread the stale layout.
- Must: A keeps the drag, and its next write lists the dragged layout as current.

**S-43 · Variants of an unusable file** (V0-#1, V3-#1; RC-3, RC-10)
- Variants:
  - an empty file;
  - a damaged plist;
  - a plist without the `settings` key;
  - a symbolic link or a folder in place of the file or of the `holzBar` folder;
  - a file over 1 MiB.
- Wrong (SA05): the file was mapped to "unusable" and written over at the next local change, and a waiting version was dropped.
- Must:
  - A file holzBar cannot interpret never counts as "no other Mac wrote here".
  - No overwrite loses another Mac's change silently, and the user sees the state.
  - A deliberate new setup (S-44) stays possible.

**S-44 · Setting up a new folder** (R6 deviation; must not stall)
- Steps: A, on N, chooses an empty folder with Change…. Later B joins.
- Must:
  - A publishes its complete state, with its layout listed as current, without any question.
  - B's join follows S-01 and S-07.
  - Any fix for S-34 to S-41 must leave this working (§5.2 pair 2).

### G7 · What an answer means (Use / Keep / Later)

**S-45 · Keep writes an untouched layout over a newer arrangement** (V0-#2, major; step C; RC-8, RC-6)
- Steps:
  1. On B, Command-drag (L2) and change "Show on hover".
  2. On A, without touching the layout, change it the other way.
  3. On A, choose Choose Settings… → Keep This Mac's Settings.
  4. Restart A through the hint, or quit and reopen it. Variant: Command-drag on A before restarting.
- Wrong (SA05): Keep wrote A's L1, which differed only by holzBar's placements since the last sync, over L2. B lost its drag at its next restart or launch. The question had shown only the settings difference.
- Must:
  - The folder keeps L2 together with A's setting.
  - A takes L2 in at the restart or launch.
  - A drag on A before then asks.

**S-46 · A version arrives while the question is open** (V1-#2, minor; step K; RC-8, RC-1)
- Steps:
  1. Both Macs change "Show on hover", and A's sheet opens.
  2. B changes another setting, and it reaches A.
  3. On A, choose Keep.
- Wrong (SA05/R1): Keep wrote over B's new version, which nobody had asked about.
- Must: the hint returns as Choose Settings…, and nothing of B's new version is lost.

**S-47 · Keep, then sync turned off and on before the restart** (V1-#0, major; step I; RC-8, RC-5)
- Steps:
  1. S-45 steps 1–3, without restarting.
  2. On A, turn sync off and on.
  3. Restart A, or Command-drag before restarting.
  4. Quit and reopen B.
- Wrong (R1): the re-join recorded B's kept layout as synced without applying it, so A's next drag overwrote B's arrangement silently.
- Must:
  - A shows Restart and takes L2 in; a drag before then asks.
  - B keeps L2.

**S-48 · Keep, a drag, then joining again** (V2-#0, major; step Q; RC-8, RC-5)
- Steps:
  1. S-45 steps 1–3.
  2. A Command-drags; the hint reads Choose Settings….
  3. Turn sync off and on. Variants: choose the same folder again with Change…; or turn sync off, Command-drag, then turn sync on.
- Wrong (R2): the re-join wrote A's dragged layout over B's kept layout without asking.
- Must: A asks before it joins, and B keeps L2 until the user chooses.

**S-49 · After Keep, pushes stop, or an ordinary change asks about this Mac's own write** (V1-#7, minor; step L; RC-8, RC-9)
- Steps: after S-47 step 1 (Keep, no restart), toggle another setting on A. Then quit and reopen A.
- Wrong (R1): pushes stopped, and the ordinary change turned into a question about A's own write.
- Must:
  - The toggle syncs, and B receives it. The hint stays Restart.
  - At the relaunch, A takes L2 in and keeps the toggle.

**S-50 · Keep for a re-joining Mac brings the question back** (V4, major; step AH; RC-8)
- Steps: the S-31 setup. A asks at the re-join; choose Keep This Mac's Settings.
- Wrong (R4): the re-join branch was checked before Keep, so nothing was written and the same question came back.
- Must: one Keep settles the question.

**S-51 · Keep over a restored older version lists its stale layout again** (V5, blocker; step AK; RC-8, RC-2, RC-3)
- Setup: A, B and D on N, same macOS version.
- Steps:
  1. On D, Command-drag. A and B restart with D's arrangement.
  2. Put back a copy of `Settings.plist` saved before step 1, as a sync app restoring it would.
  3. On A, choose Choose Settings… → Keep This Mac's Settings.
  4. Restart D and B.
  5. Repeat with sync turned off and on on A before step 3 (the re-join path).
- Wrong (R5): Keep over a version that was not newer than A's last sync listed that version's stale layout as current. D and B applied it, and D's arrangement was reverted on every Mac.
- Must:
  - A keeps D's arrangement and shows no Restart. `currentLayouts`, or its successor, lists that arrangement.
  - D and B keep it.

**S-52 · Keep after a lost write: the arrangement is lost whichever button the user picks** (V5, blocker; step AL; RC-8, RC-1)
- Steps:
  1. On A, Command-drag. Before B reads it, delete `Settings.plist`.
  2. On B, change "Show on hover".
  3. On A, choose Keep This Mac's Settings.
- Wrong (R5): Keep, answering a version without A's last layout write, kept B's stale layout. Use would have lost A's arrangement too.
- Must: A keeps its arrangement, and B shows it after a restart. B's setting is replaced by A's, because the user chose so after the question showed it.

**S-53 · Keep answered while the file is missing** (V5, minor; step AO; RC-8, RC-3)
- Steps:
  1. On B, Command-drag and change a setting. On A, change a setting; A shows Choose Settings….
  2. Delete `Settings.plist`, and choose Keep on A.
  3. B checks.
- Wrong (R5): the answered version was not recorded, so B asked the same question again. The obvious fix, recording it, would have let B apply A's layout silently over its arrangement.
- Must: B shows Restart, not a question. After the restart, B keeps its arrangement and has A's setting.

**S-54 · The kept-layout record is lost after a successful write** (V3-#3, minor; step AB; RC-9, RC-5) [§5.2 pair 5]
- Steps: A's write that keeps B's layout reaches the file, but the local record is lost. Causes:
  - sync is turned off while the exchange runs, and the cancelled task drops the result;
  - holzBar quits between the coordinated write and the state update;
  - the state comes from an older branch build.
  
  A then changes a user setting.
- Wrong (R3): with no kept record, `isOldOwnLayout` judged the version an old copy, and A wrote its own layout over L_B. B applied it at launch.
- Must: A never overwrites on the strength of a missing record. It recovers the record or asks.

### G8 · Automatic versus user changes

**S-55 · holzBar places new items or apps** (SA-05; must not ask)
- Steps: an app adds a menu bar item on A. On macOS 26 it gets the default placement; on macOS 27, `Concealer27` places the new app. Seeding counts the same.
- Must:
  - No hint on B. A Restart hint already showing on A stays Restart.
  - A's next layout change takes the placement along. A non-layout write takes it along only for items no other Mac has seen.
  - The placement never replaces B's arrangement.

**S-56 · A Command-click without a move** (V0-#6, V1-#3, minor; steps F, M; RC-6)
- Steps: with Restart showing, Command-click an item without moving it. Variant: the default new-item placement has left an unsaved item.
- Wrong (SA05/R1): it counted as a layout edit, so the hint became Choose Settings…, and the next push listed holzBar's placements as the user's.
- Must: no edit.

**S-57 · Applying the current profile again** (V1-#4, minor; step N; macOS 27; RC-6)
- Steps: with Restart showing, apply the current layout profile again by its hotkey.
- Wrong (R1): it counted as an edit.
- Must: the hint stays Restart.

**S-58 · The first move of an item holzBar never saved** (V2-#4a, V3-#2a, major; steps V and AC.3; macOS 26; RC-6) [§5.2 pair 7]
- Steps: the user Command-drags an item that has no saved section, because it appeared during a drag, was skipped while the restore yielded, or was only temporarily shown. Then a newer version arrives from a Mac that knows the item.
- Wrong (R2/R3): the move did not count, so the remote section was applied, and the move was reverted silently.
- Must: the move counts. A writes it, or asks if the other Mac moved the same item too.

**S-59 · macOS displaces items, then the user Command-clicks or drags** (V2-#4b, V3-#2b, major; step AC.1–2; macOS 26; RC-6) [§5.2 pair 6]
- Steps: connect or disconnect a display, or wake the Mac, so macOS moves items. Before the restore puts them back, the user Command-clicks or Command-drags any item.
- Wrong (R2/R3): the save 1.5 s later stored the displaced section of every cached item and counted it as the user's arrangement. A wrote it over the other Macs' arrangements, and they applied it silently.
- Must: displaced items keep their saved sections. Only the item the user moved counts.

**S-60 · A reconciliation stores an old section over the user's fresh save** (V2-#7, minor; macOS 26; RC-6, RC-9)
- Steps: the user saves a section by dragging. A reconciliation that read the bar earlier then stores the item's old section.
- Wrong (R2): holzBar's stale placement replaced the user's fresh save, and the stale value synced.
- Must: an automatic store never replaces a section the user saved after the read.

**S-61 · A move in the Layout pane during a restore** (step AD, major; RC-6)
- Steps: drag an item in the Layout pane right after a wake.
- Must: the move is saved and synced, and the next restore never reverts it.

**S-62 · A layout rearranged during the β2 pause, then sync resumes** (`77ab5629`, remediation "Next beta"; RC-6, RC-7)
- Setup: A synced under β1, then updated to β2. β2 runs no migration, counts no edits and writes no version marker.
- Steps:
  1. The user rearranges A's menu bar.
  2. A updates to N, and sync resumes.
- Wrong (SA05 migration as written): `SettingsSyncLayoutEdits` is missing, so `initialLayoutEdits(hasLayout: true, syncs: true)` returns 0. The layout counts as unchanged, and the join takes the folder's layout silently.
- Must: on the first sync after an update from any earlier build, an existing layout counts as the user's, and holzBar asks if it differs.

**S-63 · Only learned keys differ** (sync-1 decision; must not ask; RC-6)
- Setup: A and B on N. Only `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners`, `MacOS27LayoutSeeded`, `hasMigrated*` or `hasImportedPreviousSettings` differ.
- Wrong (β1): a whole-file apply replaced the receiving Mac's `KnownItemTags`, and the automatic rewrites caused prompts on the other Mac.
- Must: a silent union or OR merge, with no question, no hint and no restart.

### G9 · Timing races

**S-64 · Restart within 1.5 s of a drag** (V0-#4, minor; step E; macOS 26; RC-9, RC-6)
- Steps: B changes a setting, and A shows Restart. On A, Command-drag an item and click Restart within about 1 s.
- Wrong (SA05): the save waits 1.5 s (`saveSectionsSoon`), so the hint saw no edit. The restart applied B's version, the next launch restored the old section, and the drag was lost.
- Must: the drag counts, so A asks, or A saves first. Keep then keeps the drag.

**S-65 · An edit lands during an exchange** (R2 issue 13; RC-9)
- Steps: a user edit happens between building an exchange request and recording its result.
- Wrong (SA05 glue): the record used an edit count newer than the one the decision saw, so the edit was marked as synced although it was never written.
- Must: an edit made during an exchange is never recorded as synced, and it starts the next exchange.

**S-66 · A hint built from a stale side** (R3 `f5895cb6`; RC-9)
- Steps: a change happens while an exchange runs.
- Wrong (before R3): `.apply`, `.ask` and `.takeInLayout` built the hint from the request's state, so the hint was stale: Restart instead of Choose Settings…, or the other way round.
- Must: hints always reflect the current local state.

**S-67 · Displacement and arrangement within the 2 s settle window** (R4 residual, documented; macOS 26; RC-6, RC-9)
- Steps: macOS displaces items, and the user arranges, both within 2 s of a display change or wake, while holzBar does not read the bar.
- Wrong (R4–R6): decided as before R4, so the displacement can count as the user's.
- Must: INV-4 holds inside the window as well. The design must not depend on a snapshot taken before the arrangement, which may not exist.

### G10 · Convergence and how often holzBar asks (guards against "safe by stalling" or "safe by asking")

**S-68 · A closed laptop catches up** (R3 non-fix note; must not ask)
- Setup: A and B on N.
- Steps: A is closed and offline while B writes twice, with separate changes. Then A opens.
- Must: A applies B's latest version without a question: silently at launch, or through Restart while running. A design with a single parent digest fails this.

**S-69 · An arrangement held only as a copy stalls** (R5/R6 accepted risk; RC-5, RC-4)
- Setup: an arrangement exists in the folder only as a copy. Causes:
  - a sync app restored an older version;
  - a Mac wrote over a deleted file while a kept layout waited;
  - a Mac of the other macOS version set up the folder;
  - Keep was answered while the file was missing.
- Wrong (R5/R6, documented): no Mac takes the arrangement until the user rearranges on a Mac of that macOS version. Meanwhile each Mac keeps its own, so the Macs diverge with no end.
- Must: the Macs converge on the newest user arrangement without another rearrangement (INV-15).

**S-70 · Extra questions after bookkeeping gaps** (R5/R6 known risks; RC-5, RC-2)
- Cases:
  - an adoption that does not move `lastWritten`, followed by a version that holds this Mac's settings but not its write record;
  - a newer version that changed nothing and was not merged into `seen`, followed by a write over a missing file;
  - the `lastWritten` of a round 4 build;
  - more than 64 Macs in the record;
  - a clock set back after a reset.
- Wrong (R5/R6): one extra question in each case.
- Must: no question when none of this Mac's user changes is missing (INV-7).

---

## 7. Coverage index and how to use the catalogue

### 7.1 Root-cause class → scenarios

| Class | Scenarios |
|---|---|
| RC-1 Whole-state writes into one file | S-01–S-05, S-11, S-20, S-28, S-29, S-34, S-39, S-40, S-45, S-46, S-52 |
| RC-2 Wall-clock ordering | S-15, S-16, S-28–S-33, S-39, S-51, S-54, S-70 |
| RC-3 File lifecycle | S-03, S-09, S-11, S-15, S-19, S-26, S-34–S-44, S-51, S-53 |
| RC-4 Two per-OS layouts | S-13–S-19, S-69 |
| RC-5 Provenance from digests and absence | S-17, S-18, S-20, S-22–S-25, S-29, S-31, S-37, S-38, S-40–S-42, S-47, S-48, S-54, S-69, S-70 |
| RC-6 Automatic vs user | S-04, S-08, S-21, S-27, S-45, S-55–S-64, S-67 |
| RC-7 Peers on other versions | S-01, S-08, S-18–S-27, S-62 |
| RC-8 Answer scope | S-23, S-33, S-37, S-45–S-53 |
| RC-9 Races and atomicity | S-04, S-05, S-35, S-36, S-49, S-54, S-60, S-64–S-67 |
| RC-10 Identity, I/O, content | S-06, S-09–S-12, S-43 |
| RC-11 Verification | all: §7.2 |

### 7.2 What "passes" means

1. **Automate every scenario as a multi-Mac test** that drives the real decision, state and file code, with no copied glue. The test environment simulates:
   - the folder, with delay, dataless placeholders, restore, deletion, damage and conflict copies;
   - a clock per Mac, with skew and steps;
   - a **β1 peer** that implements exactly the `v0.0.7-beta1` algorithm from §2.1: write at launch and 5 s after any change, never read first, apply silently with key removal, drop unknown keys, order by `modified > lastSynced`;
   - a **β2 peer** that does nothing and counts no edits.
2. **Each test asserts:**
   - every Mac's final user settings and per-OS layout, and the folder state;
   - the number of questions and what each covered, and the hints;
   - that no user value changed outside an answered question (INV-1 and INV-2, checked against a ground-truth log of user intents that the test keeps).
3. **Test generated event sequences.** The test generates sequences of these events and checks the invariants INV-1, -2, -4, -5, -6, -7, -9 and -15 as oracles after every step:
   - user edits (settings, layout per OS, profile, import);
   - holzBar placements and macOS displacements;
   - file deletion, restore, damage, delay and dataless placeholders;
   - clock steps;
   - relaunch, quit during an exchange, sync off and on, Change…;
   - Use, Keep and Later;
   - β1 and β2 peer actions.
   
   Every review round found its blockers this way, by hand.
4. **The [CONFLICT] scenarios** (S-19, S-25, S-26) need an explicit, documented boundary decision for β1 peers before implementation (§5.4). The tests then assert the chosen boundary.
5. **Run on real Macs** S-01, S-09, S-14, S-20 (with a real β1 Mac), S-34, S-45, S-59, S-62 and S-68, on iCloud Drive, on one File Provider folder (Dropbox or OneDrive) and on one SMB share. The SYNC-01 and sync-1 human check is still open and was never run in R1–R6.

---

## 8. Appendix: hazards the classes imply but V0–V5 never exercised

Listed so the redesign checks them deliberately. None was observed.

- **Provider conflict copies** such as `Settings 2.plist` or "conflicted copy" files. No build reads them, so a concurrent write that lands in a conflict copy is a lost update nobody sees (RC-3, C5). Any design with several files must also define a consistent snapshot across files.
- **Local state rolled back on the same hardware.** A Time Machine restore of `~/Library/Preferences` keeps the hardware hash, so the identity is unchanged (F-38 does not trigger). But the base, `lastSynced`, `lastWritten` and `seen` roll back while the folder is newer. The restored Mac must not treat its old state as current (RC-5, RC-10).
- **Preferences deleted or the app reinstalled.** The Mac becomes a joining Mac with the same hardware hash. It must follow S-01/S-07 and not be mistaken for an earlier writer.
- **The folder moved or renamed by the sync app** while a waiting version exists. INV-9 has to hold across a change of the bookmark's location.
