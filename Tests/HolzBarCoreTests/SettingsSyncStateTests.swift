import Foundation
import Testing
@testable import HolzBarCore

/// The sync bookkeeping that `SettingsSync` keeps in its defaults: how it is stored, brought up
/// to date and recorded after an exchange. `SettingsSync` only reads and writes the values
/// these functions name, so their rules are tested here.
@Suite("SettingsSyncPolicy state")
struct SettingsSyncStateTests {
    private typealias Policy = SettingsSyncPolicy
    private typealias State = SettingsSyncPolicy.State

    private let lastSynced = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Stored keys

    @Test("The sync state keeps the keys earlier builds stored it under")
    func storedKeys() {
        // Renaming a key would make every Mac join its folder again and lose its layout edits.
        #expect(State.baseKey == "SettingsSyncBaseSettingsDigest")
        #expect(State.baseLayoutKey == "SettingsSyncBaseLayoutDigest")
        #expect(State.layoutEditsKey == "SettingsSyncLayoutEdits")
        #expect(State.syncedLayoutEditsKey == "SettingsSyncSyncedLayoutEdits")
        #expect(State.lastSyncedKey == "SettingsSyncLastSynced")
        #expect(State.pendingKey == "SettingsSyncPendingModified")
        #expect(State.versionDigestKey == "SettingsSyncVersionSettingsDigest")
        #expect(State.recentLayoutsKey == "SettingsSyncRecentLayoutDigests")
        #expect(State.legacyBaseKey == "SettingsSyncBaseDigest")
    }

    @Test("The sync state is read from its keys, and only changed fields are stored")
    func storedRoundTrip() {
        var stored: [String: Any] = [
            State.baseKey: "base",
            State.baseLayoutKey: "layout",
            State.layoutEditsKey: 4,
            State.syncedLayoutEditsKey: 3,
            State.lastSyncedKey: lastSynced,
        ]
        let old = State(reading: { stored[$0] })
        #expect(old == State(base: "base", baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: nil))
        #expect(old.changes(from: old).isEmpty)
        #expect(State(reading: { _ in nil }) == State())

        var new = old
        new.base = nil
        new.pending = lastSynced.addingTimeInterval(60)
        new.countLayoutEdit()
        let changes = new.changes(from: old)
        #expect(Set(changes.map(\.key)) == [State.baseKey, State.pendingKey, State.layoutEditsKey])
        for (key, value) in changes {
            stored[key] = value
        }
        #expect(stored[State.baseKey] == nil)
        #expect(State(reading: { stored[$0] }) == new)

        var every = State()
        every.markSynced(base: "b", layout: "l", layoutEdits: 2, modified: lastSynced)
        every.layoutEdits = 7
        every.pending = lastSynced
        #expect(every.versionDigest == "b")
        #expect(Set(every.changes(from: State()).map(\.key)) == [
            State.baseKey, State.baseLayoutKey, State.layoutEditsKey, State.syncedLayoutEditsKey, State.lastSyncedKey, State.pendingKey,
            State.versionDigestKey, State.recentLayoutsKey,
        ])
        var everyStored = [String: Any]()
        for (key, value) in every.changes(from: State()) {
            everyStored[key] = value
        }
        #expect(State(reading: { everyStored[$0] }) == every)
    }

    // MARK: Migration

    @Test("Bringing an earlier build's state up to date reads the keys it stored", arguments: [MenuBarBackendKind.service26, .accessibility27])
    func migration(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let syncs = Defaults.Key.syncsSettingsWithICloud.rawValue
        func migration(_ stored: [String: Any]) -> State.Migration {
            State.migration(reading: { stored[$0] }, layouts: layouts)
        }
        // A Mac that synced: its layout came from the folder and counts as unchanged.
        let synced: [String: Any] = [layouts.own: ["a": 0], syncs: true, State.lastSyncedKey: lastSynced]
        #expect(migration(synced) == State.Migration(removesLegacyBase: false, layoutEdits: 0))
        // Without a date of the last sync, with sync off, or with only the other macOS
        // version's layout, the layout may be the user's.
        #expect(migration(synced.filter { $0.key != State.lastSyncedKey }).layoutEdits == 1)
        #expect(migration(synced.merging([syncs: false]) { $1 }).layoutEdits == 1)
        #expect(migration(synced.filter { $0.key != syncs }).layoutEdits == 1)
        #expect(migration([layouts.other: ["a": 0], syncs: true]).layoutEdits == 0)
        // A Mac that counts its layout edits already keeps its count.
        #expect(migration(synced.merging([State.layoutEditsKey: 5]) { $1 }).layoutEdits == nil)
        #expect(migration([State.layoutEditsKey: 0, layouts.own: ["a": 0]]).layoutEdits == nil)
        // The base of earlier test builds is removed.
        #expect(migration([State.legacyBaseKey: "old", State.layoutEditsKey: 0]) == State.Migration(removesLegacyBase: true, layoutEdits: nil))
    }

    // MARK: Recording an exchange

    @Test("A write and an adoption record the layout edits their side saw, so an edit made while the exchange ran still counts")
    func recordsCapturedEdits() {
        let layouts = Policy.Layouts(backend: .service26)
        let settings: [String: Any] = ["ShowOnHover": true, layouts.own: ["a": 0]]
        let start = State(base: "base", baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced)
        // The exchange starts with the count it sees.
        let local = Policy.Local(settings: settings, layouts: layouts, state: start, layoutEdits: start.layoutEdits, postponed: nil, forcesWrite: false)
        #expect(local.layoutEdits == 4)
        #expect(local.editsLayout)

        // The user edits while the exchange runs.
        var written = start
        written.countLayoutEdit()
        written.recordWrite(Policy.WriteRecord(layoutDigest: "written", takesInLayout: false), modified: lastSynced.addingTimeInterval(10), local: local)
        #expect(written.syncedLayoutEdits == 4)
        #expect(written.layoutEdits == 5)
        #expect(written.editsLayout)

        var kept = start
        kept.countLayoutEdit()
        kept.recordWrite(Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true), modified: lastSynced.addingTimeInterval(10), local: local)
        #expect(kept.syncedLayoutEdits == 4)
        #expect(kept.editsLayout)

        let version = Policy.Version(
            isFromThisMac: false,
            modified: lastSynced.addingTimeInterval(10),
            isNewer: true,
            userDigest: local.userDigest,
            layoutDigest: "version"
        )
        var adopted = start
        adopted.countLayoutEdit()
        adopted.recordAdoption(version, local: local, takesInOwnLayout: false)
        #expect(adopted.syncedLayoutEdits == 4)
        #expect(adopted.editsLayout)

        var takenIn = start
        takenIn.countLayoutEdit()
        takenIn.recordAdoption(version, local: local, takesInOwnLayout: true)
        #expect(takenIn.syncedLayoutEdits == 4)
        #expect(takenIn.editsLayout)

        // Without an edit in between, the exchange leaves none.
        var quiet = start
        quiet.recordWrite(Policy.WriteRecord(layoutDigest: "written", takesInLayout: false), modified: lastSynced.addingTimeInterval(10), local: local)
        #expect(!quiet.editsLayout)
    }

    @Test("Taking in a kept layout records only the layout; choosing another Mac's version records it whole")
    func recordUse() {
        let start = State(base: "base", baseLayoutDigest: "mine", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: lastSynced)
        let own = Policy.Version(isFromThisMac: true, modified: lastSynced.addingTimeInterval(10), isNewer: false, userDigest: "older", layoutDigest: "kept")
        var takenIn = start
        takenIn.recordUse(of: own, layoutDigest: own.layoutDigest, base: "applied")
        // This Mac's user settings stay unsynced changes; the layout edits no longer count.
        #expect(takenIn == State(base: "base", baseLayoutDigest: "kept", layoutEdits: 4, syncedLayoutEdits: 4, lastSynced: lastSynced, pending: nil, recentLayouts: ["kept"]))
        var launched = start
        launched.recordLayoutTakeIn(layoutDigest: nil)
        #expect(launched.baseLayoutDigest == Policy.noLayoutDigest)
        #expect(!launched.editsLayout)
        #expect(launched.pending == nil)

        let other = Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(10), isNewer: true, userDigest: "other", layoutDigest: "theirs")
        var used = start
        used.recordUse(of: other, layoutDigest: other.layoutDigest, base: "applied")
        // The digest of the version is kept apart from this Mac's, which may hold settings the
        // version lacks.
        #expect(used == State(base: "applied", baseLayoutDigest: "theirs", layoutEdits: 4, syncedLayoutEdits: 4, lastSynced: other.modified, pending: nil, versionDigest: "other", recentLayouts: ["theirs"]))
    }

    @Test("Adopting this Mac's own version with a layout to take in waits without pausing pushes")
    func recordOwnAdoption() {
        let local = Policy.Local(userDigest: "mine", base: nil, pending: nil, postponed: nil, forcesWrite: false, layoutDigest: "placements")
        let own = Policy.Version(isFromThisMac: true, modified: lastSynced.addingTimeInterval(10), isNewer: false, userDigest: "mine", layoutDigest: "kept")
        var state = State(baseLayoutDigest: "kept", lastSynced: lastSynced)
        state.recordAdoption(own, local: local, takesInOwnLayout: true)
        #expect(state == State(base: "mine", baseLayoutDigest: "placements", lastSynced: own.modified, pending: nil, versionDigest: "mine", recentLayouts: ["placements", "kept"]))
        let other = Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(10), isNewer: true, userDigest: "mine", layoutDigest: "theirs")
        var waiting = State(baseLayoutDigest: "theirs", lastSynced: lastSynced)
        waiting.recordAdoption(other, local: local, takesInOwnLayout: true)
        #expect(waiting == State(base: "mine", baseLayoutDigest: "placements", lastSynced: lastSynced, pending: other.modified, versionDigest: "mine", recentLayouts: ["placements", "theirs"]))
    }

    @Test("A sync remembers the last layouts it synced, the newest first")
    func recentLayouts() {
        var state = State()
        state.markSynced(base: "b", layout: nil, layoutEdits: 0, modified: nil)
        #expect(state.recentLayouts.isEmpty)
        state.markSynced(base: "b", layout: Policy.noLayoutDigest, layoutEdits: 0, modified: nil)
        #expect(state.recentLayouts.isEmpty)
        for index in 0 ..< 10 {
            state.recordWrite(Policy.WriteRecord(layoutDigest: "l\(index)", takesInLayout: false), modified: nil, local: Policy.Local(userDigest: "b", base: "b", pending: nil, postponed: nil, forcesWrite: false))
        }
        #expect(state.recentLayouts == ["l9", "l8", "l7", "l6", "l5", "l4", "l3", "l2"])
        // A layout synced again moves to the front.
        state.markSynced(base: "b", layout: "l5", layoutEdits: 0, modified: nil)
        #expect(state.recentLayouts == ["l5", "l9", "l8", "l7", "l6", "l4", "l3", "l2"])
        // A kept layout's write remembers the written layout and this Mac's.
        var kept = State()
        let local = Policy.Local(userDigest: "b", base: "b", pending: nil, postponed: nil, forcesWrite: false, layoutDigest: "mine")
        kept.recordWrite(Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true), modified: nil, local: local)
        #expect(kept.recentLayouts == ["mine", "kept"])
        // They stay when this Mac leaves the folder, and are read back at most eight.
        kept.leaveFolder(forgetsLastSync: true)
        #expect(kept.recentLayouts == ["mine", "kept"])
        let stored: [String: Any] = [State.recentLayoutsKey: (0 ..< 12).map { "s\($0)" }]
        #expect(State(reading: { stored[$0] }).recentLayouts.count == State.recentLayoutLimit)
        #expect(Policy.Local(settings: [:], layouts: Policy.Layouts(backend: .service26), state: kept, layoutEdits: 0, postponed: nil, forcesWrite: false).recentLayouts == ["mine", "kept"])
    }

    @Test("Leaving the folder forgets the user settings and the waiting version, but keeps the layout last synced and the layout edits")
    func leaveFolder() {
        let start = State(base: "base", baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: lastSynced, versionDigest: "v")
        var off = start
        off.leaveFolder(forgetsLastSync: false)
        #expect(off == State(base: nil, baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: nil))
        var other = start
        other.leaveFolder(forgetsLastSync: true)
        #expect(other == State(base: nil, baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: nil, pending: nil))
    }

    // MARK: Planning a write

    @Test("A planned write records the layout it wrote, and a kept layout of another Mac's to take in", arguments: [MenuBarBackendKind.service26, .accessibility27])
    func planWrite(backend: MenuBarBackendKind) {
        let layouts = Policy.Layouts(backend: backend)
        let syncedLayout: [String: Any] = ["a": 0, "b": 1]
        let mine: [String: Any] = ["ShowOnHover": false, layouts.own: ["a": 0, "b": 1, "placed": 1]]
        let file: [String: Any] = ["ShowOnHover": true, layouts.own: ["a": 5, "b": 1]]
        let state = State(
            base: Policy.userDigest(of: [:]),
            baseLayoutDigest: Policy.layoutDigest(of: [layouts.own: syncedLayout], layouts: layouts),
            lastSynced: lastSynced
        )
        let keeps = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 0, postponed: nil, forcesWrite: true)

        // Without a layout change of the user's, the file's arrangement is kept and waits to be
        // taken in.
        let kept = Policy.planWrite(mine, file: file, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        let keptLayout: [String: Any] = ["a": 5, "b": 1, "placed": 1]
        #expect(Policy.digest(of: ["l": kept.settings[layouts.own] as Any]) == Policy.digest(of: ["l": keptLayout]))
        #expect(kept.settings["ShowOnHover"] as? Bool == false)
        #expect(kept.currentLayouts == [layouts.own])
        #expect(kept.record == Policy.WriteRecord(layoutDigest: Policy.layoutDigest(of: [layouts.own: keptLayout], layouts: layouts), takesInLayout: true))

        // After a layout change of the user's, this Mac's layout is written and nothing waits.
        let edited = Policy.Local(settings: mine, layouts: layouts, state: state, layoutEdits: 1, postponed: nil, forcesWrite: true)
        let own = Policy.planWrite(mine, file: file, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: edited)
        #expect(own.record == Policy.WriteRecord(layoutDigest: Policy.layoutDigest(of: mine, layouts: layouts), takesInLayout: false))

        // A file whose layout is not current, or the one this Mac last synced, leaves nothing
        // to take in.
        let unlisted = Policy.planWrite(mine, file: file, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        #expect(!unlisted.record.takesInLayout)
        let syncedFile: [String: Any] = ["ShowOnHover": true, layouts.own: syncedLayout]
        let same = Policy.planWrite(mine, file: syncedFile, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        #expect(!same.record.takesInLayout)
        let empty = Policy.planWrite(mine, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: keeps)
        #expect(empty.record == Policy.WriteRecord(layoutDigest: Policy.layoutDigest(of: mine, layouts: layouts), takesInLayout: false))
        #expect(!empty.insertsCopy)

        // This Mac's copy of the other macOS version's layout is added only to a file without
        // one (F-60), and the plan says so.
        let withCopy = mine.merging([layouts.other: ["o": 1]]) { $1 }
        #expect(Policy.planWrite(withCopy, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: keeps).insertsCopy)
        #expect(Policy.planWrite(withCopy, file: file, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps).insertsCopy)
        let fileWithOther = file.merging([layouts.other: ["o": 2]]) { $1 }
        #expect(!Policy.planWrite(withCopy, file: fileWithOther, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps).insertsCopy)
    }
}
