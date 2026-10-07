# D1 · Settings sync with one file per Mac, dotted multi-value registers and a lattice merge

Design option 1 for the holzBar settings-sync redesign. Written 2026-10-07, read-only: nothing in the repository or its git state was changed.

**Inputs:** `A1-failure-taxonomy.md` (root causes RC-1 to RC-11, invariants INV-1 to INV-16, scenarios S-01 to S-70), `A2-requirements-invariants.md` (requirements R-…, invariants INV-S/A/L/K/P/C/ID/Z/F/B/R/PR, open questions OQ-1 to OQ-14), `A3-research.md` (techniques, providers, macOS APIs, design C), the decisions `sync-1.md` and `modal-alerts-1.md`, and the code at `audit/remediation-2026-10-05` (`SettingsSync*.swift`, `SectionRestore.swift`, `Concealer27.swift`, `LayoutProfiles.swift`, `HIDEventManager.swift`, `LayoutBarPaddingView.swift`) and at `v0.0.7-beta1` (`SettingsSync.swift`).

**Terms:** β1 = 0.0.7-beta1 (and 0.0.6, same sync code), β2 = 0.0.7-beta2 (sync paused), N = a Mac running this design. A *unit* is the smallest piece of state that is compared, merged and asked about. *gen(m)* is the layout generation of Mac m: g26 (macOS 26 and earlier, key `ItemSections`) or g27 (macOS 27, key `MacOS27Layout`).

---

## 0. Summary

1. **Each Mac writes exactly one file, `holzBar/Macs/<MacID>.plist`, and nothing else in the folder.** The file is a full replica of everything that Mac knows about the sync state. Every Mac reads every other Mac's file and merges them with a join that is commutative, associative and idempotent. No Mac ever replaces another Mac's data, so the lost update (RC-1) and every "write over a missing, restored or unusable file" defect (RC-3) are gone by construction.
2. **Every user value carries a *dot* `(MacID, counter)`; every file carries a version vector (its *context*) of all dots it has seen.** "Newer", "older", "already seen" and "concurrent" are facts read from dots, never from dates (RC-2, RC-5). Counters are compared only with the same Mac's counters, so clocks never decide anything.
3. **Each unit is a multi-value register.** Concurrent writes to the same unit with different values stay side by side as *siblings*. Siblings are the only source of a conflict question. A local write and an answer each supersede exactly the dots they observed (the *applied-context rule*), so an answer can never overwrite a value the user did not see (RC-8), and a change waiting for Restart can never be overwritten by this Mac's own later write (RC-9).
4. **Only the user's actions create dots.** holzBar's placements, macOS displacements, seeding, reconciliation, migrations and learned keys never do. They live in a local layer with lower priority than any user entry (RC-6). Layouts are per item: one unit per item and per macOS generation (`l26/<item>`, `l27/<bundleID>`). A Mac authors only its own generation's units and relays the other generation's untouched (RC-4). On macOS 26 the moved item is identified when the drag starts, not by comparing bar snapshots afterwards.
5. **β1 is handled by a hard boundary.** N never writes `holzBar/Settings.plist`. It reads it once, when it founds a new group in a folder that has one. β1 Macs and N Macs do not sync with each other until every Mac is updated. Nothing is lost on either side, and the user sees this as a status line and in the release notes (RC-7, A1 §5.4 C1–C5).
6. **Result of the walk in §13:** all 70 regression scenarios pass. 51 pass exactly as written. 13 meet their safety and outcome requirements with a documented difference in a literal detail: mostly "no question is needed", because a missing write can no longer cause a loss. 6 pass through the β1 boundary.
7. **Maintainer decisions this design needs (§14).**
   - Per-unit questions: changes to *different* settings on two Macs merge silently, and only the same setting changed differently is asked about. The letter of `sync-1` asks whenever both Macs changed anything. The data model supports both. The strict reading is one schema constant ("Mode G": all user settings form one unit).
   - Each Mac keeps publishing its own file while a question waits. This is safe by construction. `sync-1` and `modal-alerts-1` pause pushes.
   - One-time flags become local, and are no longer OR-merged.
   - β1 and N do not sync with each other.
   - Placements stay local.
8. **Cost.** About 1,700 lines of Foundation-only Core, about 800 lines of app glue and about 3,000 lines of tests, including a deterministic multi-Mac simulator. It replaces `SettingsSyncPolicy.swift` (717 lines) and most of `SettingsSync.swift` (1,909 lines). Each Mac's file is typically 30–80 KB and at most 1 MiB.

---

## 1. Architecture at a glance

```text
 Mac A (macOS 26, N)                         sync folder                              Mac C (macOS 27, N)
┌─────────────────────────────┐        <folder>/holzBar/                         ┌─────────────────────────────┐
│ UserDefaults  ◄── apply     │          ├─ Settings.plist   β1 only: never       │ UserDefaults  ◄── apply     │
│   (launch / Restart)        │          │                   written by N; read   │                             │
│ Sync state file (local)     │          │                   once when founding   │ Sync state file (local)     │
│   replica R_A               │ write  ──┼─► Macs/<A>.plist  (only A writes)  ──► │   replica R_C               │
│   applied dots, origins     │ own    ◄─┼── Macs/<C>.plist  (only C writes)  ◄── │   applied dots, origins     │
│   counter, MacID            │ file     │   Macs/<…>.plist                       │                             │
│ intent hooks (user moves)   │ read all └───────────────────────────────────────│ intent hooks                 │
└─────────────────────────────┘          merge = join(own replica, all files)    └─────────────────────────────┘
```

- **State layers on a Mac.**
  - *Applied intent* is the per-unit value that this Mac's `UserDefaults` reflects, with the dots it came from.
  - The *replica* is everything this Mac has seen: every live entry with its dot, and the context.
  - The *local layer* holds automatic placements and overrides, and is never published.
- **Flow.**
  - A user action creates a dot in the replica, is persisted, and is published.
  - A check reads the files, joins them into the replica, and classifies each unit: in sync, fast-forward, conflict, or relay only.
  - Fast-forwards are applied at launch, or through **Restart**. Conflicts become **Choose Settings…**.

---

## 2. Data model

### 2.1 Identity, dots and counters

| Item | Definition |
|---|---|
| `MacID` | A random UUID (v4). It is the only identity ever written to the folder and the name of the Mac's file. It is kept in `SettingsSyncDeviceID` (F-38 code path). |
| Identity binding (F-38, extended) | `SettingsSyncDeviceHash = SHA-256(salt ‖ hardwareUUID ‖ uid)`, with `salt` = `SettingsSyncDeviceSalt`. The hash, the salt and the UUID stay local. Adding the account's `uid` also splits two user accounts on one Mac that share copied preferences (A2 `CopyAccount`). If no hash is stored, the hash is stored and the ID is rotated once (`sync-1`). On a mismatch: new `MacID` (§5.10). |
| Dot | `(mac: MacID, counter: UInt64)`. Unique per write event. |
| Counter rule | `next = max(last + 1, ⌊unix seconds now⌋, maxSeenSelf + 1)`. `maxSeenSelf` is the largest `context[me]` or own dot seen in any file. Two more copies of `last` are kept: the state file and `SettingsSyncCounter` in `UserDefaults`. The larger of the two is used, so rolling back either one alone is harmless. The time floor makes counters survive a full state loss (the Syncthing rule). Counters are **never compared across Macs**, so clock skew and clock steps do not matter (INV-3, INV-F9). |
| Context | `[MacID: UInt64]`. `context[X] = n` means "every dot of X with counter ≤ n has been seen", either as a live entry or as superseded. It is causally closed because files are whole replicas (§2.3). |

**Why dots and a version vector rather than Lamport or HLC timestamps.**
- A Lamport or hybrid logical clock can *order* writes, but it cannot *detect* that two writes are concurrent. Last-writer-wins on such a clock silently drops one of two concurrent user changes, which violates "never overwrite silently" (A3 §4.4).
- Dots identify each write uniquely. Contexts tell exactly whether a write was seen. Together they give the multi-value register its siblings.

### 2.2 Units: the schema table (Core, versioned)

Every key in `Defaults.importableKinds` maps to exactly one class. A Core test fails if a new `Defaults.Key` has no class (R-CLASS-1).

| Class | Unit key(s) | Value | Notes |
|---|---|---|---|
| U scalar settings | `s/<DefaultsKey>`: one unit per key in A2 class U (e.g. `s/ShowOnHover`, `s/ItemSpacingOffset`, `s/NewItemsPlacement`, `s/SpacerCount`) | plist scalar or small array | "Reset to default" writes the default as a value |
| U per-entry dictionaries | `hk/<action>` (Hotkeys), `ii/<itemKey>` (ItemIcons choice) | `Data` / file name / `none` | Removing a hotkey or icon writes `none`. File names must be plain (R-SEC-3). |
| D data | `icon` (`IceIcon` + `CustomIceIconIsTemplate` as one unit), `app` (`MenuBarAppearanceConfigurationV2`), `grp` (`ItemGroups` JSON, capped on read, F-47), `rr` (`RevealRules`) | `Data` / JSON | The icon is stored once, as a PNG of at most 256 KB, converted when it is set (F-61). |
| PR profiles | `prof` (`LayoutProfiles` JSON, whole list) | JSON | Per-profile units are a later refinement (OQ-12). |
| LAY layout | `l26/<identityKey>` (from `ItemSections`), `l27/<bundleID>` (from `MacOS27Layout`) | section index 0/1/2, or `-1` = "user reset, let holzBar place it" | Per item. A Mac authors only `gen(m)`'s namespace (§7). |
| LRN learned | `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners` | grow-only sets, no dots | Union, capped deterministically (§5.1). Never a question, hint or restart. |
| Local (never synced) | `MacOS27LayoutSeeded`, `hasMigrated*`, `HasImportedIceSettings` (FLG); `CurrentLayoutProfile` (CTX); `MacOS27ClickRestoreDelay`, `MacOS27IceBarWaitsForRefresh` (TUNE); LEG keys; all LOC keys and every `SettingsSync…` key | n/a | Deviation from `sync-1`, which said to OR the flags: OR can skip a step this Mac still needs (A2 INV-K3, OQ-5). |

**Mode G** (the strict reading of `sync-1`, one constant): all U, D and PR keys form **one** unit, `settings`, whose value is the dictionary of all of them. Layout stays per item, and learned keys stay sets. Everything below holds unchanged. Only what counts as "the same unit" differs.

A unit key never changes format. If the value format of a key changes in a later release, it gets a new unit key, and every Mac converts its value locally and deterministically.

### 2.3 Entries, registers, replica

```swift
struct Dot: Hashable { let mac: MacID; let counter: UInt64 }
struct Entry {                      // one value written by one user action or answer
    let dot: Dot
    let value: CanonicalValue       // typed plist value; equality by canonical encoding (sorted keys)
    let raw: Data                   // the entry's original encoding, relayed byte for byte
}
struct Replica {                    // what a Mac holds and publishes
    var context: [MacID: UInt64]    // version vector of everything seen
    var units: [UnitKey: [Entry]]   // multi-value register per unit; usually one entry
    var sets: [LearnedKey: Set<String>]
}
```

- **Variant chosen: replica files, not own-writes files.** In the other variant, each file holds only the values its Mac wrote. That variant needs a separate superseded-set per entry, and it loses information when a departed Mac's file is deleted: an older value can come back for a Mac that joins later (A3 §4.1). Replica files make any single up-to-date file sufficient to rebuild the group state. They also make a departed Mac's file safe to delete once it is dominated (§5.9).
- **Absent means "no information".** A unit missing from a file never means deletion (INV-6, F-60). Deletions are values (`none`, the default, `-1`).
- **Pass-through.** Entries of unknown unit namespaces, values that fail validation here, and unknown fields of entries are all kept and relayed byte for byte. A Mac never drops an entry while advancing its context. Dropping it would make the other Macs read "seen and superseded" and delete it there: the CRDT form of F-59/F-60 (A3 §4.5 pitfall).

### 2.4 Provenance on this Mac (the local layer)

For every comparable unit (U, D, PR, and the layout units of `gen(m)`), the state records the origin of the **intent** value:

| Origin | Meaning | Published? | Remote single value differs | Siblings |
|---|---|---|---|---|
| `dotted` | The applied value came from entries with these dots: a user action here, an answer, or an adopted remote entry | yes (its entries are in the replica) | fast-forward | question |
| `default` | Never set, or equal to the schema default (U/D/PR keys; policy D1-Q4) | no | fast-forward (silent) | question |
| `auto` | Placed by holzBar or macOS (layout entries without intent) | no | fast-forward (silent): user intent beats placement | question |
| `pre` | A local value whose origin holzBar could not observe: present before the first N run (β1, β2, dev builds; the pause gap C-8); changed while holzBar was not watching (prefs restore, `defaults write`, another build); or a macOS 26 drag whose item could not be identified (§7.2) | at a join, or once the group has no entry for the unit | **question** (never replaced silently) | question |

Automatic **overrides** of a user entry are kept beside the intent and never change it (R-AUTO-3, A2). Examples: a profile applied by a Space or display binding (OQ-6, treated as automatic), and Live Activities kept visible. Placements are recorded as `auto`: their priority is below every user entry, they never create dots, and they are never published. That is the "lower-priority provenance" the policy needs. An auto tier in the file was considered and rejected: no receiver would ever use a remote placement, and publishing one risks INV-A3.

### 2.5 The local state file (one atomic record, INV-10)

`~/Library/Application Support/holzBar/Sync/State.plist`, binary, written atomically (temporary file plus rename):

```swift
struct SyncState {
    var format: Int                         // state format version
    var me: MacID, counter: UInt64          // the counter is mirrored in UserDefaults SettingsSyncCounter
    var replica: Replica                    // includes entries merged but not yet applied ("waiting for Restart")
    var applied: [UnitKey: Set<Dot>]        // dots the applied intent reflects (the "taken in" fact)
    var intent: [UnitKey: (origin: Origin, digest: Digest)]   // origin and canonical digest of the intent value
    var overrides: Set<UnitKey>             // units with a recorded automatic local override
    var joining: JoinState?                 // folder being joined plus the shown units; Cancel restores the previous configuration
    var later: Int?                         // launch count at "Later"; the hint is hidden until the next launch
    var published: Digest?                  // canonical digest of the last file this Mac wrote
    var verifiedCounter: UInt64             // counter at the last launch where the own file matched the state
    var status: SyncStatus                  // too large, unreadable files, legacy Mac active, newer format, waiting for download
}
```

- *Seen* is the replica context. *Taken in* is `applied`. These are different facts, so "synced" no longer conflates them (RC-5, A1 §5.2 pair 8).
- The file is outside `UserDefaults`, so Export and Import never carry it. Migration Assistant copies it; that case is handled in §5.10.

---

## 3. File format and versioning

### 3.1 Folder layout

```text
<chosen folder>/holzBar/Settings.plist       β1/L0/SA05 file. N: never written; read only when founding (§8.2) and for a status line.
<chosen folder>/holzBar/Macs/<MacID>.plist   one per Mac; written only by that Mac
```

- holzBar creates only `holzBar/` and `holzBar/Macs/` inside an existing, accessible, chosen folder. It never creates the chosen folder or any ancestor of it (R-IO-5).
- β1 has an `NSFilePresenter` and a vnode `DispatchSource` on `holzBar/`.
  - Files changing in `Macs/` reach its presenter as `presentedSubitemDidChange`. β1 then reads `Settings.plist` in the background, finds nothing newer, and does nothing (`checkForNewerSettings`, β1 lines 434–457).
  - The vnode source fires only once, when `Macs/` is created.
  - So N's files cannot make a β1 Mac apply or alert anything.
- Readers accept only names matching `^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.plist$`, and the `mac` field must equal the name.
- Everything else is ignored for merging: conflict copies, `.syncthing.*.tmp`, `* 2.plist`, `.DS_Store`, `Icon\r`, renamed copies. A conflict-copy-like name that starts with this Mac's own ID is a collision signal (§5.10).

### 3.2 Encoding (binary plist)

| Field | Type | Meaning |
|---|---|---|
| `format` | Int | Major format, 1. |
| `minor` | Int | Additive revision, 0. |
| `classes` | Int | Version of the schema table (R-CLASS-3). |
| `mac` | String | Writer's MacID; must equal the file name. |
| `macs` | [String] | Mac table, sorted, so entries refer to Macs by index. |
| `context` | [Int] | Aligned with `macs`. |
| `units` | {String: [[Int, Int, Any, …]]} | Unit key → entries `[macIndex, counter, value, …]`, sorted by (MacID, counter). Unknown trailing elements are preserved through `raw`. |
| `sets` | {String: [String]} | Learned sets, sorted. |
| `written` | Date | Display only (sheet, cleanup horizon). Never in a decision. |

The *canonical bytes* are the encoding without `written`. A Mac writes only when they differ from `published`, or when its own file in the folder needs healing (§5.7). That is why a relaunch writes nothing (INV-C4).

### 3.3 Versioning and forward compatibility

- **Minor changes**, such as new unit namespaces, new optional fields or new entry elements, are passed through by older N readers (§2.3). Unknown top-level fields are ignored. A Mac does not show and cannot apply a unit it does not know, and never writes one.
- **Major changes** use a new folder, `holzBar/Macs2/`. An N Mac that sees a newer `Macs<k>/` shows "A newer holzBar uses this folder. Update holzBar on this Mac." It never reads, prunes or rewrites that data (R-COMPAT-7, INV-B8).
- A unit key never changes its value format (§2.2), so `classes` only grows.

### 3.4 Structural validation and limits (all or nothing per file)

- **Checks before decoding.**
  - `lstat`: a regular file, not a symbolic link. Opened with `O_NOFOLLOW`.
  - Size: at most 4 MiB to read. The write limit is 1 MiB (INV-Z2: the write limit is at most the read limit).
  - At most 64 files per check.
- **Checks after decoding.**
  - The plist types are as expected; `mac` equals the file name.
  - At most 1,024 Mac IDs, 20,000 entries, 32 siblings per unit, and 512 KiB per value.
  - Every counter is at most 2^34. That is far beyond any clock and catches corruption.
  - A dot that appears twice with different bytes is a collision.
- **Any failure makes the whole file "unreadable (reason)".** It is never partly merged, never treated as missing or empty, and shown in the sync status (INV-13, INV-F1, INV-Z6).
- **Values are checked one by one, and only when they are applied** (F-59, §5.6). They never affect merging.

---

## 4. Conflict units, questions and answers: the rules in one table

For a comparable unit u on Mac m: `R` = the register `replica.units[u]`, `vals` = the distinct values in `R`, `I` = the intent value with its origin.

| `vals` | Origin of `I` | Classification | Effect |
|---|---|---|---|
| ∅ | `pre` | publish | A fresh dot with `I`, no question. Happens at a join, or when the group has never had a user value for u. |
| ∅ | other | nothing | — |
| {v}, v = I | any | **in sync** | `applied[u] := dots(R)`, origin `dotted`. Silent (INV-P2). |
| {v}, v ≠ I | `dotted`, `default`, `auto` | **fast-forward** | Applied silently at the next launch, or through **Restart** while running. |
| {v}, v ≠ I | `pre` | **question** | Join-style row: this Mac's value against the folder's. |
| ≥ 2 values | any | **question (conflict)** | Siblings: one row with every alternative. |

- The other generation's layout units are **relay only**: never classified, applied, compared or shown (INV-L1).
- Learned sets are merged silently.
- **Hint:** "Choose Settings…" if any question exists, otherwise "Restart" if any fast-forward exists, otherwise nothing.

---

## 5. Algorithms

### 5.1 Join (pure Core)

```text
covers(ctx, d)  :=  ctx[d.mac] ≥ d.counter
join(a, b):
  ctx := pointwise max(a.ctx, b.ctx)
  for u in keys(a.units) ∪ keys(b.units):
    A := a.units[u] ?? [] ;  B := b.units[u] ?? []
    keepA := { e ∈ A | e.dot ∈ dots(B)  ∨  ¬covers(b.ctx, e.dot) }
    keepB := { e ∈ B | e.dot ∉ dots(A)  ∧  ¬covers(a.ctx, e.dot) }
    units[u] := sort(keepA ∪ keepB by (mac, counter))      -- empty ⇒ u absent
  sets[k] := capUnion(a.sets[k], b.sets[k])                 -- keep the cap_k elements with the smallest SHA-256
  same dot with different raw bytes in a and b  ⇒  collision (§5.10); the file is refused
```

- The join is commutative, associative and idempotent, and `join(x, older(x)) = x`. So delivery order, duplicates, coalescing and stale restores cannot change the result (INV-F2, INV-F3, INV-F5).
- `capUnion` keeps the k elements with the smallest hash. It is a semilattice too, and the cap is 2,000 elements per key (INV-K2).
- **A Mac's view** is `join(persisted replica, every readable file in Macs/, including its own)`. A file that cannot be read now is left out for now. Leaving a file out never removes anything, because a join only adds.

### 5.2 A local user write (the applied-context rule)

```text
userChange(u, v):                        -- called from an intent hook (§7) or the settings observer
  if v == I(u).value: return             -- no change, no dot (Command-click, profile re-applied: S-56, S-57)
  c := nextCounter()
  e := Entry((me, c), v)
  R.units[u] := R.units[u].filter { $0.dot ∉ applied[u] } + [e]   -- supersede only what this Mac applied
  R.ctx[me] := c ;  applied[u] := {e.dot} ;  intent[u] := (dotted, digest(v))
  persist(state) ;  publish in 2 s
```

- A remote entry that was merged but not yet applied, because it waits for Restart, is **not** superseded. It stays as a sibling, so the unit becomes a question. This is the per-unit form of `sync-1` rule (b): "another Mac's newer version arrived while this Mac had user changes".
- Waiting remote changes to *other* units keep waiting and stay non-conflicting.
- Dots are recorded **while sync is off** as well. It costs nothing, and turning sync back on is then an ordinary merge (A3 §8.7).

**How changes are attributed.**
- **U, D and PR keys.** The defaults observer on synced keys counts a change as the user's unless one of these applies:
  - it happens inside the engine's own apply;
  - it happens inside `SyncAttribution.automatic { … }`, which wraps migrations and any non-UI writer of a synced key;
  - it leaves the digest unchanged.

  A Core test lists every non-UI writer of a synced key, so a forgotten wrapper fails the build (INV-A1).
- **Layout.** Only explicit intent hooks count (§7). The defaults observer ignores `ItemSections` and `MacOS27Layout`.

### 5.3 Automatic changes

- Placements, seeding, reconciliation, displacement and migrations change only the local layer. They create no dot and no publication, and cause no hint (INV-A1 to INV-A3).
- Learned sets grow locally. Their union is published at most once an hour on its own, or with the next publication (R-FUN-8).
- An automatic override of a `dotted` unit is recorded in `overrides`, so the launch check (§5.6) does not mistake it for an unobserved change.

### 5.4 Check: read and merge (background actor)

Triggers:
- `NSFilePresenter` on `Macs/` (iCloud);
- a vnode or FSEvents source on `Macs/` (other providers);
- wake, app activation, and opening the Settings window;
- a 15-minute timer, or 2 minutes on network volumes (where FSEvents does not see remote writes);
- debounced by 1 s.

```text
check():
  folder := resolve bookmark .withoutMounting ; unavailable ⇒ status "The sync folder cannot be found"; return
  require holzBar/ and Macs/ to be real folders (lstat), else status "unusable"; return     -- never follow links
  names := list Macs/ (metadata only; strict name filter; ≤ 64)
  for n in names:
     dataless (SF_DATALESS or ubiquitousItemDownloadingStatus ≠ current) ⇒ request download; mark waiting; continue
     read bounded, off the main actor (coordinated read for iCloud, with a timeout) ⇒ decode + structural check (§3.4)
     failure ⇒ status unreadable(n, reason); continue
  own := file named me (if readable)
     own is ahead of the state (has own dots unknown here, or context[me] > counter) ⇒ §5.10 (rollback or collision)
  newer major format seen ⇒ status "newer holzBar"
  counter := max(counter, max_i file_i.context[me])
  R' := join(R, all readable files)
  if joining: plan the join (§5.8) and stop here; nothing is committed or published until it is decided
  commit R := R' ; persist ; classify (§4) ; update hints
  if canonical(R) ≠ published: publish (relay, debounced 5 min; immediately if this Mac's own entries are not in its own file)
  if own file missing, unreadable, or its digest ≠ published: heal, i.e. publish in 2 s (R-LIN-4)
```

The check is one serialized task of the engine actor. A merge is committed as `join(current state, fetched files)`, never as a replacement. So a user edit made while files were being read is never lost, and never marked as anything it is not (S-65).

### 5.5 Classify and hint

- Classification (§4) runs after every commit, every local write and every answer.
- Hints are computed from the committed state each time (S-66).
- Clicking a hint re-classifies first. **Restart** with a conflict present opens the sheet instead. **Restart** also completes any arrangement capture still pending (§7.2) before it decides (S-64).

### 5.6 Launch (bounded, `AppDelegate.init`)

```text
1  load State.plist (local disk) ; missing or corrupt ⇒ "state lost": every comparable unit becomes pre, joining := true
2  identity check (salted hash) ; mismatch ⇒ §5.10
3  rollback check: counter := max(state.counter, SettingsSyncCounter, ⌊now⌋)
4  unobserved-change check, for every comparable unit with origin dotted or default:
     UserDefaults value ≠ intent value and u ∉ overrides  ⇒  origin := pre, intent := the UserDefaults value
     (prefs restored, defaults write, a run of another build, a crash between change and record)
5  apply every fast-forward unit from the persisted replica:
     SettingsBackup.apply(subset, removesMissingKeys: false), validating each entry;
     a bad entry is skipped and logged, its unit keeps the local value, the entry stays in the replica
     then persist applied/intent (apply, then record: a crash re-applies, which is idempotent)
6  union the learned sets into the local keys (capped)
7  start a background check with a 1 s budget; results that arrive in time and contain only fast-forwards are applied as in 5
8  after setup: hints ("Choose Settings…" for questions; "Restart" never shows at launch for what was just applied)
```

- No folder I/O runs on the main thread. Steps 1–6 use only the local state file, so a waiting change survives a missing, dataless or unreadable folder (INV-9, S-35, S-36).
- **Partial apply** (policy D1-Q3): fast-forward units apply at launch while conflicting units keep their local values.

### 5.7 Publish (write this Mac's own file)

- **Triggers:**
  - own user writes: 2 s debounce;
  - answers: immediately after they are recorded;
  - relays: 5 min debounce;
  - learned-only changes: at most once an hour;
  - healing: 2 s.
- **Never at launch** unless healing is needed. An unchanged state never writes (INV-C4).
- **Size check** before the write: if the encoding is over 1 MiB, nothing is written, the previous file stays, and the status shows "This Mac's settings are too large to sync" (R-SIZE-2, INV-Z3).
  - Leaving out an oversized unit is **not** allowed. The file's context would cover that unit's dot while the file lacked the entry, and readers would delete it.
  - With the icon capped at 256 KB, a file stays under 1 MiB even with a three-way icon conflict.
- **Atomic replace:**
  - write a temporary file in the item-replacement directory for the target volume, or a dot-prefixed temporary file in `Macs/` on SMB;
  - then `replaceItemAt`, coordinated with `.forReplacing` for iCloud;
  - off the main actor, with a timeout, at most one write outstanding.
- **Order of operations:** persist the state first, then write the file. A crash in between leaves the file older than the state, and the next check heals it.

### 5.8 Join: Turn On…, Change…, re-enabling, a lost state, the first N run

A join is an ordinary merge into a **tentative** replica `R'`, plus the dot-less comparison of §4 (`pre` rows). Nothing is committed or published, and the previous folder stays active, until the join is decided (SA-06).

| Folder `Macs/` | Join result |
|---|---|
| no entries at all | **Founding.** Optional founding import of `Settings.plist` (§8.2). Then publish `R` plus every `pre` unit as fresh dots. No question unless the founding import finds differences. |
| entries, none readable yet (dataless or unreadable) | Wait, request downloads, status "Waiting for the sync folder to download". **Never founding:** unreadable is not empty (INV-Z6). |
| readable entries | Join. Rows to show: `pre` units that differ, plus existing conflicts. None ⇒ commit silently: equal units are adopted, fast-forwards become the Restart hint. Otherwise ⇒ join sheet with **Cancel**. |

To reduce noise, the join waits up to 30 s for files that are still downloading before it shows the sheet. A view that is still partial is safe: values that arrive later are ordinary fast-forwards or, rarely, one more question. The pending join is persisted, so the sheet comes back after a relaunch.

### 5.9 Cleanup of departed Macs and conflict copies

- **A Mac X's file may be deleted by Mac m only when all of the following hold:**
  - m has read the file in this run (only delete what you have loaded);
  - m's **currently published** file dominates it: every entry of X's file is in m's replica or covered by m's context, and m's context covers X's whole context;
  - its `written` date is more than 180 days old (OQ-9);
  - X is not m.
- **Why deletion is safe.** Everything X knew is relayed by m's file. The 180-day horizon only limits churn; it is not what makes deletion safe. If X comes back, it simply publishes from its local replica again.
- **Concurrent deletions** are idempotent. A delete that races with X's return is healed by X.
- **Context entries of departed Macs are never pruned.** They cost about 24 bytes each. Pruning one would let a restored old file bring back superseded values (R-LIN-5).
- **Old IDs of this Mac** (after re-identification) are deleted as soon as the new file dominates them.
- **Conflict copies** (OQ-11) are deleted only if they carry this Mac's ID or an old ID of this Mac, are dominated, and are older than 30 days. Other names are never touched.

### 5.10 Identity events

| Event | Detection | Action |
|---|---|---|
| Migration Assistant, clone or restore to other hardware (F-38) | Hash mismatch at launch | New `MacID`, new counter. **Keep** the replica, `applied` and `intent`: a copied state is a valid causal state, and dots are globally unique. The old ID's file belongs to the original Mac. |
| Another account on the same Mac with copied preferences | `uid` in the hash | As above. |
| Preferences or state restored on the same hardware (counter rolled back) | `max(state.counter, SettingsSyncCounter, ⌊now⌋)` at launch. Later: the own file ahead of the state, or any `context[me]` > counter | If the own file extends this Mac's history (every own dot in the state is present in it with the same bytes): join it. These are this Mac's own later writes, and they are applied as fast-forwards. |
| Collision: two installations under one ID, or a re-used dot | Own file holds an own dot with different bytes, or contradicts the state; an own conflict copy; an iCloud conflict version of the own file | Re-identify. Every unit whose applied entry carries the old ID and was written after `verifiedCounter` becomes `pre`. The join comparison then asks only where the group differs. |

---

## 6. Conflicts: detection and the question shown

### 6.1 Detection

- A **conflict** is a comparable unit whose register holds two or more *different* values (§4).
- Equal values are never a conflict, and the next write collapses them.
- A `pre` row is a dot-less local value that differs from the group's single value. It appears at a join, at founding, or after an unobserved change.
- With dots and contexts, "same unit changed on two Macs since they last saw each other's change" is exact. There are no false conflicts from clock skew, missing records or digest equality.

### 6.2 Hint and sheet (`modal-alerts-1`: a quiet hint, never a dialog by itself)

- The hint **Choose Settings…** appears in Settings → Advanced and at the top of holzBar's menu. It is shown on **every** Mac whose applied value differs from a sibling, so the conflict can be answered on any Mac and disappears everywhere.
- The sheet opens on the Settings window. At most one is open at a time, and it has no default button (SA-07). Example:

```text
┌ Your Macs have different settings ───────────────────────────────────────────────┐
│ These settings were changed differently on this Mac and on another Mac.           │
│ Choose which to use on all your Macs. Other changes keep syncing.                 │
│                                                                                    │
│  Setting                      This Mac            Sync folder                      │
│  Show on hover                On                  Off  (another Mac, 7 Oct, 14:03) │
│  Menu bar layout (macOS 26)   3 items differ      [Details…]                       │
│                                                                                    │
│ [Use Settings from Sync Folder]   [Keep This Mac's Settings]   [Later]             │
└────────────────────────────────────────────────────────────────────────────────────┘
```

- **Details…** lists each item with its section on both sides, and its name from the local item cache, or the bundle ID.
- A unit with three or more alternatives (three Macs changed it concurrently) gets a pop-up menu in its row. The bulk buttons then cover the two-way rows.
- **Joining:** the title reads "This folder already holds holzBar settings", and **Cancel** replaces **Later**.
- **Founding import (§8.2):** the column reads "Sync folder (saved by an older holzBar on <date>)".
- **The other Mac is never named.** Only a date is shown, from the counter of the sibling's dot, for display only. A user-chosen label is optional (OQ-10).

### 6.3 Answers

Each shown unit u has its shown dots `S_u` and the chosen value `v_u`: the folder's value, this Mac's value, or a row choice.

```text
answer(choice):
  for each shown u:
    c := nextCounter() ; e := Entry((me, c), v_u)                   -- an answer is a user act: always a fresh dot
    R.units[u] := R.units[u].filter { $0.dot ∉ S_u } + [e] ; R.ctx[me] := c
    v_u == intent value ⇒ applied[u] := {e.dot}                      -- Keep: no apply needed
    else               ⇒ pendingApply[u] := e                        -- Use: apply, then record
  persist ; publish now ; if any pendingApply: apply (no removal), record, relaunch
```

- **Only the dots shown are superseded.** An entry that arrived while the sheet was open survives as a sibling and is asked about again (INV-8, S-33, S-46). A unit that is resolved elsewhere while the sheet is open is dropped from the answer, with the note "Already decided on another Mac".
- **Every answer needs a fresh dot.** An answer that only dropped the other siblings would go wrong when two Macs answer at the same time: their two "drops" would cancel each other and remove every value. With fresh dots, simultaneous answers produce one new pair of siblings and one more question. That converges as soon as anyone answers (A3 §8.5).
- **An answer is the user's choice.** Even if this Mac's value was placed automatically, "Keep This Mac's Settings" makes it a user value, because the user saw it and chose it.
- **Later** writes nothing. The siblings stay, and the hint hides until the next launch (INV-P4). Other units keep syncing.
- **Cancel** (joining only) discards `R'`. The previous folder or "off" stays, and nothing is written.
- **Answers in Mode G:** one row, "All settings", plus the layout rows. Use and Keep act on the whole settings dictionary, exactly as `sync-1` describes.

### 6.4 Worked example

1. A sets `ShowOnHover` = off, dot (A,101). B merges it and shows **Restart**.
2. Before restarting, B's user sets it to on, dot (B,205). B's applied dots were {(B,90)}, so (A,101) stays. B's register is {(A,101): off, (B,205): on}, and both Macs show **Choose Settings…** once they have merged.
3. On A the user picks "Keep This Mac's Settings" (off). A writes (A,102): off, superseding the shown {(A,101), (B,205)}.
4. B merges A's file. Its register becomes {(A,102): off}. That is a fast-forward, so **Restart**, and off applies at the restart. The question has disappeared on both Macs.

---

## 7. Layouts per macOS version

### 7.1 Namespaces and authority

- **Separate namespaces.** `l26/<identityKey>` mirrors `ItemSections` per item. `l27/<bundleID>` mirrors `MacOS27Layout` per item.
- **A Mac writes dots only in its own generation's namespace** (INV-L2).
- **The other namespace is relayed** inside the replica: never applied, compared, shown or deleted, and never replaced with a copy (INV-L3–L5). There are no "copies", no "current" lists and no stale-copy recognition: RC-4 disappears.
- **The effective local layout is assembled per item.** For each item: the applied user entry if there is one; otherwise the saved `pre` or auto value; otherwise holzBar's placement (`NewItemsPlacement`).
- **Applying a fast-forward** writes only the affected items into `ItemSections` or `MacOS27Layout` and keeps every other item.
  - The value `-1` removes the item's saved section, so holzBar places it again.
  - A profile whose layout is empty for `gen(m)` changes nothing and never writes an empty layout (F-03, R-FUN-9).
- **Upgrade from macOS 26 to 27** (R-FUN-7, INV-L6):
  - `seedLayoutIfNeeded` seeds `MacOS27Layout` from `ItemSections` as auto values.
  - The group's `l27` user entries then fast-forward over those values, silently at the next launch.
  - Only g27 moves the user made after the upgrade have dots, and only those can conflict.
  - The Mac's `l26` entries stay in the replica as a relay.
  - `MacOS27LayoutSeeded` stays local.

### 7.2 Capturing intent (only user actions create dots)

**macOS 27.** Every user path already names the item and the section:
- `Concealer27.setSection(_:for:)` from the Layout pane (`LayoutBarPaddingView` line 314);
- profile apply (`LayoutProfiles.apply`, `SectionLayout27.applyingProfile`);
- Import.

Each records `userChange(l27/<bundleID>, section)` only if the section changes. `placeNewApplications` and `seedLayoutIfNeeded` are automatic.

**macOS 26.**
- **Layout pane.** `LayoutBarMoves.setSection(of:to:)` records the item and section immediately. Undo and keyboard moves go through the same function.
- **Command-drag on the bar.**
  - At drag start (`handleMenuBarItemDragStart`), holzBar records the window ID of the menu bar item under the cursor and a copy of the cached sections.
  - At drag end (`handleMenuBarItemDragStop` or `handleArrangementEnd`), after the bar settles (today's `saveSectionsSoon`, at most 1.5 s), it resolves the window ID to the item's identity and reads that item's new section.
  - Only that item is stored in `ItemSections` and recorded as the user's change, and only if its section changed.
  - Every other item keeps its saved section, so displaced items are restored by the reconciliation (S-59, S-67).
  - The identity is known even for items that were never saved, or that appeared during the drag (S-58).
  - If the dragged item is one of holzBar's own control items and that drag is allowed: the items between its old and new positions whose sections changed are the user's moves.
- **Command-click without a move.** No section changes, so no dot (S-56).
- **No identifiable item** (should be rare). The changed items are stored with origin `pre`: kept, never replaced silently, published only where the group has no entry, and asked about where it differs. A real move is never reverted silently, and a displacement can at worst cause a question.
- **Profiles.** A per-item difference against the current intent: only items whose section changes get dots (S-57). A profile applied by a binding is automatic (OQ-6).
- **Import.** A per-item difference. Items the file removes are written as `-1`.
- **Reconciliation and placement** (`reconcileSections`, `storeSections(byUser: false)`, the first-run `saveSections`) are automatic.
  - They store only items without applied user intent. An item whose user entry was applied after the reconciliation read the bar is skipped, using a per-item change generation (S-60).
  - Even a stray local store creates no dot. The published intent stays the user's, and the next apply restores it.
- **Restart and quit.**
  - **Restart** completes a pending capture first (S-64).
  - `applicationWillTerminate` completes it within a short time bound and persists the state.
  - Only a crash within about 1.5 s of a drag can lose that one move, locally. That is an input loss, not a sync decision.

---

## 8. Migration and coexistence

### 8.1 The β1 boundary (A2 OQ-2: no legacy writes)

- **What N does with the legacy file.**
  - It **never writes** `holzBar/Settings.plist`.
  - It reads it once, when founding a group (§8.2).
  - Afterwards it only watches it for a status line.
- **What a β1 Mac does.** It keeps reading and writing `Settings.plist` and syncs with other β1 Macs as before, with β1's own known behaviour. It never reads `Macs/`.
- **Consequences.**
  - **Safety.** Nothing N writes can be applied silently by β1, can remove β1 keys (F-60), or can revert a β1 change. INV-B1 holds trivially. Nothing β1 writes enters the N group, so a β1 rewrite, an old copy or β1's automatic writes can never displace an N user change. INV-B3 and INV-B4 hold with zero questions. A1 §5.4 conflicts C1–C5 disappear, because N no longer writes the file β1 applies.
  - **Limitation the user sees.** β1 Macs and N Macs do not sync with each other until the β1 Macs are updated.
    - Settings → Advanced shows "A Mac with an older holzBar also uses this folder. Update holzBar there to sync with it." This appears whenever the `modified` field in `Settings.plist` changes after this Mac founded or joined the group and the writer is not this Mac's own legacy ID, and it is cleared 30 days after the last change.
    - The release notes say: "Update holzBar on every Mac that syncs. Macs on 0.0.7-beta1 and Macs on this version do not sync with each other. Nothing is lost: when you update a Mac, holzBar compares its settings with the folder and asks where they differ."

### 8.2 Founding import (once per new group)

When a Mac **founds** a group (`Macs/` has no entries) and `Settings.plist` exists, is readable and is not from this Mac's own legacy ID (`SettingsSyncLegacyDeviceID`, kept locally when the ID is rotated), its content is a lineage-free snapshot (R-EVID-2):

| This Mac's unit | Legacy file | Result |
|---|---|---|
| origin `default` or `auto` | has a value | Adopt silently: apply, and publish as a fresh dot from this Mac. |
| equal | — | Nothing. The unit is published as `pre` → dotted. |
| origin `pre` (or `dotted`), different | — | A row in the **founding sheet** (Use / Keep / Cancel), showing the legacy file's date. |
| learned sets | — | Union. |
| flags, CTX, TUNE, LEG keys; the other generation's layout key | — | Ignored. A Mac never authors the other generation (INV-L2). That generation's Macs publish their own layout when they update. |

There is at most one founding question per group, so INV-B4 holds. If two Macs found at the same time, their entries are concurrent: equal values collapse, and different values become ordinary conflicts.

### 8.3 First N run on a Mac coming from β1, β2 or a development build

- **No sync state exists, so the Mac joins** (R-POL-9).
  - Every comparable value present in the app's persistent domain gets origin `pre`.
  - Values absent from it, or equal to the schema default (D1-Q4), get origin `default`.
  - Every existing layout entry is `pre`. This covers the pause gap: a layout rearranged during β2 counts as the user's (C-8, R-COMPAT-4, INV-B5).
- **Old state is never evidence** (INV-B6). `SettingsSyncLastSynced`, the unreleased `SettingsSyncBase*`, `…LayoutEdits` and `…PendingModified` keys, and the file fields `currentLayouts`, `copiedLayouts` and `seen` are never used.
  - `SettingsSyncLastSynced` is left untouched, because β1 needs it after a downgrade.
  - The unreleased keys are removed after the first successful join.
- **Identity.**
  - If no hash is stored, the hash is stored and the ID is rotated once (`sync-1`). This also splits Macs that share a copied β1 ID.
  - The old β1 ID is kept locally as `SettingsSyncLegacyDeviceID`.
- **The custom icon** is converted once into the capped PNG unit, as a `pre` value.
- **Then** founding (§8.2) or joining (§5.8).

### 8.4 Downgrade and return; β2 peers

- **β2 peers.** A β2 Mac touches nothing in the folder. While it is paused it simply does not take part (R-COMPAT-8).
- **Downgrade N → β1 → N.** The β1 run never touches `Macs/` (INV-B7). On the return to N, the unobserved-change check (§5.6 step 4) turns every value that differs from the recorded intent into `pre`. A value is replaced only through a question; where the group has no entry, it is published.
- **N → β2 → N** behaves the same way.

---

## 9. Failure handling

### 9.1 By root-cause class (A1 §4)

| Class | What removes it in D1 | What remains |
|---|---|---|
| RC-1 Whole-state writes into one shared file | Single-writer files. No Mac writes another Mac's data, and there is no read-modify-write of a shared object. | — |
| RC-2 Ordering by wall clock | Dots and contexts. Counters are compared only within one Mac, and the time floor is used only to avoid re-using a counter. Dates are for display only. | — |
| RC-3 File lifecycle | Missing, restored, old, damaged, dataless or too large files: a join with an older or partial state changes nothing. Unreadable is never "missing". Each Mac heals its own file from its persisted replica. Waiting changes live in the local state. | Delivery stays eventual (by nature) |
| RC-4 Two per-OS layouts | Per-item units in two namespaces, authored only by their own generation and relayed otherwise. β1 never reads N files. | — |
| RC-5 Provenance from digests and missing records | Each value carries the dot of the event that produced it. "Seen" is the context, "taken in" is `applied`. No inference from missing records: a missing state means joining (R-EVID-1). | — |
| RC-6 Automatic and user changes mixed | Only intent hooks create dots, per item. Placements and overrides stay in the local layer. On macOS 26 the item is identified at drag start, not inferred from snapshots. | Attribution on macOS 26 depends on the window ID under the cursor. If that fails, the move is stored as `pre`: no silent loss, at worst a question. |
| RC-7 Peers on other versions | The hard β1 boundary (§8.1), the founding import, the pause gap handled by `pre`, pass-through for minor formats, a new folder for major formats. | No sync between β1 and N (stated to the user) |
| RC-8 Answers covering the whole state | Questions per unit. An answer supersedes exactly the shown dots, with a fresh dot. | — |
| RC-9 Races and bookkeeping that is not atomic | One engine actor. One state file written atomically before every folder write. Merges committed as joins. Hints recomputed. Restart completes pending capture. | A crash within about 1.5 s of a macOS 26 drag (local input loss) |
| RC-10 Identity, I/O, content | F-38 with `uid`; collision detection (§5.10); no folder I/O on the main thread; a 1 s launch bound; `.withoutMounting`; the size limit checked at the writer; structural checks all or nothing; per-entry checks at apply (F-59); the icon stored once and capped (F-61). | — |
| RC-11 Verification blind spots | All decisions in pure Core. The engine actor is in Core too, behind I/O protocols. A simulator drives the real engine (§12). | A real two-Mac check stays mandatory |

### 9.2 Provider faults (A2 §6) and the A1 §8 hazards

| Fault | D1 behaviour |
|---|---|
| Delay, reordering, coalescing, duplicates | No effect on the result, because the join is commutative, associative and idempotent (INV-F2, INV-F3). |
| Concurrent writes to one path (conflict copies, iCloud versions, last writer wins on SMB) | Cannot happen with single writers unless two installations share an ID. A conflict copy of this Mac's own file is the collision signal (§5.10). Safety never depends on conflict-copy names (INV-F4). |
| Restore of an older file (version history, Recently Deleted, Rewind, Time Machine, Syncthing versioning) | Dominated, so the join does nothing. The writer heals its own file. Deliberate rollback goes through Export and Import, which are user writes (A3 §10 Q9). |
| Deletion of a file or of the whole `Macs/` folder | Every Mac re-publishes its own file from its persisted replica. Nothing is reset or lost on any Mac (INV-F6). Deleting the folder does not reset sync. |
| Dataless files, eviction | Skipped at launch, downloaded in the background, merged later. A partial set of files is safe to merge. |
| Partial content (SMB, non-coordinating clients) | Fails the structural check, so it counts as unreadable and is retried (INV-F1). |
| Stalls, hung provider | Every read and write has a timeout, with at most one outstanding per path. Launch never waits more than 1 s (INV-R2). |
| Share not mounted | Status "The sync folder cannot be found". No writes and no folder creation. Resumes on mount (INV-F7). |
| Foreign bytes, symbolic links, oversize or crafted files | The checks in §3.4: refused as unreadable, links never followed (INV-SEC1). A valid forged file can still supersede values, as any folder writer can today (out of scope without keys). |
| Clock offsets and steps | Ignored by every decision (INV-F9). |
| Local state rolled back on the same hardware | Counter copies, plus the own file being ahead of the state, lead to recovery (§5.10). |
| Preferences deleted or app reinstalled | The salt is new, so the ID rotates and the Mac joins. Defaults count as `default` and adopt silently. |
| Folder moved or renamed by the sync app | The bookmark follows it. Waiting changes are in the local state (INV-9). |

---

## 10. Privacy and security

- **The folder contains only:**
  - format numbers;
  - random Mac IDs (UUID v4, rotated on any identity change);
  - counters, which are close to the unix second of each user change and so reveal *when* a setting changed, as `modified` does today;
  - `written` dates;
  - the synced settings values, including item identities, bundle IDs, profile names, hotkeys and the custom icon;
  - the learned sets.

  Nothing else (R-PRIV-2, INV-PR2).
- **Never in the folder:** the hardware UUID, the salt or the hash, the `uid`, the computer name, the user name, paths, bookmark data, or the names of conflict copies (OneDrive puts the computer name into them).
- **The extended F-38 hash** is documented in `docs/privacy-and-permissions.md`.
- **No network** (C-1). Logs mark paths, values and IDs as private.
- **Writes.** holzBar writes only regular files inside `holzBar/Macs/`. It never mounts anything, and never follows a link (R-SEC-5, R-IO-4).
- **Synced file names** (ItemIcons) are used only as plain names (R-SEC-3).

---

## 11. File sizes

| Part | Estimate (binary plist) |
|---|---|
| Header, Mac table and context | ~0.2 KB + 40 B per Mac ID ever seen |
| About 70 U units at 40–70 B | ~4 KB |
| Profiles, groups, appearance, reveal rules (JSON) | 2–15 KB |
| Layout: about 60–150 items per generation, 2 generations, at 60–80 B | 7–24 KB |
| Learned sets (capped at 2,000 elements per key) | 5–30 KB typical, 150 KB at the caps |
| Custom icon (PNG, capped at 256 KB) | 0 typical; ≤ 256 KB |
| Siblings during a conflict | + one entry per concurrent Mac and unit |
| **Typical file** | **30–80 KB**; worst case about 450 KB, which is below the 1 MiB write limit |

- The folder holds one such file per Mac, typically 2–4 files, plus `Settings.plist` as long as β1 Macs exist.
- Departed Macs' files are removed after 180 days once they are dominated (§5.9).
- The local `State.plist` is about the size of the Mac's own file.
- `|state| ≤ c1 + c2·D` (INV-Z4), and the number of files is at most the number of live Macs plus files waiting for cleanup (INV-Z5).

---

## 12. Test strategy

1. **Structure for testability (R-TEST-1, RC-11).**
   - Everything except AppKit UI and real I/O lives in Foundation-only Core:
     - `SyncCore`: the schema, the join, writes, answers, classification, the launch, join and founding plans, cleanup, the attribution function, and the codec with its checks;
     - `SyncEngine`: an actor that owns `SyncState`, behind the protocols `FolderIO`, `DefaultsStore`, `StateStore` and `Clock`.
   - The app provides the real implementations, plus the hint and sheet views and the intent hooks.
   - The glue has no branches that change outcomes. A CI lint forbids `FileManager` and `NSFileCoordinator` in main-actor sync code (INV-R1).
2. **Algebraic property tests** on randomly generated replicas:
   - the join is commutative, associative and idempotent;
   - `join(x, older(x)) = x`;
   - `capUnion` is a semilattice and stays bounded;
   - a write grows the context monotonically;
   - an answer supersedes exactly `S_u`;
   - encoding round-trips, and the canonical bytes are stable under key order.
3. **A deterministic multi-Mac simulator** in the test package, implementing A2 §2 and §8.
   - **Macs.** N Macs run the real `SyncEngine`. L1 Macs run A2 §2.6 literally: writing at launch and 5 s after any change, never reading first, applying silently with key removal, dropping unknown keys. P Macs are inert.
   - **Provider model.** The A2 §6.3 presets (iCloud, Syncthing, SMB, Hostile): delay, coalescing, reordering, dataless, conflict copies and last writer wins, restore, delete, partial content, stalls, unmount, foreign bytes.
   - **Clocks.** One per Mac, with steps.
   - **Identity events.** `Clone`, `CopyAccount`, `RestorePrefs`.
   - **User events.** Settings edits, layout moves per generation, profiles, import, and every answer (adversarial).
   - **Automatic events.** Placements, displacements, seeding, learning.
   - **Ground truth.** Unique-value tokens and vector clocks over the trace (A2 §2.3, §2.5). The design's own metadata is never trusted; `claimedPast` is exposed for INV-S3 (b).
4. **Oracles, checked after every step:**
   - A1 INV-1 to INV-15;
   - A2 INV-S1 to S9, A1 to A4, L1 to L6, K1 to K3, P1 to P5, ID1 to ID5, Z1 to Z6, F1 to F10, B1 to B9;
   - liveness invariants C1 to C6 after a drain phase.

   Metamorphic pairs:
   - INV-A1: the same trace with automatic events inserted;
   - INV-F9: randomised clocks;
   - INV-F2: permuted deliveries.
5. **Exploration.**
   - Exhaustive small scope: 2–3 Macs, both generations, at least one L1 peer, up to about 8 events, every interleaving and every answer.
   - Seeded random long runs of thousands of steps per preset.
   - A failure is minimised and printed as a scenario.
6. **Named regression tests.**
   - S-01 to S-70 (§13), each as a scripted simulator run that asserts the outcome column;
   - the A2 §7 SC-xx catalogue;
   - the A1 §8 hazards (conflict copies, rolled-back state, reinstall, moved folder).
7. **Intent capture.**
   - The attribution function (drag start window ID, before and after sections → set of user moves) is tested on recorded traces: displacement during the drag, an item that appears mid-drag, a control-item drag, an unidentified item.
   - The macOS 27 hooks are covered by unit tests of `Concealer27` and `LayoutProfiles` with an in-memory `DefaultsStore`.
8. **Fuzzing** the decoder and the checks with arbitrary bytes, truncations and type swaps (R-TEST-4, INV-SEC1).
9. **Mutation gate** (R-TEST-5): removing or inverting any guard in `SyncCore` or `SyncEngine` must fail at least one simulator test.
10. **Real Macs**, recorded as the human check (A1 §7.2.5, A2 R-TEST-7):
    - S-01, S-09, S-14, S-20 (with a real β1 Mac), S-34, S-45, S-59, S-62, S-68;
    - on iCloud Drive, on one File Provider folder (Dropbox or OneDrive) and on one SMB share.

---

## 13. Regression walk: every A1 scenario through D1

- **Pass**: the "Must" holds as written.
- **Pass (D)**: safety and outcome hold, with a documented difference in a literal detail, explained in the row.
- **Pass (B)**: the "Must" holds through the β1 boundary (§8.1).
- Unless a row says otherwise, the per-unit mode is meant. Mode G differs only where noted.

### G1 · Joining, identity, routine writes

| # | D1 outcome | Verdict |
|---|---|---|
| S-01 | B lists `Macs/` and reads A's file. It publishes nothing until the join is decided. Units where B's value is `default` or `auto` are adopted silently: Restart after Turn On…, or at the next launch. Equal units adopt A's dots. Units where B has a user or `pre` value that differs from A's entry go into the join sheet (Use / Keep / Cancel). A user value on A changes only through B's **Keep**. *Difference:* a unit only B's user set, where A has no entry and holds only the default, reaches A as a fast-forward without a question. Nothing of A's user is replaced. In Mode G, B's whole settings differ, so B asks. | Pass (D) |
| S-02 | No write at launch: canonical bytes unchanged, own file current. No relay, no hint, no ping-pong. | Pass |
| S-03 | B writes only its own file. It cannot replace A's entry, whose dot B's context does not cover. When A's file arrives: a fast-forward, or a question if B changed the same unit. A dataless file is skipped until it is downloaded. | Pass |
| S-04 | Later leaves B's entry in A's persisted replica. Automatic writes create no dots. A's files relay B's entry and never supersede it. A user change on A to the *same* unit: a sibling, so Choose Settings… on A and B. *Difference:* a change to another unit merges without a question; in Mode G it asks. | Pass (D) |
| S-05 | A keeps publishing its own file, which relays B's waiting entry and cannot supersede it (§5.2). Restart applies the persisted waiting entries, or their causal successors. A newer conflicting arrival switches the hint before the restart. *Difference:* publishing is not paused. | Pass (D) |
| S-06 | B's salted hash (hardware UUID plus uid) mismatches, so B gets a new MacID. B keeps the copied replica and its applied dots, which are a valid causal state with globally unique dots. No unobserved differences, so no question. B's first file adds no new dots, so A shows no hint. The hash never leaves the Mac. *Difference:* the sync state is kept instead of cleared. S-07 holds. | Pass (D) |
| S-07 | Empty folder: founding, publish, no question. Own file: a merge with nothing new. Equal settings: adopt dots. Re-identified Mac with equal settings: as S-06. No hint on any Mac: publications carry no new dots or only equal values (INV-P2). | Pass |
| S-08 | First N run: the hand-made layout entries are `pre`. When the folder becomes reachable, the join compares them per item with the folder's layout for this generation. Differences become rows in the join sheet; nothing is taken silently. | Pass |

### G2 · Infrastructure

| # | D1 outcome | Verdict |
|---|---|---|
| S-09 | Launch reads only the local state file. The folder check runs in the background with a 1 s budget. Dataless files are skipped and downloaded, and merged later; they lead to the Restart hint or are applied at the next launch. No coordinated I/O on the main thread. | Pass |
| S-10 | The bookmark resolves `.withoutMounting`, so "The sync folder cannot be found" is shown. No writes and no folder creation. Dots keep accumulating locally and are published once the share is mounted. | Pass |
| S-11 | The icon is converted and capped (≤ 256 KB) when it is set. The writer checks ≤ 1 MiB before every write; over that, it writes nothing, keeps its previous file and shows a warning. A file B cannot read is "unreadable", never "missing", and nobody writes another Mac's file. `Settings.plist` is never written, so a β1 oversize file is left alone. | Pass |
| S-12 | Structural checks per file are all or nothing. Values are checked per entry only when applied. A bad `MacOS27Layout` entry affects only that item, a bad hotkey only that action, and an undecodable JSON unit only that unit, which keeps its local value. Bad entries stay in the replica byte for byte, are never "repaired" and never published as a loss. Local Import also checks per entry (F-59). | Pass |

### G3 · Two macOS versions

| # | D1 outcome | Verdict |
|---|---|---|
| S-13 | No key removal on any path. `l26` units are relayed by a macOS 27 Mac and never applied to it, and the reverse. Each Mac's own layout key is touched only by its own generation's entries. | Pass |
| S-14 | B (macOS 27) founds: U units plus its `l27` units; it authors no `l26`. A (macOS 26) joins: U units are equal, so A adopts. The `l26` namespace is empty, so A's `pre` items are published without a question. `l27` is never compared on A. A's Command-drag creates a dot on one `l26` item. No question at any point; B's `MacOS27Layout` is unchanged. | Pass |
| S-15 | The restored old file of A is behind A's replica, so A heals it. C joining that old file changes nothing: C's dots from L_C1 are covered by C's context and absent from its register. A never takes in or re-lists L_C1. C keeps L_C2 and receives A's setting as a fast-forward. | Pass |
| S-16 | A stale file of B, delivered again, is dominated, so the join does nothing. B heals its own file. | Pass |
| S-17 | There are no copies or "current" lists. D's re-enable is a merge: C's newer `l27` entries (also relayed by A) supersede what D applied, so D gets a fast-forward and Restart. D's writes relay C's entries. D's unchanged layout has no new dots and cannot compete. If D's user moves the same item, the result is a sibling and a question. Restored files are dominated in every variant. | Pass |
| S-18 | β1 writes only `Settings.plist`, which N does not merge: no question, no revert. A's file holds A's `l27` entries. N never touches C's `ItemSections`. | Pass (B) |
| S-19 | N never writes `Settings.plist`, so nothing A does can delete or revert C's `ItemSections` on β1. Conflict C1 is removed by the boundary. | Pass (B) |

### G4 · Same macOS version with a β1 Mac

| # | D1 outcome | Verdict |
|---|---|---|
| S-20 | A ignores B's β1 write, and A's own write goes only to A's file. β1 B never reads N files, so B keeps L_B. A never replaces it. L_B reaches the N group when B updates (S-21). The limitation is shown as a status line. | Pass (B) |
| S-21 | B's first N run: its layout entries are `pre`. The join compares them per item with the group, and differences are asked about. Nothing is taken silently. | Pass |
| S-22 | C founds the N group, since `Macs/` is empty. The founding import reads B's `Settings.plist`. C's `pre` arrangement differs from L_B, so C shows the founding sheet (Use / Keep / Cancel). B is never written. | Pass |
| S-23 | A's sheet shows only the "Show on hover" unit. Keep writes one fresh dot for it. B's `l26` entries stay live, A's file relays them, and A applies them at restart. C's β1 writes never enter the group. B keeps its arrangement. *Difference:* a drag on A asks if it moves an item B arranged; moving other items merges. | Pass (D) |
| S-24 | β1 write-backs never enter the group: no question. A's entries stay current in A's file, and C's `ItemSections` is untouched by N. | Pass (B) |
| S-25 | C's return to L1 stays on C: β1 never reads N files, and N never merges `Settings.plist`. A's later drag cannot reach C. When C updates, its `pre` layout is compared with the group and asked about. Nothing is reverted silently. Conflict C2 is removed by the boundary. | Pass (B) |
| S-26 | B's change lives in B's replica and file. A deleted `Settings.plist` and a β1 write have no effect on the N group. If B's own file is deleted, B heals it. B's change is never reverted. | Pass (B) |
| S-27 | `Settings.plist` rewrites cause no hint and no question on N Macs, only the status line about an older holzBar. A β1 rewrite can never displace an N user change. | Pass |

### G5 · Clocks and dates

| # | D1 outcome | Verdict |
|---|---|---|
| S-28 | B's dot is new to A (A's `context[B]` is smaller), whatever B's clock says. A fast-forward if A did not change that unit; a question if it did. *Difference:* a change by A to another unit merges; in Mode G, A asks. | Pass (D) |
| S-29 | Seen is not taken in. A relays L2 while still showing L1. A's drag of an item B moved supersedes only A's applied entry, so it becomes a sibling and a question. The other L2 items are applied at restart. Nothing is overwritten silently. | Pass |
| S-30 | Counters are compared only with the same Mac's. A Mac with a clock far ahead affects nobody else. Corrupt counters above 2^34 make the file unreadable, shown in the status. | Pass |
| S-31 | Turning sync off and on is a merge. B's entries are fast-forwards on A, not applied until restart. A's later drag of the same item becomes a sibling and a question. No dates are involved. | Pass |
| S-32 | W1 and W2 get distinct, increasing dots, whatever the clock or the second. Deleting a file cannot remove W2: it is in A's replica, and A heals the file. B's file cannot supersede W2, since B's context does not cover it. *Difference:* A asks only if B changed the same unit; W2 is never at risk, so a "missing write" is no reason to ask. | Pass (D) |
| S-33 | Keep supersedes exactly the dots shown. B's later entry was not shown and survives: asked again if it conflicts, applied otherwise. | Pass |

### G6 · The file goes missing, is restored or becomes unusable

| # | D1 outcome | Verdict |
|---|---|---|
| S-34 | B's change V2 is in B's replica. B heals its deleted or damaged file. A's file cannot supersede V2, so V2 is merged on A. A damaged file of A is unreadable for B until A heals it; B's view keeps everything it already merged. Never a silent apply. | Pass |
| S-35 | V2 waits in A's persisted replica, so the hint stays. A's writes relay V2 and never supersede it. *Difference:* A still writes its own file. | Pass (D) |
| S-36 | V2 is in the persisted replica, so at relaunch it is applied silently, as a fast-forward per `sync-1`. It survives the missing file. A's later change is an ordinary dot. | Pass |
| S-37 | Keep covered only "Show on hover". A's file relays B's `l26` entries, and A's own older entries for those items are superseded and never re-listed. After the deletion, A's write still relays them. B keeps L_B. A takes L_B in at restart, and A's drag of those items asks. | Pass |
| S-38 | There are no copies. A's two writes add two dots to "Show on hover" only. B keeps its arrangement and receives A's latest value. B's drag adds a dot. | Pass |
| S-39 | b1 is in B's replica and in B's healed file. No later write by A or a third Mac covers b1, since their contexts lack it. b1 reaches everyone once B's file is back. *Difference:* B asks only if another Mac changed the same unit concurrently; b1 cannot be lost, so no question is needed for that. | Pass (D) |
| S-40 | C holds and applied a1. B's file lacks a1 but cannot cover it. C keeps the arrangement through relaunches. *Difference:* no Choose Settings… on C, because nothing threatens a1 (INV-7). | Pass (D) |
| S-41 | Context and `applied` are separate facts. A relays B's entries and never publishes its stale layout. B keeps its arrangement. | Pass |
| S-42 | A's own file, restored to an older version, is behind A's replica, so A heals it. Joining the old version changes nothing. A keeps the drag, and its next write lists it. | Pass |
| S-43 | An empty file, a damaged plist, a plist without fields or a file over 4 MiB: unreadable, with the reason shown. A link or a folder in place of `holzBar/` or `Macs/`: folder unusable. Never "missing" or "empty". Nothing is written over another Mac's file. This Mac's own path is replaced only if it is a regular file; otherwise the status reads "blocked". A deliberate new setup still works (S-44). | Pass |
| S-44 | An empty folder: founding, publish everything, layout included, with no question; there is no legacy file. B then joins as in S-01 and S-07. Only an empty `Macs/` founds, so this never conflicts with S-34. | Pass |

### G7 · What an answer means

| # | D1 outcome | Verdict |
|---|---|---|
| S-45 | The sheet covers only "Show on hover", so Keep writes one fresh dot. The folder keeps L2 (B's entries, relayed by A). A takes L2 in at restart or launch. A drag of an L2 item before then becomes a sibling and a question. | Pass |
| S-46 | The answer supersedes only the dots shown, so B's new entry survives and nothing is lost. The hint returns as Choose Settings… if the new entry conflicts: the same unit, or any change in Mode G. *Difference:* in per-unit mode an unrelated new change shows Restart instead. | Pass (D) |
| S-47 | Keep wrote a fresh dot. Turning sync off and on is a merge, and L2 stays a fast-forward on A, so Restart. A drag of L2 items before the restart asks. B keeps L2. | Pass |
| S-48 | A's drag of an L2 item makes siblings, so Choose Settings… shows on A and on B. Turning sync off and on, Change… to the same folder, or off, drag, on: the siblings stay, and nothing is resolved silently. B keeps L2 applied until someone answers. | Pass |
| S-49 | Publishing never stops. The toggle is another unit, so no question, and B receives it. The hint stays Restart. At relaunch A applies L2 and keeps the toggle. | Pass |
| S-50 | Keep writes fresh dots that cover the dots shown, so the question cannot come back. The outcome does not depend on the order of any rules. | Pass |
| S-51 | The restored old file is dominated, so there is no conflict and no question on A. D's arrangement stays applied on A, B and D, with no Restart. The re-join variant behaves the same. | Pass |
| S-52 | A's a1 is in A's replica, and A heals its file. B's "Show on hover" change is a fast-forward on A, with no question. B gets A's arrangement after its restart. If A had also changed "Show on hover", it would be a question, and Keep would give A's value. *Difference:* no question arises and nothing is replaced, so B keeps its own setting change. | Pass (D) |
| S-53 | Keep writes a fresh dot superseding the shown {b2, a1}. A publishes and heals. B sees a fast-forward: Restart, not a question. After the restart B keeps its arrangement and has A's setting. | Pass |
| S-54 | There are no kept records. The state file is written atomically before every folder write. A cancelled task commits nothing partial. A lost state, or state from an old build, means a join: dot-less values are compared, and only differences are asked about. Never an overwrite on missing evidence. | Pass |

### G8 · Automatic versus user changes

| # | D1 outcome | Verdict |
|---|---|---|
| S-55 | Placements are `auto`: local layer, no dots. B shows no hint, A's Restart stays Restart, and they never replace B's arrangement. *Difference:* placements do not travel with A's next change; each Mac places new items by the synced "new items" setting. | Pass (D) |
| S-56 | No section change, so no dot. The hint is unchanged. | Pass |
| S-57 | The profile is compared per item; nothing changes, so no dot. The hint stays Restart. | Pass |
| S-58 | The dragged item is identified at drag start, by window ID resolved after the bar settles. It gets a dot even without a saved section. A concurrent remote entry for that item becomes a sibling and a question. Never reverted silently. | Pass |
| S-59 | A Command-click creates no dot. A drag gives a dot only to the dragged item, and only that item is stored. Displaced items keep their saved sections and are restored. | Pass |
| S-60 | Automatic stores skip items whose user entry was applied after the reconciliation read the bar. Even a stray local store creates no dot, so the published intent stays the user's and the next apply restores it. | Pass |
| S-61 | Moves in the Layout pane are recorded at once with their item and section, as dots. The restore reads the effective layout, user entries first, so the move is not reverted. | Pass |
| S-62 | First N run after β2: the layout entries are `pre`. If they differ from the group or the legacy file (founding), holzBar asks. Never silent. | Pass |
| S-63 | Learned keys are capped grow-only sets: union, silent, no hint, no restart. The flags are local. | Pass |

### G9 · Timing races

| # | D1 outcome | Verdict |
|---|---|---|
| S-64 | Restart first completes the pending capture (identify, dot, persist), then re-classifies. If the drag moved the same item as the waiting change, the sheet opens instead of the restart. Otherwise the restart applies, and the drag is kept and published. Keep keeps the drag. | Pass |
| S-65 | User edits and merge commits are serialized in the engine actor. A merge is committed as a join with the current state. There is no "synced" marker that could be set too early. The next publication is built from the latest state. | Pass |
| S-66 | Hints are recomputed from the committed state after every change, and again when clicked. | Pass |
| S-67 | Attribution uses the identity of the dragged item, not a snapshot taken before the arrangement. A displacement inside the settle window gets no dot. | Pass |

### G10 · Convergence and how often holzBar asks

| # | D1 outcome | Verdict |
|---|---|---|
| S-68 | B's latest file covers its earlier dot, so every unit has a single value. Silent at launch, or Restart while running. No question. | Pass |
| S-69 | There are no copies. Every user entry is live in the replicas and travels as a fast-forward. The Macs converge without another rearrangement (INV-15). | Pass |
| S-70 | None of that bookkeeping exists. Contexts are not capped by a Mac count. Counters never go back (time floor, mirrored counter, own-file check), so there are no extra questions. | Pass |

**Tally:** 51 Pass, 13 Pass (D) and 6 Pass (B), out of 70. No scenario fails.
- The Pass (D) rows are S-01, S-04, S-05, S-06, S-23, S-28, S-32, S-35, S-39, S-40, S-46, S-52 and S-55.
- The Pass (B) rows are S-18, S-19, S-20, S-24, S-25 and S-26.

---

## 14. Deviations from recorded decisions, and questions for the maintainer

| ID | Question | D1 default and why | Alternative |
|---|---|---|---|
| D1-Q1 | Questions per unit, or for the whole set of settings (`sync-1` letter)? | **Per unit.** Different settings changed on two Macs merge, nothing is overwritten, and only the same setting changed differently asks. The rejected "Pro Einstellung zusammenführen" never asked at all; this asks on every true conflict. | Mode G: one constant, no format change. Affects S-01, S-04, S-28, S-46. |
| D1-Q2 | May a Mac publish while a question or Restart waits (`sync-1` "pushes stay paused", `modal-alerts-1` point 4)? | **Yes.** The applied-context rule makes it impossible to supersede a waiting change. Pausing would only delay this Mac's other changes. | Pause publishing: a one-line gate, which hurts liveness. |
| D1-Q3 | At launch, apply non-conflicting units while others wait? | **Yes** (partial apply). | Hold everything until answered. |
| D1-Q4 | Does a value equal to the default count as "no user value" at a join (A2 OQ-4)? | **Yes** for U, D and PR keys (A1 S-01: defaults adopt silently). Layout entries existing before N always count as the user's. | Treat as `pre`, which asks. |
| D1-Q5 | One-time flags: OR-merge (`sync-1`) or local? | **Local** (A2 INV-K3, OQ-5). | — |
| D1-Q6 | β1 and N not syncing with each other (A2 OQ-2, A3 Q6)? | **Accept**, with the founding import, a status line and release notes. | A continuous one-way import from β1 (per-key three-way merge against the last import). Not recommended for a beta. |
| D1-Q7 | Placements travel with the next change (today's docs)? | **No**, they stay local (INV-A3). | — |
| D1-Q8 | macOS 26 drag with an unidentified item: `pre` (protect, maybe ask) or automatic (never ask, maybe lose the move locally)? | **`pre`.** | Automatic (A3 §8.4 default). |
| D1-Q9 | Naming the other Mac in the sheet (A2 OQ-10)? | Date only. | A user-chosen label stored in the folder. |
| D1-Q10 | Custom icon: cap at 256 KB PNG, or content-addressed blobs? | **Cap and convert once.** | Blobs in `Macs/blobs/` (A3 §8.11). |
| D1-Q11 | Cleanup horizon for departed Macs' files (A2 OQ-9)? | 180 days, and only when dominated. | — |
| D1-Q12 | Show a conflict between two other Macs on a third Mac? | **Yes** (answerable anywhere, resolved everywhere). | Hide it on Macs that wrote neither sibling. |

Further differences from earlier texts, all safe and listed for the docs:
- a re-identified Mac keeps its replica (S-06);
- a missing write is no longer a reason to ask (S-32, S-39, S-40, S-52);
- deleting the sync folder does not reset sync (A3 §10 Q9).

---

## 15. Implementation plan and cost

| Phase | Content | Lines (approx.) |
|---|---|---|
| P1 Core | `SyncCore`: the schema table with the R-CLASS-1 test, dots and counters, the join, writes, answers, classification, the launch, join and founding plans, cleanup, the attribution function, the codec and its checks. `SyncEngine` actor behind I/O protocols. Simulator, property tests, fuzzing, S-01–S-70 scenarios. | Core ~1,700; tests ~3,000 |
| P2 Glue | `FolderIO` actor (list, read, write, dataless handling, presenter and FSEvents, timers), `StateStore`, `DefaultsStore`, hint and sheet (sheet on the Settings window per `modal-alerts-1`), intent hooks in `HIDEventManager`, `LayoutBarMoves`, `Concealer27`, `LayoutProfiles`, `SectionRestore`, `SettingsBackup` import, and `SyncAttribution.automatic` around migrations. | ~800 |
| P3 Migration and text | First N run, founding import, legacy status line, icon conversion, new strings in en, de (Swiss), fr, it and rm, `strings-check.py`, `docs/features.md`, privacy doc, release notes (β1 limitation, pause-gap question). | ~200 plus strings |
| P4 Verification | Mutation gate, CI lint for main-thread I/O, the real-Mac check (§12 item 10). | — |

**Kept from the paused code:**
- `SettingsSyncFile.readContents`, `isUsableFolder` and `isLocal`;
- `SettingsSyncDevice`, with `uid` added to the hash;
- `SettingsSyncLocation` and `SettingsSyncPause`;
- `SettingsBackup.apply(_:removesMissingKeys:)`;
- the learned-key merge, extended with a cap;
- the canonical encoding of `SettingsSyncPolicy.digest`;
- the F-14 run-loop helper.

**Removed:**
- the base digests, the pending state, `seen`, `writeStamp`, `currentLayouts`, `copiedLayouts`, the kept records, `recentLayouts`, `allowedClockSkew`, `isNewer`, the layout-edit counters;
- `SettingsSyncPolicy.decide` and every rule in it.

**New strings**, in five languages:
- the sheet title and column labels;
- "Menu bar layout (%d items differ)";
- "saved by an older holzBar on %@";
- "Already decided on another Mac";
- status lines: too large, unreadable file, older holzBar in this folder, newer holzBar, waiting for download, a setting from another Mac cannot be used here.

**Existing strings reused:**
- "Settings changed on another Mac", "Restart", "Choose Settings…";
- "Use Settings from Sync Folder", "Keep This Mac's Settings", "Later", "Cancel";
- "The sync folder cannot be found".

**Sync stays paused** in releases until P1–P3 pass the simulator, the mutation gate and the real two-Mac check.
