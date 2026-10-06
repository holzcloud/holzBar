---
phase: audit-remediation-sa05
plan: sa05
subsystem: settings-sync
tags: [sync, layout, macos26, macos27]
requirements: [SA-05]
status: complete
key-files:
  created:
    - Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift
  modified:
    - holzBar/Core/SettingsSyncPolicy.swift
    - holzBar/Core/SettingsSyncFile.swift
    - holzBar/Utilities/SettingsSync.swift
    - holzBar/Utilities/SettingsBackup.swift
    - holzBar/MenuBar/MenuBarItems/SectionRestore.swift
    - holzBar/MenuBar/MenuBarItems/MenuBarItemManager.swift
    - holzBar/MenuBar/MacOS27/Concealer27.swift
    - holzBar/MenuBar/Profiles/LayoutProfiles.swift
    - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
    - docs/release-notes/v0.0.7-beta2.md
    - docs/features.md
    - .planning/audit/REMEDIATION-2026-10-05.md
decisions:
  - "SA-05: Automatisches nicht mitzählen. Each Mac compares only its own macOS version's layout key and takes the other one in silently; only user-initiated layout changes count."
  - "A local count of layout edits (SettingsSyncLayoutEdits, SettingsSyncSyncedLayoutEdits) marks user layout changes; a count cannot lose an edit made while an exchange runs."
  - "Sync files list their current layouts (currentLayouts); layout copies in files of earlier builds are neither compared, applied nor taken in."
  - "Review fix-up: a joining Mac without layout edits takes in the folder's layout for its macOS version (at launch at once, while running through the Restart hint)."
  - "Review fix-up: after the update, an existing layout counts as a user change only on a Mac that did not sync."
  - "Review fix-up: a file without the other macOS version's layout gets this Mac's copy, not listed as current, for 0.0.7 beta 1."
completed: 2026-10-06
duration: 11 min (plus the review fix-ups)
plan_head_before: 9100d1834b841601abfa55a49aa797607630fe2d
plan_head_after: b5b9959f
actuals:
  tokens: 33000    # chars/4 over the realized diff (code, tests, docs and this summary)
  tasks: 7
  commits: 6       # measured 9100d183..b5b9959f when this file was last written; the review docs commit is the seventh
---

# SA-05: holzBar's own layout placements and the other macOS version's layout no longer count for settings sync

The maintainer chose **"Automatisches nicht mitzählen"** for SA-05, a finding of the review of the
new settings sync (not an audit finding). holzBar's own automatic placements no longer count as the
user's change, and the layout key of the macOS version a Mac does not run is taken in silently
instead of compared. A macOS 26 Mac and a macOS 27 Mac with otherwise equal settings are no longer
asked which settings to use when one joins.

## Commits

| # | Hash | Subject |
|---|------|---------|
| 1 | `4c5e3539` | fix(sync): resolve SA-05 — take in the other macOS version's layout instead of comparing it |
| 2 | `422bba40` | fix(sync): resolve SA-05 — stop counting holzBar's own layout placements as a settings change |
| 3 | `d41ca102` | fix(sync): resolve SA-05 — document that holzBar's own placements no longer count for sync |
| 4 | `ab2aad45` | fix(sync): address review of SA-05 — take in the folder's layout when a Mac joins without layout changes |
| 5 | `fde070f9` | fix(sync): address review of SA-05 — count an existing layout as changed only on a Mac that did not sync |
| 6 | `b5b9959f` | fix(sync): address review of SA-05 — keep the other layout for earlier builds when the file has none |
| 7 | this commit | fix(sync): address review of SA-05 — correct the docs and add the same-version test steps |

## What changed

### Part 1: per-macOS layouts (commit 1)

- **Core, `SettingsSyncPolicy`**: `Layouts(backend:)` names this Mac's layout key (`own`), the other
  version's (`other`) and the learned list of `own` (`ownKnown`). `userDigest(of:)` leaves out both
  layout keys; `layoutDigest(of:layouts:)` digests only `own` (`noLayoutDigest` without one).
  `Local` gains `layoutDigest`, `baseLayoutDigest`, `editsLayout` and `comparedLayout`;
  `hasChanges` is `base != userDigest || editsLayout`. `Version` gains `layoutDigest` (nil when the
  file has no current own layout). `decide` follows the plan's table: `holdsLocalSettings` (adopt),
  a joining Mac whose only difference is its own layout against a file without one or with the
  layout it last synced writes instead of asking, and `changedNothingSinceBase` lets this Mac's
  changes win over a version that changed nothing this Mac uses. New pure functions:
  `withoutStaleLayouts`, `mergedLayout`, the layout-aware `settingsToApply`, `layoutToTakeIn`,
  `fileToWrite`. Existing members keep their signatures, so `SettingsSyncPolicyTests.swift` is
  unchanged and passes.
- **Core, `SettingsSyncFile`**: `currentLayoutsKey` and `Contents.currentLayouts`.
- **App, `SettingsSync`**: base keys `SettingsSyncBaseSettingsDigest` (new) and
  `SettingsSyncBaseLayoutDigest` (new, content-based, kept when sync is turned off); the branch-only
  `SettingsSyncBaseDigest` is removed at launch (`migrateSyncState()`), so test Macs on branch
  builds join once more. `inspect` uses only the file's current layouts; `write` uses `fileToWrite`
  and writes `currentLayouts`; launch apply and `use` use the layout-aware apply; adopt (join and
  exchange) and the launch's learned-key step take in the other version's layout.

### Part 2: only user layout changes count (commit 2)

- **Core**: `initialLayoutEdits(hasLayout:)` and `editsLayout(count:synced:)`.
- **App, `SettingsSync`**: `SettingsSyncLayoutEdits` counts user layout changes
  (`userChangedLayout()`), `SettingsSyncSyncedLayoutEdits` holds the count the last sync recorded
  (captured with the request for a write or adopt, current for a launch apply and `use`). The
  migration starts the count at 1 for an existing layout and 0 for a fresh install.
- **Call sites of `SettingsSync.userChangedLayout()`** (exactly five):
  `SectionRestore.saveSections(byUser: true)` (Layout pane drop, keys, undo, Command-drag, through
  `needsSectionSave`), `SectionRestore.storeSections(wanted, byUser: true)` (profile before macOS 27),
  `Concealer27.setSection` (Layout pane on macOS 27, with undo), `LayoutProfiles.apply` (macOS 27
  branch, when the profile has a macOS 27 layout) and `SettingsBackup.importFromFile`.
- **holzBar's own writes never call it**: the first-run save (`cacheItemsRegardless` passes
  `byUser: needsSectionSave`), `storeSections(placedSections, byUser: false)`,
  `Concealer27.placeNewApplications`, `Concealer27.seedLayoutIfNeeded`, and every sync apply or take-in.

### Rules per macOS version

| Step | Mac before macOS 27 (`own` = `ItemSections`) | macOS 27 Mac (`own` = `MacOS27Layout`) |
|------|----------------------------------------------|-----------------------------------------|
| Write: other key | `MacOS27Layout` = the file's value (listed only if the file listed it); only when the file has none, this Mac's copy, never listed (for 0.0.7 beta 1) | `ItemSections` likewise |
| Write: own key | this Mac's `ItemSections` after a user layout change, with "Keep This Mac's Settings", or when the file has no current one; otherwise the file's current one plus this Mac's entries it has never seen (neither in it nor in its `KnownItemTags`); the file's value as is when this Mac has none | same with `MacOS27Layout` and `KnownApplications27` |
| Write: `currentLayouts` | `ItemSections` when written from this Mac or a listed value; `MacOS27Layout` only when the file listed it | mirrored |
| Adopt | takes in a listed, different `MacOS27Layout`; base layout = the version's. A joining Mac without layout edits also takes in the version's `ItemSections` plus its own unseen entries when the version is newer: at launch at once; while running it records its own layout as base and offers Restart | takes in `ItemSections`; the join take-in uses `MacOS27Layout` |
| Launch with a base | learned keys merged plus the other key taken in | same |
| Apply (launch, Restart, "Use Settings from Sync Folder") | user settings as before; `MacOS27Layout` from the version when listed (else kept); `ItemSections` kept when the version has none or did not change it since the last sync and the user did not change it; otherwise the version's plus this Mac's entries it has never seen | mirrored |
| Import | replaces everything; counts as a user layout change | same |

### Migration

1. `SettingsSyncBaseDigest` (branch builds only, never released) is removed at every launch; such a
   Mac joins once more. Equal settings are adopted silently.
2. `SettingsSyncLayoutEdits` starts at 1 when a layout exists and sync is off, otherwise 0 (review
   fix-up `fde070f9`): a Mac that syncs had its layout from the folder, which earlier builds synced
   whole, so its first join takes in the folder's layout without a question. Branch-build test Macs
   that already ran commit 2 keep the 1 they stored, and are asked once if their layouts differ.
3. Sync files are not rewritten: files without `currentLayouts` have no current layouts. The first
   write by this build lists the writer's own layout and carries the other key unlisted for builds
   before this one.

## Review fix-ups (commits 4 to 7)

The review of commits 1 to 3 found one major and three minor issues; all four are fixed.

1. **Major: a joining Mac never received the folder's layout for its own macOS version.** With no
   layout edits, `holdsLocalSettings` adopted while `comparedLayout` was nil, every adopt path
   recorded the file's layout as synced but applied nothing, and the next drag wrote the stale
   layout over the other Mac's arrangement. `SettingsSyncPolicy.ownLayoutToTakeIn` now gives the
   version's layout plus this Mac's entries it has never seen, for a joining Mac without layout
   edits and a version newer than the last sync. At launch the adopt applies it before anything
   reads the layout. While holzBar runs (`SettingsSync.adopt`, used by `finishJoin` and `handle`),
   holzBar reads the layout only at launch, so the Mac records its own layout digest as synced,
   keeps the date of the last sync, sets the version pending and offers the quiet Restart hint;
   `decide` then applies the version (Restart or next launch). `RemoteVersion` carries `isNewer`.
2. **Minor: the migration made same-version Macs ask.** See Migration step 2.
3. **Minor: F-60 regression for 0.0.7 beta 1 peers.** `fileToWrite` now writes this Mac's copy of
   the other version's layout when the file has none, without listing it in `currentLayouts`;
   this build ignores it (`withoutStaleLayouts`), beta 1 keeps a layout. The file's value still
   always wins when it has one.
4. **Minor: docs overstated how holzBar's own placements travel.** A write after a non-layout user
   change keeps the file's layout plus only entries the file has never seen (neither in it nor in
   its learned list), and applying a changed layout lets entries the version knows follow it.
   `docs/features.md`, `REMEDIATION-2026-10-05.md` and this summary now say so; the release notes
   never claimed it. The release notes' known issues now say that the layout of a Mac that already
   synced does not count in the one-time question after the update, and to update every Mac that
   syncs.

## Tests

New suite **"SettingsSyncPolicy layouts"** (`Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift`),
22 test functions, the direction tests parameterized over `.service26` and `.accessibility27`:

- Each macOS version has its own layout key
- The user digest leaves out both layouts
- The layout digest sees only this Mac's layout key
- Only the layouts a file lists as current are used
- A write keeps the file's layout of the other macOS version, and adds this Mac's copy unlisted only
  when the file has none (review fix-up)
- Without a layout change of the user's, a write keeps the file's layout and adds only items it has never seen
- Applying takes the other macOS version's layout from the version, and keeps this Mac's when it has none
- Applying keeps this Mac's layout when the version did not change it since the last sync
- Applying a changed layout keeps this Mac's items the version has never seen
- The other macOS version's layout is taken in only when it differs
- A Mac before macOS 27 and a macOS 27 Mac with otherwise equal settings never ask when one joins
- Joining without a layout change of the user's does not ask about another layout of the same macOS version
- A joining Mac without a layout change of the user's takes in the folder's layout of its macOS version
  (review fix-up: the merged layout; while running the recorded state applies with Restart; nothing
  after an edit, when not joining, for a version not newer, without a current layout, when held; a
  fresh install takes the folder's as it is)
- Joining after a layout change of the user's asks only about another user's layout
- A layout from a file of an earlier build is neither compared nor applied
- A newer version that changed only the other macOS version's layout is adopted
- A layout change here and one of the other macOS version there do not ask
- holzBar's own placements never count as a change
- A layout change of the user's counts as a change
- A newer version equal to the last sync lets this Mac's changes win
- A layout from before the update counts as changed until the first sync only on a Mac that did not sync
- After the update, a Mac that syncs takes in the layout of another Mac of its macOS version without a
  question (review fix-up)
- Only layout edits the last sync did not record count
- The hint offers a restart exactly where a newer version is applied, also with layouts

`SettingsSyncFileTests`: "The contents list the file's current layouts" (string array, missing key,
wrong type). `SettingsSyncPolicyTests.swift` is byte-identical to `9100d183` and passes.

RED was seen before each implementation step (the new API did not compile), GREEN after.
SettingsSync filter: 86 tests in 5 suites. Full `swift test`: 435 tests in 60 suites, 195 tests in
35 suites and 3 tests in 1 suite, all passed. After the review fix-ups: SettingsSync filter 88 tests
in 5 suites; full `swift test` 437 tests in 60 suites, 195 tests in 35 suites and 3 tests in 1 suite,
all passed (`swift test` needed retries for the known Command Line Tools "TestingMacros plugin not
found" transient).

## Gates

| Gate | Command | Result |
|------|---------|--------|
| G1 | `appcheck.sh WT sa05-t1/-t2/-t3`, then `appcheck.sh WT sa05` | `ERRORS: 0` before each commit (only the pre-existing `ScreenCapture.swift` deprecation warning) |
| G2 | `swift test --filter SettingsSync` (commits 1, 2, 4 to 6), full `swift test` (commits 3, 7) | all passed |
| G3 | `swiftlint lint --strict --quiet` | no output |
| G4 | privacy-check network, logs; strings-check | exit 0 (382 strings in 5 languages; no new strings) |
| G5 | former-name `git grep` | no match |
| G6 | `git diff --quiet 9100d183 -- SettingsSyncPolicyTests.swift Localizable.xcstrings` | exit 0 (also after the review fix-ups) |

## Deviations from Plan

None that change behaviour; small implementation choices:

1. `markSynced` is `markSynced(base:layout:layoutEdits:modified:)` with an optional `layout` that
   falls back to `noLayoutDigest` inside, instead of `settings:layout:modified:` with the fallback at
   each call site.
2. Two private helpers in `SettingsSync`: `currentLocal(settings:postponed:)` (the `Local` from the
   stored sync state, used by the launch, `refreshHint` and `use`) and `takeInOtherLayout(from:)`
   (the adopt take-in with its log line).
3. Layout values are validated like every synced setting (`Defaults.Key.validatedSettings`) before
   they are digested, merged or taken in; a layout that is not a dictionary counts as none
   (`Version.layoutDigest` nil, `layoutDigest` = `noLayoutDigest`).
4. Test 19 also checks that a newer version whose layout changed since the last sync still asks, and
   test 22 that the edit count wraps instead of trapping.

## Known risks

1. Branch-build test Macs join once more; equal settings are adopted silently, different ones show
   the existing joining hint. Released 0.0.7 beta 1 never had a base.
2. The first sync after the update: a Mac that syncs counts its layout as unchanged and takes in
   the folder's current layout for its macOS version, if the folder has one (a version written by a
   Mac already on this build); its own entries the folder has never seen stay. Only a Mac that had
   sync off and has a layout compares it once and may be asked when it joins.
3. Mixed builds: a Mac still on 0.0.7 beta 1 neither lists nor keeps current layouts and still
   writes its settings over the folder's. A file without its layout key now carries the writer's
   copy (unlisted), so beta 1 keeps a layout, possibly an older one; only a writer without a copy
   leaves the key out. The release notes say to update every Mac that syncs.
4. Merge heuristics: an item the other Mac knows but has no entry for follows the other Mac (on macOS
   27 it is visible). A layout key in an older identity format counts as unseen and is kept.
5. Automatic placements are not synced by themselves. A write after a user layout change carries
   this Mac's whole layout; a write after any other user change carries only entries the file has
   never seen (neither in its layout nor in its learned list). Applying a changed layout lets every
   entry the version knows follow the version.
6. A joining Mac without layout edits takes the folder's layout while holzBar runs only after a
   restart (the Restart hint, or the next launch). Until then a user change of its own turns the
   hint into "Choose Settings…", as for any waiting version. If the folder's version is not newer
   than this Mac's last sync (sync turned off and on again with the same folder, nothing new from
   another Mac), its layout is not taken in: this Mac's layout already holds it, apart from
   holzBar's own placements.
7. Bound profiles applied on a display or Space change count as user changes and push, as before.
8. The app module is only type-checked locally; CI's Xcode 27 build is the first real build.

## Two-Mac test steps (Mac A on macOS 26, Mac B on macOS 27, same sync folder)

Read-only checks: `defaults read com.holzcloud.holzBar <Key>` and the sync file's modification date.

1. **Join without a question.** Give A and B the same settings apart from the layout. On B, turn
   sync off, rearrange one item in the Layout pane, turn sync on with the folder: no question, no
   hint on A. Repeat on A. Then change Show on hover on A only and repeat the join on B: the question
   appears (a real difference).
2. **holzBar's own placement on macOS 27.** Settings → Advanced → new items: Hidden. Launch a menu
   bar app B has never seen. B hides it; the sync file's date does not change; A shows no hint.
3. **holzBar's own placement on macOS 26.** Same on A: the new item moves to Hidden, the file's date
   stays, B shows nothing.
4. **Restart stays Restart.** Change a setting on A. B shows "Settings changed on another Mac" with
   Restart. Launch a new menu bar app on B so holzBar places it: still Restart. Click Restart: B gets
   A's setting and the new app stays hidden.
5. **User changes still count.** With a Restart hint on B, drag an item to another section in B's
   Layout pane: after about 5 s the hint reads "Choose Settings…". Apply a layout profile or import
   settings on a Mac: the other Mac of the same version (if available) gets a hint; A and B never get
   one for each other's layout alone.
6. **Each version's layout stays its own.** Drag an item on A: B shows no hint, and after B's next
   launch `ItemSections` on B equals A's. Drag an item on B: `MacOS27Layout` on A follows after A's
   next launch; changing a setting on A afterwards and clicking Restart on B leaves B's layout as it
   is (no older copy).
7. **Upgrade.** From the previous build with sync on, update both Macs and launch them: no question
   when their settings are equal apart from the layouts; at most one silent write per Mac.
7a. **Upgrade, same macOS version (if available).** Two Macs on the same macOS version (C and D),
   sync on, on 0.0.7 beta 1. Let holzBar place a new app on D only, so the layouts differ only by
   that placement. Update C, launch it and move one item to another section in its Layout pane (C
   writes and lists its layout; the other settings stay equal). Update D and launch it: no
   question, no hint; D's `ItemSections` (`MacOS27Layout` on macOS 27) equals C's, plus D's newly
   placed app if C has never seen it.
8. **Two Macs of the same version (if available).** Place a new app on one Mac, change a setting on
   the other, click Restart on the first: the newly placed app stays hidden.
9. **Rejoin after the folder's layout changed (same macOS version, if available).** On C, turn sync
   off without dragging anything. On D, rearrange an item in the Layout pane (D writes). On C, turn
   sync on again with the folder: no question; the hint reads "Settings changed on another Mac" with
   Restart. Click Restart: C has D's arrangement. Drag an item on C afterwards: D gets a quiet
   Restart hint and keeps its arrangement until it restarts; nothing of D's is lost.
10. **Earlier build in the folder (only if a Mac on 0.0.7 beta 1 is at hand).** Delete the sync
   file, then let A (this build, macOS 26) write it by changing a setting: the file holds
   `MacOS27Layout` (A's copy) but `currentLayouts` lists only `ItemSections`
   (`plutil -p <folder>/holzBar/Settings.plist`). A macOS 27 Mac on beta 1 that applies it keeps a
   layout.

## Threat surface

No surface beyond the plan's threat model: `currentLayouts` in the sync file (T-SA05-01) and the new
local keys under the `SettingsSync` prefix, which are never exported, imported, synced or logged
(T-SA05-03). No log line carries a digest, count, hash or id.

## Self-Check: PASSED

- Created file exists: `Tests/HolzBarCoreTests/SettingsSyncLayoutTests.swift`.
- Commits `4c5e3539`, `422bba40`, `d41ca102`, `ab2aad45`, `fde070f9` and `b5b9959f` are ancestors of
  HEAD.
