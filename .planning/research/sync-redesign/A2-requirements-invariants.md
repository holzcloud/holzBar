# Settings sync redesign: requirements and invariants (A2)

Status: input for the sync redesign phase (discuss, plan, execute, verify). Written 2026-10-07, read-only analysis of the repository at `audit/remediation-2026-10-05` (`a8ba867e`), branch `audit-manual/sync-fix` (`9b0f4bb5`), tag `v0.0.7-beta1`, the audit, the review findings and the maintainer's decisions `sync-1` and `modal-alerts-1`.

This document says **what** sync must do and **which properties** every design must keep. It does not choose a design. Where a property strongly favours one design (for example one file per Mac), that is said as a consequence, not as a decision. Every invariant is written so that a deterministic simulator can check it against a model run: it names the state it reads, the moment it is evaluated, and what counts as a violation.

Conventions: **MUST**, **SHOULD** and **MAY** as in RFC 2119. `R-…` are requirements, `INV-…` invariants, `SC-…` scenarios, `OQ-…` open questions for the maintainer. "N" is a Mac running the redesign; "L1" is a Mac running 0.0.6 or 0.0.7-beta1; "P" is a Mac running 0.0.7-beta2 (sync paused); "L0" is a Mac running 0.0.5 or earlier.

---

## 0. Where sync stands, and why the patches did not converge

- **Released behaviour (L1).** 0.0.6 and 0.0.7-beta1 have byte-identical sync code (`git diff v0.0.6 v0.0.7-beta1` of `SettingsSync.swift`, `SettingsSyncFile.swift`, `SettingsSyncDevice.swift`, `SettingsSyncLocation.swift`, `SettingsBackup.swift` and `Defaults.swift` is empty). Real users run it. Section 2.6 models it exactly.
- **0.0.7-beta2 (P).** Sync is paused (`SettingsSyncPause.isPaused = true`). P never reads, writes, watches or mounts the folder, runs no sync migration, counts no layout edits and writes no version marker. The stored configuration (`SyncsSettingsWithICloud`, the folder bookmark, `SettingsSyncDeviceID`, `SettingsSyncLastSynced`) is left as it was.
- **Paused code on `audit/remediation-2026-10-05`.** It fixes F-02, F-15, F-18, F-38, F-60 and SA-05 with a base digest, a pending version, a layout-edit counter and `currentLayouts`, but it does not run in any release.
- **`audit-manual/sync-fix`.** Six fix-and-review rounds, 58 commits, not merged. Every round found new ways in which a stale layout was written back as current or a user's arrangement was replaced. Some of these came from the previous round's fixes. The confirmed issues fall into eight root causes, and each one maps to a requirement in this document:

| # | Root cause seen in the rounds | Typical confirmed issue | Requirement that removes it |
|---|---|---|---|
| RC1 | One shared, mutable file, written read-modify-write over an eventually consistent folder | "Writing over a missing or unusable sync file silently reverts another Mac's last change" (rounds 3–6) | INV-S3, INV-S6, INV-F6, INV-Z6, R-LIN-4 |
| RC2 | No causal history: wall-clock `modified` dates used as version identity and order | "not newer" versions, clock steps, older own versions brought back (rounds 1–6) | R-LIN-1, R-LIN-2, INV-F5, INV-F9, INV-ID4 |
| RC3 | User and automatic entries mixed inside one layout key | Command-click or a displaced item saved as the user's arrangement (rounds 1–4, SA-05) | INV-A1 … INV-A4 |
| RC4 | The other macOS version's layout carried as a copy inside the shared file (listed, unlisted, kept, copied) | Stale copy of the other macOS layout taken in and re-published as current (round 4 blocker, round 5 blockers) | INV-L1 … INV-L6 |
| RC5 | A missing key read as "delete it" | F-60: the per-OS layout wiped between macOS 26 and 27 | INV-S4, INV-S5 |
| RC6 | L1 peers apply any newer foreign file silently, with remove-missing | SA-05 blocker: a beta 1 same-OS drag overwritten | INV-B1 … INV-B4 |
| RC7 | Negative evidence and heuristics (8, then 64 recent layout digests; "no kept record means old copy") | 64-digest recognition reverts a beta 1 user's deliberate return to an earlier arrangement | R-EVID-1 |
| RC8 | Decisions spread across untested app glue | "Issue 13": the `SettingsSync.swift` glue untested in every round | R-TEST-1, R-TEST-2 |

The pattern behind all eight: when evidence was missing, the code decided toward overwriting. This document requires the opposite (R-EVID-1). It also defines exactly which extra questions that costs, so that "ask only on true conflicts" stays checkable (INV-P1).

---

## 1. Constraints

- **C-1 No network.** holzBar never opens a network connection for sync. Settings travel only through a folder that the user's own sync app provides: iCloud Drive (default), Dropbox, OneDrive, Nextcloud, Syncthing, an SMB or other network share, or any folder. holzBar has no iCloud entitlement (ad hoc signed), so `NSUbiquitousKeyValueStore` and `NSMetadataQuery` ubiquitous scopes are out of reach.
- **C-2 Privacy.** Nothing that identifies the Mac or the person leaves the Mac, except the settings the user chose to sync. Allowed in the folder: settings values, random identifiers, counters, digests and dates. Not allowed: the hardware UUID or anything derived from it, serial numbers, MAC addresses, the computer name, the user name, home or volume paths, bookmark data.
- **C-3 Two layout generations.** Before macOS 27 the arrangement lives in `ItemSections` (item identity key → section index). On macOS 27 it lives in `MacOS27Layout` (bundle ID → section index), plus `MacOS27LayoutSeeded` and `KnownApplications27`. One person's Macs can run macOS 26 and 27 at the same time, and a Mac can move from 26 to 27.
- **C-4 Updates arrive one Mac at a time.** For weeks a folder can be shared by N, P and L1 Macs, in any mix. A Mac can also be downgraded (installing an older release) and upgraded again.
- **C-5 Field versions.**
  - L0 (0.0.5 and earlier) wrote `holzIce/Settings.plist`, identified by the computer name in `device`.
  - L1 (0.0.6, 0.0.7-beta1) writes `holzBar/Settings.plist` (section 2.6).
  - P (0.0.7-beta2) does nothing with the folder.
  - Unreleased development builds (the paused code and the `sync-fix` rounds) may have left `SettingsSyncBase*`, `SettingsSyncLayoutEdits`, `SettingsSyncSyncedLayoutEdits`, `SettingsSyncPendingModified`, `SettingsSyncDeviceSalt`, `SettingsSyncDeviceHash` and file fields `currentLayouts`, `copiedLayouts` and `seen` on developer Macs.
- **C-6 Maintainer policy** (decision `sync-1`, SA-05 "Automatisches nicht mitzählen", `modal-alerts-1`):
  - holzBar asks on real conflicts.
  - It never overwrites or reverts silently.
  - holzBar's own automatic placements are not the user's changes.
  - Per-setting merge was offered and **rejected**: a conflict is decided for the whole set of user settings, not key by key.
  - Sync notices are a quiet hint plus a sheet, never a modal `runModal()` inside a Task.
- **C-7 Code and test constraints.**
  - `swift test` compiles only `holzBar/Core`, `holzBar/MenuBar/MacOS27/Core` and `Shared/CodeSigning`, which are Foundation-only.
  - The app target is compile-checked only by CI.
  - New user-facing strings need en, de (Swiss spelling), fr, it and rm, and `.github/scripts/strings-check.py` must pass.
  - New local keys start with `SettingsSync`, so that `SettingsBackup.excludedKeyPrefixes` keeps them out of export, import and sync. Persisted keys are never renamed.
- **C-8 The pause gap.** P writes no marker, so N cannot tell whether a Mac ran P, or for how long. On a Mac coming from any pre-N build, a layout the user rearranged during the pause looks exactly like one that never changed (remediation log, "Requirement for the redesign").

---

## 2. Reference model (what the simulator implements)

The simulator runs N, L1 and P Macs, a file provider with faults, and a user, all against one global clock that the Macs cannot see. The redesign's decision code (pure Core, R-TEST-1) is plugged into the N Macs. L1 Macs run the model in 2.6. Invariants are predicates over the simulator's ground truth (2.4, 2.5), not over the design's own bookkeeping.

### 2.1 Macs

An installation `m` is one macOS user account on one physical Mac. Its state:

| Field | Meaning |
|---|---|
| `hw(m)` | Hardware identity (IOPlatformUUID). Constant, except that a clone moves its preferences to other hardware. |
| `gen(m) ∈ {g26, g27}` | Layout generation: g26 is every macOS before 27, g27 is macOS 27. Changed only by `UpgradeOS`. |
| `ver(m) ∈ {L0, L1, P, N, N+}` | App version; N+ is a later format the current N does not know. |
| `S_m : Atom → Value ∪ {⊥}` | The settings holzBar uses, restricted to synced atoms (2.3). ⊥ means absent or default. |
| `Σ_m` | Local sync state: every `SettingsSync…` key, the device ID, the salt and the hash, the folder bookmark, the bases, pending versions and the write log. Never synced. |
| `clock(m)` | Global time plus an offset; `ClockStep` can change the offset in either direction. |
| `enabled(m)`, `folder(m)` | The sync configuration. |
| `running(m)` | Whether holzBar is running; `Launch` and `Quit` toggle it. |

### 2.2 Folder and provider

Each Mac sees its own replica `F_m : Path → Entry` of the folder. An entry is one of:

- `Present(bytes)`
- `Dataless(size)`: a placeholder whose content is not on this Mac; reading it starts a download, which can block.
- `Partial(bytes)`: a truncated or in-progress content.
- `Absent`

The provider keeps the global history of all written contents and moves them between replicas with these operations. The simulator applies them under a fault policy (section 6).

| Operation | Effect |
|---|---|
| `Deliver(path, content, m)` | After any delay. It may skip intermediate contents of the same path (coalescing). It may deliver different paths in any order. |
| `ConflictCopy(path, content, m, name)` | A concurrent write to the same path survives as a sibling file with a provider-specific name (6.2), or as an iCloud unresolved `NSFileVersion`. |
| `LWW(path)` | No copy is kept (SMB, some WebDAV): the last write wins and the other content disappears. |
| `Restore(path, old)` | Version history, Time Machine, Syncthing versioning or a stale replica brings back an older content. |
| `Delete(path)`, `DeleteFolder` | Deletion by the user, the provider or another app. |
| `Evict(path, m)` | The content becomes `Dataless` (Optimize Storage, Files On-Demand). |
| `ExposePartial(path, m)` | Readers see `Partial` for a while (non-coordinating providers, SMB). |
| `Stall(m, d)` | Coordinated reads or writes on m block for time d. A hung provider is an infinite d. |
| `Unmount(m)`, `Mount(m)` | The network share disappears or comes back. |
| `Foreign(path, bytes)` | Any app or person puts arbitrary bytes, including symbolic links. The folder is untrusted. |

### 2.3 Atoms, values, provenance

- **Atom.** The unit of comparison and of user change.
  - A scalar key is one atom.
  - For an entry-granular key, every entry `(key, entry)` is an atom. `ItemSections` and `MacOS27Layout` MUST be entry-granular (R-AUTO-2). A design MAY also make `Hotkeys`, `ItemIcons` and `RevealRules` entry-granular; the simulator uses the finest granularity the design claims.
  - JSON-blob keys (`LayoutProfiles`, `ItemGroups`) and data keys (`IceIcon`, `MenuBarAppearanceConfigurationV2`) are one atom each, unless the design splits them.
- **Comparable atoms of m.** `Cmp(m)` is the set of atoms m compares when it decides whether to ask:
  - every OS-independent user atom (classes U, D, PR in section 3);
  - plus the layout atoms of `gen(m)`;
  - not learned keys, flags, the other generation's layout atoms, or local keys.
- **Unique-value instrumentation.** In simulation, every user change writes a fresh token (`u17@ItemSections/com.foo`), every automatic change writes `auto-m2-42`, and defaults are ⊥. The value at any place (a Mac's `S_m`, a file in the folder) then identifies the event that produced it: `origin(x) ∈ {user(u), auto(e), default, pre(m)}`. `pre(m)` marks values that already existed when m first ran N; their provenance is unknown (C-8). Boolean or enum keys are simulated with token-valued stand-ins. Equality collisions of real values are covered by separate equal-value scenarios (SC-12).

### 2.4 Events

| Kind | Events |
|---|---|
| User | `UserEdit(m, {(a, v)})`; `UserDelete(m, a)` (reset to default, remove a hotkey, delete a profile); `UserImport(m, file)`, a user change of every atom it sets and a `UserDelete` of every importable key it removes (file import keeps remove-missing semantics, F-60 fix); `UserApplyProfile(m, p)`; `Answer(m, prompt, choice)` |
| Automatic (holzBar or macOS, never the user) | `AutoPlace(m, a, v)` (new-item placement, first-run save, macOS 27 seeding, new apps on 27, reconciliation, Live Activities, notch overflow, macOS displacing items before 27); `Learn(m, k, element)` (KnownItemTags, KnownApplications27, TitleChangingItemOwners); `SetFlag(m, k)` (hasMigrated…, HasImportedIceSettings, MacOS27LayoutSeeded) |
| Lifecycle | `Launch(m)`, `Quit(m)`, `Enable(m, folder)` (Turn On…), `ChangeFolder(m, folder)`, `Disable(m)`, `UpdateApp(m, ver)` (including downgrades), `UpgradeOS(m)` (g26 → g27) |
| Identity | `Clone(m → m')` (Migration Assistant, disk clone, restore to new hardware: m' gets m's preferences and `Σ_m` on different `hw`); `RestorePrefs(m, snapshot)` (same hardware, older preferences and `Σ`); `CopyAccount(m → m')` (same hardware, another user account) |
| Time | `ClockStep(m, Δ)` |
| Provider | the operations in 2.2 |

Ground-truth classification for the simulator:
- **User-initiated:** Layout pane drags, keyboard moves and undo; Command-drag on the bar; applying a profile from the menu, a hotkey, Shortcuts or `holzbar://`; Import; every control in Settings.
- **Automatic:** everything in the automatic row. Profile applications triggered by a Space or display binding are listed under OQ-6 and simulated both ways.

### 2.5 Causality, ingestion, liveness

- **Happens-before (→).** Program order on each Mac, plus write → ingest edges. A Mac *ingests* a version when it applies, adopts or merges it, decides that it is dominated, or resolves it through an answer. Reading a version without deciding (pending) is **not** ingestion.
- **`Past(V)`.** For every version V written by any Mac: the set of user changes and answers u with u → write(V), through ingest edges only. The simulator computes it from the event trace, whatever V's metadata says.
- **`Past(m, t)`.** The same for Mac m's state at time t.
- **Justified supersession.** A user change u that set atom a is superseded on a by an event x if and only if one of these holds:
  1. x is a user change on a with u → x (a later, informed edit); or
  2. x is an answer whose sheet presented, as the losing alternative, a state containing u's value at a. This holds for "Use Settings from Sync Folder" (losing: the local state) and "Keep This Mac's Settings" (losing: the presented folder version).
- **Liveness of a change.** `live(u, a, t)` holds iff u set a, and no justified supersession of (u, a) happened before t.
- **Global loss.** A live change u is *globally lost* at t if no Mac's `S_m` and no readable version in any replica holds u's value at a, and no pending version on any Mac holds it.
- **Conflict (the policy's definition, snapshot level).** `Conflict(m, V)` holds iff all of the following hold:

  ```text
  ∃ u ∈ Past(m) \ Past(V), live in S_m on some a ∈ Cmp(m)      -- m has a change V lacks
  ∧ ∃ u' ∈ Past(V) \ Past(m), live in V on some a' ∈ Cmp(m)    -- V has a change m lacks
  ∧ S_m|Cmp(m) ≠ V|Cmp(m)                                       -- and the user states differ
  ```

  Learned keys, flags, the other generation's layout and local keys never contribute to a conflict.
- **Dominance.** V is *dominated* for m if `Past(V) ⊆ Past(m)` and V is not newer on any comparable atom. m *dominates-by* V (fast-forward) if `Past(m) ⊆ Past(V)`.
- **Joining.** m is joining while its first decision about the folder is open after any of: `Enable`; `ChangeFolder`; re-identification (INV-ID2); the first launch of N with sync on, coming from any pre-N build or from unreleased-build state (R-COMPAT-5); or loss of `Σ_m`.

### 2.6 Exact model of an L1 peer (0.0.6 and 0.0.7-beta1)

Derived from `v0.0.7-beta1:holzBar/Utilities/SettingsSync.swift`, `SettingsSyncFile.swift`, `SettingsSyncDevice.swift` and `SettingsBackup.swift`:

```text
file path:     <folder>/holzBar/Settings.plist (XML plist)
file content:  { modified: Date(clock(b)), deviceID: Σ_b.SettingsSyncDeviceID, settings: S_b ∩ importable \ local }
               (L0 files carry device: <computer name> instead of deviceID)
local keys:    SyncsSettingsWithICloud, SettingsSyncLastSynced; every key with prefix SettingsSync,
               NSWindow Frame, NSStatusItem Preferred Position, NSStatusItem Visible, SU is excluded

accept(file) := file.size ≤ 1 MiB ∧ regular file ∧ parses
                ∧ (file.deviceID ≠ own id   [or, without deviceID: file.device ≠ computer name])
                ∧ file.modified > SettingsSyncLastSynced
                ∧ file.modified ≤ clock(b) + 1 h

Launch(b) with sync on:
  1. in AppDelegate.init, on the main thread (coordinated read, may block):
       if accept(file): apply(file.settings); SettingsSyncLastSynced := file.modified
     apply(s): for every key b knows as importable and s lacks → removeObject  (remove-missing, F-60)
               set every schema-valid key of s; unknown keys and wrong types are ignored
               HasImportedIceSettings := true
  2. performSetup: isEnabled false→true ⇒ push()                            (F-02 b)
push(): if binary(S_b settings) ≠ lastPushedData (nil after launch):
          write the file with modified := now, without reading it first;
          SettingsSyncLastSynced := now
On any UserDefaults change (user or automatic) while running: push() 5 s later (debounced)
On a presenter or folder event while running: if accept(file): alert "Settings changed on another Mac"
  Restart → apply as in 1, then relaunch;  Later → nothing recorded; the next push overwrites (F-02 c)
Turn On… / Change…: lastPushedData := nil; push() without reading                    (F-02 a)
```

Consequences the redesign cannot change:
- An L1 Mac applies **any** acceptable file silently at its next launch, with remove-missing.
- It overwrites the shared file at every launch, and 5 s after every defaults change, including holzBar's automatic writes.
- It never reads before writing.
- It drops every top-level field and every settings key it does not know.
- It ignores a file over 1 MiB, and a file dated more than 1 h ahead of its clock.

---

## 3. What is synced: key classes

Defaults keys come from `holzBar/Core/Defaults.swift` (`Defaults.Key`, `importableKinds`, `localOnlyKeys`) and `SettingsBackup.excludedKeyPrefixes`. The "Rule" column is a requirement (R-CLASS-*). Where it departs from today's paused code or from a decision, an OQ is noted.

| Class | Keys | Written by | Synced | Merge and conflict rule | Removal rule |
|---|---|---|---|---|---|
| **U** User settings, OS-independent | `ShowIceIcon`, `CustomIceIconIsTemplate`, `UseIceBar`, `IceBarLocation`, `IceBarDisplays`, `ShowsNotchOverflowInIceBar`, `ShowOnClick`, `ShowOnHover`, `ShowOnScroll`, `ShowOnHoverDelay`, `AutoRehide`, `RehideStrategy`, `RehideInterval`, `TempShowInterval`, `ItemSpacingOffset`, `HolzBarIconShowsCaptureDot`, `EnableAlwaysHiddenSection`, `ShowAllSectionsOnUserDrag`, `SectionDividerStyle`, `HideApplicationMenus`, `KeepsDockIconHidden`, `EnableSecondaryContextMenu`, `NewItemsPlacement`, `KeepLiveActivitiesVisible`, `AutoZenWhileSharingScreen`, `OpenHiddenItemsInMenuBar`, `RevealOnChangeItems`, `SpacerCount`, `SpacerWidth`, `RevealRules`, `Hotkeys` | The user (Settings UI) | Yes | Snapshot-level conflict (2.5); comparable on every Mac | Only by an explicit user deletion (INV-S5) |
| **D** User data, large or binary | `IceIcon` (custom icon data, up to 8 MiB raw, stored twice), `MenuBarAppearanceConfigurationV2`, `ItemGroups` (JSON), `ItemIcons` (choice → file name; the PNGs stay local in Application Support/holzBar/ItemIcons) | The user | Yes, within the size budget (R-SIZE) | Like U. A reference to a local file that the receiver lacks falls back (today's `ItemIconChoice`) and is never treated as an error that blocks sync | Like U |
| **LAY** Per-OS layout intent | `ItemSections` (g26), `MacOS27Layout` (g27) | User **and** holzBar, mixed in one dictionary (`saveSections` writes every cached item) | Yes, unless OQ-1 removes them | Entry-granular. Only user-origin entries count (R-AUTO). Compared only between Macs of the same generation. The other generation's layout is never compared, never authored, never reverted (INV-L*) | Never removed by sync; a user removal of an entry is explicit |
| **PR** Profiles | `LayoutProfiles` (JSON; each profile holds `itemSections` and `applicationSections`, so both generations) | The user | Yes | One atom (or per profile, if the design splits it); comparable on every Mac | Explicit deletion only |
| **CTX** Device context | `CurrentLayoutProfile`; a profile application triggered by a Space or display binding | The binding, per Mac | OQ-6 (recommended: local) | Not comparable | n/a |
| **LRN** Learned sets | `KnownItemTags`, `KnownApplications27`, `TitleChangingItemOwners` | holzBar | Yes (decision `sync-1`) | Union; never a conflict, prompt, hint or restart; capped deterministically (INV-K2) | Never removed by sync |
| **FLG** One-time-step flags | `MacOS27LayoutSeeded`, `hasMigrated0_8_0` … `hasMigrated0_11_13_1`, `HasImportedIceSettings` | holzBar | Decision `sync-1`: OR-merge. See INV-K3 and OQ-5 | OR; never a conflict | Never removed |
| **LEG** Ice-era input keys | `MenuBarHasBorder`, `MenuBarBorderColor`, `MenuBarBorderWidth`, `MenuBarHasShadow`, `MenuBarTintKind`, `MenuBarTintColor`, `MenuBarTintGradient`, `MenuBarShapeKind`, `MenuBarFullShapeInfo`, `MenuBarSplitShapeInfo`, `MenuBarAppearanceConfiguration`, `Sections`, `ShowSectionDividers`, `CanToggleAlwaysHiddenSection` (only `Defaults.swift` names them; to be confirmed against `Migration.swift`) | The migration reads them; L1 may still carry them | SHOULD NOT be authored by N; relayed only for L1 safety (INV-B2) | Not comparable | Never removed by sync |
| **TUNE** Device tuning | `MacOS27ClickRestoreDelay`, `MacOS27IceBarWaitsForRefresh` | Developer or user via `defaults` | Today importable; OQ-7 (recommended: local) | Not comparable if local | n/a |
| **LOC** Local, never synced | `SyncsSettingsWithICloud`, `DebugDropsBarrierExitEvent`, `DebugHangsItemImageCapture`, every `SettingsSync…` key, `NSWindow Frame…`, `NSStatusItem Preferred Position…`, `NSStatusItem Visible…`, `SU…`, every key that is not holzBar's | macOS or holzBar | **Never** (INV-S8) | n/a | Sync never touches them |
| **ID** Device identity | `SettingsSyncDeviceID` (random UUID, the only identity in the folder); `SettingsSyncDeviceSalt` and `SettingsSyncDeviceHash` (salted SHA-256 of the hardware UUID, local only) | holzBar | The random ID only, as file metadata, never as a setting | n/a | n/a |
| **META** File metadata | L1: `modified`, `deviceID`, `settings`. Unreleased: `currentLayouts`, `copiedLayouts`, `seen`. N: whatever lineage the design needs (R-LIN) | holzBar | In the folder only | Bounded (INV-Z4); never identifying (INV-PR2) | n/a |
| **FILES** Non-defaults data | ItemIcons PNGs, the macOS 27 item image cache | holzBar | No (OQ-8) | n/a | n/a |

Class rules:

- **R-CLASS-1** Every key in `importableKinds` MUST belong to exactly one class above, and a Core test MUST fail when a new `Defaults.Key` case has no class.
- **R-CLASS-2** A key's class decides how it is compared, merged and removed. No code path may treat a key differently from its class (for example by digesting LRN keys into the conflict digest).
- **R-CLASS-3** The classification MUST be versioned in the format (R-LIN-6), so that a later release can move a key between classes without older N Macs misreading it.

---

## 4. Requirements

### 4.1 Policy (maintainer decisions)

- **R-POL-1 Ask on real conflicts.** holzBar asks when `Conflict(m, V)` holds (2.5), and when a joining Mac finds a version whose comparable user state differs from its own (R-FUN-2). It decides for the whole set of user settings: per-setting merge was rejected (`sync-1`).
- **R-POL-2 Never overwrite or revert silently.** No sync action may replace a live user change on any Mac, or in the folder, without a justified supersession (2.5). This holds for N's own actions in every mix of N, P, L1 and L0 peers, as far as N's actions can cause it (INV-B1).
- **R-POL-3 Automatic is not the user's.** holzBar's own placements and learned keys never count as a change of the user's, never make a Mac ask, never cause a hint or restart on another Mac, and never override a user's choice on another Mac (R-AUTO).
- **R-POL-4 The three answers.** These follow `sync-1` and `modal-alerts-1`.
  - **Use Settings from Sync Folder** applies the presented version's user state with no key removal, then relaunches.
  - **Keep This Mac's Settings** publishes this Mac's user state as superseding exactly the presented version and its past, nothing newer.
  - The third button is **Cancel** when joining: sync stays off, or the previous folder stays chosen, and nothing is written. Otherwise it is **Later**: the version stays pending, this Mac publishes nothing that would supersede it, and the question comes back after the next launch.
  - The sheet has no default button (SA-07).
- **R-POL-5 Launch.** At launch, a newer version is applied silently only if no conflict exists. Otherwise the question comes once setup is done, never in `AppDelegate.init`. While running, a non-conflicting newer version shows the quiet hint with **Restart**. A conflicting one shows **Choose Settings…**, which opens the sheet on the Settings window.
- **R-POL-6 Learned keys.** They are merged silently (union, OR), never asked about. A learned-only remote change is merged at the next launch, with no hint.
- **R-POL-7 Device identity.** The device ID is bound to the Mac by a salted hash of the hardware UUID, stored only locally. The random UUID stays the ID written to the folder (F-38).
- **R-POL-8 No removal on sync.** Sync never removes a local key because the incoming version lacks it. File import keeps remove-missing (F-60).
- **R-POL-9 Existing installs are joining.** A Mac without a base from N joins. Its existing layout counts as edited by the user (C-8, remediation log).

### 4.2 Functional behaviour

- **R-FUN-1 Publish only real changes.**
  - An N Mac publishes when its user state, its learned sets (R-FUN-8) or its lineage obligations (R-LIN-4) changed since its last publication.
  - It never publishes at launch, on `Enable` of an already-synced state, or for automatic placements alone (INV-A1, INV-C2).
  - Publishing is debounced: at most one write per debounce window per Mac.
- **R-FUN-2 Joining.**
  - **Empty folder:** publish, no question.
  - **Folder holds a version whose comparable user state equals this Mac's:** record it as base; no question.
  - **Folder holds a differing version:** ask (R-POL-4, with **Cancel**). Exception (SA-05): differences in layout atoms of `gen(m)` count only if this Mac holds user-origin or `pre`-origin entries there. Otherwise the folder's layout for `gen(m)` is taken in silently, at launch or through the Restart hint.
  - Learned sets and flags are merged and never asked about.
  - **OQ-4:** should a fresh install with only default values also adopt silently?
- **R-FUN-3 Receiving.** For every readable version V that m has not ingested, exactly one of the following happens:
  - **dominated:** ignore it, but merge learned sets;
  - **fast-forward:** apply silently at the next launch, or through the Restart hint, with no removal;
  - **conflict:** ask;
  - **lineage-free difference:** handle it per R-EVID-2.
- **R-FUN-4 Pending.**
  - A version waiting for an answer is persisted locally (bounded, INV-Z4). It survives relaunch, deletion of the folder file, and later arrivals.
  - When a newer version from the same or another Mac arrives, the open question refers to the newest relevant state on the next presentation. An answer given to an older presentation applies only to what it presented (INV-S9).
- **R-FUN-5 Deletion is a change.**
  - A user deletion (`UserDelete`, the removals of `UserImport`, a deleted profile, a removed hotkey) is published as an explicit deletion of that atom.
  - Absence of an atom in a version means "no information" and never deletion (INV-S4, INV-S5).
- **R-FUN-6 Disable and Change folder.**
  - `Disable` stops all folder access. It leaves local settings and the folder untouched, and keeps `Σ_m` so that a later `Enable` of the same folder can recognise its own lineage. Even so, re-enabling is a join (2.5).
  - `ChangeFolder` is a join on the new folder. **Cancel** keeps the previous folder.
- **R-FUN-7 OS upgrade.**
  - After `UpgradeOS(m)`, the seeding of `MacOS27Layout` from `ItemSections` is automatic (no user change).
  - m then joins the g27 group's layout like a joining Mac without layout edits: it takes in the folder's g27 user layout silently if one exists, and asks only if the user edited m's g27 layout before m first synced it.
  - m's `ItemSections` stays in its g26 role: relayed, never reverted (INV-L3).
- **R-FUN-8 Learned propagation.**
  - Learned-set growth MAY be published on its own, at a rate limit (for example at most one learned-only write per Mac per hour). Otherwise it rides on the next publication.
  - It never causes a prompt, hint or restart on a receiver.
  - It never makes an L1 peer apply a full file (if legacy writes exist, R-COMPAT-2).
- **R-FUN-9 Profiles.**
  - Applying a profile by the user is a user change of the layout atoms it changes, and only of those. An unchanged atom is not a change (sync-fix round 1, issue 5).
  - A profile whose layout for `gen(m)` is empty never writes an empty layout (F-03), and never publishes deletions.

### 4.3 Lineage and evidence

- **R-LIN-1** Every version an N Mac writes MUST carry enough causal metadata for any N receiver to decide, without wall-clock time, for each live local change u whether `u ∈ Past(V)`. Typical designs use a version vector or per-device write counters. Its correctness MUST NOT depend on the order, delay, coalescing or duplication of deliveries.
- **R-LIN-2** Version identity MUST be unique even after a Mac's local state is rolled back (`RestorePrefs`) or copied (`Clone`, `CopyAccount`). Examples: a random nonce per write, or detection of a reused (device, counter) with different content (INV-ID3).
- **R-LIN-3** Lineage MUST be honest. A version claims to include a change only if it carries that change's value, or a justified supersession of it (INV-S3).
- **R-LIN-4** When the folder's readable state no longer shows a Mac's latest publication (file deleted, restored to older, lost to LWW, renamed to a conflict copy), that Mac MUST re-publish it, or a dominating state. It needs no question when the re-publication is honest (R-LIN-3), and the re-publication MUST NOT claim to include versions the Mac has not ingested.
- **R-LIN-5** Lineage metadata MUST be bounded (INV-Z4).
  - Pruning a device's entry MUST be safe: a receiver that cannot decide `u ∈ Past(V)` because of pruning treats V as concurrent (ask), never as dominating.
  - Pruning happens only for entries dominated by every live device's latest publication, or older than a stated horizon (OQ-9).
- **R-LIN-6** The format MUST carry a format version and the key-class table version (R-CLASS-3). A reader that sees a newer format MUST NOT rewrite or drop that data (INV-B8).
- **R-EVID-1 Fail safe, positively proved.**
  - A silent apply, silent adoption, silent overwrite or silent discard is allowed only when positive evidence (lineage, R-LIN-1) proves it is a fast-forward or dominated.
  - Missing, unreadable, pruned or lineage-free evidence MUST resolve toward "keep both, ask, or wait", never toward overwriting.
  - Heuristics (digest memories, date comparisons, "looks like an old copy") MAY suppress a question only when they prove equality of content. They MUST NOT permit a silent overwrite.
- **R-EVID-2 Lineage-free versions** (L1 or L0 files, or an N file whose lineage cannot be read):
  - They MAY be applied silently only on atoms where m's current value has `default` or `auto` origin.
  - A difference on an atom where m's value has `user` or `pre` origin is asked about, under the snapshot policy.
  - For each N Mac there is at most one question per distinct comparable content digest of a lineage-free writer (INV-B4).

### 4.4 Automatic versus user changes

- **R-AUTO-1** The sync layer MUST know, per atom, whether the current local value is user-origin, automatic or default. It learns this at the moment of the change, not by comparing digests afterwards. For layouts, the user's action records exactly the entries it changed: a drag, a key move, undo, a Command-drag, a profile or an import. Entries that holzBar or macOS changed (reconciliation, the settle window before macOS 27, displacement, new-item placement, seeding, notch, Live Activities) stay automatic (sync-fix round 4 major).
- **R-AUTO-2** The published layout state of a Mac for `gen(m)` MUST be its user intent: for every entry, the value of the latest live user change it knows, or no entry (or an entry marked automatic, which receivers never let override a user entry).
- **R-AUTO-3** Local automatic overrides of a user entry (for example Live Activities kept visible, or notch overflow) MUST NOT change the published intent of that entry.
- **R-AUTO-4** A user change that sets an entry to the value holzBar had already placed there automatically is still a user change, and the value becomes user-origin. Without this, a confirmed placement could later be overridden by another Mac's automatic value.

### 4.5 Compatibility

- **R-COMPAT-1 Reading L1.** An N Mac MUST read `holzBar/Settings.plist` written by L1 or L0 peers as lineage-free input (R-EVID-2). It MUST tolerate an L1 relaunch rewriting it with unchanged content and a fresh `modified` (INV-B4).
- **R-COMPAT-2 Writing for L1** (decision OQ-2). The default this document recommends is that N never writes `holzBar/Settings.plist`: L1 peers then stop receiving N changes, and N never feeds L1's silent remove-missing apply. A design that does write it MUST satisfy INV-B1 and INV-B2 for every L1 peer modelled in 2.6, and MUST write it only:
  - with a full L1 key set, including both generations' layouts at their latest user intent;
  - never with `modified` beyond the writer's clock;
  - never while a conflict is pending;
  - never with content an L1 peer would read as its own.
- **R-COMPAT-3 L1 must not destroy N data.** N data MUST live where an L1 write cannot overwrite it: a different path, never `holzBar/Settings.plist` alone. A downgrade N → L1 → N loses nothing in the folder; the return to N is a join (INV-B7).
- **R-COMPAT-4 Pause gap** (C-8). On the first N launch after any pre-N build, every existing layout entry has `pre` origin. The first sync asks if the folder's layout for `gen(m)` differs, and never takes it in silently (INV-B5).
- **R-COMPAT-5 Old local state.** N MUST NOT use as a base any sync state written by pre-N builds: `SettingsSyncLastSynced`, and the unreleased `SettingsSyncBase*`, `…LayoutEdits`, `…PendingModified`, `currentLayouts`, `copiedLayouts`, `seen`. The first N run with sync on is a join (R-POL-9). It keeps the folder bookmark. It keeps `SettingsSyncDeviceID`, subject to INV-ID2, except for one change that decision `sync-1` allows: when no hardware hash is stored yet, it MAY rotate the ID once, which also splits Macs that already share a copied ID. The first run is a join anyway, so the rotation is safe.
  - **Deliberate departure from `sync-1`:** that decision keeps `SettingsSyncLastSynced` across the rotation. The redesign MUST NOT use it as evidence of dominance, because of the pause gap (C-8).
- **R-COMPAT-6 L0.** N never reads `holzIce/`, and never writes the `device` (computer name) field.
- **R-COMPAT-7 Forward.** An N Mac that finds a newer format (N+) MUST NOT overwrite or prune it. It keeps its own publications in its own format and shows "update holzBar" (new strings). It never lets a lossy rewrite of N+ data reach other Macs.
- **R-COMPAT-8 P peers.** A P Mac is silent: it neither reads nor writes. The redesign treats it like a Mac that is switched off. When it updates to N, R-COMPAT-4 and R-COMPAT-5 apply.

### 4.6 I/O and responsiveness

- **R-IO-1** No sync file-system call (stat, open, read, write, `createDirectory`, `NSFileCoordinator`, bookmark resolution) runs on the main thread (F-15, F-18).
- **R-IO-2** The launch waits at most 1 s in total for sync. A read that does not finish in time is cancelled, including its file coordinator, and retried once in the background after setup.
- **R-IO-3** A dataless or not-yet-downloaded file (`SF_DATALESS`, `ubiquitousItemDownloadingStatus ≠ .current`) is never read at launch. A background read MAY trigger the download, but no decision may wait on it.
- **R-IO-4** Bookmarks resolve with `.withoutMounting`. holzBar never mounts a share. While the folder is unavailable, sync is idle and Settings shows "The sync folder cannot be found".
- **R-IO-5** holzBar creates only its own subfolder inside an existing, accessible, chosen folder. It never creates the chosen folder or any ancestor: writing under an unmounted `/Volumes/…` path would create a local folder.
- **R-IO-6** Writes are atomic replacements (a coordinated `.forReplacing` write, or a temporary file plus rename in the same folder). Readers validate content (R-SEC-2), because non-coordinating providers can still expose partial content.
- **R-IO-7** Every coordinated read or write has a timeout, and stalls never queue more than one outstanding operation per path.
- **R-IO-8** No `runModal()` inside a main-actor Task (F-14). The sheet and the hint follow `modal-alerts-1`.

### 4.7 Size

- **R-SIZE-1** Every file N writes MUST be at most the smallest read limit of every version that reads that path: 1 MiB for `holzBar/Settings.plist` (L1), and a stated limit `Lmax` for N files (default 1 MiB).
- **R-SIZE-2** When the encoded state exceeds the limit, N MUST NOT write. It MUST keep the previous publication, and show a warning in Settings (F-61; new strings; policy OQ-3). It MAY instead leave out a designated oversized D atom (the custom icon), with a visible note. It must never fail silently.
- **R-SIZE-3** Binary plist SHOULD be used for N files. Data that is stored twice (the icon set) SHOULD be stored once.
- **R-SIZE-4** Learned sets are capped (INV-K2). Collections from the folder are capped on read (F-47: item groups).
- **R-SIZE-5** The number of files N creates in the folder is bounded by a function of the number of live devices (INV-Z5). Stale devices' files are removed only when dominated (R-LIN-5).

### 4.8 Privacy and security

- **R-PRIV-1** No network: holzBar opens no sockets for sync (C-1). CI's privacy check keeps covering this.
- **R-PRIV-2** Folder content written by holzBar contains only settings values, random IDs, counters, digests, dates and format versions (INV-PR2). The salt and the hardware hash never leave `Σ_m`, and are documented in `docs/privacy-and-permissions.md`.
- **R-PRIV-3** Logs mark paths, settings values and IDs as private. Conflict-copy file names, which can contain computer or user names, are never copied into holzBar's files.
- **R-SEC-1** All folder content is untrusted.
  - Only regular files are read, opened with `O_NOFOLLOW`; the holzBar folder is checked with `lstat`.
  - The size is checked before reading.
  - Plists are parsed with type checks.
- **R-SEC-2** Validation works per key and per entry (F-59). A bad entry is skipped and logged. It never empties the whole setting, and the loss is never written back. Numbers are clamped to their rules. A truncated, corrupt or wrong-typed file is "unreadable", never "missing" and never "empty".
- **R-SEC-3** File names that come from synced values (`ItemIcons` choices, group images) MUST be plain names, with no `/`, no `..` and no absolute paths, before holzBar touches the file system with them.
- **R-SEC-4** For any byte sequence in any file of the folder, holzBar neither crashes, nor hangs beyond the bounds of R-IO, nor applies a value outside its schema (fuzzed in R-TEST-4).
- **R-SEC-5** holzBar writes only inside `<folder>/holzBar/` (or the design's own subfolder), and only regular files.

### 4.9 User experience

- **R-UX-1** A non-conflicting change from another Mac: the quiet hint "Settings changed on another Mac" with **Restart**, in Settings → Advanced and at the top of holzBar's menu. No dialog.
- **R-UX-2** A conflict: the hint reads **Choose Settings…** and opens a sheet on the Settings window. The sheet has three buttons (R-POL-4) and no default button. It shows when the folder's version was written, and SHOULD say in plain words what each button keeps and what it discards. Naming the other Mac needs a user-chosen label, because of privacy (OQ-10).
- **R-UX-3** At most one sync sheet at a time. While it is open, holzBar publishes nothing that would supersede the presented version (F-14 consequence 4).
- **R-UX-4** Settings shows the sync status: on, last synced, waiting for an answer, folder not found, file too large (R-SIZE-2), file from a newer holzBar (R-COMPAT-7), and file unreadable.
- **R-UX-5** Every new string exists in en, de (Swiss spelling), fr, it and rm, and `strings-check.py` passes.
- **R-UX-6** Release notes and `docs/features.md` describe the behaviour with L1 Macs in the same folder (R-COMPAT-2) and the first-sync question after the pause (R-COMPAT-4).

### 4.10 Testability

- **R-TEST-1** Every decision (classify, compare, apply, publish, answer, join, re-identify, migrate) lives in pure, Foundation-only Core code. The app glue only does I/O and UI, and has no branches that change outcomes (fixes RC8).
- **R-TEST-2** A deterministic simulator in the test package drives that Core code through section 2's model, and checks every invariant of section 5 after every step.
- **R-TEST-3** Exhaustive small-scope exploration: 2–3 Macs, both generations, at least one L1 peer, up to about 8 events from section 2.4 and the fault operations of 2.2, every interleaving and every answer. Plus seeded random long runs (thousands of steps). A minimised failing trace is printed as a scenario.
- **R-TEST-4** The parser and validator are fuzzed with arbitrary bytes, truncations and type swaps (R-SEC-4).
- **R-TEST-5** Mutation check: removing or inverting any guard in the decision Core MUST make at least one simulator scenario fail (precedent: the `sync-fix` mutation logs).
- **R-TEST-6** Every scenario of section 7 is a named regression test.
- **R-TEST-7** The human two-Mac check stays: same macOS; macOS 26 with 27; one Mac on 0.0.7-beta1; an online-only file at login; joining; a change after Later; an SMB share unmounted.

---

## 5. Invariants

Each invariant gives a statement, a predicate over the model of section 2, **when the simulator evaluates it**, and where it comes from.
- A *sync-caused transition* is a change of `S_m` made by the sync engine (apply, adopt, merge, answer). Changes by the user, or by holzBar's non-sync logic, are not sync-caused.
- `value_u(a)` is the token that u wrote at a.
- `Origin`-based checks use the unique-value instrumentation of 2.3.
- `pre` origin is treated as `user` in every safety invariant (C-8).

### 5.1 Safety of the user's data

**INV-S1 No silent loss.**
- **Statement:** a sync-caused transition never replaces a live user value without a justified supersession.
- **Predicate:** for every sync-caused transition τ on m at t that changes `S_m[a]` from x to y, where `origin(x) = user(u)` (or `pre`) and `live(u, a, t⁻)`, one of these holds:
  - (i) τ executes the answer **Use Settings from Sync Folder** on m, and that sheet presented x as the losing value; or
  - (ii) y comes from a version V with `u ∈ Past(V)`, and some event in `Past(V)` justifies superseding (u, a) (2.5).
- **Check:** on every sync-caused transition, on N and L1 Macs alike. For L1 Macs, the violation is charged to N only when an N write caused it (INV-B1).
- **From:** F-02, F-60, SA-05 and every sync-fix round.

**INV-S1g No global loss.**
- **Statement:** no live user change is globally lost (2.5).
- **Check:** after every step and at the end of the run.
- **From:** F-02 (a): "no copy is left in the folder".

**INV-S2 No silent revert.**
- **Statement:** a sync-caused transition never moves an atom to an older user value.
- **Predicate:** no sync-caused transition changes `S_m[a]` from `value_u(a)` to `value_{u0}(a)` with u0 → u, nor to ⊥ (absent or default) unless an explicit deletion d with u → d is in `Past(V)`. The only exception is case (i) of INV-S1.
- **Check:** on every sync-caused transition. This is a cheaper oracle that INV-S1 implies.
- **From:** "older own version brought back" (round 2), "stale layout written back as current" (rounds 4–5).

**INV-S3 Honest publication.**
- **Statement:** a version carries what it claims to include, and claims nothing it has not ingested.
- **Predicate:** for every version V that an N Mac m writes at t:
  - **(a) Carries what it claims.** For every a that V covers and every u ∈ `Past(V)` live on a at t, V carries one of: `value_u(a)`; the value of a live u' with u → u' on a; or the opposite value, when V is the Keep publication of an answer that presented u as losing.
  - **(b) No over-claim.** `claimedPast(V) ⊆ Past(V)`, where `claimedPast` is the design's own decoder of V's lineage (R-LIN-1), mapped to events.
- **Check:** on every write. The design MUST expose `claimedPast` to the test package.
- **From:** RC1, RC2. Round 3–6 "write over a missing file" lists another Mac's write that it does not carry.

**INV-S4 Absence is not deletion.**
- **Statement:** if V does not mention atom a (absent, as opposed to an explicit deletion), ingesting V leaves `S_m[a]` unchanged.
- **Check:** on every ingestion.
- **From:** F-60. Especially `MacOS27Layout`, `MacOS27LayoutSeeded`, `KnownApplications27` and `ItemSections` between generations, and keys that L1 does not know.

**INV-S5 Deletions are explicit and travel.**
- **Statement:** a `UserDelete(m, a)`, including each removal by `UserImport`, appears as an explicit deletion of a in m's next publication. A receiver treats it exactly like any other user change: fast-forward or asked, never dropped, never applied out of order.
- **Check:** on every write after a `UserDelete`; at the end of a quiescent run, deleted atoms are ⊥ on every agreeing Mac.
- **From:** the consequence of R-POL-8. Without it, Macs never agree after an import.

**INV-S6 No lost update by holzBar's own write.**
- **Statement:** an N Mac never writes over content it has not ingested, unless its write log proves the content is its own.
- **Predicate:** for every write W by an N Mac m to path p, the content C at p in `F_m` just before W is one of:
  - `Absent`;
  - a version m has ingested, or one dominated by `Past(m)`;
  - m's own earlier write, as proved by m's write log, not by its ID alone (INV-ID4).
  - If C is `Dataless`, `Partial`, too large, unreadable or not ingested, there is no write.
- **Additional constraint:** a write over `Absent` MUST satisfy INV-S3.
- **Check:** on every write.
- **From:** SA-05 blocker 2 (a file over 1 MB is overwritten unasked); RC1.

**INV-S7 A pending version is durable.**
- **Statement:** while m has a pending version V (read, in conflict, not answered), V stays available and nothing m publishes supersedes it.
- **Predicate:** until an answer or the ingestion of a version dominating V's user content:
  - (a) V's user content stays available to m across Quit, Launch, `Delete(path)` and newer arrivals;
  - (b) m writes no version whose `claimedPast` includes V, and nothing that supersedes V. Pushes are paused by policy; a design with single-writer files MAY keep publishing m's own state as long as it does not claim V.
- **Check:** after every step while a version is pending.
- **From:** F-02 (c) "after Later"; F-14 consequence 4; round 5 "a waiting version is gone after a relaunch if the file is missing".

**INV-S8 Local keys never travel.**
- **Statement:** no LOC key, no salt and no hardware hash appears in any written file. No sync action changes a LOC key on any Mac, except the sync engine's own `Σ_m` bookkeeping.
- **Check:** on every write (scan the file) and every sync-caused transition.
- **From:** C-2, F-38.

**INV-S9 An answer binds to what the sheet showed.**
- **Statement:** a prompt p on m that presents version `V_p` against local state `L_p` has exactly these effects:

| Answer | Effect |
|---|---|
| Use | `S_m|Cmp(m) := V_p|Cmp(m)`. No removal (INV-S4). Learned sets are merged. The other generation's layout is taken in only if it is not older by lineage (INV-L5). Then relaunch. |
| Keep | The next publication V' has `claimedPast(V') ⊇ Past(V_p) ∪ Past(m)` and carries m's current user state. `claimedPast(V')` includes no version that arrived after p was shown, unless `V_p` dominates it. |
| Later | `S_m` is unchanged; `V_p` stays pending (INV-S7). |
| Cancel | `enabled(m)` and `folder(m)` are as before the join; nothing is written. |

- **Check:** at every answer and at the next write.
- **From:** rounds 1–3, "Keep writes over a version that arrived while the sheet was open, or an unasked version of a third Mac".

### 5.2 Automatic changes are not the user's

**INV-A1 Automatic events are invisible to the conflict machinery.**
- **Statement:** inserting automatic events into a trace changes no prompt, hint or restart, and no user-state publication.
- **Predicate:** take two traces T and T' that are equal except that T' contains additional `AutoPlace`, `Learn` and `SetFlag` events. Then T and T' have the same prompts, hints and restarts on every Mac, and the same sequence of user-state publications. They may differ only in learned-only publications (R-FUN-8) and in entries marked automatic.
- **Check:** metamorphic. The simulator runs each generated trace twice, with and without randomly inserted automatic events.
- **From:** R-POL-3, SA-05.

**INV-A2 Automatic never overrides the user on another Mac.**
- **Statement:** no sync-caused transition on any Mac changes `S_R[a]` from a live user-origin value to an automatic-origin value.
- **Check:** on every sync-caused transition.
- **From:** SA-05, round 4 "displaced items synced as the user's arrangement".

**INV-A3 Published layout intent is the user's.**
- **Statement:** for every version V written by m and every layout atom a of `gen(m)`, V publishes the latest live user change on a that m knows, and never an automatic value as user intent.
- **Predicate:** if some u ∈ `Past(V)` is live on a, then V's user-intent value at a is the value of the →-latest such u. An automatic-origin value is never published as user intent.
- **Check:** on every write.
- **From:** R-AUTO-2 and R-AUTO-3.

**INV-A4 Provenance labels match ground truth.**
- **Statement:** where the design labels an atom user-origin, the ground truth is `user` or `pre`; where it labels it automatic, the ground truth is `auto` or `default`.
- **Check:** after every event, if the design exposes its labels (R-TEST-1 requires it).
- **From:** rounds 1–4: a Command-click without a move, a profile that changed nothing, a first move of an unsaved item.

### 5.3 Per-generation layouts

**INV-L1 Generations are never compared.**
- **Statement:** a prompt on m is never justified only by differences in the other generation's layout atoms, or in learned keys or flags. If `S_m|Cmp(m) = V|Cmp(m)`, there is no prompt.
- **Check:** at every prompt.
- **From:** SA-05; round 1 issues 6 and 11.

**INV-L2 No cross-generation authorship.**
- **Statement:** a Mac with `gen(m) = g` never publishes a new user change to an atom of the other generation. Every value it publishes there has `origin = user(u)` with `gen(mac(u)) = g'` at the time of u, or is not published at all.
- **Check:** on every write.

**INV-L3 The other generation is preserved.**
- **Statement:** a write never replaces or removes another-generation user value that the writer knows is live.
- **Predicate:** for every version V written by m with `gen(m) = g`, every atom a of g' and every u ∈ `Past(V)` live on a: V either carries `value_u(a)` or a later live value, or does not cover a at all. If it does not cover a, INV-S4 protects receivers.
- **Check:** on every write.
- **From:** F-60; the round 4 and 5 blockers (stale copy of the other macOS layout promoted to current).

**INV-L4 Taking in the other generation never reverts.**
- **Statement:** when m takes in another-generation values to relay them or to keep them for a later `UpgradeOS`, it never replaces a value with one that is older by →.
- **Check:** on every sync-caused transition of an other-generation atom.

**INV-L5 Relays follow lineage, not dates.**
- **Statement:** whether a relayed other-generation value is "newer" is decided by `Past`, never by `modified` or a file date.
- **Check:** metamorphic with INV-F9.

**INV-L6 OS upgrade.**
- **Statement:** after `UpgradeOS(m)`, sync never leaves `MacOS27Layout` empty or removes it. If the folder holds g27 user intent, m reaches it, and asks only if the user edited m's g27 layout before m first synced it (R-FUN-7). `MacOS27LayoutSeeded` on m is true only if m seeded, or m holds a non-empty `MacOS27Layout` (INV-K3).
- **Check:** after every step following `UpgradeOS`.
- **From:** F-03, F-60.

### 5.4 Learned keys and flags

**INV-K1 Union, silently.**
- **Statement:** ingesting V merges learned sets by union, and never causes a prompt, hint or restart.
- **Predicate:** for every LRN key k, after ingesting V, `S_m[k] = capmerge(S_m[k]_before, V[k])`. No prompt, hint or restart is caused by LRN or FLG differences.
- **Check:** on every ingestion.

**INV-K2 Bounded, deterministic merge.**
- **Statement:** `capmerge` is commutative, associative and idempotent, and `|S_m[k]| ≤ cap_k` at all times.
- **Check:** property tests on `capmerge`, plus a size check after every step.
- **From:** R-SIZE-4, F-69 and F-75 (unbounded learned data).

**INV-K3 Flags never skip needed work.**
- **Statement:** a flag set by a sync action never claims a one-time step that m neither did nor holds the result of.
- **Predicate:** if a sync action sets FLG f on m, then either m already did f's one-time step, or m holds the state that step would produce:
  - `MacOS27LayoutSeeded ⇒` a non-empty `MacOS27Layout` on a g27 Mac;
  - `HasImportedIceSettings ⇒` m has no un-imported Ice settings it would otherwise import (OQ-5).
- **Check:** after every sync-caused transition and every `UpgradeOS`.
- **From:** decision `sync-1` says "OR the flags". This invariant marks where OR is unsafe (L1 even sets `HasImportedIceSettings` on every apply).

### 5.5 Prompts: ask exactly on true conflicts

**INV-P1 Every prompt has a witness.**
- **Statement:** a prompt on m about version V at t is allowed only if one of these witnesses holds.

| Witness | Condition |
|---|---|
| W1 | `Conflict(m, V)` (2.5) |
| W2 | m is joining, and `S_m` and V differ on `Cmp'(m)`. `Cmp'(m)` is `Cmp(m)` without `gen(m)`'s layout atoms, unless m holds user- or pre-origin entries there (SA-05). |
| W3 | V is lineage-free, and ∃ a ∈ `Cmp(m)` with `V[a] ≠ S_m[a]` and `origin(S_m[a]) ∈ {user, pre}` (R-EVID-2). |
| W4 | V's lineage is undecidable because of pruning (R-LIN-5), and differences exist as in W3. |
| W5 | First N sync after a pre-N build, and the folder's `gen(m)` layout differs from m's `pre` entries (R-COMPAT-4). This is a special case of W2. |

- **Violation:** a prompt without a witness is a false question.
- **Budgets:** W3 and W4 prompts count against INV-B4 and INV-C3.
- **Check:** at every prompt.
- **From:** "ask only on true conflicts"; F-02 (b) ping-pong; round 6 "ask once more than needed".

**INV-P2 Equal means silent.** If `S_m|Cmp(m) = V|Cmp(m)`, there is no prompt and no Restart hint for V, whatever the dates, devices or lineage say. **Check:** at every prompt and hint. **From:** `sync-1` (skip the restart prompt when the user settings are equal).

**INV-P3 No repeated question.** After an answer other than Later to a prompt that presented content digest d from writer w, m presents (w, d) again only if m's comparable state changed since. **Check:** at every prompt.

**INV-P4 Later means after the next launch.** After Later, m presents automatically again only after its next `Launch`, and at most once per launch. Opening **Choose Settings…** by hand is always allowed. **Check:** at every prompt.

**INV-P5 One sheet.** At most one sync sheet is open on m. **Check:** after every step.

**INV-P6 Necessity.** If W1 holds for a readable V on a running m and persists, m presents a prompt within one launch cycle or one background check. It never silently applies V, never silently publishes over V, and never keeps V hidden. **Check:** liveness, at the end of a quiescent run (no unanswered W1 without a hint).

### 5.6 Convergence and quiescence (liveness)

The quiescence assumptions `Q(T0)` hold from time T0 on:

| # | Assumption |
|---|---|
| Q1 | No user events except answers. |
| Q2 | No `UpdateApp`, `UpgradeOS`, `Clone`, `RestorePrefs`, `CopyAccount`, `Enable`, `ChangeFolder`, `Disable` or `ClockStep`; constant clock offsets are allowed. |
| Q3 | The provider delivers every write to every replica within finite time, and every `Dataless` file becomes readable to a background read eventually. Delays, reordering, coalescing, and conflict copies or LWW losses caused by writes after T0 are allowed. No new `Restore`, `Delete`, `Foreign`, permanent `Stall` or `Unmount`. |
| Q4 | Every Mac launches or runs infinitely often, with sync on, on the same folder. |
| Q5 | Every prompt is eventually answered Use or Keep. Later is allowed finitely often, and the choice is adversarial. |
| Q6 | Automatic events may continue, but the universe of learned elements is finite. |

Only N Macs are covered. With OQ-2 = "no legacy writes", L1 Macs are excluded and documented.

**INV-C1 Agreement.**
- **Statement:** under `Q(T0)`, there is a T1 ≥ T0 such that for all t ≥ T1 and every pair of N Macs m, m':
  - `S_m` and `S_m'` agree on every U, D and PR atom;
  - if `gen(m) = gen(m')`, they agree on every user-intent layout entry;
  - they agree on every LRN set.
- **Check:** at the end of every quiescent run, after a drain phase.

**INV-C2 Write quiescence.** Under `Q(T0)`, there is a T1 after which no N Mac writes to the folder. **Check:** at the end of the drain phase, and the number of writes during the drain is bounded.

**INV-C3 Bounded questions.** Under `Q(T0)`, the number of prompts after T0 is at most `B`. The design states B. The reference bound is the number of pairwise-concurrent N user states at T0, plus one per distinct lineage-free content present at T0 per N Mac, plus the number of Later answers. **Check:** at the end of the run.

**INV-C4 No ping-pong.** If a trace has no user events and no automatic events, only `Launch` and `Quit` (any number, any order):
- the number of writes after every Mac has launched once is 0;
- the number of hints and prompts is 0, unless a W-witness already existed at the start.

**Check:** a dedicated scenario family. **From:** F-02 (b).

**INV-C5 Progress.** If u happens on N Mac m at t and `Q(t)` holds, then every other N Mac eventually has `value_u` applied, a pending hint or prompt that presents it, or u superseded. **Check:** at the end of the run.

**INV-C6 The folder agrees too.** After T1, a fresh N Mac with only default values that joins the folder decodes exactly the agreed state of INV-C1. **Check:** append `Enable(fresh)` at the end of quiescent runs.

### 5.7 Device identity

**INV-ID1 Unique after one launch.** For two installations i ≠ j on the same folder, once each has launched since the event that duplicated their preferences (`Clone`, `CopyAccount`, `RestorePrefs` on other hardware), `id(i) ≠ id(j)`. **Check:** after every `Launch`.

**INV-ID2 Stable, and a reset is a join.** `id(m)` changes only on a hardware-hash mismatch, a detected collision (INV-ID3) or an explicit reset. On a change, base, pending and last-synced are cleared, and m is joining. **Check:** after every step. **From:** F-38 and `sync-1` (salted hardware UUID hash).

**INV-ID3 Collision detection.**
- **Statement:** a version that carries m's ID but that m did not write is never treated as m's own.
- **Predicate:** if m reads a version V with writer ID `id(m)` that is not in m's write log (`RestorePrefs` on the same hardware, `CopyAccount`, a bug), m does not treat V as its own. It re-identifies, or treats V as foreign, and never ignores V silently.
- **Check:** at every read. **From:** F-38 (ignoring each other's changes).

**INV-ID4 Own means written by me.** "Own version" is decided by m's write log, not by the ID alone. m never applies its own earlier version as if it came from another Mac. **Check:** at every ingestion. **From:** round 2 "an older version this Mac wrote, brought back by the sync app".

**INV-ID5 Identity stays local.** No written file contains `hw(m)`, the hash, the salt, the computer name or the user name (INV-PR2).

### 5.8 Size and resources

- **INV-Z1** Every written file is at most the limit of its path (R-SIZE-1). **Check:** on every write.
- **INV-Z2** No N reader refuses a file that an N writer of the same format version wrote. **Check:** writer limit ≤ reader limit, in a property test.
- **INV-Z3** When the state is too large: no write, the previous publication is intact, and the warning is visible until the state fits. **Check:** in the oversize scenarios (SC-61).
- **INV-Z4** `|Σ_m|`, the pending storage and the lineage metadata of every version are at most `c1 + c2·D`, where D is the number of devices seen within the horizon (R-LIN-5). **Check:** after every step.
- **INV-Z5** The number of files holzBar created in the folder is at most `c3 + c4·D_live`. **Check:** after every step.
- **INV-Z6** Too large or unreadable is never treated as missing: a present but refused file never leads to a write over it (INV-S6), and never to "joining an empty folder". **Check:** on every write and join. **From:** SA-05 blocker 2.

### 5.9 File-provider realities

- **INV-F1** A partial, truncated, corrupt or wrong-typed file is never ingested, and never read as empty or missing (R-SEC-2). **Check:** on every read.
- **INV-F2 Order independence.** For any permutation of the delivery order of the same set of versions, with the same answers to the same presented contents, the final `S_m` of every Mac is the same, and every safety invariant holds on every path. **Check:** permutation testing of deliveries in small scope.
- **INV-F3** Coalescing (skipped intermediate versions) and duplicate delivery change nothing: ingestion is idempotent, and every version carries the full state plus lineage. **Check:** re-deliver and skip in the fault policy, and compare.
- **INV-F4 Conflict copies.**
  - (a) No safety invariant depends on recognising conflict-copy names.
  - (b) A live user change whose only copy is a conflict copy is either ingested from it as a candidate version, or re-published by its origin Mac (R-LIN-4). INV-S1g covers this.
  - (c) A dominated conflict copy never causes a prompt, a hint or an apply.
  - (d) holzBar deletes a conflict copy only after its content is dominated (OQ-11).
  - **Check:** in the `ConflictCopy` and `LWW` fault scenarios.
- **INV-F5 Restored old versions.** A restored version with lineage that is dominated is never applied and never prompted about. Its writer re-publishes its current state (R-LIN-4). A restored lineage-free (L1) file falls under R-EVID-2 and INV-B4. **Check:** in the `Restore` scenarios.
- **INV-F6 Deletion.** `Delete` or `DeleteFolder` never causes a local deletion or reset on any Mac. Every later publication satisfies INV-S3. **Check:** in the `Delete` scenarios.
- **INV-F7 Dataless, stalls and unmounted shares.**
  - No main-thread sync I/O (INV-R1).
  - Launch delay ≤ 1 s (INV-R2).
  - Nothing is mounted (INV-R3).
  - No write happens while the folder is unavailable or under `/Volumes` without the share (R-IO-5).
  - **Check:** in the `Stall`, `Evict` and `Unmount` scenarios.
- **INV-F8 Atomic replacement.** A reader of a coordinating provider never sees a partial N write. For non-coordinating providers, INV-F1 covers it.
- **INV-F9 Clock independence.** For traces that differ only in clock offsets and `ClockStep`s, every decision is identical: apply, ask, ignore, the content and lineage of publications, and the set of pending versions. Only displayed dates and L1-facing `modified` values may differ. **Check:** metamorphic, by re-running each trace with randomised clocks. **From:** round 6 "clock set back"; L1's 1 h future window.
- **INV-F10** The same version ingested twice has no further effect (part of INV-F3).

### 5.10 Compatibility with L1, P, L0 and N+ peers

- **INV-B1 L1 peers lose nothing through N.**
  - For every L1 Mac b and every N-written file that b applies (b's `accept` in 2.6), INV-S1 and INV-S4 hold at b. No key b holds is removed, and no live user value on b is replaced without justification.
  - This holds trivially if N never writes `holzBar/Settings.plist` (R-COMPAT-2).
  - **Check:** on every L1 apply of an N-written file.
- **INV-B2 L1 key completeness.** This applies only if N writes the L1 path. Its `settings` contain every L1-importable key that any peer in the folder could hold, at the latest user intent N knows. That includes both layout keys, the learned keys, the flags and the LEG keys that N relays. **Check:** on every L1-path write.
- **INV-B3 L1 input is handled conservatively.** An L1 version never changes a user- or pre-origin value on an N Mac without an answer (R-EVID-2, INV-S1). **Check:** on every ingestion of a lineage-free version.
- **INV-B4 L1 question budget.** Per N Mac, at most one prompt per distinct pair (L1 writer ID, comparable content digest). An L1 relaunch write with unchanged comparable content causes no prompt and no hint. **Check:** a scenario family with L1 Macs that relaunch 10 to 100 times.
- **INV-B5 Pause gap.** On the first N run after any pre-N build, no `pre`-origin layout entry is replaced without an answer. If the folder's `gen(m)` layout differs, m asks. **Check:** the migration scenarios (SC-44).
- **INV-B6 Old state is not a base.** No decision of a Mac's first N run uses `SettingsSyncLastSynced` or unreleased-build state as evidence of dominance. **Check:** the migration scenarios.
- **INV-B7 Downgrade.** After N → L1 → N on one Mac, no N-format data in the folder was overwritten by the L1 run, and the return to N is a join. **Check:** the downgrade scenarios.
- **INV-B8 Newer formats survive.** An N Mac never rewrites, prunes or drops N+ data, and shows the "update holzBar" status. **Check:** the N+ scenarios.
- **INV-B9 L0.** N never writes the `device` field and never touches `holzIce/`. **Check:** on every write.

### 5.11 Responsiveness, privacy, security

- **INV-R1** No sync file-system call runs on the main actor or main thread. **Check:** every I/O call in the model is tagged with its executor, and the app glue is checked by a CI lint, for example forbidding `NSFileCoordinator` and `FileManager` in main-actor sync code.
- **INV-R2** The time from `Launch` to "setup done" that sync adds is ≤ 1 s, for any `Stall`, `Dataless` or `Unmount`. **Check:** the launch scenarios with infinite stalls.
- **INV-R3** No bookmark resolution mounts anything (`.withoutMounting`). **Check:** the model records mount attempts.
- **INV-PR1** No network use (C-1). **Check:** CI's privacy check, plus no networking API in the sync code.
- **INV-PR2 No identifiers leave the Mac.** The simulator plants marker strings for `hw(m)`, the computer name, the user name and the home path in each Mac model. It then scans every written byte for them, for their SHA-256 with and without the salt, and for the salt. Any hit is a violation. **Check:** on every write.
- **INV-SEC1** For fuzzed folder content (R-TEST-4), no crash, no hang beyond the R-IO bounds, no out-of-schema value in `S_m`, no file-system access outside the folder through a synced name (R-SEC-3), and no symbolic link followed. **Check:** the fuzz runs.

---

## 6. File-provider fault model

### 6.1 Facts every design must accept

- **No cross-Mac locking exists.** `NSFileCoordinator` coordinates processes on one Mac (and iCloud's daemon on it), not Macs with each other. "Read before write" narrows the window, but can never exclude a concurrent write by another Mac. Concurrency MUST be handled by the data design (lineage, and preferably single-writer files), never by locking.
- **Delivery is eventual, unordered and lossy in its intermediate states.** A Mac can be offline for weeks. Different files arrive in any order. Intermediate contents of one file can be skipped.
- **The folder is shared with the user and other apps.** Files can be deleted, restored, duplicated, renamed or replaced at any time, including by symbolic links.
- **Content may be absent locally.** On macOS 14 and later, iCloud Drive, Dropbox, OneDrive, Google Drive and Nextcloud (virtual files) present not-yet-downloaded files as dataless (`SF_DATALESS`). Reading one starts a download that blocks the reader.
- **Network shares** have no conflict copies (last writer wins). They can expose partial content while a non-atomic writer writes, and they disappear when unmounted.

### 6.2 Provider behaviours to simulate

Conflict-copy names are illustrative. Safety MUST NOT depend on them (INV-F4).

| Provider | Dataless | Concurrent write to one path | Other behaviour |
|---|---|---|---|
| iCloud Drive | yes (`ubiquitousItemDownloadingStatus`) | `Settings 2.plist`, or an unresolved `NSFileVersion` | Version history restore; eviction under Optimize Storage |
| Dropbox | yes (File Provider) | `Settings (<name>'s conflicted copy <date>).plist` | Version history restore |
| OneDrive | yes (Files On-Demand) | `Settings-<ComputerName>.plist` (puts the computer name in the folder: never propagate it, R-PRIV-3) | Restore |
| Nextcloud | optional (virtual files) | `Settings (conflicted copy <date> <time>).plist` | Restore |
| Syncthing | no | `Settings.sync-conflict-<date>-<time>-<id>.plist` | Temporary `.syncthing.*.tmp` files; versioning restore; "revert local changes" rolls a replica back |
| Google Drive | yes | `Settings (1).plist` | Restore |
| SMB / AFP / NFS / WebDAV | no | Last writer wins, no copy | Partial reads; `Unmount`; long stalls |

### 6.3 Fault-policy parameters for the simulator

- **Delay:** 0 up to "never during the run", heavy-tailed, plus offline periods during which a Mac neither sends nor receives.
- **Delivery:** reordering across paths; coalescing per path; duplicate delivery.
- **Concurrent writes:** for two writes to one path within a window w, a `ConflictCopy` with probability p_c, otherwise `LWW`.
- **Other faults:** `Restore` of any earlier content; `Delete` of a file or of the whole folder; `Evict`; `ExposePartial`; `Stall` (finite or infinite); `Unmount`; `Foreign` bytes, including symbolic links, over 1 MiB, truncated plists and wrong types.
- **Clocks:** offsets of ±7 days, and steps of ±1 day at any time.
- **Presets:**
  - "iCloud": dataless, NSFileVersion conflicts, restores.
  - "Syncthing": no dataless, sync-conflict copies, temporary files, rollback.
  - "SMB": LWW, partial reads, unmount, stalls.
  - "Hostile": everything, including Foreign.

---

## 7. Scenario catalogue (regression tests and simulator seeds)

The notation is setup → steps → expected outcome [invariants]. "A", "B" and "C" are Macs; the subscript gives the generation, and the version is N unless stated.

**Joining and identity**

| ID | Scenario |
|---|---|
| SC-01 | Empty folder → A joins → A publishes; no prompt [INV-P1, INV-S3] |
| SC-02 | Folder holds B's state, equal to A's → A joins → no prompt, base recorded, no hint on B [INV-P2, INV-C4] |
| SC-03 | B configured for weeks; A fresh with some user changes → A joins → A asks with **Cancel**. Cancel: nothing written, sync off on A. Use: A = B, no key removed. Keep: B later fast-forwards to A, by the user's explicit choice [INV-S9, INV-S1, INV-S4] |
| SC-04 | A fresh, only automatic layout; B has a user layout of the same generation → A joins → A's layout becomes B's silently; other differences per R-FUN-2 [INV-A1, INV-P1 W2] |
| SC-05 | `Clone(A → A')` with Migration Assistant → A' launches → new ID, joins; A and A' then see each other's changes [INV-ID1, INV-ID2] |
| SC-06 | `RestorePrefs(A)` to a 2-week-old snapshot (same hardware) → A launches and finds versions under its ID that are not in its write log → collision handling; no silent revert of B; nothing ignored [INV-ID3, INV-S2] |
| SC-07 | Two user accounts on one Mac, same folder → distinct IDs; normal sync [INV-ID1] |
| SC-08 | `ChangeFolder` to a folder holding another set → join on the new folder; Cancel keeps the old folder (SA-06) [INV-S9] |

**Steady state**

| ID | Scenario |
|---|---|
| SC-10 | A changes X; B is running → B shows the Restart hint; X applied at B's next launch; no prompt [INV-P1, INV-C5] |
| SC-11 | A changes X and B changes Y concurrently → both see `Conflict` → prompt. After B answers Use, A sees no further prompt [INV-P1 W1, INV-C3] |
| SC-12 | A and B set X to the same value concurrently → no prompt [INV-P2] |
| SC-13 | A and B relaunch 100 times, alternating, with no changes → 0 writes, 0 hints [INV-C4] |
| SC-14 | B answers Later; B edits locally; A changes again → B publishes nothing that supersedes A's version; after B's relaunch the question shows A's newest; nothing lost [INV-S7, INV-P4, INV-S1g] |
| SC-15 | C writes while B's sheet about A's version is open; B answers Keep → B's publication does not claim C's version; C's version is decided afterwards [INV-S9, INV-S3] |
| SC-16 | A deletes a hotkey → B removes it (fast-forward); B's other keys are untouched [INV-S5, INV-S4] |
| SC-17 | A imports a file that lacks Hotkeys (remove-missing) → the deletion travels to B as a user deletion [INV-S5] |

**Automatic versus user**

| ID | Scenario |
|---|---|
| SC-20 | A new item appears on A and holzBar places it → no write of its own, no hint or prompt anywhere [INV-A1, INV-C4] |
| SC-21 | B's user put X in Hidden; A's holzBar placed X in Visible automatically; A's user drags Y → B keeps X in Hidden, and Y moves [INV-A2, INV-A3] |
| SC-22 | Before macOS 27, macOS displaces items during the settle window, then the user Command-drags one item → only the dragged entry is a user change (round 4 major) [INV-A4, INV-A3] |
| SC-23 | Live Activities or notch reconciliation moves a user-placed item on A → nothing published; B unchanged [INV-A1, R-AUTO-3] |
| SC-24 | A learns tag T and B learns U → both end with {T, U}; no prompt; at most rate-limited writes [INV-K1, INV-K2, INV-C2] |
| SC-25 | A Command-click without a move, or a profile that changes nothing → no user change [INV-A4] |

**Generations**

| ID | Scenario |
|---|---|
| SC-30 | A₂₆ and B₂₇ with equal settings → no prompt; each keeps its own layout [INV-L1] |
| SC-31 | A₂₆ edits `ItemSections` → B₂₇ gets no hint, prompt or restart for it; it may relay [INV-L1, INV-K1] |
| SC-32 | B₂₇ edits `MacOS27Layout`; C₂₇ receives it; A₂₆ writes many times → A never reverts or removes B's g27 intent [INV-L3, INV-L2] |
| SC-33 | `UpgradeOS(A)` while B₂₇ holds a user layout → A seeds automatically, then takes in B's g27 layout silently; no prompt [INV-L6, INV-A1] |
| SC-34 | F-60: a g27 Mac reads a file written only by a g26 Mac → `MacOS27Layout`, `MacOS27LayoutSeeded` and `KnownApplications27` are kept [INV-S4] |
| SC-35 | A profile saved on 26 is applied on 27 → no empty layout and no deletions published (F-03) [INV-L6, R-FUN-9] |
| SC-36 | Round 4 and 5 blockers: an old own version or a not-newer version carries a stale g26 layout and reaches A₂₇ → A₂₇ never re-publishes it as current; B₂₆ never applies it silently [INV-L4, INV-S3, INV-S2] |

**L1, P and N+ peers**

| ID | Scenario |
|---|---|
| SC-40 | A (N) and B (L1): B launches and rewrites `Settings.plist` → A: equal → nothing; different on user-origin atoms → one prompt; different only on default or automatic atoms → silent [R-EVID-2, INV-B3, INV-B4] |
| SC-41 | B (L1) relaunches 50 times with unchanged content → at most one prompt on A [INV-B4] |
| SC-42 | A (N, g26) and B (L1, g27) → B never loses `MacOS27Layout` because of A [INV-B1, INV-B2] |
| SC-43 | SA-05 blocker 1: B (L1, g27) drags; A (N, g27) has an older layout → A never overwrites B's drag silently, and B never applies A's older layout because of A [INV-B1, INV-S1] |
| SC-44 | The pause gap: A synced under beta 1, rearranged under beta 2 (P), updates to N, and the folder's layout differs → A asks [INV-B5, INV-B6] |
| SC-45 | A downgrades N → L1 (launch and push) → N → no N data lost; A joins [INV-B7] |
| SC-46 | An N+ file is present → A does not rewrite or prune it, and shows "update holzBar" [INV-B8] |
| SC-47 | An L0-style file with only `device` → lineage-free; N never writes `device` [INV-B9, INV-PR2] |

**File-provider realities**

| ID | Scenario |
|---|---|
| SC-50 | Dataless file at login → launch delay ≤ 1 s; background read later; then hint or prompt [INV-R2, INV-F7] |
| SC-51 | Hung provider (infinite `Stall`) → launch bounded; UI responsive; no write over the unread file [INV-R1, INV-S6] |
| SC-52 | Truncated plist (`ExposePartial`) → "unreadable", not missing; retried; no write over it [INV-F1, INV-Z6] |
| SC-53 | A and B write concurrently; the provider keeps A's in `Settings (conflicted copy).plist` → A's change is not globally lost; a dominated copy causes nothing [INV-F4, INV-S1g] |
| SC-54 | iCloud unresolved `NSFileVersion` instead of a sibling file → as SC-53 |
| SC-55 | `Restore` brings back a 3-week-old file → no apply, no prompt (lineage); the writer re-publishes [INV-F5, R-LIN-4] |
| SC-56 | `Delete` of the file, or of the whole folder → no local deletion; the next publications are honest; no revert of another Mac's last change (rounds 3–6) [INV-F6, INV-S3] |
| SC-57 | B is offline for 14 days with edits; A edits too; B comes back → exactly one conflict question pair; nothing lost [INV-P1 W1, INV-S1g] |
| SC-58 | A writes V1 then V2; C receives V2 before V1 → C ends at V2 and never reverts to V1 [INV-F2, INV-S2] |
| SC-59 | A's clock +3 h, B's clock −1 day, A steps back 2 h → decisions identical to the same trace with correct clocks [INV-F9] |
| SC-60 | SMB share unmounted → nothing mounted; nothing written under `/Volumes`; status "cannot be found"; resumes after `Mount` [INV-R3, INV-F7] |
| SC-61 | F-61: the state exceeds 1 MiB (a large Ice icon) → no write, warning shown, previous publication intact; other Macs keep the last good state; nobody overwrites the big file as "unusable" (SA-05 blocker 2) [INV-Z1, INV-Z3, INV-Z6] |
| SC-62 | F-59: one bad entry in `MacOS27Layout` or `Hotkeys` in the folder → the entry is skipped, the rest applied, nothing emptied, nothing written back [R-SEC-2, INV-SEC1] |
| SC-63 | A symbolic link planted as the file or the folder → refused [INV-SEC1] |
| SC-64 | SMB LWW: A's and B's concurrent writes, B's write lost → B sees that its publication is missing and re-publishes honestly; one W1 prompt if the states are concurrent [R-LIN-4, INV-S1g] |
| SC-65 | Syncthing rolls A's replica back to an old state of A's own file → A recognises it as its own older write and re-publishes; no prompt [INV-ID4, R-LIN-4] |

**Convergence**

| ID | Scenario |
|---|---|
| SC-70 | Three Macs (two g27, one g26, one of them L1 in a variant), 200 random steps, then `Q(T0)` and a drain → INV-C1, INV-C2, INV-C3, INV-C5 and INV-C6 hold |
| SC-71 | INV-A1 metamorphic pair of SC-70 (with and without automatic events) and INV-F9 metamorphic pair (random clocks) |

---

## 8. Simulator design notes

- **Ground truth is the simulator's own.** It keeps vector clocks over its own event trace to compute `Past`, `live`, `Conflict` and origins. It never trusts the design's metadata, which is checked against ground truth through `claimedPast` (INV-S3 b).
- **Pluggable Macs.**
  - N Macs run the real Core decision code (R-TEST-1) behind a thin adapter. The adapter provides the folder replica, `Σ_m`, `S_m`, and the hint and sheet events.
  - L1 Macs run section 2.6 literally, including remove-missing, `HasImportedIceSettings := true`, the push at every launch, and the 1 MiB and +1 h rules.
  - P Macs are inert towards the folder, but their users still edit settings, which feeds the pause gap.
- **Adversarial user.** Answers are chosen by the explorer (every choice in exhaustive mode). Later is bounded per run, so that `Q5` can hold.
- **Oracles.** Safety invariants run after every step, liveness invariants after a drain phase, and metamorphic invariants (INV-A1, INV-F2, INV-F9) as paired runs.
- **Exploration.**
  - Exhaustive small scope (2–3 Macs, about 8 events, all interleavings and answers).
  - Seeded random runs with the presets of 6.3.
  - Every failure is minimised to the shortest trace and printed in the SC notation, ready to become a regression test.
- **Mutation gate (R-TEST-5).** Run the simulator on every guard mutation of the decision core. A surviving mutant is either a missing scenario or a dead guard, and must be resolved before merge.

---

## 9. Open questions for the maintainer

| ID | Question | Why it matters | Default this document assumes |
|---|---|---|---|
| OQ-1 | Keep syncing the menu bar arrangement (`ItemSections`, `MacOS27Layout`)? | Offered on 2026-10-06; the maintainer chose to pause first. Not syncing it removes INV-L*, most of R-AUTO, and the pause-gap question; profiles and every other setting still sync. L1 peers keep sending layouts, which N then ignores. | Undecided. Every invariant is written to hold in both variants. |
| OQ-2 | Write `holzBar/Settings.plist` for L1 peers? | Writing it feeds L1's silent remove-missing apply (INV-B1, INV-B2); not writing it means L1 Macs stop receiving changes from N Macs. | No legacy writes. Read L1 files as lineage-free input. Release notes ask users to update every Mac. |
| OQ-3 | F-61 size policy | Warning strings are needed. | Refuse and warn; optionally leave out the custom icon with a note; convert Ice icons once. |
| OQ-4 | Should a fresh install (defaults only, or automatic values only) joining a folder adopt it silently? | `sync-1` asks whenever user settings differ; with no user-origin values nothing can be lost. | Ask, as decided. Silent adoption is a candidate simplification. |
| OQ-5 | Should FLG flags be OR-merged (`sync-1`) or kept local? | OR can skip a step this Mac still needs (`MacOS27LayoutSeeded`, `HasImportedIceSettings`; INV-K3). | Local, or OR only together with the state the step produced. |
| OQ-6 | Is `CurrentLayoutProfile`, and a profile applied by a Space or display binding, device context or a user change? | Synced, one Mac's Space switch changes the other Mac's layout. | Local context; binding applications are automatic. |
| OQ-7 | Should `MacOS27ClickRestoreDelay` and `MacOS27IceBarWaitsForRefresh` be local? | They are device tuning, not preferences. | Local. |
| OQ-8 | Sync the ItemIcons images? | Today only the choice syncs, and the image falls back on other Macs. | Keep local with fallback. |
| OQ-9 | Lineage pruning horizon and device garbage collection | Needed to bound metadata (INV-Z4). | 180 days and dominated entries only; ask when pruning makes a decision undecidable. |
| OQ-10 | A device label in the sheet? | Privacy (C-2). | Dates only. A user-chosen label is optional and would be stored in the folder. |
| OQ-11 | May holzBar delete dominated conflict copies of its own files? | It keeps the folder tidy, but deleting is a risk. | Only dominated copies, and only of files holzBar wrote. |
| OQ-12 | Conflict granularity for D and PR keys (whole key or per profile)? | Finer granularity means fewer questions, but merging is not the policy. | Whole key, snapshot policy. |
| OQ-13 | Should a Mac keep publishing its own state while a question is pending? | `sync-1` says pushes stay paused; single-writer designs could publish without claiming the pending version (INV-S7 b). | Paused, as decided. |
| OQ-14 | What does Turn Off keep? | Keeping `Σ_m` lets a re-enable recognise its own lineage. | Keep `Σ_m`; re-enabling is still a join. |

---

## 10. Traceability

| Source | Requirement or invariant |
|---|---|
| F-02 (a) joining overwrites the folder | R-FUN-2, R-POL-4, INV-S1, INV-S1g, INV-P1 W2, SC-03 |
| F-02 (b) push at every launch, ping-pong | R-FUN-1, INV-C4, INV-P2, SC-13 |
| F-02 (c) after Later | R-FUN-4, INV-S7, INV-P4, SC-14 |
| F-03 empty profile layout on 27 | R-FUN-9, INV-L6, SC-35 |
| F-14 modal alerts | R-IO-8, R-UX-1 … R-UX-3 |
| F-15 main-thread I/O, dataless | R-IO-1 … R-IO-3, INV-R1, INV-R2, SC-50, SC-51 |
| F-18 mounting | R-IO-4, INV-R3, SC-60 |
| F-38 copied device ID | R-POL-7, INV-ID1 … INV-ID4, SC-05 … SC-07 |
| F-47 uncapped groups | R-SIZE-4, R-SEC-1 |
| F-59 one bad entry | R-SEC-2, INV-SEC1, SC-62 |
| F-60 removal of missing keys | R-POL-8, INV-S4, INV-L3, SC-34 |
| F-61 sync file over 1 MiB | R-SIZE-1 … R-SIZE-3, INV-Z1, INV-Z3, SC-61 |
| SA-05 automatic placements | R-AUTO-1 … R-AUTO-4, INV-A1 … INV-A4, INV-L1, SC-20 … SC-25 |
| SA-05 review: beta 1 drag overwritten (blocker) | INV-B1, SC-43 |
| SA-05 review: a file over 1 MB counts as unusable (blocker) | INV-S6, INV-Z6, SC-61 |
| SA-05 review: Keep writes an unchanged layout over a newer one | INV-S9, INV-A3 |
| SA-06 never drop a chosen folder without asking | R-FUN-6, SC-08 |
| SA-07 no default button | R-POL-4, R-UX-2 |
| sync-fix rounds 1–3: Keep over unasked or newer versions | INV-S9, SC-15 |
| sync-fix rounds 2–5: older own versions, stale copies, the other generation's copies | INV-ID4, INV-L3, INV-L4, INV-S3, SC-36, SC-55, SC-65 |
| sync-fix rounds 3–6: writes over a missing or unusable file | INV-S3, INV-S6, INV-F6, R-LIN-4, SC-56 |
| sync-fix round 4: displaced items, first move | R-AUTO-1, INV-A4, SC-22 |
| sync-fix round 4: 64-digest recognition | R-EVID-1 |
| sync-fix round 6: clock set back | INV-F9, SC-59 |
| sync-fix Issue 13: untested glue | R-TEST-1, R-TEST-2 |
| Pause gap (remediation log) | R-COMPAT-4, INV-B5, SC-44 |
| 0.0.7-beta1 in the field | 2.6, R-COMPAT-1 … R-COMPAT-3, INV-B1 … INV-B4, SC-40 … SC-43 |
