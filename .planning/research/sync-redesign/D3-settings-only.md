# D3 · Settings-only sync: one file per Mac, causal merge per setting, a question for real conflicts

Design option 3 for the settings-sync redesign (sync paused in 0.0.7-beta2): sync the user's settings and leave the menu bar arrangement on each Mac. Read-only design, 2026-10-07. Nothing in the repository or its git state was changed.

**Inputs:** A1 (`A1-failure-taxonomy.md`: root causes RC-1 to RC-11, invariants INV-1 to INV-16, §5.2 pairs, §5.4 conflicts C1 to C5, scenarios S-01 to S-70); A2 (`A2-requirements-invariants.md`: R-…, INV-S/A/L/K/P/C/ID/Z/F/B…, SC-…, OQ-1 to OQ-14); A3 (`A3-research.md`: design C); decisions `sync-1` and `modal-alerts-1`; the paused code on `audit/remediation-2026-10-05` (`SettingsSync.swift`, `Core/SettingsSync*.swift`, `SettingsBackup.swift`, `SectionRestore.swift`, `Concealer27.swift`, `LayoutProfiles.swift`, plus `Defaults.swift`, `ItemIdentity.swift`, `HotkeysSettings.swift`, `HotkeyTarget.swift`, `ItemIconStore.swift`, `MenuBarItemGroups.swift`); the six rounds on `audit-manual/sync-fix`; audit findings F-02, F-15, F-38, F-59, F-60, F-61; `docs/features.md`; the sync code of `v0.0.7-beta1` (identical in behaviour to 0.0.6, 0.0.6-beta2 and 0.0.6-beta1).

**Terms.** As in A1: β1 (0.0.6 and 0.0.7-beta1, writes `holzBar/Settings.plist`), β2 (0.0.7-beta2, sync paused, inert), N (this design). New here:

| Term | Meaning |
|---|---|
| **Unit** | The smallest thing that syncs and that can conflict: one setting, one hotkey, one item's icon (§1.1). |
| **Entry** | One value of a unit, stamped with the dot of the change that made it (§5.3). A deletion is an entry too. |
| **Dot** | `(MacID, n)`: which Mac made a change, and its counter there. Compared only with dots of the same Mac. |
| **Context** | A version vector `MacID → n`: every dot a replica has seen. |
| **Replica** | Context plus the live entries of every unit. Each Mac keeps one and publishes it as its file. |
| **Σ** | This Mac's local sync state, one atomic file (§5.4). Never exported, imported or synced. |
| **Group** | The Macs that publish into one `holzBar/Macs/` folder. |
| **Applied** | The entries whose value this Mac's defaults hold: what the user here has seen. |

---

## 0. In brief

1. **What syncs:** the user's settings: General, Advanced, Hotkeys, appearance, the holzBar icon, item groups, item icons, "Show When It Changes" marks and the reveal rules. **What stays on each Mac:** the arrangement (`ItemSections`, `MacOS27Layout`), layout profiles and the current profile, everything holzBar learns or flags by itself (`KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners`, `MacOS27LayoutSeeded`, `hasMigrated…`, `HasImportedIceSettings`), device tuning and every `SettingsSync…` key.
2. **Mechanism:** one file per Mac, `holzBar/Macs/<MacID>.plist`, written only by that Mac. It holds that Mac's merged replica: per unit the live entries, each with a dot; per file one context. Merging is a lattice join, so order, duplicates, late and restored files cannot move anything backwards.
3. **"Last change wins" is causal, not by clock.** A change made on a Mac whose defaults already held the previous value replaces it everywhere, without a question. Two changes of the same unit made without knowing each other are a real conflict: if their values differ, holzBar asks. No clock decides anything; dates are shown, never compared across Macs.
4. **The question** is `sync-1`'s sheet (Use Settings from Sync Folder, Keep This Mac's Settings, Later, or Cancel when joining), shown from the quiet hint of `modal-alerts-1`. It now lists the settings that conflict, and an answer covers exactly the entries it showed.
5. **β1 boundary:** N never writes or deletes `holzBar/Settings.plist`. It reads it once, as join input, and only while the new folder holds no device file. β1 Macs and N Macs form two groups until every Mac is updated.
6. **Failure classes that disappear:** RC-1, RC-2, RC-4, RC-5, RC-8 and RC-9 by construction. RC-6 disappears with the arrangement, except one automatic writer of a synced key that must be fixed. RC-7 disappears behind the boundary. RC-3 shrinks to delivery latency. RC-10 and RC-11 stay engineering work. All nine §5.2 pairs and all five §5.4 conflicts vanish.
7. **What the user loses:** the arrangement and the profiles no longer follow between Macs by themselves. Instead: "Share Profile" through the sync folder (an explicit, immutable snapshot that the other Mac adds and applies), single-profile export and import, and the existing Export… and Import…. During the update period, β1 and N Macs do not sync with each other.
8. **Regression walk (§14):** 33 of A1's 70 scenarios pass as written. 27 are about the arrangement: their safety clauses hold by construction, and their clauses that need an arrangement to reach another Mac are waived by design. 10 are about β1 peers and are resolved by the boundary. No scenario fails a safety clause (no silent loss, revert or stale return). §15 adds 20 scenarios that this design introduces.
9. **Size:** about 800 lines of Foundation-only Core plus tests, about 600 lines of app glue, about 300 for profile sharing. It replaces `SettingsSyncPolicy.swift` (717 lines on SA05, 2,358 on R6) and most of `SettingsSync.swift` (1,909).
10. **Decisions needed (§16), 11 in all.** The two that shape the design: merge different settings changed on two Macs without asking (Q1), and share profiles on demand instead of syncing them (Q2).

---

## 1. Scope

### 1.1 The unit table

The table lives in Core (`SettingsSyncUnits`), versioned (`unitTable: 1`, §6.4). A Core test fails when a `Defaults.Key` case has no row (A2 R-CLASS-1). Stored key names are shown.

**Synced: user settings.**

| Stored key(s) | Unit | Notes |
|---|---|---|
| `ShowIceIcon`, `UseIceBar`, `IceBarLocation`, `IceBarDisplays`, `ShowsNotchOverflowInIceBar`, `ShowOnClick`, `ShowOnHover`, `ShowOnScroll`, `ShowOnHoverDelay`, `AutoRehide`, `RehideStrategy`, `RehideInterval`, `TempShowInterval`, `ItemSpacingOffset`, `HolzBarIconShowsCaptureDot` | one unit per key | General |
| `EnableAlwaysHiddenSection`, `ShowAllSectionsOnUserDrag`, `SectionDividerStyle`, `HideApplicationMenus`, `KeepsDockIconHidden`, `EnableSecondaryContextMenu`, `NewItemsPlacement`, `KeepLiveActivitiesVisible`, `AutoZenWhileSharingScreen`, `OpenHiddenItemsInMenuBar`, `SpacerCount`, `SpacerWidth` | one unit per key | Advanced |
| `IceIcon` + `CustomIceIconIsTemplate` | one unit, `HolzBarIcon` | An image and its template flag change together; one without the other is a state nobody made. At most 256 KiB, else it stays on this Mac with a note (F-61, §6.5). |
| `MenuBarAppearanceConfigurationV2` | whole | JSON, at most 64 KiB. Colours, gradients and shapes only, no images. |
| `ItemGroups` | whole | JSON, at most 64 KiB. A group's `imageFile` stays on this Mac; other Macs show the group's symbol (as today). |
| `Hotkeys` | one unit per entry: each action (`ToggleHiddenSection`, …) and each `OpenItem:<item>` | `ApplyProfile:<name>` entries stay local with the profiles (§1.3). Clearing an action hotkey stores an encoded "none"; clearing an item hotkey removes the entry, which syncs as a deletion. |
| `ItemIcons` | one unit per item | The PNG files stay in Application Support/holzBar/ItemIcons; other Macs fall back to the next choice (`ItemIconChoice`), as today. |
| `RevealRules` | one unit per entry (`revealsOnLowBattery`, `lowBatteryThreshold`, `revealsWhenOffline`) | |
| `RevealOnChangeItems` | one unit per item (marked or not) | Stored as an array; applied as set membership. |

**Local: never captured, published, read from a file or applied by sync.**

| Stored key(s) | Class | Why local |
|---|---|---|
| `ItemSections`, `MacOS27Layout` | arrangement | The premise of D3. |
| `KnownItemTags`, `KnownApplications27` | learned | They decide which items are new on this Mac (§1.2). |
| `TitleChangingItemOwners` | learned | It re-keys this Mac's items (§1.2). |
| `MacOS27LayoutSeeded`, `hasMigrated0_8_0` … `hasMigrated0_11_13_1`, `HasImportedIceSettings` | flags | One-time steps of this Mac (A2 INV-K3, OQ-5). |
| `LayoutProfiles`, `CurrentLayoutProfile` | profiles, context | Shared on demand (§1.3, §4). |
| `MacOS27ClickRestoreDelay`, `MacOS27IceBarWaitsForRefresh` | device tuning | A2 OQ-7. |
| `SyncsSettingsWithICloud`, `DebugDropsBarrierExitEvent`, `DebugHangsItemImageCapture`, every `SettingsSync…` key | local | As today. |
| `MenuBarHasBorder` … `MenuBarAppearanceConfiguration`, `ShowSectionDividers`, `CanToggleAlwaysHiddenSection`, `Sections` | Ice-era input | Read only by the Ice import; never authored by N. |
| Any key that is not a `Defaults.Key` | — | Never. |

**Why units of this size.** A unit is one thing the user edits as one thing. Dictionaries the user edits entry by entry (hotkeys, item icons, reveal rules, marks) are split, so that two Macs that changed two different hotkeys never get a question. `ItemGroups` and the appearance stay whole, because concurrent edits of them are rare and splitting them would need rules for ordering groups. A3 §9 notes that the unit table is a product decision, made once.

**Settings that act on the arrangement.** `NewItemsPlacement` and `EnableAlwaysHiddenSection` still sync. Each Mac applies them to its own arrangement, and neither changes what that arrangement records: an always-hidden item shows in Hidden while the section is off, and its saved section stays.

### 1.2 Why the learned keys and flags now stay local

`sync-1` merged them (union and OR), because the arrangement travelled with them. Without the arrangement, merging them harms the receiving Mac:

- **`KnownItemTags`.** `SectionRestore` treats an item as new only when it is missing from both the saved sections and the known tags (`isNew = storedKnown != nil && saved[key] == nil && !known.contains(key)`). A merged list would mark another Mac's items as known on a Mac that never placed them, so `NewItemsPlacement` would no longer apply to them there.
- **`KnownApplications27`.** `Concealer27.placeNewApplications` places only bundle IDs that are missing from the known list. The reasoning is the same.
- **`TitleChangingItemOwners`.** `ItemIdentity.storedKey` maps every stored key of a learned owner to `owner:#1`. Learning an owner from another Mac re-keys this Mac's items of that app, and two saved sections of that app can collapse into one, which moves an item on this Mac. Sync would then change an arrangement after all. The cost of keeping it local: item-keyed settings of apps whose titles change may not match on a Mac that has not learned that app yet (§3.1).
- **Flags** record one-time steps of this Mac. OR-merging them can skip a step this Mac still needs (A2 INV-K3). β1 even set `HasImportedIceSettings` on every apply.

### 1.3 Profiles: three options

A `LayoutProfile` holds an arrangement and device context:
- `itemSections` (macOS 26) and `applicationSections` with `knownApplications` (macOS 27). `saveCurrentLayout` fills both parts from this Mac's defaults, so a profile saved on a macOS 26 Mac carries that Mac's copy of `MacOS27Layout`, which D3 no longer refreshes.
- `displayUUID` and `spaceUUID` bindings: identifiers of this Mac's displays and Spaces. A display UUID is derived from the display's EDID, which includes its serial number (A2 C-2).
- Profile hotkeys, stored as `Hotkeys/ApplyProfile:<name>`.
- `CurrentLayoutProfile`, which Space and display bindings set.

| Option | What it means | Cost and risk |
|---|---|---|
| **P1 (recommended): local, shared on demand** | Profiles stay on each Mac. "Share Profile" publishes an immutable snapshot; another Mac adds it explicitly (§4.3). | No conflicts are possible. New UI and strings. |
| P2: synced per profile | One unit per profile. | Needs a stable profile ID, because today the name is the identity and a rename is a delete plus a create. Needs one sub-unit per macOS generation, or saving on 26 overwrites the 27 part, which is RC-4 inside the profile. Bindings and the current profile stay local; profile hotkeys must be keyed by ID. Possible later through unit table 2, without a file-format change. |
| P3: local, file export and import only | §4.2 only. | The least code, and the least convenient. |

---

## 2. Which failure classes disappear

### 2.1 Root-cause classes (A1 §4)

| Class | In D3 | How |
|---|---|---|
| RC-1 Whole-state writes into one shared file | **Gone** | Each Mac writes only its own file. No write can replace another Mac's data, so no compare-and-swap is needed. In normal use providers make no conflict copies, because each file has one writer. |
| RC-2 Ordering by wall clock | **Gone** | Dots and contexts. Counters are compared only within one Mac. Dates are for display, plus the value a sheet proposes, which the user sees (§8.4). |
| RC-3 A file lifecycle holzBar does not control | **Shrinks to latency** | A restored or older file is dominated and changes nothing. A deleted file is re-published by its owner, and its content is already relayed in the other Macs' replicas. A damaged, partial or oversize file is refused and retried, never read as "missing". A dataless file is skipped and fetched later. What remains: changes arrive when the provider delivers them. |
| RC-4 Two per-OS layouts in one file; a legacy peer that deletes missing keys | **Gone** | Layouts are local. N never writes the legacy file. Absence never means deletion: deletions are explicit entries. |
| RC-5 Provenance from digests and missing records | **Gone** | Every entry carries its dot. "Seen" is the context, "taken in" is the applied set, and both are explicit. A missing record is never evidence: a lost Σ makes the Mac join. Digest equality only ever suppresses a question (INV-P2), never permits an overwrite. |
| RC-6 Automatic and user changes in one snapshot | **Gone with the arrangement**, plus one fix | Placements, learned lists and flags are local, so they are never captured. One automatic writer of a synced key exists: `HotkeysSettings.loadInitialState` drops a hotkey whose combination an earlier one uses, and writes the dictionary back. It must stop writing back (§17.3). The clash rule (§7.3) keeps sync from creating such duplicates. |
| RC-7 Peers on other versions | **Gone behind the boundary** | β1 and 0.0.6 never see `Macs/`. N never writes `Settings.plist` and reads it only as join input. β2 is inert. A downgrade N → β1 → N is detected and makes the Mac join (§7.10). What remains: mixed fleets are two groups (§3.1). |
| RC-8 Questions cover the whole state | **Gone** | Siblings exist per unit. An answer writes one entry per shown unit, covering exactly the dots it showed. |
| RC-9 Async and UI races; bookkeeping that is not atomic | **Gone** | Σ is one atomic file, guarded by a generation number in the defaults (§5.4). Σ is persisted before any device file is written. Capture runs before every apply. One serial file actor writes. The device file is only a snapshot of Σ. |
| RC-10 Identity, I/O, content | **Engineering, kept** | F-38, with the hash bound to the user account, plus a nonce and collision checks (§5.1). F-15 and F-18 code kept. F-59: validation per entry, pass-through, no write-back. F-61: caps per unit and a writer-side check. |
| RC-11 Verification | **Engineering, kept** | A pure Core engine, a simulator with an exact β1 peer, invariant oracles, mutation testing, and two-Mac checks on real Macs (§13). |

### 2.2 The nine pairs of histories that look the same (A1 §5.2)

| Pair | Why it no longer needs deciding |
|---|---|
| 1 β1 old copy vs. β1 user's return | β1 writes are never N input after the join, and layouts are not synced. |
| 2 Deleted file after an unseen write vs. new folder | There is no shared file. Publishing a replica can never revert anyone, so an empty `Macs/` folder needs no interpretation. |
| 3 Lagging clock vs. restored version | A new change has a dot the context does not cover. A restored file has only covered dots. |
| 4 β1 may have arranged vs. no current layout | Layouts are not synced. |
| 5 Lost kept-layout record vs. real old copy | There are no kept records. Σ is atomic, and a lost Σ means joining. |
| 6 User moved vs. macOS displaced | Layouts are not synced. |
| 7 Unsaved item moved by the user vs. placed by holzBar | Layouts are not synced. |
| 8 Applied vs. adopted but not taken in | The applied set per unit is the "taken in" fact. |
| 9 Nothing changed vs. A→B→A or a clock set back | Every change gets a new dot. Equal values never conflict, and counters never repeat. |

### 2.3 The five constraint conflicts with β1 (A1 §5.4)

C1 to C4 exist only while N writes, or keeps reading, the file β1 applies. D3 does neither, so they vanish. C5 (one file without compare-and-swap) vanishes with single-writer files.

### 2.4 Invariants that become vacuous or narrower

- A1 INV-5 (per-OS authority) and A2 INV-L1 to INV-L6, INV-A3 and R-COMPAT-4 (pause gap) are **vacuous**: sync never touches a layout. INV-L6 ("sync never leaves `MacOS27Layout` empty") holds trivially.
- A2 INV-K1 to INV-K3 and R-FUN-8 are vacuous: learned keys and flags are not synced.
- A1 INV-15 and A2 INV-C1 (convergence) are **narrowed** to the synced units. "Same per-OS layouts" is dropped by design.
- A1 INV-14 and A2 INV-B1 to INV-B4 hold trivially: N never writes what β1 reads.

---

## 3. What the user loses, and what changes

### 3.1 Losses

1. **The arrangement no longer follows between Macs.** Rearranging on one Mac moves nothing on the others. A new Mac does not get the arrangement by turning sync on. Replacement: share a profile (§4.3), or Export… and Import….
2. **Profiles no longer sync by themselves** (P1), and neither do their hotkeys or the current profile. Replacement: Share Profile, or profile export and import (§4.2).
3. **Mixed fleets do not sync.** While some Macs still run 0.0.6 or 0.0.7-beta1, those Macs keep syncing among themselves through `Settings.plist`, with β1's known bugs. N Macs sync among themselves through `Macs/`. A Mac joins the N group when it updates. A note in Settings says that a Mac with an older holzBar still uses the folder (§8.2).
4. **Item-keyed settings may not match on another Mac.** This covers item icons, "Show When It Changes" marks, item hotkeys and group members. They match by item identity key, and that key can differ between Macs for apps whose titles change (TitleChangingItemOwners stays local) and possibly between macOS 26 and 27. Nothing is lost: the setting stays in the group and applies wherever the key matches.
5. **A custom holzBar icon over 256 KiB stays on its Mac** (Ice imports kept up to 8 MiB raw). Settings says so; choosing the icon again stores a small PNG, which syncs.
6. **Hidden device-tuning defaults no longer sync** (`MacOS27ClickRestoreDelay`, `MacOS27IceBarWaitsForRefresh`).
7. **Unchanged from today:** the pictures of item icons and groups stay local, and an item hotkey registers on every Mac, even where the item does not exist.

### 3.2 Behaviour that changes without a loss

- **Different settings changed on two Macs merge without a question** (Q1). Today's design asks, and either answer discards one Mac's unrelated change.
- **The question names the settings** and shows both values.
- **Changes keep syncing while a question waits** (Q4). Only the conflicting setting waits; the other Macs' version of it is never overwritten.
- **A re-enabled or cloned Mac asks only about real conflicts.** Its replica records what it has seen (§7.9).
- **Settings → Advanced describes sync anew** (new strings, §8.2). Today it says "Keeps layout, profiles, hotkeys and appearance the same".

### 3.3 Gains

- No arrangement can ever be lost, reverted or brought back stale by sync. That was every blocker in R1 to R6.
- macOS 26 and 27 Macs sync settings with no special case.
- Fewer questions: no false question from automatic changes, learned keys, the other OS, clocks or legacy rewrites.
- **Privacy:** the folder no longer lists every menu bar app the user has (`KnownItemTags`, `KnownApplications27` and both layouts were synced), nor display and Space identifiers (profile bindings).

---

## 4. Exchanging arrangements and profiles by hand

### 4.1 Whole settings: Export… and Import… (existing)

- The exported file still holds every importable key, the arrangement included (`SettingsBackup.currentSettings`).
- Import is a user action and keeps remove-missing semantics (F-60 fix).
- On a Mac that syncs, capture (§7.1) then sees the change of every synced unit. Each one publishes: a changed value as a new entry, a removed key as a deletion entry (A2 R-FUN-5, INV-S5). The arrangement in the file is applied on this Mac only.
- The import sheet should say so (new text): "Imported settings replace these settings on all your Macs that sync; the menu bar arrangement changes only on this Mac."

### 4.2 One profile as a file (new)

- **Export Profile…** writes `<name>.holzBarProfile`, a property list with `kind: "holzBarProfile"`, `format: 1`, the name, the part of the running macOS generation (§4.4) and optionally the profile's hotkey. Bindings and the current profile are never included.
- **Import Profile…** validates the file per entry (F-59) and adds the profile under its name. If a profile with that name exists, holzBar asks: Replace, Keep Both (which adds "Name 2") or Cancel.
- This works without sync (AirDrop, Mail, USB).

### 4.3 A profile shared on demand through the sync folder (new, needs sync on)

- **Share.** In the profile's menu (Settings → Menu Bar Layout → Profiles), **Share with Your Other Macs** writes `holzBar/Profiles/<ShareID>.plist`. `ShareID` is a random UUID stored in the local profile, so re-sharing keeps the ID. Only the sharing Mac writes this file. Saving the profile again under its name rewrites the file with `revision + 1`, the same counter rule as dots. **Stop Sharing** deletes it; only the sharing Mac deletes it, and the user can delete it in Finder.
- **Receive.** Other Macs list `Profiles/` on their usual checks, read each file (bounded, at most 256 KiB, validated) and show **From Your Other Macs**: name, "made on macOS 26" or "made on macOS 27", and the share date. **Add** copies the profile into the local profiles, recording `sharedFrom: ShareID` and the revision; a name clash asks as in §4.2. A higher revision shows **Update**. A removed share stays added; a note says it is no longer shared.
- **Applying** an added profile is an ordinary local user action, and it rearranges only this Mac.
- **No conflicts are possible.** Snapshots are immutable. Each file has one writer, and receivers copy and never merge. A share therefore needs no dots, no context and no question.
- **Privacy:** sharing is explicit and per profile. Only the name, the arrangement part and optionally a hotkey travel.

### 4.4 Which part of a profile travels

A snapshot carries only the part of the macOS generation of the sharing Mac: `itemSections` from a macOS 26 Mac, `applicationSections` and `knownApplications` from a macOS 27 Mac. On a Mac of the other generation, the profile can be added but changes nothing when applied. holzBar says "Made on macOS 27; it applies only there". This is the existing rule: a profile without a layout for this macOS version changes nothing (F-03).

### 4.5 Companion change to saving profiles

`saveCurrentLayout` should record only the running generation's part, and keep the other part of an existing profile of the same name. Today it copies this Mac's other-generation copy, which D3 no longer refreshes, into every profile it saves.

---

## 5. Data model

### 5.1 Identity

- **MacID:** a random UUID, the existing `SettingsSyncDeviceID`. It appears in the file name and in entries.
- **Installation nonce:** a random UUID kept in Σ and written into the device file. A new one is made whenever Σ is created fresh or the Mac re-identifies.
- **Binding (F-38, extended):** `SettingsSyncDeviceHash` = SHA-256(salt ‖ hardware UUID ‖ the user account's uid), with a random salt, stored locally only. Migration Assistant, a clone or a restore to other hardware changes the hardware UUID; a copied account on the same Mac (A2 `CopyAccount`) changes the uid. Existing hashes, which lack the uid, do not match once. That is the one-time rotation `sync-1` allows, and the first N run is a join anyway.
- **Re-identification** happens on a hash mismatch, when this Mac's own file carries another nonce, when a provider conflict copy of this Mac's file appears (§6.6), or on a dot collision (the same dot with two values, §7.2).
  - The Mac gets a new MacID and nonce.
  - It **keeps** Σ's replica, applied set and baseline: a copied replica is a valid state, because every dot in it is real (A3 §8.7).
  - Nothing is asked unless local values differ without dots.
  - This departs from `sync-1`'s "clear the sync state and join": with dots the join adds nothing, and outcome S-06 and S-07 hold (§14).

### 5.2 Dots and counters

- A dot is `(MacID, n)`, where n = max(Σ.counter + 1, Unix seconds now, highest n of this MacID seen in any file + 1). This is Syncthing's floor, plus the folder.
- Dots are compared only with dots of the same MacID, so clock skew between Macs does not matter.
- A clock set back can never repeat a dot, because Σ.counter grows by one at least.
- Σ.counter is persisted before any file contains the dot.

### 5.3 Entries, registers, replica

- **Entry** = (dot, value or `deleted`, `at`). `at` is the minting Mac's date, for display only.
- **Register** of unit u = the set of live entries. Usually one. Two or more are siblings.
- **Replica** = (context, registers), with the invariant that the context covers every entry's dot.
- **A deletion is an entry**, never an absence (INV-6, A2 INV-S4 and INV-S5).
- **Values are kept as received**, byte for byte, whether or not this build can apply them (A3 §4.5 pitfall). An entry is never dropped while the context advances, except when an entry that covers it supersedes it.

### 5.4 Σ: this Mac's sync state

`~/Library/Application Support/holzBar/Sync/State.plist`, a binary plist, replaced atomically (temporary file and rename). It holds:

| Field | Meaning |
|---|---|
| `format`, `mac`, `nonce`, `counter` | §5.1, §5.2 |
| `generation` | Increases with every persist. The same number is written to the defaults key `SettingsSyncGeneration` **before** Σ is persisted. |
| `replica` | §5.3 |
| `applied` | unit → the dots whose value the defaults hold |
| `baseline` | unit → canonical digest of the local value as last captured or applied, or `unset` |
| `join` | The pending join preview, or none (§7.8) |
| `folder` | Digest of the bookmark of the folder last committed (informational; another group is recognised by its MacIDs, §7.8) |
| `legacy` | `SettingsSyncLastSynced` as N last saw it, and the digest of the legacy file at the join |
| `published` | Digest of the replica last written, and of this Mac's file as last read back |
| `status` | Refused files, oversize units, newer formats, legacy writer seen |

**Rules:**
- Σ changes only on the main actor, and is persisted before any device file is written.
- Every persist first writes the new generation to the defaults and synchronizes them. A power loss that still leaves the defaults older on disk only makes the Mac join, which asks instead of losing anything.
- **Generation check at launch.** If `SettingsSyncGeneration` < Σ.generation, the preferences were rolled back (a Time Machine restore of Preferences only, A2 `RestorePrefs`). The Mac then joins (§7.8), so restored old values are asked about, never published as new changes. If it is greater than Σ.generation, Σ is behind (a crash, or Σ restored alone): §7.6 step 4 recovers.
- **A lost or unreadable Σ means joining.** It is never evidence of anything.
- The `SettingsSync` prefix keeps the defaults key out of export, import and sync.

### 5.5 Canonical values and validation

- **Equality** uses the canonical digest of today's `SettingsSyncPolicy.digest`: sorted keys, 1 equal to 1.0, JSON compared by content. Absent and `deleted` are equal.
- **Validation at apply** (F-59), per unit and per entry:
  - `SettingsSchema` kinds and number rules;
  - JSON units decode with the model's decoder;
  - the icon decodes under `CustomIconData`'s rules;
  - an unknown enum raw value or icon name, as a newer build may write, is not applicable.
- **A value that is not applicable** stays in the replica and is relayed. It is never applied, and never replaced by a "repaired" one.

---

## 6. Files, format and versioning

### 6.1 Folder layout

```
<chosen folder>/holzBar/Settings.plist             β1 and 0.0.6 file. N never writes or deletes it; it reads it only as join input (§7.8)
<chosen folder>/holzBar/Macs/<MacID>.plist         one per Mac, written only by that Mac
<chosen folder>/holzBar/Profiles/<ShareID>.plist   profiles shared on demand, written only by the sharing Mac
```

- β1's presenter on `holzBar/` may hear about writes in the subfolders. It then reads `Settings.plist` and finds nothing it would not have found anyway: only another β1 Mac's newer write makes it offer a restart, which that write's own event would have done. Harmless.
- `holzIce/` (0.0.5) is never read (A2 R-COMPAT-6).

### 6.2 Device file (binary plist)

```text
{
  format:       1                                  // Int; a reader skips files with a higher major
  unitTable:    1                                  // Int; the writer's unit table (§6.4)
  mac:          "<MacID>"                          // must equal the file name
  installation: "<nonce>"                          // §5.1
  written:      <Date>                             // display only
  context:      { "<MacID>": <UInt64>, … }         // every dot this replica has seen
  units: {                                         // whole units → live entries
    "ShowOnHover": [ { mac: "<MacID>", n: <UInt64>, at: <Date>, value: true } ],
    "HolzBarIcon": [ { mac: …, n: …, at: …, value: { IceIcon: <Data>, CustomIceIconIsTemplate: false } } ],
    …
  }
  entries: {                                       // split units → item → live entries
    "Hotkeys":             { "ToggleHiddenSection": [ { …, value: <Data> } ],
                             "OpenItem:com.example.app:Status": [ { …, deleted: true } ] },
    "ItemIcons":           { "com.example.app:Status": [ { …, value: "app" } ] },
    "RevealRules":         { "revealsWhenOffline": [ { …, value: true } ] },
    "RevealOnChangeItems": { "com.example.app:Status": [ { …, value: true } ] }
  }
}
```

- An identity key can contain `/` or `:` (for example "Network # B/s"), so split units nest one level and never join names into one string.
- An unknown name under `units` or `entries` is passed through: kept, relayed, never applied.

### 6.3 Shared-profile file

```text
{ kind: "holzBarProfile", format: 1, mac: "<MacID>", share: "<ShareID>", revision: <UInt64>,
  sharedAt: <Date>, name: "<name>", generation: 26 | 27,
  itemSections: {…}?                                     // only from macOS 26
  applicationSections: {…}?, knownApplications: […]?    // only from macOS 27
  hotkey: <Data>? }
```

The same format serves the file export of §4.2, without `mac` and `share`.

### 6.4 Versioning and forward compatibility

- **`format` (major).** A file with a higher major is skipped and never joined. Settings shows "A Mac uses a newer holzBar. Update holzBar to sync with it." Each file has one writer, so N never rewrites, prunes or strips another Mac's file: A2 INV-B8 holds by construction. An incompatible future format uses a new folder (`Macs2/`) and reads `Macs/` as join input, as N does with the β1 file.
- **Unknown top-level keys** are ignored. They cannot be lost, because nobody but their writer writes that file.
- **`unitTable`.** A unit unknown to this build is passed through. A unit that a later table moves between local and synced (P2 profiles, for example) is handled by that table: older Macs relay its entries and never apply them (A2 R-CLASS-3).
- **Σ** has its own `format`. A newer Σ, after a downgrade from a later N, is left unused, and the Mac joins.

### 6.5 Size limits (F-61, INV-13)

| Limit | Value | When it is exceeded |
|---|---|---|
| Device file, read | 1 MiB (today's `SettingsSyncFile.maximumFileSize`) | Refused, "a sync file can't be read" in Settings, retried; never treated as missing |
| Device file, write | 1 MiB, checked before writing | Not written; the previous file stays; warning in Settings |
| `HolzBarIcon` unit | 256 KiB encoded | Not published; "Your custom holzBar icon is too large to sync"; remote icons are not applied over it |
| JSON units | 64 KiB each | Not published; a note names the setting |
| Other units | 4 KiB each | Not published (only a corrupt value can get there) |
| Device files read | 64 | The rest are ignored with a note; their content still arrives through the relays (§7.5) |
| Entries per split unit | 1,024 | The file is refused as malformed |

Binary plist with the icon stored once: typical files are 5–20 KB, or 30–150 KB with a custom icon.

### 6.6 Names the reader accepts

- **Device files:** exactly `^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\.plist$`, read with `lstat`, `O_NOFOLLOW` and the size check, never through a symbolic link (the existing `readContents` and `isUsableFolder`).
- **Everything else is ignored:** `.DS_Store`, `Icon\r`, `.syncthing.*.tmp`, holzBar's own `.<MacID>.plist.tmp`, Nextcloud, Dropbox and Syncthing conflict names, and OneDrive's `-ComputerName` copies.
- **A name that starts with a known MacID** and does not match is a conflict copy of that Mac's file. Only the Mac with that MacID acts on it (join it, then re-identify, §5.1). Its name, which may contain a computer name, is never copied anywhere and is logged as private.

---

## 7. Algorithms

All decisions are pure Core functions over (Σ, local defaults snapshot, file contents). The app glue does I/O and UI only (A2 R-TEST-1).

### 7.1 Capture: a local change becomes an entry

```text
capture(local):                                        // main actor
  for u in units:
    d = digest(local[u])                               // "unset" when absent
    if d == Σ.baseline[u]: continue
    if live(u) holds one distinct value w and digest(w) == d:
        // a completed apply (crash recovery), or the user chose exactly that value
        Σ.applied[u] = dots(live(u)); Σ.baseline[u] = d; continue
    if u is over its size cap: Σ.status.oversize += u; Σ.baseline[u] = d; continue     // not published
    dot = mint()
    Σ.replica.reg[u] = live(u) − { e | e.dot ∈ Σ.applied[u] } + { (dot, local[u] or deleted, now) }
    Σ.replica.context[me] = dot.n
    Σ.applied[u] = { dot }; Σ.baseline[u] = d
  if anything changed: defaults[SettingsSyncGeneration] = Σ.generation + 1; persist Σ; schedule a write
```

- **The applied-context rule** (A3 §8.4). A local change supersedes only the entries the user here had seen, its applied dots. Another Mac's entry that arrived but waits for a restart stays live, so the unit becomes a question: this is `sync-1`'s rule (b), per unit.
- **When capture runs:** 2 s after the last change of the defaults (debounced), at launch before merging, before every apply (Restart, Use, Keep), and before quitting. It runs only while sync is on, and once at Turn On… (§7.9). Capture is diff-based, so changes made while sync was off are captured then: one change per unit, which is enough.
- **Why capture compares values instead of hooking every control:** it catches every user path at once (Settings controls, hotkey actions such as Toggle Auto Rehide, confirmed `holzbar://` commands, Import, undo, `defaults write` in Terminal). It cannot miss a change of the user's.
- **The price:** automatic writes of different values to synced keys would count as the user's. One exists and must be fixed (§17.3). The others rewrite equal values at load, which compare equal.

### 7.2 Merge: the join

```text
join(a, b):
  context = pointwise max(a.context, b.context)
  for u in keys(a.reg) ∪ keys(b.reg):
    keepA = { e ∈ a.reg[u] | e ∈ b.reg[u]  or  not covers(b.context, e.dot) }
    keepB = { e ∈ b.reg[u] | e ∉ a.reg[u]  and not covers(a.context, e.dot) }
    reg[u] = keepA ∪ keepB
  // Entries are equal when their dot and value digest are equal. The same dot with two
  // values is kept twice (a conflict, never a silent pick) and flags a collision (§5.1).
covers(c, d) = (c[d.mac] ?? 0) >= d.n
```

**Properties tested** (§13): commutative, associative and idempotent; joining an older replica changes nothing; contexts only grow. Each Mac's view is the join of Σ.replica with every readable device file, its own file included.

### 7.3 Plan: what each unit needs

For every unit u, with `vals(u)` the distinct values of `live(u)`:

| Case | Result |
|---|---|
| `live(u)` empty | Nothing (nobody ever published u). |
| One value w, and w equals the local value | **Equal**: applied = dots(live(u)), silently. No hint (INV-P2). |
| One value w that this build cannot apply | Nothing applied; status "A setting from a newer holzBar can't be used here". |
| One value w otherwise | **Fast-forward** (w, a deletion included). Applied at launch, or by Restart while running. |
| Two or more values | **Conflict**. |

**Clash check.** Simulate applying every fast-forward of the `Hotkeys` units. If two hotkeys would end up with the same key combination, those units become one **clash** row, which counts as a conflict. The system registers a combination only once per app, and today's `loadInitialState` would drop one of the two.

**Taking part.** A conflict is this Mac's if one of its live entries was made on this Mac (this MacID, or one this installation had before it re-identified). Capture has already turned any local change into such an entry. Otherwise the conflict is between other Macs, even when this Mac shows one of their values, and this Mac only waits (§8.1).

**Hint:**
- **Choose Settings…** when a conflict or clash is this Mac's;
- otherwise **Restart** when a fast-forward waits;
- otherwise none.

### 7.4 Apply

```text
apply(fastForwards):                    // at launch silently; while running only by Restart or Use, then relaunch
  capture(local)                        // a change made just before Restart still counts (S-64)
  replan; for each fast-forward (u, w) that is valid and not part of a clash:
    write w to the defaults (or remove the key or entry for a deletion)
    Σ.applied[u] = dots(live(u)); Σ.baseline[u] = digest(w)
  defaults[SettingsSyncGeneration] = Σ.generation + 1
  CFPreferencesAppSynchronize            // values and generation reach the disk before Σ does
  persist Σ
```

- **It never removes a key that has no deletion entry** (F-60). It never writes a layout, learned or local key.
- **Partial apply** (Q9): non-conflicting units apply even while another unit waits for an answer. None of them is a change of the user's here, so applying them loses nothing (`sync-1`: apply silently at launch when there are no user changes, read per unit).

### 7.5 Write: this Mac's file, relays and healing

- **What:** the header and Σ.replica. The write is skipped when the digest of the replica equals `published` and this Mac's file in the folder reads back intact.
- **When:**
  - own changes, debounced 2 s;
  - relays, debounced 10 s: after merging other Macs' entries changed the replica, so their values survive in this file;
  - healing, at the next check: this Mac's file is missing, damaged, older than Σ, or another installation wrote it (nonce, §5.1).
- **Why relays:** a writer that is gone for good and whose file was deleted still reaches a Mac that joins later (A2 INV-C6). They cost at most one write per Mac per change, and they settle: a relayed replica gives the others nothing new.
- **How:**
  - off the main actor, in one serial file actor, time-bounded;
  - coordinated `.forReplacing` for iCloud Drive;
  - otherwise a temporary file `.<MacID>.plist.tmp` in `Macs/`, then a rename;
  - `lstat` checks on `holzBar/` and `Macs/`;
  - holzBar creates only `holzBar/Macs/` inside an existing, accessible chosen folder; it never creates the chosen folder or mounts anything (F-18, A2 R-IO-5).
- **Before writing:** if this Mac's file carries a higher counter for this MacID with the same nonce, Σ was rolled back. holzBar joins that file first, raises the counter above it, then writes.
- **Size check** (§6.5): too large → not written, with a warning.

### 7.6 Launch (in `AppDelegate.init`, after the Ice import, before `AppState`)

1. Sync off and no Σ: return.
2. Identity check (§5.1).
3. Load Σ. If it is absent, unreadable or of a newer format, the Mac is joining: return. The join runs after setup.
4. **Consistency checks:**
   - preferences rolled back (generation, §5.4), or a pre-N build synced since N last ran (`SettingsSyncLastSynced` ≠ Σ.legacy, §7.10): the Mac joins, so return;
   - Σ behind the preferences: join this Mac's own file if it is readable now.
5. **Capture** (§7.1). A completed apply is adopted; real local changes become entries.
6. **Read** on the file queue, at most about 1 s in total: resolve the bookmark without mounting; list `Macs/`; read only local, non-dataless files (`SF_DATALESS`, `ubiquitousItemDownloadingStatus`). On timeout, cancel the coordinators. This is today's `readForLaunch`, applied to a folder.
7. **Merge** whatever was read.
8. **Plan.** Apply every valid fast-forward silently, including those that arrived in earlier sessions and were never restarted for. If the folder is unreachable, these come from Σ alone (INV-9).
9. Persist Σ.

The launch never asks, never shows a dialog and never writes the folder. Conflicts show as the hint after setup.

### 7.7 While running

- **Triggers:**
  - an `NSFilePresenter` on `Macs/` and `Profiles/` (iCloud Drive);
  - a `DispatchSource` on those folders (other providers);
  - app activation, wake and opening Settings;
  - a timer every 10 minutes only while the folder is on a network volume, where file system events cannot report other computers' writes (A3 §6).
  - Bursts are debounced by 2 s.
- **Then:** read in the background → merge on the main actor → plan → update the hint → schedule relay or healing writes. A file that is dataless or still being written is skipped and read on a later trigger. Downloads are requested in the background, and no decision ever waits for one.

### 7.8 Join

**When.** Turn On…; Change…; the first N launch with sync on; Σ lost or unreadable; preferences rolled back; a pre-N build synced since (§7.10); the folder now holds device files of none of the Macs in Σ's context (the bookmark leads to another group). An empty folder with a valid Σ is not a join: this Mac re-publishes its replica (§7.5).

**Steps:**

1. **Read the whole folder.** Every listed device file is read or refused for a lasting reason (too large, wrong type, newer format). Dataless files are downloaded in the background. The join waits up to about 10 s, showing "Reading the sync folder…" when the user started it, then goes on with what it has. A file that arrives later merges normally, and any conflict it brings appears with Later instead of Cancel. Nothing is published before the commit.
2. F = the join of the readable device files, and of Σ.replica when Σ is valid (Turn On… after Turn Off, Change… to another folder).
3. **Legacy input L**, only when `Macs/` holds no device file at all and `holzBar/Settings.plist` reads within the existing limits:
   - L is the synced units of its `settings`, validated;
   - `modified`, `deviceID`, `device`, `currentLayouts`, `copiedLayouts`, `seen`, the layout keys, the learned keys and every local key are ignored.
4. **Preview per unit.** With a valid Σ, capture runs first, so only true conflicts appear: units both sides changed. Without Σ, every present local value is a value without a dot. With Σ, a present local value is represented by its applied dots and counts as the folder's when it is one of the folder's live values.

   | Local value | Folder (F, or L when F is empty) | Preview |
   |---|---|---|
   | equal to a folder value | any | Adopt: applied = that entry's dots. A value from L becomes this Mac's entry. |
   | unset (key absent) | value | Fast-forward after the commit (Restart). |
   | present | no value | Published as this Mac's entry, with no question. |
   | present and different | one or more values | **Row of the join sheet** |
   | — | two or more values already | A group conflict: after the commit it is a normal conflict, with Later |

5. **No rows:** commit. Σ.replica = F plus the new entries; publish; set the hint from the plan.
6. **Rows:** the hint reads **Choose Settings…** and opens the join sheet (Use Settings from Sync Folder, Keep This Mac's Settings, Cancel, §8.3):
   - **Use:** each row takes the folder's value; commit; apply and relaunch.
   - **Keep:** each row gets a new entry with the local value that covers the folder dots shown; commit; publish.
   - **Cancel:** nothing is written. After Turn On… or a first run, sync stays off; after Change…, the previous folder stays.
7. **The commit** records Σ.folder, the legacy digest, `SettingsSyncLastSynced` as seen, and `join = none`.

**"No user value" means absent** (Q6). The settings models load with `Defaults.ifPresent`, so a fresh install has the keys absent: it takes the folder's values silently (Restart) and gets no question. A Mac that synced under β1 has every key present, so its differences are asked about. That is conservative, as A2 OQ-4 and R-POL-9 require.

### 7.9 Turn Off, Turn On, Change…, re-identification, rollback

- **Turn Off:** stops all folder access, keeps Σ, and hides the hint. Open siblings stay in Σ.
- **Turn On…** (same folder or another one): capture once, then join with Σ. Only units changed on both sides since are asked about, with Cancel available. Changes made on only one side merge (Restart on this Mac, or a fast-forward on the others). This departs from A2 R-FUN-6's "re-enabling is a join that compares everything": dots make the full comparison unnecessary, and it would force the user to discard one side's unrelated change.
- **Change… to an empty folder:** the replica is published there, so the group moves with the user. To a folder holding another group: per-unit questions for the units that differ, with Cancel keeping the old folder.
- **Re-identification** keeps the replica (§5.1).
- **Σ rolled back with the preferences intact:** this Mac's own file is ahead with the same nonce → join it → the counter goes above it.
- **Both restored (a full Time Machine restore of the home folder):** the group's newer values are fast-forwards and are applied. A restored Mac must not treat its old state as current (A1 §8). To roll back on purpose, the user imports an exported file (A3 §10 Q9).

### 7.10 Old builds on the same Mac

- **Downgrade N → β1 → N.** β1 pushes at every launch with sync on, which sets `SettingsSyncLastSynced`. β1 also applies the legacy file silently with remove-missing. If N finds `SettingsSyncLastSynced` changed since its last run, it joins: what β1 applied is asked about, never published as this Mac's changes (A2 INV-B7). N never writes or deletes `SettingsSyncLastSynced`, so β1 behaves after a downgrade exactly as it would have.
- **Downgrade N → β2 → N.** β2 is inert, so any change made under it is the user's and is captured.

---

## 8. Conflicts and the question

### 8.1 Definition

**A conflict** is a unit whose live entries hold two or more different values. Each value comes from a change made without knowledge of the other, in the applied sense of §7.1, so it is a real conflict under `sync-1`.

**Never a conflict:**
- equal values;
- a fast-forward, including one after several missed changes;
- anything about the arrangement, learned keys, flags, profiles or device tuning;
- a β1 rewrite;
- a dated, restored, delayed or duplicated file;
- this Mac's own entries (a new local change covers this Mac's applied dot);
- two different settings changed on two Macs (Q1).

**A conflict between other Macs** (no live entry of it was made on this Mac, §7.3) puts no hint in holzBar's menu on this Mac, and this Mac applies neither value. Settings → Advanced shows "Your other Macs differ on 1 setting" with **Choose Settings…** available, so a user who is here can answer. This keeps A2 INV-P1 (no question without this Mac's own change) and still lets the conflict resolve from any Mac. Once it is answered anywhere, this Mac gets a fast-forward.

### 8.2 Hint and status (Settings → Advanced and the top of holzBar's menu; never a dialog)

| State | Text | Button | Strings |
|---|---|---|---|
| Fast-forwards wait | "Settings changed on another Mac" | Restart | existing |
| A conflict or clash of this Mac's | "Settings changed on another Mac" | Choose Settings… | existing |
| A join reads the folder (user-started) | "Reading the sync folder…" | — | new |
| A join with rows | "Choose which settings this Mac uses" | Choose Settings… | new |
| Conflict between other Macs | "Your other Macs differ on %d settings" (Settings only) | Choose Settings… | new |
| Folder unavailable | "The sync folder cannot be found. Choose it again." | Change… | existing |
| Newer format seen | "A Mac uses a newer holzBar. Update holzBar to sync with it." | — | new |
| Legacy writer active (the legacy file changed after the join) | "A Mac with an older holzBar still uses this folder. Update holzBar there to sync with it." | — | new (Q11) |
| Oversize unit | "Your custom holzBar icon is too large to sync." | — | new |
| Refused files | "A sync file in the folder can't be read." | — | new |
| Annotation (all states) | "Keeps your hotkeys, appearance and other settings the same on all your Macs through a folder they sync: iCloud Drive, Nextcloud, Dropbox, OneDrive, Syncthing or a network share. The menu bar arrangement and layout profiles stay on each Mac; share a profile to use it on another Mac. holzBar never goes online. Changes from another Mac apply after a restart." | — | replaces today's string |

Every new string needs en, de (Swiss spelling), fr, it and rm, and `.github/scripts/strings-check.py` must pass.

### 8.3 The sheet

- **Where and how:** a sheet on the Settings window, opened only by Choose Settings… (`modal-alerts-1`, F-14). Only one sync sheet is open at a time (INV-P5). It has no default button (SA-07).
- **Title** (existing): "Which settings should holzBar use?"
- **Text** (new):
  - running: "You changed these settings on this Mac, and they were changed differently on another Mac. Your other settings stay as they are on all your Macs.";
  - join: "These settings differ between this Mac and the sync folder."
- **List:** one row per conflicting unit:
  - the setting's existing label (for hotkeys, "Hotkey: <action title>"; for item units, "<item name>: <setting>");
  - **This Mac:** the value, rendered as On or Off, the choice label, the number, the key glyphs or the icon;
  - **Sync folder:** the value and "changed on 3 Oct, 14:02". That date is the minting Mac's, for display only.
  - JSON units show "Changed" with the date.
  - A clash row reads "⌘⇧H: Show Hidden Items (this Mac) · Search Menu Bar Items (another Mac)".
- **Footer** (new): "Using the sync folder's settings restarts holzBar."
- **Buttons** (existing strings): **Use Settings from Sync Folder** (destructive), **Keep This Mac's Settings** (destructive), and **Later**, or **Cancel** when joining (Escape).

### 8.4 Answer semantics: an answer is a write that covers exactly what was shown

For each row, the sheet keeps `shown[u]`: the dots of the entries it displayed.

| Answer | Effect per row u |
|---|---|
| **Use Settings from Sync Folder** | New entry: the folder's value, covering `shown[u]`. Then apply (§7.4) and relaunch. |
| **Keep This Mac's Settings** | New entry: this Mac's current value, covering `shown[u]`. No relaunch, unless fast-forwards wait (then the hint becomes Restart). |
| **Later** | Nothing. The siblings stay in Σ and in every file, and the hint stays. The sheet never opens by itself (INV-P4). |
| **Cancel** (join only) | Nothing written (§7.8). |

**Clash rows.**
- Keep: the other Mac's hotkey gets this Mac's value for it (its old combination, or none).
- Use: this Mac's hotkey loses the combination, and the other one is applied.

**A row with several folder values** (three Macs): the row lists them all, and Use takes the one with the newest display date, marked "(used)". The clock only proposes; the user sees what will happen, and the answer covers every shown dot.

**Consequences:**
- An entry that arrives while the sheet is open is not in `shown[u]`. It survives, and if it differs, the hint returns. This settles R1–R3's Keep-scope findings by construction (S-33, S-46).
- One answer settles a unit on every Mac. The resolution entry covers both siblings, so the other Mac gets a fast-forward, or nothing at all when its value was chosen (equal → silent).
- Use and Keep answered for the same unit on two Macs at once make one new pair of siblings and one more question. As soon as either is answered, the Macs converge (A2 INV-C3).

### 8.5 Questions holzBar never asks (must-not-ask)

holzBar never asks about:
- a relaunch;
- joining an empty folder, or one with equal settings;
- a fresh install whose keys are absent;
- a cloned Mac with a copied Σ;
- holzBar's placements, learned keys or flags;
- the other macOS version;
- a β1 rewrite;
- a restored, late or duplicated file;
- several missed changes from one Mac (a closed laptop);
- two different settings changed on two Macs (Q1);
- equal values;
- this Mac's own earlier entries.

---

## 9. macOS 26 and 27

- **Layouts are never units.** `ItemSections`, `MacOS27Layout` and their learned lists are never captured, read from a file (legacy input included) or applied. Questions between macOS versions, F-60 between versions and "copies" of the other generation cannot occur.
- **OS-specific settings** (such as the camera dot of macOS 27) are ordinary units. A Mac that does not use them keeps and relays them, and gets them when it upgrades. If a setting ever needs a value per macOS version, the unit table can split it into `<key>@26` and `<key>@27` in a new table version. None needs that today.
- **Upgrading macOS 26 → 27** is local, as before: Concealer27 seeds from the bar.
- **What β1 left on each Mac.** A macOS 26 Mac that synced under β1 may hold a copy of another Mac's `MacOS27Layout` and an OR-merged `MacOS27LayoutSeeded`. D3 leaves both alone; nothing is deleted.
  - On an upgrade, the Mac starts from that copy, as β1 intended.
  - Companion repair (local, optional): on a macOS 26 Mac, `MacOS27LayoutSeeded` true with an empty `MacOS27Layout` is an OR artifact that would stop seeding after an upgrade. Clear the flag once (A2 INV-K3).
- **Profiles** carry only their own generation's part when shared (§4.4).

---

## 10. Migration

| From | First N launch | Notes |
|---|---|---|
| **β1, 0.0.6, 0.0.6-beta2** (sync on) | Identity check: the uid-bound hash differs once, so the MacID rotates (§5.1). No Σ → the Mac is joining. After setup: if `Macs/` is empty, the legacy file is join input; otherwise the group. Equal → silent commit. Different present values → the join sheet. Nothing from the folder is applied at this launch. | The legacy file is never written. `SettingsSyncLastSynced`, the folder bookmark and `SyncsSettingsWithICloud` are kept (§7.10). |
| **0.0.6-beta1** | As above. | Its sync code differs from β1 only in the presenter's isolation, which later code notes would crash holzBar once sync was on. |
| **β2** (paused) | As β1: the stored configuration is intact. Settings the user changed during the pause are present values: asked about where they differ, kept where they are the only value. | The 77ab5629 requirement (layout edits during the pause) is vacuous: no layout is ever replaced. |
| **Unreleased SA05 and sync-fix builds** | As β1. Their keys (`SettingsSyncBase*`, `…LayoutEdits`, `…PendingModified`, `VersionSettingsDigest`, `RecentLayoutDigests`, `KeptLayoutDigest`, `LastWritten`, `SeenWrites`) and file fields (`currentLayouts`, `copiedLayouts`, `seen`) are ignored, never read as evidence (A2 R-COMPAT-5, INV-B6). | They are left in place, never deleted (downgrade safety). |
| **Sync off on the old build** | Nothing until Turn On…, which is a join. | |
| **Fresh install** | Turn On… is a join: absent keys take the folder's values (Restart), and present ones are compared. | |
| **0.0.5 and earlier (`holzIce/`)** | Never read. | A2 R-COMPAT-6 |

**Several Macs updating at once** (two N Macs both see an empty `Macs/` and use the legacy file): both commit and publish their own entries. Equal values collapse. Different values become siblings, and one question settles them. Nothing is lost.

**The β1 group's later changes** reach N only when a β1 Mac updates: its join compares its present values, which include the β1 group's latest state, with the N group. That is where the two groups merge, by the user's answers. A continuous one-way import of β1 changes is not offered: a provider restore of `Settings.plist` and a β1 user's deliberate change look the same without lineage (§5.2 pair 1).

---

## 11. Failure handling

### 11.1 Per root-cause class

| Class | Situation | What D3 does |
|---|---|---|
| RC-1 | Two Macs write at once | Different files: both survive. Per unit, concurrent values become siblings → question only if they differ. |
| RC-1 | A Mac that is behind writes | Its context lacks the unseen dots, so its entries cannot cover them; nothing of the other Mac's is replaced. |
| RC-2 | Skew, steps, same second, future dates | Ignored: dots per Mac; dates for display only. |
| RC-3 | A device file deleted | Its owner re-publishes it at the next check, and others already relay its entries. No local deletion anywhere (A2 INV-F6). |
| RC-3 | The whole `holzBar/` folder deleted | Every Mac re-publishes its replica, and the group is back. β1's file is gone for β1 Macs (β1's business). |
| RC-3 | A file restored to an older version (version history, Rewind, Time Machine, Syncthing) | Dominated: the join changes nothing, and no question arises. The owner heals its file (A2 INV-F5, SC-55, SC-65). |
| RC-3 | Damaged, truncated or partial (SMB, non-coordinating writers) | Refused, never "missing"; retried; the owner heals its own (A2 INV-F1, INV-Z6). |
| RC-3 | Dataless, online-only | Never read at launch or on the main thread; background download; merged when local (F-15). |
| RC-3 | Too large | Refused by readers. The writer never writes it (§6.5). Nobody writes over another Mac's file in any case. |
| RC-3 | Delivered late, coalesced, reordered, duplicated | The join is commutative, associative and idempotent (A2 INV-F2, INV-F3). |
| RC-4 | Layout keys or a legacy peer that removes missing keys | Not units; the legacy file is never written. |
| RC-5 | A lost record | There is none to lose besides Σ. A lost Σ → join. |
| RC-6 | holzBar's placements, learned lists, flags | Local keys, never captured. |
| RC-6 | An automatic write of a different value to a synced key | Must not exist. The one found is fixed (§17.3); a review and grep rule keeps it so (§13.6). |
| RC-7 | β1 writes, rewrites, applies, drops metadata | Not N input after the join; N never feeds β1. |
| RC-7 | β2 | Inert, like a Mac that is switched off. |
| RC-7 | Downgrade loop | Detected (§7.10) → join. |
| RC-7 | A newer N (N+) | Its files are skipped (major) or passed through (units). Never rewritten. |
| RC-8 | Answer scope | Covers exactly the shown dots (§8.4). |
| RC-9 | Quit or crash mid-capture | Σ not persisted → the next launch captures again. Nothing reached the folder: device files are written from a persisted Σ only. |
| RC-9 | Crash between applying to the defaults and persisting Σ | The next launch adopts the equal value (§7.1). |
| RC-9 | Crash after an answer's entry is persisted, before applying | The next launch applies it as a fast-forward. |
| RC-9 | An edit during a write | Captured into Σ; another write follows. Nothing is marked "synced": the applied set changes only on apply. |
| RC-9 | Hint from a stale state | The hint is recomputed from Σ after every capture and merge, on the main actor. |
| RC-10 | Clone, restore, copied account | Hash bound to hardware and account; nonce; collisions → re-identify (§5.1). |
| RC-10 | Hung provider, unmounted share | Bounded, cancellable reads off the main thread; `.withoutMounting`; status; resume on mount. |
| RC-10 | Malformed values | Validation per entry; pass-through; no write-back (F-59). |
| RC-10 | A symbolic link, or a folder in place of a file | Refused (`O_NOFOLLOW`, `lstat`). |
| RC-10 | Hostile folder writer | Can forge entries that supersede values, as anyone who can write the folder can today. Values stay within the schema; file names that come from synced values (item icon and group image files) are accepted only as plain names, with no `/` and no `..` (A2 R-SEC-3); sizes are bounded. Authenticity is out of scope. |
| RC-11 | Defects that review cannot see | §13. |

### 11.2 Per provider (A2 §6.2)

| Provider | Specific risk | Handling |
|---|---|---|
| iCloud Drive | Dataless files, `NSFileVersion` conflicts, Recently Deleted restores | Dataless handling; a conflict version of this Mac's file is the collision signal; restores are dominated. |
| Dropbox, OneDrive, Google Drive | Conflict copies by name (OneDrive puts the computer name in it); online-only files | Names ignored; a copy of this Mac's file → join it, then re-identify; names never copied or logged in clear. |
| Nextcloud | The conflict copy stays on the writing Mac by default | Cannot happen with one writer per file. |
| Syncthing | Delivery lags for days; `.sync-conflict-` copies; replica rollback | Order-free join; names ignored; rollback = restore → heal. |
| SMB, AFP, NFS, WebDAV | Last writer wins; partial reads; unmounts; no events for other computers' writes | One writer per file; validation; never mount; a 10-minute timer only on network volumes. |

---

## 12. Privacy

- **No network.** holzBar opens no connection; the user's sync app moves the files (C-1; CI's no-network check stays).
- **What enters the folder:** the values of synced units only (the unit table is an allow-list), a random MacID, a random nonce, counters, display dates, format and unit-table versions, and shared profiles the user published explicitly.
- **What never enters it:** the hardware UUID, its hash, the salt or the uid; the computer name or user name; paths and bookmarks; display and Space UUIDs (profile bindings); the list of every menu bar app (`KnownItemTags`, `KnownApplications27`, both layouts). The last two travel today; D3 stops that.
- **What still travels:** item identity keys (bundle ID plus canonical title) of items the user configured (icons, marks, item hotkeys, groups), as today, and only for those items.
- **Local only:** Σ (in Application Support) and `SettingsSyncGeneration` and `SettingsSyncDeviceHash` (in the preferences).
- **Logs** mark paths, values, IDs and file names as private. Conflict-copy names are never logged in clear.
- **Docs to update:** `docs/privacy-and-permissions.md`:
  - the folder row (`holzBar/Macs/<id>.plist`, `holzBar/Profiles/`);
  - the hardware-UUID paragraph (the uid is now hashed with it, locally);
  - Σ in Application Support.

---

## 13. Test strategy

### 13.1 Structure that makes testing possible

- **Core** (Foundation-only, compiled by `swift test`):
  - the unit table with validators and the mapping between the defaults and units ([String: Any] in and out);
  - the replica, join, capture, plan, apply plan, answer and join preview;
  - the codec (encode, decode, size, format);
  - identity and counter decisions;
  - legacy input;
  - shared-profile codec.
- **The glue** (file actor, presenter, watcher, defaults adapter, sheet and hint):
  - has no branch that changes an outcome;
  - calls the same Core entry points as the simulator (A1 RC-11, A2 R-TEST-1);
  - a CI lint forbids `NSFileCoordinator` and `FileManager` in main-actor sync code (A2 INV-R1).

### 13.2 Algebraic and property tests

- The join is commutative, associative and idempotent; `join(x, older(x)) == x`.
- The context grows monotonically under capture, join and answer.
- Capture is idempotent, and an A→B→A change within one debounce makes no entry.
- An answer covers exactly `shown`; an entry outside `shown` always survives.
- Codec round trip; unknown units and values pass through byte for byte.
- Validation never empties a unit, and never turns a valid entry into a deletion.
- The unit table is complete for `Defaults.Key` (A2 R-CLASS-1).
- The counter never repeats under clock steps and Σ rollbacks.

### 13.3 Simulator

Model-based, seeded, deterministic, in the test package; the shape is A2 §2 and §8.

- **Macs:**
  - N Macs run the real Core through the adapter;
  - **β1 peers** run A2 §2.6 literally: they write at launch and 5 s after any defaults change, automatic writes included; never read first; apply silently with remove-missing; drop unknown keys; use `modified > lastSynced` and the 1 h future window;
  - β2 peers are inert towards the folder, but their users edit settings.
- **Provider:** delay, coalescing, reordering, duplicates, conflict copies, last writer wins, restore, delete, delete folder, evict to dataless, partial reads, stalls, unmount, and foreign bytes including symbolic links. Presets: iCloud, Syncthing, SMB, Hostile (A2 §6.3).
- **Clocks:** offsets of ±7 days and steps of ±1 day.
- **Lifecycle:** launch; quit; a crash between any two persisted steps; sync off and on; Change…; Clone; RestorePrefs; Σ lost; Σ restored; CopyAccount; downgrade N → β1 → N; UpgradeOS.
- **User:** edits, deletions, import, profile share, add and update, and answers. Use, Keep, Later and Cancel are chosen by the explorer, all of them in exhaustive mode.
- **Automatic events:** placements, learning and flags. They write only local keys, by construction.
- **A rogue-writer mutation** (an automatic write of a different value to a synced key) must make an oracle fail. That shows the oracles see RC-6 if it returns.

### 13.4 Oracles

| Oracle | Source | Checked |
|---|---|---|
| No silent loss or revert of a live user value; no global loss | A1 INV-1, INV-2; A2 INV-S1, INV-S1g, INV-S2 | every sync-caused transition; every step |
| Honest publication: the context covers only ingested dots, and every live covered change is carried | A2 INV-S3 | every write |
| Absence is not deletion; deletions travel | A2 INV-S4, INV-S5 | every ingestion |
| A Mac writes only its own file | A2 INV-S6 (structural) | every write |
| A waiting change lasts | A1 INV-9; A2 INV-S7 | every step |
| No local key, identifier or salt in any written byte | A2 INV-S8, INV-PR2 (planted markers) | every write |
| An answer binds to what was shown | A2 INV-S9 | every answer and the next write |
| Automatic events change nothing in sync | A2 INV-A1 (metamorphic) | paired runs |
| Every prompt has a witness; equal means silent; no repeat; Later; one sheet; necessity | A2 INV-P1 to INV-P6 | every prompt |
| Agreement, write quiescence, bounded questions, no ping-pong, progress, folder agrees | A2 INV-C1 to INV-C6 (synced units) | after a drain |
| Identity unique, stable, collisions, "own means written by me" | A2 INV-ID1 to INV-ID5 | every launch and read |
| Sizes bounded | A2 INV-Z1 to INV-Z6 | every step |
| Partial, conflict copies, restore, delete, dataless, order, clock independence | A2 INV-F1 to INV-F10 | fault scenarios; metamorphic clock runs |
| Mixed versions | A2 INV-B1 to INV-B9 | peer scenarios |
| No layout key is ever changed by a sync-caused transition | D3-specific | every transition |

### 13.5 Exploration

- **Exhaustive small scope:** 2–3 Macs, both macOS generations, at least one β1 peer, up to about 8 events, every interleaving and every answer.
- **Seeded random long runs:** thousands of steps per preset.
- **Metamorphic pairs:** automatic events, clocks, delivery order.
- Every failure is minimised and printed as a scenario, ready to become a regression test.
- **Mutation gate** (A2 R-TEST-5): every guard mutation in the Core must make a scenario fail.

### 13.6 Named regression tests, fuzzing, lint

- Each A1 scenario in its settings form (§14), with the layout keys asserted untouched.
- Each D3 scenario (§15).
- A2 SC-01 to SC-71.
- Codec fuzzing with arbitrary bytes, truncations and type swaps (A2 R-TEST-4).
- A lint that lists every `Defaults.set` of a synced key outside the settings models' setters, the import, sync's apply and the answer. Each must be reviewed (the guard for RC-6).

### 13.7 Real Macs (A2 R-TEST-7; still open from SYNC-01)

Two Macs, on iCloud Drive with Optimize Storage, on Dropbox or OneDrive, and on an SMB share:
- same macOS;
- macOS 26 with 27;
- one Mac on 0.0.7-beta1 (two groups, nothing harmed);
- dataless at login;
- Turn On… on a fresh Mac and on a migrating one;
- the same setting changed on both;
- different settings changed on both;
- Later, then relaunch;
- Turn Off, edits, Turn On…;
- downgrade to β1 and back;
- profile sharing;
- an unmounted share;
- a deleted `holzBar/` folder.

---

## 14. Regression walk: A1 S-01 to S-70

**Verdicts:**
- **PASS:** the scenario, as written, meets its Must.
- **SCOPE:** the scenario is about the arrangement. Sync never writes, applies or takes in an arrangement, so its safety clauses hold by construction and its settings form passes. Clauses that need an arrangement to reach another Mac are waived by design (§3.1).
- **BOUNDARY:** the scenario is about a β1 peer. N never writes the file β1 applies and reads it only as join input, so nothing N does harms the β1 Mac and β1 cannot harm the N group. Clauses that need a change to cross between β1 and N are waived (two groups, §3.1).

### G1 · Joining, identity, routine writes

| S | D3 outcome | Verdict |
|---|---|---|
| S-01 second Mac joins with defaults | Turn On… on B is a join (§7.8); nothing is written before the decision. B's absent keys take A's values (Restart); B's present equal values are silent; present different values → join sheet (Use, Keep, Cancel). A changes only where B's user chose Keep, or where A has no value and B's user set one (propagation of B's own change; nothing of A's replaced). Neither arrangement moves. | PASS |
| S-02 relaunch, nothing changed | Capture finds no difference; no dot; replica digest unchanged → no write; no hint anywhere (INV-C4). | PASS |
| S-03 Mac behind writes over newer | B writes only `Macs/B.plist`; A's file untouched. B's entries cannot cover A's unseen dot. Different units merge; the same unit → siblings → question on both. If A's file is dataless on B, B skips it and still writes its own file without claiming A's dot. | PASS |
| S-04 Later, then any push | B's change waits on A as a live, unapplied entry in Σ. A's automatic writes touch local keys only. A's change of another unit publishes without covering B's entry. A's change of the same unit → sibling → Choose Settings…. B never loses its change; it is in B's file and relayed in A's. | PASS |
| S-05 notice open while pushes run | Publishing continues (single-writer files cannot overwrite B), but no write covers B's entry (applied-context rule). Restart applies B's entry, or B's newer one, never nothing. The mechanism differs from the Must's "no push"; its purpose holds (A2 INV-S7 b allows it, OQ-13; Q4). | PASS |
| S-06 Migration Assistant, restore, clone | Hash of hardware and account differs → new MacID and nonce. The copied Σ is kept: a valid replica, so no question if settings are equal. Later changes of either Mac carry their own dots and are never ignored. Without a copied Σ: join, equal → silent. The hash never leaves the Mac. Departs from "clear the sync state" (§5.1); the outcome Must holds. | PASS |
| S-07 joining without a conflict | Empty folder → publish, no question. Own file with Σ lost → counter and values recovered from it; equal → adopt. Equal settings → adopt. Re-identified with equal settings → nothing to ask. No new entries for equal values, so no hint on other Macs. | PASS |
| S-08 sync on, folder never reached | A's hand-made arrangement is never compared, written or replaced. Settings: the first readable folder triggers the join; equal → silent. | SCOPE |

### G2 · Infrastructure

| S | D3 outcome | Verdict |
|---|---|---|
| S-09 online-only file at login | Launch reads Σ and only local, non-dataless device files within about 1 s on the file queue; dataless ones download later; no coordinated I/O on the main thread. Waiting entries already in Σ are applied anyway. | PASS |
| S-10 share not mounted | `.withoutMounting`; "The sync folder cannot be found"; resumes on the mount notification (F-18 code kept). | PASS |
| S-11 file over the size limit | Per-unit cap: a large icon is not published, with a note, and every other unit syncs. Whole-file check before writing. Readers never write over a refused file; they never write other Macs' files at all. β1 variant: an oversize legacy file is refused as join input and never written. | PASS |
| S-12 malformed entry | Validation per unit and entry at apply. A bad entry stays in the replica, untouched, never applied and never "repaired". Layout keys are not synced, so "every app visible" cannot come from sync. The app-wide F-59 reader fix is still needed for local data. | PASS |

### G3 · Two macOS versions

| S | D3 outcome | Verdict |
|---|---|---|
| S-13 applying the other OS's file | Apply never removes a key without a deletion entry; layout keys, flags and known lists are local. | PASS |
| S-14 macOS 26 and 27 with equal settings | No layout is ever compared; equal settings → no question; each layout untouched. | PASS |
| S-15 stale other-OS layout from a restored own version | No layout in any file. Settings form: A's restored file is dominated; A rewrites it; C's join of it changes nothing; C keeps L_C2 and gets A's setting. | SCOPE |
| S-16 stale other-OS layout from another Mac's old version | As S-15. | SCOPE |
| S-17 three Macs, copy promoted | D's write cannot touch C's arrangement. Settings form: D's older values are covered by C's dots and ignored. Waived: "if D's user rearranges too, holzBar asks" (arrangements never conflict). | SCOPE |
| S-18 β1 Mac of the other OS writes an old copy | The legacy file is not read after the join → no question, no revert. C's `ItemSections` are never touched by N. Waived: "the file ends with A's layout current". | BOUNDARY |
| S-19 [C1] file lost while a β1 Mac of the other OS syncs | N never writes `Settings.plist`, so nothing A does can make C delete or revert its layout. A lost legacy file is β1's own business. Resolved. | BOUNDARY |

### G4 · Same macOS version with a β1 Mac

| S | D3 outcome | Verdict |
|---|---|---|
| S-20 β1 drag overwritten by an N write | N never writes the legacy file → B keeps L_B; A leaves L_B alone; no drag on A replaces anything elsewhere. | BOUNDARY |
| S-21 β1 Mac updated to N adopts the other layout | B's arrangement is never adopted from anywhere. B's first N run joins the settings group and asks only about differing settings. | BOUNDARY |
| S-22 N Mac with its own arrangement joins a β1 folder | Nothing is replaced, so no question is needed. Waived: "C asks". | BOUNDARY |
| S-23 kept arrangement written back by β1 | No kept arrangements; β1 writes are not input after the join. | BOUNDARY |
| S-24 β1 keeps writing an old copy | No question; C's `ItemSections` untouched. | BOUNDARY |
| S-25 [pair 1, C2] β1 user returns to L1 | The return can never be reverted by N; A's drag affects only A. Resolved. | BOUNDARY |
| S-26 [C2] β1 write over a deleted file | B's change lives in `Macs/B.plist` and every replica that merged it; β1's file is not input; B never takes C's file. Resolved. | BOUNDARY |
| S-27 β1 rewrites at launch and after automatic changes | Ignored by N Macs after the join: no hint, nothing displaced. Optional note "an older holzBar still uses this folder". | BOUNDARY |

### G5 · Clocks

| S | D3 outcome | Verdict |
|---|---|---|
| S-28 change dated before the last sync | Dates are not consulted. B's dot is not covered by A's context → fast-forward (A has no change of the unit) or sibling (A changed it). | PASS |
| S-29 an older version's layout recorded as synced | No layout. Settings form: the applied set records only what was applied. | SCOPE |
| S-30 version dated far in the future | Dates are display only; counters per Mac. | PASS |
| S-31 re-joining Mac adopts an older version | The steps are drags. Settings form: a re-join with Σ asks only real conflicts and records nothing as applied that was not applied. | SCOPE |
| S-32 [pair 9] clock set back, two writes in one second | The counter never repeats (§5.2); W2 has its own dot; B's write covers only what B saw → W2 stays live. A asks only if B changed the same unit (both values shown); otherwise they merge. The deleted file does not matter. | PASS |
| S-33 Keep over a version dated at or before the answered one | Keep covers exactly the shown dots; B's later entry stays and is asked about if it differs. | PASS |

### G6 · Missing, restored, unusable files

| S | D3 outcome | Verdict |
|---|---|---|
| S-34 write over a missing file reverts another Mac | No shared file. B's change is in B's file (re-published if deleted) and in A's replica once merged. A's writes never cover B's unseen dot. | PASS |
| S-35 waiting version dropped when the file goes away | The waiting entry is in A's persisted Σ; still offered; nothing written covers it. | PASS |
| S-36 relaunch while the file is missing | Σ survives; the non-conflicting waiting entry is applied at launch (a conflicting one stays offered); A's later change publishes. | PASS |
| S-37 Keep without a layout edit, then the file goes away | Keep publishes A's value only for the shown setting; B keeps its arrangement (never synced). Waived: "A takes L_B in later". | SCOPE |
| S-38 copy over a missing file promotes holzBar's layout | No layout written, ever. Waived: "B's drag lists B's layout as current". | SCOPE |
| S-39 several writes, or a third Mac, without B's change | Contexts carry each Mac's counter; neither A's writes nor the third Mac's cover B's dot → B keeps its change everywhere. A question comes only if the same unit changed concurrently, which is stronger than "B asks" and still never silent. | PASS |
| S-40 third Mac applies a version without a held write | The steps are a drag. Settings form: C's applied entries are covered only by writers that saw them → C keeps A's value. | SCOPE |
| S-41 [pair 8] the record claims a write never taken in | No layout. "Seen" (context) and "taken in" (applied) are separate facts in Σ. | SCOPE |
| S-42 provider restores an older own version | Σ is authoritative: the restored own file is older → A rewrites it; joining an older replica changes nothing; A's drag is local. | SCOPE |
| S-43 unusable file variants | Refused files are never "missing". Nobody writes another Mac's file. A refused own file is rewritten by its owner. A symbolic link in place of `holzBar/` or `Macs/` is refused for reading and writing. S-44 still works. | PASS |
| S-44 setting up a new folder | Empty `Macs/` → A publishes its replica without a question; B's join follows S-01 and S-07. | PASS |

### G7 · What an answer means

| S | D3 outcome | Verdict |
|---|---|---|
| S-45 Keep writes an untouched layout over a newer arrangement | Keep publishes A's value for the shown setting only; L2 stays on B, L1 on A. Waived: "folder keeps L2; A takes L2 in; a drag on A asks". | SCOPE |
| S-46 a version arrives while the question is open | The new entry is not in `shown` → it survives; the hint returns if it differs. | PASS |
| S-47 Keep, then sync off and on before the restart | Keep is a persisted dot; off and on with Σ asks nothing new; B keeps L2. Waived: "A takes L2 in". | SCOPE |
| S-48 Keep, a drag, joining again | A re-join with Σ asks only real conflicts; A's drag is local. | SCOPE |
| S-49 after Keep, pushes stop, or a change asks about this Mac's own write | Publishing never stops; this Mac's entries never conflict with its own later changes. The toggle syncs and B receives it. Waived: "A takes L2 in at the relaunch". | SCOPE |
| S-50 Keep for a re-joining Mac brings the question back | One answer is one write covering every shown dot: settled. | PASS |
| S-51 Keep over a restored older version relists its layout | Restored files are dominated: their entries are not live, so they are never shown, applied or listed. D's arrangement is local. | SCOPE |
| S-52 Keep after a lost write | A's change is in A's Σ and re-published; the sheet shows both values; the chosen one wins everywhere. Waived: "B shows A's arrangement after a restart". | SCOPE |
| S-53 Keep answered while the file is missing | Keep is a dot in A's Σ; A re-publishes; on B, A's entry covers B's → Restart, not a question; after it, B has A's setting and its own arrangement. Different settings: no question at all, both merge. | PASS |
| S-54 [pair 5] the kept-layout record lost after a write | No kept records; Σ atomic with the generation check. A lost Σ → join: asks about differing present values and never overwrites on a missing record. | PASS |

### G8 · Automatic versus user changes

| S | D3 outcome | Verdict |
|---|---|---|
| S-55 holzBar places new items | Placements write local keys only; nothing captured; no hint anywhere; never replaces anything elsewhere. | PASS |
| S-56 Command-click without a move | Local only; sync sees nothing. | SCOPE |
| S-57 applying the current profile again | Local only. | SCOPE |
| S-58 first move of an unsaved item | The move stays on that Mac; sync never reverts it. Waived: "A writes it". | SCOPE |
| S-59 macOS displaces items, then the user Command-clicks | A mis-saved displacement can never spread to another Mac; it stays a local SectionRestore matter. | SCOPE |
| S-60 reconciliation stores an old section over a fresh save | Local; never spread. | SCOPE |
| S-61 a move in the Layout pane during a restore | Saved locally; "the next restore never reverts it" is a local requirement D3 does not change. Waived: "synced". | SCOPE |
| S-62 layout rearranged during the β2 pause | The arrangement is never replaced by sync. Settings changed during the pause are present values → the first N join asks where they differ. | SCOPE |
| S-63 only learned keys differ | Learned keys are local; nothing to merge, ask or restart. | PASS |

### G9 · Timing races

| S | D3 outcome | Verdict |
|---|---|---|
| S-64 Restart within 1.5 s of a drag | The drag is local. Settings form: Restart and Use capture first, so a setting changed a moment before counts (it may turn Restart into Choose Settings…). | SCOPE |
| S-65 an edit during an exchange | Capture is synchronous on the main actor and persisted; the device file is a snapshot of Σ; no "synced" mark exists that could be set wrongly; the edit causes another write. | PASS |
| S-66 a hint built from a stale state | Hints are recomputed from the current Σ after every capture and merge. | PASS |
| S-67 displacement and arrangement within the settle window | Local only. | SCOPE |

### G10 · Convergence and how often holzBar asks

| S | D3 outcome | Verdict |
|---|---|---|
| S-68 a closed laptop catches up | B's second entry covers its first; single live values → applied silently at launch or by Restart; no question. | PASS |
| S-69 an arrangement held only as a copy stalls | No copies exist; synced settings converge (INV-15 for synced units). Waived: "the Macs converge on the newest arrangement". | SCOPE |
| S-70 extra questions after bookkeeping gaps | No `lastWritten` or `seen`; no 64-entry cap (contexts grow with Macs ever seen, bounded by the file limit); a clock set back cannot repeat a counter; no question when none of this Mac's changes is missing. | PASS |

**Tally: 33 PASS, 27 SCOPE, 10 BOUNDARY.** No scenario fails a safety clause. The waived clauses are exactly the ones that need an arrangement, or a β1 Mac's change, to reach another Mac.

**A1 §8 appendix (hazards never exercised):**
- **Provider conflict copies:** structurally absent in normal use; a copy of a device file is the collision signal (§6.6).
- **Local state rolled back on the same hardware:** generation check and own-file recovery (§5.4, §7.9).
- **Preferences deleted or the app reinstalled:** Σ, the MacID or both are gone → join, which recovers from the own file when the MacID survived.
- **The folder moved or renamed:** the bookmark follows it, and the waiting entries live in Σ, not in the folder (INV-9).

---

## 15. New scenarios this design introduces (regression tests)

| ID | Scenario | Must |
|---|---|---|
| D3-S01 | A changes Show on Hover, B changes Auto Rehide, concurrently | Both Macs end with both changes; no question (Q1). |
| D3-S02 | A and B change Show on Hover to different values concurrently | One Choose Settings… on each Mac; one answer on either settles both; the other gets Restart, or nothing when its value was chosen. |
| D3-S03 | A, B and C change one setting concurrently; D's change arrives while A's sheet is open | The sheet lists three values; the answer covers them; D's value is asked about anew. |
| D3-S04 | A answers Keep and B answers Use for the same conflict at the same time | One more question, then convergence (bounded). |
| D3-S05 | B and C conflict; A changed nothing | No hint in A's menu; Settings shows "Your other Macs differ"; once B answers, A fast-forwards. |
| D3-S06 | A gives ⌘⇧H to Show Hidden Items, B gives it to Search, concurrently | A clash row; neither hotkey goes dead silently; `loadInitialState` never meets a duplicate made by sync. |
| D3-S07 | A changes X; B and C merge it; A is retired and its file deleted; fresh D joins | D gets X from B's or C's relayed replica (INV-C6). |
| D3-S08 | N → 0.0.7-beta1 (launch with sync on, a stale legacy file applied) → N | The return to N is a join: what β1 applied is asked about, never published as this Mac's change (INV-B7). |
| D3-S09 | Preferences restored from a two-week-old backup, Σ not | Generation check → join; the restored values are not published as new changes; no silent revert of B (A2 SC-06). |
| D3-S10 | Σ restored alone, or lost, with the own file in the folder | Own-file recovery; the counter goes above it; no duplicate dot; no question when values are equal. |
| D3-S11 | A second user account on the same Mac with copied preferences | The uid-bound hash differs → new MacID; both accounts sync; no shared file. |
| D3-S12 | Crash between applying to the defaults and persisting Σ, at launch and at Use | The next launch adopts the applied value; nothing is published as a new change. |
| D3-S13 | An N+ Mac publishes a unit, or an enum value, this build does not know | Relayed byte for byte, never applied, never deleted; "update holzBar" note. |
| D3-S14 | A custom icon of 400 KB (from Ice) | Stays on its Mac with a note; every other unit syncs; remote icons are not applied over it. |
| D3-S15 | The first N Mac finds an empty `Macs/` and a β1 file that differs in two settings; a second N Mac comes later | The first asks about the two differences (Use, Keep, Cancel); the second joins the N group, never the legacy file. |
| D3-S16 | A (macOS 27) shares "Work"; B (27) adds it; A saves "Work" again; C (26) sees it | B sees Update and applies it locally; C sees "made on macOS 27" and applying changes nothing; bindings and current profile never travel. |
| D3-S17 | `defaults write com.holzcloud.holzBar ShowOnHover -bool true` while holzBar is quit, with B's change of ShowOnHover waiting in Σ | Captured at launch before anything is applied → a conflict, not a silent apply over it. |
| D3-S18 | Dropbox makes `<A's MacID> (conflicted copy …).plist` | A joins it and re-identifies; no other Mac acts; the name is never logged in clear. |
| D3-S19 | Turn Off on A; A changes X and Y, B changes Y and Z; Turn On… on A | Only Y is asked about, with Cancel; X and Z merge. |
| D3-S20 | 70 Macs in the folder | 64 files read, a note shown; nothing lost, because every value is relayed. |

---

## 16. Decisions for the maintainer (multiple choice; the first option is recommended)

| # | Question | Options |
|---|---|---|
| Q1 | Two Macs change **different** settings since they last synced | (a) merge both, no question (nothing is overwritten or reverted); (b) ask once for all differences (the literal reading of `sync-1`: either answer discards one Mac's unrelated change) |
| Q2 | Layout profiles | (a) stay on each Mac; "Share with Your Other Macs" and file export and import (P1); (b) sync per profile (P2, later, more code); (c) file export and import only (P3) |
| Q3 | The question | (a) the three `sync-1` buttons with a list of the settings; (b) a choice per row |
| Q4 | While a question waits | (a) keep syncing the other settings (the waiting one is never overwritten); (b) pause all publishing (`sync-1` literal) |
| Q5 | The 0.0.7-beta1 file when the new folder is empty | (a) compare with it once at the join; (b) ignore it (a new group starts from this Mac's settings) |
| Q6 | At the join, "no setting of my own" means | (a) the key is absent (a fresh install); (b) absent or equal to its default (needs the defaults table in Core) |
| Q7 | A custom icon over 256 KB | (a) stays on its Mac, with a note; (b) converted once to a 256-pixel PNG at the first launch |
| Q8 | `TitleChangingItemOwners` | (a) stays local (item settings of title-changing apps may not match elsewhere); (b) union (can move items on the receiving Mac) |
| Q9 | At launch while a question waits | (a) apply the settings that do not conflict; (b) apply nothing until the answer |
| Q10 | Files of Macs no longer used | (a) never deleted automatically in this release; (b) deleted when every live Mac has their content and they are 180 days old |
| Q11 | Macs on 0.0.6 or 0.0.7-beta1 in the same folder | (a) a note in Settings and the release notes; (b) the release notes only |

**Departures from earlier decisions, all stated in the questions above:**
- per-setting merge instead of a whole-set question (Q1);
- publishing continues while a question waits (Q4);
- learned keys and flags are local instead of union and OR (§1.2, Q8);
- a re-enabled or cloned Mac with a valid Σ asks only about real conflicts (§5.1, §7.9);
- the hardware hash also binds the user account (§5.1).

---

## 17. Cost, what stays and what goes

### 17.1 New code

| Part | Lines (estimate) |
|---|---|
| Core: unit table, validators, defaults ↔ units mapping | 200 |
| Core: replica, join, capture, plan, apply plan, answers, join preview | 350 |
| Core: device and profile codecs, size checks | 150 |
| Core: identity and counter decisions, legacy input | 100 |
| Glue: file actor (list, read, write, dataless, presenter, watcher, timer), launch path | 400 |
| Glue: hint, sheet rows, status | 200 |
| Profile sharing and file export and import (model and UI) | 300 |
| Tests: properties, simulator, oracles, named scenarios, fuzzing | 1,500 |

### 17.2 Kept from the paused code

- `SettingsSyncFile.readContents`, `isUsableFolder`, `isLocal`;
- `SettingsSyncDevice`, with the hash input extended;
- `SettingsSyncLocation`;
- `SettingsSyncPause` (switched off);
- the bounded launch read (`readForLaunch`);
- the presenter and watcher classes;
- `showSettings` and the sheet plumbing;
- the canonical digest (`SettingsSyncPolicy.digest`);
- `SettingsBackup.apply(_:removesMissingKeys:)` for import (sync applies per unit instead);
- the F-14 run-loop helper.

### 17.3 Companion changes outside the sync engine

1. `HotkeysSettings.loadInitialState`: drop a duplicate at registration only, and do not write the dictionary back. This is the only automatic writer of a synced key with a different value, and it follows F-59's rule.
2. F-59 readers per entry (`ItemIconStore`, `HotkeysSettings`, `LayoutProfiles`, `MenuBarItemGroups`), as audited.
3. `LayoutProfiles.saveCurrentLayout` records only the running generation's part (§4.5).
4. Remove `SettingsSync.userChangedLayout()` and its calls (`SectionRestore`, `Concealer27`, `LayoutProfiles`, the import), and the layout-edit counter.
5. Optional local repair of the `MacOS27LayoutSeeded` artifact on macOS 26 Macs (§9).
6. Strings in five languages (§8.2, §4); `docs/features.md` (sync section rewritten: what syncs, the two groups during updates, profiles shared on demand); `docs/privacy-and-permissions.md` (§12); the release notes; the README and `docs/comparison.md` ("settings sync", no longer "layout sync").

### 17.4 Removed

- `SettingsSyncPolicy`'s `decide`, `Local`, `Version`, `File`, `Action`, `hint(for:)`, layouts, `learnedSettings`, `layoutToTakeIn`, `ownLayoutToTakeIn` and `fileToWrite`;
- the base digests, `pending`, `postponed` and the "pushes paused" logic;
- `currentLayouts`, `copiedLayouts` and `seen`;
- `allowedClockSkew` and `isNewer`;
- `SettingsSyncLastSynced` as evidence (the key stays, untouched);
- the exchange dispatch of `SettingsSync.swift` (`requestExchange`, `handle`, `adopt`, `markSynced`, `finishJoin`), which is replaced by the plan.

**Net effect:** the decision surface shrinks from R6's 2,358-line rule list with 16 persisted keys to:
- one join;
- one capture;
- one five-case plan;
- one answer primitive;
- one Σ file plus two defaults keys (`SettingsSyncGeneration`, and the existing identity keys).

That is the precondition A1 §5.5 names for a design that passes the catalogue by construction instead of by patches.
