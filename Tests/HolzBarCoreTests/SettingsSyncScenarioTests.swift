import Foundation
import Testing
@testable import HolzBarCore

private typealias Policy = SettingsSyncPolicy

/// A sync folder with one sync file, as its property list, or none.
private final class SyncFolder {
    var file: [String: Any]?

    /// The layouts the file lists as current.
    var currentLayouts: [String] {
        file?[SettingsSyncFile.currentLayoutsKey] as? [String] ?? []
    }
}

/// A Mac that syncs the way `SettingsSync` drives the Core decisions: an exchange decides,
/// writes and acts on the outcome; the launch applies what it decided; "Use Settings from
/// Sync Folder" and "Keep This Mac's Settings" answer the waiting version.
private final class SyncingMac {
    let id: String
    let layouts: Policy.Layouts
    var settings: [String: Any]
    var state = Policy.State()
    var keepsOver: Policy.Version?
    /// The version the hint offers, with its current settings and its unlisted layout.
    var waiting: (version: Policy.Version, current: [String: Any], unlisted: [String: Any]?)?

    init(_ id: String, backend: MenuBarBackendKind, settings: [String: Any]) {
        self.id = id
        layouts = Policy.Layouts(backend: backend)
        self.settings = settings
    }

    /// This Mac's layout for its macOS version.
    var layout: [String: Int] {
        settings[layouts.own] as? [String: Int] ?? [:]
    }

    /// The hint for the waiting version, if any.
    var hint: Policy.Hint? {
        waiting.map { Policy.hint(for: local(), version: $0.version) }
    }

    func local(forcesWrite: Bool = false) -> Policy.Local {
        var local = Policy.Local(settings: settings, layouts: layouts, state: state, layoutEdits: state.layoutEdits, postponed: nil, forcesWrite: forcesWrite)
        if forcesWrite {
            local.keepsOver = keepsOver
        }
        return local
    }

    /// The user rearranges this Mac's menu bar.
    func arrange(_ layout: [String: Int]) {
        settings[layouts.own] = layout
        state.countLayoutEdit()
    }

    private struct Inspection {
        var file: Policy.File
        var version: Policy.Version?
        var current: [String: Any]?
        var fileSettings: [String: Any]?
        var currentLayouts: Set<String> = []
        var copiedLayouts: Set<String> = []
        var unlisted: [String: Any]?
    }

    private func inspect(_ folder: SyncFolder, now: Date) -> Inspection {
        guard let file = folder.file else {
            return Inspection(file: .missing)
        }
        guard let contents = SettingsSyncFile.contents(of: file, lastSynced: state.lastSynced, deviceID: id, computerName: nil, localKeys: [], now: now) else {
            return Inspection(file: .unusable)
        }
        let current = Policy.withoutStaleLayouts(contents.settings, currentLayouts: contents.currentLayouts)
        let unlistedDigest = Policy.unlistedLayoutDigest(
            in: contents.settings,
            currentLayouts: contents.currentLayouts,
            copiedLayouts: contents.copiedLayouts,
            layouts: layouts
        )
        let version = Policy.Version(
            settings: current,
            layouts: layouts,
            isFromThisMac: contents.isFromThisMac,
            modified: contents.modified,
            isNewer: contents.isNewer,
            unlistedLayoutDigest: unlistedDigest,
            seen: contents.seen,
            seenWrite: contents.seenWrite
        )
        return Inspection(
            file: .version(version),
            version: version,
            current: current,
            fileSettings: contents.settings,
            currentLayouts: contents.currentLayouts,
            copiedLayouts: contents.copiedLayouts,
            unlisted: unlistedDigest.flatMap { _ in contents.settings[layouts.own].map { [layouts.own: $0] } }
        )
    }

    private func apply(_ applied: [String: Any]) {
        settings.merge(applied) { $1 }
    }

    /// An exchange while holzBar runs: a push of this Mac's changes, a check of the file, or
    /// the write of "Keep This Mac's Settings".
    @discardableResult
    func exchange(_ folder: SyncFolder, at now: Date, check: Bool = false, keep: Bool = false) -> Policy.Action {
        let local = local(forcesWrite: keep)
        let trigger: Policy.Trigger = check ? .check : .localChange
        guard Policy.needsExchange(trigger, local: local) else {
            return .none
        }
        let inspection = inspect(folder, now: now)
        let action = Policy.decide(trigger, local: local, file: inspection.file)
        var written: (record: Policy.WriteRecord, modified: Date?)?
        var plan: Policy.WritePlan?
        if action == .write, !check {
            let planned = Policy.planWrite(
                settings,
                file: inspection.fileSettings,
                fileCurrentLayouts: inspection.currentLayouts,
                fileCopiedLayouts: inspection.copiedLayouts,
                fileVersion: inspection.version,
                layouts: layouts,
                local: local
            )
            folder.file = SettingsSyncFile.fileToWrite(plan: planned, deviceID: id, modified: now)
            written = (planned.record, now)
            plan = planned
        }
        var takesInOwnLayout = false
        if action == .adopt, let version = inspection.version, let current = inspection.current {
            apply(Policy.otherLayoutToTakeIn(current, over: settings, layouts: layouts, version: version, local: local))
            takesInOwnLayout = !Policy.ownLayoutToTakeIn(current, over: settings, layouts: layouts, local: local, version: version).isEmpty
        }
        let outcome = Policy.outcome(
            of: action,
            isCheck: check,
            version: inspection.version,
            local: local,
            state: state,
            takesInOwnLayout: takesInOwnLayout,
            written: written
        )
        state = outcome.state
        switch outcome.hint {
        case .unchanged:
            break
        case .withdraw:
            waiting = nil
        case .offerFileVersion:
            if let version = inspection.version, let current = inspection.current {
                waiting = (version, current, inspection.unlisted)
            }
        case .offerWrittenVersion:
            if let plan {
                let current = Policy.withoutStaleLayouts(plan.settings, currentLayouts: Set(plan.currentLayouts))
                waiting = (Policy.Version(settings: current, layouts: layouts, isFromThisMac: true, modified: now, isNewer: false), current, nil)
            }
        }
        if outcome.pushes {
            exchange(folder, at: now)
        }
        return action
    }

    /// The launch: it applies what it decides before anything reads the settings.
    @discardableResult
    func launch(_ folder: SyncFolder, at now: Date) -> Policy.Action {
        waiting = nil
        let inspection = inspect(folder, now: now)
        let local = local()
        let action = Policy.decide(.launch, local: local, file: inspection.file)
        if let current = inspection.current, let version = inspection.version {
            apply(Policy.settingsToApplyAtLaunch(for: action, remote: current, over: settings, layouts: layouts, local: local, version: version))
        }
        let appliedBase = action == .apply ? Policy.userDigest(of: settings) : nil
        state.recordLaunch(action, version: inspection.version, local: local, appliedBase: appliedBase)
        if Policy.launchApplication(for: action) != .settings, state.base != nil, let current = inspection.current, let version = inspection.version {
            apply(Policy.settingsToTakeInAtLaunch(from: current, over: settings, layouts: layouts, version: version, local: local))
        }
        return action
    }

    /// "Use Settings from Sync Folder", or Restart: applies the waiting version.
    func use() {
        guard let waiting else {
            return
        }
        let used = Policy.settingsToUse(waiting.current, unlisted: waiting.unlisted, over: settings, layouts: layouts, version: waiting.version, local: local())
        apply(used.settings)
        state.recordUse(of: waiting.version, layoutDigest: used.layoutDigest, base: Policy.userDigest(of: settings))
        self.waiting = nil
    }

    /// "Keep This Mac's Settings" for the waiting version.
    @discardableResult
    func keep(_ folder: SyncFolder, at now: Date) -> Policy.Action {
        guard let waiting else {
            return .none
        }
        keepsOver = waiting.version
        return exchange(folder, at: now, keep: true)
    }

    /// Sync is turned off; the folder stays the same.
    func turnSyncOff() {
        state.leaveFolder(forgetsLastSync: false)
        keepsOver = nil
        waiting = nil
    }
}

/// A date of the scenarios, `seconds` into them.
private func at(_ seconds: Double) -> Date {
    Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
}

/// Whole scenarios across several Macs, each step as the app takes it.
@Suite("SettingsSyncPolicy scenarios")
struct SettingsSyncScenarioTests {
    private let older: [String: Int] = ["a": 0, "b": 0]
    private let newer: [String: Int] = ["a": 1, "b": 1]

    @Test("Keep This Mac's Settings over an older version a sync app brings back keeps the newest arrangement on every Mac", arguments: [false, true])
    func keepOverRestoredVersion(rejoins: Bool) {
        let folder = SyncFolder()
        let a = SyncingMac("A", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let b = SyncingMac("B", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let d = SyncingMac("D", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        #expect(b.exchange(folder, at: at(100)) == .write)
        let restored = folder.file
        a.exchange(folder, at: at(110))
        d.exchange(folder, at: at(120))
        // D arranges the newest layout; A and B take it.
        d.arrange(newer)
        #expect(d.exchange(folder, at: at(200)) == .write)
        a.exchange(folder, at: at(210), check: true)
        a.use()
        b.exchange(folder, at: at(215), check: true)
        b.use()
        #expect(a.layout == newer)
        // A sync app brings B's older version back; D asks about it.
        if rejoins {
            a.turnSyncOff()
        }
        folder.file = restored
        #expect(d.exchange(folder, at: at(300), check: true) == .ask)
        // A asks too, and the user keeps A's settings.
        #expect(a.exchange(folder, at: at(310), check: true) == .ask)
        #expect(a.hint == .choice(isJoining: rejoins))
        #expect(a.keep(folder, at: at(320)) == .write)
        #expect(folder.currentLayouts.contains("ItemSections"))
        #expect(a.waiting == nil)
        a.launch(folder, at: at(330))
        d.exchange(folder, at: at(340), check: true)
        d.launch(folder, at: at(350))
        b.launch(folder, at: at(360))
        #expect(a.layout == newer)
        #expect(d.layout == newer)
        #expect(b.layout == newer)
    }

    @Test("A rearrangement lost with the sync file survives Keep This Mac's Settings, and a third Mac that took it asks")
    func keepAfterLostWrite() {
        let folder = SyncFolder()
        let a = SyncingMac("A", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let b = SyncingMac("B", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let c = SyncingMac("C", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        b.exchange(folder, at: at(100))
        a.exchange(folder, at: at(110))
        c.exchange(folder, at: at(120))
        c.settings["ShowOnScroll"] = true
        c.exchange(folder, at: at(130))
        a.exchange(folder, at: at(131), check: true)
        a.use()
        b.exchange(folder, at: at(132), check: true)
        b.use()
        // A rearranges and writes; C takes it. The file goes away before B reads it, and B
        // writes a change over the missing file.
        a.arrange(newer)
        a.exchange(folder, at: at(200))
        c.exchange(folder, at: at(201), check: true)
        c.use()
        #expect(c.layout == newer)
        folder.file = nil
        b.settings["ShowOnHover"] = false
        #expect(b.exchange(folder, at: at(300)) == .write)
        // C holds A's write, which B's version lacks: it asks, and its launch keeps A's.
        #expect(c.exchange(folder, at: at(301), check: true) == .ask)
        #expect(c.hint == .choice(isJoining: false))
        #expect(c.launch(folder, at: at(302)) == .ask)
        #expect(c.layout == newer)
        // A asks and keeps its settings: its arrangement stays, and reaches every Mac.
        #expect(a.exchange(folder, at: at(310), check: true) == .ask)
        #expect(a.keep(folder, at: at(320)) == .write)
        a.launch(folder, at: at(330))
        #expect(a.layout == newer)
        c.exchange(folder, at: at(331), check: true)
        c.launch(folder, at: at(332))
        b.launch(folder, at: at(333))
        #expect(c.layout == newer)
        #expect(b.layout == newer)
    }

    @Test("A Mac that applied a version holding only a copy of its layout writes its layout as a copy over a missing file, so the Mac that arranged it keeps it")
    func copyAfterAppliedCopy() {
        let folder = SyncFolder()
        let a = SyncingMac("A", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let d = SyncingMac("D", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        d.exchange(folder, at: at(100))
        a.exchange(folder, at: at(110))
        d.arrange(newer)
        d.exchange(folder, at: at(200))
        // A keeps its settings over D's rearrangement and waits to take it in.
        a.settings["ShowOnClick"] = true
        #expect(a.exchange(folder, at: at(210), check: true) == .ask)
        #expect(a.keep(folder, at: at(220)) == .write)
        #expect(a.state.keptLayoutDigest != nil)
        // The file goes away; A writes its layout as a copy, and D keeps its arrangement.
        folder.file = nil
        a.settings["ShowOnScroll"] = true
        a.exchange(folder, at: at(300))
        #expect(!folder.currentLayouts.contains("ItemSections"))
        d.exchange(folder, at: at(310), check: true)
        d.use()
        #expect(d.layout == newer)
        // D changes a setting, passing the copy on; A applies it, which ends its kept layout.
        d.settings["ShowOnHover"] = false
        d.exchange(folder, at: at(400))
        a.exchange(folder, at: at(410), check: true)
        a.use()
        #expect(a.state.keptLayoutDigest == nil)
        #expect(a.layout == older)
        // The file goes away again: A's layout is still written as a copy, so D's arrangement
        // stays.
        folder.file = nil
        a.settings["ShowOnClick"] = false
        a.exchange(folder, at: at(500))
        #expect(!folder.currentLayouts.contains("ItemSections"))
        d.exchange(folder, at: at(510), check: true)
        d.launch(folder, at: at(520))
        #expect(d.layout == newer)
    }

    @Test("A copy made of an arrangement dated before the last sync, then one lost file, never reverts that arrangement")
    func copyByDateThenLostFile() {
        let folder = SyncFolder()
        let start: [String: Any] = ["ShowOnHover": true, "ItemSections": older, "MacOS27Layout": ["x": 0]]
        let d = SyncingMac("D", backend: .service26, settings: start)
        let a = SyncingMac("A", backend: .service26, settings: start)
        let c = SyncingMac("C", backend: .accessibility27, settings: start)
        d.exchange(folder, at: at(100))
        a.exchange(folder, at: at(110))
        c.exchange(folder, at: at(120))
        c.settings["ShowOnClick"] = true
        c.exchange(folder, at: at(300))
        d.exchange(folder, at: at(301), check: true)
        d.use()
        a.exchange(folder, at: at(302), check: true)
        a.use()
        // D's clock runs behind: its rearrangement is dated before C's last sync, so C's next
        // write passes it on as a copy.
        d.arrange(newer)
        d.exchange(folder, at: at(250))
        c.settings["ShowOnScroll"] = true
        c.exchange(folder, at: at(400))
        #expect(!folder.currentLayouts.contains("ItemSections"))
        d.exchange(folder, at: at(401), check: true)
        d.use()
        a.exchange(folder, at: at(402), check: true)
        a.use()
        #expect(a.layout == older)
        // The file goes away; A writes a change over the missing file.
        folder.file = nil
        a.settings["ShowOnHover"] = false
        a.exchange(folder, at: at(500))
        #expect(!folder.currentLayouts.contains("ItemSections"))
        d.exchange(folder, at: at(501), check: true)
        d.launch(folder, at: at(502))
        #expect(d.layout == newer)
    }

    @Test("Keep This Mac's Settings answered while the sync file is missing records the answered version, so its Mac neither asks again nor loses its arrangement", arguments: [false, true])
    func keepWhileFileMissing(rearrangedThere: Bool) {
        let folder = SyncFolder()
        let a = SyncingMac("A", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let b = SyncingMac("B", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        b.exchange(folder, at: at(100))
        a.exchange(folder, at: at(110))
        b.settings["ShowOnClick"] = true
        if rearrangedThere {
            b.arrange(newer)
        }
        b.exchange(folder, at: at(200))
        // A changed a setting too: it asks. The file goes away, and the user keeps A's.
        a.settings["ShowOnScroll"] = true
        #expect(a.exchange(folder, at: at(210), check: true) == .ask)
        folder.file = nil
        #expect(a.keep(folder, at: at(220)) == .write)
        #expect(a.waiting == nil)
        // B's arrangement is answered with a copy of A's layout, so B keeps it.
        #expect(folder.currentLayouts.contains("ItemSections") == !rearrangedThere)
        // B takes A's settings with a restart, without asking again about the choice.
        #expect(b.exchange(folder, at: at(230), check: true) == .apply)
        #expect(b.hint == .restart)
        b.launch(folder, at: at(240))
        #expect(b.settings["ShowOnScroll"] as? Bool == true)
        #expect(b.layout == (rearrangedThere ? newer : older))
        #expect(a.layout == older)
    }

    @Test("Keep This Mac's Settings answered while the sync file is missing lists this Mac's arrangement when the answered version lacked it")
    func keepStaleWhileFileMissing() {
        let folder = SyncFolder()
        let a = SyncingMac("A", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        let b = SyncingMac("B", backend: .service26, settings: ["ShowOnHover": true, "ItemSections": older])
        b.exchange(folder, at: at(100))
        a.exchange(folder, at: at(110))
        // A rearranges; the file goes away before B reads it, and B writes over it.
        a.arrange(newer)
        a.exchange(folder, at: at(200))
        folder.file = nil
        b.settings["ShowOnHover"] = false
        b.exchange(folder, at: at(300))
        #expect(a.exchange(folder, at: at(310), check: true) == .ask)
        // The file goes away again before the user keeps A's settings.
        folder.file = nil
        #expect(a.keep(folder, at: at(320)) == .write)
        #expect(folder.currentLayouts.contains("ItemSections"))
        b.exchange(folder, at: at(330), check: true)
        b.launch(folder, at: at(340))
        #expect(b.layout == newer)
        #expect(a.layout == newer)
    }
}
