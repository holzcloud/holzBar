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
        #expect(State.keptLayoutKey == "SettingsSyncKeptLayoutDigest")
        #expect(State.lastWrittenKey == "SettingsSyncLastWritten")
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
        every.keptLayoutDigest = "k"
        every.lastWritten = lastSynced
        #expect(every.versionDigest == "b")
        #expect(Set(every.changes(from: State()).map(\.key)) == [
            State.baseKey, State.baseLayoutKey, State.layoutEditsKey, State.syncedLayoutEditsKey, State.lastSyncedKey, State.pendingKey,
            State.versionDigestKey, State.recentLayoutsKey, State.keptLayoutKey, State.lastWrittenKey,
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
        // The layout to take in is recorded as such, and is not one this Mac synced until it
        // is taken in.
        #expect(state == State(base: "mine", baseLayoutDigest: "placements", lastSynced: own.modified, pending: nil, versionDigest: "mine", recentLayouts: ["placements"], keptLayoutDigest: "kept"))
        #expect(Policy.Local(settings: [:], layouts: Policy.Layouts(backend: .service26), state: state, layoutEdits: 0, postponed: nil, forcesWrite: false).keptLayoutDigest == "kept")
        let other = Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(10), isNewer: true, userDigest: "mine", layoutDigest: "theirs")
        var waiting = State(baseLayoutDigest: "theirs", lastSynced: lastSynced)
        waiting.recordAdoption(other, local: local, takesInOwnLayout: true)
        #expect(waiting == State(base: "mine", baseLayoutDigest: "placements", lastSynced: lastSynced, pending: other.modified, versionDigest: "mine", recentLayouts: ["placements"]))
        // Adopting a version whose layout this Mac holds remembers it.
        var adopted = State(lastSynced: lastSynced)
        adopted.recordAdoption(other, local: local, takesInOwnLayout: false)
        #expect(adopted.recentLayouts == ["theirs"])
    }

    @Test("A sync remembers the last layouts it synced, the newest first")
    func recentLayouts() {
        var state = State()
        state.markSynced(base: "b", layout: nil, layoutEdits: 0, modified: nil)
        #expect(state.recentLayouts.isEmpty)
        state.markSynced(base: "b", layout: Policy.noLayoutDigest, layoutEdits: 0, modified: nil)
        #expect(state.recentLayouts.isEmpty)
        // Many days of rearranging while a Mac still on 0.0.7 beta 1 may write an old copy back.
        #expect(State.recentLayoutLimit == 64)
        let writes = State.recentLayoutLimit + 2
        for index in 0 ..< writes {
            state.recordWrite(Policy.WriteRecord(layoutDigest: "l\(index)", takesInLayout: false), modified: nil, local: Policy.Local(userDigest: "b", base: "b", pending: nil, postponed: nil, forcesWrite: false))
        }
        #expect(state.recentLayouts == (2 ..< writes).reversed().map { "l\($0)" })
        // A layout synced again moves to the front.
        state.markSynced(base: "b", layout: "l5", layoutEdits: 0, modified: nil)
        #expect(state.recentLayouts == ["l5"] + (2 ..< writes).reversed().filter { $0 != 5 }.map { "l\($0)" })
        // A kept layout's write remembers only this Mac's layout: the kept one is another
        // Mac's arrangement until this Mac takes it in.
        var kept = State()
        let local = Policy.Local(userDigest: "b", base: "b", pending: nil, postponed: nil, forcesWrite: false, layoutDigest: "mine")
        kept.recordWrite(Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true), modified: nil, local: local)
        #expect(kept.recentLayouts == ["mine"])
        #expect(kept.keptLayoutDigest == "kept")
        var takenIn = kept
        takenIn.recordLayoutTakeIn(layoutDigest: "kept")
        #expect(takenIn.recentLayouts == ["kept", "mine"])
        // They stay when this Mac leaves the folder, and are read back at most the limit.
        kept.leaveFolder(forgetsLastSync: true)
        #expect(kept.recentLayouts == ["mine"])
        let stored: [String: Any] = [State.recentLayoutsKey: (0 ..< State.recentLayoutLimit + 4).map { "s\($0)" }]
        #expect(State(reading: { stored[$0] }).recentLayouts.count == State.recentLayoutLimit)
        #expect(Policy.Local(settings: [:], layouts: Policy.Layouts(backend: .service26), state: takenIn, layoutEdits: 0, postponed: nil, forcesWrite: false).recentLayouts == ["mine", "kept"])
    }

    @Test("A kept layout stays recorded until it is taken in, applied over or written over, also when this Mac leaves the folder")
    func keptLayoutRecord() {
        let local = Policy.Local(userDigest: "mine", base: "base", pending: nil, postponed: nil, forcesWrite: false, layoutDigest: "placements")
        var kept = State(base: "base", baseLayoutDigest: "placements", lastSynced: lastSynced)
        kept.recordWrite(Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true), modified: lastSynced.addingTimeInterval(10), local: local)
        #expect(kept.keptLayoutDigest == "kept")
        #expect(kept.baseLayoutDigest == "placements")
        // A later push that keeps it records it again; one that writes this Mac's layout ends it.
        var again = kept
        again.recordWrite(Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true), modified: lastSynced.addingTimeInterval(20), local: local)
        #expect(again.keptLayoutDigest == "kept")
        var overwritten = kept
        overwritten.recordWrite(Policy.WriteRecord(layoutDigest: "dragged", takesInLayout: false), modified: lastSynced.addingTimeInterval(20), local: local)
        #expect(overwritten.keptLayoutDigest == nil)
        // Taking it in, or applying another Mac's version, ends it.
        var takenIn = kept
        takenIn.recordLayoutTakeIn(layoutDigest: "kept")
        #expect(takenIn.keptLayoutDigest == nil)
        var applied = kept
        applied.recordApplied(Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(30), isNewer: true, userDigest: "other", layoutDigest: "theirs"), base: "other", layoutDigest: "theirs")
        #expect(applied.keptLayoutDigest == nil)
        // Adopting another Mac's version ends it, as the file no longer holds it as this Mac's.
        var adopted = kept
        adopted.recordAdoption(Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(30), isNewer: true, userDigest: "mine"), local: local, takesInOwnLayout: false)
        #expect(adopted.keptLayoutDigest == nil)
        // Leaving the folder keeps it, whether the date of the last sync goes or not.
        for forgetsLastSync in [false, true] {
            var left = kept
            left.leaveFolder(forgetsLastSync: forgetsLastSync)
            #expect(left.keptLayoutDigest == "kept")
            #expect(Policy.Local(settings: [:], layouts: Policy.Layouts(backend: .service26), state: left, layoutEdits: 0, postponed: nil, forcesWrite: false).keptLayoutDigest == "kept")
        }
    }

    @Test("An old copy this Mac writes over stays remembered however often the user rearranges meanwhile")
    func oldCopyRemembered() {
        let local = Policy.Local(userDigest: "b", base: "b", pending: nil, postponed: nil, forcesWrite: false)
        var state = State()
        state.recordWrite(Policy.WriteRecord(layoutDigest: "copy", takesInLayout: false), modified: nil, local: local)
        for round in 0 ..< 3 {
            for index in 0 ..< State.recentLayoutLimit - 1 {
                state.recordWrite(Policy.WriteRecord(layoutDigest: "r\(round)-\(index)", takesInLayout: false), modified: nil, local: local)
            }
            // A Mac still on beta 1 wrote the copy back; this Mac writes over it.
            state.recordWrite(Policy.WriteRecord(layoutDigest: "r\(round)-over", takesInLayout: false, oldCopyDigest: "copy"), modified: nil, local: local)
            #expect(state.recentLayouts.prefix(2) == ["r\(round)-over", "copy"])
        }
        // Also when the write keeps another Mac's layout to take in.
        var kept = State(recentLayouts: ["copy"])
        kept.recordWrite(Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true, oldCopyDigest: "copy"), modified: nil, local: local)
        #expect(kept.recentLayouts.contains("copy"))
        // Without one, nothing else is remembered.
        var plain = State()
        plain.recordWrite(Policy.WriteRecord(layoutDigest: "w", takesInLayout: false), modified: nil, local: local)
        #expect(plain.recentLayouts == ["w"])
    }

    @Test("A version of another Mac's that is not newer never moves the date of the last sync")
    func notNewerKeepsLastSynced() {
        let future = lastSynced.addingTimeInterval(365 * 24 * 60 * 60)
        let ahead = Policy.Version(isFromThisMac: false, modified: future, isNewer: false, userDigest: "other", layoutDigest: "theirs")
        #expect(ahead.syncedDate == nil)
        var used = State(base: "base", lastSynced: lastSynced)
        used.recordUse(of: ahead, layoutDigest: ahead.layoutDigest, base: "applied")
        #expect(used.lastSynced == lastSynced)
        #expect(used.versionDigest == "other")
        let local = Policy.Local(userDigest: "other", base: "base", pending: nil, postponed: nil, forcesWrite: false)
        var adopted = State(base: "base", lastSynced: lastSynced)
        adopted.recordAdoption(ahead, local: local, takesInOwnLayout: false)
        #expect(adopted.lastSynced == lastSynced)
        // A newer version, and this Mac's own, record their date.
        let newer = Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: true, userDigest: "other")
        let own = Policy.Version(isFromThisMac: true, modified: lastSynced.addingTimeInterval(90), isNewer: false, userDigest: "other")
        #expect(newer.syncedDate == newer.modified)
        #expect(own.syncedDate == own.modified)
        adopted.recordAdoption(own, local: local, takesInOwnLayout: false)
        #expect(adopted.lastSynced == own.modified)
        var applied = State(base: "base", lastSynced: lastSynced)
        applied.recordApplied(newer, base: "applied", layoutDigest: nil)
        #expect(applied.lastSynced == newer.modified)
    }

    @Test("Leaving the folder forgets the user settings and the waiting version, but keeps the layout last synced and the layout edits")
    func leaveFolder() {
        let start = State(base: "base", baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: lastSynced, versionDigest: "v", keptLayoutDigest: "kept")
        var off = start
        off.leaveFolder(forgetsLastSync: false)
        #expect(off == State(base: nil, baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: lastSynced, pending: nil, keptLayoutDigest: "kept"))
        var other = start
        other.leaveFolder(forgetsLastSync: true)
        #expect(other == State(base: nil, baseLayoutDigest: "layout", layoutEdits: 4, syncedLayoutEdits: 3, lastSynced: nil, pending: nil, keptLayoutDigest: "kept"))
    }

    // MARK: Acting on decisions

    @Test("Acting on a decision while holzBar runs stores the state and changes the hint as each action needs")
    func outcomes() {
        let local = Policy.Local(userDigest: "mine", base: "base", pending: nil, postponed: nil, forcesWrite: false, layoutDigest: "placements")
        let start = State(base: "base", baseLayoutDigest: "placements", lastSynced: lastSynced, versionDigest: "base")
        let other = Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: true, userDigest: "other", layoutDigest: "theirs")
        let own = Policy.Version(isFromThisMac: true, modified: lastSynced.addingTimeInterval(60), isNewer: false, userDigest: "mine", layoutDigest: "kept")
        func outcome(
            _ action: Policy.Action,
            isCheck: Bool = false,
            version: Policy.Version? = nil,
            state: State? = nil,
            takesInOwnLayout: Bool = false,
            written: (record: Policy.WriteRecord, modified: Date?)? = nil
        ) -> Policy.Outcome {
            Policy.outcome(of: action, isCheck: isCheck, version: version, local: local, state: state ?? start, takesInOwnLayout: takesInOwnLayout, written: written)
        }

        // Nothing waits any more.
        var waiting = start
        waiting.pending = other.modified
        #expect(outcome(.none, version: other, state: waiting) == Policy.Outcome(state: start, hint: .withdraw))
        // Nothing now.
        for action in [Policy.Action.wait, .retry] {
            #expect(outcome(action, version: other, state: waiting) == Policy.Outcome(state: waiting, hint: .unchanged))
        }
        // A version from another Mac to apply or ask about waits, and pauses pushes.
        for action in [Policy.Action.apply, .ask] {
            #expect(outcome(action, version: other) == Policy.Outcome(state: waiting, hint: .offerFileVersion))
            #expect(outcome(action) == Policy.Outcome(state: start, hint: .unchanged))
        }
        // This Mac's own version with a kept layout waits without pausing pushes.
        let takeIn = outcome(.takeInLayout, version: own)
        #expect(takeIn == Policy.Outcome(state: start, hint: .offerFileVersion))
        #expect(takeIn.state.pending == nil)
        #expect(outcome(.takeInLayout) == Policy.Outcome(state: start, hint: .unchanged))

        // An adoption that takes a layout in offers it: this Mac's own version without pausing
        // pushes, another Mac's as a version to apply.
        var adoptedOwn = start
        adoptedOwn.recordAdoption(own, local: local, takesInOwnLayout: true)
        #expect(outcome(.adopt, version: own, takesInOwnLayout: true) == Policy.Outcome(state: adoptedOwn, hint: .offerFileVersion))
        #expect(adoptedOwn.keptLayoutDigest == "kept")
        #expect(adoptedOwn.pending == nil)
        let adoptedOther = outcome(.adopt, version: other, takesInOwnLayout: true)
        #expect(adoptedOther.hint == .offerFileVersion)
        #expect(adoptedOther.state.pending == other.modified)
        // Any other adoption withdraws the hint.
        var adopted = start
        adopted.recordAdoption(other, local: local, takesInOwnLayout: false)
        #expect(outcome(.adopt, version: other) == Policy.Outcome(state: adopted, hint: .withdraw))
        var adoptedNone = start
        adoptedNone.recordAdoption(nil, local: local, takesInOwnLayout: false)
        #expect(outcome(.adopt, takesInOwnLayout: true) == Policy.Outcome(state: adoptedNone, hint: .withdraw))

        // A check never writes: a push follows.
        #expect(outcome(.write, isCheck: true, version: other, state: waiting) == Policy.Outcome(state: start, hint: .withdraw, pushes: true))
        // A write that kept another Mac's layout offers the written version; any other write
        // withdraws the hint.
        let keptRecord = Policy.WriteRecord(layoutDigest: "kept", takesInLayout: true)
        let writeDate = lastSynced.addingTimeInterval(90)
        var wroteKept = start
        wroteKept.recordWrite(keptRecord, modified: writeDate, local: local)
        #expect(outcome(.write, version: other, written: (keptRecord, writeDate)) == Policy.Outcome(state: wroteKept, hint: .offerWrittenVersion))
        let plainRecord = Policy.WriteRecord(layoutDigest: "placements", takesInLayout: false)
        var wrote = start
        wrote.recordWrite(plainRecord, modified: writeDate, local: local)
        #expect(outcome(.write, version: other, written: (plainRecord, writeDate)) == Policy.Outcome(state: wrote, hint: .withdraw))
        #expect(outcome(.write, version: other) == Policy.Outcome(state: start, hint: .unchanged))
        // Only a check that found changes pushes.
        for action in [Policy.Action.none, .wait, .retry, .adopt, .apply, .ask, .takeInLayout] {
            #expect(!outcome(action, isCheck: true, version: other).pushes)
        }
    }

    @Test("The launch applies the version, the folder's layout or a kept layout as decided, and records it")
    func launch() {
        #expect(Policy.launchApplication(for: .apply) == .settings)
        #expect(Policy.launchApplication(for: .adopt) == .ownLayout)
        #expect(Policy.launchApplication(for: .takeInLayout) == .keptLayout)
        for action in [Policy.Action.none, .wait, .retry, .write, .ask] {
            #expect(Policy.launchApplication(for: action) == .nothing)
        }

        let local = Policy.Local(userDigest: "mine", base: "base", pending: nil, postponed: nil, forcesWrite: false, layoutDigest: "placements")
        let start = State(base: "base", baseLayoutDigest: "placements", layoutEdits: 3, syncedLayoutEdits: 2, lastSynced: lastSynced, versionDigest: "base", keptLayoutDigest: "kept")
        let other = Policy.Version(isFromThisMac: false, modified: lastSynced.addingTimeInterval(60), isNewer: true, userDigest: "other", layoutDigest: "theirs")
        let own = Policy.Version(isFromThisMac: true, modified: lastSynced.addingTimeInterval(60), isNewer: false, userDigest: "mine", layoutDigest: "kept")
        func launched(_ action: Policy.Action, _ version: Policy.Version?, appliedBase: String? = "applied") -> State {
            var state = start
            state.recordLaunch(action, version: version, local: local, appliedBase: appliedBase)
            return state
        }
        var applied = start
        applied.recordApplied(other, base: "applied", layoutDigest: "theirs")
        #expect(launched(.apply, other) == applied)
        #expect(launched(.apply, nil) == start)
        #expect(launched(.apply, other, appliedBase: nil) == start)
        var adopted = start
        adopted.recordAdoption(other, local: local, takesInOwnLayout: false)
        #expect(launched(.adopt, other) == adopted)
        var takenIn = start
        takenIn.recordLayoutTakeIn(layoutDigest: "kept")
        #expect(launched(.takeInLayout, own) == takenIn)
        #expect(takenIn.keptLayoutDigest == nil)
        #expect(takenIn.base == "base")
        #expect(launched(.takeInLayout, nil) == start)
        var asked = start
        asked.pending = other.modified
        #expect(launched(.ask, other) == asked)
        var waiting = start
        waiting.pending = other.modified
        var cleared = waiting
        cleared.recordLaunch(.none, version: other, local: local, appliedBase: nil)
        #expect(cleared == start)
        for action in [Policy.Action.write, .wait, .retry] {
            var state = waiting
            state.recordLaunch(action, version: other, local: local, appliedBase: "applied")
            #expect(state == waiting)
        }
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

        // A write over an unlisted old copy of a layout this Mac synced records it.
        let copyLayout: [String: Any] = ["a": 9, "b": 1]
        let copyDigest = Policy.layoutDigest(of: [layouts.own: copyLayout], layouts: layouts)
        let beta1File: [String: Any] = ["ShowOnHover": true, layouts.own: copyLayout]
        var remembers = keeps
        remembers.recentLayouts = [copyDigest]
        let overCopy = Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: remembers)
        #expect(overCopy.record.oldCopyDigest == copyDigest)
        #expect(overCopy.currentLayouts.contains(layouts.own))
        // Not an unlisted layout this Mac never synced, nor a listed one or a marked copy.
        #expect(Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: keeps).record.oldCopyDigest == nil)
        #expect(Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: remembers).record.oldCopyDigest == nil)
        #expect(Policy.planWrite(mine, file: beta1File, fileCurrentLayouts: [], fileCopiedLayouts: [layouts.own], layouts: layouts, local: remembers).record.oldCopyDigest == nil)

        // This Mac's copy of the other macOS version's layout is added only to a file without
        // one (F-60), and the plan says so.
        let withCopy = mine.merging([layouts.other: ["o": 1]]) { $1 }
        #expect(Policy.planWrite(withCopy, file: nil, fileCurrentLayouts: [], fileCopiedLayouts: [], layouts: layouts, local: keeps).insertsCopy)
        #expect(Policy.planWrite(withCopy, file: file, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps).insertsCopy)
        let fileWithOther = file.merging([layouts.other: ["o": 2]]) { $1 }
        #expect(!Policy.planWrite(withCopy, file: fileWithOther, fileCurrentLayouts: [layouts.own], fileCopiedLayouts: [], layouts: layouts, local: keeps).insertsCopy)
    }
}
