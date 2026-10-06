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
        #expect(Set(every.changes(from: State()).map(\.key)) == [
            State.baseKey, State.baseLayoutKey, State.layoutEditsKey, State.syncedLayoutEditsKey, State.lastSyncedKey, State.pendingKey,
        ])
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

        var adopted = start
        adopted.countLayoutEdit()
        adopted.recordAdoption(layoutDigest: "version", modified: lastSynced.addingTimeInterval(10), local: local, takesInOwnLayout: false)
        #expect(adopted.syncedLayoutEdits == 4)
        #expect(adopted.editsLayout)

        var takenIn = start
        takenIn.countLayoutEdit()
        takenIn.recordAdoption(layoutDigest: "version", modified: lastSynced.addingTimeInterval(10), local: local, takesInOwnLayout: true)
        #expect(takenIn.syncedLayoutEdits == 4)
        #expect(takenIn.editsLayout)

        // Without an edit in between, the exchange leaves none.
        var quiet = start
        quiet.recordWrite(Policy.WriteRecord(layoutDigest: "written", takesInLayout: false), modified: lastSynced.addingTimeInterval(10), local: local)
        #expect(!quiet.editsLayout)
    }

    @Test("Leaving the folder forgets the user settings and the waiting version, but keeps the layout last synced and the layout edits")
    func leaveFolder() {
        let start = State(base: "base", baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: lastSynced)
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
    }
}
