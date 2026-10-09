# D2 · Settings sync, option 2: one shared file, a dot on every key, merge-then-write

Design for the settings-sync redesign after the pause in 0.0.7-beta2. Read-only work, 2026-10-07: nothing in the repository or its git state was changed.

**Inputs.**
- A1 (failure taxonomy and the 70 regression scenarios S-01 to S-70), A2 (requirements and invariants), A3 (research).
- The paused code on `audit/remediation-2026-10-05`: `SettingsSync.swift`, `Core/SettingsSyncPolicy.swift`, `SettingsSyncFile.swift`, `SettingsSyncDevice.swift`, `SettingsSyncLocation.swift`, `SettingsSyncPause.swift`, `SettingsBackup.swift`, `SectionRestore.swift`, `Concealer27.swift`, `SectionLayoutEditing27.swift`, `LayoutProfiles.swift`, `HIDEventManager.swift`, `LayoutBarPaddingView.swift`, `Defaults.swift`, `GeneralSettings.swift`.
- The six rounds and `sync-fix-SUMMARY.md` on `audit-manual/sync-fix`; `sa05-review2.json`, `syncfix-loop.json`, `syncfix-round4-issues.json`.
- Audit findings F-02, F-15, F-38, F-59, F-60, F-61.
- The decisions `sync-1` (with the rejected options in `manual-questions.json`), `modal-alerts-1` and `hotkey-conflicts-1`.
- The sync section of `docs/features.md`.
- `v0.0.7-beta1`: `SettingsSync.swift`, `SettingsSyncFile.swift`, `SettingsBackup.swift`.

**Conventions.**
- As in A1: β1 = 0.0.7-beta1 (and 0.0.6, whose sync code is byte-identical), β2 = 0.0.7-beta2 (paused), N = a Mac running this design. S-nn, RC-n and INV-n are A1's scenarios, root-cause classes and invariants.
- A2's invariants keep their A2 names (INV-S1, INV-B4, …).
- §3 defines the terms used from there on: unit, entry, dot, context, replica, applied set, origin, heal, genesis, group.
- "Option 1" means one file per Mac (A3's design C). This document designs option 2 and compares the two only in §10.6 and §16.

---

## 0. Summary

1. **Shape.**
   - There is one shared file per sync format: `<folder>/holzBar/Sync2/Settings.plist`. Only N Macs read and write it.
   - Every synced *unit* holds a multi-value register: its *entries*, each tagged with a *dot* (Mac ID, counter). A unit is a setting, a hotkey, an item icon, one menu bar item in one macOS version's layout, or the profile list.
   - The file carries one causal *context*, a version vector of every dot it has seen.
   - Each Mac keeps the same structure as its local *replica*. The replica is persisted atomically, in one defaults value, together with the settings it describes.
2. **Every write is a merge-then-write.** It runs in one coordinated read-and-write (`NSFileCoordinator`, `.forReplacing`), off the main thread, in this order:
   - read the file and any provider conflict copies;
   - join them with the replica;
   - write the join only when the file lacks something.

   A write carries other Macs' entries, but it can never supersede them. Superseding an entry needs a context that covers its dot without the entry, and only two things create one: a user's change, or an answer to a question. Each covers only the dots this Mac had applied, or the dots its sheet showed.
3. **Conflicts come from concurrency of dots, never from dates.** A conflict is a unit whose surviving entries hold two different values.
   - A stale, restored, duplicated or late file changes nothing, because all its dots are covered.
   - Deleting the file loses nothing, because every replica still holds the entries.
   - An answer supersedes exactly the entries the sheet showed. A value that arrived while the sheet was open is asked about again.
4. **The shared file cannot be `holzBar/Settings.plist`.**
   - β1 rewrites that file at every launch and 5 s after any defaults change, keeping only `modified`, `deviceID` and `settings`. Any metadata N puts there is gone at the next β1 write.
   - β1 applies anything N writes there silently, with key removal.
   - So the legacy file becomes read-only input: the genesis join and the legacy base (§8). β1 Macs and N Macs form separate groups until every Mac is updated.
   - This is the only form of option 2 that can meet INV-14 (§1.2).
5. **Can write-over still lose data?** It can lose a *write in the folder*, but not the *change*.
   - Macs have no compare-and-swap. Two Macs that write at the same time, based on the same version of the file, end up with one surviving copy: the provider keeps a conflict copy or drops one write (last writer wins).
   - D2 joins every conflict copy it finds (Dropbox, OneDrive, Nextcloud, Syncthing, Google Drive, iCloud conflict versions).
   - With last writer wins (SMB, or an iCloud winner whose losing versions are not visible on this Mac), the loser still holds its entries in its replica. It writes them again (*heal*) as soon as it reads a file whose context lacks its latest dot.
   - A change is lost for good only if both of these happen:
     - its copy in the folder is destroyed (a collision without a surviving copy, a deletion or a restore) before any other Mac reads it;
     - its author's replica is destroyed (Mac wiped, preferences deleted) before that Mac's next exchange.
   - One file per Mac removes the collision part of this condition. D2 does not (§10).
6. **Only the user's intent creates dots.** A dot is created at the user's action, per item:
   - a Layout-pane move;
   - a Command-drag, attributed to the item under the pointer;
   - a profile, but only for the entries it actually changes;
   - an import;
   - a Settings control.

   Placements, displacement by macOS, seeding, reconciliation, migrations and learned keys stay in a local layer and never sync. On macOS 26 this needs changes in `SectionRestore` and `HIDEventManager` that any design needs (§7).
7. **Per-OS layouts are two namespaces,** `L26/<item>` and `L27/<bundleID>`.
   - A Mac writes dots only in the namespace of the macOS version it runs.
   - The other namespace travels with its original dots.
   - There are no copies, no "current" lists and no stale-copy rules.
8. **Migration.**
   - The first N run is a join in which every existing value has *pre* origin. This covers layouts rearranged during the pause.
   - The first N Mac in a folder creates the group from the β1 file (*genesis*). It records that file's values as a *legacy base*.
   - Macs that update later are asked only about the values they changed after the group moved to N (§8).
9. **Regression walk (§14).** All 70 of A1's scenarios pass:

   | How they pass | Count | Scenarios |
   |---|---|---|
   | As the catalogue's "Must" states | 50 | |
   | With fewer questions than the Must names, because nothing is lost | 5 | S-32, S-39, S-40, S-51, S-52 |
   | Through the β1 boundary, with its documented limitation | 7 | S-18 to S-20, S-24 to S-27 |
   | Merged where sync-1's literal whole-set reading would ask (decision M-1) | 4 | S-04, S-23, S-28, S-48 |
   | Same safety goal, different mechanism | 4 | S-05, S-06, S-35, S-55 |

   S-58, S-59 and S-67 also depend on the layout-capture changes of §7.
10. **Decisions the maintainer must take (§15):**
    - M-1: per-unit conflicts (proposed) or sync-1's literal whole-set rule;
    - M-3: no push pause while a question waits;
    - M-4: one-time flags stay local;
    - the β1 boundary;
    - the F-61 icon cap;
    - the "Replace…" action.
11. **Verdict.** D2 is workable: every scenario passes and every write-over is recoverable while its author's replica lives. It trades option 1's *structural* exclusion of lost updates for an *operational* one: a heal protocol that must run, plus a single file whose damage blocks every Mac's publications until someone acts. It is about the same size as option 1, plus roughly 150–250 lines for conflict copies and healing. Choose D2 only if the maintainer values a single inspectable file over that guarantee (§16).

---

## 1. Scope and the decisions this design takes

### 1.1 What stays from the paused code, and what goes

**Kept (local engineering that does not depend on the replication model):**
- F-15: background I/O on one serial queue, and a launch read bounded to about 1 s that skips dataless files (`readForLaunch`, `isLocal`).
- F-18: bookmarks resolved with `.withoutMounting`; never mounting.
- F-38: `SettingsSyncDevice`, the salted hardware hash and `verifyDeviceIdentity`.
- F-60: `SettingsBackup.apply(_:removesMissingKeys: false)`.
- Safe reads: `SettingsSyncFile.readContents` (`O_NOFOLLOW`, `fstat`, bounded) and `isUsableFolder`.
- `SettingsSyncLocation`, `SettingsSyncPause`, the presenter and folder watcher, the F-14 run-loop helper.
- The hint, the sheet and their strings: "Settings changed on another Mac", "Restart", "Choose Settings…", "Which settings should holzBar use?", "Use Settings from Sync Folder", "Keep This Mac's Settings", "Later", "Cancel".
- The canonical encoding in `SettingsSyncPolicy.digest`, used only to test whether two values are equal.

**Removed:**
- `decide()` and its action enum;
- the base digests, `pending`, `postponed`, `forcesWrite`;
- the layout-edit counter;
- `currentLayouts`, `copiedLayouts`, `seen`, `writeStamp`, `lastWritten`, the kept and recent layout records;
- `isNewer` and `allowedClockSkew`;
- `fileToWrite`, `withoutStaleLayouts`, `mergedLayout`, `ownLayoutToTakeIn`, `layoutToTakeIn`.

### 1.2 Which file: the legacy path or a new one (D2-1)

"Keep one shared file" can mean two things. Only the second survives β1, whose behaviour is fixed (A1 §2.1, A2 §2.6).

| | 2-L: add per-key metadata to `holzBar/Settings.plist` | 2-N: a new file, `holzBar/Sync2/Settings.plist` |
|---|---|---|
| β1 writes it | At every launch (`performSetup` sets `isEnabled` from false to true, which pushes) and 5 s after any defaults change, including automatic ones. Each write keeps only `modified`, `deviceID` and `settings`, so every dot and the context disappear several times a day. | Never. β1 reads and writes only `holzBar/Settings.plist`. |
| β1 applies it | Silently at its next launch, if the file is newer than its `lastSynced`. It removes every key the file lacks or that fails validation. A safe N write would therefore have to carry every β1 Mac's unseen changes (A1 §5.4 C1, C3). | Never. |
| N reads β1's writes | As states without lineage, several times a day. A β1 user's change and a β1 rewrite look the same (A1 §5.2 pair 1, C2). Each β1 write is either a question or a stall. | Only once, at genesis, as join input without dots (§8.3). |
| Result | INV-14 fails by construction. The [CONFLICT] scenarios S-19, S-25 and S-26 cannot pass. | INV-14 holds. Limitation: β1 Macs stop receiving N Macs' changes (§9). |

**Decision.** The shared file is `holzBar/Sync2/Settings.plist`, written only by N. N never writes `holzBar/Settings.plist`.

The subfolder keeps β1's folder watcher quiet. β1 watches `holzBar/` with a `DispatchSource` for write, rename, delete and link events, so N's atomic renames inside `Sync2/` do not fire it. β1's presenter may still see subitem changes. It then re-reads `Settings.plist`, finds nothing newer and does nothing (β1 `checkForNewerSettings`).

### 1.3 Decisions this design takes that depart from a requirement or a decision

Each is listed again in §15 for the maintainer.

| # | This design | Departs from | Why |
|---|---|---|---|
| M-1 | Conflicts per unit. Concurrent changes to *different* settings merge without a question. A "strict" mode that asks for the whole set is specified in §6.5. | A2 R-POL-1 ("decides for the whole set"); the wording of sync-1 ("both Macs changed since the last sync → ask") | Per-key dots are the premise of option 2. Merging different keys overwrites nothing, so "nothing is lost unasked" still holds. A3 recommends the same. |
| M-2 | N never writes the β1 file. β1 and N Macs do not sync with each other. | A2 R-COMPAT-2 allows writing it under conditions | §1.2; A2 and A3 recommend the same. |
| M-3 | A Mac keeps publishing while a remote change or a question waits. | sync-1 ("pushes stay paused"); modal-alerts-1 point (4) | Those rules prevented whole-state overwrites. A D2 write is a join: it carries the waiting entries unchanged and supersedes none of them (§6.4). |
| M-4 | One-time flags stay local: `MacOS27LayoutSeeded`, `hasMigrated*`, `HasImportedIceSettings`. Learned *sets* still merge by union. | sync-1 ("OR the flags") | A2 INV-K3: an OR'd flag skips work this Mac still needs. |
| M-5 | `CurrentLayoutProfile` and the device tuning keys (`MacOS27ClickRestoreDelay`, `MacOS27IceBarWaitsForRefresh`) stay local. A profile applied by a Space or display binding is automatic. | Today all are importable and synced; `LayoutProfiles.apply` counts a bound profile as the user's | A2 OQ-6 and OQ-7 defaults. Otherwise one Mac's Space switch changes another Mac's layout. |
| M-6 | A fresh install whose values are all unset adopts the folder silently. | A2 OQ-4 default ("ask") | A1 S-01: "If B's user settings are defaults …, B adopts silently." |
| M-7 | A present file that stays unreadable or too large is never overwritten automatically. "Replace…" in Settings writes over it with the user's consent. | none (A2 INV-Z6) | Sync must not stall for good, and nothing is overwritten unasked. |

---

## 2. Overview

```
 Mac A (N)                              sync folder (any provider)                 Mac B (N)
 ┌─────────────────────────────┐        <folder>/holzBar/                          ┌──────────────┐
 │ UserDefaults: the settings  │          Settings.plist        β1 only. N reads   │  same as A   │
 │   holzBar uses ("applied")  │                                it at genesis and  │              │
 │ SettingsSyncState (one key):│                                watches its date;  │              │
 │   replica, applied sets,    │                                never writes it.   │              │
 │   origins, counter, group,  │          Sync2/Settings.plist  N's shared state.  │              │
 │   join in progress          │                                Merge-then-write.  │              │
 └─────────────────────────────┘          Sync2/<conflict copies>  joined, deleted └──────────────┘
                                                                   once dominated
```

**Flows.**
- **A user's change.**
  1. The capture (§7.2) creates a dot for the unit and persists the local state, synchronously.
  2. About 2 s later (debounced), an exchange runs: a coordinated read, a join, and a write if needed (§5.4).
  3. The hint is recomputed.
- **A file event, a poll, wake or app activation:** an exchange.
- **Launch.**
  1. Load the state and reconcile it with `UserDefaults`.
  2. Read the shared file, at most 1 s, and only if it is local.
  3. Join it with the replica.
  4. Apply the fast-forwards silently, before any model reads the settings.
  5. After setup: an exchange, and the hint.
- **The user acts on the hint.**
  - **Restart:** relaunch, which applies the fast-forwards.
  - **Choose Settings…:** the sheet. Use and Keep each write one resolution entry per conflicting unit; Use then relaunches. Later writes nothing.

---

## 3. Data model

### 3.1 Identity, counters, dots

- **Mac ID.**
  - A random UUID: today's `SettingsSyncDeviceID`, verified against the salted hardware hash (F-38).
  - It changes on a hardware-hash mismatch (clone, Migration Assistant), on the one-time rotation when no hash is stored yet (`.firstSeen`), and on an own-ID anomaly (§5.8).
  - The hash and the salt never leave the Mac.
- **Counter.** Each Mac's counter strictly increases and is never reused:

  ```
  next = max(last + 1, unixMillis(now), replica.context[me] + 1, cacheHighWater + 1)
  ```

  - `unixMillis(now)` is a floor that keeps a counter from going back after a Time Machine restore of the preferences.
  - `replica.context[me]` covers this Mac's own newer writes found in the folder.
  - `cacheHighWater` is optional: the last counter mirrored in `~/Library/Caches/com.holzcloud.holzBar/SyncCounter`, which Time Machine excludes by default. It is an extra floor after a restore of the preferences alone.
  - Counters are compared only with counters of the same Mac. The clock serves only as a floor for uniqueness and never orders anything across Macs (INV-3, INV-F9).
- **Dot.** A pair (Mac ID, counter) that names one user change to one unit. One write that changes 20 units creates 20 dots.

### 3.2 Units: the schema table (pure Core, with a test that every `Defaults.Key` has a class; R-CLASS-1)

| A2 class | Keys | Unit key(s) | Value | How it syncs |
|---|---|---|---|---|
| U, user settings | `ShowIceIcon`, `UseIceBar`, `IceBarLocation`, `IceBarDisplays`, `ShowsNotchOverflowInIceBar`, `ShowOnClick`, `ShowOnHover`, `ShowOnScroll`, `ShowOnHoverDelay`, `AutoRehide`, `RehideStrategy`, `RehideInterval`, `TempShowInterval`, `ItemSpacingOffset`, `HolzBarIconShowsCaptureDot`, `EnableAlwaysHiddenSection`, `ShowAllSectionsOnUserDrag`, `SectionDividerStyle`, `HideApplicationMenus`, `KeepsDockIconHidden`, `EnableSecondaryContextMenu`, `NewItemsPlacement`, `KeepLiveActivitiesVisible`, `AutoZenWhileSharingScreen`, `OpenHiddenItemsInMenuBar`, `RevealOnChangeItems`, `SpacerCount`, `SpacerWidth`, `RevealRules` | `S/<key>`, one per key. Optional groups, a product decision: `S/rehide` = {AutoRehide, RehideStrategy, RehideInterval}; `S/shelf` = {UseIceBar, IceBarLocation, IceBarDisplays, ShowsNotchOverflowInIceBar} | The value, or *removed* | Multi-value register with dots |
| U, hotkeys | `Hotkeys` (action → data) | `H/<action>`, one per entry | The key combination data, or *removed* | Same |
| D, user data | `IceIcon` with `CustomIceIconIsTemplate` | `S/icon`, one group: they change together | {data ≤ 256 KB encoded, isTemplate} | Same, with a cap |
| D, user data | `MenuBarAppearanceConfigurationV2`, `ItemGroups` | `S/<key>` | Data ≤ 256 KB | Same |
| D, user data | `ItemIcons` (choice → file name; the PNGs stay local, A2 OQ-8) | `I/<itemKey>`, one per entry | The file name (plain name only, R-SEC-3), or *removed* | Same |
| PR, profiles | `LayoutProfiles` (JSON) | `P/LayoutProfiles`, the whole list (A2 OQ-12) | Data | Same |
| LAY, macOS 26 | `ItemSections` (identity key → section index) | `L26/<identityKey>` | Section index (`profileIndex`) | Same; written only by macOS 26 Macs and only from intent (§7) |
| LAY, macOS 27 | `MacOS27Layout` (bundle ID → section) | `L27/<bundleID>` | 0 visible, 1 hidden, 2 always hidden. **Visible is an explicit 0**, never absence. | Same; written only by macOS 27 Macs and only from intent |
| LRN, learned | `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners` | `learned/<key>` | A set of strings | Union, capped deterministically: the 2,048 smallest by SHA-256 (A2 INV-K2). No dots, no questions. |
| FLG, one-time steps | `MacOS27LayoutSeeded`, `hasMigrated0_8_0` … `hasMigrated0_11_13_1`, `HasImportedIceSettings` | none | — | Local (M-4) |
| CTX, TUNE | `CurrentLayoutProfile`, `MacOS27ClickRestoreDelay`, `MacOS27IceBarWaitsForRefresh` | none | — | Local (M-5) |
| LEG | The Ice-era input keys | none | — | N never authors them |
| LOC | `SyncsSettingsWithICloud`, `Debug…`, every `SettingsSync…` key, `NSWindow Frame…`, `NSStatusItem…`, `SU…` | none | — | Never |

**`Cmp(m)`, the units a Mac compares and asks about:** the kinds `S`, `H`, `I` and `P`, plus the layout namespace of the macOS version it runs. It never includes the other namespace, the learned sets or the local keys (A2 INV-L1).

### 3.3 Entries, registers, the context, and what "superseded" means

```swift
struct Dot: Hashable, Comparable { var mac: MacID; var counter: UInt64 }
typealias Context = [MacID: UInt64]                  // version vector: per Mac, the highest counter seen
func covers(_ c: Context, _ d: Dot) -> Bool { (c[d.mac] ?? 0) >= d.counter }

enum UnitValue: Equatable { case set(CanonicalValue), removed }   // equality through the canonical encoding
struct Entry { var dot: Dot; var value: UnitValue; var written: Date }   // `written`: display only

struct Replica {
    var group: GroupID                               // random, created at genesis (§5.8)
    var context: Context
    var units: [UnitKey: [Entry]]                    // multi-value register per unit, usually one entry
    var learned: [LearnedKey: Set<String>]
    var legacyBase: [UnitKey: Digest]?               // §8.3; set once at genesis
}
```

- **One context per state is enough.** Each Mac's replica is cumulative: it reflects all of its own earlier dots, either as entries or as their supersession. So a state that holds (A, 1005) has also seen every earlier dot of A. Counters may have gaps, because the clock floor skips numbers; a gap is just a number never used.
- **Superseded.** An entry with dot `d` is superseded in state S when S's context covers `d` and S does not contain the entry.
  - Only a write that saw the entry can produce that: a user's change or an answer.
  - A plain join or relay keeps every entry the other side has not seen.
- **Why a dot per entry rather than a full version vector per key.** "Every key carries a version vector" is realised as a dot on every entry plus one vector per state. A full vector on every key (Syncthing's per-file vectors, applied per key) would also order versions without clocks, but:
  - it costs keys × Macs;
  - it cannot hold two concurrent values of one key without extra structure;
  - it turns "the answer covers exactly what the sheet showed" into a comparison of vectors instead of a set of dots.

  Dots plus one context carry the same causal information (A3 §4.3, the causal-context formalism).

### 3.4 This Mac's local state, persisted atomically

```swift
struct SyncLocalState {
    var me: MacID
    var counter: UInt64
    var replica: Replica                 // everything this Mac has seen: the "seen" fact
    var applied: [UnitKey: Set<Dot>]     // per unit, the dots whose value UserDefaults reflects: the "taken in" fact
    var origin: [UnitKey: Origin]        // only for values without applied dots: .auto, .pre, .uncertain
    var join: JoinInProgress?            // tentative state while a join question is open (§5.7)
    var pendingCaptures: [UnitKey]       // layout moves whose value is not read from the bar yet (§7.2)
    var lastLegacySeen: Digest?          // the β1 file's (modified, deviceID) digest at the last look (§9)
    var formatVersion: Int
}
```

- **Two facts kept apart.** "Seen" is `replica.context` plus entries, and "taken in" is `applied`. Lumping them together was RC-5's error (A1 §5.2 pair 8).
- **Origins** of values without dots:
  - `.auto`: holzBar or macOS wrote it, through placement, seeding, displacement, reconciliation, a migration or the hotkey clean-up of F-30. A remote intent may replace it silently (SA-05).
  - `.pre`: the value existed before this Mac joined: a migration from a build before N, a lost local state, a downgrade period. It is protected and compared at the join.
  - `.uncertain`: a layout change whose attribution failed (§7.2). It is protected, so a different remote value makes a question on this Mac. It is not published until the user confirms it.
- **Persistence.**
  - The whole state is one binary-plist `Data` in one defaults key, `SettingsSyncState`.
  - The `SettingsSync` prefix keeps it out of export, import and sync.
  - It sits in the same preferences domain as the settings it describes. A Time Machine restore of the preferences therefore restores both together, and they stay consistent (§10.5).
  - One `defaults.set` is atomic, so a quit or crash leaves either the old state or the new one, never a mix (INV-10).
- **Order of operations.**
  - **User changes:** create the dot and persist, before the change reaches the bar or the file (§7.2).
  - **Applies:** write the `UserDefaults` values first, then persist `applied`. A crash in between is repaired at launch by equality: the value equals an entry's value, so those dots count as applied (§5.5).

### 3.5 Learned sets, flags, local keys

- Learned sets merge by union. Receivers union them into their local keys at the next launch, silently, with no hint (A2 INV-K1, R-POL-6).
- A Mac publishes a learned-only change at most once per hour. Otherwise the change rides on the next write (R-FUN-8).
- Flags, `CurrentLayoutProfile`, the tuning keys, the Ice-era keys and every local key are never written into the file and never touched by an apply.

---

## 4. File format and versioning

### 4.1 Paths and folder rules

```
<chosen folder>/holzBar/                       holzBar's folder (exists for β1 too)
<chosen folder>/holzBar/Settings.plist         β1's file: read at genesis, its date watched (§9); never written by N
<chosen folder>/holzBar/Sync2/Settings.plist   N's shared state ("the canonical file")
<chosen folder>/holzBar/Sync2/<other *.plist>  provider conflict copies (§4.5)
```

- holzBar creates `holzBar/` and `Sync2/` only inside an existing, accessible chosen folder, and only after `lstat` shows real folders, not links (`isUsableFolder`; R-IO-5, R-SEC-5).
- Nothing is written while the folder is unavailable.
- A future format that older N builds could not merge uses a new folder (`Sync3/`). N builds then form separate groups, like β1 and N do (§4.4).

### 4.2 Fields of the canonical file

```
{
  "format": 2,                       // major: equals the folder generation (Sync2)
  "minor": 0,                        // additive changes only (§4.4)
  "classes": 1,                      // version of the key-class table (R-CLASS-3)
  "group": "<random UUID>",          // the sync group; created at genesis
  "macs": ["<MacID>", ...],          // table of Mac IDs; dots refer to an index
  "context": [<UInt64>, ...],        // per Mac index: the highest counter seen
  "units": {
    "S/ShowOnHover": [ { "d": [0, 1759820551234], "v": true,  "t": <date> } ],
    "H/toggleHidden": [ { "d": [1, 1759820600001], "v": <data>, "t": <date> },
                        { "d": [0, 1759820600777], "x": true,  "t": <date> } ],   // two concurrent entries: a conflict
    "L27/com.example.app": [ { "d": [1, 1759820700000], "v": 1, "t": <date> } ],
    ...
  },
  "learned": { "KnownItemTags": [...], "KnownApplications27": [...], "TitleChangingItemOwners": [...] },
  "legacyBase": { "S/ShowOnHover": "<sha256>", "L26/<id>": "<sha256>", ... },     // §8.3, optional
  "legacySeen": "<sha256 of (modified, deviceID) of the β1 file at genesis>",    // §9, optional
  "written": <date>                  // display only
}
```

- An entry holds `d` (the dot), then either `v` (the value) or `x: true` (*removed*), and `t` (the author's wall-clock time, for display only).
- Absence of a unit means "no information", never "deleted". A deletion is an explicit `x: true` entry (A2 R-FUN-5, INV-S4, INV-S5).

### 4.3 Encoding, equality, size

- **Encoding.**
  - Binary plist, not XML: no second base64 layer (F-61).
  - Entries are sorted by dot, so equal states encode almost identically. Correctness never depends on bytes.
- **Equality.**
  - Two values are equal when their canonical digests are equal (`SettingsSyncPolicy.digest`: sorted keys, 1 equals 1.0, JSON inside `Data` compared by content).
  - Two states are equal when they are equal as sets of entries, contexts, learned sets and base.
  - A Mac writes only when `join(replica, file) ≠ file` in this sense, so it never writes because of byte noise.
- **Size budget.**
  - The limit `Lmax` is 2 MiB for `Sync2/Settings.plist`, for readers and writers alike. β1 never reads this file, so its 1 MiB limit does not apply; INV-Z2 holds because writer limit equals reader limit.
  - Caps per value: 256 KB encoded for `S/icon`, `S/MenuBarAppearanceConfigurationV2` and `S/ItemGroups`; learned sets at 2,048 elements each; at most 64 Mac IDs in the table, with older ones kept; entry counts are bounded by units × Macs.
  - Typical file: about 70 setting units, about 2 × 100 layout units and about 30 hotkeys, each entry about 40–80 B. That is 20–60 KB, plus an icon of up to 256 KB.
  - Worst case with four unanswered concurrent icons: about 1.1 MiB, still under `Lmax`.
- **Writer side (F-61, INV-13, R-SIZE-2).**
  - A *new* value over its cap is not published. The unit stays local, and Settings shows "This Mac's custom icon is too large to sync" (new strings).
  - A merged state over `Lmax` is not written. The previous file stays, and Settings shows a warning until answers or smaller values bring it under the limit.
  - A file another Mac would refuse is never written.
- **Ice icons up to 8 MiB** are converted once, at migration, to a PNG of at most 128 KB (F-61, fix 3). The template image is stored once (fix 4).

### 4.4 Versioning

- **`format` (major)** equals the folder generation.
  - A file in `Sync2/` with `format` > 2 is from a newer holzBar. N never writes over it and never prunes it. Settings shows "This sync folder is used by a newer holzBar. Update holzBar to keep syncing." (R-COMPAT-7, INV-B8).
  - A newer major always uses a new folder, so this case arises only from a bug or a hand-made file.
- **`minor`** may only add:
  - new unit kinds and new keys. Older N Macs join them by dots and pass them through byte for byte, without understanding the values;
  - new entry fields, also passed through;
  - informational top-level fields.

  A change that needs any other merge rule is a new major.
- **The pass-through rule (A3 §4.5 pitfall).** A reader never drops an entry it cannot interpret while advancing its context: an unknown unit kind, a value that fails validation, or a value over a cap. If it did, every other Mac would read "seen and superseded" and delete the entry. That would be F-59 and F-60 in CRDT form. Validation happens only when values are applied to `UserDefaults`, and only on the receiving Mac.
- **`classes`** versions the class table. A key that a newer release moves into a synced class is passed through by older N Macs. A key it moves out of sync is still published by older N Macs and ignored by newer ones.

### 4.5 Which files a read considers

- **The canonical file**, read inside the coordinated read and write (§5.4).
- **Conflict copies.** Every other regular, non-hidden file in `Sync2/` whose name ends in `.plist` and whose content parses as a `format` 2 state. Read with individual coordinated reads, bounded, at most 16 files of at most `Lmax` each. This covers:
  - `Settings 2.plist` (iCloud, Finder);
  - Dropbox's "… (… conflicted copy …).plist";
  - OneDrive's `Settings-<ComputerName>.plist`;
  - Nextcloud's "(conflicted copy …)";
  - Syncthing's `.sync-conflict-…`;
  - Google Drive's `Settings (1).plist`.

  Their names are never logged or copied, because they can carry user or computer names (R-PRIV-3). Safety never depends on recognising a name (INV-F4 (a)): a copy matters only through its content.
- **iCloud conflict versions.** `NSFileVersion.unresolvedConflictVersionsOfItem(at:)` for the canonical file, joined like copies, then marked resolved after a successful write. This must be verified on a real Mac without the iCloud entitlement. It is not needed for correctness, because the heal covers it (§10.3).
- **Temporary files** (a leading dot, `.syncthing.*.tmp`), folders, links and files over `Lmax` are ignored or refused, never followed.

---

## 5. Algorithms (all decisions are pure Core functions; the glue only does I/O and UI)

### 5.1 Join

```swift
func join(_ a: Replica, _ b: Replica) -> Replica {           // precondition: a.group == b.group
    var out = a
    out.context = a.context.merging(b.context, uniquingKeysWith: max)
    for u in Set(a.units.keys).union(b.units.keys) {
        let ea = a.units[u] ?? [], eb = b.units[u] ?? []
        let da = Set(ea.map(\.dot)), db = Set(eb.map(\.dot))
        let keep = ea.filter { db.contains($0.dot) || !covers(b.context, $0.dot) }     // a's entry survives unless b superseded it
                 + eb.filter { !da.contains($0.dot) && !covers(a.context, $0.dot) }    // b's new entries a has not superseded
        out.units[u] = keep.isEmpty ? nil : keep.sorted { $0.dot < $1.dot }
    }
    out.learned = a.learned.merging(b.learned) { capped($0.union($1)) }
    out.legacyBase = a.legacyBase ?? b.legacyBase
    return out
}
```

- **Properties, tested as properties:**
  - commutative, associative, idempotent;
  - `join(x, past(x)) == x`;
  - the context only grows.
- **Collision check.** Two entries with the same dot and different values mean that two writers used one Mac ID. Both are kept, so the unit shows a conflict and nothing is dropped. The Mac whose ID it is re-identifies (§5.8).

### 5.2 A user's change: the applied-context rule

```swift
mutating func userChanged(_ u: UnitKey, to v: UnitValue, now: Date) {
    let d = Dot(mac: me, counter: nextCounter(now))
    let saw = applied[u] ?? []                                     // what this Mac's user saw
    replica.units[u] = (replica.units[u] ?? []).filter { !saw.contains($0.dot) } + [Entry(dot: d, value: v, written: now)]
    replica.context[me] = d.counter
    applied[u] = [d]
    origin[u] = nil
    persist()                                                      // before anything else happens
    schedulePublish(after: .seconds(2))
}
```

- A remote entry this Mac received but had not applied is not in `applied[u]`. So it survives as a sibling, and the unit becomes a conflict on both Macs (A3 §8.4). This is the per-unit form of sync-1's rule (b): another Mac's newer version arrived while this Mac had user changes.
- A remote entry that superseded this Mac's applied entry is in the register while the applied dot is not. The new write keeps it, so the change is again a conflict, as it must be: the user changed a value they had not seen.

### 5.3 Classifying a unit, and the hint

```swift
enum UnitState { case quiet, fastForward(UnitValue), conflict(values: [UnitValue], stake: Bool), protected(local: UnitValue, remote: UnitValue) }

func classify(_ u: UnitKey) -> UnitState {
    let entries = replica.units[u] ?? []
    guard !entries.isEmpty else { return .quiet }                       // no information
    let values = distinct(entries.map(\.value))
    let local = projectedLocalValue(u)                                  // what UserDefaults holds now
    if values.count == 1 {
        let v = values[0]
        if v == local { applied[u] = Set(entries.map(\.dot)); origin[u] = nil; return .quiet }   // equal means silent (INV-P2)
        if origin[u] == .pre || origin[u] == .uncertain { return .protected(local: local, remote: v) }
        return .fastForward(v)                                          // superseded what this Mac applied, or replaces .auto
    }
    let stake = entries.contains { applied[u]?.contains($0.dot) == true } || values.contains(local)
    return .conflict(values: values, stake: stake)
}
```

| Hint on Mac m | When |
|---|---|
| **Choose Settings…** | m is joining with differences (§5.7); or some unit in `Cmp(m)` is `.conflict(stake: true)` or `.protected` |
| **Restart** ("Settings changed on another Mac") | Otherwise, when some unit in `Cmp(m)` is `.fastForward` |
| Nothing | Otherwise. Learned-only changes, the other namespace, and conflicts in which m has no stake never cause a hint. |

- **Capture first, then classify.** A local change that the defaults observer has not captured yet (its 2 s debounce) is captured before any classification. Otherwise `projectedLocalValue` would differ from the applied entries, and the unit would look like a fast-forward back to the old value. At launch, the reconcile step does the same (§5.5 step 4).
- **Bystanders.** In a conflict where m has no stake (two other Macs disagree), m keeps its applied value. Settings shows a passive "Waiting for a choice on another Mac" line (optional string, §6.2). A2 INV-P1 allows no prompt there.
- The hint is a pure function of the current state, recomputed after every change of it (S-66).

### 5.4 Exchange: merge-then-write under `NSFileCoordinator`

Runs on the serial file actor, never on the main actor (F-15, INV-R1), with a time bound: the coordinator is cancelled after 10 s and the exchange retried later (R-IO-7).

```swift
func exchange(_ snapshot: SyncLocalState) -> ExchangeResult {
    guard folderIsUsable() else { return .unavailable }                      // unmounted, link, missing: idle, status
    let copies = readConflictCopies()                                         // §4.5, each bounded and coordinated
    var result = ExchangeResult.retry
    var error: NSError?
    NSFileCoordinator(filePresenter: presenter).coordinate(                  // own presenter excluded from own write
        readingItemAt: canonical, options: [],
        writingItemAt: canonical, options: .forReplacing, error: &error) { readURL, writeURL in
        switch readCanonical(readURL) {                                       // O_NOFOLLOW, fstat, size, parse, validate shape
        case .notLocal, .partial, .stale:      result = .retry(download: true); return     // dataless, downloading, half-written
        case .refused(let why):                result = .blocked(why); return              // too large, not a regular file, corrupt
        case .newerFormat:                     result = .blocked(.newerFormat); return
        case .absent:                          result = merge(nil, copies, snapshot, writeURL)
        case .state(let file):                 result = merge(file, copies, snapshot, writeURL)
        }
    }
    if error != nil { return .retry(download: false) }
    afterWrite(result, copies)                                                // after .written or .upToDate: resolve iCloud versions,
                                                                              // delete copies the canonical file now dominates (M-8)
    return result
}

func merge(_ file: Replica?, _ copies: [Replica], _ s: SyncLocalState, _ writeURL: URL) -> ExchangeResult {
    var folder = file ?? Replica.empty(group: s.replica.group)               // absent file: no information, same group
    if folder.group != s.replica.group { return .otherGroup(folder) }        // another group's file: a join (§5.7)
    for c in copies where c.group == folder.group { folder = join(folder, c) }
    let merged = join(s.replica, folder)
    guard merged != file else { return .upToDate(folder) }                   // nothing to add: no write (INV-C4)
    guard s.join == nil else { return .joinPending(folder) }                 // nothing is published before a join is decided
    let bytes = encode(merged)
    guard bytes.count <= Lmax else { return .tooLarge(folder) }              // previous file stays; warning
    write(bytes, atomicallyTo: writeURL)                                      // temp file with a leading dot + rename
    return .written(folder: folder, written: merged)
}

// main actor
func finish(_ r: ExchangeResult) {
    if let seen = r.folderState { state.replica = join(state.replica, seen) } // join into the CURRENT state, never replace it,
    if let w = r.written { state.replica = join(state.replica, w) }          // so edits made during the exchange stay (S-65)
    persist(state); recomputeHint()
}
```

- **When an exchange runs:**
  - 2 s after a user's change (debounced);
  - on a presenter event (iCloud) or a `DispatchSource` event on `Sync2/` (other providers);
  - on wake and on app activation;
  - every 5 min while running, and every 60 s when the folder is on a network volume, since FSEvents does not see other computers' writes to SMB;
  - after setup.
- **Writes and heal.** A Mac writes whenever the file lacks something its replica has:
  - **its own dots:** `file.context[me] < replica.context[me]`. It writes at once;
  - **another Mac's entries it relays** (the relay heal). It first waits a random 5–60 s and re-reads, so that four Macs do not heal at the same moment.

  Both are honest: the written state carries every entry its context claims (A2 INV-S3).
- **iCloud gate.** A write happens only when the canonical file is `.current`. If iCloud knows a newer version, the Mac first starts the download (`startDownloadingUbiquitousItem`, or a coordinated read in the background) and retries. This removes most iCloud collisions. On other providers, such a status is not available in general.
- **What coordination buys and does not buy** is in §10.1.

### 5.5 Launch (in `AppDelegate.init`, at most about 1 s, no writes, no UI)

1. **Load** `SettingsSyncState`. If it is missing or unreadable, rebuild it: a new empty replica, every local value `.pre`, and the Mac joining (never read as evidence; INV-10).
2. **Migrate** if this is the first N run (§8.2).
3. **Tripwire.** If `SettingsSyncLastSynced` exists again, a build before N ran sync on this Mac (a downgrade). N removed that key after migrating, and β1 writes it on every push and apply. The Mac then joins, with its changed values `.pre` (§8.6).
4. **Reconcile `UserDefaults` with the state.** For each unit of kind `S`, `H`, `I` or `P`, let `lv` be the projected local value and `av` the value of the applied entries:
   - `lv == av`: nothing to do.
   - `lv` equals the value of other entries of the unit: those dots become applied. This repairs a crash between an apply and its record.
   - Otherwise, while joining: `.pre`.
   - Otherwise, the value changed while holzBar was not watching: `defaults write`, or a crash after a Settings change but before its dot. If the change comes from a registered automatic writer that ran this launch (a migration, the hotkey clean-up), it is `.auto`. Otherwise it is `userChanged(u, to: lv)`, a change of this Mac; a concurrent remote entry then makes it a conflict.
5. **Layout units of this macOS version.** Where an applied intent exists and the local entry differs, automatic code overwrote it, so the intent is written back. Where a pending capture exists from a quit within 1.5 s of a drag, it is flushed (§7.2).
6. **Read** the canonical file only if it is local and not dataless, within the remaining budget (`readForLaunch`, F-15). If it is read and belongs to the same group, it is joined. Conflict copies wait for the background exchange.
7. **Apply silently** every `.fastForward` unit in `Cmp(m)`:
   - `S`, `H`, `I` and `P` through `SettingsBackup.apply(_:removesMissingKeys: false)`, with only the changed keys;
   - layout intent entries into `ItemSections` or `MacOS27Layout` (on macOS 27, value 0 removes the entry);
   - the learned unions.

   Then record `applied` and persist. Conflicts and protected units are not applied (R-POL-5).
8. After setup: an exchange, which heals if needed, and the hint. A dialog never opens during `init`.

### 5.6 Answers

The sheet keeps a **snapshot**: for each conflicting or protected unit it shows, the exact entries (dots and values) on screen.

| Answer | Effect |
|---|---|
| **Use Settings from Sync Folder** | For each unit in the snapshot, a resolution entry: a new dot of this Mac, holding the folder value the sheet showed for the unit, and superseding exactly the snapshot's entries. Apply those values, record `applied`, persist, publish, relaunch. When a unit had several different remote values, the sheet showed each one, and "Use" takes the one it labelled "Sync folder": the first in dot order (§6.3). |
| **Keep This Mac's Settings** | For each unit in the snapshot, a resolution entry with this Mac's value, superseding exactly the snapshot's entries. Persist and publish. No relaunch. |
| **Later** | Nothing is written. The entries stay in the replica and in the file, so they survive relaunches, deletion of the file and later writes (INV-9). The hint stays. The sheet never opens by itself; the user opens it with **Choose Settings…** (A2 INV-P4). |
| **Cancel** (joining only) | The tentative join is discarded. Sync stays off, or the previous folder and group stay. Nothing is written (§5.7). |

```swift
mutating func resolve(_ u: UnitKey, to v: UnitValue, superseding shown: Set<Dot>, now: Date) {
    let d = Dot(mac: me, counter: nextCounter(now))
    replica.units[u] = (replica.units[u] ?? []).filter { !shown.contains($0.dot) } + [Entry(dot: d, value: v, written: now)]
    replica.context[me] = d.counter
    applied[u] = [d]                       // for Use: after the value is applied
}
```

- **An entry that arrived after the sheet opened** is not in the snapshot. It survives as a sibling or as a fast-forward and is decided anew (INV-8, S-33, S-46).
- **Answers on two Macs at once** produce two resolution entries.
  - Equal values collapse.
  - Different values make one more question. Once anyone answers it, the Macs converge (A3 §8.5).
- **The other Mac in the conflict** sees the resolution entry, which supersedes its own sibling.
  - If its applied value already equals the result, it records the dot silently.
  - Otherwise the unit is a fast-forward (**Restart**).

  The question disappears everywhere.

### 5.7 Joining: Turn On…, Change…, the first N run, a lost local state

A Mac is *joining* while its first decision about a folder is open, after any of:
- Turn On…;
- Change… to a folder of another group;
- the first N run with sync on (§8.2);
- a rebuilt local state (§5.5);
- the downgrade tripwire.

While it joins, it publishes nothing (`state.join` holds the tentative replica).

**Input.**
- The folder state F: the canonical file joined with its copies, or, at genesis, the β1 file as values without dots (§8.3), or nothing.
- The local values without dots: every unit of `Cmp(m)` whose value has no applied dot in the folder's group, with its origin.

| Local value (no dot) | Folder | Result | Question? |
|---|---|---|---|
| Absent: never set | Has a value | Adopt it: apply, and `applied` = the folder's dots | No |
| `.auto` (placements, seeding; known because N records origins from its first run) | Has an intent value | Adopt it (SA-05) | No |
| Equal to the folder's single value | — | Adopt (`applied` = its dots) | No |
| Equal to the legacy base for the unit (a Mac from the β1 era, §8.4) | A different single value | Adopt: the group moved on from the value this Mac still holds | No |
| Any | No entry for the unit | Publish it, with a new dot of this Mac | No |
| Set, or `.pre`, and different | A single value | A difference | **Yes** |
| Set, or `.pre` | Siblings: a question still open in the folder | Equal to one of them: adopt that one and become one of its stakeholders. Otherwise: a difference | Only if different |

- **Without differences**, the join commits: `applied`, origins and dots are recorded, and an exchange publishes whatever there is. A1 S-07 lists the joins that must not ask.
- **With differences**, the hint reads **Choose Settings…** and the sheet lists them:
  - **Use** adopts the folder's values, then relaunches;
  - **Keep** publishes this Mac's values, each with a dot that supersedes the folder's entries for that unit;
  - **Cancel** discards the tentative state.
- **An all-unset fresh install** adopts the whole folder state silently (M-6, A1 S-01).
- **The other namespace and the learned sets** are never compared. They come with the folder state.

### 5.8 Turn Off, re-enable, Change…, re-identification, own-ID anomalies

- **Group.** A random ID created at genesis and carried in the file and in the replica.
  - Same group: a merge, never a join question.
  - Another group's file: a join (§5.7).
- **Turn Off.**
  - All folder access stops.
  - The replica and `applied` stay (A2 OQ-14), and user changes keep creating dots locally, at no cost.
  - Turning sync on again with the same folder is an ordinary exchange. Changes made while sync was off are concurrent with the other Macs' changes and are asked about only where both sides changed the same unit.
- **Change… to an empty folder** (or the same folder without its file): the replica is written there unchanged, with the same group. The file was deleted, or the user moved the group to a new place; in both cases nothing can be reverted, because the content is the replica with every other Mac's entries and original dots (A1 §5.2 pair 2 needs no distinction). Other Macs of the group that choose the new folder later merge without questions.
- **Change… to a folder of another group:** a join. **Cancel** keeps the previous folder and its replica. After a confirmed join, the old group's replica is dropped. This Mac's *values* go along as values without dots, never the old group's entries of other Macs.
- **Re-identification (F-38: clone, Migration Assistant, restore to new hardware).**
  - A new Mac ID. The replica stays: dots are global facts, so a copied replica is a valid, older replica state.
  - The counter starts fresh under the new ID.
  - Local values that differ from their applied entries become `.pre`, which is rare right after a clone.
  - No join question unless there are such differences.
- **Own-ID anomaly.** If the folder shows `context[me]` above this Mac's counter, or an entry with this Mac's dot and a value this Mac never wrote, then either the local state was restored (Time Machine, same hardware) or another installation uses this ID (`CopyAccount`, or `.unknown` hardware).
  - Both are handled the same way: re-identify, and join the folder's entries. They include this Mac's own newer writes, which arrive as fast-forwards.
  - Re-identifying costs one more Mac in the table and closes dot reuse (A2 INV-ID3, INV-ID4).

---

## 6. Conflict detection and the question

### 6.1 What counts as a real conflict

A conflict is a unit in `Cmp(m)` whose surviving entries hold two or more different values. It arises only when two writes to the unit were concurrent: neither one's context covered the other's dot. In practice that means:
- two Macs changed the same setting (or moved the same item in the same macOS version), neither having applied the other's change. A2 W1, the Conflict definition at unit level.
- a Mac changed a unit while another Mac's change to it waited for a restart (S-04).
- two Macs answered the same question differently.

**Never a conflict:**
- equal values, from any number of Macs (A2 INV-P2);
- learned sets, flags, local keys;
- the other macOS version's layout (INV-L1);
- automatic placements, which have no dots (INV-A1);
- a stale, restored or duplicated file, whose entries are covered;
- several missed writes from one Mac, which supersede one another (S-68);
- a β1 write, which N never reads after genesis.

**Joining differences** (A2 W2/W5) and **protected values** (`.pre` and `.uncertain` facing a different single remote value) also lead to the sheet, on that Mac only.

### 6.2 What each Mac shows

| Situation on m | Hint | Sheet |
|---|---|---|
| Only fast-forwards | **Restart**, in Settings → Advanced and at the top of holzBar's menu (modal-alerts-1) | None |
| A conflict with a stake, a protected unit, or a join with differences | **Choose Settings…** | Opened only by the user, as a sheet on the Settings window |
| A conflict between other Macs only (bystander) | None. Optional status line "Waiting for a choice on another Mac" (new string) | None |
| A folder file too large, unreadable, from another group, or from a newer holzBar | A status line in Settings (§11) | "Replace…" only for refused files (M-7) |
| A β1 Mac still writing the old file after genesis | A passive status line (§9) | None |

### 6.3 The sheet

- **Existing strings:** the title "Which settings should holzBar use?", the informative text ("The sync folder holds settings from another Mac that differ from this Mac's. Using them restarts holzBar; keeping this Mac's settings replaces them in the sync folder."), the three buttons (Use, Keep, then Later or Cancel), and no default button (SA-07).
- **Recommended addition (new strings):** a short list of the units that differ, using the existing Settings labels. Each row shows "This Mac: … · Sync folder: …", plus the other Mac's wall-clock time for display (A2 R-UX-2).
  - A layout difference shows as "Menu bar layout: n items".
  - A unit with two different remote values, which needs three Macs changing one setting at once, shows each value with its time. "Use" takes the first one in dot order, which the list marks "Sync folder".
- **The other Mac is named only "another Mac".** A user-chosen label stored in the file is optional (A2 OQ-10).

### 6.4 Why publishing need not pause while something waits (M-3)

sync-1 ("pushes stay paused") and modal-alerts-1 point (4) prevented one failure: a push of this Mac's *whole state* over another Mac's newer file, after which **Restart** applied nothing (S-05).

In D2 that cannot happen:
- **The waiting entries are carried, not replaced.** A write is `join(replica, file)`, so B's waiting entries stay in the file and in A's replica unchanged.
- **Nothing in a write supersedes them.** The write's context covers B's dots only because the write *carries* those entries (A2 INV-S3 (a)). A later change of A's to the same unit supersedes only `applied[u]`, so B's entry becomes a sibling, not a loss (INV-S7 (b) in substance).
- **Restart still applies B's entries,** which remain fast-forwards until applied.

Pausing would only delay A's own unrelated changes. The rejected sync-1 option paused pushes "because the in-memory models would otherwise write old values back". That does not apply either: models write only in `didSet`, on a change (`GeneralSettings`), and a model rewriting an unchanged value makes no difference from `applied`, so no dot.

### 6.5 Strict mode: the literal sync-1 reading (M-1)

If the maintainer keeps "both Macs changed anything since the last sync → ask", the schema gets coarser and nothing else changes:
- all `S`, `H`, `I` and `P` keys form one unit `S/all`, whose value is a dictionary of those keys;
- each macOS version's layout forms one unit (`L26`, `L27`), whose value is the map of the user's intent (item → section, intent entries only).

Concurrent changes to *any* settings then become siblings of two whole dictionaries, and the question offers one or the other. Every safety property in this document holds unchanged.

What changes:
- the 4 scenarios marked M-1 in §14 ask instead of merging;
- more questions overall: any two Macs changing anything at the same time;
- each answer discards the other side's unrelated changes, by the user's choice;
- every write carries the whole settings dictionary.

---

## 7. macOS-specific layouts

### 7.1 Namespaces and authority

- **Two namespaces.** `L26/<identityKey>` holds `ItemSections`, keyed by `ItemIdentity`'s current key format. `L27/<bundleID>` holds `MacOS27Layout`.
- **Authority.** A Mac running macOS 26 or earlier creates dots only in `L26`; a Mac running 27 only in `L27` (A2 INV-L2).
- **The other namespace.**
  - It lives in the replica.
  - It is relayed with its original dots in every write, and never re-dotted.
  - It is never applied to `UserDefaults` and never compared (INV-5, INV-L1, INV-L3).
  - A stale entry of it is covered and dropped by every join (S-15, S-16, S-17).
- **The `UserDefaults` copy of the other key** (a macOS 26 Mac's old `MacOS27Layout` from the β1 era, or the reverse) is left untouched. It is neither published nor removed (F-60).
- **Explicit values, not absence.** Moving an app to Visible on macOS 27 is the explicit value 0. Locally it removes the entry, as `SectionLayoutEditing27.settingSection` does today. Absence never means "visible" in the file.

### 7.2 Capturing intent: which actions create dots

| Action | macOS | Creates dots for | Notes and code it touches |
|---|---|---|---|
| A move in the Layout pane, with its undo and the keyboard moves | 26 | The moved item's unit, with its destination section | `LayoutBarPaddingView.move(_:to:…)` knows the item and the `MoveDestination`. The dot is created at the move; a 1.5 s save delay no longer delays it. |
| A move in the Layout pane | 27 | `L27/<bundleID>` | `Concealer27.setSection(_:for:)` is already exactly one user move. It calls the capture instead of `userChangedLayout()`. |
| A Command-drag on the bar | 26 | The item under the pointer at mouse-down, if its section changed once the bar settled | `handleMenuBarItemDragStart` records the item: hit-tested against the item windows (`Bridging.getMenuBarWindowList`) at the mouse-down point, not against the cache, so an item that just appeared counts (S-58). After the drop, the save reads that item's section. A Command-click without a move changes nothing, so no dot (S-56). |
| The same Command-drag, attribution failed (no window under the point) | 26 | Nothing published | If exactly one item's section changed and no display or wake settle is running, that item is attributed: only the user can have moved it. Otherwise every changed item becomes `.uncertain`: protected and not published (§3.4). |
| Applying a profile, from the menu, a hotkey, Shortcuts or `holzbar://` | 26, 27 | Only the entries whose value changes (`applyingProfile` on 27; the `wanted` sections against the current values on 26) | Applying the current profile again changes nothing, so no dot (S-57). A profile without a macOS 27 layout changes nothing on 27 (F-03). |
| Applying a profile from a Space or display binding | 26, 27 | Nothing (`.auto`) | M-5 |
| Importing settings | 26, 27 | Every `S`, `H`, `I` and `P` unit it changes, including *removed* for keys the import deletes, plus this macOS version's layout entries it changes. Never the other namespace. | `SettingsBackup.importFromFile` calls the capture before `relaunch()` (A2 R-FUN-5; SA05 review #4 (a)) |
| A control in Settings | — | That unit | Captured from the debounced defaults observer: the projected value against the value of `applied` |
| Placing new items or apps; the first-run save; seeding on 27; reconciliation and restore; displacement by macOS; the notch overflow; Live Activities; migrations; the F-30 hotkey clean-up at load | — | Nothing (`.auto`) | Registered as automatic writers in a Core table, so the observer never takes them for the user (R-AUTO-1) |

**Pending captures.** On macOS 26, a Command-drag's destination is known only once the bar settles, about 1–1.5 s later. Until then, the item is in `pendingCaptures` (persisted).
- **Restart** and the sheet's answers first finish the pending captures, waiting at most 2 s, then recompute the hint. If the move now conflicts, **Restart** turns into **Choose Settings…** (S-64).
- `applicationWillTerminate` flushes them too (SA05 review #4).

### 7.3 Applying intent, and the rules automatic code must follow

The effective layout is the applied intent of each item where there is one. Elsewhere it is the local automatic value. Three rules make this hold. Each is a change outside the sync code, and option 1 needs the same changes.

1. **Automatic stores never overwrite an entry backed by applied intent.** This covers `saveSections(byUser: false)`, `storeSections(_:byUser: false)` and the reconciliation's stores (S-60). Automatic overrides of such an entry (Live Activities, the notch) stay transient or in a separate local map, never in `ItemSections` (A2 R-AUTO-3).
2. **A user's save stores only the attributed item.** `saveSections(byUser: true)` no longer snapshots every cached item. It stores the moved item, plus, as `.auto`, items that have no saved section yet. Displaced items keep their saved sections, so the restore puts them back (S-59).
3. **Seeding coexists with intent.** On macOS 27, `seedLayoutIfNeeded` seeds the apps that have no entry yet, instead of requiring an empty layout. Intent applied at launch then does not block seeding of the other apps (INV-L6).

**Remote intent** for an item whose local value is `.auto` is a fast-forward and replaces the placement without a question (SA-05). An `.uncertain` or `.pre` local value is protected (§5.3).

### 7.4 Upgrading from macOS 26 to 27

On the first launch on 27:
- The `L27` units already in the replica (relayed from macOS 27 Macs) are applied as fast-forwards over the local `MacOS27Layout`. Its entries are `.auto`: old copies from the β1 era, or nothing.
- Seeding then fills in the remaining apps, as automatic values.
- `ItemSections` keeps its `L26` role: relayed, never reverted.

There is no question unless the user moves apps before the first sync on 27; those moves are dotted and simply merge. This meets A2 R-FUN-7 and INV-L6.

---

## 8. Migration

### 8.1 Starting states

| Coming from | What exists |
|---|---|
| β1 (0.0.6 or 0.0.7-beta1) with sync on | `SyncsSettingsWithICloud`, the folder bookmark, `SettingsSyncDeviceID` (no hardware hash), `SettingsSyncLastSynced`. The folder has `holzBar/Settings.plist`. |
| β2 (paused) | The same, unchanged, plus anything the user changed during the pause, which nothing recorded (A2 C-8) |
| A development build (SA05, R1–R6) | `SettingsSyncBaseSettingsDigest`, `…BaseLayoutDigest`, `…LayoutEdits`, `…SyncedLayoutEdits`, `…PendingModified`, `…DeviceSalt`/`…DeviceHash`, and on the R branch more keys. The file may carry `currentLayouts`, `copiedLayouts`, `seen`. |
| A fresh install | Nothing |

### 8.2 The first N run (before anything reads the folder)

1. **F-38.** `verifyDeviceIdentity`. Without a stored hash (every β1 and β2 Mac), the ID rotates once. That is harmless: N dots are new anyway (R-COMPAT-5).
2. **Keep** the bookmark and `SyncsSettingsWithICloud`.
3. **Use nothing else as evidence** (R-COMPAT-5, INV-B6): `SettingsSyncLastSynced`, every development-build key, and the β1 file's dates. After the join commits, the development-build keys and `SettingsSyncLastSynced` are deleted. The latter then serves as the downgrade tripwire (§5.5).
4. **Create the local state.**
   - An empty replica; no group yet.
   - Every existing value of `Cmp(m)` gets origin `.pre`, including **every layout entry of this macOS version**. This covers the pause gap (S-62, A2 R-COMPAT-4) and a Mac that never reached its folder (S-08).
   - Learned sets are taken as they are. Flags stay local.
5. **Convert an oversized Ice icon** (§4.3).
6. **Join** (§5.7). The folder's state is:
   - `Sync2/Settings.plist` if it exists, which is the group created by an earlier N Mac;
   - otherwise the β1 file: genesis (§8.3);
   - otherwise nothing: genesis without input.

**Cancel** on a migration join turns sync off, with the status "Sync is off: this Mac's settings differ from the sync folder's". The old file cannot keep working for an N Mac (M-2).

### 8.3 Genesis from the β1 file, and the legacy base

The first N Mac in a folder finds no `Sync2/` file. It reads `holzBar/Settings.plist`, applying β1's reading rules for size, links and parsing, but no date rules:

- **Readable.** Its `settings`, without local keys, flags and Ice-era keys, become the folder values, without dots.
  - This Mac's own namespace is compared. The other namespace is *not* imported: N never authors other-namespace intent (INV-L2), and the Macs of that macOS version bring their own when they update.
  - The join table of §5.7 applies, with one change: "adopt" gives the adopted value a dot of this Mac, because the group needs a first author.
  - Before the first write, the Mac creates the group ID and records **`legacyBase`**: the canonical digest of each unit's value in the β1 file. It also records **`legacySeen`**, the digest of the file's (`modified`, `deviceID`), so that later β1 writes can be recognised (§9).
- **Dataless or downloading.** Wait. A background download is requested, and the join stays open until the file can be read.
- **Refused: too large, a link, or unparseable.** Genesis goes ahead without it. The β1 state is not lost: β1 Macs keep it and are asked when they update. Settings shows "The old sync file could not be read" (new string).
- **Absent.** Every local value is published.

If the β1 file was written by this Mac itself and holds nothing it has since changed, every value is equal and nothing is asked. If this Mac changed values during the pause, those differ and are asked about once. That is A1 S-62's rule, and no date or `lastSynced` is used to skip it (INV-B6).

### 8.4 Macs that update later: the three-way join against the legacy base

A Mac that updates after genesis joins the existing group. For each unit where its `.pre` value differs from the group's:
- **Equal to `legacyBase[u]`:** this Mac still holds the value the group started from, and has not changed it since. The group's newer value is adopted silently. A1 §5.2 pair 9 (A→B→A) is accepted here: equal values show no change.
- **Different from the base, or no base:** asked.

So a β1 Mac that changed nothing since genesis updates without a question. Values changed on it after genesis, including layouts rearranged during the pause, are asked about (S-21, S-62, SC-44). This is a three-way merge whose base is the group's starting point: a recorded fact, not a guess from dates.

### 8.5 Development-build state and files

- Development-build keys are ignored and deleted after the join (§8.2).
- A development-build `holzBar/Settings.plist`, with `currentLayouts`, `copiedLayouts` or `seen`, is treated exactly like a β1 file at genesis. Its extra fields are ignored.
- No development build ever wrote `Sync2/`.

### 8.6 Downgrade (N → β1 → N) and newer builds

- **During a downgrade, β1:**
  - never touches `Sync2/` or `SettingsSyncState`: `SettingsSync…` keys are excluded from its `currentSettings`, so its remove-missing apply skips them;
  - syncs with other β1 Macs through the old file;
  - writes `SettingsSyncLastSynced`.
- **Back on N,** the tripwire turns the run into a join. Values changed during the β1 period are `.pre` and asked about where they differ from the group. Nothing in `Sync2/` was overwritten (A2 INV-B7).
- **Newer builds** with the same major are passed through (§4.4). A new major uses a new folder.

---

## 9. β1 peers: the boundary

**Rules.**
1. N never writes `holzBar/Settings.plist`.
2. N reads it only at genesis (§8.3). After that, it reads only its date and `deviceID`, through `lstat` and a small bounded read, on each exchange.
3. If the file changes after genesis (its `(modified, deviceID)` digest differs from `legacySeen` and from the last look), Settings shows a passive status (new strings): "A Mac with holzBar 0.0.7 beta 1 or earlier still uses this sync folder. It no longer gets this Mac's changes. Update it to sync again." There is no hint, no question and no restart.
4. β1 Macs keep syncing among themselves through the old file, with their known bugs (F-02 and F-60 among β1 Macs).
5. A β1 Mac that updates joins the group (§8.4), so its values are never lost.

**Effect.**
- Nothing an N Mac does reaches a β1 Mac, so INV-B1 holds trivially.
- Nothing a β1 Mac does after genesis reaches an N Mac (INV-B3, INV-B4).
- The [CONFLICT] scenarios S-19, S-25 and S-26 pass because the two groups never share a file.
- The release notes and `docs/features.md` say: update every Mac; until then Macs on β1 and on this build do not sync with each other. β2 Macs are paused and touch nothing.

**Why not a one-way bridge (β1 changes imported into the N group).** It is possible: compare each β1 write per unit against the previous one, and import the units that changed as dot-less values, asking where an N user value differs. But it brings back A1 §5.2 pair 1 in a new form, because β1 also writes holzBar's *automatic* changes:
- `ItemSections` snapshots, including displaced items;
- `MacOS27Layout` placements;
- `KnownItemTags`;
- `HasImportedIceSettings := true` at every apply.

None of these can be told apart from a β1 user's move. The bridge would import automatic values as user changes, against INV-4, and ask about them, against INV-B4, for a release that is meant to be short-lived. Rejected; it can be added later behind the same per-unit diff if the maintainer wants it.

---

## 10. Can write-over still lose data?

### 10.1 What `NSFileCoordinator` gives, and what it does not

- **It gives, on this Mac:**
  - Mutual exclusion with other processes that coordinate, including iCloud's daemon (bird, fileproviderd): the daemon cannot swap a downloaded version in between this Mac's read and its rename.
  - A daemon that never uploads a half-written file.
  - Presenter notifications that leave out this Mac's own writes.
- **It does not give:**
  - Any exclusion between Macs.
  - Any compare-and-swap: a write is not rejected because the file changed on another Mac after this Mac's read.
  - Any ordering.
  - Coordination with Syncthing, the classic Dropbox and Nextcloud clients, or other Macs on SMB (A3 §6).

So the classic lost update stays possible by construction (A1 §5.4 C5): two Macs read version v0 and each writes `v0 ⊔ own`, and the provider keeps one.

### 10.2 The guarantee

Let a *user change* be an entry `e` with dot `d`, written by Mac m and persisted in m's replica before any write (§3.4).

- **G1. Nothing is superseded without being seen.** `e` disappears from a state only when that state is joined with a state whose context covers `d` and that lacks `e`.
  - Contexts grow only through fresh own dots and through joins.
  - The only operations that remove an entry they contain are a user's change to `e`'s unit, which removes only `applied[u]`, and an answer, which removes only the dots its sheet showed.
  - So every disappearance of a user value goes back to a user's change that saw it, or an answer that showed it (A2 INV-S1 (i)/(ii)).
- **G2. Stale input is inert.** Joining a state that some state already merged (an older file, a restored file, a duplicate, a late delivery) changes nothing (A2 INV-F3, INV-F5).
- **G3. Re-publication.** When the folder (the canonical file joined with its readable copies) lacks `e`, every running Mac whose replica holds `e` writes a state containing it at its next exchange. The only exception is a visible block: a refused file, a newer format, or the size budget. Exchanges run on events, on a poll, on wake and on launch (§5.4).
- **Consequence.** `e` is lost for good if and only if **every** replica holding it is destroyed or rolled back before another replica merges it. The folder is one of those replicas.
  - A collision alone does not lose it.
  - Neither does a deletion, a restore, a dataless period, a stall, any delivery order, or a β1 write.
  - Each of these only *delays* `e`: until m's next exchange while m runs, or until m comes back if it is off. While m is off, `e` waits in m's persisted replica.

### 10.3 Provider by provider (behaviour as researched in A3 §5)

| Provider | Two Macs write the canonical file at once | What D2 does | Can the change be lost? |
|---|---|---|---|
| iCloud Drive | One winner; the losers are unresolved `NSFileVersion` conflict versions, possibly visible on only some Macs | Writes only on a `.current` file, which avoids most collisions. Conflict versions are joined and marked resolved. Otherwise the loser heals. | Only if the loser's replica is destroyed before its next exchange **and** no Mac saw its version |
| Dropbox | The *newest* write becomes "… conflicted copy …" | Copy joined; deleted once dominated | No: the copy is on every Mac |
| OneDrive | Copy with the computer name appended | Same; the name is never logged | No |
| Nextcloud | Local conflict copy, not uploaded by default | Only the writer sees the copy, and its replica holds the change anyway, so it heals | Only as for iCloud |
| Syncthing | The version with the older mtime is renamed `.sync-conflict-…` and synced to all devices | Joined | No |
| Google Drive | `Settings (1).plist` | Joined | No |
| SMB, AFP, NFS, WebDAV | Last rename wins; no copy | The loser heals within one poll period (60 s on network volumes) | Only as for iCloud |

### 10.4 The remaining window: exactly when a change is lost

All of the following must happen:
1. Mac m writes a change.
2. That write loses a collision without a surviving copy (last writer wins, an iCloud loser invisible on every Mac, a Nextcloud local copy), **or** the file is deleted or restored before another Mac reads it.
3. Before m's next exchange (at most about 5 min while it runs; at its next launch otherwise), m's replica is destroyed: preferences deleted, the app's data removed, the Mac wiped or lost. A restore of the preferences from an older Time Machine backup also counts.
4. No other Mac read the folder between m's write and its loss. On SMB, any read in between saves the change, because that Mac then relays it.

That is the same exposure as making a change on a Mac that dies before it syncs, narrowed further by the conditions on the folder. It is never silent *corruption*: the surviving Macs stay consistent with one another.

**Option 1 (one file per Mac) removes condition 2's collision part.** There, another Mac never writes over m's file, so only a deletion or a restore of m's own file can meet condition 2.

### 10.5 Other ways a write could lose data, and what stops them

| Path | Guard | What remains |
|---|---|---|
| A reader drops an entry it cannot interpret (an unknown kind, a failed validation, over a cap) while advancing its context | The pass-through rule (§4.4). Validation happens only at apply. A property test: decode, encode and join keep every entry byte for byte. | None, if tested |
| Dot reuse: the same (Mac, counter) for two values, so receivers drop the second as covered | `max(last+1, unix ms, context[me]+1, cache high-water+1)`. Re-identification on any own-ID anomaly (§5.8). The local state lives in the same preferences file as the settings, so a restore rolls both back together. | A restore of the preferences, **and** the folder file lost, **and** the clock set back past the restored counter, **and** the cache floor purged. It is detected later as "same dot, different value" if any Mac still holds the old entry. |
| A forged or buggy foreign writer whose context covers dots it dropped | Bounded parsing, a format check, refusal of links (R-SEC-1) | Out of scope, as today: anyone who can write the folder can also replace `Settings.plist` (A3 §9) |
| A refused canonical file (corrupt, too large, a link) is written over | Never automatically (INV-Z6). "Replace…" in Settings asks first; the other Macs then heal their own entries. | Entries that only the refused file held, which happens only if their authors also lost their replicas, are lost by the user's choice |
| A newer major format is written over | Never (§4.4) | Older Macs pause publishing until they update; their changes wait in their replicas |
| The merged state exceeds `Lmax` | No write; a warning on every Mac; answers and smaller values bring it back under | Publication pauses, visibly; nothing is lost |
| A layout move recorded wrong (an input error, RC-6) | The capture rules (§7.2); `.uncertain` protects instead of publishing | A wrong attribution is a local error the user can see, never a silent overwrite on another Mac |
| A Time Machine restore of the preferences | Settings and state roll back together; newer values come back from the folder as fast-forwards | Rolling back on purpose has to use Export and Import (A3 §10 Q9); documented |

### 10.6 D2 against one file per Mac, on loss alone

| | D2: one shared file | Option 1: one file per Mac |
|---|---|---|
| Concurrent writes | A conflict copy or a dropped write, by design; recovered by joins and heals | Never in normal operation; a conflict copy of a Mac's own file means two Macs share an ID |
| Correctness depends on | The heal protocol running, and the writer's replica surviving until its next exchange | Joins only; a Mac's own file heals itself, but no other Mac can destroy it |
| Damage to one file | Blocks every Mac's publications until "Replace…" | Affects only that Mac's file |
| Clone (F-38) signal from conflict copies | Weak: copies are normal | Strong |
| Code beyond the shared parts | Conflict-copy discovery and joins, `NSFileVersion` handling, heal and relay with jitter, the "Replace…" flow, the iCloud `.current` gate: about 150–250 lines | Listing the folder, cleaning up retired Macs' files: about 100 lines |
| Folder footprint | One file (plus transient copies) | One file per Mac that ever joined |

---

## 11. Failure handling, by root-cause class

| Class (A1) | How D2 handles it | What remains |
|---|---|---|
| **RC-1** Whole-state writes into one shared file | Every write is `join(replica, file ⊔ copies)`. A writer that missed a change still carries it if the file holds it. If the file does not hold it (a stale read), its author heals (§10.2). Copies are joined. | The window of §10.4 |
| **RC-2** Wall-clock order and identity | No clock in any decision. Counters are per Mac, with a millisecond floor only for uniqueness. Dates are for display. | A triple fault for dot reuse (§10.5) |
| **RC-3** A file lifecycle holzBar does not control | Missing: no information; the group continues, heals. Restored or older: inert, heals. Dataless or downloading: skipped at launch, downloaded and retried in the background. Partial: unreadable for now, retried. Corrupt, too large or a link: refused, status, no automatic write, "Replace…". Newer format: refused, status. Waiting changes live in the persisted replica (INV-9). | Publication pauses while a refused file stays |
| **RC-4** Two per-OS layouts in one file; β1 removes missing keys | Namespaces, authority by macOS version, relay with the original dots (§7.1). β1 never reads N's file (§9). | — |
| **RC-5** Provenance from digests and missing records | Dots and `applied` record "seen" and "taken in" separately. Absence is "no information". A lost local state means joining (`.pre`), never evidence. Equality is used only to collapse siblings, adopt equal values, and against the legacy base, a recorded starting point. | — |
| **RC-6** Automatic and user changes mixed in one snapshot | Dots only from captured intent, per item, at the event. Automatic writers are registered. `.uncertain` instead of guessing. Automatic stores never overwrite intent; user saves store only the moved item (§7). | The macOS 26 Command-drag attribution must be verified on real Macs (S-58, S-59, S-67) |
| **RC-7** Peers on other versions | The β1 boundary. β2 counts as off. The first N run is a join with `.pre`. Development-build state is ignored. The downgrade tripwire. Newer formats are passed through or refused. | β1 and N do not sync with each other (documented) |
| **RC-8** Questions and answers cover the whole state | Siblings per unit. An answer supersedes exactly the shown dots. Bulk buttons reuse the strings. | Strict mode (§6.5) reintroduces whole-set answers by the maintainer's choice |
| **RC-9** Races and bookkeeping that is not atomic | Dots are created and persisted synchronously at the event. One atomic state value. Exchange results are joined into the current state, never replace it. The hint is a pure function. Pending captures are flushed before Restart and quit. | — |
| **RC-10** Identity, I/O, content | F-38 plus own-ID anomaly checks. F-15 and F-18 as in SA05. Per-entry validation at apply (F-59) and pass-through. Value caps, `Lmax`, refusal at the writer with a warning (F-61). | The F-59 fixes in the local readers (`ItemIconStore`, `Concealer27`, `HotkeysSettings`, `LayoutProfiles`, `SectionRestore`, `MenuBarItemGroups`) are still needed for local behaviour. Sync no longer spreads such a loss, because a move dots only the moved item. |
| **RC-11** Verification that could not see the defects | Pure Core planner. One I/O protocol shared by the app and the simulator. Invariant oracles over generated histories. Mutation and fuzzing (§13). | The real-Mac matrix stays |

**A1 §8, hazards not exercised so far:**
- **Conflict copies:** joined (§4.5).
- **A local state rolled back on the same hardware:** the state rolls back together with the settings, the counter floors hold, an own-ID anomaly re-identifies, and the folder's newer values come back as fast-forwards.
- **Preferences deleted, or the app reinstalled:** a new ID and a join with `.pre`. The old ID's entries stay in the group as another Mac's.
- **The folder moved by the sync app:** the bookmark finds it again. Everything waiting is in the local state (INV-9).

**A2 §6 fault operations:**

| Operation | Effect in D2 |
|---|---|
| `Deliver`, with reordering, coalescing or duplicates | Joins are order-free and idempotent |
| `ConflictCopy` | Joined |
| `LWW` | Heal |
| `Restore` | Inert, then heal |
| `Delete`, `DeleteFolder` | Heal; never a local deletion (INV-F6) |
| `Evict` | Skipped, then downloaded in the background |
| `ExposePartial` | Unreadable for now, retried |
| `Stall` | Bounded at launch; the coordinator is cancelled after 10 s |
| `Unmount` | Idle; nothing is written under `/Volumes`; a status |
| `Foreign` bytes or links | Refused, with a status |

---

## 12. Privacy

- **The shared file holds only:**
  - settings values;
  - random Mac IDs and the random group ID;
  - counters, whose millisecond floor reveals write times, as the display dates already do;
  - display dates;
  - SHA-256 digests of settings values (`legacyBase`, `legacySeen`);
  - format numbers;
  - optionally, a label the user chose for a Mac (A2 OQ-10).
- **It never holds:**
  - the hardware UUID, its salted hash or the salt;
  - the computer name or the user name;
  - paths or bookmark data.

  A2 INV-PR2's marker scan runs on every write in the simulator.
- **Conflict-copy names** can contain user or computer names (Dropbox, OneDrive). They are never written into holzBar's files and are logged only as `.private`. A copy deleted after its merge leaves no trace in holzBar's state.
- **No network:** sync uses only the folder the user's own sync app provides (C-1). The CI privacy check stays.
- **Logs** mark values, IDs, paths and names as private, as today.
- **`docs/privacy-and-permissions.md` lists:**
  - what the file holds;
  - that the β1 file is read once at genesis and its date afterwards;
  - that the salted hash stays local.

---

## 13. Test strategy

1. **Pure Core only** (A2 R-TEST-1). The model, join, intent writes, classification, the exchange's merge step, launch, answers, joins, migration, the legacy reader, the format, validation and the size budget live in `holzBar/Core/Sync2/`. They are Foundation-only and compiled by `swift test`.

   The app glue does only this:
   - file I/O through a `SyncFolderIO` protocol: list, a coordinated read, a coordinated read and write, delete, the download state;
   - presenters, watchers, timers;
   - the hint and the sheet.

   The simulator implements the same `SyncFolderIO` in memory. So the scenario tests run the app's exchange sequence, not a copy of the glue (RC-11, the risk noted after round 6).
2. **Algebraic property tests** on random replicas:
   - join is commutative, associative and idempotent, and `join(x, past(x)) == x`;
   - contexts only grow;
   - encode and decode followed by join keep every entry, including unknown kinds;
   - `capmerge` is a lattice;
   - `nextCounter` is strictly increasing under any clock steps, restores and folder states the generator produces.
3. **A model-based simulator** following A2 §2 and §8:
   - **N Macs** run the Core code above.
   - **β1 Macs** run A2 §2.6 literally: they push at every launch and 5 s after any change, never read before writing, apply silently with remove-missing, and set `HasImportedIceSettings`.
   - **β2 Macs** are inert.
   - **The provider** has one shared path with collisions inside a window `w`, ending in `ConflictCopy` (with probability p_c) or `LWW`, plus restore, delete, evict, partial, stall, unmount, foreign bytes, links, and the provider presets.
   - **Clocks** have offsets and steps.
   - **Identity events:** clone, restored preferences, a copied account, re-identification.
   - **User events** include the macOS 26 capture inputs: mouse-down item, drop, displacement inside the settle window, a failed hit-test. Answers are chosen adversarially.
4. **Oracles.** A2's safety invariants are checked after every step. Liveness invariants are checked after a drain (INV-C1 to INV-C6). Metamorphic pairs: INV-A1 (with and without automatic events), INV-F9 (randomised clocks), INV-F2 (delivery permutations).

   One oracle is specific to D2, the **loss accounting**. Every globally lost live change (A2 INV-S1g) must match the §10.4 conditions in the trace: a collision without a copy, a delete or a restore, then the author's replica destroyed before its next exchange, and no read in between. Any other loss is a failure.
5. **Exhaustive small scope:** 2–3 Macs, both macOS versions, one β1 Mac, up to 8 events, every interleaving and answer. **Random long runs:** thousands of steps per preset (iCloud, Syncthing, SMB, Hostile). A minimal failing trace is printed as a scenario in A1's notation.
6. **Named regression tests:**
   - **S-01 to S-70**, each with the outcome of §14. The strict-mode variants of the 4 M-1 scenarios run as well.
   - **D2-specific additions:**
     - X-1: SMB last writer wins, then heal within one poll.
     - X-2: a Dropbox copy joined and deleted.
     - X-3: iCloud conflict versions joined.
     - X-4: a collision, then the loser's preferences deleted. The only loss allowed, and expected.
     - X-5: four Macs healing at once converge with a bounded number of writes.
     - X-6: a file from another group in the folder means a join.
     - X-7: the downgrade tripwire.
     - X-8: the same dot with different values means re-identification and a question.
     - X-9: the counter floor after a restore of the preferences plus a deleted file.
     - X-10: sibling icons near `Lmax`.
     - X-11: a refused file plus "Replace…".
     - X-12: a newer major format.
7. **A mutation gate** (R-TEST-5). Every guard in join, classify, merge, intent, resolve and the join table is mutated. A surviving mutant is a missing scenario or a dead guard.
8. **Fuzzing** (R-TEST-4) of the format reader and of the β1 reader: arbitrary bytes, truncations, type swaps, oversize collections.
9. **A layout-capture suite** (Core, pure). The attribution function takes the item at mouse-down, the sections before and after, and whether a settle is running, and returns dots, automatic values or `.uncertain`. Plus the rules of §7.3 as tests of the store guards.
10. **Real Macs**, the matrix of A1 §7.2 point 5:
    - S-01, S-09, S-14, S-20 (with a real β1 Mac), S-34, S-45, S-59, S-62 and S-68;
    - on iCloud Drive, on Dropbox or OneDrive, and on an SMB share;
    - plus two D2 checks:
      - two Macs offline, both edit, both back online, on each provider: watch the copy or the dropped write, and the heal;
      - `NSFileVersion` access without the iCloud entitlement.

---

## 14. Regression walk: every scenario of A1

**Verdicts.**
- **Pass:** the catalogue's Must holds as written.
- **Pass+:** the Must's safety holds with fewer questions, because nothing is lost.
- **Pass (β1 boundary):** the Must holds because N never shares a file with β1. Limitation: the β1 Mac does not receive N's changes.
- **Pass (M-1):** with per-unit conflicts, different units merge where the Must's wording asks. Strict mode (§6.5) asks as written.
- **Pass (mechanism):** the Must's safety goal holds, by a different mechanism than the Must's wording.

### G1 · Joining, identity, routine writes

- **S-01 · A second Mac joins with its defaults.** **Pass.**
  - Turn On… makes B join (§5.7). B reads the group's file before writing anything.
  - All-unset values adopt silently (M-6). Equal values adopt. Different set values ask Use, Keep or Cancel.
  - A changes only through B's **Keep**: resolution entries that supersede the shown entries.
  - If A is still on β1 and only the old file exists, B does genesis from it. A never sees N's file, so A changes not even after Keep (β1 boundary).
- **S-02 · A relaunch with nothing changed.** **Pass.**
  - The launch only reads (§5.5).
  - The exchange after setup finds `join(replica, file) == file`, so there is no write and no hint anywhere (INV-C4).
- **S-03 · A Mac behind writes over a newer version.** **Pass.**
  - B's merge-then-write with a stale copy of the file collides with A's write.
  - A copy is joined, or A sees `file.context[A]` below its counter and heals.
  - A's change survives. Two different settings merge; the same setting changed on both Macs becomes siblings and a question on both.
  - B never writes over a version it has on disk without reading it: the read and the write are one coordinated access, and a dataless or downloading file means "retry".
- **S-04 · Later, then any push.** **Pass (M-1).**
  - B's change is an entry. A's later writes, automatic learned-set writes included, carry it unchanged, so it keeps waiting (INV-9).
  - A user change on A to the *same* unit becomes a sibling and a question on both Macs. A change to another unit merges; the hint stays Restart.
  - In strict mode, any change on A asks, as the Must's wording says.
- **S-05 · The notice is open while pushes run.** **Pass (mechanism).**
  - A keeps publishing (M-3), but every write carries B's entries, so the file never becomes "A's own" in a way that hides B.
  - **Restart** applies B's entries, plus any later fast-forwards, never a unit in conflict.
  - The Must's "no push while a version waits" is replaced by "no write can supersede a waiting entry" (§6.4).
- **S-06 · Set up by Migration Assistant, a restore or a clone.** **Pass (mechanism).**
  - The hash mismatch gives B a new ID; the hash never leaves the Mac.
  - B keeps the copied replica, a valid older state, instead of clearing it. So it merges like a re-enabled Mac.
  - No question with equal settings (S-07); newer folder values arrive as fast-forwards.
  - Clearing the state, as the Must says, would turn A's later changes into join differences and could ask needlessly.
- **S-07 · Joining without a conflict.** **Pass.**
  - No file: publish.
  - Own group's file (sync off and on, or a re-identified Mac): merge.
  - Equal settings: adopt.
  - No question in any case, and no write when nothing is new, so no hint on any Mac.
- **S-08 · Sync was on but never reached the folder.** **Pass.**
  - The first N run gives every existing layout entry `.pre`, whatever β1's sync state said (no `initialLayoutEdits`).
  - Once the folder is reachable, the join asks where A's layout differs, and adopts where it is equal.

### G2 · Infrastructure

- **S-09 · An online-only file at login.** **Pass.**
  - The launch reads only a local, non-dataless file, within about 1 s, off the main thread.
  - Otherwise the replica serves and the background exchange downloads the file and checks later.
  - No coordinated I/O on the main thread; the coordinator is cancelled after its bound.
- **S-10 · The network share is not mounted.** **Pass.**
  - Bookmarks are resolved with `.withoutMounting`. The folder is unavailable, so sync is idle and shows "The sync folder cannot be found".
  - Volume notifications and the poll resume sync. Nothing is created under `/Volumes`.
- **S-11 · A settings file over the size limit.** **Pass.**
  - Icons over 256 KB are not published, with a warning. Ice icons are converted once.
  - A merged state over `Lmax` is not written; there is a warning and the previous file stays.
  - A file over `Lmax` from anyone is refused and never written over automatically ("Replace…").
  - A β1 file over 1 MiB is never written by N; at genesis it is skipped with a status.
- **S-12 · A malformed entry in a synced setting.** **Pass.**
  - Each layout item and each hotkey is its own unit, so one bad value affects one unit.
  - It is validated at apply, skipped there, and kept byte for byte in the replica (pass-through).
  - A later move dots only the moved item, so sync never spreads an emptied dictionary even before the local F-59 reader fixes land. Those fixes are still needed so that the receiving Mac does not empty its own dictionary.

### G3 · Two macOS versions

- **S-13 · Applying a file of the other macOS version.** **Pass.**
  - Applying is per unit and never removes anything; a missing unit is no information.
  - A macOS 27 Mac applies only `L27`; `MacOS27Layout`, `MacOS27LayoutSeeded` and `KnownApplications27` are untouched by a macOS 26 Mac's writes. The reverse holds for `ItemSections`.
- **S-14 · macOS 26 and 27 with equal settings.** **Pass.**
  - B (27) does genesis in the empty folder with `S`, `H`, `I`, `P` and its `L27` dots. It never writes `L26`.
  - A (26) joins: the settings are equal (adopt). The folder has no `L26`, so A publishes its own.
  - A's Command-drag dots `L26` only. B relays it and never applies it. No layout question at any point.
- **S-15 · A stale other-OS layout from a restored own version.** **Pass.**
  - The restored V1 carries C's (C, c1) entries, which A's context covers: they are dropped at the join.
  - A's write carries (C, c2), so the heal restores the newer state.
  - C keeps L_C2 and receives A's setting as a fast-forward. Nothing is "taken in" or "listed".
- **S-16 · A stale other-OS layout from a third Mac's older version.** **Pass.** The same: a stale entry's dot is covered whoever delivers it.
- **S-17 · Three Macs: the other-OS copy promoted to current.** **Pass.**
  - A relays C's (C, c2) through the restore.
  - D, turned on again, merges by dots: (C, c2) supersedes D's older applied value and is a fast-forward for D. D's setting change carries (C, c2).
  - D has no dots for those apps, so nothing of D's "is listed".
  - C keeps its arrangement. A move of the same app on D at the same time becomes siblings and a question.
- **S-18 · A β1 Mac of the other OS writes an old copy back.** **Pass (β1 boundary).**
  - C (β1) never receives A's L1, so there is no old copy to write back.
  - C's writes go only to the old file, which A no longer reads.
  - No question and no revert. A's layout is the current intent in N's file; C keeps `ItemSections`.
- **S-19 · The file is lost while a β1 Mac of the other OS syncs [C1].** **Pass (β1 boundary).**
  - N writes only `Sync2/`. If the old file is lost, β1 C finds nothing newer at launch, applies nothing and pushes its own state again.
  - C's arrangement survives. A2 §5.4 C1 does not arise, because no N write ever reaches β1.

### G4 · Same macOS version with a β1 Mac

- **S-20 · A β1 drag overwritten by an N Mac's non-layout write.** **Pass (β1 boundary).**
  - B's drag goes to the old file; A's change goes to `Sync2/`. B keeps L_B; A leaves it alone.
  - When B updates, its dragged items differ from the legacy base and from A's values, so B's join asks. That is where "a drag that would replace L_B asks first" is met.
- **S-21 · A β1 Mac updated to N adopts the other Mac's layout.** **Pass.**
  - B's layout entries are `.pre`. Items B dragged after genesis differ from the base, so they are asked about. Items equal to the base adopt A's.
  - B's arrangement survives until the user chooses.
- **S-22 · An N Mac with its own arrangement joins a folder written by β1.** **Pass.** Genesis compares C's `.pre` layout with B's old file. They differ, so C asks.
- **S-23 · A kept arrangement written back by β1.** **Pass (M-1).**
  - Among A and B: B's drag and setting change, A's opposite setting change. Only `ShowOnHover` has siblings.
  - A's **Keep** supersedes the two `ShowOnHover` entries. B's layout dots stay a fast-forward on A; no "kept but not taken in" state exists.
  - C (β1) writes only the old file, which N ignores.
  - B keeps its arrangement after a relaunch. A move on A of an item B moved asks. A move of another item merges; strict mode asks.
- **S-24 · β1 keeps writing an old copy while N rearranges.** **Pass (β1 boundary).** No question; A's moves are the intent in N's file; C's `ItemSections` is untouched, because N never writes the old file.
- **S-25 · A β1 user goes back to an earlier arrangement [C2].** **Pass (β1 boundary).**
  - C's return is never reverted, because N never writes the old file.
  - When C updates, its arrangement differs from the base, so it is asked about: the case becomes decidable at the join.
  - The setup's "C applied L2 from A" cannot happen in D2.
- **S-26 · A β1 write over a deleted or damaged file [C2].** **Pass (β1 boundary).**
  - The old and new files are separate. Deleting either does not affect the other.
  - B's change in `Sync2/` is healed by B if needed. C's file has no effect on N.
- **S-27 · β1 rewrites at launch and after automatic changes.** **Pass (β1 boundary).**
  - N reads only the old file's date after genesis. There is no hint, question or restart for any β1 write, equal or not; only the passive status of §9.
  - C's rewrites never displace A's or B's changes.

### G5 · Clocks and dates

- **S-28 · A change dated before the last sync.** **Pass (M-1).**
  - B's change has a dot A's context does not cover, so it is new whatever its date. It is a fast-forward, or a question if A changed the same unit.
  - A change by A to *another* unit merges; strict mode asks, as the Must's "if A also changed something" says.
  - It is never ignored and never written over.
- **S-29 · An older version's layout recorded as synced, then overwritten by a drag.** **Pass.**
  - A's setting write relays B's L2 dots, but A's `applied` for those items stays old: seen is not taken in. L2 is a fast-forward for A.
  - A's drag of a moved item before the restart makes siblings and a question. A drag of another item does not touch L2.
- **S-30 · A version dated far in the future.** **Pass.**
  - Dates are for display only. B's large clock gives B large counters, compared only with B's own.
  - Nothing about other Macs' ordering changes; when B's clock is fixed, its counters continue from last + 1.
- **S-31 · A re-joining Mac adopts an older version.** **Pass.**
  - Sync off and on keeps the replica, so the exchange is a merge. B's drag (B's dot) is a fast-forward for A, taken in at the restart.
  - A drag of the same item before then makes siblings and a question. Never a silent overwrite.
- **S-32 · A clock set back, or two writes in the same second.** **Pass+.**
  - W2's counter is `max(last + 1, …)`, above W1's whatever the clock does.
  - After the deletion, B's file lacks (A, W2): A's entry is not covered, so A keeps it and heals, and B gets W2 as a fast-forward.
  - Nothing is reverted, so no question is needed. The Must asked only because the old model could not merge.
- **S-33 · Keep over a version dated at or before the answered one.** **Pass.**
  - A's **Keep** supersedes exactly the snapshot's dots.
  - B's later change, whatever its date, is either another unit (a fast-forward) or a new entry of the same unit not in the snapshot (siblings again, asked again).

### G6 · The file goes missing, is restored or becomes unusable

- **S-34 · A write over a missing file reverts another Mac's change.** **Pass.**
  - A's write over the missing file is A's replica. B's (B, 9) is not covered there, so B keeps its value and heals; A gets it as a fast-forward.
  - The Must's "or the change is merged" holds, and there is no silent apply.
- **S-35 · A waiting version dropped when the file goes away.** **Pass (mechanism).**
  - V2's entries live in A's persisted replica. The hint stays.
  - A's next write (a heal, or a change of its own) re-publishes V2 unchanged, and cannot revert B.
  - The Must's "nothing is written until the user answers" is replaced by "every write carries V2".
- **S-36 · A relaunch while the file is missing.** **Pass.** The entries and the classification are recomputed from the persisted state after the relaunch, so the hint is back (INV-9).
- **S-37 · Keep without a layout edit, then the file goes away.** **Pass.**
  - The Keep covers only `ShowOnHover`. B's layout dots stay in A's replica.
  - A's write over the deleted file carries them. A has no layout dots for those items, so its placements never travel.
  - B keeps its arrangement. A takes L_B in at the restart; a drag of the same item before then asks.
- **S-38 · A copy over a missing file, then a second write promotes holzBar's layout.** **Pass.**
  - There are no copies or "current" lists. Both of A's writes carry B's dots, and A's automatic values have none.
  - B keeps its arrangement and takes A's setting. B's next drag dots its items again.
- **S-39 · Several writes, or a third Mac, on top of a version without B's change.** **Pass+.**
  - However many writes follow, none covers (B, b), so every join keeps it and B heals.
  - Nothing is applied over B's value, so no question is needed.
- **S-40 · A third Mac applies a version without a write it holds.** **Pass+.**
  - C holds (A, a), applied. B's file does not cover it, so C keeps A's arrangement and relays it (a heal).
  - B's setting is a fast-forward for C (**Restart**). The arrangement survives relaunches.
  - The Must's "Choose Settings…" is unnecessary, because nothing conflicts.
- **S-41 · The `seen` record claims a write whose layout was never taken in.** **Pass.**
  - Seen (the context, with the entries carried) and taken in (`applied`) are separate facts.
  - A's write over the missing file carries B's layout entries. B keeps its arrangement.
- **S-42 · A sync app restores an older version of this Mac's own.** **Pass.**
  - At the relaunch, the restored file's entries are covered by A's replica: nothing is applied.
  - A heals, so its next state in the folder carries the drag.
- **S-43 · Variants of an unusable file.** **Pass.**
  - An empty file, a damaged plist, a plist of another format, a link or folder in place of the file or of `holzBar/`/`Sync2/`, a file over `Lmax`: each is refused and never treated as "missing" or "no other Mac wrote here".
  - There is no automatic write; Settings shows the state, with "Replace…" for refused files.
  - Waiting entries persist. A deliberate new setup in another folder stays possible (S-44).
- **S-44 · Setting up a new folder.** **Pass.**
  - Change… to an empty folder writes A's replica, the complete state, with A's intent as the layout entries. No question.
  - A fresh B joins as in S-01 and S-07. A B from the same group merges without a question.

### G7 · What an answer means

- **S-45 · Keep writes an untouched layout over a newer arrangement.** **Pass.**
  - Only `ShowOnHover` is in conflict, and the Keep covers only those two entries.
  - The folder keeps L2 (B's dots) together with A's setting. A takes L2 in at the restart or launch. A drag of an L2 item before then makes siblings and a question.
- **S-46 · A version arrives while the question is open.** **Pass.**
  - B's new change is not in the snapshot, so it survives the Keep: as a fast-forward, or as new siblings. The hint returns to **Choose Settings…** if a conflict remains.
- **S-47 · Keep, then sync turned off and on before the restart.** **Pass.**
  - The replica is kept and re-enabling is a merge. L2 is still a fast-forward for A (**Restart**); a drag of an L2 item before then asks.
  - B keeps L2.
- **S-48 · Keep, a drag, then joining again.** **Pass (M-1).**
  - A drag of an L2 item on A makes siblings with B's unapplied entry, a question that sync off and on, Change… to the same folder, or a drag while off all keep.
  - Nothing supersedes B's entry without an answer. A drag of another item merges; strict mode asks.
- **S-49 · After Keep, pushes stop, or an ordinary change asks about this Mac's own write.** **Pass.**
  - Nothing pauses: A's toggle is dotted and published, and B gets it as a fast-forward. A's hint stays **Restart** (for L2).
  - At the relaunch A applies L2 and keeps the toggle.
- **S-50 · Keep for a re-joining Mac brings the question back.** **Pass.** One Keep writes resolution entries that cover the shown siblings, so the question is gone on every Mac.
- **S-51 · Keep over a restored older version lists its stale layout again.** **Pass+.**
  - The restored file's entries are covered by every replica that saw D's drag, so they create no question at all. There is nothing to Keep.
  - A, B and D keep D's arrangement; the heal puts it back in the folder. With sync turned off and on first, the result is the same.
- **S-52 · Keep after a lost write.** **Pass+.**
  - B's file lacks (A, a), so A keeps it and heals.
  - B's `ShowOnHover` is a fast-forward for A, and A's arrangement one for B. No unit conflicts, so there is no question.
  - Both changes survive. The Must's question existed only because one of them had to lose.
- **S-53 · Keep answered while the file is missing.** **Pass.**
  - A's Keep writes the resolution entry into the missing file as A's replica, which also carries B's layout dots.
  - B sees its sibling superseded: **Restart**, not a question. After the restart B has A's setting and its own arrangement.
- **S-54 · The kept-layout record is lost after a successful write.** **Pass.**
  - There are no kept records. The dot is persisted before the write; a quit after that is healed.
  - A lost state means joining with `.pre`. A development-build state is ignored at migration. Nothing is ever written on the strength of a missing record.

### G8 · Automatic versus user changes

- **S-55 · holzBar places new items or apps.** **Pass (mechanism).**
  - Placements have no dots: no write (a learned-set change is published at most hourly), no hint on B, and A's **Restart** stays **Restart**.
  - A placement never replaces B's arrangement.
  - The Must's "A's next layout change takes the placement along" is replaced by: placements never travel. Each Mac places by the synced `NewItemsPlacement` setting, and agreement (INV-C1) covers user intent.
- **S-56 · A Command-click without a move.** **Pass.** The attributed item's section is unchanged, so no dot and no hint change. The "unsaved item" variant is the same.
- **S-57 · Applying the current profile again.** **Pass.** Only changed entries get dots, and here there are none.
- **S-58 · The first move of an item holzBar never saved.** **Pass.**
  - The item under the pointer is hit-tested against the item windows, so an item that just appeared, was skipped or was shown only for a moment counts: a dot.
  - A newer remote entry for it that A had not applied becomes a sibling and a question; never a silent revert.
  - Depends on the §7.2 capture changes.
- **S-59 · macOS displaces items, then the user Command-clicks or drags.** **Pass.**
  - Only the attributed item gets a dot. The user's save stores only that item, so displaced items keep their saved sections and the restore puts them back (§7.3 rules 1 and 2).
  - With a failed hit-test, several changed items become `.uncertain`: protected, not published.
  - Depends on the `SectionRestore` changes.
- **S-60 · A reconciliation stores an old section over the user's fresh save.** **Pass.**
  - The user's move is dotted at the event.
  - Automatic stores never overwrite an intent-backed entry (§7.3 rule 1), and the launch writes intent back if they did.
- **S-61 · A move in the Layout pane during a restore.** **Pass.** The Layout-pane move is dotted at once. The restore uses the applied intent for that item and never reverts it.
- **S-62 · A layout rearranged during the β2 pause, then sync resumes.** **Pass.**
  - The first N run gives every entry `.pre`. The join asks where the folder differs: against the old file at genesis, or against the group, with the legacy base, later. Never a silent take-in.
- **S-63 · Only learned keys differ.** **Pass.** Union, silently: no question, no hint, no restart. The flags are local.

### G9 · Timing races

- **S-64 · Restart within 1.5 s of a drag.** **Pass.**
  - The dragged item is a pending capture. **Restart** finishes it first (at most 2 s), then recomputes the hint.
  - A conflicting move turns **Restart** into **Choose Settings…**, and **Keep** keeps the drag. A quit flushes too.
- **S-65 · An edit lands during an exchange.** **Pass.**
  - The edit's dot is in the current local state. The exchange's result is *joined* into that state, never replaces it.
  - The next exchange publishes the edit; it is never recorded as synced without being written.
- **S-66 · A hint built from a stale side.** **Pass.** The hint is a pure function of the current state, recomputed after every change of it.
- **S-67 · Displacement and arrangement within the 2 s settle window.** **Pass.**
  - Nothing depends on a snapshot from before the arrangement. The item under the pointer is attributed; displaced items are never dotted.
  - Inside a settle, a failed hit-test gives `.uncertain`, not a guess.
  - The remaining risk is the attribution itself, which needs the real-Mac check.

### G10 · Convergence and how often holzBar asks

- **S-68 · A closed laptop catches up.** **Pass.**
  - B's later entry supersedes its earlier one, and both are new to A: one fast-forward per unit. It is silent at launch if the file is local, otherwise **Restart**.
  - No question, whatever number of writes A missed.
- **S-69 · An arrangement held only as a copy stalls.** **Pass.**
  - There are no copies. Every arrangement is dotted intent in its own namespace.
  - Every Mac of that macOS version applies it as a fast-forward, or asks if it holds a concurrent different entry.
  - The Macs converge without another rearrangement (INV-15).
- **S-70 · Extra questions after bookkeeping gaps.** **Pass.**
  - There is no `lastWritten` and no `seen`, and no cap on Macs in the context (the table keeps them all).
  - Counters never go back, and adoption and missed writes are dot facts.
  - A question appears only for siblings with different values (INV-7).

**Tally.**

| Verdict | Count | Scenarios |
|---|---|---|
| Pass | 50 | |
| Pass+ | 5 | S-32, S-39, S-40, S-51, S-52 |
| Pass (β1 boundary) | 7 | S-18, S-19, S-20, S-24, S-25, S-26, S-27 |
| Pass (M-1) | 4 | S-04, S-23, S-28, S-48 |
| Pass (mechanism) | 4 | S-05, S-06, S-35, S-55 |

S-58, S-59 and S-67 depend on the layout-capture changes of §7. S-12's local behaviour also needs the F-59 reader fixes.

---

## 15. Decisions for the maintainer

| # | Question | Proposed in D2 | Alternative |
|---|---|---|---|
| M-1 | Ask when two Macs changed *different* settings, or merge them? | Merge per unit; ask when the same unit changed on two Macs (§6.1) | Strict mode, sync-1's literal wording (§6.5): more questions, each answer discards the other side's unrelated changes |
| M-2 | Write the old file for β1 Macs? | Never. Separate groups until every Mac is updated; a passive status line (§9) | None that is safe (§1.2) |
| M-3 | Pause this Mac's publications while a change or question waits? | No: writes are joins (§6.4) | Pause as in sync-1; costs only delay |
| M-4 | Sync the one-time flags with OR? | No, keep them local; learned sets still union | OR, with A2 INV-K3's risk of skipping needed work |
| M-5 | Sync `CurrentLayoutProfile` and the tuning keys, and count bound-profile applications as the user's? | No, no, and no | As today |
| M-6 | A fresh install with nothing set: adopt the folder silently? | Yes (A1 S-01) | Ask (A2 OQ-4) |
| M-7 | A file that stays unreadable or too large | Never overwritten automatically; "Replace…" in Settings | Wait forever (sync stalls) |
| M-8 | Delete provider conflict copies once merged? | Yes, only copies fully read and dominated by the state just written (A2 OQ-11) | Leave them; each costs a read per exchange |
| M-9 | F-61 size policy | 256 KB per icon value, Ice icons converted once, `Lmax` 2 MiB, writer refusal with a warning | Content-addressed blobs |
| M-10 | Rollbacks by the provider or Time Machine | The folder wins; deliberate rollback goes through Export and Import (documented) | — |
| M-11 | Option 2 or option 1? | §16 | — |

**New strings, in en, de with Swiss spelling, fr, it and rm, checked by `strings-check.py`:**
- the β1 status;
- "The sync file cannot be read" and "Replace…";
- the too-large warnings, for the icon and for the file;
- the newer-format status;
- "The old sync file could not be read";
- optional: the bystander line and the difference list in the sheet.

---

## 16. Implementation outline, cost, and how D2 compares

**Order.**
1. The maintainer's decisions M-1 to M-11.
2. Core model, join and property tests.
3. Schema, projections, validation (F-59 at apply), the class test.
4. Format, the β1 reader, the size budget, fuzzing.
5. Planner functions (launch, exchange merge, intent, classify, answer, join, migrate), the simulator, the oracles, the mutation gate.
6. Layout capture (§7.2, §7.3):
   - `HIDEventManager`: the hit-test at mouse-down, pending captures;
   - `SectionRestore`: the store guards, user saves of the moved item only;
   - `Concealer27`: `setSection` and seeding;
   - `LayoutProfiles`: dots for changed entries only, bound applications automatic;
   - `SettingsBackup` import;
   - registration of the F-30 hotkey clean-up and of migrations as automatic writers.
7. Glue:
   - the file actor (coordination, copies, `NSFileVersion`, the iCloud `.current` gate, heal timers);
   - presenter, watcher, poll;
   - hint, sheet, status lines, "Replace…", strings.
8. Removal of the paused policy code and its keys. `SettingsSyncPause.isPaused = false` and its test.
9. The real-Mac matrix (§13 point 10).
10. Docs and release notes: the β1 boundary, the first-sync question after the pause, rollback through Export and Import.

**Size.**
- Core: about 1,000–1,400 lines (model and join about 250, schema about 200, planner about 450, format and β1 reader about 250, layout attribution about 150).
- Glue: about 600–800 lines.
- Tests: about 1,800–2,800 lines.
- That is about the size of A3's estimate for option 1, plus the 150–250 lines of §10.6.

**How D2 compares.**
- **D2 meets the policy.** Every catalogue scenario passes, and every user change survives every provider fault while its author's replica lives (§10.2).
- **What it gives up** against one file per Mac:
  - the *structural* exclusion of lost updates: collisions become delays that the heal must repair, plus the narrow loss window of §10.4;
  - per-Mac isolation of a damaged file.
- **What it keeps:** one inspectable file in the folder, and no per-Mac files to clean up.
- **Recommendation.** If the maintainer has no strong reason to keep a single file, option 1 delivers the same behaviour with one fewer failure mode and slightly less code. Everything in §3 to §9 and §11 to §14 carries over to option 1 almost unchanged: units, dots, intent capture, joins, the β1 boundary, migration and the question. Only §4.5, §5.4's heal and §10 differ.
