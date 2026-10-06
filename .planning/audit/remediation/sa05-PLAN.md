---
phase: audit-remediation-sa05
plan: sa05
type: execute
wave: 1
depends_on: []
files_modified:
  - holzBar/Core/SettingsSyncPolicy.swift
  - holzBar/Core/SettingsSyncFile.swift
  - holzBar/Utilities/SettingsSync.swift
  - holzBar/Utilities/SettingsBackup.swift
  - holzBar/MenuBar/MenuBarItems/SectionRestore.swift
  - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
  - holzBar/MenuBar/MacOS27/Concealer27.swift
  - holzBar/MenuBar/Profiles/LayoutProfiles.swift
  - Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift
  - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
  - docs/release-notes/v0.0.7-beta2.md
  - docs/features.md
  - .planning/audit/REMEDIATION-2026-10-05.md
  - .planning/audit/remediation/sa05-SUMMARY.md
  - .planning/audit/remediation/sa05-PLAN.md
autonomous: true
requirements: [SA-05]

estimate:
  tokens: 200000
  raw_tokens: 200000
  tasks: 3
  confidence: low

must_haves:
  truths:
    - "A macOS 26 Mac and a macOS 27 Mac whose settings are equal apart from their layouts never get the question 'Which settings should holzBar use?' when one joins (Turn On…, Change…, a rejoin after the update or after re-identification), in both orders (D-06, D-09)"
    - "holzBar's own layout writes (new-item placement and the first-run save before macOS 27, new-app placement and seeding on macOS 27) write nothing to the sync file, keep the quiet hint at 'Restart' and show nothing on another Mac (D-04, D-05, D-07)"
    - "User layout changes (Layout pane drag, keys and undo, Command-drag, applying a profile, importing settings) still push, turn 'Restart' into 'Choose Settings…' and count when joining (D-08)"
    - "This Mac never writes its own copy of the other macOS version's layout key into the sync file: it keeps the file's value, or leaves the key out when the file has none; it takes the file's value in silently when it adopts or applies a version (D-01, D-02, D-03)"
    - "Layout keys in sync files written by earlier builds are neither compared nor applied nor taken in, so an older copy cannot replace a layout (D-02, A-01)"
    - "Applying another Mac's version keeps this Mac's layout when that version did not change it, and otherwise keeps this Mac's entries for items that version has never seen (A-02)"
    - "Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift is unchanged and passes; the new Core tests cover both directions (macOS 26 Mac, macOS 27 Mac), automatic versus user changes and joining (C-02, C-03)"
  artifacts:
    - path: holzBar/Core/SettingsSyncPolicy.swift
      provides: "Per-macOS layout keys (Layouts), user digest without layouts, layout digest, holdsLocalSettings and changedNothingSinceBase, the new decision rows, apply/write/take-in rules with the layout merge, the layout-edit counter rules"
    - path: holzBar/Core/SettingsSyncFile.swift
      provides: "currentLayoutsKey and Contents.currentLayouts"
    - path: holzBar/Utilities/SettingsSync.swift
      provides: "New base keys and migration, makeLocal, layout-aware inspect/write/apply/adopt, userChangedLayout()"
    - path: Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift
      provides: "Swift Testing suite 'SettingsSyncPolicy layouts', parameterized over the macOS 26 and macOS 27 backend"
  key_links:
    - from: "SectionRestore (user saves, profile), Concealer27.setSection, LayoutProfiles.apply (macOS 27), SettingsBackup.importFromFile"
      to: "SettingsSync.userChangedLayout()"
      via: "increments SettingsSyncLayoutEdits in the same main-actor step as the layout write"
    - from: "SettingsSync.makeLocal"
      to: "SettingsSyncPolicy.Local.editsLayout"
      via: "SettingsSyncPolicy.editsLayout(count:synced:) over SettingsSyncLayoutEdits and SettingsSyncSyncedLayoutEdits"
    - from: "SettingsSync.inspect"
      to: "SettingsSyncPolicy.Version.layoutDigest"
      via: "SettingsSyncPolicy.withoutStaleLayouts(_:currentLayouts:) on the file's settings"
    - from: "SettingsSync.write"
      to: "SettingsSyncFile.currentLayoutsKey in the written file"
      via: "SettingsSyncPolicy.fileToWrite(_:file:fileCurrentLayouts:layouts:keepsOwnLayout:)"
---

# Remediation plan: SA-05 — holzBar's own layout placements and the other macOS version's layout in settings sync

Paths used below:

- `WT` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05` (the only tree to change; branch `audit-manual/sa05`, based on `9100d183`)
- `S` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad` (scratch files, tools, commit message files)

Guardrails for the executor: work only in `WT`. Never touch `/Users/cheidenreich/privat/holzBar` or another
worktree, never switch branches, never push, never run `gh auth switch` or a writing `gh` command, never quit or
relaunch holzBar, never change system state (no `defaults write`, no `tccutil`). Everything in English. Swift 6 with
default `MainActor` isolation and `NonisolatedNonsendingByDefault`; no deprecated API. No hashes, salts, digests or
UUIDs in logs. Persisted keys are never renamed; new ones are added. No new user-facing strings.

<objective>
Implement the maintainer's decision **"Automatisches nicht mitzählen"** for SA-05 (a finding of the review of the
new settings sync, not an audit finding):

1. The layout key of the macOS version this Mac does not run (`MacOS27Layout` on a Mac before macOS 27,
   `ItemSections` on a macOS 27 Mac) is handled like a learned key: left out of this Mac's user digest, the sync
   file's value is kept when this Mac writes (never this Mac's older copy), and taken in silently when this Mac
   adopts or applies a version.
2. holzBar's own automatic writes of its own macOS version's layout key never count as the user's change: they
   never turn "Restart" into "Choose Settings…", never make the joining comparison ask and never by themselves
   show a hint on another Mac. User-initiated layout changes still count.

Purpose: no unnecessary questions or hints. A macOS 26 Mac and a macOS 27 Mac with otherwise equal settings are not
asked when one joins.

Output: three commits on `audit-manual/sa05` (per-macOS layouts; automatic versus user layout changes; docs and
SUMMARY), one new Core test file, `sa05-SUMMARY.md`.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@WT/CLAUDE.md
@WT/.planning/audit/REMEDIATION-2026-10-05.md (section "Open question: SA-05")
@WT/.planning/audit/remediation/sync-alerts-sync-SUMMARY.md
@WT/.planning/audit/remediation/sync-alerts-alerts-SUMMARY.md
@WT/holzBar/Core/SettingsSyncPolicy.swift
@WT/holzBar/Core/SettingsSyncFile.swift
@WT/holzBar/Core/MenuBarBackendKind.swift
@WT/holzBar/Core/Defaults.swift (Key cases, settingsKind, validatedSettings, keysRemoved)
@WT/holzBar/Utilities/SettingsSync.swift
@WT/holzBar/Utilities/SettingsBackup.swift
@WT/holzBar/MenuBar/MenuBarItems/SectionRestore.swift
@WT/holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift (cacheItemsRegardless, lines 584–596)
@WT/holzBar/MenuBar/MacOS27/Concealer27.swift (placeNewApplications 801–843, setSection 845–853, seedLayoutIfNeeded 855–905)
@WT/holzBar/MenuBar/Profiles/LayoutProfiles.swift (apply 183–222)
@WT/holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift (LayoutBarMoves.move, setSection, setSection27)
@WT/holzBar/Events/HIDEventManager.swift (handleMenuBarItemDragStop, handleArrangementEnd)
@WT/Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift (must stay unchanged and green)
@WT/Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
@WT/docs/release-notes/v0.0.7-beta2.md
@WT/docs/features.md (section "Settings sync")
</context>

## 1. Sources: the decision, constraints, and the design additions it needs

### 1.1 Decision items (from the maintainer's decision for SA-05)

| ID | Decision item |
|----|---------------|
| D-01 | The other macOS version's layout key (`MacOS27Layout` on a Mac before macOS 27, `ItemSections` on a macOS 27 Mac) is left out of this Mac's user digest. |
| D-02 | When this Mac writes, the sync file's value of that key is kept; it is never overwritten with this Mac's (possibly older) local copy, which would bring back an F-60-style layout loss. |
| D-03 | That key is taken in silently when this Mac adopts or applies a version. |
| D-04 | holzBar's automatic writes of its own macOS version's layout key are tracked separately from the user's: `SectionRestore.storeSections(placedSections)` (new items) and every other automatic placement found (section 2.2). The user-changed state is recorded only on user-initiated layout changes. |
| D-05 | Automatic writes never turn the quiet "Restart" hint into "Choose Settings…". |
| D-06 | Automatic writes never make the joining comparison ask. |
| D-07 | Automatic writes do not by themselves show a hint on another Mac. |
| D-08 | User-initiated layout changes (drags in the Layout pane, Command-drags, profile apply, import) still count as user changes. |
| D-09 | Result: no unnecessary questions or hints; a macOS 26 Mac and a macOS 27 Mac with otherwise equal settings do not get the question when joining. |

### 1.2 Constraints (from the task)

| ID | Constraint |
|----|------------|
| C-01 | Persisted keys are never renamed; new keys are added. |
| C-02 | Decision logic lives in `holzBar/Core` (package `HolzBarCore`) and is covered by Swift Testing tests in `Tests/HolzBarCoreTests`, both directions (macOS 26 Mac and macOS 27 Mac), automatic versus user changes, joining. |
| C-03 | The existing sync tests keep passing; `SettingsSyncPolicyTests.swift` is not edited. |
| C-04 | No new user-facing strings (none is needed). |
| C-05 | Private: no hashes, salts, digests or UUIDs in logs. |
| C-06 | Docs in the last commit: release notes, `docs/features.md` (it describes this behaviour), the remediation record; `sa05-SUMMARY.md`. |
| C-07 | Commit subjects `fix(sync): resolve SA-05 — <what>` with the two trailer lines; gates before each commit, full `swift test` before the last. |

### 1.3 Design additions the decision needs (each justified; none widens the decision)

| ID | Addition | Why it is needed |
|----|----------|------------------|
| A-01 | The sync file lists the layout keys whose values are current (`currentLayouts`). Layout keys a file does not list (every file of an earlier build) are neither compared, applied nor taken in. | Files written so far (0.0.7 beta 1 and the branch builds) carry each Mac's older copy of the other version's layout. Without the list, the first new write would keep that older copy as "the file's value" (D-02) and a macOS 27 Mac would apply it. This is the migration of existing sync state for the file. |
| A-02 | Applying a version keeps this Mac's own layout when the version did not change it since this Mac last synced (and the user did not change it), and otherwise keeps this Mac's entries for items the version has never seen. | Automatic placements no longer push (D-07), so they are not in the file. Without A-02, the next apply of another Mac's version would drop them, and a newly placed item would turn visible after Restart. |
| A-03 | Without a layout change of the user's, a write keeps the file's current layout for this macOS version and adds only this Mac's entries for items the file has never seen. | A joining Mac whose layout is only holzBar's own is no longer asked (D-06). Its next real push must not replace another Mac's layout with holzBar's placements. |
| A-04 | A version that changed nothing this Mac uses since its last sync (its user settings equal the base and its layout for this macOS is none or the base layout) lets this Mac's changes win (write), instead of asking. | With D-01, a macOS 26 Mac's layout change is invisible to a macOS 27 Mac. If the 27 Mac changed its own layout at the same time, the current table would ask ("both changed"), which is an unnecessary question (D-09). |
| A-05 | Layout edits are counted (`SettingsSyncLayoutEdits`) and the count at the last sync is recorded (`SettingsSyncSyncedLayoutEdits`). An install that already has a layout at the first launch of this build starts with one edit (counts as changed until its first sync); a fresh install starts with none. | A count (not a flag) cannot lose an edit made while an exchange runs. An existing layout's origin is unknown; counting it once avoids silently treating a user's earlier arrangement as holzBar's own. |
| A-06 | The base moves to new keys; the branch-only key `SettingsSyncBaseDigest` is removed at launch, so such a Mac joins once more. | The digest's meaning changes (no layouts). `SettingsSyncBaseDigest` never shipped (not in `v0.0.7-beta1`), so only test Macs on branch builds join again; equal settings are adopted silently. |

Interpretations: a bound profile applied on a display or Space change counts as a user change (task: "profile
apply"). Learned keys keep their current behaviour. The joining question's text stays as it is.

## 2. What the code does today

### 2.1 Why automatic placements count (SA-05)

- `SettingsSyncPolicy.userDigest(of:)` (Core, lines 45–49) is the digest of every validated setting except the
  `learnedKeys`; `ItemSections` and `MacOS27Layout` are both in it.
- `Local.hasChanges` is `base != userDigest`. It drives `needsExchange(.localChange)` (push), `hint(for:)`
  ("Restart" versus "Choose Settings…") and `decide` (ask versus apply).
- A joining Mac (`base == nil`) asks whenever the file's user digest differs from its own (`decide`, line 297).
  A macOS 26 Mac's file holds its `ItemSections` and an older copy of `MacOS27Layout`; a macOS 27 Mac compares
  both, so it practically always asks.
- `SettingsSync.write` (line 1064) writes all of this Mac's settings, including its local copy of the other
  version's layout key.

### 2.2 Layout writes in the app, by origin (complete list, verified with `grep`)

| macOS | Site | Key | Origin |
|-------|------|-----|--------|
| 14–26 | `MenuBarItemManager.cacheItemsRegardless` → `saveSections()` when `needsSectionSave` | `ItemSections` | user (set only by `saveSectionsSoon()`: Layout pane drop, keys, undo through `LayoutBarMoves.move`; Command-drag end in `HIDEventManager`) |
| 14–26 | same call when `ItemSections` is still missing (first run) | `ItemSections` | automatic |
| 14–26 | `SectionRestore.performReconciliation` → `storeSections(wanted)` | `ItemSections` | user (profile) |
| 14–26 | `SectionRestore.performReconciliation` → `storeSections(placedSections)` | `ItemSections` | automatic (new items) |
| 14–26 | `storedSectionIndexes()` rewrites stale identity keys inside the two writes above | `ItemSections` | follows the write it is part of |
| 27 | `Concealer27.setSection` (only caller `LayoutBarMoves.setSection27`, also undo/redo) | `MacOS27Layout` | user |
| 27 | `Concealer27.placeNewApplications` | `MacOS27Layout` | automatic |
| 27 | `Concealer27.seedLayoutIfNeeded` | `MacOS27Layout` | automatic |
| 27 | `LayoutProfiles.apply` (macOS 27 branch) | `MacOS27Layout` | user (profile, also bound profiles) |
| any | `SettingsBackup.importFromFile` → `apply(_, removesMissingKeys: true)` | both | user (import) |
| any | sync apply (`pullIfNeeded`, `use`) and the new take-in | both | sync, never a change |

No other code writes `ItemSections` or `MacOS27Layout` (`grep -rn -E "itemSections|macOS27Layout" holzBar`).
`KnownItemTags`, `KnownApplications27` and `MacOS27LayoutSeeded` are learned keys and stay as they are.

## 3. Design

### 3.1 Terms

`Layouts(backend:)` names the two layout keys from one Mac's point of view:

| `MenuBarBackendKind` | `own` (this Mac's layout key) | `other` (the other version's) | `ownKnown` (learned list of what `own` has seen) |
|----------------------|-------------------------------|-------------------------------|--------------------------------------------------|
| `.windowList` (14, 15), `.service26` (26) | `ItemSections` | `MacOS27Layout` | `KnownItemTags` |
| `.accessibility27` (27 and later) | `MacOS27Layout` | `ItemSections` | `KnownApplications27` |

The app uses `SettingsSyncPolicy.Layouts(backend: .current)` once (`private nonisolated static let layouts` in
`SettingsSync`). Tests pass both backends.

### 3.2 Data model

**Sync file** (`holzBar/Settings.plist` in the folder), one new top-level key:

| Key | Type | Meaning |
|-----|------|---------|
| `currentLayouts` (`SettingsSyncFile.currentLayoutsKey`) | array of strings | The layout keys whose values in `settings` are current: the writer's own layout key, and the other version's when the writer kept it from a file that listed it. Missing in files of earlier builds; their layouts are not used. Earlier builds ignore the key. |

**This Mac's defaults** (all start with `SettingsSync`, so `SettingsBackup.excludedKeyPrefixes` keeps them out of
export, import and sync):

| Key | Type | Meaning | Removed when |
|-----|------|---------|--------------|
| `SettingsSyncBaseSettingsDigest` (new, replaces the branch-only `SettingsSyncBaseDigest`) | String | Digest of the user settings without learned keys and without both layouts at the last sync (write, adopt, apply). Missing: this Mac joins. | sync off, folder change, re-identified Mac (as today) |
| `SettingsSyncBaseLayoutDigest` (new) | String | Layout digest of the sync file's current layout for this Mac's macOS version at the last sync: the layout written, or the version's when adopting or applying; `noLayoutDigest` when it had none. | never; only a sync replaces it (content-based, so it stays valid across sync off and folder changes) |
| `SettingsSyncLayoutEdits` (new, task 2) | Int | Number of user-initiated changes of this Mac's layout. Never reset. | never |
| `SettingsSyncSyncedLayoutEdits` (new, task 2) | Int | `SettingsSyncLayoutEdits` as captured by the last sync. | never |
| `SettingsSyncBaseDigest` (legacy) | String | Branch-only base with layouts inside. | removed at every launch by the migration step |

**Policy types** (Core). New stored properties have default values, so the memberwise initializers the existing
tests use still compile:

- `Local` gains `layoutDigest: String? = nil` (this Mac's layout now), `baseLayoutDigest: String? = nil` and
  `editsLayout: Bool = false` (the user changed this Mac's layout since its last sync). `userDigest` and `base`
  keep their names and now mean the digest without layouts. New computed `comparedLayout`: `layoutDigest` when
  `editsLayout`; otherwise `nil` while joining (holzBar's own layout has no say) and `baseLayoutDigest` when not
  joining (only holzBar's own placements differ from the layout last synced). `hasChanges` becomes
  `base != userDigest || editsLayout`.
- `Version` gains `layoutDigest: String? = nil`: the digest of the file's current layout for this Mac's macOS
  version; `nil` when the file has none or does not list it.

### 3.3 Digests

- `userDigest(of:)` (existing name, same signature): digest of `userSettings(validated)` without both layout keys
  (D-01; the own layout is compared on its own).
- `layoutDigest(of:layouts:)`: digest of the validated `[layouts.own: value]`, or of `[:]` when the key is missing.
  `noLayoutDigest` is the latter. The canonical encoding of `digest(of:)` is reused, so order, Int versus Double and
  JSON-in-Data behave as before.
- A version's digests are computed from `withoutStaleLayouts(settings, currentLayouts:)`, so an unlisted layout
  yields `layoutDigest == nil`.

### 3.4 Decision table (`decide`, rows in order; "changes" = `hasChanges`)

| # | Condition | `.launch` | `.check` / `.localChange` |
|---|-----------|-----------|---------------------------|
| 1 | file unreadable | retry | retry |
| 2 | file missing or unusable | none | write if joining, forcing or changes; else none |
| 3 | `holdsLocalSettings(version, local)` | adopt | adopt |
| 4 | `forcesWrite` | none | write |
| 5 | version from this Mac | none | write if changes, else none |
| 6 | joining, `version.userDigest == local.userDigest`, and `version.layoutDigest` is nil or equals `local.baseLayoutDigest` (only reached with `editsLayout`, see row 3) | none | write |
| 7 | joining, otherwise | ask | ask |
| 8 | `changedNothingSinceBase(version, local)` (A-04) | none | write if changes, else none |
| 9 | version not newer | none | write if changes, else none |
| 10 | postponed and not launch | — | wait |
| 11 | changes | ask | ask |
| 12 | otherwise | apply | apply |

- `holdsLocalSettings`: `version.userDigest == local.userDigest`, and for the layout: when the version has no
  layout (`nil`) it holds this Mac's only if `!local.editsLayout`; when `local.comparedLayout` is nil it holds;
  otherwise the two digests are equal.
- `changedNothingSinceBase`: `local.base != nil`, `version.userDigest == local.base`, and `version.layoutDigest` is
  nil or equals `local.baseLayoutDigest`.
- With layouts left neutral (all new fields at their defaults, as in the existing tests) every row gives what it
  gives today; row 8 only adds `.write` for a newer foreign version equal to the base while this Mac changed,
  which no existing test covers. `hint(for:)` and `needsExchange` are unchanged and keep matching rows 11/12.

### 3.5 Write, adopt and apply rules per macOS version

| Step | Mac before macOS 27 (`own` = `ItemSections`) | macOS 27 Mac (`own` = `MacOS27Layout`) |
|------|----------------------------------------------|-----------------------------------------|
| Write: other key | `MacOS27Layout` = the file's value (listed only if the file listed it); left out if the file has none; never this Mac's copy (D-02) | `ItemSections` likewise |
| Write: own key | this Mac's `ItemSections` when the user changed the layout since the last sync, when "Keep This Mac's Settings" forces the write, or when the file has no current `ItemSections`; otherwise the file's current `ItemSections` plus this Mac's entries whose keys are neither in it nor in the file's `KnownItemTags` (A-03); the file's value as is when this Mac has none | same with `MacOS27Layout` and `KnownApplications27` |
| Write: `currentLayouts` | `ItemSections` when written as above from this Mac or from a listed value; `MacOS27Layout` only when the file listed it | mirrored |
| Write: learned keys | merged as today | merged as today |
| Adopt | take in `MacOS27Layout` from the version when listed and different (D-03); own layout untouched; base layout = the version's layout digest or `noLayoutDigest` | take in `ItemSections` likewise |
| Launch (every readable version, with a base) | learned keys merged (today) plus the other key taken in | same |
| Apply (launch apply, Restart, "Use Settings from Sync Folder") | user settings as today; `MacOS27Layout` from the version when listed (else kept, F-60); `ItemSections`: kept when the version has none, or when it equals the base layout and the user did not change the layout; otherwise the version's plus this Mac's entries the version has never seen (A-02); base layout = the version's layout digest or `noLayoutDigest` | mirrored |
| Import | unchanged (replaces everything); counts as a user layout change | same |

"Never seen" means: the key is neither in the version's (or file's) own layout nor in its `ownKnown` list. Entries
the version knows but lacks follow the version (on macOS 27 a known application missing from the layout is visible).

### 3.6 Migration of existing sync state

All steps run in a new `private static func migrateSyncState()`, called first in `SettingsSync.pullIfNeeded()`,
before its sync-on guard, so it runs at every launch before any model reads the settings:

1. Task 1: if `SettingsSyncBaseDigest` exists, remove it and log once, without data, that this Mac joins the sync
   folder again. A branch-build Mac then joins: equal settings are adopted silently; different ones give the
   existing joining hint. Beta 1 Macs never had a base and join anyway (existing known issue "Settings sync may ask
   once after the update").
2. Task 2: if `SettingsSyncLayoutEdits` is missing, set it to `SettingsSyncPolicy.initialLayoutEdits(hasLayout:)`
   with whether the defaults hold `layouts.own`: 1 for an existing layout, 0 for a fresh install (the first-run save
   comes later). `SettingsSyncSyncedLayoutEdits` missing reads as 0.
3. Files: nothing to rewrite. Files without `currentLayouts` simply have no current layouts; the first write by this
   build lists the writer's own layout and carries the other key unlisted, so builds before this one still find a
   value (they would otherwise remove their own layout when applying, the F-60 bug of beta 1).

Expected upgrade (both Macs on this build, settings equal apart from layouts): each Mac joins once without a
question. With the migrated layout edit, a Mac whose file has no current layout for its macOS writes once after
setup; the other Mac adopts that write silently.

### 3.7 Interfaces (Core; signatures only, for the executor)

```swift
// holzBar/Core/SettingsSyncPolicy.swift — new API in `nonisolated extension SettingsSyncPolicy`
struct Layouts: Equatable, Sendable {
    let own: String
    let other: String
    let ownKnown: String
    init(backend: MenuBarBackendKind)
}
static let layoutKeys: Set<String>                       // ItemSections, MacOS27Layout
static let noLayoutDigest: String
static func layoutDigest(of settings: [String: Any], layouts: Layouts) -> String
static func withoutStaleLayouts(_ settings: [String: Any], currentLayouts: Set<String>) -> [String: Any]
static func mergedLayout(_ remote: [String: Any], keeping local: [String: Any]?, seen: Set<String>) -> [String: Any]
static func settingsToApply(_ remote: [String: Any], over local: [String: Any], layouts: Layouts,
                            baseLayoutDigest: String?, editsLayout: Bool) -> [String: Any]
static func layoutToTakeIn(_ remote: [String: Any], over local: [String: Any], layouts: Layouts) -> [String: Any]
static func fileToWrite(_ local: [String: Any], file remote: [String: Any]?, fileCurrentLayouts: Set<String>,
                        layouts: Layouts, keepsOwnLayout: Bool) -> (settings: [String: Any], currentLayouts: [String])
static func holdsLocalSettings(_ version: Version, local: Local) -> Bool
static func changedNothingSinceBase(_ version: Version, local: Local) -> Bool
// task 2
static func initialLayoutEdits(hasLayout: Bool) -> Int
static func editsLayout(count: Int, synced: Int) -> Bool

// file scope
nonisolated extension SettingsSyncPolicy.Local {
    init(settings: [String: Any], layouts: SettingsSyncPolicy.Layouts, base: String?, baseLayoutDigest: String?,
         editsLayout: Bool, pending: Date?, postponed: Date?, forcesWrite: Bool)
}
nonisolated extension SettingsSyncPolicy.Version {
    // `settings` already passed through withoutStaleLayouts; layoutDigest is nil when it has no `layouts.own`
    init(settings: [String: Any], layouts: SettingsSyncPolicy.Layouts, isFromThisMac: Bool, modified: Date, isNewer: Bool)
}

// holzBar/Core/SettingsSyncFile.swift
static let currentLayoutsKey = "currentLayouts"
// Contents gains: let currentLayouts: Set<String>   (from file[currentLayoutsKey] as? [String], else empty)
```

The two-argument `settingsToApply(_:over:)` and `settingsToWrite(_:file:)` stay unchanged (the existing tests call
them); the new layout-aware functions call them first. Everything new is `nonisolated`, as `hint(for:)` had to be
(a plain extension in Core is main-actor isolated and the nonisolated test suites cannot call it).

### 3.8 Walkthroughs (expected outcomes; the tests in section 4 pin them)

| # | Situation | Outcome |
|---|-----------|---------|
| W1 | macOS 27 Mac B joins a folder written by macOS 26 Mac A; settings equal apart from layouts; file lists `ItemSections` only | B without layout edits: adopt, takes in `ItemSections`. B with edits: write (adds `MacOS27Layout`); A then adopts silently and takes it in. No question either way. |
| W2 | W1 mirrored (26 Mac joins a 27 folder) | Same, mirrored. |
| W3 | B rejoins after editing its layout while sync was off; file lists B's older `MacOS27Layout` (kept by A) | Row 6 (equals B's base layout): write, no question. |
| W4 | B joins with edits; file lists a different `MacOS27Layout` from another macOS 27 Mac C | Row 7: ask (a real conflict between two user layouts). Without edits: adopt, no question. |
| W5 | File from an earlier build with an older `MacOS27Layout` copy | Not compared, not applied, not taken in; carried unlisted on the next write. |
| W6 | A (26) places a new item; B (27) or another 26 Mac in the folder | Nothing pushed; no hint anywhere; A's hint for a waiting version stays "Restart". |
| W7 | B (27) seeds or places a new app | Same as W6, mirrored. |
| W8 | A drags an item in the Layout pane | Push; B adopts silently and takes in `ItemSections`; no hint on B. |
| W9 | A drags (pushes) while B also dragged (edits) | B's push sees row 8: B writes its `MacOS27Layout`, keeps A's `ItemSections`; A adopts silently. No question. |
| W10 | B has a "Restart" hint from A's setting change, then the user drags on B | Hint turns into "Choose Settings…" (user change). |
| W11 | Two macOS 27 Macs B, C: B placed app P (not pushed); C changes a setting | B: apply ("Restart"); C's layout equals B's base, so B keeps its own layout and P stays hidden. If C also changed its layout, B gets C's layout plus P. |
| W12 | B has only holzBar's placements and pushes a setting change | Written `MacOS27Layout` = the file's plus B's entries the file has never seen; C's layout is not replaced. |
| W13 | "Keep This Mac's Settings" | This Mac's own layout written as is; the other key from the file. |

## 4. Tests

New file `Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift`, `@Suite("SettingsSyncPolicy layouts")`, Swift
Testing, style of `SettingsSyncPolicyTests.swift` (no file header lint applies to tests, but keep `import Foundation`,
`import Testing`, `@testable import HolzBarCore`). Direction tests use
`@Test("…", arguments: [MenuBarBackendKind.service26, .accessibility27])` and build realistic settings with a helper
(user setting `ShowOnHover`, `ItemSections`, `MacOS27Layout`, `KnownItemTags`, `KnownApplications27`), creating
`Local` and `Version` through the new convenience initializers so the real digests run.

Task 1 (per-macOS layouts):

1. Each backend has its own layout key (`.windowList`, `.service26` → `ItemSections`; `.accessibility27` → `MacOS27Layout`; `other` and `ownKnown` accordingly).
2. The user digest leaves out both layouts (both directions, any values).
3. The layout digest sees only this Mac's layout key; a missing key gives `noLayoutDigest`; key order and 1 versus 1.0 do not matter.
4. `withoutStaleLayouts`: no list drops both layout keys, a list keeps only the listed ones; learned and user keys stay.
5. A write keeps the file's other-version layout, never this Mac's copy; a file without it gives a file without it; `currentLayouts` lists the other key only when the file listed it (both directions).
6. A write without layout edits keeps the file's current own layout and adds only entries the file has never seen; with edits, with `keepsOwnLayout`, or with no current layout in the file it writes this Mac's layout (both directions).
7. Applying takes the other-version layout from the version, and keeps this Mac's when the version has none.
8. Applying keeps this Mac's own layout when the version's equals the base and there are no edits; with edits it takes the version's (merged).
9. Applying a changed own layout keeps this Mac's entries the version has never seen and drops those it knows (both directions).
10. `layoutToTakeIn` returns the other key when it differs, nothing when it is equal or missing.
11. **A macOS 26 Mac and a macOS 27 Mac with otherwise equal settings never ask when joining**: file from the other macOS version (with its own layout listed; this Mac's key missing, listed and equal, listed and equal to the base layout, or unlisted), this Mac with and without edits, triggers `.localChange`, `.check`, `.launch` → never `.ask`.
12. A newer version that changed only the other-version layout is adopted (`.check` and `.launch`), so no hint appears.
13. A user layout change here and an other-version layout change there do not ask: row 8 gives `.write` for `.localChange` and `.check`, `.none` at `.launch`.
14. **holzBar's own placements never count**: layout differs from the base layout, `editsLayout == false` → `hasChanges == false`, `needsExchange(.localChange)` false, `hint(for:)` with a pending version is `.restart`, a newer version with a setting change gives `.apply`, not `.ask` (both directions).
15. **A user layout change counts**: `editsLayout == true` → `hasChanges`, `needsExchange` true, hint `.choice(isJoining: false)`, newer version with a setting change gives `.ask`.
16. Joining without edits does not ask about a different listed layout of the same macOS version (`.adopt`).
17. Joining with edits asks about a different listed layout of the same version (`.ask`), writes when the file has none or holds the base layout (`.write`; `.none` at launch).
18. A same-version layout from a file of an earlier build is neither compared nor applied.
19. Row 8 with opaque digests: newer foreign version equal to the base, this Mac changed → `.write` (`.localChange`, `.check`), `.none` (`.launch`).
20. The hint offers a restart exactly where a newer version is applied, also with layouts (every candidate with and without edits, layout equal or different, against versions whose decision is `.apply` or `.ask`).

Task 2 (counting):

21. `initialLayoutEdits(hasLayout:)` is 1 with a layout, 0 without.
22. `editsLayout(count:synced:)`: equal counts are no edit; an edit after a sync captured its count still counts.

`SettingsSyncFileTests.swift` additions (task 1): `contents(of:…)` reports `currentLayouts` from a string array, an
empty set when the key is missing, and an empty set for a value of another type. Existing tests stay as they are.

## 5. Commits

Stage only the listed files: `git -C WT add <files> && git -C WT commit -F S/sa05-cN-msg.txt` (message files in `S`).
Do not change git config.

**Commit 1 (after Task 1)** — `holzBar/Core/SettingsSyncPolicy.swift`, `holzBar/Core/SettingsSyncFile.swift`,
`holzBar/Utilities/SettingsSync.swift`, `Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift`,
`Tests/HolzBarCoreTests/SettingsSyncFileTests.swift`

    fix(sync): resolve SA-05 — take in the other macOS version's layout instead of comparing it

    The maintainer chose "Automatisches nicht mitzählen" for SA-05, found in
    the review of the new settings sync.
    Both layout keys counted as user settings, so a macOS 26 Mac and a macOS 27
    Mac compared each other's layouts: joining asked, and a write carried this
    Mac's older copy of the other version's layout into the sync file.
    The user digest now leaves out both layouts; each Mac compares only its own
    layout key. A write keeps the file's value of the other version's layout,
    never this Mac's copy, and adopting or applying takes it in silently. The
    file lists its current layouts; layouts of files from earlier builds are
    neither compared nor applied. A version that changed nothing this Mac uses
    lets this Mac's changes win instead of asking, and applying a changed
    layout keeps this Mac's items the version has never seen.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

**Commit 2 (after Task 2)** — `holzBar/Core/SettingsSyncPolicy.swift`, `holzBar/Utilities/SettingsSync.swift`,
`holzBar/Utilities/SettingsBackup.swift`, `holzBar/MenuBar/MenuBarItems/SectionRestore.swift`,
`holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift`, `holzBar/MenuBar/MacOS27/Concealer27.swift`,
`holzBar/MenuBar/Profiles/LayoutProfiles.swift`, `Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift`

    fix(sync): resolve SA-05 — stop counting holzBar's own layout placements as a settings change

    holzBar's own layout writes (placing new items and the first save of the
    sections before macOS 27, seeding and placing new apps on macOS 27) changed
    the user digest, so they were pushed, turned the quiet Restart hint into
    Choose Settings… and could make a join ask.
    Only user-initiated layout changes count now: Layout pane drags, keys and
    undo, Command-drags, applying a profile and importing settings increment a
    local count of layout edits, which every sync records. holzBar's own
    placements travel with the next real change, and without a layout change of
    the user's a write keeps the folder's layout and only adds items it has
    never seen. A layout from before this update counts as changed until the
    first sync.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

**Commit 3 (after Task 3)** — `docs/release-notes/v0.0.7-beta2.md`, `docs/features.md`,
`.planning/audit/REMEDIATION-2026-10-05.md`, `.planning/audit/remediation/sa05-SUMMARY.md`,
`.planning/audit/remediation/sa05-PLAN.md`

    fix(sync): resolve SA-05 — document that holzBar's own placements no longer count for sync

    The release notes, the features page and the remediation record say that
    holzBar's own placement of new items no longer triggers the sync question
    or a hint on other Macs, and that a macOS 26 Mac and a macOS 27 Mac with the
    same settings are not asked when they join. The summary lists the tests and
    the two-Mac test steps.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

## 6. Gates (all must pass before each commit; run from `WT`)

| Gate | Command | Pass |
|------|---------|------|
| G1 | `zsh S/appcheck.sh WT sa05-<label>` | prints `ERRORS: 0` |
| G2 | `cd WT && swift test --filter SettingsSync` before commits 1 and 2; `cd WT && swift test` (full) before commit 3 | all tests pass. `swift test` sometimes fails to find the TestingMacros plugin on this host; run it again until the test run starts |
| G3 | `cd WT && TOOLCHAIN_DIR=/Library/Developer/CommandLineTools S/swiftlint/swiftlint lint --strict --quiet` | no output |
| G4 | `cd WT && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/strings-check.py` | exit 0 |
| G5 | `cd WT && ! git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'` | exit 0, no output |
| G6 | `git -C WT diff --quiet 9100d183 -- Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift holzBar/Resources/Localizable.xcstrings` | exit 0 (existing policy tests and the string catalog untouched) |

There is no Xcode on this Mac: the app module is only type-checked (G1); CI builds it after the chain's push.

<tasks>

<task type="tracer" tdd="true">
  <name>Task 1 (tracer): per-macOS layout keys end to end — Core policy, sync file, SettingsSync; other version's layout taken in, never compared (commit 1)</name>
  <files>holzBar/Core/SettingsSyncPolicy.swift, holzBar/Core/SettingsSyncFile.swift, holzBar/Utilities/SettingsSync.swift, Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift, Tests/HolzBarCoreTests/SettingsSyncFileTests.swift</files>
  <read_first>sections 1–4 of this plan; holzBar/Core/SettingsSyncPolicy.swift (whole); holzBar/Core/SettingsSyncFile.swift (Contents, contents(of:…)); holzBar/Core/MenuBarBackendKind.swift; holzBar/Core/Defaults.swift (validatedSettings); holzBar/Utilities/SettingsSync.swift (whole; keys 49–92, verifyDeviceIdentity 101–126, forgetSyncState 555–563, finishJoin 638–656, commitJoin 686–704, markSynced 763–771, RemoteVersion/ExchangeRequest/ExchangeResult/Inspection 804–858, makeRequest 865–899, requestExchange 903–942, handle 954–989, performExchange/write/inspect 1019–1127, pullIfNeeded 1227–1285, refreshHint 1323–1339, use 1509–1523); Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift (style; do not edit)</read_first>
  <behavior>
    Tests 1–20 of section 4 (14 and 15 drive `Local.editsLayout` directly; the counting tests 21–22 come in Task 2), plus the SettingsSyncFileTests additions. Every direction test runs for `.service26` and `.accessibility27`. Write them first and see them fail to compile (RED), then implement (GREEN). The existing SettingsSyncPolicyTests and SettingsSyncFileTests pass unchanged.
  </behavior>
  <action>Implements D-01, D-02, D-03, D-06 (for the other version's layout), D-09, A-01, A-02, A-03, A-04, A-06; prepares D-04/D-05/D-07/D-08 through `Local.editsLayout`.

Core, SettingsSyncPolicy.swift: add the API of section 3.7 (everything except `initialLayoutEdits` and `editsLayout(count:synced:)`) in a `nonisolated extension SettingsSyncPolicy`, plus the two file-scope `nonisolated extension`s with the convenience initializers. `Layouts(backend:)` follows the table in 3.1 using `Defaults.Key` raw values. Change `userDigest(of:)` to leave out `layoutKeys` (update its doc comment and the type's doc comment: each Mac compares only its own layout key; the other version's is taken in like a learned key; holzBar's own placements do not count). Add the three `Local` properties and the one `Version` property with default values after the existing ones (so the memberwise initializers stay source compatible), the computed `comparedLayout`, and the new `hasChanges` (section 3.2). Rewrite `decide` exactly per the table in 3.4, using `holdsLocalSettings` and `changedNothingSinceBase`; keep `needsExchange` and `hint(for:)` as they are. `mergedLayout`: the remote dictionary plus every local entry whose key is neither in it nor in `seen`. `settingsToApply(_:over:layouts:baseLayoutDigest:editsLayout:)`: start from the two-argument function; leave the other key as it comes from the remote (absent stays absent); for the own key apply the rule of 3.5 (remove it from the result to keep the local value when the remote has none, or when `!editsLayout` and the remote's layout digest equals `baseLayoutDigest`; otherwise `mergedLayout` with `seen` = the remote's `ownKnown` strings). `layoutToTakeIn`: `[other: value]` only when the remote has the key and its digest differs from the local value's. `fileToWrite`: start from the two-argument `settingsToWrite`, then set the other key to the file's value or remove it, set the own key per 3.5 in this order (this Mac without one → the file's value as is, listed only if the file listed it; else `keepsOwnLayout` or no listed own layout in the file → this Mac's; else `mergedLayout` of the file's listed one with `seen` = the file's `ownKnown`), and return `currentLayouts` sorted per 3.5. `withoutStaleLayouts` removes every `layoutKeys` member not in the list. Doc comments in the style of the file; no logging in Core.

Core, SettingsSyncFile.swift: add `currentLayoutsKey` (doc per 3.2), `Contents.currentLayouts` read in `contents(of:…)` as described; extend the type's doc comment (the file also lists its current layouts).

App, SettingsSync.swift:
(1) Keys (C-01: new persisted keys, the old one only removed): point the `baseKey` constant at the new key "SettingsSyncBaseSettingsDigest"; add `baseLayoutKey` = "SettingsSyncBaseLayoutDigest" and `legacyBaseKey` = "SettingsSyncBaseDigest"; add `private nonisolated static let layouts = SettingsSyncPolicy.Layouts(backend: .current)`.
(2) A static helper that forgets the base removes `baseKey` and `legacyBaseKey` (not `baseLayoutKey`, which is content-based, section 3.2); use it in verifyDeviceIdentity (.otherMac), forgetSyncState and commitJoin instead of the single `removeObject(forKey: baseKey)`.
(3) `migrateSyncState()` per 3.6 step 1, called as the first statement of `pullIfNeeded()`; its log line carries no interpolation.
(4) A static `makeLocal(settings:base:baseLayoutDigest:pending:postponed:forcesWrite:)` built on the `Local` convenience initializer; in this task `editsLayout` is `base == nil || layoutDigest != baseLayoutDigest` (any layout difference still counts until Task 2). Use it in makeRequest (add a `baseLayoutDigest:` parameter; the join in chooseFolder passes the stored `baseLayoutKey` value, which is content-based), requestExchange, pullIfNeeded and refreshHint.
(5) `RemoteVersion` gains `layoutDigest: String?`; `ExchangeResult` gains `writtenLayoutDigest: String?`; `Inspection.settings` becomes the current settings (after `withoutStaleLayouts`) and gains `fileSettings: [String: Any]?` (the file's settings as read, for writing) and `currentLayouts: Set<String>`.
(6) `inspect` builds the `Version` with the convenience initializer from the current settings, and `RemoteVersion` from the same settings and the version's layout digest.
(7) `write` takes the file's settings and current layouts, calls `fileToWrite` with `keepsOwnLayout: request.local.forcesWrite || request.local.editsLayout`, writes `SettingsSyncFile.currentLayoutsKey` beside the existing keys, and returns `writtenLayoutDigest` (the written own layout's digest when it is listed, else nil).
(8) `markSynced` takes `settings:layout:modified:` and also stores `baseLayoutKey`. Call sites: write → `writtenLayoutDigest ?? noLayoutDigest`; adopt → the version's layout digest `?? noLayoutDigest`; launch apply and `use` → the version's layout digest `?? noLayoutDigest`, settings digest of the settings after applying (as today).
(9) Apply: pullIfNeeded's `.apply` and `use` call the five-argument `settingsToApply` with the current `Local`'s `baseLayoutDigest` and `editsLayout`.
(10) Take-in: pullIfNeeded's learned block also merges `layoutToTakeIn` (one `SettingsBackup.apply(_, removesMissingKeys: false)` call); `handle` (.adopt) and `finishJoin` (.adopt) take in `layoutToTakeIn` from the remote version's settings over `syncedSettings()` and log, without interpolation, that the other macOS version's layout was taken in.
(11) Update the class doc comment: each Mac compares only its own layout; the other version's is passed on and taken in.
Do not log any digest. Do not touch the alerts, hints, strings or the folder code.</action>
  <verify><automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05 && swift test --filter SettingsSync 2>&1 | tail -5 && zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05 sa05-t1 | tail -1</automated></verify>
  <acceptance_criteria>
    - The SettingsSync suites pass, including "SettingsSyncPolicy layouts" for both backends; appcheck prints `ERRORS: 0`
    - G3–G6 pass; `git -C WT diff --quiet 9100d183 -- Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift` exits 0
    - `grep -c 'SettingsSyncBaseSettingsDigest\|SettingsSyncBaseLayoutDigest' WT/holzBar/Utilities/SettingsSync.swift` is at least 2, and `grep -c '"SettingsSyncBaseDigest"' WT/holzBar/Utilities/SettingsSync.swift` is 1 (only the legacy constant)
    - `grep -c 'currentLayoutsKey' WT/holzBar/Utilities/SettingsSync.swift` is at least 1
  </acceptance_criteria>
  <done>Each Mac compares only its own layout key; the other version's is kept from the file on writes and taken in on adopt and apply; files list their current layouts and older files' layouts are ignored; commit 1 made after G1–G6.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: count only user-initiated layout changes — holzBar's own placements never push, never change the hint, never make a join ask (commit 2)</name>
  <files>holzBar/Core/SettingsSyncPolicy.swift, Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift, holzBar/Utilities/SettingsSync.swift, holzBar/MenuBar/MenuBarItems/SectionRestore.swift, holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift, holzBar/MenuBar/MacOS27/Concealer27.swift, holzBar/MenuBar/Profiles/LayoutProfiles.swift, holzBar/Utilities/SettingsBackup.swift</files>
  <read_first>sections 2.2, 3.2 and 3.6 of this plan; holzBar/MenuBar/MenuBarItems/SectionRestore.swift (saveSections, storeSections, performReconciliation 295–306); holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift (584–596); holzBar/MenuBar/MacOS27/Concealer27.swift (801–905); holzBar/MenuBar/Profiles/LayoutProfiles.swift (183–222); holzBar/Utilities/SettingsBackup.swift (importFromFile); holzBar/MenuBar/LayoutBar/LayoutBarPaddingView.swift (LayoutBarMoves.move and setSection27, to confirm the user paths); holzBar/Events/HIDEventManager.swift (482–513)</read_first>
  <behavior>
    Tests 21–22 of section 4 (RED first). Tests 14 and 15 from Task 1 already pin the policy side; they must still pass.
  </behavior>
  <action>Implements D-04, D-05, D-06, D-07, D-08 and A-05.

Core: add `initialLayoutEdits(hasLayout:)` and `editsLayout(count:synced:)` to the `nonisolated extension SettingsSyncPolicy` with doc comments (an existing layout counts as changed until the first sync after the update, a fresh install's does not; an edit made while an exchange ran still counts after that exchange records its earlier count).

SettingsSync.swift: add the keys `layoutEditsKey` = "SettingsSyncLayoutEdits" and `syncedLayoutEditsKey` = "SettingsSyncSyncedLayoutEdits" (neither is removed by the base helper). Extend `migrateSyncState()` with step 2 of 3.6 (has a layout = the defaults hold an object for `layouts.own`). Add `static func userChangedLayout()` that increments `layoutEditsKey` (wrapping add) with a doc comment: only user-initiated layout changes call it; holzBar's own placements never do, so they never count as a settings change for sync (SA-05). `makeLocal` now computes `editsLayout` with `editsLayout(count:synced:)` from the two keys (no longer from the base layout). `ExchangeRequest` captures the count it was made with (makeRequest reads `layoutEditsKey` once and uses that value both for `editsLayout` and as the captured count); `markSynced` gains `layoutEdits:` and stores it in `syncedLayoutEditsKey`: the captured count after a write or adopt (exchange and join), the current count after a launch apply and in `use`. Joining, sync off, folder change and re-identification leave both counts alone.

Layout write sites (each call comes right after the `Defaults.set` of the layout, in the same main-actor step):
- SectionRestore.swift: `saveSections(byUser:)` and `storeSections(_:byUser:)` call `SettingsSync.userChangedLayout()` after their write only when `byUser`; `performReconciliation` passes `byUser: true` for `wanted` (profile) and `byUser: false` for `placedSections`. Update the doc comments (the first-run save and new-item placement are holzBar's own and do not count for sync).
- MenuBarItemManager.swift (cacheItemsRegardless): capture `needsSectionSave` before resetting it and call `saveSections(byUser:)` with it, so the first-run save (missing `ItemSections`) is not a user change.
- Concealer27.swift: `setSection` calls `SettingsSync.userChangedLayout()` after its write. `placeNewApplications` and `seedLayoutIfNeeded` stay without it; add one sentence to each doc comment that this placement is holzBar's own and does not count as a settings change for sync.
- LayoutProfiles.swift: in `apply`, macOS 27 branch, call it right after `Defaults.set(layout.mapValues(\.rawValue), forKey: .macOS27Layout)` (not when the profile has no macOS 27 layout). The macOS 14–26 branch counts through `storeSections(wanted, byUser: true)`.
- SettingsBackup.swift: in `importFromFile`, call it right after `apply(settings, removesMissingKeys: true)` and before `relaunch()`.
No other call sites. Do not mention the function name in comments inside `placeNewApplications` or `seedLayoutIfNeeded`.</action>
  <verify><automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05 && swift test --filter SettingsSync 2>&1 | tail -5 && zsh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/appcheck.sh /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05 sa05-t2 | tail -1 && grep -rn 'userChangedLayout()' holzBar --include='*.swift' | grep -v '///' | grep -v 'static func' | wc -l</automated></verify>
  <acceptance_criteria>
    - SettingsSync suites pass (tests 1–22); appcheck prints `ERRORS: 0`; G3–G6 pass
    - The call count printed by the verify command is 5: two in SectionRestore.swift (inside the `byUser` branches), one each in Concealer27.swift, LayoutProfiles.swift and SettingsBackup.swift
    - `awk '/func setSection\(_ section: MacOS27Section/,/^    }$/' WT/holzBar/MenuBar/MacOS27/Concealer27.swift | grep -v '///' | grep -c 'userChangedLayout()'` is 1, and `grep -v '///' WT/holzBar/MenuBar/MacOS27/Concealer27.swift | grep -c 'userChangedLayout()'` is 1 (so neither placeNewApplications nor seedLayoutIfNeeded calls it)
    - `grep -c 'storeSections(placedSections, byUser: false)' WT/holzBar/MenuBar/MenuBarItems/SectionRestore.swift` is 1 and `grep -c 'storeSections(wanted, byUser: true)' WT/holzBar/MenuBar/MenuBarItems/SectionRestore.swift` is 1
  </acceptance_criteria>
  <done>Only user-initiated layout changes move the edit count; holzBar's own placements leave `hasChanges` false; commit 2 made after G1–G6.</done>
</task>

<task type="auto">
  <name>Task 3: docs, remediation record and SUMMARY; full gates (commit 3)</name>
  <files>docs/release-notes/v0.0.7-beta2.md, docs/features.md, .planning/audit/REMEDIATION-2026-10-05.md, .planning/audit/remediation/sa05-SUMMARY.md, .planning/audit/remediation/sa05-PLAN.md</files>
  <read_first>section 9 of this plan; docs/release-notes/v0.0.7-beta2.md ("#### Settings sync" and "### ⚠️ Known issues"); docs/features.md ("## Settings sync"); .planning/audit/REMEDIATION-2026-10-05.md ("Review fix-ups" list and "## Open question: SA-05"); .planning/audit/remediation/sync-alerts-alerts-SUMMARY.md (SUMMARY format)</read_first>
  <action>Implements C-06 and C-07. Make exactly the doc edits of section 9 (release notes: remove the Known issues bullet about holzBar's own placement and add the Fixed line; features: replace the last sync bullet and adjust the "Settings a Mac lacks are kept" bullet; remediation record: replace the open question by the resolved section and add the SA-05 commits to the review fix-ups line, using the real short hashes of commits 1 and 2 from `git -C WT log --format='%h %s' 9100d183..HEAD`). Do not change the remediation record's counts or the table of the 16 decisions. Write `sa05-SUMMARY.md` in the format of the sync-alerts SUMMARYs: frontmatter (phase audit-remediation-sa05, plan sa05, subsystem settings-sync, requirements [SA-05], status, key-files, completed date, plan_head_before 9100d183, actuals), the decision, the commits (1, 2 with hashes, 3 as "this commit"), what changed per part, the per-macOS rules table (section 3.5), the migration, the tests with their names and the counts of the full run, the gates table with results, deviations from this plan, known risks (section 7), and the two-Mac test steps (section 8). Run every gate with the full `swift test`, then commit 3 including this plan file.</action>
  <verify><automated>cd /private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05 && swift test 2>&1 | tail -4 && grep -c "counts as a settings change" docs/release-notes/v0.0.7-beta2.md docs/features.md; grep -c "SA-05" .planning/audit/REMEDIATION-2026-10-05.md</automated></verify>
  <acceptance_criteria>
    - Full `swift test` passes; G1, G3–G6 pass on the final tree
    - The old wording is gone from both docs: the first grep prints 0 for both files (before the edit it prints 1 for each: release notes line 103, features line 77)
    - The SA-05 line count of the remediation record is at least 2 (resolved section and fix-ups line; it is 1 before the edit)
    - The remediation record has a resolved SA-05 section naming the decision "Automatisches nicht mitzählen" and the commit hashes of commits 1 and 2
    - `git -C WT status --short` is empty after commit 3; `git -C WT log --oneline 9100d183..HEAD` shows exactly the three SA-05 commits
  </acceptance_criteria>
  <done>Docs and the remediation record describe the fixed behaviour; the SUMMARY with test steps is committed; the branch holds three SA-05 commits and nothing else changed.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| sync folder → holzBar | Anyone who can write the synced folder controls `Settings.plist`, now including `currentLayouts` |
| other holzBar builds → sync file | Builds before this one write layout copies that may be older than the layouts they stand for |
| this Mac's defaults | The new keys (digests, counts) stay on this Mac |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-SA05-01 | Tampering | `currentLayouts` and the layouts in the sync file | low | mitigate | Same trust as every synced setting: values pass `validatedSettings` (top-level dictionary kind), the 1 MiB limit and the file checks; a listed layout is applied only where a version is applied anyway (launch without local changes, Restart, the user's choice), never removes a local key, and the merge only adds local entries |
| T-SA05-02 | Tampering (integrity, data loss) | An older copy of a layout replacing a newer one (F-60 style) | medium | mitigate | This Mac never writes its own copy of the other version's layout; files of earlier builds have no current layouts, so their layouts are neither compared, applied nor taken in; writes carry such values unlisted |
| T-SA05-03 | Information disclosure | New local keys (base digests, layout edit counts) | low | mitigate | Under the `SettingsSync` prefix: never exported, imported or synced; never logged (C-05); a digest or count reveals no setting |
| T-SA05-04 | Denial of service (annoyance) | Questions and hints caused by holzBar's own placements | low | mitigate | This change: automatic placements never push or change the hint; joins compare only user changes |
| T-SA05-SC | Tampering | npm/pip/cargo installs | high | accept | No package is installed; no dependency changes |
</threat_model>

## 7. Risks

1. **Branch-build test Macs join once more** (A-06): equal settings are adopted silently; different ones show the
   existing joining hint. Released 0.0.7 beta 1 never had a base, so released users see only the existing known issue.
2. **First sync after the update writes once** where a Mac's layout counts as changed (A-05) and the file has no
   current layout for its macOS version; other Macs on this build adopt that write silently. Two macOS 27 Macs whose
   layouts differ at the update get the question once (covered by "Settings sync may ask once after the update").
3. **Mixed builds**: a Mac still on 0.0.7 beta 1 neither lists nor keeps current layouts, and its F-60 bug can still
   delete its own layout when it applies a file without it. Layout changes of a beta 1 Mac do not reach Macs on this
   build until it updates. Advise updating every Mac that syncs.
4. **Merge heuristics** (A-02, A-03): an item the other Mac knows but has no entry for follows the other Mac (on macOS
   27 it is visible). A layout key in an older identity format counts as unseen and is kept, which is harmless.
5. **Automatic placements reach other Macs only with the next real change** (as learned keys do). Until then another
   Mac of the same version that installs the same app places it by its own new-items setting.
6. **A joining Mac without layout edits keeps its own layout** when the folder holds a different one of the same
   version; it takes the folder's at the next layout change there, and its own writes never replace the folder's.
7. **Bound profiles** applied on a display or Space change count as user changes and push, as before.
8. The app module is only type-checked locally; CI's Xcode 27 build is the first real build.

## 8. Two-Mac test steps (maintainer, after the chain's build; Mac A on macOS 26, Mac B on macOS 27, same folder)

Read-only checks use `defaults read com.holzcloud.holzBar <Key>` and the sync file's modification date.

1. **Join without a question.** Give A and B the same settings (apart from the layout). On B, turn sync off,
   rearrange one item in the Layout pane, turn sync on with the folder: no question, no hint on A. Repeat on A.
   Then change Show on hover on A only and repeat the join on B: the question appears (a real difference).
2. **holzBar's own placement on macOS 27.** Settings → Advanced → new items: Hidden. Launch a menu bar app B has never
   seen. B hides it; the sync file's date does not change; A shows no hint.
3. **holzBar's own placement on macOS 26.** Same on A: the new item moves to Hidden, the file's date stays, B shows nothing.
4. **Restart stays Restart.** Change a setting on A. B shows "Settings changed on another Mac" with Restart. Launch a
   new menu bar app on B so holzBar places it: still Restart. Click Restart: B gets A's setting and the new app stays hidden.
5. **User changes still count.** With a Restart hint on B, drag an item to another section in B's Layout pane: after
   about 5 s the hint reads "Choose Settings…". Apply a layout profile or import settings on a Mac: the other Mac of
   the same version (if available) gets a hint; A and B never get one for each other's layout alone.
6. **Each version's layout stays its own.** Drag an item on A: B shows no hint, and after B's next launch
   `ItemSections` on B equals A's. Drag an item on B: `MacOS27Layout` on A follows after A's next launch, and
   changing a setting on A afterwards and clicking Restart on B leaves B's layout as it is (no older copy).
7. **Upgrade.** From the previous build with sync on, update both Macs and launch them: no question when their
   settings are equal apart from the layouts; at most one silent write per Mac.
8. **Two Macs of the same version (if available).** Holding back holzBar's placement: place a new app on one Mac,
   change a setting on the other, click Restart on the first: the newly placed app stays hidden.

## 9. Docs (Task 3; exact edits)

- `docs/release-notes/v0.0.7-beta2.md`:
  - Remove the Known issues bullet that starts with "**holzBar's own placement of new items counts as a settings
    change for sync.**".
  - Add under "#### Settings sync" (after "**The other macOS version's layout is kept.** …"): "- **holzBar's own
    placement of new items no longer counts as a change.** It no longer turns **Restart** into **Choose Settings…**
    or shows a hint on your other Macs, and a Mac on macOS 26 and one on macOS 27 with the same settings are not
    asked which settings to use when they join."
- `docs/features.md`, "## Settings sync":
  - Replace the bullet "- **Settings a Mac lacks are kept**, such as the other macOS version's layout." (line 75) with "- **Each macOS version
    keeps its own layout.** A Mac on macOS 26 and one on macOS 27 never compare their layouts or ask about them;
    each passes the other's on unchanged, and settings a Mac lacks are kept."
  - Replace the last bullet ("holzBar's own placement of new menu bar items counts as a settings change, …") with
    "**Only your changes count.** holzBar's own placement of new menu bar items never turns **Restart** into
    **Choose Settings…** and never shows a hint on another Mac; it travels with your next change. Layout changes you
    make (in the Layout pane, by Command-dragging, by applying a profile or by importing settings) count."
- `.planning/audit/REMEDIATION-2026-10-05.md`:
  - In "Review fix-ups that name no finding ID", append to the sync-alerts line: "`<hash 1>`, `<hash 2>` (SA-05)".
  - Replace "## Open question: SA-05" and its paragraph with "## SA-05: resolved": found in the review of the sync
    chain, not an audit finding; the maintainer chose **"Automatisches nicht mitzählen"**; three bullets (each Mac
    compares only its own layout key and takes the other version's in silently, never writing its older copy; only
    user-initiated layout changes count, holzBar's own placements travel with the next real change; sync files list
    their current layouts, so copies in files of earlier builds are ignored); the commits; a link to
    [remediation/sa05-SUMMARY.md](remediation/sa05-SUMMARY.md).
- No change to README, SECURITY.md, CLAUDE.md, docs/privacy-and-permissions.md or the string catalog.

## 10. Source coverage audit

| Source | ID | Item | Task | Status |
|--------|----|------|------|--------|
| GOAL | — | No unnecessary questions or hints from holzBar's own placements or the other version's layout | 1, 2 | COVERED |
| REQ | SA-05 | holzBar's own layout writes counted as user changes | 1, 2 | COVERED |
| CONTEXT | D-01 | Other version's layout left out of the user digest | 1 | COVERED |
| CONTEXT | D-02 | File's value kept on write, never the local copy | 1 (with A-01) | COVERED |
| CONTEXT | D-03 | Taken in silently on adopt and apply | 1 | COVERED |
| CONTEXT | D-04 | Automatic writes tracked separately (all sites of 2.2) | 2 | COVERED |
| CONTEXT | D-05 | Restart never turns into Choose Settings… by automatic writes | 1 (policy), 2 (wiring) | COVERED |
| CONTEXT | D-06 | Joining comparison never asks because of automatic writes | 1 (policy), 2 (wiring) | COVERED |
| CONTEXT | D-07 | No hint on another Mac from automatic writes alone | 2 | COVERED |
| CONTEXT | D-08 | User layout changes (drags, Command-drags, profile, import) still count | 2 | COVERED |
| CONTEXT | D-09 | 26 and 27 Macs with otherwise equal settings not asked when joining | 1 (tests 11, 13) | COVERED |
| CONTEXT | C-01…C-07 | Keys, Core tests both directions, existing tests, strings, privacy, docs, commits | 1, 2, 3 | COVERED |
| RESEARCH | — | No research file for this item | — | n/a |

<verification>
- Full `swift test` passes (all three test targets); the existing `SettingsSyncPolicyTests.swift` is byte-identical to `9100d183`.
- appcheck `ERRORS: 0`; SwiftLint strict quiet prints nothing; privacy network/logs and strings checks exit 0; the former-name check finds nothing.
- `git -C WT log --oneline 9100d183..HEAD` lists the three SA-05 commits with the required subjects and trailers.
</verification>

<success_criteria>
- holzBar's own placements (both macOS versions) neither push, nor change the quiet hint, nor make a join ask (tests 14, 16; walkthroughs W6, W7).
- User layout changes still count (test 15; W10).
- A macOS 26 and a macOS 27 Mac with otherwise equal settings are never asked when joining (test 11; W1–W3).
- The other version's layout is never written from a local copy and never replaced by an older one (tests 5, 7, 18; W5).
- Docs and the remediation record updated; `sa05-SUMMARY.md` committed.
</success_criteria>

<output>
Create `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sa05/.planning/audit/remediation/sa05-SUMMARY.md` in Task 3 and commit it with commit 3.
</output>
