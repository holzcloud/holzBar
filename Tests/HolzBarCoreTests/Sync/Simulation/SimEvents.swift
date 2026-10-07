import Foundation

/// Which side of a prompt a pick keeps.
enum SimPromptSide: String, Hashable, Sendable {
    case local
    case folder
}

/// How the user answers an open prompt. The old peer's alert understands `use` (Restart) and `later`.
enum SimAnswer: Hashable, Sendable {
    /// "Use Settings from Sync Folder" (Restart on the old peer).
    case use
    /// "Keep This Mac's Settings".
    case keep
    case later
    case cancel
    /// A per-unit pop-up pick: which side wins for each listed unit.
    case pick([String: SimPromptSide])

    var canonical: String {
        switch self {
        case .use: "use"
        case .keep: "keep"
        case .later: "later"
        case .cancel: "cancel"
        case .pick(let picks):
            "pick(" + picks.keys.sorted().map { "\($0)=\(picks[$0]!.rawValue)" }.joined(separator: ",") + ")"
        }
    }
}

/// How foreign bytes look when "another app or person" puts them into the folder (A2 section 6.3).
enum SimForeignKind: String, Hashable, Sendable, CaseIterable {
    case symbolicLink
    case oversize
    case truncatedPlist
    case typeSwappedPlist
    case garbage
}

/// Provider events: the faults of A2 section 2.2. Durations are relative to the global clock at the event.
enum SimProviderEvent: Hashable, Sendable {
    case restore(folder: String = "F1", path: String, version: Int)
    case delete(folder: String = "F1", path: String)
    case deleteFolder(folder: String = "F1")
    case evict(folder: String = "F1", path: String, mac: SimMacName)
    case exposePartial(folder: String = "F1", path: String, mac: SimMacName, forMilliseconds: Int64)
    /// A stall of `forMilliseconds`; `nil` is a hung provider (forever).
    case stall(folder: String = "F1", mac: SimMacName, forMilliseconds: Int64?)
    case unmount(folder: String = "F1", mac: SimMacName)
    case mount(folder: String = "F1", mac: SimMacName)
    case foreign(folder: String = "F1", path: String, kind: SimForeignKind)
    /// The Mac neither sends nor receives for `forMilliseconds`.
    case offline(folder: String = "F1", mac: SimMacName, forMilliseconds: Int64)
}

/// The full event alphabet (analysis section 5.3). Every Mac kind receives every event; a kind that
/// does not understand an event records it and ignores it. Later plans add behaviour, not cases.
enum SimEvent: Hashable, Sendable {
    // MARK: User
    /// A user edit. `nil` value mints a fresh `u<k>@<unit>` token.
    case userEdit(mac: SimMacName, unit: String, value: SimValue? = nil)
    /// Reset to default, remove a hotkey, delete a profile.
    case userDelete(mac: SimMacName, unit: String)
    /// Import of a settings file that sets `units` (fresh tokens) and removes every importable key it lacks.
    case userImport(mac: SimMacName, units: [String])
    /// A hotkey assignment from a small combination pool, to provoke clashes.
    case setHotkey(mac: SimMacName, action: String, combo: Int)
    /// An item-icon choice on a title-changing app, to provoke re-keys.
    case chooseItemIcon(mac: SimMacName, item: String)
    case oversizeIcon(mac: SimMacName)
    /// A Layout-pane move on macOS 27 (one user change on `l27/<bundle>`).
    case moveApp27(mac: SimMacName, bundle: String, section: Int)
    /// Applying a layout profile; `byUser` is false for a Space or display binding.
    case applyProfile(mac: SimMacName, profile: String, byUser: Bool)
    case saveProfile(mac: SimMacName, profile: String)
    case renameProfile(mac: SimMacName, profile: String)
    case deleteProfile(mac: SimMacName, profile: String)
    case turnOn(mac: SimMacName, folder: String)
    case turnOff(mac: SimMacName)
    case changeFolder(mac: SimMacName, folder: String)
    case answer(mac: SimMacName, SimAnswer)

    // MARK: Automatic (holzBar or macOS, never the user)
    case autoPlace(mac: SimMacName, unit: String)
    case learn(mac: SimMacName, key: String)
    case setFlag(mac: SimMacName, key: String)
    /// macOS 27 layout seeding: fills only apps without an entry.
    case seed27(mac: SimMacName)
    case placeNewApp27(mac: SimMacName, bundle: String)
    /// macOS 26 to 27.
    case upgradeOS(mac: SimMacName)

    // MARK: Lifecycle
    case launch(mac: SimMacName)
    case quit(mac: SimMacName)
    /// A crash: the process dies without running any quit code.
    case crash(mac: SimMacName)
    /// The user restarts the app (quit, then launch).
    case restartApp(mac: SimMacName)
    /// Updates or downgrades the app on that Mac (it quits first).
    case updateApp(mac: SimMacName, version: SimMacVersion)

    // MARK: Identity
    /// Migration Assistant or a disk clone: `to` gets `from`'s preferences and sync state on other hardware.
    case clone(from: SimMacName, to: SimMacName)
    /// Same hardware, another user account.
    case copyAccount(from: SimMacName, to: SimMacName)
    /// Same hardware, older preferences and sync state.
    case restorePrefs(mac: SimMacName)
    case restoreSigma(mac: SimMacName)
    /// Defaults and sync state together, with Caches kept or lost.
    case restoreHome(mac: SimMacName, keepCaches: Bool)
    case sigmaLost(mac: SimMacName)
    case reinstall(mac: SimMacName)

    // MARK: Time
    /// Virtual time passes; due deliveries and timers run in order.
    case advance(milliseconds: Int64)
    /// The Mac's clock jumps by this much (also backwards).
    case clockStep(mac: SimMacName, milliseconds: Int64)
    /// A timer the Mac's brain scheduled. Raised by the world itself.
    case timerFired(mac: SimMacName, tag: String)

    // MARK: Provider
    case provider(SimProviderEvent)

    /// The Mac the event acts on, when it has one.
    var mac: SimMacName? {
        switch self {
        case .userEdit(let mac, _, _), .userDelete(let mac, _), .userImport(let mac, _),
             .setHotkey(let mac, _, _), .chooseItemIcon(let mac, _), .oversizeIcon(let mac),
             .moveApp27(let mac, _, _), .applyProfile(let mac, _, _), .saveProfile(let mac, _),
             .renameProfile(let mac, _), .deleteProfile(let mac, _), .turnOn(let mac, _),
             .turnOff(let mac), .changeFolder(let mac, _), .answer(let mac, _),
             .autoPlace(let mac, _), .learn(let mac, _), .setFlag(let mac, _), .seed27(let mac),
             .placeNewApp27(let mac, _), .upgradeOS(let mac), .launch(let mac), .quit(let mac),
             .crash(let mac), .restartApp(let mac), .updateApp(let mac, _), .restorePrefs(let mac),
             .restoreSigma(let mac), .restoreHome(let mac, _), .sigmaLost(let mac),
             .reinstall(let mac), .clockStep(let mac, _), .timerFired(let mac, _):
            mac
        case .clone(_, let to), .copyAccount(_, let to):
            to
        case .advance, .provider:
            nil
        }
    }

    /// A canonical one-line rendering. Stable across runs and platforms; the trace hash uses it.
    var canonical: String {
        switch self {
        case .userEdit(let mac, let unit, let value):
            return "userEdit(\(mac),\(unit),\(value?.canonical ?? "fresh"))"
        case .userDelete(let mac, let unit): return "userDelete(\(mac),\(unit))"
        case .userImport(let mac, let units): return "userImport(\(mac),\(units.sorted().joined(separator: "|")))"
        case .setHotkey(let mac, let action, let combo): return "setHotkey(\(mac),\(action),\(combo))"
        case .chooseItemIcon(let mac, let item): return "chooseItemIcon(\(mac),\(item))"
        case .oversizeIcon(let mac): return "oversizeIcon(\(mac))"
        case .moveApp27(let mac, let bundle, let section): return "moveApp27(\(mac),\(bundle),\(section))"
        case .applyProfile(let mac, let profile, let byUser): return "applyProfile(\(mac),\(profile),\(byUser))"
        case .saveProfile(let mac, let profile): return "saveProfile(\(mac),\(profile))"
        case .renameProfile(let mac, let profile): return "renameProfile(\(mac),\(profile))"
        case .deleteProfile(let mac, let profile): return "deleteProfile(\(mac),\(profile))"
        case .turnOn(let mac, let folder): return "turnOn(\(mac),\(folder))"
        case .turnOff(let mac): return "turnOff(\(mac))"
        case .changeFolder(let mac, let folder): return "changeFolder(\(mac),\(folder))"
        case .answer(let mac, let answer): return "answer(\(mac),\(answer.canonical))"
        case .autoPlace(let mac, let unit): return "autoPlace(\(mac),\(unit))"
        case .learn(let mac, let key): return "learn(\(mac),\(key))"
        case .setFlag(let mac, let key): return "setFlag(\(mac),\(key))"
        case .seed27(let mac): return "seed27(\(mac))"
        case .placeNewApp27(let mac, let bundle): return "placeNewApp27(\(mac),\(bundle))"
        case .upgradeOS(let mac): return "upgradeOS(\(mac))"
        case .launch(let mac): return "launch(\(mac))"
        case .quit(let mac): return "quit(\(mac))"
        case .crash(let mac): return "crash(\(mac))"
        case .restartApp(let mac): return "restartApp(\(mac))"
        case .updateApp(let mac, let version): return "updateApp(\(mac),\(version.rawValue))"
        case .clone(let from, let to): return "clone(\(from)->\(to))"
        case .copyAccount(let from, let to): return "copyAccount(\(from)->\(to))"
        case .restorePrefs(let mac): return "restorePrefs(\(mac))"
        case .restoreSigma(let mac): return "restoreSigma(\(mac))"
        case .restoreHome(let mac, let keep): return "restoreHome(\(mac),keepCaches=\(keep))"
        case .sigmaLost(let mac): return "sigmaLost(\(mac))"
        case .reinstall(let mac): return "reinstall(\(mac))"
        case .advance(let milliseconds): return "advance(\(milliseconds))"
        case .clockStep(let mac, let milliseconds): return "clockStep(\(mac),\(milliseconds))"
        case .timerFired(let mac, let tag): return "timerFired(\(mac),\(tag))"
        case .provider(let event): return "provider.\(event.canonical)"
        }
    }
}

extension SimProviderEvent {
    var canonical: String {
        switch self {
        case .restore(let folder, let path, let version): "restore(\(folder),\(path),v\(version))"
        case .delete(let folder, let path): "delete(\(folder),\(path))"
        case .deleteFolder(let folder): "deleteFolder(\(folder))"
        case .evict(let folder, let path, let mac): "evict(\(folder),\(path),\(mac))"
        case .exposePartial(let folder, let path, let mac, let duration): "exposePartial(\(folder),\(path),\(mac),\(duration))"
        case .stall(let folder, let mac, let duration): "stall(\(folder),\(mac),\(duration.map(String.init) ?? "forever"))"
        case .unmount(let folder, let mac): "unmount(\(folder),\(mac))"
        case .mount(let folder, let mac): "mount(\(folder),\(mac))"
        case .foreign(let folder, let path, let kind): "foreign(\(folder),\(path),\(kind.rawValue))"
        case .offline(let folder, let mac, let duration): "offline(\(folder),\(mac),\(duration))"
        }
    }
}
