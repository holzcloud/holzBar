# Settings sync redesign: analysis, architecture and plan

Synthesis of the sync redesign analysis for holzBar, written 2026-10-07. This is a read-only analysis: nothing in the repository or its git state was changed.

**Inputs:**
- `A1-failure-taxonomy.md`: 11 root-cause classes, invariants INV-1 to INV-16, the nine ambiguous history pairs, the β1 constraint conflicts C1 to C5 and the 70 regression scenarios S-01 to S-70.
- `A2-requirements-invariants.md`: requirements, simulator-checkable invariants, the fault model and open questions OQ-1 to OQ-14.
- `A3-research.md`: techniques, provider behaviour and Apple APIs.
- `D1-per-device-files.md`, `D2-single-file-version-vectors.md` and `D3-settings-only.md`: three designs, each walked through the catalogue.
- The verdicts of three judges: J1 (adversarial lens), J2 (pragmatic lens) and J3 (formal lens).
- The decisions `sync-1` and `modal-alerts-1`.
- The remediation log and the redesign todo.
- `docs/features.md`.
- The code on `planning/sync-redesign`, which equals `main` at 0.0.7-beta2. Appendix A lists every code fact this plan relies on, re-checked at file and line.

**Terms:**

| Term | Meaning |
|---|---|
| β1 | 0.0.6 and 0.0.7-beta1, with byte-identical sync code, in the field. It writes `holzBar/Settings.plist`, applies a newer file silently at launch with remove-missing, and pushes at every launch. |
| β2 | 0.0.7-beta2, released, with sync paused. It is inert towards the folder. |
| N | A Mac running the redesign: Phase 1 targets 0.0.7-beta3. |
| unit | The smallest piece of state that syncs, merges and can conflict: one setting, one hotkey, one item's icon. |
| entry | One value of a unit, stamped with a dot. A deletion is an entry too. |
| dot | `(MacID, n)`: the Mac that made a change and its counter there. Dots are compared only with dots of the same Mac. |
| context | A version vector `MacID → n` holding every dot a replica has seen. |
| replica | Context plus the live entries of every unit. Each Mac persists one and publishes it as its file. |
| Σ | This Mac's local sync state, kept as one atomic file. |
| applied | Per unit, the dots whose value this Mac's defaults hold: what the user here has seen ("taken in"). |
| baseline | Per unit, the canonical digest of the local value as last captured or applied. |
| `pre` | A local value without a dot whose origin holzBar could not observe. It is protected: it is never replaced without an answer. |
| fast-forward | A remote value that supersedes what this Mac applied. It applies silently at launch, or through **Restart**. |
| conflict | A unit whose live entries hold two or more different values. |

---

## 0. Status and the short answer

**Where sync stands on 2026-10-07:**
- **β1 in the field** (0.0.6 and 0.0.7-beta1) still runs the old sync: one shared `holzBar/Settings.plist` that every Mac overwrites. A newer file is applied silently at launch, and keys the file lacks are removed.
- **β2 is released with sync paused** (`SettingsSyncPause.isPaused = true`, guarded by a test). It never touches the folder, and it keeps the stored configuration (on/off, bookmark, device ID, every `SettingsSync…` key) for a later resume.
- **The paused code on `main`** fixes F-02, F-15, F-18, F-38, F-60 and SA-05, but it does not run.
- **The 58-commit branch `audit-manual/sync-fix`** (rounds R1–R6) is reference only and must not be merged.
- **The analysis is complete:** A1–A3, three designs and three judges.

**The answer in five lines:**
1. **Phase 1 (0.0.7-beta3)** syncs the user's settings only, through one file per Mac (`holzBar/Macs/<MacID>.plist`), with a causal merge per setting: dots, multi-value registers and a lattice join.
2. The menu bar arrangement, the profiles and everything holzBar learns stay on each Mac. All six fix rounds failed on exactly that arrangement.
3. β1 Macs and β3 Macs form two separate groups until every Mac is updated. holzBar never writes the old file. When a Mac updates, holzBar compares its settings and asks where they differ, so nothing is lost.
4. **The design is proven before app code exists:** a deterministic multi-Mac simulator in the HolzBarCore test package runs the real Core engine against β1 and β2 peers and hostile file providers, and checks every invariant over thousands of seeded runs plus the full A1 catalogue.
5. **Phase 2 (later, opt-in)** adds the arrangement as "Also sync the menu bar arrangement". It is gated on Phase 1 passing on real Macs and on a real-Mac prototype of the macOS 26 Command-drag attribution.

All three judges converge on this combination: D3's scope on D1's engine, D2 rejected.

**What the maintainer must decide** (§6; four questions in `SYNC-REDESIGN-DECISIONS.json`):
- (1) stop syncing the arrangement in Phase 1;
- (2) merge different settings without asking, and ask only when the same setting changed on two Macs;
- (3) accept two groups (β1 and β3) during the rollout;
- (4) how profiles move between Macs.

Eight further points have a recommended default (§6.2).

---

## 1. What went wrong, and why patching could not converge

### 1.1 The shape of the failure

- About 50 confirmed defects across reviews V0–V5 (9, 9, 9, 7, about 8 and about 8), plus six audit findings, reduce to 11 root-cause classes (A1 §4).
- Blockers per review rose instead of falling: V0 2, V1 0, V2 1, V3 1, V4 3, V5 3.
- 25 of the roughly 41 findings in V1–V5 were caused or only half fixed by the previous round (A1 §5.3).
- From SA05 to R6, `SettingsSyncPolicy.swift` grew from 717 to 2,358 lines. Persisted `SettingsSync*` keys grew from 11 to 16, and sync-file keys from 3 (β1) to 6.
- Every gate passed in every round: mutation checks were "all caught" each time. No two-Mac step (A–AP) was ever run on real Macs.

### 1.2 Root causes (A1 §4, condensed)

| Class | Mechanism |
|---|---|
| RC-1 | One shared file, replaced whole by every Mac, without compare-and-swap. This is the classic lost update. |
| RC-2 | "Newer", "seen" and "based on" were decided from wall-clock dates. |
| RC-3 | The file lifecycle is outside holzBar's control: deleted, restored, dataless, damaged, too large. |
| RC-4 | Two per-OS layouts in one file, plus a legacy peer that deletes missing keys. |
| RC-5 | Provenance was inferred from content digests and from missing records. |
| RC-6 | Layout values were snapshots of the observed bar, mixing user moves, macOS displacement and holzBar's placements. |
| RC-7 | β1 peers drop all metadata, rewrite at every launch and apply silently. |
| RC-8 | Questions and answers covered the whole state. |
| RC-9 | Asynchronous bookkeeping, spread over about 16 keys, that was not atomic. |
| RC-10 | Identity, I/O and content robustness: F-15, F-18, F-38, F-59, F-61. |
| RC-11 | Verification that could not see the defects: untested glue, no generated sequences, no real two-Mac run. |

### 1.3 Why no rule set could converge

Every round kept the shape `decide(trigger, Local, File)` over lossy summaries: dates, whole-state digests, one base per Mac, one edit counter per layout. A1 §5.2 lists nine pairs of histories that produce the *same* summary but need *opposite* outcomes:
- a β1 write-back of an old copy, against a β1 user's deliberate return;
- a deleted file after an unseen write, against a new folder;
- a lagging clock, against a restored old version;
- "seen", against "taken in";
- a user move, against a macOS displacement;
- an unsaved item the user moved, against one holzBar placed;
- A→B→A, against nothing changed;
- and others.

Any decision function over those inputs is wrong for one column of every row. Each patch picked a column, or added a proxy field (a date, a digest list, a flag). That proxy had its own counterexample, was not kept up to date on every path, or was destroyed by β1's next write. Restores, deletions, a third Mac and legacy writers can generate new such pairs without limit, so the patch sequence could not converge.

**β1 makes some outcomes impossible while N shares its file** (A1 §5.4):
- **C1:** with a missing file, every choice for the other OS's layout fails: copy, omit or mark.
- **C2:** β1 strips metadata.
- **C3:** β1 applies silently at launch.
- **C4:** β1 orders by clock.
- **C5:** a single file without compare-and-swap.

The only exit is not to write the file β1 applies.

### 1.4 What any working design must record (A1 §5.5, A3 §2)

- **Single-writer data.** No Mac ever overwrites another Mac's data. This removes RC-1 and C5.
- **Causal stamps per unit, independent of clocks.** This removes RC-2 and RC-5.
- **"Seen" and "taken in" as separate facts,** with the user's intent captured at the moment of change. This removes RC-5, RC-6 and RC-8.
- **A hard boundary with β1.** This removes RC-7 and C1–C4.
- **One atomic local state.** This removes RC-9.
- **Verification by generated adversarial histories against ground-truth oracles,** driving the real code. This removes RC-11.

The arrangement's intent on macOS 26 cannot be recorded reliably by the existing hooks (Appendix A, item 9), which is why Phase 1 leaves it out.

---

## 2. The invariants

### 2.1 Constraints and policy every invariant serves

- **No network.** Sync goes only through a folder the user's own sync app provides: iCloud Drive, Dropbox, OneDrive, Nextcloud, Syncthing, SMB or any folder. holzBar has no iCloud entitlement.
- **Privacy.** Nothing identifying leaves the Mac except the settings the user syncs: no hardware UUID or its hash, salt, uid, computer name, user name, paths or bookmark data.
- **Two layout generations.** macOS 26 uses `ItemSections`; macOS 27 uses `MacOS27Layout`.
- **Updates arrive one Mac at a time,** with downgrades possible.
- **Maintainer policy.** holzBar asks on real conflicts, never overwrites or reverts silently, and never counts its own automatic placements as the user's changes. `modal-alerts-1`: a quiet hint plus a sheet on the Settings window, never a dialog by itself.

### 2.2 The invariant set (checked by the simulator; IDs follow A2, plus new ones)

**When each invariant is checked:**
- *step*: after every simulated step;
- *drain*: after the quiescence and drain phase;
- *meta*: as a metamorphic pair of runs.

| ID | Invariant | Check |
|---|---|---|
| **INV-S1** | **No silent loss.** A sync-caused change never replaces a live user value (or a `pre` value) on any Mac, except by an answer whose sheet showed it, or by a version whose past contains a later user change of that unit. | step |
| INV-S1g | **No global loss.** A live user change always survives somewhere: in some Mac's settings, a readable replica or a pending entry. Amended: losses where every holder was destroyed by non-sync events (wipe, reinstall) are excluded. | step |
| **INV-S2** | **No silent revert, no stale return.** Sync never moves a unit back to an older user value, nor to "unset" without an explicit deletion entry. Restored, copied, late or duplicated input changes nothing. | step |
| INV-S3 | **Honest publication.** A published context claims only dots the writer has seen, and the file carries every live entry the context covers. The engine exposes `claimedPast` to the tests. | every write |
| INV-S4 / S5 | **Absence is not deletion; deletions are explicit entries and travel.** | every ingestion |
| **INV-S6** | **Single writer.** A Mac writes only `Macs/<its MacID>.plist`, and only when that file is absent, or was read in this session and is dominated by Σ. It never writes `Settings.plist` or another Mac's file. Amended (J3). | every write |
| INV-S7 | **A waiting change lasts.** A remote entry waiting for Restart or an answer survives relaunch, file deletion and later arrivals, and no publication supersedes it. Amended: "claims" means *supersedes*, under the applied-context rule. | step |
| INV-S8 | **Local keys, the salt, the hash, the uid and names never appear in a written byte.** Checked with planted markers. | every write |
| INV-S9 | **An answer supersedes exactly the dots its sheet showed.** An entry that arrived later survives. | every answer |
| INV-N1 | *(new, Phase 1)* **No sync-caused change touches a layout, learned, flag, profile or local key.** | step |
| **INV-A1** | **Automatic events are invisible.** The same trace with or without automatic events gives the same prompts, hints and publications. | meta |
| INV-A5 | *(new)* **Launches without user events mint no dot,** also across two different N builds (unit tables, model fields) and after a β2 run with its load-time writers. | meta |
| INV-A6 | *(new)* **A re-key by `ItemIdentity` never publishes a deletion.** | step |
| **INV-P1** | **Every prompt has a witness:** a per-unit conflict this Mac takes part in, a join difference, a `pre` row, or a hotkey clash. | every prompt |
| INV-P2 | **Equal means silent.** No prompt or Restart for equal values. | every prompt |
| INV-P3 / P4 / P5 | No repeated question after an answer. Later hides the hint until the next launch. At most one sync sheet is open. | every prompt |
| INV-P6 | **Necessity.** A real conflict is shown within one launch or one check; it is never applied, hidden or published over. | drain |
| INV-P7 | *(new)* **Bystanders,** Macs with no live entry in a conflict, get no menu hint, only a Settings line. | every prompt |
| **INV-C1** | **Agreement.** Under quiescence, all N Macs agree on every synced unit. | drain |
| INV-C2 / C4 | **Write quiescence and no ping-pong.** Relaunches alone produce zero writes and zero hints. | drain, step |
| INV-C3 | **Bounded questions.** At most: the concurrent unit pairs at T0, plus one join sheet per updated Mac, plus the number of Later answers. | drain |
| INV-C5 / C6 | **Progress, and the folder agrees.** A fresh Mac joining after the drain decodes exactly the agreed state. | drain |
| INV-ID1–ID5 | **Identity.** IDs are unique after one launch, stable and local. Collisions are detected; "own" means written by me. Amended: ID2 keeps the replica on re-identification. | launch, read |
| INV-ID6 | *(new)* **No undetected dot reuse.** An own dot minted after the last publication that another file's context covers triggers re-identification *before* that file is joined. | every read |
| INV-J1 | *(new)* **A join never commits while a listed device file is unread,** unless the file is refused for a lasting reason. Cancel writes nothing. | step |
| INV-F1 | **Partial, corrupt or wrong-typed files** are never ingested and never read as missing or empty. | every read |
| INV-F2 / F3 / F10 | **Order independence, coalescing, duplicates, idempotence.** | meta, step |
| INV-F4 / F5 / F6 | Conflict copies need no name recognition for safety. Restored old files are inert. Deletion causes no local deletion. | fault scenarios |
| INV-F7 / R1–R3 | No main-thread sync I/O. Launch adds at most 1 s. Nothing is mounted. Nothing is written under an unmounted `/Volumes` path. | step, lint |
| INV-F9 | **Clock independence.** Decisions are identical across clock offsets and steps. Amended: publications are compared modulo per-Mac order-preserving counter renaming, because counters carry a time floor. | meta |
| INV-Z1–Z6 | **Size and refusal.** The writer limit is at most the reader limit. Too large is never written and never treated as missing. Amended: Z4 bounds by devices ever seen, since contexts are never pruned. | step |
| INV-B1–B9 | **Compatibility.** B1–B4 hold by the boundary (N never writes the β1 file). B6: old local state is never evidence. B7: N → β1 → N loses nothing and returns as a join. B8: newer formats are never rewritten. B9: N never writes L0's `device` field. | peer scenarios |
| INV-PR1 / PR2 | **No network; no identifier in any written byte.** | lint, every write |

**Liveness assumptions** (A2 §5.6). From T0 on, no user events except answers and no lifecycle or clock steps. Every write is delivered eventually, and every dataless file eventually becomes readable. Every Mac runs infinitely often. Every prompt is eventually answered, with Later allowed only finitely often.

### 2.3 Amendments to A2 before the simulator is built (J3)

Without these amendments, every multi-value-register design fails A2's oracles literally, which would make the gate meaningless:
1. **Split `Past` into *seen* (the context) and *applied*.** Restate INV-S7(b), the Keep row of INV-S9 and Conflict/W1 in terms of supersession and the applied past. Relaying an entry is not claiming it.
2. **INV-ID2** keeps the replica on re-identification.
3. **INV-F9** compares publications modulo counter renaming.
4. **INV-S1g** excludes losses where every holder was destroyed by non-sync events.
5. **INV-Z4** counts devices ever seen.
6. **Replace SC-40's continuous β1 ingestion with the boundary.** Continuous ingestion contradicts INV-A1, because β1 pushes its automatic writes.
7. **Conflict granularity follows decision D-2:**
   - per unit (recommended);
   - or a whole-set witness computed from per-unit dots, never from a coarser "Mode G" unit.
8. **Phase 1 only:**
   - INV-L1–L6, INV-A3, R-COMPAT-4 (pause gap), INV-K1–K3 and R-FUN-8 become vacuous;
   - INV-N1 replaces them;
   - INV-C1 is narrowed to synced units.
9. **R-FUN-6:** re-enabling with a trusted Σ is a merge that asks only where both sides changed, not a full comparison.
10. **INV-Z5 is relaxed in Phase 1.** Nothing is deleted automatically (D-9), so the file count can grow beyond the live Macs, by one file per re-identification. Re-identification is rare. Every value stays relayed, so the 64-file read cap loses nothing.

---

## 3. The options and the judges' scores

### 3.1 The three designs

- **D1: one file per Mac, dotted multi-value registers, settings *and* per-item layouts.**
  - Each Mac publishes its full replica.
  - Layouts are per-item units in two namespaces, `l26/` and `l27/`, each authored only by its own generation.
  - macOS 26 Command-drags are attributed at drag start.
  - Strongest model and full feature set. About 1,700 lines of Core, 800 of glue and 3,000 of tests, plus hooks in `HIDEventManager`, `LayoutBarMoves`, `SectionRestore`, `Concealer27`, `LayoutProfiles` and the import.
- **D2: one shared `Sync2/Settings.plist`, a dot on every unit, merge-then-write.**
  - The same algebra as D1 in a single file, protected operationally by conflict-copy joins, healing, an iCloud `.current` gate and a "Replace…" flow.
- **D3: settings only.**
  - One file per Mac with a causal merge per setting.
  - The arrangement, profiles, learned keys and flags stay local.
  - Profiles move by explicit sharing or file export.
  - About 800 lines of Core, 600 of glue and 1,500 of tests.

### 3.2 Scores (0–10; "migration" = migration safety, higher means less risk)

| Design | J1 (adversarial) C / S / V / M | J2 (pragmatic) C / S / V / M | J3 (formal) C / S / V / M | Mean correctness | Mean simplicity | Mean user value | Mean migration | Sum |
|---|---|---|---|---|---|---|---|---|
| D1 | 6 / 5 / 8 / 5 | 7 / 4 / 8 / 5 | 7 / 5 / 8 / 6 | 6.7 | 4.7 | **8.0** | 5.3 | 24.7 |
| D2 | 5 / 4 / 7 / 4 | 6 / 3 / 7 / 4 | 4 / 3 / 7 / 4 | 5.0 | 3.3 | 7.0 | 4.0 | 19.3 |
| D3 | 7 / 8 / 5 / 8 | 8 / 7 / 6 / 8 | 8 / 8 / 5 / 8 | **7.7** | **7.7** | 5.3 | **8.0** | **28.7** |
| Recommended combination (J3's estimate for Phase 1) | | | | 9 | 8 | 6 (about 9 after Phase 2) | 8 | 31 |

**Regression walks, as the designs claimed them:**
- D1: 51 Pass, 13 Pass (D), 6 Pass (B). J1 judged this optimistic for S-58, S-59, S-62 and S-67.
- D2: 50 Pass, 5 Pass+, 7 Pass through the boundary, 4 Pass (M-1), 4 Pass by another mechanism.
- D3: 33 PASS, 27 SCOPE (layout clauses waived by design) and 10 BOUNDARY. No safety clause fails.

### 3.3 What broke each design (verified findings)

**D1:**
- **Pause-gap revert.** D1-Q4 counts "equal to the default" as no user value, so a deliberate return to the default during β2 is silently forced back (J1).
- **macOS 26 attribution does not exist yet.** `handleMenuBarItemDragStart` runs only when the mouse-dragged monitor runs, and that monitor runs only with "Show all sections on drag" or a custom appearance (Appendix A, item 9). Every other Command-drag falls back to `pre`, so the user is asked about their own moves, which never spread.
- **Merging learned keys breaks new-item placement and re-keys items.**
  - `SectionRestore`'s `isNew` (item 5) and `Concealer27.placeNewApplications` (item 6) stop placing items another Mac has seen.
  - Merged `TitleChangingItemOwners` re-keys items to `owner:#1` (item 7).
- **No hotkey clash rule across units.**
- **Whole-list profiles republish a stale macOS 27 part,** because `saveCurrentLayout` copies `MacOS27Layout` on every OS (item 8).
- **A 180-day cleanup by the writer's wall clock.**
- **Load-time writers count as the user's** (item 1).
- **Positional `ns:#n` keys** can name different items on two Macs.

**D2:**
- **Lost updates are possible by construction.** A collision without a copy, followed by loss of the author's replica, loses the change for good.
- **iCloud per-device conflict winners can hide a loss indefinitely.**
- **One refused canonical file blocks every Mac** until someone runs "Replace…".
- **CopyAccount reverts silently,** because the hash has no uid.
- **`legacyBase` equality silently overrides an A→B→A return.**
- **Deleting `SettingsSyncLastSynced` makes a downgraded β1 Mac re-apply a stale file.**
- **An oversize value has no origin rule.**

**D3:**
- **Capture by diff turns automatic writes of *different* values into user changes under version skew.** `MenuBarAppearanceManager`, `MenuBarItemGroups` and `holzBarIcon` re-encode on load; `MenuBarSpacers` and `GeneralSettings` clamp through `didSet`; `HotkeysSettings` writes its duplicate clean-up back (items 1–4).
- **The rollback join contradicts D3-S09:** capture runs "with a valid Σ" after a preferences rollback.
- **Item re-keys publish deletions** (items 10–11).
- **A dot-reuse hole.** After a full home restore, with the clock set back, the folder unreadable and an edit, the new dot can be dropped (J3).
- **A join commits with unread files,** so Cancel is lost.
- **A clock-based default for three-way rows.**
- **Scope:** the arrangement and the profiles stop syncing.

### 3.4 The verdict

All three judges recommend the same combination:
- **Build D3's scope on D1's engine and format** (identity rules, pass-through, room for more namespaces).
- **Fix D3's capture residuals before coding.**
- **Add D1's layout namespaces later** as a separately gated, opt-in Phase 2.
- **Reject D2.** It gives up single-writer safety for one inspectable file. D2's own §16 agrees.

The six rounds failed in the layout input layer, not in the merge. The combination removes that layer from Phase 1 and keeps the merge that can be proven.

---

## 4. The recommended architecture

### 4.1 Overview

```text
 Mac A (macOS 26, β3)                     <folder>/holzBar/                         Mac B (macOS 27, β3)
┌──────────────────────────────┐   ├─ Settings.plist        β1/0.0.6 only: never   ┌──────────────────────────────┐
│ UserDefaults (settings,      │   │                        written or deleted by  │ UserDefaults                 │
│  layouts, learned: local)    │   │                        N; read only to found  │                              │
│ Σ  ~/Library/Application     │   │                        a group                │ Σ (same structure)           │
│    Support/holzBar/Sync/     │   ├─ Macs/<A>.plist  ◄── written only by A ──────►│                              │
│    State.plist (atomic)      │   └─ Macs/<B>.plist  ◄── written only by B ──────►│                              │
│ capture → join → plan →      │        view = join(Σ.replica, every readable file) │ capture → join → plan →      │
│ apply (launch / Restart)     │                                                    │ apply                        │
└──────────────────────────────┘                                                    └──────────────────────────────┘
```

**Flow:**
1. A user change becomes an entry with a fresh dot (capture), is persisted in Σ, and is published in this Mac's own file.
2. A check reads every device file and joins it into Σ, then plans each unit: equal, fast-forward, conflict, clash or `pre`.
3. Fast-forwards apply at launch, or through **Restart**. Conflicts show **Choose Settings…**. Answers are entries that supersede exactly the dots shown.

### 4.2 What syncs in Phase 1 (unit table v1, in Core; a test fails for any `Defaults.Key` without a row)

| Stored key(s) | Unit | Notes |
|---|---|---|
| `ShowIceIcon`, `UseIceBar`, `IceBarLocation`, `IceBarDisplays`, `ShowsNotchOverflowInIceBar`, `ShowOnClick`, `ShowOnHover`, `ShowOnScroll`, `ShowOnHoverDelay`, `AutoRehide`, `RehideStrategy`, `RehideInterval`, `TempShowInterval`, `ItemSpacingOffset`, `HolzBarIconShowsCaptureDot` | one unit per key | General |
| `EnableAlwaysHiddenSection`, `ShowAllSectionsOnUserDrag`, `SectionDividerStyle`, `HideApplicationMenus`, `KeepsDockIconHidden`, `EnableSecondaryContextMenu`, `NewItemsPlacement`, `KeepLiveActivitiesVisible`, `AutoZenWhileSharingScreen`, `OpenHiddenItemsInMenuBar`, `SpacerCount`, `SpacerWidth` | one unit per key | Advanced. `NewItemsPlacement` and `EnableAlwaysHiddenSection` act on each Mac's own arrangement. |
| `IceIcon` + `CustomIceIconIsTemplate` | `HolzBarIcon`, one unit | At most 256 KiB encoded. A larger value stays on its Mac with a note (D-7) and is never replaced by a remote icon. |
| `MenuBarAppearanceConfigurationV2` | whole | At most 64 KiB. Compared after the model's own decode and encode (§4.6.2). |
| `ItemGroups` | whole | At most 64 KiB. Group image files stay local, and other Macs show the symbol, as today. |
| `Hotkeys` | split: one unit per action, and one per `OpenItem:<itemKey>` | `ApplyProfile:<name>` entries are local, with the profiles. The projection keeps them out of the replica and preserves them on apply. A hotkey clash is a question (§4.6.3). |
| `ItemIcons` | split per item key | The PNG files stay local; other Macs fall back to the next choice, as today. Re-keys follow the alias rule (§4.6.2). |
| `RevealRules` | split per entry | |
| `RevealOnChangeItems` | split per item (marked or not) | Re-keys follow the alias rule. |

**Local, never captured, published or applied by sync:**
- **Arrangement:** `ItemSections`, `MacOS27Layout`.
- **Learned:** `KnownItemTags`, `KnownApplications27` and `TitleChangingItemOwners`. They decide which items are new on *this* Mac and how *this* Mac keys its items (Appendix A, items 5–7).
- **Flags:** `MacOS27LayoutSeeded`, `hasMigrated…` and `HasImportedIceSettings` (A2 INV-K3).
- **Profiles:** `LayoutProfiles` and `CurrentLayoutProfile` (D-4).
- **Tuning:** `MacOS27ClickRestoreDelay` and `MacOS27IceBarWaitsForRefresh`.
- **LOC:** `SyncsSettingsWithICloud`, `Debug…` and every `SettingsSync…` key.
- **Ice-era input keys:** `MenuBarHasBorder` … `Sections`.

This is also a privacy gain: the folder no longer lists every menu bar app the user has, nor display and Space identifiers.

**Rules of the table:**
- A unit key never changes its value format. A changed format, a new field in a JSON unit, or a widened range gets a **new unit key** in a new table version.
- Splitting or grouping units later also means new keys.
- A unit that is new in a table version, and so has no baseline in Σ, is handled as a join for that unit only: its present local value is `pre` (§4.6.8).

### 4.3 Files and format

```text
<folder>/holzBar/Settings.plist        β1 and 0.0.6. N never writes or deletes it; it reads it only to found a group (§4.8).
<folder>/holzBar/Macs/<MacID>.plist    one per Mac, written only by that Mac: its full replica.
```

**Device file** (binary plist; D3's nested encoding plus D1's versioning and pass-through):

```text
{
  format: 1, minor: 0, unitTable: 1            // major, additive minor, unit-table version
  mac: "<MacID>"                               // must equal the file name
  installation: "<nonce>"                      // per Σ creation or re-identification (§4.5)
  written: <Date>                              // display only, never in a decision
  context: { "<MacID>": <UInt64>, … }          // every dot this replica has seen
  units:   { "<unit>": [ entry, … ] }          // whole units
  entries: { "<family>": { "<itemKey>": [ entry, … ] } }   // split units: Hotkeys, ItemIcons, RevealRules, RevealOnChangeItems
}
entry = { mac: "<MacID>", n: <UInt64>, at: <Date, display only>, value: <plist> }  or  { mac, n, at, deleted: true }
```

- **Nesting.** Identity keys can contain `/` and `:`, so split units nest one level and are never joined into one string.
- **Pass-through from day 1.** Unknown names under `units` or `entries`, values this build cannot apply, and unknown entry fields are kept and relayed unchanged as property-list values. Phase 2's `l26`, `l27` and `prof` families are therefore additive (a new `minor`), and Phase-1 Macs relay them untouched.
- **A major change uses a new folder** (`Macs2/`). An N Mac that sees a newer major shows "update holzBar" and never rewrites that data. Since each file has one writer, nobody strips anyone's fields.
- **Names.** Only `^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\.plist$` is read, and `mac` must equal the name. Everything else is ignored: `.DS_Store`, `Icon\r`, temporary files, Dropbox, Nextcloud, Syncthing and OneDrive conflict names.
  - A name that starts with a known MacID but does not match is a conflict copy of that Mac's file. It is a collision signal for that Mac only (§4.5).
  - Such names are never logged in clear, because OneDrive puts the computer name into them.
- **Limits:**
  - read at most 1 MiB, else refused as "unreadable (too large)", never as missing;
  - write at most 1 MiB, checked before writing;
  - at most 64 device files read per check: the most recently modified, then by name. The rest are skipped with a note, and their content still arrives through the relays;
  - at most 1,024 entries per split family;
  - counters at most 2^34;
  - per-unit caps as in §4.2.

  Any structural failure refuses the whole file: it is never partly merged. Values are validated one by one, and only when they are applied (F-59).
- **Typical file size:** 5–20 KB, or 30–300 KB with a custom icon.

### 4.4 Σ, this Mac's sync state (one atomic record)

`~/Library/Application Support/holzBar/Sync/State.plist` is a binary plist, replaced atomically (temporary file plus rename).

| Field | Meaning |
|---|---|
| `format`, `mac`, `nonce`, `counter` | State format, MacID, installation nonce, last counter used |
| `publishedCounter` | `counter` at the last own-file write that read back intact. Dots above it are "unpublished" (§4.5). |
| `generation` | Increases with every persist. The same number goes to the defaults key `SettingsSyncGeneration` **before** Σ is persisted (rollback detection). |
| `replica` | Context plus the live entries |
| `applied` | Unit → the dots whose value the defaults hold |
| `baseline` | Unit → canonical digest of the local value as last captured or applied, or `unset` |
| `localOnly` | Unit → reason (`oversize`, `invalid`): not published, not replaced by remote values |
| `join` | A pending join: the tentative folder state, the rows and the shown dots. It survives relaunch. |
| `legacy` | `SettingsSyncLastSynced` as N last saw it, the digest of the legacy file's `(modified, deviceID)` at founding or join, and the β1 device ID kept after rotation |
| `published` | Digest of the replica last written, and of the own file as last read back |
| `later` | Launch count at the last Later |
| `status` | Refused files, oversize units, a newer format seen, a legacy writer active, files waiting for download |

**Outside Σ:**
- **Defaults** (local, `SettingsSync` prefix, so never exported, imported or synced):
  - `SettingsSyncGeneration`;
  - `SettingsSyncCounter` (a counter mirror);
  - the existing `SettingsSyncDeviceID`, `SettingsSyncDeviceSalt` and `SettingsSyncDeviceHash`;
  - `SettingsSyncLegacyDeviceID`.
- **A counter high-water file** in the app's Caches folder (D2). Time Machine excludes Caches by default, so a restored home folder does not roll it back.

**Rules:**
- Σ changes only on the main actor, and is persisted before any device file is written.
- The order is always: apply to the defaults, write the generation, `CFPreferencesAppSynchronize`, then persist Σ. A crash in between re-applies, and applying is idempotent.
- A lost, unreadable or newer-format Σ means **joining**. It is never evidence of anything.

### 4.5 Identity, counters and collisions

- **MacID** is the existing `SettingsSyncDeviceID`, a random UUID.
- **Binding** (F-38, extended): `SettingsSyncDeviceHash = SHA-256(salt ‖ hardware UUID ‖ uid)`. It stays local and is documented in `docs/privacy-and-permissions.md`.
  - The uid splits copied accounts on one Mac (D2's CopyAccount defect).
  - On the first N run, a missing or uid-less hash mismatches once. The ID rotates, which `sync-1` allows, and the old β1 ID is kept as `SettingsSyncLegacyDeviceID`.
- **Counter:** `n = max(Σ.counter + 1, SettingsSyncCounter + 1, cacheHighWater + 1, ⌊unix seconds⌋, maxSeenSelf + 1)`.
  - `maxSeenSelf` is the highest counter of this MacID in any file read so far, in a context or an entry.
  - Σ and both mirrors are persisted before any file holds `n`.
  - Counters are compared only within one Mac, so clocks never decide anything (INV-F9).
- **Reuse check (closes J3's dot-reuse hole; INV-ID6).** Before joining any file F, look for an own dot `d` that is live in Σ, has `d.n > Σ.publishedCounter` (never published), and is covered by `F.context`.
  - Nobody can legitimately have seen an unpublished dot, so such a dot was reused.
  - holzBar then re-identifies first. Every unit holding such a dot becomes `pre`: it is asked about where the group differs, published where the group has nothing, and never dropped.
- **Other collision signals:**
  - an own dot held by any file with different bytes;
  - the own file carrying another installation nonce;
  - a conflict copy of the own file;
  - an iCloud conflict version of the own file.

  Each leads to re-identification.
- **Own file rules:**
  - Never overwrite the own file unless it was read in this session and is dominated by Σ, or is absent.
  - An own file that is ahead of Σ (Σ restored alone) is joined first: those are this Mac's own later writes, and they arrive as fast-forwards.
  - An own file that stays unreadable for a lasting reason (corrupt, wrong type, too large) is never overwritten. The Mac re-identifies and publishes under the new ID instead. Nothing is lost, because the replica is kept and dots are globally unique.
  - **"Lasting"** means the same refusal on consecutive checks for at least 10 minutes while the file's size and modification date stay unchanged. A partial, still-downloading or dataless file is never lasting.
- **Re-identification keeps** the replica, `applied` and `baseline`: a copied state is a valid causal state. It makes a new MacID and a new nonce. Units with suspect old-ID dots become `pre`.

### 4.6 Algorithms (all decisions are pure, Foundation-only Core functions)

#### 4.6.1 Join (merge)

```text
covers(ctx, d) := (ctx[d.mac] ?? 0) ≥ d.n
join(a, b):
  context := pointwise max(a.context, b.context)
  for u in units(a) ∪ units(b):
    keepA := { e ∈ a[u] | e ∈ b[u]  ∨  ¬covers(b.context, e.dot) }
    keepB := { e ∈ b[u] | e ∉ a[u]  ∧  ¬covers(a.context, e.dot) }
    a⊔b[u] := keepA ∪ keepB            // sorted by (mac, n); empty ⇒ u absent
  // entries are equal iff dot and canonical value digest are equal;
  // the same dot with two values keeps both (a conflict, never a silent pick) and flags a collision (§4.5)
```

- **Properties (tested):** commutative, associative and idempotent; `join(x, older(x)) = x`; contexts only grow.
- **A Mac's view** is `join(Σ.replica, every readable device file)`, own file included, after the reuse check.
- **An unreadable file is left out for now.** Leaving it out removes nothing, because a join only adds.

#### 4.6.2 Capture: a local change becomes an entry

```text
capture(localDefaults):                               // main actor; only while Σ is trusted (§4.6.6)
  for u in syncedUnits(unitTable) where !isAliasedHere(u):
    x := normalize(u, project(u, localDefaults))      // unset if the key or entry is absent
    d := digest(x)
    if d == Σ.baseline[u]: continue
    if !valid(u, x): Σ.localOnly[u] := .invalid; Σ.baseline[u] := d; continue        // never published
    if size(u, x) > cap(u): Σ.localOnly[u] := .oversize; Σ.baseline[u] := d; continue
    Σ.localOnly[u] := nil
    if distinct(live(u)) == [w] and digest(w) == d:   // a finished apply, or the user chose that value
        Σ.applied[u] := dots(live(u)); Σ.baseline[u] := d; continue
    e := Entry(dot: mint(), value: x or deleted)
    Σ.replica[u] := live(u) − { e' | e'.dot ∈ Σ.applied[u] } + { e }     // the applied-context rule
    Σ.replica.context[me] := e.dot.n ; Σ.applied[u] := {e.dot} ; Σ.baseline[u] := d
  if changed: SettingsSyncGeneration := Σ.generation + 1 ; persist Σ ; schedule a write (2 s)
```

**The applied-context rule.** A local change supersedes only the entries the user here had seen. Another Mac's entry that arrived but waits for Restart stays live, so the unit becomes a question. This is `sync-1`'s rule (b), applied per unit.

**When capture runs:**
- 2 s after the last defaults change (debounced);
- at launch, before merging;
- before every apply (Restart, Use, Keep) and before quitting;
- once at Turn On….

Because capture is diff-based, it catches every user path: Settings controls, hotkey actions, confirmed `holzbar://` commands, Import, undo and `defaults write`.

**Normalization** (J1, J3). `normalize` decodes the stored value with the model's own decoder and range rules and re-encodes it canonically. An older or newer build's load-time re-encode, filling defaults and dropping unknown fields, therefore compares equal. A JSON unit carrying fields this build does not know is relayed and never applied (§4.6.4).

**The alias rule for item-keyed units** (fixes D3's re-key deletions; INV-A6). `ItemIdentity.storedKey` can map a stored key such as `ns:Title` to `ns:#1` on this Mac, because `TitleChangingItemOwners` is local.
- A unit whose key this Mac maps to another key is **aliased here**: relay-only, never captured as a deletion, never applied, never asked about.
- `ItemIconStore.setChoice` and `ItemChangeWatcher.setRevealedOnChange` then publish the new key's value as an ordinary entry, and never a deletion of the old key.
- A Mac that did not learn the owner keeps applying the old key, where it matches. Nothing is lost.

**Automatic writers of synced keys must not exist.** The ones found are removed (§4.9). Any future migration that must rewrite a synced key runs inside `SyncAttribution.automatic { … }`, which moves the baseline without minting. A lint lists every `Defaults.set` of a synced key outside the settings models' setters, Import, sync's apply and the answer path.

#### 4.6.3 Plan: what each unit needs

For each synced unit `u` not aliased here, with `vals` the distinct values of `live(u)` and `x` the normalized local value:

| Case | Result |
|---|---|
| `live(u)` empty | Nothing. If `u` is new to this unit table and `x` is present: publish it as `pre` → this Mac's entry. |
| `vals == [w]`, `w == x` | **Equal**: `applied := dots(live(u))`, silently (INV-P2) |
| `vals == [w]`, `w` not applicable here (newer enum value, unknown fields, invalid) | Nothing applied. Status: "A setting from a newer holzBar can't be used here." |
| `vals == [w]`, `w ≠ x`, `u ∈ localOnly` | Protected: nothing applied, status only |
| `vals == [w]`, `w ≠ x`, local value is `pre` (a join, a new unit, a collision) | **`pre` row** (join-style question) |
| `vals == [w]`, `w ≠ x` otherwise | **Fast-forward**: applied silently at launch, or by Restart while running |
| `|vals| ≥ 2` | **Conflict**. It is this Mac's if any live entry was minted under this Mac's current or earlier IDs. Otherwise this Mac is a **bystander**: it applies neither value, gets no menu hint, and Settings shows "Your other Macs differ on %d settings" with **Choose Settings…**. |

**Clash check** (from D3). Simulate applying every fast-forward of the `Hotkeys` units, together with the local hotkeys. If two hotkeys would share a key combination, those units become one **clash row**, which counts as a conflict and is never applied. This keeps sync from creating the duplicates that `HotkeysSettings.loadInitialState` would otherwise drop.

**Hint:**
- **Choose Settings…** when a conflict, clash or `pre` row is this Mac's;
- otherwise **Restart** when a fast-forward waits;
- otherwise nothing.

The hint is recomputed from the committed Σ after every capture, merge and answer, and again when clicked (S-66).

#### 4.6.4 Apply

```text
apply(fastForwards):                    // at launch (AppDelegate.init, before AppState), or right before a relaunch
  capture(localDefaults)                // a change made just before Restart still counts (S-64)
  replan
  for (u, w) in fast-forwards that are valid, applicable here, not in a clash and not localOnly:
    write w into the defaults (remove the key or entry only for a deletion entry)
    Σ.applied[u] := dots(live(u)) ; Σ.baseline[u] := digest(w)
  SettingsSyncGeneration := Σ.generation + 1 ; CFPreferencesAppSynchronize ; persist Σ
```

- It never removes a key that has no deletion entry (F-60). It never writes a layout, learned, flag, profile or local key (INV-N1).
- **Partial apply** (D3 Q9): non-conflicting units apply while others wait for an answer. None of them is a change of the user's here.
- Apply happens only before the models load, or immediately before a relaunch. No model can write a stale value in between.

#### 4.6.5 Write: own changes, relays, healing

- **What:** the header plus `Σ.replica`.
- **When:**
  - own changes and answers: 2 s debounce;
  - relays: 10 s after a merge changed the replica, so other Macs' values survive in this file and reach a Mac that joins later (INV-C6);
  - healing: when the own file is missing, older than Σ, damaged, or written by another nonce.
  - **Never at launch.**
  - The write is skipped when the replica digest equals `published` and the own file reads back intact. That is why a relaunch writes nothing (INV-C4).
- **Preconditions:**
  - the folder is available (bookmark resolved with `.withoutMounting`, `lstat` checks on `holzBar/` and `Macs/`);
  - the own file was read in this session and is dominated, or is absent (§4.5);
  - no join is pending;
  - the encoded size is at most 1 MiB. Otherwise nothing is written, the previous file stays and Settings warns.
- **How:**
  - off the main actor, in one serial file actor, time-bounded, with at most one write outstanding;
  - an NSFileCoordinator `.forReplacing` write for iCloud Drive;
  - otherwise a dot-prefixed temporary file in `Macs/`, then a rename;
  - holzBar creates only `holzBar/Macs/` inside an existing, accessible chosen folder;
  - after the write reads back intact: `publishedCounter := counter`, then persist Σ.
- **No automatic file cleanup in Phase 1** (D-9). Departed Macs' files stay, and they are dominated and harmless.

#### 4.6.6 Launch (AppDelegate.init, after the Ice import, before AppState; bounded, no UI, no folder writes)

1. If sync is off: return. Σ is kept, and Turn On… later resumes with a same-group join (§4.6.10).
2. Identity check (§4.5).
3. Load Σ. If it is absent, unreadable or of a newer format: **joining**. The join runs after setup (§4.6.8).
4. **Trust checks.** Σ is trusted for capture only if all of these hold:
   - `SettingsSyncGeneration == Σ.generation`. If the defaults generation is lower, the preferences were rolled back (a Time Machine restore of Preferences, or a reinstall): join, dot-less. If it is higher, Σ is behind (a crash, or Σ restored alone): capture waits until the own file has been read and joined, in this launch or in the background check, and then runs.
   - `SettingsSyncLastSynced == Σ.legacy.lastSyncedSeen`, the **tripwire**. β1 writes that key on every push and apply, so a change means a pre-N build synced on this Mac: join, dot-less.
   - The identity did not change with differences (§4.5).
5. **Capture** (§4.6.2), only if Σ is trusted.
6. **Read**, at most about 1 s in total, on the file queue:
   - resolve the bookmark without mounting and list `Macs/`;
   - read only local, non-dataless files (`SF_DATALESS`, `ubiquitousItemDownloadingStatus`);
   - run the reuse check before joining each file;
   - on timeout, cancel the coordinators.

   This is today's `readForLaunch`, applied to a folder.
7. **Merge** what was read.
8. **Plan, then apply** every valid fast-forward, including those waiting from earlier sessions. If the folder is unreachable, they come from Σ alone (INV-9, S-35, S-36).
9. Persist Σ. After setup: the hint, a background check, and the pending join if any.

#### 4.6.7 While running

- **Triggers:**
  - an `NSFilePresenter` on `Macs/` (iCloud);
  - a `DispatchSource` or FSEvents on `Macs/` (other providers);
  - app activation, wake and opening Settings;
  - a 15-minute timer, and a 2-minute timer while the folder is on a network volume, where FSEvents does not see other computers' writes.

  Triggers are debounced by 2 s.
- **Then:** read in the background → reuse checks → merge on the main actor (`join(current Σ, fetched)`, never a replacement, so an edit made during the read is kept; S-65) → plan → hint → schedule relay or healing writes.
- A dataless file is skipped, and its download is requested. No decision ever waits for one.

#### 4.6.8 Join (Turn On…, Change…, first N launch, untrusted Σ)

A unit that is new to the unit table is joined on its own, through the plan (§4.6.3): its present local value is `pre`. Everything else in this section concerns a join with the whole folder.

1. **Read the whole folder.** Every listed device file must be read, or refused for a lasting reason (too large, wrong type, newer major).
   - While files are still downloading, the join **waits**. Settings shows "Reading the sync folder… (%d files not downloaded yet)" with **Cancel**.
   - Nothing is published or applied from the folder before the commit (INV-J1). The pending join is persisted, so it survives a relaunch.
   - Waiting is safe, because every provider eventually downloads while online, and SMB and Syncthing never present dataless files.
2. **Folder state F:** the join of the readable device files.
   - **Same group:** Σ trusted, and some device file belongs to a MacID in Σ's context. Then F also joins Σ.replica, and capture runs first, so only units changed on both sides become rows.
   - **Another group, or untrusted Σ:** local values are **dot-less**, with no capture. This fixes D3's contradiction with D3-S09 after a rollback. After the commit, the old group's entries of other Macs are dropped (D2).
3. **Legacy input L (founding only).** Only when `Macs/` holds no device file, `holzBar/Settings.plist` reads within the β1 limits, and its `deviceID` is not this Mac's own legacy ID:
   - L is its synced units, validated and normalized;
   - `modified`, `deviceID`, layout keys, learned keys, flags and local keys are ignored.

   If the legacy file was last written by this Mac itself, it is this Mac's own older state, and it is ignored (D1 §8.2).
4. **Preview per unit.** "No user value" means **the key is absent** from the persistent domain, never "equal to its default" (J1; D-6).

   | Local value | Folder (F, or L when founding) | Preview |
   |---|---|---|
   | equal to a folder value | any | Adopt: `applied :=` that entry's dots. A value from L becomes this Mac's entry. |
   | absent | has a value | Fast-forward after the commit (Restart) |
   | present | no value | Published as this Mac's entry, no question |
   | present and different | one value | **Row** |
   | present, equal to one of them | two or more values | Adopt that sibling's dots. After the commit this Mac takes part in a normal conflict, with Later (D2). |
   | present, equal to none | two or more values | **Row** listing every value, with a pop-up |
   | absent | two or more values | After the commit, a bystander conflict: no menu hint, and neither value applied |
5. **No rows:** commit (Σ.replica := F plus the new entries), publish and hint.
6. **Rows:** the hint reads **Choose Settings…**, and the join sheet offers **Use** (folder values, then relaunch), **Keep** (this Mac's values as fresh entries covering the shown dots) or **Cancel**.
   - Cancel writes nothing. Sync stays off after Turn On… or a first run. After Change…, the previous folder stays.
7. **Commit:** records the folder, the legacy digest and `SettingsSyncLastSynced` as seen. `join := none`.

**Two Macs founding at the same time** both publish. Equal values collapse; different values become one ordinary conflict.

#### 4.6.9 Answers

The sheet keeps `shown[u]`, the exact dots it displayed for each row.

| Answer | Per row u |
|---|---|
| **Use Settings from Sync Folder** | A new entry with a **fresh dot**, holding the folder's value and covering `shown[u]`. Then apply and relaunch. |
| **Keep This Mac's Settings** | A new entry with a fresh dot, holding this Mac's value and covering `shown[u]`. No relaunch, unless fast-forwards wait. |
| **Later** | Nothing is written. The siblings stay in Σ and in every file. The hint hides until the next launch, and the sheet never opens by itself. |
| **Cancel** (joins only) | Nothing is written. |

- **Fresh dots, not drops.** Two Macs answering at once then produce one new pair of siblings and one more question, and converge after any answer. Without fresh dots, two drops could cancel out.
- **An entry that arrived after the sheet opened** is not in `shown`. It survives and is decided anew (S-33, S-46). A row resolved elsewhere while the sheet is open is dropped with "Already decided on another Mac".
- **A row with three or more values** shows a pop-up listing each value with its display date, and no default. The bulk buttons stay disabled until every such row has a choice (J3: no clock-based pick).
- **Clash rows:**
  - Keep: the other Mac's hotkey gets this Mac's value for it, its old combination or none.
  - Use: this Mac's hotkey loses the combination, and the other one applies.
- **One answer settles the unit everywhere.** The other Mac gets a fast-forward, or nothing when its value was chosen.

#### 4.6.10 Turn Off, Change…, rollback, downgrade

- **Turn Off** stops all folder access, keeps Σ and hides the hint. Open siblings stay in Σ.
- **Turn On…** with a trusted Σ: capture once, then a same-group join. Only both-sided changes are asked, with Cancel.
- **Change… to an empty folder:** Σ.replica is published there, so the group moves with the user.
- **Change… to a folder holding another group:** a dot-less join, with Cancel keeping the old folder.
- **A Time Machine restore of the preferences only:** the generation check forces a dot-less join, so restored values are asked about and never published as new.
- **Σ restored alone:** the own file is joined first, and the counter floors hold.
- **A full home restore:** the group's newer values arrive as fast-forwards. Deliberate rollback goes through Export and Import, which are user writes.
- **N → β1 → N:** the β1 run never touches `Macs/` or Σ. It writes `SettingsSyncLastSynced`, so the tripwire forces a dot-less join on return.
- **N → β2 → N:** β2 is inert. Normalization makes its load-time re-encodes compare equal. Its user changes are real and are captured. The simulator keeps a β2 peer with its load-time writers to prove that INV-A5 holds.

### 4.7 The question and the status lines (`modal-alerts-1`: a quiet hint, a sheet only when clicked)

| State | Text (Settings → Advanced and the top of holzBar's menu) | Button | Strings |
|---|---|---|---|
| Fast-forwards wait | "Settings changed on another Mac" | Restart | existing |
| A conflict, clash or `pre` row of this Mac's | "Settings changed on another Mac" | Choose Settings… | existing |
| A join is reading the folder | "Reading the sync folder… (%d files not downloaded yet)" | Cancel | new |
| A join with rows | "Choose which settings this Mac uses" | Choose Settings… | new |
| A conflict between other Macs (Settings only) | "Your other Macs differ on %d settings" | Choose Settings… | new |
| Folder unavailable | "The sync folder cannot be found." | Change… | existing |
| A newer format seen | "A Mac uses a newer holzBar. Update holzBar to sync with it." | — | new |
| A legacy writer active | "A Mac with an older holzBar still uses this folder. Update holzBar there to sync with it." | — | new (D-3) |
| An oversize icon | "Your custom holzBar icon is too large to sync." | — | new |
| Refused files | "A sync file in the folder can't be read." | — | new |
| An unusable value | "A setting from a newer holzBar can't be used here." | — | new |

**The sheet:**
- **Placement:** on the Settings window, one at a time, with no default button (SA-07).
- **Title** (existing string): "Which settings should holzBar use?"
- **Body** (new strings):
  - running: "You changed these settings on this Mac, and they were changed differently on another Mac. Your other settings stay as they are on all your Macs.";
  - join: "These settings differ between this Mac and the sync folder."
- **Rows:** the existing setting label; **This Mac:** the value; **Sync folder:** the value and "changed on 3 Oct, 14:02". The date is the minting Mac's and is shown only.
  - Clash row: "⌘⇧H: Show Hidden Items (this Mac) · Search Menu Bar Items (another Mac)".
  - A row decided on another Mac while the sheet is open reads "Already decided on another Mac" (new string) and is left out of the answer.
  - The other Mac is never named (privacy).
- **Footer** (new string): "Using the sync folder's settings restarts holzBar."
- **Buttons** (existing strings): **Use Settings from Sync Folder**, **Keep This Mac's Settings**, and **Later** (or **Cancel** when joining).

**The Advanced-pane annotation** replaces "keeps layout, profiles, hotkeys and appearance the same" with: "Keeps your hotkeys, appearance and other settings the same on all your Macs through a folder they sync: iCloud Drive, Nextcloud, Dropbox, OneDrive, Syncthing or a network share. The menu bar arrangement and layout profiles stay on each Mac. holzBar never goes online. Changes from another Mac apply after a restart."

Every new string needs en, de (Swiss spelling), fr, it and rm, and `.github/scripts/strings-check.py` must pass.

### 4.8 Migration and β1 coexistence

**The boundary:**
1. N never writes or deletes `holzBar/Settings.plist`.
2. N never writes or deletes `SettingsSyncLastSynced`. β1 needs it after a downgrade, and N uses it as the tripwire (D2 deleted it, which made a downgraded β1 Mac re-apply a stale file).
3. N reads the legacy file only to found a group (§4.6.8 step 3). After that, it reads only its metadata, to show the status line.

**What a β1 Mac sees:**
- β1 keeps syncing with other β1 Macs through the old file, with β1's known behaviour.
- It never reads `Macs/`. N's writes inside `Macs/` reach β1's presenter as subitem changes; β1 re-reads `Settings.plist`, finds nothing newer and does nothing (`checkForNewerSettings`). Writes inside `Macs/` do not fire β1's vnode source on `holzBar/`.

| Coming from | First N launch |
|---|---|
| β1 or 0.0.6, sync on | The uid-bound hash mismatches once, so the MacID rotates and the old ID is kept locally. No Σ, so the Mac is joining. After setup: if `Macs/` is empty, it founds, with the legacy file as input unless that file is this Mac's own; otherwise it joins the group. Equal values commit silently; differing present values go into the join sheet. Nothing from the folder is applied in this launch. |
| β2 (paused) | As β1. Settings changed during the pause are present values: asked about where they differ, published where they are the only value. |
| Unreleased SA05 or sync-fix builds | As β1. Their keys and file fields are ignored, never used as evidence (INV-B6), and left in place for downgrade safety. |
| Sync off on the old build | Nothing until Turn On…, which is a join. |
| Fresh install | Turn On… is a join: absent keys take the folder's values (Restart) and get no question. |
| 0.0.5 and earlier (`holzIce/`) | Never read. |

**Status line** (D-3). It shows when the legacy file's `(modified, deviceID)` digest changes after this Mac founded or joined, and the writer is not this Mac's legacy ID. It clears 30 days after the last change.

**Release notes:** "Update holzBar on every Mac that syncs. Macs on 0.0.7-beta1 (or 0.0.6) and Macs on this version do not sync with each other. Nothing is lost: when you update a Mac, holzBar compares its settings with the folder and asks where they differ. The menu bar arrangement and layout profiles now stay on each Mac."

**A later Mac may be asked once about settings another Mac changed meanwhile.** D2's `legacyBase`, which adopts silently when a value equals the founding value, is *not* used. Its equality test silently overrides a β1 user's A→B→A return (J3, R-EVID-1). One bounded sheet per updated Mac is the price, and it covers INV-C3.

### 4.9 Companion changes outside the engine ("fix before coding")

Each item is a precondition for capture by diff (INV-A5, INV-A6). It lands in the same phase before the pause switch flips.

1. **`HotkeysSettings.loadInitialState`:** drop a duplicate at registration only, and never write the dictionary back (lines 106–111). This was the only automatic writer of a different value that D3 found.
2. **No model writes on load.**
   - `GeneralSettings.loadInitialState` assigns through `ifPresent`, which triggers `didSet` → `Defaults.set` for every present key, clamps `ItemSpacingOffset` and `RehideInterval` (lines 189–195), and re-encodes `holzBarIcon` (lines 35–46, 214–216).
   - `MenuBarSpacers.performSetup` clamps and writes through `didSet` (lines 37–46).
   - `MenuBarAppearanceManager.loadInitialState` re-encodes through `didSet` (lines 15–20, 111–119). The decoder fills missing fields from defaults and drops unknown ones (`MenuBarAppearanceConfigurationV2.swift` lines 79–92).
   - `MenuBarItemGroups.performSetup` re-encodes through `didSet` → `save()` (lines 52–57, 72–97).
   - The fix: load without saving (a loading flag or direct backing storage). Clamp when the value is used, never by rewriting storage.
3. **Normalizers in Core** for every JSON and data unit: the model's decode, range rules and canonical encode. The capture and plan comparisons use them (§4.6.2).
4. **Item re-key paths** use the alias rule: `ItemIconStore.setChoice` (lines 70–86) removes the old key and writes the new identity key; `ItemChangeWatcher.setRevealedOnChange` (lines 84–96) filters by `storedIdentityKey`; the OpenItem hotkey re-key; group membership. Each publishes the new key's value and never a deletion of the old key.
5. **`LayoutProfiles.saveCurrentLayout`** records only the running generation's part, and keeps the other part of an existing profile of the same name. Today line 130 copies `MacOS27Layout` on every OS. This is local correctness, and a precondition for Phase 2.
6. **Remove** `SettingsSync.userChangedLayout()` and its calls (`SectionRestore.saveSections` line 64, `Concealer27`, `LayoutProfiles`, the import), and the layout-edit counter.
7. **Lints in CI:**
   - every `Defaults.set` or `removeObject` of a synced key outside the allowed sites is flagged;
   - no `FileManager` or `NSFileCoordinator` in main-actor sync code (INV-R1);
   - no `Dictionary` or `Set` iteration without sorting in `holzBar/Core/Sync/` (determinism).
8. **Recommended, can be split out: the F-59 per-entry readers** (`ItemIconStore`, `HotkeysSettings`, `LayoutProfiles`, `MenuBarItemGroups`, `SectionRestore`, `Concealer27`). Sync already never spreads a loss, because values are validated per entry at apply and passed through.
9. **Optional local repair:** on macOS 26, `MacOS27LayoutSeeded == true` with an empty `MacOS27Layout` is a β1 OR-merge artifact that would stop seeding after an upgrade. Clear it once.

### 4.10 Grafted ideas, and where they come from

| Idea | Source | Why it is in |
|---|---|---|
| Settings-only scope; learned keys, flags and profiles local | D3 | Removes RC-4 to RC-6 and the macOS 26 attribution from Phase 1. The learned-key analysis was confirmed in the code (Appendix A, items 5–7). |
| Capture by diff, generation check, tripwire, clash rows, nested encoding, bystander rule, "absent = no user value" | D3 (absence also D2) | Catches every user path. Detects rollbacks and downgrades. Avoids D1-Q4's pause-gap revert. |
| Single-writer replica files, dots, multi-value registers, the applied-context rule, answers with fresh dots | D1 (A3 design C) | Removes RC-1, RC-2, RC-5, RC-8 and RC-9 by construction. |
| Format versioning (`format`, `minor`, `unitTable`) and pass-through of unknown namespaces | D1 §2.3, §3.3 | Phase 2 is additive, with no migration. |
| Identity bound to hardware and uid, and the own-file rules | D1 §5.10, D3 §5.1 | Closes CopyAccount and dot collisions. |
| Counter high-water mark in Caches | D2 §3.1 | Survives a full home restore. |
| Reuse check on unpublished own dots before any join | J3, refining D1's own-dot verification | Closes J3's dot-reuse hole without false collisions after legitimate supersession. |
| Rollback joins are dot-less; never commit with unread files; never overwrite an unread own file | J1, J3 | Fix the D3 contradictions found by the judges. |
| Normalization before comparing; no model writes on load; new unit keys for format changes | J1, J3, D1 §2.2 | Prevent version skew from minting false user changes. |
| Alias rule for re-keyed item units | J1, J2 | D3's re-key deletions. |
| Pop-up for rows with three or more values | J3, D1 §6.2 | No clock decides a value. |
| For Phase 2: the hit test at mouse-down and `.uncertain` instead of guessing | D2 §7.2 | The judges' preferred macOS 26 capture. D2's "exactly one item changed" fallback is dropped, because Live Activity moves break it. |
| No `legacyBase`; no automatic cleanup in Phase 1 | J3, J1 | Equality must never permit an overwrite. The wall-clock horizon is unsafe. |
| D2's shared file, healing, "Replace…" and the iCloud gate | rejected | Lost updates by construction; one bad file blocks every Mac. |

### 4.11 How each root cause and each ambiguous history pair disappears

| A1 | In the recommended design |
|---|---|
| RC-1 lost update | Gone: one writer per file, and a join that only adds |
| RC-2 clocks | Gone: per-Mac counters; dates for display only |
| RC-3 file lifecycle | Reduced to latency. Restored or old files are dominated. Deleted files are healed by their owner and relayed by the others. Unreadable files are never treated as missing. Dataless files are fetched later. |
| RC-4 two layouts in one file; remove-missing | Gone: layouts are local, and the legacy file is never written |
| RC-5 provenance from digests and absence | Gone: dots per entry; seen = context, taken in = applied; a lost Σ means a join |
| RC-6 automatic vs user | Gone with the layouts, plus §4.9 for load-time writers and re-keys, guarded by INV-A5 and INV-A6 and a lint |
| RC-7 old peers | Behind the boundary. Downgrades and rollbacks are detected and turn into joins. |
| RC-8 answer scope | Gone: per-unit rows; answers cover exactly the shown dots |
| RC-9 races and bookkeeping | Gone: one atomic Σ, persisted before writes; merges are joined into the current state |
| RC-10 identity, I/O, content | F-38 with uid, nonce and reuse checks. The F-15 and F-18 code is kept. Per-entry validation with pass-through. Per-unit caps and a writer check (F-61). |
| RC-11 verification | §5: the real Core in a simulator with ground truth, control engines that prove the oracles see failures, and mutation and real-Mac gates |

**The nine pairs:**
- **1 and 4:** β1 writes are not input after founding, and layouts are local.
- **2:** there is no shared file, so an empty `Macs/` needs no interpretation.
- **3:** a new change has a dot that the context does not cover; a restored file has only covered dots.
- **5:** there are no kept records.
- **6 and 7:** layouts are local.
- **8:** `applied` is the taken-in fact.
- **9:** every change has a new dot, and counters never repeat.

**C1–C5 vanish:** N never writes what β1 applies, and files have single writers.

### 4.12 Residual risks and their guards

| Risk | Guard |
|---|---|
| A future automatic writer of a synced key | The lint; INV-A5 in the simulator, with a rogue-writer mutation that must fail it; `SyncAttribution.automatic` for migrations |
| A JSON unit gains a field | A new unit key (table version). Older Macs relay the new unit and keep the old one. |
| A full home restore, clock set back, folder unreadable, and an edit | The counter floors (Caches, mirror); the reuse check before any join; units become `pre` and nothing is dropped |
| A join waits for a file that never downloads | A status line with Cancel. In practice it only happens while offline. |
| Item-keyed settings do not match on another Mac (title-changing apps, macOS 26 vs 27 keys) | The alias rule. Nothing is lost; the setting applies wherever its key matches (documented, as today). |
| A hostile folder writer | Bounded parsing, links refused, plain file names only (R-SEC-3), values within the schema. A valid forged file can supersede values, as any folder writer can today (out of scope without keys). |
| Mixed fleets during the rollout | The boundary, the status line, release notes, and the join sheet when a Mac updates |
| Real-provider behaviour (presenter events, dataless downloads, SMB) | The two-Mac test on iCloud Drive with Optimize Storage, Dropbox or OneDrive, and SMB (§7.5) |

### 4.13 Phase 2: the arrangement as an opt-in (a separate phase, later)

**Gates before it starts:**
- (a) Phase 1 passed the real-Mac matrix on iCloud, Dropbox or OneDrive, and SMB.
- (b) A real-Mac prototype of macOS 26 Command-drag attribution: a hit test at mouse-down against the item windows, with the mouse-down monitor running whenever layout sync is on. Its recorded traces must tell moves from displacements after wake, display changes, Live Activities and items that appear mid-drag. The traces become Core tests.

**Design:**
- Units `l26/<identityKey>` and `l27/<bundleID>`, authored only by their own generation and relayed by the other.
- Positional keys (`ns:#n`) stay local, because they can name different items on two Macs.
- An ambiguous drag gives `.uncertain`: protected and not published.
- Learned keys stay local.
- Profiles sync either per profile and generation, with bindings local, or as the Phase-15 bundle-ID format.
- `SectionRestore`'s new rules apply only while layout sync is on, or after a local regression suite has proven them for users who do not sync: a user save stores only the moved item, and automatic stores never overwrite intent.
- **Turning it on is a join for the layout namespace only:** existing entries are `pre`, and one sheet appears per Mac whose arrangement differs.
- The simulator gains layout events: user moves, displacement, settle windows and placements.

### 4.14 Cost (Phase 1, estimates)

| Part | Lines |
|---|---|
| Core: unit table, normalizers, validators, projection | 250 |
| Core: replica, join, capture, plan, apply plan, answers, join preview and commit | 400 |
| Core: codecs (device file, Σ, legacy input), identity, counters, reuse checks | 250 |
| App glue: file actor, state store, launch path, presenter and watchers | 400–500 |
| App glue: hint, sheet rows, clash rows, pop-up, status lines | 200–250 |
| Companion fixes (§4.9) | 150–250 |
| Profile export and import (D-4 a; Phase 15's plan) | about 300 |
| Tests: properties, simulator, oracles, catalogue, fuzzing, control engines | 2,000–2,800 |

The total is roughly 4,000–5,000 lines with tests; the simulator is the main investment. The code removed includes `SettingsSyncPolicy.decide` and its rules (717 lines), most of `SettingsSync.swift` (1,909) and every R-branch concept.

**Kept from the paused code:**
- `SettingsSyncFile.readContents`, `isUsableFolder` and `isLocal`;
- `SettingsSyncDevice`, with the uid added to the hash;
- `SettingsSyncLocation`;
- `SettingsSyncPause` (switched off at the end);
- `readForLaunch`;
- the presenter and watcher;
- the canonical digest;
- `SettingsBackup.apply(_:removesMissingKeys:)`, for Import;
- the F-14 run-loop helper.

---

## 5. Verification strategy: prove the design before app code exists

### 5.1 Principles

1. **Every decision is pure Core** (`holzBar/Core/Sync/`, Foundation-only, `nonisolated` value types). The app glue only executes I/O and UI effects and has no branches that change outcomes. The simulator and the app call **the same entry point**: `SyncEngine.handle(event, state) → (state, [Effect])`. This closes RC-11's "copied glue" gap.
2. **Ground truth belongs to the simulator,** never to the engine. Unique tokens and vector clocks over the event trace decide what is live, lost, concurrent or user-made.
3. **Determinism:**
   - all randomness comes from a seeded PRNG (SplitMix64 or xoshiro);
   - all time comes from a virtual clock, with no real concurrency;
   - the engine never depends on `Dictionary` or `Set` order, which is enforced by the lint;
   - each seed's trace has a hash, and a failing seed reproduces exactly.
4. **The oracles must be shown to see failures** (§5.6) before a green run means anything.

### 5.2 Code layout

```text
holzBar/Core/Sync/            target HolzBarCore (compiled by `swift test` and the app)
  SyncDot.swift  SyncReplica.swift  SyncUnits.swift  SyncDeviceFile.swift  SyncState.swift
  SyncIdentity.swift  SyncCapture.swift  SyncPlan.swift  SyncJoin.swift  SyncLaunch.swift
  SyncAnswer.swift  SyncLegacyInput.swift  SyncEngine.swift
Tests/HolzBarCoreTests/Sync/
  JoinLawsTests  CodecTests  UnitTableTests (R-CLASS-1)  CounterTests  CaptureTests  PlanTests ...
  Simulation/
    SimWorld  SimRandom  SimClock  SimEvents  SimGenerator
    SimProvider (+ presets)  SimFolderReplica
    SimMacN (executes SyncEngine effects)  SimMacBeta1 (A2 §2.6 literally)  SimMacBeta2
    GroundTruth  Oracles  Liveness  Metamorphic  Shrinker  ScenarioPrinter
    ControlEngines (LWW-by-clock, shared-file β1-style, no applied-context, unread-overwrite)
    Catalogue/ (A1 S-01…S-70 in settings form, A2 SC-xx, D3-S01…S20, J-01…J-16)
    SimulationTests (seed matrix; SYNC_SIM_SEEDS / SYNC_SIM_STEPS environment overrides)
```

### 5.3 The world model

**Macs:**
- **N:** the real engine, behind the simulator's effect executor.
- **β1:** A2 §2.6 literally:
  - it writes at launch and 5 s after any defaults change, automatic writes included, and never reads before writing;
  - it applies silently, with remove-missing, when `modified > lastSynced` and the file is at most 1 h in the future;
  - it drops unknown keys, sets `HasImportedIceSettings` and ignores files over 1 MiB.
- **β2:** inert towards the folder, but its users edit settings and its **load-time writers** run at launch: the hotkey write-back, clamps, re-encodes.
- **N-skew:** two N builds with different unit tables and an extra appearance field.

**Per-Mac state:**
- defaults (all keys, local ones included);
- Σ, which can be lost or restored;
- Caches (high-water);
- `hw`, `uid`, `gen ∈ {26, 27}`, the clock offset, `running`, `enabled` and `folder`.

**Provider** (A2 §6), with a per-Mac folder replica whose entries are `Present`, `Dataless`, `Partial` or `Absent`. Its operations:
- `Deliver`: heavy-tailed delay, offline periods, reordering across paths, coalescing per path, duplicates;
- `ConflictCopy`, with provider names, the computer name included;
- `LWW`;
- **iCloud per-device conflict winners** (J1);
- `Restore` of any earlier content;
- `Delete` of a file or of the whole folder;
- `Evict` to dataless;
- `ExposePartial`;
- `Stall`, finite or infinite;
- `Unmount` and `Mount`;
- `Foreign` bytes, including links, oversize files, truncation and type swaps.

**Presets:**
- **iCloud:** dataless, conflict versions with per-device winners, restores.
- **Dropbox and OneDrive:** File Provider dataless, named copies.
- **Nextcloud:** the conflict copy stays local.
- **Syncthing:** no dataless, `.sync-conflict` copies, replica rollback, days of lag.
- **SMB:** LWW, partial reads, unmount, polling only.
- **Hostile:** everything.

**Lifecycle and identity events:**
- `Launch`, `Quit`, and `Crash` after any effect, to test every persist boundary;
- `Enable`, `Disable` and `ChangeFolder`;
- `UpdateApp`: β1 → N, β2 → N, N → β1 → N, N → β2 → N and N1 → N2 → N1;
- `UpgradeOS` (26 → 27);
- `Clone` (new hardware) and `CopyAccount` (new uid);
- `RestorePrefs`, `RestoreΣ` and `RestoreHome` (defaults plus Σ, with Caches kept or lost);
- `ΣLost` and `Reinstall`;
- `ClockStep` of ±1 day, with offsets up to ±7 days.

**User events:**
- setting edits with unique token values;
- reset or delete;
- Import with remove-missing;
- hotkey assignments from a small combination pool, to provoke clashes;
- item-icon choices on title-changing apps, to provoke re-keys;
- an oversize icon;
- Turn On, Turn Off, Change… and relaunch;
- answers (Use, Keep, Later, Cancel, pop-up picks), chosen adversarially, and exhaustively in exhaustive mode.

**Automatic events:** placements, learning, flags, and β2 load-time writes. In Phase 1 these touch only local keys, by construction. INV-A1 and INV-A5 keep it that way.

### 5.4 Ground truth and oracles

- **Tokens.** Every user change writes `u<k>@<unit>`; automatic writes are `auto-<mac>-<k>`; defaults are ⊥. Values present before a Mac's first N run are `pre(m)`.
- **Causality.** A vector-clock tracker over program order and file-ingest edges computes `Past(V)`, the *seen* past and the *applied* past, liveness, global loss and the per-unit Conflict.
- **What the engine exposes:** `claimedPast` (its decoded context) for INV-S3(b), and its origin labels for INV-A4.
- **Safety oracles** run after every step (§2.2). **Liveness oracles** run after a drain:
  - no user events;
  - deliver everything;
  - launch every Mac until quiescent;
  - answer every prompt (Use or Keep, with Later allowed finitely often);
  - then check C1–C6, including a fresh Mac's join.
- **Metamorphic pairs:**
  - with and without automatic events (INV-A1);
  - randomized clocks, modulo counter renaming (INV-F9);
  - permuted deliveries (INV-F2);
  - duplicated and coalesced deliveries (INV-F3);
  - inserted β2 or N-skew launches with no user events, which must mint no dot (INV-A5).

### 5.5 Exploration

- **Bounded exhaustive families:**
  - 2–3 Macs (both generations, optionally one β1 peer), 2 units, 2 values each;
  - an event alphabet per family: edits and answers; files (deliver, delete, restore, evict); identity (RestorePrefs, RestoreHome, CopyAccount, ClockStep, Crash);
  - depth 6–8, with visited-state hashing;
  - families must include RestorePrefs, ClockStep, Evict and CopyAccount (J3's gate).
- **Seeded random long runs:** 200–2,000 steps, per preset, interleaving every event kind.
- **Shrinking:** each failure is minimized by delta debugging over the event list, and printed as an A1-style scenario (Setup / Steps / Wrong / Must) plus a ready-to-paste Swift test.

### 5.6 Proving the simulator can see failures

1. **Control engines** must fail within a bounded number of seeds:
   - LWW by clock: INV-S1 and INV-F9;
   - a single shared file written β1-style by N Macs: INV-S1 and INV-S6;
   - the engine with the applied-context rule removed: INV-S1 and INV-S7;
   - an engine that overwrites an unread own file: INV-S6 and INV-S1g;
   - an engine that mints at launch for an untrusted Σ: INV-S2;
   - an engine with "equal to default = unset": the pause-gap revert.

   If a control engine survives, the generator or the oracles are too weak, and the gate fails.
2. **Mutation gate** (R-TEST-5). A scripted list of guard mutations in `holzBar/Core/Sync/` is applied with `sed` patches and run through `swift test --filter Sync`, following the sync-fix precedent: remove the applied filter, `≥` → `>` in `covers`, skip the reuse check, skip the generation check, treat unreadable as missing, drop pass-through, apply `localOnly` units, skip the clash check, commit a join with unread files. Every mutation must be killed by at least one test. A survivor is either a missing scenario or a dead guard, and it must be resolved.

### 5.7 Fixed tests (the catalogue)

- **A1 S-01 to S-70.**
  - The PASS scenarios are as written.
  - The SCOPE scenarios run in their settings form, with the layout keys asserted untouched.
  - The BOUNDARY scenarios run with a real β1 peer and assert that nothing is harmed on either side.
- **A2 SC-01 to SC-71**, where they apply.
- **D3-S01 to D3-S20**, including:
  - different settings merging;
  - three-way rows;
  - simultaneous answers;
  - bystanders;
  - the hotkey clash;
  - a retired Mac's file deleted while a fresh Mac still gets its values through relays;
  - downgrade;
  - rollback;
  - Σ restored;
  - CopyAccount;
  - a crash between apply and persist;
  - N+ pass-through;
  - the oversize icon;
  - founding with a β1 file;
  - `defaults write` while quit;
  - a Dropbox copy of the own file;
  - Turn Off with edits on both sides;
  - 70 Macs.
- **J-scenarios from the judges:**

  | ID | Scenario | Must |
  |---|---|---|
  | J-01 | A synced setting is set back to its default during β2, while the group has another value | Asked, never silently forced back (no D1-Q4 revert) |
  | J-02 | ⌘⇧H assigned to different actions on two Macs | A clash row; no hotkey silently dead; no Restart that never goes away |
  | J-03 | An N1 Mac and an N2 Mac (N2 has an extra appearance field) relaunch repeatedly | No dot, no hint, the field never stripped (INV-A5) |
  | J-04 | N → β2 (with load-time writers) → N | No dot from β2's writes; the user's β2 edits are captured |
  | J-05 | Preferences restored two weeks back, Σ intact and trusted otherwise | A dot-less join; restored values asked about, never published as new |
  | J-06 | Full home restore, clock set back below the old counters, folder unreadable, an edit, then the folder returns | The reuse check re-identifies; the edit becomes `pre` and is never dropped |
  | J-07 | A join where one listed file stays dataless | No commit; Cancel still writes nothing; the commit follows the download |
  | J-08 | The own file stays corrupt | Never overwritten; the Mac re-identifies and publishes under a new ID |
  | J-09 | An item-icon choice on a title-changing app re-keys `ns:Title` → `ns:#1` | No deletion published; the other Mac keeps its icon choice |
  | J-10 | Two installations collide under one ID on iCloud with per-device winners | A collision detected on both sides; nothing lost |
  | J-11 | A new item appears on both Macs | Each Mac places it by `NewItemsPlacement`; learned lists never merged |
  | J-12 | Three Macs change one setting differently | The pop-up row has no default; the bulk buttons stay disabled until a choice is made |
  | J-13 | An oversize icon on A, then a small icon on B | A keeps its icon (local-only, with a note); B's icon never overwrites it |
  | J-14 | Two Macs found the group at the same moment | Equal values collapse; one question for each differing unit |
  | J-15 | A copied account on the same Mac | The uid-bound hash differs; distinct IDs; both sync |
  | J-16 | A β1 Mac rewrites `Settings.plist` 100 times | No hint or question on N Macs; the status line only |

### 5.8 Fuzzing and lints

- **Codec fuzzing** (device file, Σ, legacy input) with arbitrary bytes, truncations, type swaps and oversize collections. It must not crash or hang. Refused files are never partly merged, and no value outside the schema is ever applied.
- **The CI lints of §4.9 item 7,** plus R-CLASS-1 (every `Defaults.Key` has a class).

### 5.9 Budgets and gate criteria

- **In CI** (part of the existing required `test` check), at most about 3 minutes:
  - every fixed test;
  - every control engine caught;
  - about 1,000 seeded runs per preset;
  - the exhaustive families at reduced depth;
  - fuzzing with 10,000 inputs.
- **Locally, before the simulator gate** (`swift test` works on this Mac without Xcode):
  - at least 10,000 runs per preset, with 0 violations;
  - the exhaustive families at full depth;
  - fuzzing with 1,000,000 inputs;
  - the full mutation gate.
- Every violation found is minimized and added to the catalogue before it is fixed.

---

## 6. Decisions for the maintainer

### 6.1 The four questions in `SYNC-REDESIGN-DECISIONS.json`

| # | Question | Options (recommended first) | Why the recommendation |
|---|---|---|---|
| **D-1** | Keep syncing the menu bar arrangement? | (a) Settings only now; the arrangement later as an opt-in Phase 2. (b) Settings only, for good. (c) The arrangement right away (D1). | All six rounds failed on the arrangement. The macOS 26 drag hook does not exist for most users (Appendix A, item 9). (a) delivers what `sync-1` asked for settings now, keeps the door open, and costs about half of (c). The maintainer was offered this on 2026-10-06 and chose to pause first, so it needs an explicit yes. |
| **D-2** | Two Macs changed *different* settings | (a) Merge per setting; ask only when the same setting changed differently; the rest keeps syncing while a question waits. (b) Ask once for all, as `sync-1` literally says, computed from per-unit dots. | (a) overwrites nothing and asks on every real conflict. The rejected "Pro Einstellung zusammenführen" never asked at all. (b) is equally safe, but every answer discards the other Mac's unrelated change. Publishing while a question waits is safe by construction (single-writer files, the applied-context rule), so `sync-1`'s and `modal-alerts-1`'s "pushes stay paused" is no longer needed in either mode. |
| **D-3** | Macs still on β1 during the rollout | (a) Two groups, with a status line plus release notes. (b) Two groups, release notes only. (c) Also write the old file (not safe). | Every design shares the boundary. (c) brings back A1 §5.4 C1–C5: β1 applies silently and removes missing keys. |
| **D-4** | How profiles move between Macs in Phase 1 | (a) Profile export and import as a file (the planned Phase 15 format: bundle ID → section; works on macOS 26 and 27). (b) Also "Share with Your Other Macs" through the folder (D3 P1). (c) Stay local until Phase 2. | (a) has the least code, no conflicts and no bindings travelling, and it is already planned. (b) adds about 300 lines and new strings, and needs a two-Mac test. |

### 6.2 Defaults the plan assumes unless the maintainer objects

| # | Point | Default | Alternative |
|---|---|---|---|
| D-5 | Learned keys and one-time flags | **Local** (Appendix A, items 5–7; A2 INV-K3) | Union and OR, as `sync-1` said. That breaks new-item placement and re-keys items. |
| D-6 | "No user value" at a join | **The key is absent** | Absent or equal to its default: D1-Q4's pause-gap revert |
| D-7 | A custom icon over 256 KiB | **Stays on its Mac with a note**; choosing it again stores a small PNG that syncs | Convert once at the first launch, which changes the user's data unasked |
| D-8 | Rows with three or more values | **A pop-up per row with no default** | The newest display date proposed (clock-based) |
| D-9 | Files of Macs no longer used | **Never deleted automatically in Phase 1** | Delete when dominated and 180 days old (the writer's wall clock, unsafe) |
| D-10 | Bystander conflicts | **A Settings line only, answerable there** | A menu hint on every Mac (INV-P1 false question) |
| D-11 | Naming the other Mac in the sheet | **Dates only** | A user-chosen label stored in the folder |
| D-12 | Mixed founding from the β1 file | **Compare once when founding; ignore it when it is this Mac's own** | Ignore it entirely, so a new group starts from this Mac |

**Departures from recorded decisions, all safe and listed for the docs:**
- per-unit merge (D-2);
- publishing while a question waits;
- learned keys and flags local;
- a re-enabled or cloned Mac keeps its replica and asks only about real conflicts;
- the hardware hash also binds the user account;
- a missing write is no longer a reason to ask, because it can no longer cause a loss (S-32, S-39, S-40, S-52).

---

## 7. GSD phase outline (0.0.7-beta3)

### 7.1 Setup

1. On branch `planning/sync-redesign`, copy this file and `SYNC-REDESIGN-DECISIONS.json` into `.planning/research/sync-redesign/`, and record the four answers, plus any objection to the §6.2 defaults, in `.planning/research/sync-redesign/DECISIONS.md`.
2. `/gsd-phase` adds **"Settings sync redesign (settings-only, per-Mac causal replicas)"** before the 0.0.7-beta3 release. The number is assigned by the command; the roadmap's last phase is 27.
3. `/gsd-spec-phase` writes SPEC.md (§7.2). `/gsd-plan-phase` writes the plans (§7.3). Optionally, `/gsd-plan-review-convergence` gets a cross-AI review of the plans.
4. `/gsd-execute-phase` runs the waves; `/gsd-code-review` with an adversarial reviewer and a skeptic per change (handoff anti-pattern); `/gsd-verify-work` for the two-Mac UAT; `/gsd-ship` opens one PR, because `main` is protected and needs 8 required checks.

### 7.2 SPEC contents (acceptance-level)

- Scope: the unit table v1 and the local keys (§4.2).
- The invariant table with the A2 amendments (§2).
- The format, Σ, identity and counter rules (§4.3–4.5).
- The algorithms as normative pseudocode (§4.6).
- The UI states and strings (§4.7).
- The migration and boundary rules (§4.8).
- The companion changes (§4.9).
- The verification gates (§5.9).
- The two-Mac script (§7.5).
- Out of scope: layout sync (Phase 2), D2's mechanisms, `legacyBase`, automatic cleanup.
- **Done means:** G1–G3 passed, `SettingsSyncPause.isPaused == false` with its test updated, and the docs updated.

### 7.3 Plans and waves (one PR branch)

| Wave | Plan | Content | Depends on |
|---|---|---|---|
| 1 | **S-01 Core model** | Dot, Context, Entry, Replica, join; device-file and Σ codecs with structural checks and pass-through; unit table v1, normalizers, validators, caps and the R-CLASS-1 test; counter and identity functions. Property tests: join laws, codec round trip, pass-through, counter monotonicity under clock steps and restores. | decisions |
| 1 | **S-02 Simulator harness** | World, PRNG, clock, provider with presets (iCloud per-device winners included), folder replicas, β1 and β2 peers, ground-truth tracker, oracle framework, shrinker, scenario printer, control engines. It is proven against the control engines before S-03 lands. | decisions |
| 2 | **S-03 Engine** | Capture (trusted Σ, normalization, alias rule, localOnly), plan (clash, bystander, `pre`), apply plan, write rules, launch, while-running checks, join (founding, same group, other group, dot-less rollback, unread-file wait), answers, identity events, reuse checks; `SyncEngine.handle`, wired into the simulator. | S-01, S-02 |
| 2 | **S-04 Companion fixes** (app code, no sync behaviour) | §4.9 items 1–7 (item 8 if in scope); the lint scripts; the local app type check (`swiftc -emit-sil` against the CLT macOS 26.5 SDK); SwiftLint strict. | decisions |
| 2–3 | **S-05 Catalogue and exploration** | A1, A2, D3 and J scenarios as fixed tests; exhaustive families; metamorphic pairs; mutation-gate script; fuzzing. | S-03 |
| — | **Gate G1 (simulator gate)** | §5.9 local criteria: all control engines caught; 0 violations; mutation gate fully killed; determinism verified. **No app sync code before G1.** | S-05 |
| 3 | **S-06 App glue** | File actor (list, read, write, dataless, coordinated writes, presenter, FSEvents, timers); state store (Σ, generation, counter mirrors, Caches high-water); defaults adapter; launch integration in `AppDelegate.init`; hint, status lines, sheet (rows, clash rows, pop-up, Cancel); strings in five languages; removal of `SettingsSyncPolicy.decide` and the old exchange paths; the main-thread I/O lint. | G1, S-04 |
| 3 | **S-07 Profile export and import** (if D-4 a) | Phase 15's 15-01 to 15-03, reduced to a file only. | S-04 |
| 4 | **S-08 Release prep** | `docs/features.md` sync section rewritten, `docs/privacy-and-permissions.md`, README and `docs/comparison.md` ("settings sync"), release notes for 0.0.7-beta3 (the β1 split, the first-sync question, what syncs); `SettingsSyncPause.isPaused = false` and its test; full review. | S-06, S-07 |
| — | **Gate G2** | CI green (build, test, former-name, no-network, strings, workflows, compat macos-26 and xcode-27); `strings-check.py` and `privacy-check.py`; lints; the adversarial review resolved; the mutation gate re-run on the final code. | S-08 |
| — | **Gate G3** | The two-Mac UAT (§7.5) by the maintainer, recorded in the phase's UAT.md. | G2 |
| — | **Release** | 0.0.7-beta3; the tag is created by an admin. | G3 |

Sync stays paused in every build until G1 to G3 pass. If G3 finds a defect, its trace becomes a simulator scenario before the fix (RC-11).

### 7.4 Gate summary

- **G0:** decisions recorded; SPEC approved.
- **G1:** the simulator proves the engine; no app glue before it.
- **G2:** CI and review.
- **G3:** real Macs.
- **G4:** release.
- **Phase 2** starts only after G3 plus the attribution prototype (§4.13).

### 7.5 Two-Mac manual test script (maintainer)

**Setup:**
- Mac A runs macOS 26, Mac B runs macOS 27, both on 0.0.7-beta3.
- First run Settings → Advanced → **Export…** on both Macs, as a backup.
- Run the full script on **iCloud Drive with "Optimize Mac Storage" on**. Repeat T1–T6 and T9–T10 on **Dropbox or OneDrive**, and T1, T3 and T12 on an **SMB share**, if one is available.
- For each test, note pass or fail, a screenshot of the hint or sheet, and the listing of `holzBar/Macs/`.

| # | Steps | Expected |
|---|---|---|
| T1 Join, equal | Turn On… on A with a fresh folder, then on B, with the same settings on both | No question on either Mac. `holzBar/Macs/` holds two files. `Settings.plist` is never created or changed by β3. |
| T2 Join, different | On B: Turn Off sync, change two settings, quit holzBar, and delete B's local sync state `~/Library/Application Support/holzBar/Sync/` (what a new Mac or a reinstall looks like). Start holzBar, then Turn On… with the same folder. | The sheet lists exactly those two settings with both values. **Cancel** writes nothing (the file dates in `Macs/` are unchanged) and sync stays off. Repeat with **Use** (B relaunches with A's values), and once with **Keep** (A shows Restart and gets B's values). With Σ kept instead, the same steps would merge B's two one-sided changes without a question (see T14). |
| T3 One-sided change | Change "Show on hover" on A | B shows "Settings changed on another Mac" with **Restart**, and has the value after the restart. Then relaunch both Macs five times: no hint and no new file dates. |
| T4 Different settings while offline | Wi-Fi off on both Macs. A changes "Show on hover", B changes the rehide interval. Wi-Fi back on. | Both Macs end with both changes and no question (if D-2 a). |
| T5 Same setting while offline | Wi-Fi off. A sets "Show on hover" on, B sets it off. Online again. | **Choose Settings…** on both Macs, with the sheet showing one row. Answer on A: the question disappears on B, which gets Restart or nothing. |
| T6 Later | Repeat T5's setup, but first choose **Later** on B; then change another setting on B; relaunch B | The other setting syncs to A. After the relaunch, B's hint is back. Nothing is lost. |
| T7 Hotkey clash | Offline: A gives ⌘⇧H to "Show hidden items", B gives it to "Search menu bar items". Online. | A clash row. After an answer, exactly one action has ⌘⇧H on both Macs, and no hotkey is silently dead. |
| T8 Arrangement and profiles stay local | Command-drag items on A; save a profile on A; start an app that adds a menu bar item on both Macs | B's arrangement and profiles do not change. The new item is placed on each Mac by "New items" there. No hint anywhere. |
| T9 Online-only at login | On B in Finder, remove the download of A's file (right-click → Remove Download); log out, Wi-Fi off, log in | holzBar's icon appears at once (launch waits at most about 1 s). After Wi-Fi returns, the file downloads and any change arrives with Restart. |
| T10 Deleted folder | Delete `holzBar/Macs/` in Finder | Within a check (wake or activation helps), both files come back. No setting changes on either Mac. |
| T11 Restored old version | Save a copy of A's file outside the sync folder, change two settings on A, put the copy back over A's file | Nothing reverts on A or B, and A rewrites its file. |
| T12 Unmounted share (SMB) | Eject the share | "The sync folder cannot be found". Nothing is created under `/Volumes`. After mounting, sync resumes by itself. |
| T13 A Mac on 0.0.7-beta1 | Install 0.0.7-beta1 on B; change settings on A and on B; update B back to 0.0.7-beta3 | While B is on β1, nothing crosses in either direction, and A shows "A Mac with an older holzBar still uses this folder". β3 never writes `Settings.plist`; B on β1 behaves as β1 always did with that file. After B updates, the tripwire makes it join: a sheet for the settings that differ, and nothing is lost on either Mac. |
| T14 Turn Off and on | Turn sync off on A; change X and Y on A, and Y and Z on B; Turn On… on A | Only Y is asked about, with Cancel. X and Z merge. |
| T15 Oversize icon | Choose a large custom holzBar icon on A, then a different small icon on B | A shows the note "too large to sync". Every other setting still syncs, and B's icon never replaces A's. |
| T16 Import | Import… on A a file exported earlier | The synced settings arrive on B after Restart. The arrangement in the file changes only A. |

**Optional:** a Migration Assistant or clone test, if a spare Mac is available. The clone gets a new ID, and both Macs keep syncing.

### 7.6 Phase 2 outline (later, separate)

1. **Spike:** record real Command-drag traces on macOS 26 with displacement, wake, display changes, Live Activities and items that appear mid-drag. Build the mouse-down hit test and turn the traces into Core tests.
2. **Design gate:** the namespace and positional-key rules, profiles, the `SectionRestore` rules behind the opt-in, and the join for the layout namespace.
3. **Simulator extension:** layout events and their invariants (INV-L1–L6, A3, A4).
4. **App:** hooks only while "Also sync the menu bar arrangement" is on.
5. **Two-Mac UAT** with macOS 26 and 27, on the same providers.

---

## Appendix A. Code facts this plan relies on (re-checked on `planning/sync-redesign`, which equals `main` at 0.0.7-beta2)

1. **`holzBar/Settings/Models/HotkeysSettings.swift`:**
   - `loadInitialState` (line 56) drops hotkeys whose combination an earlier one uses, then writes the dictionary back with `Defaults.set` (lines 106–111). This is an automatic writer of a different value.
   - Observation of hotkeys starts only after loading (lines 44–53).
2. **`holzBar/Settings/Models/GeneralSettings.swift`:**
   - every setting saves itself in `didSet`, and `loadInitialState` (line 181) assigns present keys through `ifPresent`, so loading writes them back;
   - `ItemSpacingOffset` and `RehideInterval` are clamped on load (lines 189–195);
   - `holzBarIcon` is decoded and re-encoded through `didSet` (lines 35–46, 214–216).
3. **`holzBar/MenuBar/Spacers/MenuBarSpacers.swift`:** `performSetup` (line 37) clamps the stored width and count and writes them through `didSet` (lines 21–31, 40–43).
4. **Appearance and groups re-encode on load:**
   - `holzBar/MenuBar/Appearance/MenuBarAppearanceManager.swift`: `loadInitialState` assigns `configuration` (line 114), and its `didSet` re-encodes and writes (lines 15–20). `MenuBarAppearanceConfigurationV2.swift` fills missing fields with `decodeIfPresent … ?? default` and drops unknown ones (lines 79–92).
   - `holzBar/MenuBar/Groups/MenuBarItemGroups.swift`: `performSetup` assigns the decoded groups (line 78), and `didSet` → `save()` re-encodes them (lines 52–57, 94–97).
5. **`holzBar/MenuBar/MenuBarItems/SectionRestore.swift`:**
   - `isNew = storedKnown != nil && saved[key] == nil && !known.contains(key)` (line 252), with `known` from `KnownItemTags` (lines 242–243). A merged list would stop new-item placement for items another Mac has seen.
   - `saveSections` stores every cached item and calls `SettingsSync.userChangedLayout()` (lines 52–67).
6. **`holzBar/MenuBar/MacOS27/Concealer27.swift`:** `placeNewApplications` places only bundle IDs missing from `KnownApplications27` and the saved layout (lines 808–823).
7. **`holzBar/Core/ItemIdentity.swift`:** `storedKey(_:titleChangingOwners:)` maps a learned owner's keys to `owner:#1` (lines 99–110), and stored values are collapsed under the mapped key (lines 135–140).
8. **`holzBar/MenuBar/Profiles/LayoutProfiles.swift`:** `saveCurrentLayout` copies this Mac's `MacOS27Layout` into every profile on every OS (line 130).
9. **macOS 26 drag attribution:**
   - `holzBar/Core/InputMonitors.swift`: the mouse-dragged monitor runs only for "Show all sections on drag" or a custom appearance (lines 65–68); otherwise only the mouse-up monitor runs (lines 70–72).
   - `holzBar/Events/HIDEventManager.swift`: `handleMenuBarItemDragStart` is called only from the mouse-dragged monitor (lines 115–121). Without it, `handleArrangementEnd` only saves all sections on a Command-mouse-up (lines 502–514).
10. **`holzBar/MenuBar/MenuBarItems/ItemIconStore.swift`:** `setChoice` removes the old stored key and writes the current identity key (lines 70–86): a re-key.
11. **`holzBar/MenuBar/MenuBarItems/ItemChangeWatcher.swift`:** `setRevealedOnChange` filters by `storedIdentityKey` and writes the current identity key (lines 84–96): a re-key.
12. **`holzBar/Core/SettingsSyncPause.swift`:** `isPaused = true`, with the single gate `isActive()`. The test package (`Package.swift`) compiles `holzBar/Core` as `HolzBarCore`, with `Tests/HolzBarCoreTests`, Swift 6 and main-actor default isolation, so new Core sync types should be `nonisolated` value types.
13. **β1 (`v0.0.7-beta1`):**
    - `SettingsSyncFile.newerSettings` accepts `modified > lastSynced`, at most 1 h ahead, from another device (lines 46–63);
    - `SettingsSync.pullIfNeeded` applies with `SettingsBackup.apply` and sets `SettingsSyncLastSynced` (lines 417–427);
    - a `DispatchSource` on `holzBar/` watches `.write`, `.rename`, `.delete` and `.link` (lines 474–476);
    - a presenter handles `presentedSubitemDidChange` (line 526).

## Appendix B. Phase 1 against the A1 catalogue (summary)

This is D3's walk with the judges' fixes: **33 PASS, 27 SCOPE, 10 BOUNDARY, and no safety clause fails.**

**Changes against D3's own walk:**
- **S-62** (pause gap, settings form): now holds for values set back to their default, because "no user value" means absent (J-01).
- **S-05 and S-35:** hold by "nothing written supersedes a waiting entry" instead of "no push".
- **S-06:** keeps the replica instead of clearing the state.
- **S-32, S-39, S-40 and S-52:** need fewer questions, because a missing write can no longer cause a loss.
- **The SCOPE clauses** (S-08, S-15–S-17, S-29, S-31, S-37, S-38, S-40–S-42, S-45, S-47–S-49, S-51, S-52, S-56–S-62, S-64, S-67, S-69) are layout propagation. They are waived by D-1 (a) and return in Phase 2.
- **The BOUNDARY scenarios** (S-18–S-27) hold because N never shares a file with β1. The only thing waived is that changes do not cross between β1 and N, and the user sees that limitation.
