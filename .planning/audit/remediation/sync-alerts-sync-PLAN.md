---
phase: audit-remediation-sync-alerts
plan: sync
type: execute
wave: 1
depends_on: []
files_modified:
  - holzBar/Core/Defaults.swift
  - holzBar/Core/SettingsSyncPolicy.swift
  - holzBar/Core/SettingsSyncFile.swift
  - holzBar/Core/SettingsSyncDevice.swift
  - holzBar/Utilities/SettingsBackup.swift
  - holzBar/Utilities/SettingsSync.swift
  - holzBar/Resources/Localizable.xcstrings
  - Tests/HolzBarCoreTests/SettingsSchemaTests.swift
  - Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
  - Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
  - Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift
autonomous: true
requirements: [F-02, F-15, F-38, F-60]

estimate:
  tokens: 220000
  raw_tokens: 220000
  tasks: 6
  confidence: low

must_haves:
  truths:
    - "Turning sync on (Turn On…) or changing the folder (Change…) on a Mac whose settings differ from another Mac's file in that folder writes nothing and asks with three buttons: Use Settings from Sync Folder, Keep This Mac's Settings, Cancel (F-02 a, D-01, D-04)"
    - "Launching holzBar with sync on and no setting changed writes nothing to the sync file, so no other Mac is prompted (F-02 b, D-07, D-10)"
    - "After Later, no push overwrites the newer version from another Mac; pushes stay paused and holzBar asks again after the next launch (F-02 c, D-04, D-11)"
    - "AppDelegate.init waits at most about 1 s for the sync file and never for an online-only (dataless or not current) file; push, the post-launch check and the folder setup do no file I/O on the main thread (F-15, D-15, D-16)"
    - "A Mac whose preferences were copied by Migration Assistant, a restore or a clone gets a new sync id and joins the folder again (F-38, D-17)"
    - "Applying synced settings never removes a local key; importing a settings file still replaces all settings (F-60, D-18)"
    - "No sync alert calls runModal() inside a Task or async function (D-19)"
  artifacts:
    - path: holzBar/Core/SettingsSyncPolicy.swift
      provides: "Pure sync decision logic: canonical digests, learned keys, learned-key merge, needsExchange, decide"
    - path: Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift
      provides: "Swift Testing coverage of every row of the decision table and of digest stability"
    - path: holzBar/Utilities/SettingsSync.swift
      provides: "Join, check, push and launch flows on top of SettingsSyncPolicy; off-main file I/O; conflict and restart prompts; device identity check"
    - path: holzBar/Utilities/SettingsBackup.swift
      provides: "apply(_:removesMissingKeys:)"
    - path: holzBar/Core/SettingsSyncDevice.swift
      provides: "Hardware-identity check (salted SHA-256), salt creation"
    - path: holzBar/Resources/Localizable.xcstrings
      provides: "Four new strings in en, de, fr, it, rm"
  key_links:
    - from: "SettingsSync.pullIfNeeded (AppDelegate.init)"
      to: "SettingsSyncPolicy.decide(.launch, …)"
      via: "bounded background read, then silent apply / adopt / mark pending; never a prompt"
    - from: "SettingsSync exchange on the serial file queue"
      to: "SettingsSyncPolicy.decide"
      via: "decision made inside one coordinated read-and-write, so the read and the write see the same file"
    - from: "SettingsSync (every sync apply)"
      to: "SettingsBackup.apply(_:removesMissingKeys:)"
      via: "always false from sync; true only from importFromFile"
    - from: "SettingsSync.verifyDeviceIdentity"
      to: "SettingsSync.deviceID"
      via: "runs before the first use of the id at launch (sync on) and in chooseFolder"
---

# Audit remediation plan: chain "sync-alerts", part "sync" (F-02, F-15, F-38, F-60)

> **Scope note.** The user message relayed with this run ("Können wir das mit dem signieren nicht
> doch anders lösen?") is about release signing. Signing belongs to the `release` chain
> (decision `decisions/release-1.md`, findings F-05, F-10, F-11, F-52, F-53, F-54) and is **not**
> touched by this part. The executor must not change anything related to signing, release
> workflows or secrets. The orchestrator should route that question back to the maintainer.

Paths used below:

- `WT` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad/wt2/sync-alerts` (the only tree to change; branch `audit-manual/sync-alerts`)
- `S` = `/private/tmp/claude-503/-Users-cheidenreich-privat/252b2ff3-57b9-4b08-80f5-c50bb91c25a1/scratchpad` (scratch files, build folders, tools)

Never touch `/Users/cheidenreich/privat/holzBar` or another worktree, never switch branches, never
push, never run a writing `gh` command, never quit or relaunch holzBar, never change system state.
Do not edit README.md, docs/, SECURITY.md, release notes or CLAUDE.md (see "Doc updates needed").

<objective>
Implement the maintainer's decision **"Nachfragen bei Konflikt"** (ask on conflict) for the
settings-sync cluster, exactly as the implementation note in
`S/decisions/sync-1.md` describes, in three atomic commits:

1. F-60: sync applies settings without removing local keys.
2. F-02 + F-15 (tightly coupled, same functions): holzBar never overwrites another Mac's settings
   unasked, writes only real changes, reads before every write inside one coordinated access, keeps
   every sync file access off the main thread, bounds the launch read, and asks with one new
   three-button alert when two Macs' settings conflict.
3. F-38: the sync id is bound to the Mac by a salted SHA-256 of the hardware UUID; a copied Mac
   re-identifies and joins again.

Purpose: F-02 is a high-severity data-loss bug (joining a folder, every launch and "Later" all
overwrite other Macs' settings); F-15 blocks launch and the UI on online-only files and stalled
volumes; F-38 makes Migration-Assistant Macs ignore each other; F-60 deletes the per-OS layout
between macOS 26 and 27 Macs.

Output: one new Core file with tests, changes in five existing source files, four new catalog
strings, three commits on `audit-manual/sync-alerts`, a report with doc_updates_needed.
</objective>

<execution_context>
@~/.claude/gsd-core/workflows/execute-plan.md
@~/.claude/gsd-core/templates/summary.md
</execution_context>

<context>
@WT/CLAUDE.md
@S/decisions/sync-1.md
@S/decisions/modal-alerts-1.md
@WT/.planning/audit/FULL-AUDIT-2026-10-05.md (sections "#### F-02", "#### F-14", "#### F-15", "#### F-18", "#### F-38", "#### F-60", "#### F-61")
@WT/holzBar/Utilities/SettingsSync.swift
@WT/holzBar/Utilities/SettingsBackup.swift
@WT/holzBar/Core/SettingsSyncFile.swift
@WT/holzBar/Core/SettingsSyncDevice.swift
@WT/holzBar/Core/SettingsSyncLocation.swift
@WT/holzBar/Core/Defaults.swift (Keys, settingsKind, localOnlyKeys, importableKinds, validatedSettings)
@WT/holzBar/Core/BlockingWork.swift
@WT/holzBar/Main/AppDelegate.swift
@WT/holzBar/Main/AppState.swift (setupTask: settingsSync.performSetup)
@WT/holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift (SettingsSyncToggle)
@WT/Tests/HolzBarCoreTests/SettingsSyncFileTests.swift
@WT/Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift
@WT/Tests/HolzBarCoreTests/SettingsSchemaTests.swift
@WT/.github/scripts/strings-check.py
</context>

## 1. The maintainer's decision, as implemented here

Chosen: **Nachfragen bei Konflikt (Recommended)**. Rejected: "Ordner hat immer Vorrang", "Pro
Einstellung zusammenführen". The decision items below (D-xx) are numbered from the implementation
note and the common base in `sync-1.md`; every task cites the items it implements.

| ID | Decision item (from sync-1.md) |
|----|-------------------------------|
| D-01 | A conflict is (a) joining (Turn On…, Change…, or a re-identified Mac) with a foreign file whose user settings differ from this Mac's, or (b) a newer foreign version arriving while this Mac has user changes since the base. It shows one new alert with three buttons. |
| D-02 | "Use Settings from Sync Folder" applies without removing keys and relaunches. |
| D-03 | "Keep This Mac's Settings" pushes and sets base = local. |
| D-04 | Third button: "Cancel" when joining (sync stays off, or the previous folder is kept); "Later" otherwise (the version stays pending, pushes stay paused, holzBar asks again after the next launch). |
| D-05 | At launch, apply silently only when there are no user changes since the base; otherwise ask once setup is done, never in AppDelegate.init. |
| D-06 | Without a conflict keep today's flow: silent apply at launch, the existing Restart/Later prompt while running. |
| D-07 | Remove the push from `isEnabled.didSet`. |
| D-08 | Base: canonical SHA-256 (CryptoKit, sorted-key encoding, not binary-plist bytes) of the last pushed or applied settings, in a local `SettingsSync*` key. |
| D-09 | Skip a write whose content equals the file's; skip the restart prompt when the remote user settings equal this Mac's, then only update base and last-synced. |
| D-10 | Read the file before every push and in chooseFolder, off the main actor; exit early without reading when the local hash equals the base and nothing is pending. |
| D-11 | Never overwrite a newer, unapplied foreign version: persist it as pending and pause pushes. |
| D-12 | Learned keys (KnownItemTags, KnownApplications27, TitleChangingItemOwners, MacOS27LayoutSeeded, hasMigrated*, HasImportedIceSettings) never trigger a prompt or conflict; union string arrays, OR flags, merge learned-only remote changes silently at the next launch. |
| D-13 | Decision logic is a pure type in holzBar/Core next to SettingsSyncFile, with Swift Testing tests (join: no file, own, equal, differing; remote newer with and without local changes; learned-only; pending blocks push; re-identification; apply without removal; hash stable across key order). |
| D-14 | Existing installs without a base are treated as joining. |
| D-15 | F-15 push: build the plist on the main actor; lstat, createDirectory (also the one in updateObservers) and the coordinated write run in a serialized `@concurrent nonisolated` function; base and last-synced are published back on the main actor. |
| D-16 | F-15 launch: read only a file that is not dataless (`st_flags & SF_DATALESS`) and, if ubiquitous, `.current`; read on a background queue with a ~1 s bound, cancel the coordinator on timeout; otherwise skip and run one background check after setup. |
| D-17 | F-38: random salt + salted SHA-256 of the hardware UUID beside `SettingsSyncDeviceID`; mismatch → new id, clear last-synced, base and pending; no hash yet → store it, rotate the id once, keep last-synced; never log or sync the hash; document it (docs → handed off). |
| D-18 | F-60: `SettingsBackup.apply(_:removesMissingKeys:)`, false for sync, true for file import. |
| D-19 | Never call `runModal()` inside a main-actor Task (F-14); use `RunLoop.main.perform` or a sheet. |
| D-20 | New local keys start with "SettingsSync"; persisted keys are never renamed. |
| D-21 | New strings in en, de (Swiss spelling), fr, it, rm, machine-written; `strings-check.py` passes. |
| D-22 | Release notes of the next beta (handed off, see section 9: this run must not edit release notes). |
| D-23 | The two-Mac human check stays recorded as open (section 8). |

**Interpretations (Claude's discretion, documented):**

- **Re-identified Mac and install without a base (D-01, D-04, D-14).** Both are "joining" (base is
  absent). The decision gives joining the "Cancel" button; for these launch-time joins Cancel turns
  sync off on this Mac (the "sync stays off" outcome; there is no previous folder to keep). This is
  the literal reading. If the maintainer prefers "Later" there, only `SyncPrompt.thirdButton` and
  `cancelJoin()` change (one line each).
- **Learned-only local changes do not push by themselves (D-10, D-12).** The early exit compares the
  *user* digest (learned keys excluded) with the base, so holzBar's own writes of KnownItemTags,
  KnownApplications27 and TitleChangingItemOwners no longer rewrite the file (they caused the
  ping-pong of F-02 b/c). Learned values travel with the next user change: every write puts the
  union of this Mac's and the file's learned values into the file, and every launch (when the Mac is
  not joining) unions the file's learned values into the local defaults. Union and OR are idempotent
  and these keys only ever grow (verified: SectionRestore, Concealer27, MenuBarItemManager write
  unions or set flags to true), so nothing is lost.
- **"Content equals the file's" (D-09)** is decided on the user digest: when the user settings are
  equal, nothing is written and the version is adopted (base and last-synced only).
- **JSON inside Data values is canonicalised for the digest (D-08).** LayoutProfiles, ItemGroups,
  appearance and hotkeys are stored as JSONEncoder output without `.sortedKeys`; a model that
  re-saves the same value can change the byte order of dictionary keys. The digest parses Data that
  is JSON and hashes the parsed structure with sorted keys, so a re-save does not look like a change
  (otherwise launches would push again and re-create F-02 b).
- **Equality is exact** (not "remote is a subset"). Because sync no longer removes keys (F-60), a
  Mac that applied a file keeps keys the file lacks, so after an apply the base is the digest of the
  local settings *after* the apply, not the file's digest.

## 2. Coordination with chain part "alerts" (F-14, decision modal-alerts-1.md)

- The chain is "sync-alerts"; F-14 ("Sheets und stiller Hinweis") is the other part. It turns the
  sync restart alert into a quiet notice and Settings alerts into sheets, and relies on "the push
  guard while settings from another Mac are pending". This part provides that guard (persisted
  pending + paused pushes, section 3).
- This part presents its alerts without `runModal()` in a Task: the join conflict as a sheet on the
  window that showed "Turn On…"/"Change…" (Settings window, consistent with F-14's sheets), every
  windowless prompt (running conflict, restart prompt) through a private run-loop presenter
  (`RunLoop.main.perform(inModes: [.default])` + `MainActor.assumeIsolated`, the pattern F-14's probe
  verified). The existing restart prompt keeps its strings and Restart/Later semantics (D-06); the
  alerts part may later replace it with its notice and replace the private presenter with its shared
  helper.
- **Task 0 checks the order**: if `git -C WT log --oneline --grep='F-14'` already shows an F-14
  commit, reuse its helper(s) instead of adding the private presenter, and keep its notice as the
  non-conflict prompt (its "use now" action = apply the captured version and relaunch; dismissing it
  = Later). Expected: no F-14 commit yet (this branch equals the base, `7e7ed6bf`).

## 3. Design (read before coding)

### 3.1 Persisted local state (all raw `UserDefaults.standard` keys, D-20)

| Key | Type | Meaning | Exists |
|-----|------|---------|--------|
| `SettingsSyncDeviceID` | String | random UUID written into the file | yes, unchanged |
| `SettingsSyncLastSynced` | Date | `modified` of the last file this Mac wrote or applied/adopted | yes, unchanged |
| `SettingsSyncFolderBookmark` | Data | chosen folder | yes, unchanged |
| `SettingsSyncBaseDigest` | String (hex) | user digest of the settings last pushed or applied (D-08); absent = joining (D-14) | new (commit B) |
| `SettingsSyncPendingModified` | Date | `modified` of a newer foreign version that waits for a decision; while set, pushes are paused (D-11) | new (commit B) |
| `SettingsSyncDeviceSalt` | Data (32 random bytes) | salt of the hardware hash (D-17) | new (commit C) |
| `SettingsSyncDeviceHash` | String (hex) | SHA-256(salt ‖ UTF-8 hardware UUID) (D-17) | new (commit C) |

All start with "SettingsSync", so `SettingsBackup.excludedKeyPrefixes` keeps them out of export,
import and sync; they are not `Defaults.Key` cases, so `currentSettings()` never contains them. In
memory only: `postponed: Date?` (the version the user answered "Later" for in this session).

### 3.2 Digests and learned keys (Core, `SettingsSyncPolicy`)

- `learnedKeys` = raw values of `.knownItemTags`, `.knownApplications27`, `.titleChangingItemOwners`,
  `.macOS27LayoutSeeded`, the six `.hasMigrated…` keys and `.hasImportedPreviousSettings`.
- `userDigest(of:)` = `digest(of: userSettings(Defaults.Key.validatedSettings(settings).accepted))`
  where `userSettings` drops the learned keys. Validation also drops non-importable keys (so
  `SyncsSettingsWithICloud`) and clamps numbers, identically for local and remote settings.
- `digest(of:)`: SHA-256 (CryptoKit `SHA256` hasher) over a canonical, type-tagged,
  length-prefixed encoding: dictionaries with keys sorted; arrays in order; strings as UTF-8;
  CFBoolean as a bool (checked before numbers, `CFGetTypeID == CFBooleanGetTypeID()`); other
  numbers as Int64 when integral (so 1 and 1.0 are equal) else the Double bit pattern; Data that
  `JSONSerialization` parses into a dictionary or array as that parsed structure, other Data as
  bytes; Date as its reference-date bit pattern. Lower-case hex string.
- `learnedSettings(merging remote:, into local:)` returns only the learned keys whose merged value
  differs from the local one: string arrays → sorted union (a remote value that is not `[String]`
  is ignored); bools → `local || remote`. The kind comes from `Defaults.Key(rawValue:)?.settingsKind`.
- `settingsToApply(_ remote:, over local:)` = remote minus learned keys, plus
  `learnedSettings(merging: remote, into: local)`.
- `settingsToWrite(_ local:, file remote:)` = local, with `learnedSettings(merging: remote, into: local)`
  overriding (remote may be nil → local unchanged).

### 3.3 Decision table (Core, `SettingsSyncPolicy.decide(_:local:file:)`, D-01…D-14)

Inputs: `trigger` (`.launch` in AppDelegate.init, `.check` after the file changed or after setup,
`.localChange` for a push); `local` = user digest, `base` (nil = joining), `pending`, `postponed`,
`forcesWrite` ("Keep This Mac's Settings"); `file` = `.missing`, `.unusable` (too large, not a
regular file, or no date/settings: holzBar may write over it, as today), `.unreadable` (coordination
error, I/O error; never write), or `.version(isFromThisMac, modified, isNewer, userDigest)` where
`isNewer` = foreign, later than last-synced and at most `allowedClockSkew` in the future (the
existing `SettingsSyncFile` rule). `localChanged` = base is nil or differs from the local user digest.

Rows are evaluated in order; the first match wins:

| # | Condition | Action |
|---|-----------|--------|
| 1 | file unreadable | `.retry` |
| 2 | file missing or unusable | `.none` at launch; otherwise `.write` if joining, forced or `localChanged`, else `.none` |
| 3 | version with user digest equal to the local one | `.adopt` (no write, no prompt; D-09) |
| 4 | `forcesWrite` | `.none` at launch, else `.write` (D-03) |
| 5 | version is this Mac's own | `.write` if `localChanged` and not launch, else `.none` |
| 6 | joining (base nil) | `.ask` (conflict a; D-01, D-14) |
| 7 | version not newer (already handled, or dated too far ahead) | `.write` if `localChanged` and not launch, else `.none` |
| 8 | not launch, `postponed` set and version `modified <= postponed` | `.wait` (D-04 Later: no new question this session) |
| 9 | `localChanged` | `.ask` (conflict b; D-01) |
| 10 | otherwise (newer foreign, no local changes) | `.apply` (D-05, D-06) |

`needsExchange(_:local:)` (D-10, D-11): `.localChange` → false while `pending` is set (pushes
paused) or when base equals the local user digest (early exit, nothing read); true otherwise.
`.check`, `.launch` and forced writes → true.

### 3.4 What the app does with each action

| Action | launch (`pullIfNeeded`, AppDelegate.init) | running (`.check` / `.localChange`) | UI join (`chooseFolder`) |
|--------|---------------------|---------------------|----------------------|
| `.none` | clear pending; learned union (base set) | clear pending | n/a (base nil ⇒ rows 2/5 write) |
| `.wait` | n/a | nothing | n/a |
| `.retry` | nothing (an unreadable file at launch is treated like a skipped read; the post-setup check retries) | log, nothing; next trigger retries | commit folder with base, pending and last-synced removed (stays a join), enable |
| `.adopt` | base = local digest, last-synced = max(last, modified), clear pending; learned union | same | commit folder, same state updates, enable |
| `.write` | never (rows 2/4/5/7 exclude launch) | `.localChange`/forced: written inside the exchange → base = digest of what was written, last-synced = written date, clear pending; `.check`: request a `.localChange` exchange instead | written into the candidate folder inside the exchange, then commit + enable + same state updates |
| `.apply` | **silent apply** (D-05): `SettingsBackup.apply(settingsToApply, removesMissingKeys: false)`, base = user digest of the settings after the apply, last-synced = modified, clear pending | persist pending = modified, show the existing **Restart/Later** prompt (D-06) | n/a (joining asks) |
| `.ask` | persist pending = modified, nothing else; the post-setup check asks (D-05) | persist pending = modified, show the **conflict alert**, third button Later, or Cancel when base is nil | show the **conflict alert as a sheet**, third button Cancel; nothing is committed before the answer |

Alert answers (D-02, D-03, D-04):

- **Use Settings from Sync Folder** / **Restart**: apply the captured version with
  `settingsToApply` and `removesMissingKeys: false`; base = user digest after the apply; last-synced =
  modified; clear pending and postponed; on a UI join also store the bookmark and set
  `SyncsSettingsWithICloud` to true; then `SettingsBackup.relaunch()`.
- **Keep This Mac's Settings**: on a UI join first commit the folder (store bookmark, enable); then a
  forced exchange (`forcesWrite`, base nil on a join) writes; base, last-synced and pending update
  from its result.
- **Cancel** (joining): UI join → nothing changes (the bookmark was never stored; sync stays off or
  keeps the previous folder). Launch-time join (base nil while sync is on) → `isEnabled = false`.
- **Later** (not joining): `postponed` = modified; pending stays persisted; pushes stay paused.

While a prompt is open (`isAsking`), checks are skipped and remembered; when the prompt closes with
anything but a relaunch, one check runs. Pending is persisted *before* a prompt is scheduled, so the
defaults observer and the debouncer, which now keep running during the prompt (F-14 note 4), cannot
push over the version being asked about.

### 3.5 File access (F-15, D-15, D-16)

- One serial queue `fileQueue` (`DispatchQueue(label: "com.holzcloud.holzBar.SettingsSync", qos: .utility)`)
  carries every sync file access: launch read, checks, exchanges, folder preparation. Async callers
  use `BlockingWork.run(on: fileQueue)` from a `@concurrent private nonisolated static` function, so
  neither the main thread nor the Swift concurrency pool blocks, and accesses never overlap.
- On the main actor, one exchange at a time (`exchangeTask`); requests during an exchange coalesce
  into one follow-up (forced write before check before push) and run with fresh state afterwards.
- **Push / forced / UI join**: one `NSFileCoordinator(filePresenter: presenter)` call of
  `coordinate(readingItemAt:options:writingItemAt:options: .forReplacing, error:byAccessor:)` on the
  same URL. Inside the accessor: read (`SettingsSyncFile.readContents`), parse, `decide`, and only on
  `.write` create the holzBar folder and write the XML plist `.atomic`. The read and the write see
  the same file (closes the lost-update window for coordinated writers such as iCloud Drive).
  `isUsableFolder` (lstat) runs first on the queue; a link or file → `.retry` with the existing log.
- **Check**: read-only coordination on the queue; never writes (a `.write` decision requests a
  `.localChange` exchange).
- **Launch** (`pullIfNeeded`, synchronous in AppDelegate.init): enqueue on `fileQueue` a block that
  checks availability (holzBar folder usable; file: ENOENT → missing; `SF_DATALESS` in `st_flags`
  from `lstat` → not local; `isUbiquitousItem == true` and `ubiquitousItemDownloadingStatus != .current`
  → not local) and only then does the coordinated read with a coordinator created *outside* the block
  (boxed in a tiny `@unchecked Sendable` holder). Wait on a `DispatchSemaphore` for 1 s; on timeout
  call `coordinator.cancel()` and return nil (verified on this host: `cancel()` makes a stuck
  coordinated read return NSUserCancelledError, `S/syncplan-probe/cancel`). Not local or timed out →
  skip; the post-setup check handles it later ("die Neustart-Frage kommt dann später").
- **Folder setup** (`updateObservers`): the lstat check, `createDirectory` and the folder watcher's
  `open(O_EVTONLY)` run on `fileQueue`; back on the main actor the presenter is added only if sync is
  still on, the folder is still the same and no presenter exists.

### 3.6 Failure scenarios and how they close

| Finding | Failure scenario (audit) | Closed by |
|---------|--------------------------|-----------|
| F-02 a | Turn On…/Change… on Mac B writes B's defaults over A's file; A adopts them | chooseFolder reads first (exchange, off main); differing foreign file → conflict sheet; nothing written before "Keep This Mac's Settings" (rows 2–6, D-01, D-10) |
| F-02 b | Every launch pushes (didSet false→true, `lastPushedData` nil) → other Macs prompt, ping-pong, stale Mac overwrites newer file | push removed from didSet (D-07); early exit on user digest == base (D-10); apply sets base so the receiver never pushes back (D-08); read-before-write in one coordination (D-10) |
| F-02 c | After "Later", the next push (also holzBar's own learned-key writes) overwrites the pending version | pending persisted, `needsExchange` pauses pushes (D-11); learned keys never trigger pushes (D-12); asked again after next launch (row 9 with `postponed` nil) |
| F-15 | AppDelegate.init blocks on a dataless/hung/stalled file; push and folder setup block the main thread | bounded background launch read, skip non-local files, cancel on timeout (D-16); all other access on `fileQueue` via `@concurrent` + BlockingWork (D-15) |
| F-38 | Migration Assistant copies `SettingsSyncDeviceID`; both Macs treat each other's files as their own | salted hardware hash; mismatch → new id, clear last-synced, base, pending → join (D-17) |
| F-60 | A macOS 26 file deletes MacOS27Layout/seeded flag on a 27 Mac (and ItemSections the other way) | sync applies with `removesMissingKeys: false` (D-18); learned flags OR-merged (D-12) |

<interfaces>
Signatures to create (names are binding; bodies are the executor's). Core types are `nonisolated`
(the Core target's default isolation is MainActor and the exchange calls them off the main actor).

```swift
// holzBar/Core/Defaults.swift — inside `nonisolated extension Defaults.Key` (commit A)
static func keysRemoved(applying accepted: [String: Any], over current: [String: Any], removesMissingKeys: Bool) -> [String]

// holzBar/Utilities/SettingsBackup.swift (commit A)
@discardableResult
static func apply(_ settings: [String: Any], removesMissingKeys: Bool) -> [String]

// holzBar/Core/SettingsSyncPolicy.swift (new, commit B)
import CryptoKit
import Foundation
nonisolated enum SettingsSyncPolicy {
    static let learnedKeys: Set<String>
    static func userSettings(_ settings: [String: Any]) -> [String: Any]
    static func userDigest(of settings: [String: Any]) -> String
    static func digest(of settings: [String: Any]) -> String
    static func learnedSettings(merging remote: [String: Any], into local: [String: Any]) -> [String: Any]
    static func settingsToApply(_ remote: [String: Any], over local: [String: Any]) -> [String: Any]
    static func settingsToWrite(_ local: [String: Any], file remote: [String: Any]?) -> [String: Any]

    nonisolated enum Trigger: Sendable { case launch, check, localChange }
    nonisolated struct Local: Equatable, Sendable {
        var userDigest: String
        var base: String?
        var pending: Date?
        var postponed: Date?
        var forcesWrite: Bool
        var isJoining: Bool { base == nil }
    }
    nonisolated struct Version: Equatable, Sendable {
        var isFromThisMac: Bool
        var modified: Date
        var isNewer: Bool
        var userDigest: String
    }
    nonisolated enum File: Equatable, Sendable { case missing, unusable, unreadable, version(Version) }
    nonisolated enum Action: Equatable, Sendable { case none, wait, retry, adopt, write, apply, ask }

    static func needsExchange(_ trigger: Trigger, local: Local) -> Bool
    static func decide(_ trigger: Trigger, local: Local, file: File) -> Action
}

// holzBar/Core/SettingsSyncFile.swift (commit B)
nonisolated struct Contents { let modified: Date; let isFromThisMac: Bool; let isNewer: Bool; let settings: [String: Any] }
static func contents(of file: [String: Any], lastSynced: Date?, deviceID: String, computerName: String?, localKeys: Set<String>, now: Date = .now) -> Contents?
static func isLocal(flags: UInt32, isUbiquitous: Bool?, downloadingStatus: URLUbiquitousItemDownloadingStatus?) -> Bool
// newerSettings(in:…) stays and is re-expressed through contents(of:…) so its tests keep passing.

// holzBar/Core/SettingsSyncDevice.swift (commit C)
nonisolated enum Identity: Equatable, Sendable { case same, firstSeen, otherMac, unknown }
static func identity(storedHash: String?, salt: Data?, hardwareID: String?) -> Identity
static func hardwareHash(of hardwareID: String, salt: Data) -> String
static func makeSalt() -> Data   // 32 bytes from SymmetricKey(size: .bits256)
```

App-target names in `SettingsSync.swift` (private unless noted): `baseKey`, `pendingKey`,
`deviceSaltKey`, `deviceHashKey`, `fileQueue`, `syncedSettings()`, `readForLaunch(at:)`,
`inspect(_:lastSynced:deviceID:computerName:)` (nonisolated; turns a `ReadResult` into a
`SettingsSyncPolicy.File` plus the file's settings, shared by launch, check and exchange),
`ExchangeKind` (`.check`, `.push`, `.keepThisMac`), `ExchangeRequest`, `ExchangeResult`, `RemoteVersion` (modified + binary-plist `Data` of the file's
settings, Sendable), `exchange(_:)` (`@concurrent nonisolated static`), `requestExchange(_:)`,
`SyncPrompt` (`.restart(RemoteVersion)`, `.conflict(RemoteVersion, isJoining: Bool)`),
`scheduleWindowlessPrompt(_:)`, `makeAlert(for:)`, `JoinRequest`, `postponed`, `isAsking`,
`static func verifyDeviceIdentity()` (internal), `hardwareUUID()` (IOKit).
</interfaces>

<tasks>

<task type="auto">
  <name>Task 0: Pre-flight and baselines (no commit)</name>
  <files>(none changed)</files>
  <read_first>S/decisions/sync-1.md, S/decisions/modal-alerts-1.md, WT/CLAUDE.md, this plan's sections 1–3</read_first>
  <action>Confirm `git -C WT branch --show-current` is `audit-manual/sync-alerts` and `git -C WT status --short` shows nothing but this untracked plan (`?? .planning/audit/remediation/`); the plan file is never staged or committed. Run `git -C WT log --oneline --grep='F-14'`: if it prints a commit, read that commit's diff and apply section 2's alternative (reuse its run-loop helper and notice) everywhere this plan says "private run-loop presenter" or "Restart/Later prompt"; otherwise follow the plan as written. Record baselines for the gates in section 7: G1 swift test (all pass), G2 strings-check (exit 0), G3 privacy-check network and logs (exit 0), G4 swiftlint (exit 0), G5 appcheck (measured while planning: ERRORS 0, EXIT 0 on 7e7ed6bf). Do not mention the relayed signing question in code or commits; it is out of scope (scope note).</action>
  <verify><automated>git -C WT status --short | grep -v '^?? .planning/audit/remediation/' | wc -l   # expect 0; then run G1–G5 from section 7 and note their results</automated></verify>
  <done>Branch and clean tree confirmed, F-14 order known, all five gates green on the untouched tree.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 1: F-60 — sync applies without removing keys (commit A)</name>
  <files>holzBar/Core/Defaults.swift, holzBar/Utilities/SettingsBackup.swift, holzBar/Utilities/SettingsSync.swift, Tests/HolzBarCoreTests/SettingsSchemaTests.swift</files>
  <read_first>holzBar/Utilities/SettingsBackup.swift (apply, importFromFile), holzBar/Utilities/SettingsSync.swift (pullIfNeeded), holzBar/Core/Defaults.swift (validatedSettings), Tests/HolzBarCoreTests/SettingsSchemaTests.swift</read_first>
  <behavior>
    - keysRemoved(applying: ["A": 1], over: ["A": 0, "B": 1], removesMissingKeys: false) == []
    - keysRemoved(applying: ["A": 1], over: ["A": 0, "B": 1, "C": 2], removesMissingKeys: true) == ["B", "C"] (sorted)
    - a key in both is never removed
  </behavior>
  <action>Per D-18. Add `Defaults.Key.keysRemoved(applying:over:removesMissingKeys:)` next to `validatedSettings` in Defaults.swift: the keys of `current` that `accepted` lacks, sorted, when `removesMissingKeys`; an empty array otherwise; doc comment says sync keeps keys the sending Mac never had (F-60: per-OS keys such as MacOS27Layout, MacOS27LayoutSeeded, KnownApplications27, ItemSections). Change `SettingsBackup.apply(_:)` to `apply(_ settings:, removesMissingKeys: Bool)` (keep @discardableResult and the return value); it removes exactly `keysRemoved(applying: accepted, over: currentSettings(), removesMissingKeys:)` and sets the accepted values as before; update its doc comment ("Applies the given settings; a file import also removes…"). In `importFromFile` pass `true` for removesMissingKeys (import still replaces everything). In `SettingsSync.pullIfNeeded` pass `false`. Add the three behaviours as `@Test`s in SettingsSchemaTests (suite style of the file). Nothing else changes in this commit.</action>
  <verify><automated>cd WT && swift test --scratch-path S/build-sync-alerts --filter SettingsSchema 2>&1 | tail -3</automated></verify>
  <acceptance_criteria>
    - `grep -c "removesMissingKeys: false" WT/holzBar/Utilities/SettingsSync.swift` prints at least 1
    - `grep -c "removesMissingKeys: true" WT/holzBar/Utilities/SettingsSync.swift` == 0
    - `grep -c "removesMissingKeys: true" WT/holzBar/Utilities/SettingsBackup.swift` == 1
    - Gates G1–G6 (section 7) pass; commit A made with the message in section 6
  </acceptance_criteria>
  <done>Import still replaces; sync only sets incoming keys; tests prove both; commit A exists.</done>
</task>

<task type="tracer" tdd="true">
  <name>Task 2 (tracer): Core decision spine plus the join path end to end — Turn On…/Change… asks instead of overwriting</name>
  <files>holzBar/Core/SettingsSyncPolicy.swift, holzBar/Core/SettingsSyncFile.swift, Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift, Tests/HolzBarCoreTests/SettingsSyncFileTests.swift, holzBar/Utilities/SettingsSync.swift, holzBar/Resources/Localizable.xcstrings</files>
  <read_first>section 3 of this plan; holzBar/Core/SettingsSyncFile.swift; holzBar/Core/Defaults.swift (Key cases 186–217, settingsKind, importableKinds); holzBar/Core/BlockingWork.swift; holzBar/Utilities/SettingsSync.swift (whole file); Tests/HolzBarCoreTests/SettingsSyncFileTests.swift (style); holzBar/Settings/SettingsPanes/AdvancedSettingsPane.swift (SettingsSyncToggle)</read_first>
  <behavior>
    SettingsSyncPolicyTests (Swift Testing, `@Suite("SettingsSyncPolicy")`, one `@Test` each, D-13):
    - join, no file → .write; join, own file differing → .write; join, foreign file with equal user settings → .adopt; join, foreign file differing → .ask; join, unreadable → .retry
    - running: newer foreign, no local change → .apply; newer foreign, local change → .ask; newer foreign, equal user settings → .adopt
    - learned-only difference (only KnownItemTags/MacOS27LayoutSeeded differ) → equal user digests → .adopt; learnedSettings unions arrays (sorted) and ORs flags and returns nothing when local already holds the union
    - postponed version → .wait; a version newer than postponed → .ask/.apply again; at .launch postponed is ignored
    - needsExchange(.localChange): false with pending set; false with base == user digest; true with base nil or different; true for .check and for forcesWrite
    - forcesWrite over a newer foreign version → .write; forcesWrite with equal user settings → .adopt; forcesWrite at .launch → .none
    - own file, not joining: local change → .write, none → .none; foreign not newer (incl. future-dated) with local change → .write
    - launch never writes: missing file at .launch → .none; own file with local change at .launch → .none
    - digest: same content in different insertion orders → equal; JSON Data with reordered keys → equal; Int 1 vs Double 1.0 → equal; Bool true vs Int 1 → different; one changed value → different; 64 lower-case hex characters
    - settingsToApply keeps all remote user keys, replaces learned keys by the union, and never contains a key only the local side has
    SettingsSyncFileTests additions: contents(of:) reports isFromThisMac/isNewer/future-dated correctly and returns nil without date or settings; isLocal: dataless flag → false, ubiquitous and .notDownloaded or .downloaded → false, ubiquitous .current → true, non-ubiquitous without the flag → true.
  </behavior>
  <action>Implements D-01, D-04 (join half), D-08, D-09, D-10 (chooseFolder half), D-12, D-13, D-14, D-19, D-21.
Core: create SettingsSyncPolicy.swift exactly per the interfaces block and sections 3.2–3.3 (file header per .swiftlint.yml; `import CryptoKit` and `import Foundation`; `nonisolated enum`; doc comments in the style of SettingsSyncFile). Add `SettingsSyncFile.contents(of:…)` and `isLocal(flags:isUbiquitous:downloadingStatus:)`, and re-express `newerSettings(in:…)` through `contents` (existing tests must stay green). Write the tests first (RED), then the code (GREEN).
App, join path only in this task: rewrite `chooseFolder()` so it (1) captures `NSApp.keyWindow` before the open panel, (2) runs the panel as today (synchronous Button action; not a Task), (3) builds a `JoinRequest` from the chosen URL (candidate fileURL = url + `SettingsSyncLocation.fileComponents`) without storing the bookmark, (4) starts a Task that awaits `exchange(_:)` with trigger `.localChange`, a `Local` whose base, pending and postponed are nil (a join ignores the old folder's state), last-synced nil, the candidate fileURL, presenter nil, and the current `syncedSettings()` (binary plist Data) and user digest, (5) handles the result per the "UI join" column of 3.4: `.write`/`.adopt`/`.retry` commit (stopWatchingFolder, store bookmark, remove last-synced/base/pending, then the outcome's state, then `isEnabled = true` or `updateObservers()` when already on); `.ask` presents the conflict alert as a sheet on the captured window via `await alert.beginSheetModal(for:)` when that window is visible, else through the private run-loop presenter. Keep the `@discardableResult … -> Bool` signature (returns whether a folder was chosen; the join continues asynchronously) and update its doc comment. Guard against a second join while one runs.
Add `exchange(_:)` as a `@concurrent private nonisolated static` function that awaits `BlockingWork.run(on: fileQueue)` around a synchronous `performExchange` implementing 3.5's combined coordinated read-and-write; return a Sendable `ExchangeResult` (action, optional `RemoteVersion`, written date, refusal reason for logging). Log on the main actor from the result (existing messages; any interpolated error stays `privacy: .private`, enums `.public`).
Add the alert (`makeAlert(for:)`): messageText `String(localized: "Which settings should holzBar use?")`, informativeText `String(localized: "The sync folder holds settings from another Mac that differ from this Mac's. Using them restarts holzBar; keeping this Mac's settings replaces them in the sync folder.")`, buttons in this order: `String(localized: "Use Settings from Sync Folder")` (default), `String(localized: "Keep This Mac's Settings")`, then the existing "Cancel" (joining) or "Later" key; give the third button the Escape key equivalent as importFromFile does. Implement the answers per 3.4 (Use → apply + relaunch; Keep → commit, forced exchange; Cancel → nothing).
Add the private run-loop presenter `scheduleWindowlessPrompt(_ prompt: SyncPrompt)`: sets `isAsking`, then `RunLoop.main.perform(inModes: [.default])` with a block that calls `MainActor.assumeIsolated` and inside it `NSApp.activate()`, builds the alert with `makeAlert(for:)`, runs it modally and handles the answer; the block captures only `[weak self]` and the Sendable prompt. This is the only place outside the open panel where SettingsSync may run a modal loop.
Strings: add the four new keys to Localizable.xcstrings with the translations in section 5 (load with json, add entries, dump with `indent=2, ensure_ascii=False, separators=(',', ' : '), sort_keys=True` plus a trailing newline; verified while planning that this round-trips the current file byte for byte). Use the straight apostrophe in "Mac's" like the existing "The folder's own app"; Swiss German spelling with "ss" only.</action>
  <verify><automated>cd WT && swift test --scratch-path S/build-sync-alerts --filter 'SettingsSync' 2>&1 | tail -3 && python3 .github/scripts/strings-check.py && zsh S/appcheck.sh WT sync-t2 | tail -1</automated></verify>
  <acceptance_criteria>
    - All SettingsSyncPolicy and SettingsSyncFile tests pass; existing newerSettings tests unchanged and green
    - `grep -n "runModal()" WT/holzBar/Utilities/SettingsSync.swift | grep -v '//' | wc -l` prints 2: the open panel in chooseFolder and the alert inside the run-loop presenter (review both lines)
    - strings-check exit 0; `grep -c 'ß' WT/holzBar/Resources/Localizable.xcstrings` == 0
    - appcheck prints `ERRORS: 0  EXIT: 0`
  </acceptance_criteria>
  <done>Joining a folder with a differing foreign file shows the three-button alert and writes nothing before the answer; joining an empty, own or equal folder needs no question; the decision table is fully tested. No commit yet (commit B follows Task 4).</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Running paths — no launch push, read-before-push, pending, learned keys, restart prompt, folder setup off main</name>
  <files>holzBar/Utilities/SettingsSync.swift, Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift</files>
  <read_first>holzBar/Utilities/SettingsSync.swift (as changed by Task 2), section 3.4–3.5, holzBar/Main/AppState.swift lines 140–170</read_first>
  <behavior>
    - (Core, already covered in Task 2) any new edge found while wiring gets a test before the fix
  </behavior>
  <action>Implements D-03, D-04 (Later half), D-06, D-07, D-09, D-10, D-11, D-12, D-15, D-19.
`isEnabled.didSet`: keep `Defaults.set` and `updateObservers()`; remove the push call (D-07) and write no comment in the didSet that contains the push call text; when it changes from true to false, remove base and pending and clear `postponed`, cancel `exchangeTask`, and forget queued exchanges.
`performSetup`: after assigning `isEnabled`, when sync is on call `syncFileDidChange()` once (the one background check after setup, D-16; it already waits 2 s).
Remove the old push function, its cache of the last pushed bytes, the asking-to-restart flag, the instance helper that decoded newer settings, the `@concurrent` background read helper and the old check-and-restart function; replace them with: `settingsDidChange()` (public name kept; callers in ItemChangeWatcher, ItemIconStore, LayoutProfiles) → `requestExchange(.push)`; `requestExchange(_ kind: ExchangeKind)` (`.check`, `.push`, `.keepThisMac`, mapped to the Core triggers `.check`, `.localChange`, `.localChange` with `forcesWrite`) builds `SettingsSyncPolicy.Local` on the main actor (user digest of `syncedSettings()`, base and pending from defaults, `postponed`), returns early when `needsExchange` is false (no file access at all), serialises per 3.5 and awaits `exchange(_:)` (push: combined read-and-write; check: read only). `syncFileDidChange()` keeps its 2 s debounce and `pushesAfterCheck` logic but ends in `requestExchange(.check)`; skip and remember checks while `isAsking`, run one after the prompt closes.
Handle results per the "running" column of 3.4: `.write` → base = digest written, last-synced = written date, clear pending; `.adopt` → base, last-synced (max), clear pending; `.none` → clear pending; `.apply` → persist pending, schedule the windowless `.restart` prompt with the existing strings ("Settings changed on another Mac", "holzBar can restart now to use the settings from the sync folder.", "Restart", "Later"); `.ask` → persist pending, schedule the windowless `.conflict` prompt (Later, or Cancel when base is nil); `.retry`/`.wait` → nothing. Ignore a result when sync was turned off meanwhile, or when its request's fileURL is no longer `Self.fileURL` (the folder changed while it ran). The written file is `settingsToWrite(local, file: remote settings)` (learned union, D-12) with `modified` and `deviceID` as today; the computer name is still never written.
Restart / Use: decode the captured `RemoteVersion` settings, `SettingsBackup.apply(SettingsSyncPolicy.settingsToApply(remote, over: syncedSettings()), removesMissingKeys: false)`, store base (user digest after the apply), last-synced, clear pending and postponed, `SettingsBackup.relaunch()`. Never read the file on the main thread for this (the old `pullIfNeeded()` call in the restart path goes away). Later: `postponed = modified`. Keep: forced exchange.
`updateObservers()`: move the `isUsableFolder` check, `createDirectory` and the creation of `SettingsSyncFolderWatcher` into a `@concurrent private nonisolated static` preparation on `fileQueue` (BlockingWork); on return install the presenter and watcher only if sync is still on, `Self.folderURL` is unchanged and no presenter exists; keep the existing log lines. `volumesDidChange()` keeps its behaviour.
Use `Defaults`/`UserDefaults.standard` exactly as the file does today; keep the class `@MainActor @Observable` and every `@ObservationIgnored` annotation on new stored state.</action>
  <verify><automated>cd WT && swift test --scratch-path S/build-sync-alerts 2>&1 | tail -3 && zsh S/appcheck.sh WT sync-t3 | tail -1 && awk '/var isEnabled = false/,/^    }$/' holzBar/Utilities/SettingsSync.swift | grep -c 'push('</automated></verify>
  <acceptance_criteria>
    - The awk region count prints 0 (no push call in the isEnabled property)
    - `grep -c "lastPushedData\|isAskingToRestart\|readFileContentsInBackground" WT/holzBar/Utilities/SettingsSync.swift` == 0
    - `grep -c "createDirectory" WT/holzBar/Utilities/SettingsSync.swift` ≥ 1 and every occurrence is inside a function that runs on fileQueue (review)
    - appcheck `ERRORS: 0  EXIT: 0`; full swift test green
  </acceptance_criteria>
  <done>No push at launch; pushes read first and never overwrite a newer foreign version; pending pauses pushes across launches; learned keys never prompt; restart prompt and conflict alert run without blocking the main actor; folder setup and writes happen off the main thread.</done>
</task>

<task type="auto">
  <name>Task 4: Launch path — bounded, never asks (F-15 launch, D-05) — then commit B</name>
  <files>holzBar/Utilities/SettingsSync.swift</files>
  <read_first>holzBar/Utilities/SettingsSync.swift (pullIfNeeded, readFileContents), holzBar/Main/AppDelegate.swift (init), section 3.4 launch column and 3.5 Launch, S/syncplan-probe/cancel.swift</read_first>
  <action>Implements D-05, D-06 (launch half), D-12 (launch merge), D-14, D-16.
Give `readFileContents(at:)` a coordinator parameter (keep it `nonisolated static`). Add `readForLaunch(at:) -> SettingsSyncFile.ReadResult?` per 3.5: availability via `lstat` (`SF_DATALESS`) and `URLResourceValues` (`isUbiquitousItemKey`, `ubiquitousItemDownloadingStatusKey`) decided by `SettingsSyncFile.isLocal`, the coordinated read with the outside coordinator, a `DispatchSemaphore` wait of 1 s, `coordinator.cancel()` on timeout, result passed through an `OSAllocatedUnfairLock` (import os). Missing file returns `.missing`; not local or timed out returns nil.
Rewrite `pullIfNeeded()` (name kept; still called first thing after the migration import in AppDelegate.init, so AppDelegate.swift does not change): guard sync on; (commit C inserts `verifyDeviceIdentity()` here); resolve `fileURL` once; nil read → log at info ("The sync file is not on this Mac yet; checking it after launch") and return; otherwise parse (same helper as the exchange), build `Local` with trigger `.launch` (postponed nil, no force) and act per the launch column of 3.4: `.apply` → silent apply with `settingsToApply` and `removesMissingKeys: false`, base after the apply, last-synced, clear pending, keep `Defaults.set(true, forKey: .syncsSettingsWithICloud)` and the existing notice log; `.adopt` → base, last-synced, clear pending; `.ask` → persist pending only; `.none` → clear pending. When base is set (not joining) and the file parsed, apply `learnedSettings(merging: file settings, into: local)` with `removesMissingKeys: false` if it is not empty. Never present UI and never write the file here. Update the doc comment (it no longer claims the read is short because of the size limit; it says the read is bounded and skipped for online-only files).
Then run all gates (section 7) and make commit B with the message in section 6 (files: SettingsSyncPolicy.swift, SettingsSyncFile.swift, SettingsSync.swift, Localizable.xcstrings, SettingsSyncPolicyTests.swift, SettingsSyncFileTests.swift).</action>
  <verify><automated>cd WT && swift test --scratch-path S/build-sync-alerts 2>&1 | tail -3 && zsh S/appcheck.sh WT sync-t4 | tail -1 && python3 .github/scripts/strings-check.py && python3 .github/scripts/privacy-check.py logs && S/swiftlint/swiftlint lint --strict --quiet</automated></verify>
  <acceptance_criteria>
    - `awk '/static func pullIfNeeded/,/^    }$/' WT/holzBar/Utilities/SettingsSync.swift | grep -c "NSAlert\|runModal\|coordinate("` == 0 (no UI and no direct coordinated access in the launch function; the access lives in readForLaunch on fileQueue)
    - Gates G1–G7 green; `git -C WT show --stat HEAD` lists only the six files above
  </acceptance_criteria>
  <done>Launch applies silently only without local changes, marks conflicts pending for the post-setup question, waits at most about 1 s and never for an online-only file. Commit B exists.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 5: F-38 — bind the sync id to this Mac (commit C)</name>
  <files>holzBar/Core/SettingsSyncDevice.swift, Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift, holzBar/Utilities/SettingsSync.swift</files>
  <read_first>holzBar/Core/SettingsSyncDevice.swift, Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift, holzBar/Utilities/SettingsSync.swift (deviceID, pullIfNeeded, chooseFolder), S/syncplan-probe/probe.swift (IOKit read verified on this host: IOPlatformUUID equals gethostuuid)</read_first>
  <behavior>
    - identity(storedHash: hardwareHash(of: "A", salt: s), salt: s, hardwareID: "A") == .same
    - same stored hash and salt, hardwareID "B" → .otherMac (copied preferences)
    - storedHash nil (or salt nil) with a hardware id → .firstSeen
    - hardwareID nil → .unknown
    - hardwareHash is 64 lower-case hex characters, equal for equal inputs, different for another salt
    - makeSalt() returns 32 bytes and two calls differ
  </behavior>
  <action>Implements D-17 and D-20. Core: add `Identity`, `identity(storedHash:salt:hardwareID:)`, `hardwareHash(of:salt:)` (CryptoKit SHA-256 of salt followed by the UTF-8 id) and `makeSalt()` (`SymmetricKey(size: .bits256)` bytes) to SettingsSyncDevice; extend the type's doc comment (the id is tied to the Mac by a salted hash of the hardware UUID that never leaves it). Tests first.
App: add `deviceSaltKey = "SettingsSyncDeviceSalt"` and `deviceHashKey = "SettingsSyncDeviceHash"`; a private `hardwareUUID()` that reads `kIOPlatformUUIDKey` from the `IOPlatformExpertDevice` service through `IOServiceGetMatchingService(kIOMainPortDefault, …)` and releases the service (`import IOKit`; the app is not sandboxed; macOS 12+ API, fine for the 14.0 target); and `static func verifyDeviceIdentity()`: `.same`/`.unknown` → return; `.firstSeen` → new salt and hash stored, new `SettingsSyncDeviceID` (UUID), keep last-synced (base is absent on first run, so the Mac joins and compares content); `.otherMac` → new salt and hash, new id, remove last-synced, base and pending. Log only fixed text at notice level ("Gave this Mac a new sync id" / "This Mac's settings come from another Mac; it joins the sync folder again"); never log, export or sync the UUID, the salt or the hash. Call it in `pullIfNeeded()` right after the sync-on guard and at the start of the join in `chooseFolder()` (after the panel, before the exchange). Run all gates and make commit C.</action>
  <verify><automated>cd WT && swift test --scratch-path S/build-sync-alerts --filter SettingsSyncDevice 2>&1 | tail -3 && zsh S/appcheck.sh WT sync-t5 | tail -1 && python3 .github/scripts/privacy-check.py logs && python3 .github/scripts/privacy-check.py network</automated></verify>
  <acceptance_criteria>
    - `grep -n "logger" WT/holzBar/Utilities/SettingsSync.swift | grep -c -i "salt\|uuid\|hardwareHash\|deviceHash"` == 0 (no log line carries identity data)
    - `grep -c "verifyDeviceIdentity()" WT/holzBar/Utilities/SettingsSync.swift` ≥ 3 (definition + the calls in pullIfNeeded and chooseFolder; review)
    - Gates G1–G7 green; commit C made with the message in section 6
  </acceptance_criteria>
  <done>A Mac with copied preferences gets a new id and joins again; the first launch of this version rotates the id once and keeps last-synced; nothing identifying leaves the Mac or reaches the logs.</done>
</task>

<task type="auto">
  <name>Task 6: Final review and report</name>
  <files>(none changed unless a gate fails)</files>
  <read_first>git -C WT log --oneline -4; git -C WT diff 7e7ed6bf --stat</read_first>
  <action>Re-run all gates on HEAD. Review the full diff against sections 3.3–3.6 and the decision table in section 1 (every D-xx implemented, interpretations as documented). Check that no persisted key was renamed (`git -C WT diff 7e7ed6bf -- holzBar | grep '^-' | grep -c 'SettingsSync[A-Za-z]*"'` must be 0 except moved lines; review any hit) and that no file outside files_modified changed. Report: commits (hash + subject), gate results, the open human check (section 8), doc_updates_needed (section 9), the two interpretations in section 1, the coordination note for the alerts part (section 2), and the out-of-scope signing question (scope note). If any gate fails and cannot be fixed: `git -C WT checkout -- .` and `git -C WT clean -fd` for the uncommitted part only (never reset commits), report fix-failed with the reason and stop.</action>
  <verify><automated>git -C WT status --short | grep -v '^?? .planning/audit/remediation/' | wc -l   # expect 0 after the three commits</automated></verify>
  <done>Three commits on audit-manual/sync-alerts, all gates green, report delivered.</done>
</task>

</tasks>

## 4. Tests to add (summary)

- `Tests/HolzBarCoreTests/SettingsSchemaTests.swift`: three `keysRemoved` tests (F-60, "apply without removal").
- `Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift` (new): every row of 3.3 and `needsExchange`, learned merge, `settingsToApply`, digest stability (key order, JSON key order, 1 vs 1.0, Bool vs 1), as listed in Task 2.
- `Tests/HolzBarCoreTests/SettingsSyncFileTests.swift`: `contents(of:)` and `isLocal(...)`.
- `Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift`: identity cases, hash format, salt (re-identification).

App-target code (SettingsSync, SettingsBackup) is compiled only by CI's build job or by `S/appcheck.sh`; its behaviour is covered by the Core decision tests plus the human check in section 8.

## 5. New strings (D-21; machine-written, Swiss German spelling, terms as in the catalog)

Terms already used: de "Abgleichordner", fr "dossier de synchronisation" (vous), it "cartella di sincronizzazione" (tu), rm "ordinatur da sincronisaziun" (ti). French puts a plain space before "?" as in "Remplacer vos réglages ?". Reused keys (no new entry): "Cancel", "Later", "Restart", "Settings changed on another Mac", "holzBar can restart now to use the settings from the sync folder.".

| Key (en) | de | fr | it | rm |
|---|---|---|---|---|
| Which settings should holzBar use? | Welche Einstellungen soll holzBar verwenden? | Quels réglages holzBar doit-il utiliser ? | Quali impostazioni deve usare holzBar? | Tge parameters duai holzBar duvrar? |
| The sync folder holds settings from another Mac that differ from this Mac's. Using them restarts holzBar; keeping this Mac's settings replaces them in the sync folder. | Der Abgleichordner enthält Einstellungen eines anderen Macs, die von denen dieses Macs abweichen. Verwendest du sie, startet holzBar neu; behältst du die Einstellungen dieses Macs, ersetzen sie jene im Abgleichordner. | Le dossier de synchronisation contient des réglages d'un autre Mac qui diffèrent de ceux de ce Mac. Les utiliser redémarre holzBar ; garder les réglages de ce Mac les remplace dans le dossier de synchronisation. | La cartella di sincronizzazione contiene impostazioni di un altro Mac diverse da quelle di questo Mac. Usarle riavvia holzBar; mantenere le impostazioni di questo Mac le sostituisce nella cartella di sincronizzazione. | L'ordinatur da sincronisaziun cuntegna parameters d'in auter Mac che sa distinguan da quels da quest Mac. Sche ti als duvras, reavia holzBar; sche ti tegnas ils parameters da quest Mac, remplazzan quels ils parameters en l'ordinatur da sincronisaziun. |
| Use Settings from Sync Folder | Einstellungen aus dem Abgleichordner verwenden | Utiliser les réglages du dossier | Usa le impostazioni della cartella | Duvrar ils parameters da l'ordinatur |
| Keep This Mac's Settings | Einstellungen dieses Macs behalten | Garder les réglages de ce Mac | Mantieni le impostazioni di questo Mac | Tegnair ils parameters da quest Mac |

Each entry: `"localizations"` with `de`, `fr`, `it`, `rm`, each `{"stringUnit": {"state": "translated", "value": …}}`, like "Later".

## 6. Commits (git -C WT add <files> && git -C WT commit -F <message file in S>)

Git identity is configured; do not change git config. Stage only the listed files.

**Commit A (after Task 1)** — files: holzBar/Core/Defaults.swift, holzBar/Utilities/SettingsBackup.swift, holzBar/Utilities/SettingsSync.swift, Tests/HolzBarCoreTests/SettingsSchemaTests.swift

    fix(sync): resolve F-60 — keep local settings a synced file does not have

    The maintainer chose to ask on sync conflicts; every option of that decision
    stops sync from deleting keys.
    SettingsBackup.apply removed every importable key missing from the incoming
    settings, and sync used the same apply, so a file from a macOS 26 Mac deleted
    MacOS27Layout and its seeded flag on a macOS 27 Mac, and ItemSections the
    other way round.
    apply(_:removesMissingKeys:) now removes missing keys only for a file import;
    sync passes false.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

**Commit B (after Task 4)** — files: holzBar/Core/SettingsSyncPolicy.swift, holzBar/Core/SettingsSyncFile.swift, holzBar/Utilities/SettingsSync.swift, holzBar/Resources/Localizable.xcstrings, Tests/HolzBarCoreTests/SettingsSyncPolicyTests.swift, Tests/HolzBarCoreTests/SettingsSyncFileTests.swift

    fix(sync): resolve F-02, F-15 — ask before replacing another Mac's settings, keep sync file I/O off the main thread

    The maintainer chose to ask on conflict: joining a folder whose settings
    differ, or a newer version from another Mac while this Mac changed settings,
    now shows one alert (use the folder's settings, keep this Mac's, Cancel/Later).
    push() never read the file, pushed at every launch and after "Later", and all
    sync file access ran on the main thread, also in AppDelegate.init.
    A pure decision type in Core (tested) compares canonical digests against a
    stored base, pending versions pause pushes, learned keys never prompt, and
    every read and write runs on one serial queue; the launch read is bounded to
    1 s and skips online-only files.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

**Commit C (after Task 5)** — files: holzBar/Core/SettingsSyncDevice.swift, Tests/HolzBarCoreTests/SettingsSyncDeviceTests.swift, holzBar/Utilities/SettingsSync.swift

    fix(sync): resolve F-38 — give a Mac copied from another Mac its own sync id

    The maintainer chose a salted SHA-256 of the hardware UUID, stored only on
    this Mac, beside the random sync id.
    The id lived only in the preferences, which Migration Assistant, restores and
    clones copy, so two Macs ignored each other's changes.
    On a mismatch holzBar creates a new id and clears last-synced, base and
    pending, so the Mac joins the folder again; the first launch rotates the id
    once and keeps last-synced. The hash is never logged, exported or synced.

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_01WqxDTofwLfMsw5XESc3Sji

## 7. Gates (run from WT; all must pass before each commit)

| Gate | Command | Pass |
|------|---------|------|
| G1 | `cd WT && swift test --scratch-path S/build-sync-alerts` | all tests pass (Core + MacOS27 Core + CodeSigning) |
| G2 | `cd WT && python3 .github/scripts/strings-check.py` | exit 0 |
| G3 | `cd WT && python3 .github/scripts/privacy-check.py network && python3 .github/scripts/privacy-check.py logs` | exit 0 |
| G4 | `cd WT && S/swiftlint/swiftlint lint --strict --quiet` (0.65.1, same as CI) | exit 0 |
| G5 | `zsh S/appcheck.sh WT <label>` (whole app module, Swift 6, MainActor default isolation, CLT SDK, target 14.0) | `ERRORS: 0  EXIT: 0` (baseline on 7e7ed6bf: 0 errors) |
| G6 | `cd WT && git grep -n -i -E 'holz[ -]?[i]ce' -- . ':(exclude).planning' ':(exclude).claude' ':(exclude).github/cms-version.py'` | no output |
| G7 | `grep -c 'ß' WT/holzBar/Resources/Localizable.xcstrings` | 0 |

No Xcode on this Mac: the real app build, `xcodebuild` and the macOS 26/27 compat legs run only in
CI after the chain's single push (CLAUDE.md: push once at the end, not in this part).

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| sync folder → holzBar | Anyone who can write the synced folder (shared Dropbox/Nextcloud folder, network share, Syncthing peer) controls Settings.plist |
| hardware → preferences | The hardware UUID is read locally and only its salted hash is stored in holzBar's preferences |
| file provider / volume → main thread | Online-only files, hung providers and stalled volumes can block any thread that touches them |

## STRIDE Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation Plan |
|-----------|----------|-----------|----------|-------------|-----------------|
| T-SA-01 | Tampering | Sync file content applied after "Use Settings from Sync Folder" or at launch | medium | mitigate | Unchanged validation: holzBar keys only, expected kinds, clamped numbers (`validatedSettings`), 1 MiB limit, `O_NOFOLLOW`, regular files only, future-dated files ignored; the user now decides on every conflict instead of a silent overwrite |
| T-SA-02 | Denial of service | AppDelegate.init and UI waiting on the sync file | medium | mitigate | Launch read bounded to 1 s with `NSFileCoordinator.cancel()`, online-only files skipped; all other access on a serial background queue |
| T-SA-03 | Denial of service | A writer of the shared folder re-writing the file to trigger prompts | low | mitigate | Prompt only when the user digest differs; "Later" stops further questions for that version in the session; equal content is adopted silently |
| T-SA-04 | Information disclosure | Hardware UUID derived identity | low | mitigate | Only SHA-256(random 32-byte salt ‖ UUID) is stored, under a `SettingsSync` key (never exported, imported or synced), never logged; the UUID itself is never stored |
| T-SA-05 | Tampering | `holzBar` folder replaced by a symbolic link | low | mitigate | Existing `isUsableFolder` lstat check, now on the file queue before every write and folder setup |
| T-SA-SC | Tampering | npm/pip/cargo installs | high | accept | No package is installed; CryptoKit and IOKit are system frameworks (no Package.swift dependency, no-network check unchanged) |
</threat_model>

## 8. Risks for macOS 26 and 27, and the maintainer's hand test

Risks:

1. **macOS 27 clicks while a prompt is open.** The new and the restart prompt run from a run-loop
   source, so the main actor keeps running and SystemItemClickBridge27 can replay held-back clicks
   (F-14 probe case B). Verify on 27 by hand; if clicks still stall, the alerts part's notice
   replaces the restart prompt anyway.
2. **Online-only detection.** `SF_DATALESS` and `ubiquitousItemDownloadingStatus` are documented for
   iCloud Drive and File Provider domains on macOS 26/27; a third-party provider that reports
   neither falls back to the 1 s bound. A skipped launch read means the user gets the restart
   question after launch instead of a silent apply (decided).
3. **Coordinator cancel on macOS 27.** Verified on macOS 26.7.1 only (`S/syncplan-probe/cancel`). If
   27 ignores `cancel()`, the semaphore still returns after 1 s; only the background block stays
   stuck, which delays later sync accesses but never the main thread.
4. **One-time questions after the update.** Every Mac rotates its id once and has no base, so the
   first launch of this version compares content: Macs whose settings already match stay silent;
   Macs that diverged (for example after the old "Later" bug) get one conflict question, where
   Cancel turns sync off on that Mac (documented interpretation).
5. **Automatic layout writes still sync.** On macOS 27 `placeNewApplications` writes MacOS27Layout
   and on macOS 26 restore writes ItemSections when new items appear; these are user settings, so
   the other Macs get the restart question (or a silent apply at launch). Same as before, but no
   longer a ping-pong.
6. **No removal on sync** means "Keep This Mac's Settings" does not reset keys the other Mac set but
   this Mac never stored (it has their default). Accepted consequence of D-18.
7. **Model re-saves.** JSON in Data is canonicalised for the digest; a model that changes a value on
   load (migration, clamping) still counts as a change and pushes once.
8. **VMs.** A cloned macOS VM with a copied machine identifier keeps the same platform UUID and is
   not re-identified (unchanged from today).
9. **Compile coverage.** The app target is only type-checked locally (G5); CI's build and compat
   jobs are the first real Xcode 27 build.

Maintainer hand test (two Macs, same sync folder; recorded as **open**, D-23):

1. **Joining.** Mac A with a customised layout and sync on. On Mac B with different settings choose
   Turn On… with the same folder: the sheet asks; Cancel leaves sync off and A untouched; Turn On…
   again → "Use Settings from Sync Folder" relaunches B with A's settings, A gets no prompt. Repeat
   with Change… and "Keep This Mac's Settings": A then offers Restart.
2. **Relaunch without prompts.** Quit and reopen holzBar on A and on B several times without changing
   anything: no prompt anywhere; the file's modification date does not change.
3. **Later.** Change a setting on A; on B answer the restart prompt with Later, then change a setting
   on B: A must not change; relaunch B: B asks the conflict question (Later as third button).
4. **Online-only file at login.** iCloud Drive with Optimize Mac Storage (or a OneDrive folder):
   remove the local copy of `holzBar/Settings.plist` ("Remove Download"), change a setting on the
   other Mac, log in offline: the holzBar icon appears at once; online again, the restart question
   comes after launch.
5. **macOS 26 ↔ 27.** One Mac on 26 and one on 27: after syncing, the 27 Mac keeps its layout
   (MacOS27Layout) and the 26 Mac keeps ItemSections.
6. **Migration Assistant copy** (if available): the copied Mac asks once (or stays silent when equal)
   and afterwards both Macs see each other's changes.
7. **macOS 27 clicks**: with the restart prompt open, click the clock, battery and Control Centre;
   the clicks open their menus.

## 9. Doc updates needed (not done in this part)

- `docs/privacy-and-permissions.md`: settings sync stores a salted SHA-256 of the Mac's hardware UUID
  (and its random salt) in holzBar's preferences to recognise a Mac copied by Migration Assistant;
  it never leaves the Mac, is never exported, synced or logged (D-17).
- `docs/features.md` (sync bullet, line 59): holzBar asks which settings to use when two Macs differ
  (turning sync on, or both changed); it never overwrites another Mac's settings unasked; launch
  never waits for the cloud; settings a Mac does not have are kept.
- `SECURITY.md` T-06-L2: the launch read is now off the main thread too (bounded to 1 s, online-only
  files skipped).
- Release notes of the next beta, `docs/release-notes/v0.0.7-beta2.md` (D-22): Fixed F-02, F-15,
  F-38, F-60; New: the sync conflict question.
- README: no change needed (the sync row stays true).

## 10. Source coverage audit

| SOURCE | ID | Item | Task | Status |
|--------|----|------|------|--------|
| GOAL | — | Implement "Nachfragen bei Konflikt" for F-02, F-15, F-38, F-60 | 1–5 | COVERED |
| REQ | F-02 | Sync overwrites other Macs' settings | 2, 3, 4 | COVERED |
| REQ | F-15 | Coordinated I/O on the main thread | 2, 3, 4 | COVERED |
| REQ | F-38 | Copied device id | 5 | COVERED |
| REQ | F-60 | Apply removes missing keys | 1 | COVERED |
| RESEARCH | F-02 fix 1–5 | didSet push, ask on join, hash, read before push, Core logic | 2, 3 | COVERED |
| RESEARCH | F-15 fix 1–3 | off-main push, skip non-local at launch, design with F-02 | 3, 4 | COVERED |
| RESEARCH | F-38 fix 1–3 | hardware identity, new id + clear, conflict policy | 5, 2 | COVERED |
| RESEARCH | F-60 fix 1–2 | removesMissingKeys false for sync | 1 | COVERED |
| CONTEXT | D-01 … D-21 | see section 1 | 1–5 | COVERED |
| CONTEXT | D-22 | Release notes of the next beta | — | HANDED OFF (run forbids editing release notes; listed in section 9) |
| CONTEXT | D-23 | Two-Mac human check | 6 (report) | COVERED (recorded open) |
| OUT OF SCOPE | F-14, F-18, F-59, F-61 | other part / already fixed (F-18: `.withoutMounting` and cached name are in the base) / own decisions | — | not planned here |

<verification>
- G1–G7 green on each of the three commits.
- `git -C WT log --oneline 7e7ed6bf..HEAD` shows exactly commits A, B, C in that order.
- Every row of the decision table 3.3 has a test; every finding row of 3.6 maps to code in the diff.
</verification>

<success_criteria>
- Joining a folder with a differing foreign file never writes before the user answers.
- An unchanged launch writes nothing; a pending foreign version is never overwritten.
- AppDelegate.init waits at most about 1 s on the sync file; no other sync file access runs on the main thread.
- A copied Mac re-identifies; nothing identifying is logged or synced.
- Sync never removes local keys; import still replaces.
- Four new strings in five languages; strings-check passes.
</success_criteria>

<output>
Report to the orchestrator (no SUMMARY file in docs/): commit hashes and subjects, gate results,
open human check (section 8), doc_updates_needed (section 9), interpretations (section 1), the
coordination note for the "alerts" part (section 2) and the out-of-scope signing question.
</output>
