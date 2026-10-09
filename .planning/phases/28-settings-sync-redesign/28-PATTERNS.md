# Phase 28: Settings sync redesign - Pattern Map

**Mapped:** 2026-10-07
**Files analyzed:** 41 (new and modified)
**Analogs found:** 38 / 41 (the three without analog are the engine algorithms themselves, the simulator, and the file actor)
**Tracked-source gate (#3645):** `/Users/cheidenreich/privat/holzBar` is not a git repository (`git ls-files` is unavailable). Every path below is a source path under `holzBar/`, `Tests/` or `.github/`; none is a `.gsd/capabilities` mirror.

All line numbers refer to the working tree on 2026-10-07 (equal to `main` at 0.0.7-beta2).

## Answer: other macOS 27 user arrangement paths

**None exists besides the Layout pane, profile apply and Import. A Command-drag on the bar is not captured on macOS 27 and need not be.**

- `holzBar/MenuBar/Backends/AccessibilityBackend27.swift:10-20`: items "cannot be moved: the saved layout decides their sections"; `var canMoveItems: Bool { false }` (line 20).
- `holzBar/Events/HIDEventManager.swift:190`: `savesUserArrangement: MenuBarBackends.current.canMoveItems` is false on 27, so `InputMonitors` (`holzBar/Core/InputMonitors.swift:70-72`) does not add the mouse-up monitor for arrangement.
- The mouse-dragged and mouse-up monitors still run on 27 when "Show all sections on drag" or a custom appearance is on (`InputMonitors.swift:65-68`). Then a Command-drag sets `isDraggingMenuBarItem` (`HIDEventManager.swift:517-526`) and ends in `handleMenuBarItemDragStop()` (`HIDEventManager.swift:488-495`) which calls `itemManager.saveSectionsSoon()`. That function returns at once on 27: `SectionRestore.swift:91-93` `guard backend.canMoveItems else { return }` (same guard in `saveSections` line 53-55 and `reconcileSections` line 166). `handleArrangementEnd` (`HIDEventManager.swift:502-514`) ends in the same call. So no code reads or stores a section from a bar drag on 27, and `Concealer27` never learns of it.
- The only writers of `MacOS27Layout` (grep `macOS27Layout`): `Concealer27.swift:842` (`placeNewApplications`, automatic), `:852` (`setSection`, user), `:904` (`seedLayoutIfNeeded`, automatic), `LayoutProfiles.swift:203` (`apply`, user unless bound), `SettingsBackup.apply` (Import, via `Defaults.set` of every key; its call `SettingsSync.userChangedLayout()` is `SettingsBackup.swift:154`).
- The only caller of `Concealer27.setSection` is `LayoutBarPaddingView.swift:314` (`setSection27`, reached from `:287` drop and from undo `:309`). The Layout pane's `LayoutBarItemView.swift:376` and `:362` call `LayoutBarMoves.setSection(of:to:)` / `move`, which route to `setSection27` on 27 (`LayoutBarPaddingView.swift:84-108`). Keyboard moves and undo go through the same function.
- Other user "apply" entries: hotkeys `ApplyProfile:<name>` (`HotkeyTarget.swift:18,33,49`), `holzbar://apply-profile` (`URLCommand.swift:32,134`), the menu and Shortcuts: all end in `LayoutProfiles.apply(named:)` / `apply(_:)`. Display/Space bindings (`applyBoundProfile`, `LayoutProfiles.swift:389`) also end there, so S-06 must pass a `byUser` flag from the call sites (see below).
- Record for the plan: "no other user arrangement path on macOS 27; a macOS 27 Command-drag moves nothing holzBar saves". Recheck at execution that `canMoveItems` is still false.

## File Classification

Layout follows analysis §5.2 and §7.3. All new Core files are `nonisolated` Foundation-only value types in `holzBar/Core/Sync/` (compiled by target `HolzBarCore`, path `holzBar/Core`, so a subfolder needs no `Package.swift` change; app compiles it through the synchronized `holzBar` folder group).

| New/Modified File | Role | Data Flow | Closest Analog | Match |
|---|---|---|---|---|
| `holzBar/Core/Sync/SyncDot.swift`, `SyncReplica.swift` (dot, context, entry, join) | model | transform | `holzBar/Core/ItemIdentity.swift` (value types), `SettingsSyncPolicy.swift:187-275` (nested Equatable/Sendable structs) | role-match |
| `holzBar/Core/Sync/SyncUnits.swift` (unit table v1, normalizers, caps) | config/model | transform | `Defaults.swift:144` `Key` enum + `settingsKind` (`:300-340`) + `numberRule`; `SettingsSchema` | role-match |
| `holzBar/Core/Sync/SyncDeviceFile.swift` (per-Mac plist codec, structural checks) | utility | file-I/O (decode/encode) | `holzBar/Core/SettingsSyncFile.swift` | exact |
| `holzBar/Core/Sync/SyncState.swift` (Sigma codec) | model | file-I/O | `SettingsSyncFile.swift` (codec), `SettingsSyncDevice.swift` | role-match |
| `holzBar/Core/Sync/SyncIdentity.swift` (MacID, collisions, hardware identity) | utility | request-response | `holzBar/Core/SettingsSyncDevice.swift` (`Identity`, `hardwareHash`) | exact |
| `holzBar/Core/Sync/SyncCapture.swift`, `SyncPlan.swift`, `SyncJoin.swift`, `SyncLaunch.swift`, `SyncAnswer.swift`, `SyncLegacyInput.swift`, `SyncEngine.swift` | service (pure) | event-driven (`handle(event,state) -> (state,[Effect])`) | `SettingsSyncPolicy.swift` (`Trigger`/`Local`/`Action`, `decide`) | role-match |
| `holzBar/Core/Sync/SyncLayout27.swift` (family `l27/<bundleID>`, `prof/<id>`) | model | transform | `holzBar/MenuBar/MacOS27/Core/SectionLayout27.swift` + `SectionLayoutEditing27.swift` | exact |
| `holzBar/Core/SettingsSyncPause.swift` (flip to false, last change) | config | n/a | itself | exact |
| `Tests/HolzBarCoreTests/SettingsSyncPauseTests.swift` (flip) | test | n/a | itself | exact |
| `holzBar/Core/SettingsSyncPolicy.swift` (delete) and its tests `SettingsSyncPolicyTests`, `SettingsSyncLayoutTests` | removal | n/a | n/a | n/a |
| `holzBar/Core/SettingsSyncFile.swift`, `SettingsSyncLocation.swift`, `SettingsSyncDevice.swift` (+ tests) | utility | file-I/O | keep/adapt; `Location` and `Device` are reused | n/a |
| `Tests/HolzBarCoreTests/Sync/*Tests.swift` (JoinLaws, Codec, UnitTable, Counter, Capture, Plan) | test | transform | `SettingsSyncFileTests.swift`, `ProfileBindingTests.swift` | exact |
| `Tests/HolzBarCoreTests/Sync/Simulation/*` (World, Random, Clock, Provider, MacN, MacBeta1, MacBeta2, GroundTruth, Oracles, ControlEngines, Shrinker) | test infra | event-driven | none (see No Analog) | none |
| `Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/*` | test | event-driven | `SettingsSyncLayoutTests.swift` (loop over `layoutBackends`, scenario helpers) | role-match |
| `Scripts/` mutation-gate script | script | batch | `Scripts/macos27/verify-layout.sh` (shell), `.github/scripts/strings-check.py` (python style) | partial |
| `holzBar/Utilities/SettingsSync.swift` (replace exchange paths with glue) | service/glue | event-driven + file-I/O | itself (`SettingsSync`, 1909 lines: folder, presenter, watcher, coordinator, alerts) | exact |
| App file actor (list/read/write/dataless, coordinated writes) | service | file-I/O | `SettingsSync.swift` `@concurrent` helpers (`:290`, `:610`, `:725`, `:1227`), `NSFileCoordinator` (`:1832`), presenter (`:1880-1906`) | role-match |
| `holzBar/Utilities/SettingsBackup.swift` (adapter to engine: `currentSettings`, `apply`) | utility | transform | itself | exact |
| `holzBar/MenuBar/MacOS27/Concealer27.swift` (`setSection` capture; automatic stores respect intent) | controller | request-response | itself `:850-860`, `:808-846`, `:872-912` | exact |
| `holzBar/MenuBar/Profiles/LayoutProfiles.swift` (profile ID, `byUser`, split save) | model/service | CRUD | itself | exact |
| `holzBar/MenuBar/MenuBarItems/SectionRestore.swift` (26 part stays local; drop `userChangedLayout` call sites) | service | CRUD | itself | exact |
| `holzBar/Core/HotkeyTarget.swift`, `HotkeysSettings.swift` (profile hotkeys keyed by profile ID) | model | CRUD | itself | exact |
| Load-time writers: `HotkeysSettings.loadInitialState` (`:56`, writes `:106-111`), `GeneralSettings` (`:35-46,189-195,214-216`), `MenuBarSpacers.performSetup` (`:37`), `MenuBarAppearanceManager` (`:15-20,114`), `MenuBarItemGroups` (`:52-57,78,94-97`) | model | CRUD | the same files (stop writing back or mark automatic) | exact |
| `ItemIconStore.setChoice` (`:70-86`), `ItemChangeWatcher.setRevealedOnChange` (`:84-96`) | model | CRUD | themselves (re-key by alias rule) | exact |
| `holzBar/Core/Defaults.swift` (new local keys) | config | n/a | `Defaults.Key` enum (`:144`) | exact |
| Settings UI: hint, status lines, sheet (`SettingsSync` alerts `:1716-1760`, Advanced pane) | component | request-response | `SettingsSync.makeAlert/ask/answer` | role-match |
| `holzBar/Resources/Localizable.xcstrings` | config | n/a | existing sync entries | exact |
| `docs/features.md`, `docs/privacy-and-permissions.md`, `README.md`, `docs/comparison.md`, `docs/release-notes/v0.0.7-beta3.md` | docs | n/a | previous `docs/release-notes/v0.0.7-beta*.md` | exact |

## Pattern Assignments

### Core test package layout (applies to every new Core file and test)

**Analog:** `/Users/cheidenreich/privat/holzBar/Package.swift` (lines 1-62).

- Tools 6.2, `platforms: [.macOS(.v14)]`. Target `HolzBarCore` is `path: "holzBar/Core"` with `swiftSettings: appCore` (`approachableConcurrency + [.defaultIsolation(MainActor.self)]`). Test target `HolzBarCoreTests` is `path: "Tests/HolzBarCoreTests"`, depends on `["HolzBarCore"]`, with `approachableConcurrency` only (no MainActor default), so test code is nonisolated by default while Core types default to MainActor.
- Therefore every new Core type must be spelled `nonisolated` (enum, struct, extension) and `Sendable` where it crosses actors: precedent `nonisolated enum SettingsSyncPolicy`, `nonisolated struct Local: Equatable, Sendable` (`SettingsSyncPolicy.swift:26,198`), `nonisolated enum SettingsSyncPause` (`SettingsSyncPause.swift:13`), `nonisolated extension SectionLayout27` (`SectionLayoutEditing27.swift:6`).
- Subfolders: `holzBar/Core/Sync/` and `Tests/HolzBarCoreTests/Sync/Simulation/Catalogue/` are picked up by SwiftPM with no manifest change (the target path is a directory). Test file names must be unique across the target? Not required in SwiftPM, but keep unique to avoid object-file collisions.
- Only Foundation and CryptoKit are imported in Core (`SettingsSyncDevice.swift:6-7`). `holzBar/MenuBar/MacOS27/Core` is a separate package target `HolzBarMacOS27Core`; the L27 value helpers (`SectionLayout27`, `MacOS27Section`) live there and are NOT visible to `HolzBarCore`. Decision for the plan: either mirror `MacOS27Section` raw values (0/1/2) as plain `Int` in the Core sync unit (the stored defaults already are `[String: Int]`, see `Concealer27.swift:123-125`) or have the app glue map them. Do not add a target dependency without need.
- Run: `swift test` (all three test targets). Suite style: `@Suite("Name") struct XTests` with `@Test("sentence") func`, `import Testing`, `@testable import HolzBarCore`.

**Test file excerpt to copy** (`Tests/HolzBarCoreTests/SettingsSyncPauseTests.swift:1-8` and `SettingsSyncFileTests.swift:1-35`):
```swift
import Foundation
import Testing
@testable import HolzBarCore

@Suite("SettingsSyncFile")
struct SettingsSyncFileTests {
    private let thisMac = "THIS-MAC"
    private let otherMac = "OTHER-MAC"
    private let lastSynced = Date(timeIntervalSince1970: 1_000_000)
    ...
    @Test("A newer file from another Mac is applied")
    func newerFileFromAnotherMac() throws {
        let result = try #require(newer(in: file(deviceID: otherMac, modified: modified, settings: ["UseIceBar": true])))
        #expect(result.modified == modified)
```
Catalogue tests: copy the "every direction runs for both backends" loop from `SettingsSyncLayoutTests.swift:6-8` (`private let layoutBackends: [MenuBarBackendKind] = [.service26, .accessibility27]`), reusing `MenuBarBackendKind` (Core) for the generation `gen in {26, 27}`.

---

### `holzBar/Core/Sync/SyncDeviceFile.swift` (utility, file-I/O codec)

**Analog:** `holzBar/Core/SettingsSyncFile.swift` (186 lines).

**Constants and size limits** (lines 21-45): keys as `static let`, `maximumFileSize = 1 << 20`, `allowedClockSkew`. Reuse the 1 MiB reader limit; writer limit must be at most the reader limit (INV-Z1).
```swift
nonisolated enum SettingsSyncFile {
    static let modifiedKey = "modified"
    static let settingsKey = "settings"
    static let maximumFileSize = 1 << 20
    static let allowedClockSkew: TimeInterval = 60 * 60
```
**Safe read pattern** (doc lines 14-19, functions `readContents(atPath:maximumSize:)`, `isUsableFolder(atPath:)`, further down the file; read it again in S-01): regular file only, no symlink, size cap, `holzBar` folder must be a real folder. Copy this for `Macs/<MacID>.plist` and add the structural checks (typed values, pass-through of unknown units/families, never read partial/damaged as empty: INV-F1).
**Tolerant decode shape** (lines 66-80): `guard let x = file[key] as? T else { return nil }` returning `nil` for the whole file, never a partial result. Keep `[String: Any]` plist inputs behind one decoder; the typed model is built from it.
**Test pattern:** `SettingsSyncFileTests.swift` helper `file(deviceID:modified:settings:)` building `[String: Any]`; add structural-damage cases the same way.

### `holzBar/Core/Sync/SyncIdentity.swift` (utility, request-response)

**Analog:** `holzBar/Core/SettingsSyncDevice.swift` (88 lines). Reuse as is: `deviceIDKey` (`:19`), `Identity` enum (`.same/.firstSeen/.otherMac/.unknown`, `:55-66`), `hardwareHash(of:salt:)` (CryptoKit SHA-256, `:12-13` doc). INV-S8 / PR2: the hash, salt, uid and computer name never appear in a written byte, so `SyncDeviceFile` must not carry `deviceNameKey` (`:23`); only the MacID goes into files. Existing tests `SettingsSyncDeviceTests.swift` show how to test without real hardware.

### `holzBar/Core/Sync/SyncEngine.swift` + Capture/Plan/Join/Launch/Answer (service, event-driven)

**Analog:** `holzBar/Core/SettingsSyncPolicy.swift` (717 lines; it is replaced, copy only the shape).

Shape to keep: pure, `nonisolated`, `Sendable` input structs, an `Action`/`Hint` enum output, no I/O.
```swift
nonisolated enum SettingsSyncPolicy {
    nonisolated enum Trigger: Sendable { ... }        // :187
    nonisolated struct Local: Equatable, Sendable { settings, layouts, base, ... }  // :198
    nonisolated struct Version: Equatable, Sendable { ... }  // :245
    nonisolated enum Action: Equatable, Sendable { ... }     // :275
    enum Hint: Equatable, Sendable { ... }                   // :366
```
Differences mandated by the analysis: no dates, no whole-state digests; `SyncEngine.handle(event, state) -> (state, [Effect])` is the single entry the simulator and the app both call (§5.1). Do not copy `userDigest`/`layoutDigest`/`learnedKeys` logic (`:30-60`) except the list of learned keys, which is the starting point for D-06's local-only set:
```swift
static let learnedKeys: Set<String> = Set([ Defaults.Key.knownItemTags, .knownApplications27, .titleChangingItemOwners,
    .macOS27LayoutSeeded, .hasMigrated0_8_0, ... .hasImportedPreviousSettings ].map(\.rawValue))
```
Note D-06: `KnownApplications27` now merges by union among 27 Macs (a `known27` family), unlike the others which stay local.

### `holzBar/Core/Sync/SyncUnits.swift` (config, transform; R-CLASS-1 test)

**Analog:** `holzBar/Core/Defaults.swift`.

- `Defaults.Key: String, CaseIterable` (`:144`) lists every persisted key; each key has `settingsKind` (`.number/.data/.string/.stringArray/.dictionary`, `:300-340`) and `numberRule` (`:344-375`, clamped/wholeNumber). The unit table must classify EVERY `Defaults.Key` case (sync unit, local-only, or learned) and a test must fail when a new key lacks a class: iterate `Defaults.Key.allCases` (this is the R-CLASS-1 pattern; existing precedent `SettingsSchemaTests.swift`).
- Key names stay (CLAUDE.md "Persisted strings keep their old names"): e.g. `case macOS27Layout = "MacOS27Layout"` (`:205`), `showHolzBarIcon = "ShowIceIcon"`, `holzBarIcon = "IceIcon"`, `macOS27ShelfWaitsForRefresh = "MacOS27IceBarWaitsForRefresh"`.
- Normalization and validation reuse `Defaults.Key.validatedSettings(_:)` (used in `SettingsSyncPolicy.userDigest`, `:55`) and `SettingsSchema.NumberRule`.
- Exclusions come from `SettingsBackup.excludedKeyPrefixes` (`SettingsBackup.swift:21-33`): `NSWindow Frame`, `NSStatusItem …`, `SU`, and `SettingsSync` (every sync key never exported/imported/synced, D-06). That static list lives in the app target (`@MainActor enum SettingsBackup`), not Core; move or duplicate the prefix list in Core `SyncUnits` and have `SettingsBackup` reference it so the two cannot drift.
- New local-only keys (Sigma path, group state) get `SettingsSync…` names (excluded by prefix) or live in `~/Library/Application Support/holzBar/Sync/` (Sigma file, §4.3).

### `holzBar/Core/Sync/SyncLayout27.swift` (model, transform) and L27 capture

**Analog:** `holzBar/MenuBar/MacOS27/Core/SectionLayout27.swift` and `SectionLayoutEditing27.swift`.

**Stored form** (`Concealer27.swift:123-125`): `MacOS27Layout` is `[String: Int]`, bundle ID to raw section, with visible = absent:
```swift
private var savedLayout: [String: MacOS27Section] {
    let stored = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
    return stored.compactMapValues(MacOS27Section.init(rawValue:))
}
```
**Edit rule to mirror** (`SectionLayoutEditing27.swift:9-13`): `updated[bundleID] = section == .visible ? nil : section`. Per D-04, the sync unit has an explicit "visible" value (`l27/<bundleID> = 0`); the adapter between `[String: Int]` (absence = visible) and units (explicit values) is the new code. Absence in defaults never creates a delete or visible dot.
**Profile apply rule** (`SectionLayoutEditing27.swift:29-48`): `applyingProfile(profile, knownApplications:, to:)` yields the new layout; the capture diffs old vs new layout and records a dot only for entries whose value changes (D-04 "only entries whose value changes").
```swift
var updated = saved.filter { !known.contains($0.key) }
for (bundleID, section) in profile { updated = settingSection(section, for: bundleID, in: updated) }
```
**Capture points (user vs automatic):**

| Site | File:line | Class | Capture |
|---|---|---|---|
| `setSection(_:for:)` | `Concealer27.swift:850-860` | user | one `userChange(l27/<bundleID>, section)` only if the section differs; replaces the call `SettingsSync.userChangedLayout()` at `:853` |
| `placeNewApplications` | `Concealer27.swift:808-846` (store `:842`) | automatic | no dot; must not overwrite an entry backed by applied intent; doc line already says "does not count as a settings change for sync" |
| `seedLayoutIfNeeded` | `Concealer27.swift:872-912` (store `:904`) | automatic | no dot; fills only apps without an entry |
| `LayoutProfiles.apply` 27 branch | `LayoutProfiles.swift:184-212` (store `:203`, call `:206`) | user, except bound | needs a `byUser` parameter: menu, hotkey, Shortcuts and `holzbar://` pass true; `applyBoundProfile` (`:389`) passes false |
| Import | `SettingsBackup.swift:154` (`apply(settings, removesMissingKeys: true)` then `userChangedLayout()`) | user | diff of imported vs current per entry |
| Reconciliation, displacement | `SectionRestore.reconcileSections` (`:155`, `:204`) | automatic, macOS 26 only (`canMoveItems` guard) | none |

### `holzBar/Core/Sync/` profile family `prof/<profileID>` and `LayoutProfiles.swift` (model, CRUD)

**Analog:** `holzBar/MenuBar/Profiles/LayoutProfiles.swift` (430 lines).

Current state to change (D-05):
- `LayoutProfile.id` is the name (`:49` `var id: String { name }`; struct fields `:9-45`: `name`, `itemSections`, `applicationSections`, `knownApplications: [String]?`, `displayUUID`, `spaceUUID`). Add a stable `profileID` (Codable optional so old stored profiles decode unchanged, same technique as `knownApplications` and the UUIDs: "Optional, so profiles saved before … decode unchanged", `:17-22`). Migration assigns IDs deterministically or randomly once at load; this is a load-time writer that must be marked automatic.
- Hotkeys are keyed by name: `.applyProfile(String)` (`HotkeyTarget.swift:18`), `moveHotkey(from: .applyProfile(profile.name), to: .applyProfile(newName))` on rename (`LayoutProfiles.swift:251`), `removeHotkey` on delete (`:164`, `:290`). To sync "keyed by profile ID" (D-05) the hotkey raw string changes from name to ID with a migration and the display name looked up at use. This touches `HotkeyTarget.swift`, `HotkeysSettings.swift:188`, `HotkeysSettingsPane.swift:61,73`, and `URLCommand.swift:32,134` (the URL keeps the name: `profile(named:)` at `LayoutProfiles.swift:169`).
- `saveCurrentLayout(as:)` (`:109-155`, see `:130` `let applicationSections = Defaults.dictionary(forKey: .macOS27Layout)` and `:131-139` `if #available(macOS 27.0, *) { ... knownApplications }`): today copies `MacOS27Layout` into every profile on every OS. Change: on 26, build the profile with `applicationSections`/`knownApplications` kept from `previous` (the existing profile of that name, already looked up at `:140` `let previous = profiles.first { $0.name == name }`), and update only `itemSections`; on 27 keep `previous.itemSections`. Note `itemSections` is filled from `itemManager.itemCache` and is empty on 27 (items not movable), which is why a profile saved on 27 currently overwrites a 26 part with `[:]`; fix per D3 §4.5.
- `save()` (`:97-103`) ends with `appState?.settingsSync.settingsDidChange()` after writing `.layoutProfiles` and `.currentLayoutProfile`; keep this hook as the "defaults changed" notification, but derive dots only from explicit user events (`saveCurrentLayout`, `delete`, `rename`, `apply`), not from the diff of stored data.
- Rename (`rename(_:to:)` `:235`), delete (`:157`), `replaceProfiles` (`:228`, Import) become `prof/<id>` events: rename = value (name) change of the same ID, not delete+create.

### `holzBar/Core/SettingsSyncPause.swift` and its test (config)

**Analog:** itself (48 lines). Last code change of the phase (D-12): set `static let isPaused = false` (`:16`) and rewrite the doc comment (`:5-12`). Tests to flip: `pausedInThisBuild` (`SettingsSyncPauseTests.swift:6-12`) asserts `isPaused`, `!isActive()`, `!syncs(isTurnedOn: true)`, `!allowsChanges()`; invert the four expectations and rename ("Sync is not paused in 0.0.7-beta3"). The other three tests pass explicit `isPaused:` arguments and stay. Existing gate: `SettingsSync.userChangedLayout()` begins with `guard SettingsSyncPause.isActive() else { return }` (`SettingsSync.swift:188-196`); every new entry point must use `isActive()` the same way (never `allowsChanges`).

### `holzBar/Utilities/SettingsSync.swift` and glue (service, event-driven + file-I/O)

**Analog:** itself (1909 lines; large file, locate with grep, read non-overlapping ranges in execution).

Components to reuse or replace, by line (from `grep` of the file):
- Static helpers `verifyDeviceIdentity()` (`:126`), `userChangedLayout()` (`:188`, replaced by engine intent events), `pullIfNeeded()` (`:1484`, the launch pull; replaced by engine launch).
- Folder resolution: `FolderLocation`, `refreshFolder()` (`:342`), `resolveFolder` (`:374`), `prepareFolder` (`:553`), `chooseFolder()` (`:680`), `volumesDidChange` (`:632`): keep, adapt to `Macs/`. Nothing may be mounted or written under an unmounted `/Volumes` path (INV-R1-R3).
- I/O off the main thread via `@concurrent` functions (`:290`, `:610`, `:725`, `:1227`); keep (INV-F7: no main-thread sync I/O; lint).
- `NSFileCoordinator(filePresenter: nil)` (`:1832`) for coordinated writes; `SettingsSyncPresenter` with `presentedItemDidChange` / `presentedSubitemDidChange` / `presentedSubitemDidAppear` (`:1880-1906`); `SettingsSyncFolderWatcher` (`DispatchSource` on `holzBar/`, β1 facts Appendix A item 13); debounce `Debouncer(delay: .seconds(5))` (`:426`).
- UI plumbing: `makeAlert(isJoining:)` (`:1726`), `ask` (`:1716`), `answer` (`:1745`), `use`/`keepThisMac` (`:1787`, `:1818`), `showSettings`/`openSettingsWindow` (`:1659`, `:1695`), `offer`/`refreshHint`/`withdrawHint` (`:1586-1620`), `restartWithWaitingSettings` (`:1621`). The `modal-alerts-1` pattern is already implemented here (hint then sheet attached to the Settings window); keep the structure and change the content (rows per conflicting unit, per-row pop-up for three or more values, Cancel when joining).
- Class state is `@ObservationIgnored private var` with `@Observable` on the class (`:416-473`); follow this when adding glue state. Callers elsewhere use `appState?.settingsSync.settingsDidChange()` (`LayoutProfiles.swift:102`, `ItemIconStore.swift:~80`, `ItemChangeWatcher.swift:~94`). Keep that name or update every caller together.

### `holzBar/Utilities/SettingsBackup.swift` (utility, transform)

**Analog:** itself (199 lines).
- `currentSettings()` (`:44-52`) reads the persistent domain and filters `Defaults.Key.importableKinds[key] != nil && !isExcluded(key)`: the defaults adapter for capture.
- `apply(_:removesMissingKeys:)` (doc `:55-63`; applies only own keys of expected kind, logs and returns the ignored ones). Reuse as the applier for fast-forward (with `removesMissingKeys: false`, so a remote value never removes unrelated keys) and for Import.
- Import path `:140-158` (`NSAlert` with `addButton`, `hasDestructiveAction`, escape key, `alert.present(attachedTo:)`) is the dialog idiom; Import then calls `SettingsSync.userChangedLayout()` (`:154`) which becomes the per-unit diff capture before `relaunch()`.

### Load-time writers (Appendix A items 1-4, §4.9) (model, CRUD)

**Analogs and edits** (verified lines):
- `HotkeysSettings.swift:56` `loadInitialState` drops duplicate combinations and writes back with `Defaults.set(dictionary, forKey: .hotkeys)` at `:106-111`: wrap in the automatic-write marker or skip writing the unchanged-but-deduplicated dictionary (the sync value then stays the user's; a duplicate clash is a plan-level "hotkey clash" row, INV-P1).
- `GeneralSettings.swift`: `didSet` saves, `loadInitialState` assigns via `Defaults.ifPresent` (`Defaults.swift:123-125` shows `ifPresent<Value>(key:assign:)`), clamps at `:189-195`, icon decode/re-encode `:35-46`, `:214-216`.
- `MenuBarSpacers.swift:37` `performSetup` clamps and writes via `didSet` (`:21-31`, `:40-43`).
- `MenuBarAppearanceManager.swift:114` and `didSet` `:15-20`; `MenuBarAppearanceConfigurationV2.swift:79-92` fills missing fields via `decodeIfPresent … ?? default`, dropping unknown ones (this is the pass-through problem: the unit value for appearance is the raw `Data` blob, normalized by the unit table, so unknown fields survive).
- `MenuBarItemGroups.swift:78`, `didSet`/`save()` `:52-57`, `:94-97`.
Rule for all: a load must not change the stored bytes of a value the user did not edit. Test with the INV-A5 pattern (launch twice, zero dots, zero writes).

### `ItemIconStore.setChoice`, `ItemChangeWatcher.setRevealedOnChange`, `SectionRestore.isNew` (alias rule)

**Analogs:** `ItemIconStore.swift:70-86` (removes `storedKey(for:)` then writes `itemManager.identityKey(for:)`, then `settingsSync.settingsDidChange()`), `ItemChangeWatcher.swift:84-96` (`keys.filter { storedIdentityKey($0) != key }` then insert, then `settingsDidChange()`). Both re-key: the engine must treat the removal of the old key as an alias of the new key, never a published deletion (INV-A6). Identity helpers: `holzBar/Core/ItemIdentity.swift` `storedKey(_:titleChangingOwners:)` (`:99-110`), collapse under the mapped key (`:135-140`). `SectionRestore.swift:242-252` computes `isNew = storedKnown != nil && saved[key] == nil && !known.contains(key)`: do not merge `KnownItemTags` (D-06). `SectionRestore.swift:52-67` and `:73-87` call `SettingsSync.userChangedLayout()` for macOS 26 layouts; those calls are removed (26 arrangement stays local), `byUser` parameters can stay for the profile apply on 26 but no longer feed sync.

### `holzBar/Core/Defaults.swift` (config)

**Analog:** the `Key` enum (`:144`). Every new persisted `Defaults.Key` needs a case, a `settingsKind` branch (`:300-340`, an exhaustive `switch`, so the compiler lists the omissions) and an entry in the unit table. New local sync keys: follow the `SettingsSync…` prefix so `excludedKeyPrefixes` excludes them. Only add a key if the state cannot live in Sigma (the Sigma file is preferred, §4.3, since the 16 persisted keys were a failure cause, §1.1).

### Strings, strings check and privacy check (config / script)

**Analogs:** `holzBar/Resources/Localizable.xcstrings` (+ `AppShortcuts.xcstrings`, `InfoPlist.xcstrings`), `.github/scripts/strings-check.py`, `.github/scripts/privacy-check.py`; jobs `strings`, `no-network` in `.github/workflows/build.yml` (`strings` at ~`:331-339`, privacy at ~`:322-325`).
- Catalog: JSON, `sourceLanguage` `en`; each key has `localizations` with `de`, `fr`, `it`, `rm`, each `{"stringUnit": {"state": "translated", "value": "..."}}`; plural variations allowed; each translation must keep the key's format specifiers (`%@`, `%lld`, `%1$@` etc.: `SPECIFIER` regex `strings-check.py:~40`). Existing sync strings (e.g. "Choose a folder your Macs keep in sync…", "Sync Here", "Keeps layout, profiles, hotkeys and appearance the same on all your Macs…") are in the catalog; rewrite them for the new scope (arrangement and profiles now sync; "Changes from another Mac apply after a restart" stays true for fast-forwards).
- Every localisable literal in the Swift code must have an entry. The checker recognizes positions listed in `POSITIONS` (`strings-check.py:~46-65`): `Text(`, `Button(`, `Label(`, `Section(`, `HolzBarSection(`, `HolzBarPicker(`, `.help(`, `.accessibilityLabel(`, `String(localized:`, `NSMenuItem(title:`, `messageText =`, `informativeText =`, `addButton(withTitle:`, etc. Interpolation `\(...)` stands for a format specifier. Use `String(localized: "…")` (as in `SettingsBackup.swift:142-148` and `LayoutProfiles.swift:~150` `String(localized: "Save Profile")`) in glue code. Run `python3 .github/scripts/strings-check.py` (and `--list`).
- Privacy: `python3 .github/scripts/privacy-check.py network` and `logs`. Logger pattern `logger.notice("… \(name, privacy: .private) …")` (`LayoutProfiles.swift:~152`, `SettingsBackup.swift:~156`); bundle IDs, item tags, profile and app names, URLs must be `.private` or `.private(mask: .hash)` (`Concealer27.swift:~836` `privacy: .private(mask: .hash)`), never `.public` for personal data; log categories via `Logger(category:)`. No networking API anywhere (`.github/network-allowlist.txt`). No Dictionary iteration-order dependence in the engine (lint, §5.1).
- Also run `SwiftLint` strict (`TOOLCHAIN_DIR=/Library/Developer/CommandLineTools swiftlint lint --strict`) and the app type check (`swiftc -emit-sil -wmo` flags in CLAUDE.md "Building"; memory note holzbar-local-checks-without-xcode).

### Docs and release notes

**Analog:** `docs/release-notes/v0.0.7-beta2.md` (and beta1). Required sections: Highlights, New, Fixed, Changed, Known issues, Install; install section needs `brew trust --cask holzcloud/holzbar/holzbar` between `brew tap` and `brew install`, `brew update && brew upgrade --cask holzbar`, and `xattr -dr com.apple.quarantine /Applications/holzBar.app` (CLAUDE.md "Releases"). Must say "update all Macs" (D-02), what syncs, that the macOS 26 arrangement stays local. Update `docs/features.md`, `docs/privacy-and-permissions.md`, README feature list and the comparison table (`docs/comparison.md` "settings sync") without claiming more than the code does.

---

## Shared Patterns

### nonisolated Core value types
**Source:** `holzBar/Core/SettingsSyncPause.swift:13`, `SettingsSyncPolicy.swift:26,187-275`, `SectionLayoutEditing27.swift:6`. **Apply to:** every file under `holzBar/Core/Sync/`.
```swift
nonisolated enum SettingsSyncPause { static let isPaused = true ... }
nonisolated struct Local: Equatable, Sendable { ... }
```

### Pause gate
**Source:** `SettingsSyncPause.swift:18-47`, `SettingsSync.swift:188-196`. **Apply to:** every app entry that starts sync (read, watch, mount, write, bring state up to date).
```swift
guard SettingsSyncPause.isActive() else { return }
```
Only settings controls use `allowsChanges()`. Sync stays paused in every commit until the final one (D-12).

### Defaults access
**Source:** `holzBar/Core/Defaults.swift:100-125` (`Defaults.set(_:forKey:)`, `.dictionary(forKey:)`, `.array(forKey:)`, `.ifPresent`). **Apply to:** all app glue; Core engine code takes plain `[String: Any]` or typed values and never touches `UserDefaults`.
```swift
let stored = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
Defaults.set(updated.mapValues(\.rawValue), forKey: .macOS27Layout)
```

### Automatic vs user changes
**Source:** doc comments `Concealer27.swift:803-807,853` ("This placement is holzBar's own and does not count as a settings change for sync"), `SectionRestore.swift:12-20,47-51,69-72`, `LayoutProfiles.swift:203-206` ("Applying a profile is the user's change, also when a display or Space applies a bound one; it counts for sync": this sentence is reversed by D-04, bound application is now automatic). **Apply to:** all capture sites (table above).

### Logging
**Source:** `Concealer27.swift:836` and `LayoutProfiles.swift` (`Logger(category:)`, `.private` / `.private(mask: .hash)`, `.public` only for non-personal enums such as `name.logString`). **Apply to:** glue and file actor; engine code does not log.

### Atomicity and safe file I/O
**Source:** `SettingsSyncFile.swift:14-19` (regular file, size cap, no symlinks, real folder, clock skew); `SettingsSync.swift` coordinator `:1832`. **Apply to:** `SyncDeviceFile`, Sigma store, file actor. Writes by exactly one writer to `Macs/<own MacID>.plist` (INV-S6).

### Sheet and hint (modal-alerts-1)
**Source:** `SettingsSync.swift:1716-1773` (`ask`, `makeAlert`, `answer`, `promptDidClose`) and `SettingsBackup.swift:140-152` (`NSAlert`, `.present(attachedTo: window)`, `hasDestructiveAction`, `cancel.keyEquivalent = "\u{1B}"`). Layout and copy come from `28-UI-SPEC.md`.

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `Tests/HolzBarCoreTests/Sync/Simulation/*` (World, PRNG, virtual clock, provider with presets, β1/β2 peers, ground truth, oracles, control engines, shrinker) | test infra | event-driven | No simulator or seeded-PRNG test code exists. Closest in spirit: `SettingsSyncLayoutTests.swift` scenario helpers and `Scripts/macos27/*` probes (not unit tests). Use analysis §5.2-§5.9. |
| Mutation-gate script (G1) | script | batch | No mutation tooling. Write as a Python or shell script in `Scripts/` or `.github/scripts/`, style of `strings-check.py` (stdlib only, GitHub annotations, exit 1). |
| Folder actor for `Macs/` listing, dataless detection (`URLResourceKey.ubiquitousItemDownloadingStatus`), per-device conflict copies | service | file-I/O | The existing `SettingsSync` handles one file with `NSFileCoordinator`; listing a directory and dataless handling are new. Reuse its coordinator and presenter code; take provider behaviour from `A3-research.md`. |
| `SyncEngine` algorithms (dot/context join, multi-value registers, applied-context rule) | service | transform | No CRDT code exists; follow analysis §4 and D1 §7. Only the container shape has analogs (see above). |

## Metadata

**Analog search scope:** `holzBar/Core`, `holzBar/Utilities`, `holzBar/MenuBar/{MacOS27,Profiles,MenuBarItems,LayoutBar,Backends}`, `holzBar/Events`, `holzBar/Settings/Models`, `Tests/HolzBarCoreTests`, `Package.swift`, `.github/scripts`, `holzBar/Resources`.
**Files scanned/read:** about 30 (large files read by grep plus targeted ranges; `SettingsSync.swift` and `SettingsSyncPolicy.swift` not read in full, so S-01/S-06 must read their ranges before editing).
**Pattern extraction date:** 2026-10-07
