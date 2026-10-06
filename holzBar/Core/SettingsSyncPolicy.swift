//
//  SettingsSyncPolicy.swift
//  holzBar
//

import CryptoKit
import Foundation

/// Decides what settings sync does with the sync file: nothing, write this Mac's
/// settings, adopt or apply the file's, or ask the user (F-02).
///
/// Each Mac keeps a digest of the settings it last wrote or applied, its base. Settings
/// that differ from the base are this Mac's own changes; a file whose settings differ
/// from this Mac's is another Mac's. When both changed, or when a Mac joins a folder that
/// holds another Mac's different settings, holzBar asks which settings to use instead of
/// overwriting either.
///
/// Keys holzBar learns by itself (``learnedKeys``) never count as a change: they are
/// merged, never asked about.
///
/// Each Mac compares only the layout of the macOS version it runs (``Layouts``), and only
/// once the user changed it: holzBar's own placements of new items do not count (SA-05).
/// The other macOS version's layout is passed on unchanged and taken in like a learned key,
/// never compared, so a Mac before macOS 27 and a macOS 27 Mac with the same settings are
/// not asked about their layouts.
nonisolated enum SettingsSyncPolicy {
    /// The keys holzBar writes by itself rather than the user: the items and apps it has
    /// seen, and flags that a one-time step is done. They only ever grow, so the Macs merge
    /// them (arrays as their union, flags with OR) instead of replacing them.
    static let learnedKeys: Set<String> = Set(
        [
            Defaults.Key.knownItemTags,
            .knownApplications27,
            .titleChangingItemOwners,
            .macOS27LayoutSeeded,
            .hasMigrated0_8_0,
            .hasMigrated0_10_0,
            .hasMigrated0_10_1,
            .hasMigrated0_11_10,
            .hasMigrated0_11_13,
            .hasMigrated0_11_13_1,
            .hasImportedPreviousSettings,
        ].map(\.rawValue)
    )

    /// The settings without the ``learnedKeys``.
    static func userSettings(_ settings: [String: Any]) -> [String: Any] {
        settings.filter { !learnedKeys.contains($0.key) }
    }

    /// The digest of the user's settings: the values holzBar would apply
    /// (`Defaults.Key.validatedSettings`) without the ``learnedKeys`` and without the
    /// layouts (``layoutKeys``), which each Mac compares on its own
    /// (``layoutDigest(of:layouts:)``).
    static func userDigest(of settings: [String: Any]) -> String {
        digest(of: userSettings(Defaults.Key.validatedSettings(settings).accepted).filter { !layoutKeys.contains($0.key) })
    }

    /// A SHA-256 digest of the settings, as 64 lower-case hexadecimal characters.
    ///
    /// The encoding is canonical, so equal settings give equal digests however they were
    /// stored: dictionary keys are sorted; a number is equal to the same number of another
    /// type (1 and 1.0), but not to a Boolean; data that holds JSON is compared by its
    /// contents, as the models encode it without sorting its keys; dates count in whole
    /// seconds, as the sync file stores them.
    static func digest(of settings: [String: Any]) -> String {
        var hasher = SHA256()
        feed(settings, into: &hasher)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Adds a canonical, type-tagged and length-prefixed encoding of `value` to `hasher`.
    private static func feed(_ value: Any, into hasher: inout SHA256) {
        func feedTag(_ tag: UInt8) {
            hasher.update(data: [tag])
        }
        func feedInteger(_ integer: Int64) {
            withUnsafeBytes(of: integer.littleEndian) { hasher.update(bufferPointer: $0) }
        }
        func feedBytes(_ bytes: Data) {
            feedInteger(Int64(bytes.count))
            hasher.update(data: bytes)
        }

        if CFGetTypeID(value as AnyObject) == CFBooleanGetTypeID(), let flag = value as? Bool {
            feedTag(flag ? 0x31 : 0x30)
            return
        }
        switch value {
        case let dictionary as [String: Any]:
            feedTag(0x44)
            feedInteger(Int64(dictionary.count))
            for key in dictionary.keys.sorted() {
                feedBytes(Data(key.utf8))
                if let element = dictionary[key] {
                    feed(element, into: &hasher)
                }
            }
        case let array as [Any]:
            feedTag(0x41)
            feedInteger(Int64(array.count))
            for element in array {
                feed(element, into: &hasher)
            }
        case let string as String:
            feedTag(0x53)
            feedBytes(Data(string.utf8))
        case let data as Data:
            if let json = try? JSONSerialization.jsonObject(with: data), json is [String: Any] || json is [Any] {
                feedTag(0x4A)
                feed(json, into: &hasher)
            } else {
                feedTag(0x42)
                feedBytes(data)
            }
        case let date as Date:
            feedTag(0x74)
            feedInteger(Int64(date.timeIntervalSinceReferenceDate.rounded(.down)))
        case let number as NSNumber:
            let double = number.doubleValue
            if double.rounded(.towardZero) == double, let integer = Int64(exactly: double) {
                feedTag(0x49)
                feedInteger(integer)
            } else {
                feedTag(0x52)
                feedInteger(Int64(bitPattern: double.bitPattern))
            }
        default:
            feedTag(0x3F)
            feedBytes(Data(String(describing: value).utf8))
        }
    }

    /// The learned settings (``learnedKeys``) of `local` merged with those of `remote`:
    /// string arrays as their sorted union, flags with OR.
    ///
    /// - Returns: Only the keys whose merged value differs from the local one; empty when
    ///   `local` already holds everything `remote` has learned.
    static func learnedSettings(merging remote: [String: Any], into local: [String: Any]) -> [String: Any] {
        var merged = [String: Any]()
        for key in learnedKeys {
            guard let remoteValue = remote[key], let kind = Defaults.Key(rawValue: key)?.settingsKind else {
                continue
            }
            switch kind {
            case .stringArray:
                guard let remoteArray = remoteValue as? [String] else {
                    continue
                }
                let localSet = Set(local[key] as? [String] ?? [])
                let union = localSet.union(remoteArray)
                if union != localSet || local[key] == nil {
                    merged[key] = union.sorted()
                }
            case .bool:
                guard SettingsSchema.matches(remoteValue, .bool), remoteValue as? Bool == true else {
                    continue
                }
                if local[key] as? Bool != true {
                    merged[key] = true
                }
            default:
                continue
            }
        }
        return merged
    }

    /// The settings to apply from the sync file: its user settings, and the learned
    /// settings merged with this Mac's.
    static func settingsToApply(_ remote: [String: Any], over local: [String: Any]) -> [String: Any] {
        userSettings(remote).merging(learnedSettings(merging: remote, into: local)) { _, merged in merged }
    }

    /// The settings to write into the sync file: this Mac's, with the learned settings
    /// merged with the file's.
    static func settingsToWrite(_ local: [String: Any], file remote: [String: Any]?) -> [String: Any] {
        guard let remote else {
            return local
        }
        return local.merging(learnedSettings(merging: remote, into: local)) { _, merged in merged }
    }

    // MARK: Decisions

    /// What makes holzBar look at the sync file.
    nonisolated enum Trigger: Sendable {
        /// The launch, before anything reads the settings. holzBar never writes or asks
        /// then.
        case launch
        /// The file changed, or setup finished.
        case check
        /// This Mac's settings changed.
        case localChange
    }

    /// This Mac's side of a decision.
    nonisolated struct Local: Equatable, Sendable {
        /// The digest of this Mac's user settings (``userDigest(of:)``).
        var userDigest: String
        /// The digest of the settings this Mac last wrote or applied; `nil` while it joins
        /// the folder: sync was just turned on, the folder changed, or this Mac's settings
        /// were copied from another Mac.
        var base: String?
        /// The date of a newer version from another Mac that waits for the user; while it
        /// waits, this Mac's changes are not written.
        var pending: Date?
        /// The date of the version the user answered "Later" for in this session.
        var postponed: Date?
        /// Whether the user chose to keep this Mac's settings. The keep writes over the
        /// version the user answered (``keepsOver``) or this Mac's own, never over another
        /// version, whatever its date.
        var forcesWrite: Bool
        /// The digest of this Mac's layout for its macOS version
        /// (``layoutDigest(of:layouts:)``).
        var layoutDigest: String?
        /// The layout digest of the sync file's layout for this Mac's macOS version when this
        /// Mac last synced (``noLayoutDigest`` when it had none).
        var baseLayoutDigest: String?
        /// Whether the user changed this Mac's layout since it last synced. holzBar's own
        /// placements of new items do not count.
        var editsLayout = false
        /// The number of layout edits this side saw (``State/layoutEdits``). A sync made with
        /// this side records it, so an edit made while the exchange ran still counts
        /// afterwards.
        var layoutEdits = 0
        /// The version the user answered with "Keep This Mac's Settings" (``forcesWrite``).
        var keepsOver: Version?
        /// The digest of the user settings of the version this Mac last wrote, applied or
        /// adopted (``State/versionDigest``); `nil` while it joins, or when an earlier build
        /// synced last.
        var versionDigest: String?
        /// The layout digests this Mac recently synced (``State/recentLayouts``).
        var recentLayouts: Set<String> = []
        /// The layout digest of another Mac's layout that this Mac's own version holds and
        /// this Mac has not taken in yet (``State/keptLayoutDigest``).
        var keptLayoutDigest: String?
        /// The date of the newest version this Mac synced with (``State/lastSynced``); `nil`
        /// when it has not synced.
        var lastSynced: Date?
        /// The date of this Mac's newest write whose changes its settings hold
        /// (``State/lastWritten``); `nil` when there is none to look for.
        var lastWritten: Date?
        /// The newest write of each other Mac whose changes this Mac's settings hold, by sync id
        /// (``State/seen``).
        var seen: [String: Date] = [:]

        /// Whether this Mac joins the folder.
        var isJoining: Bool {
            base == nil
        }

        /// Whether the user changed settings since this Mac last wrote or applied them.
        var hasChanges: Bool {
            base != userDigest || editsLayout
        }

        /// The layout this Mac holds against a version's: its own after a change of the
        /// user's; otherwise none while it joins, as holzBar's own layout has no say and the
        /// version's is taken in, and the one it last synced, as only holzBar's own placements
        /// differ from it.
        var comparedLayout: String? {
            if editsLayout {
                return layoutDigest
            }
            return isJoining ? nil : baseLayoutDigest
        }
    }

    /// A version of the sync file.
    nonisolated struct Version: Equatable, Sendable {
        /// Whether this Mac wrote it.
        var isFromThisMac: Bool
        /// When it was written.
        var modified: Date
        /// Whether another Mac wrote it after this Mac last synced, and it is not dated
        /// too far in the future.
        var isNewer: Bool
        /// The digest of its user settings (``userDigest(of:)``).
        var userDigest: String
        /// The digest of its current layout for this Mac's macOS version
        /// (``layoutDigest(of:layouts:)``); `nil` when it has none or does not list it as
        /// current (``SettingsSyncFile/currentLayoutsKey``).
        var layoutDigest: String?
        /// The layout digest of a layout for this Mac's macOS version that the version holds
        /// but does not list as current (``unlistedLayoutDigest(in:currentLayouts:copiedLayouts:layouts:)``);
        /// `nil` when it holds none.
        var unlistedLayoutDigest: String?
        /// The newest write of each other Mac that it holds, by sync id, its writer's among
        /// them (``SettingsSyncFile/seenKey``); `nil` for files of earlier builds.
        var seen: [String: Date]?
        /// The date of this Mac's newest write that it holds (``SettingsSyncFile/seenKey``);
        /// `nil` when it holds none, or records no writes.
        var seenWrite: Date?
    }

    /// What reading the sync file gave.
    nonisolated enum File: Equatable, Sendable {
        /// There is no file.
        case missing
        /// The file holds nothing holzBar can use (not a regular file, no date or
        /// settings); holzBar may write over it.
        case unusable
        /// The file could not be read now, or is larger than holzBar reads; holzBar must not
        /// write over it.
        case unreadable
        /// A version of the file.
        case version(Version)

        /// What a file holzBar refused to read is for the decision.
        ///
        /// A file larger than holzBar reads holds another Mac's settings, such as a large
        /// custom icon, that this Mac cannot see: writing over it would lose them unasked,
        /// and the Mac that wrote it would later apply this Mac's version silently. So it is
        /// left alone, like a file that cannot be read now.
        init(refusal: SettingsSyncFile.Refusal) {
            switch refusal {
            case .notRegularFile:
                self = .unusable
            case .tooLarge, .unreadable:
                self = .unreadable
            }
        }
    }

    /// What settings sync does.
    nonisolated enum Action: Equatable, Sendable {
        /// Nothing; no version waits for the user.
        case none
        /// Nothing; the user answered "Later" for this version.
        case wait
        /// Nothing now; the next trigger tries again.
        case retry
        /// The file holds this Mac's user settings: only remember it as synced.
        case adopt
        /// Write this Mac's settings into the file.
        case write
        /// Apply the file's settings: silently at launch, after a restart the user agrees
        /// to while holzBar runs.
        case apply
        /// The file holds this Mac's own version with another Mac's layout that this Mac kept
        /// and has not taken in: take in only that layout, silently at launch, after a
        /// restart the user agrees to while holzBar runs. This Mac's other changes are
        /// written as usual meanwhile.
        case takeInLayout
        /// Ask which settings to use.
        case ask
    }

    /// Whether the trigger needs the sync file at all.
    ///
    /// A change of this Mac's settings needs it only when the user settings differ from
    /// the base, and not while a version from another Mac waits for the user, so nothing
    /// overwrites that version.
    static func needsExchange(_ trigger: Trigger, local: Local) -> Bool {
        guard trigger == .localChange, !local.forcesWrite else {
            return true
        }
        return local.pending == nil && local.hasChanges
    }

    /// Decides what to do with the sync file.
    ///
    /// A version that holds this Mac's settings is adopted (``holdsLocalSettings(_:local:)``).
    /// A layout change of the user's that would replace a layout an earlier build wrote asks
    /// (``replacesUnlistedLayout(_:local:)``);
    /// a joining Mac whose layout the user did not change takes in the version's layout for
    /// its macOS version as it adopts
    /// (``ownLayoutToTakeIn(_:over:layouts:local:version:)``). A version that changed nothing
    /// this Mac uses since it last synced lets this Mac's changes win
    /// (``changedNothingSinceBase(_:local:)``). A version from another Mac dated before this
    /// Mac's last sync is never applied silently or written over while it holds changes this
    /// Mac has not synced: it asks (``isUnsyncedChange(_:local:)``).
    ///
    /// - Parameters:
    ///   - trigger: What made holzBar look at the file.
    ///   - local: This Mac's side.
    ///   - file: What reading the file gave.
    static func decide(_ trigger: Trigger, local: Local, file: File) -> Action {
        let isLaunch = trigger == .launch
        let writesChanges: Action = local.hasChanges && !isLaunch ? .write : .none
        switch file {
        case .unreadable:
            return .retry
        case .missing, .unusable:
            // A version from another Mac that waits for the user is never given up, or written
            // over, because the file went away: the hint keeps offering it until the user
            // answers, and keeping this Mac's settings writes.
            if !isLaunch, local.pending != nil, !local.forcesWrite {
                return .wait
            }
            return !isLaunch && (local.isJoining || local.forcesWrite || local.hasChanges) ? .write : .none
        case .version(let version):
            if holdsOlderLayoutToJoin(version, local: local) {
                // The user answered this question with "Keep This Mac's Settings": it writes
                // this Mac's layout over the version's, which may be stale
                // (``keepsOwnLayoutOverStale(_:local:)``), as for a Mac that is not joining.
                if keepsThisMac(over: version, local: local) {
                    return isLaunch ? .none : .write
                }
                if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                    return .wait
                }
                return .ask
            }
            if holdsLocalSettings(version, local: local) {
                return .adopt
            }
            if keepsThisMac(over: version, local: local) {
                return isLaunch ? .none : .write
            }
            if replacesUnlistedLayout(version, local: local) {
                if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                    return .wait
                }
                return .ask
            }
            if version.isFromThisMac {
                guard holdsLayoutToTakeIn(version, local: local) else {
                    return writesChanges
                }
                // This Mac kept another Mac's layout in its last write and has not taken it
                // in yet (``takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``):
                // only that layout is taken in, and a layout change of the user's asks, also
                // when this Mac joins the folder again before a restart. Other changes are
                // written meanwhile, keeping that layout.
                if local.editsLayout {
                    if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                        return .wait
                    }
                    return .ask
                }
                return isLaunch || !local.hasChanges ? .takeInLayout : writesChanges
            }
            if local.isJoining {
                // Only the user's layout differs from a file without one, or from the layout
                // this Mac last synced: nothing of another Mac's is lost.
                let keepsLayout = version.layoutDigest == nil || version.layoutDigest == local.baseLayoutDigest
                guard version.userDigest == local.userDigest, keepsLayout else {
                    return .ask
                }
                return isLaunch ? .none : .write
            }
            if changedNothingSinceBase(version, local: local) {
                return writesChanges
            }
            if !version.isNewer {
                // Dated before this Mac's last sync by a clock behind this Mac's, or kept by the
                // sync app over this Mac's later write: whether it holds this Mac's last changes
                // is unknown, so one this Mac has not synced asks.
                guard isUnsyncedChange(version, local: local) else {
                    return writesChanges
                }
                if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                    return .wait
                }
                return .ask
            }
            if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                return .wait
            }
            // A version written without a write this Mac's settings hold, its own or another
            // Mac's, would revert it: it asks.
            return local.hasChanges || missesLastWrite(version, local: local) ? .ask : .apply
        }
    }
}

// MARK: - Hints

nonisolated extension SettingsSyncPolicy {
    /// What holzBar offers for a newer version from another Mac that waits for the user.
    ///
    /// holzBar never opens a dialog by itself for it: the hint sits quietly in the sync
    /// settings and the holzBar menu until the user acts on it.
    enum Hint: Equatable, Sendable {
        /// Restart with the other Mac's settings; this Mac changed nothing since it last
        /// synced.
        case restart
        /// Ask in a sheet in Settings which settings to use: this Mac changed its settings
        /// too, or it joins the folder.
        case choice(isJoining: Bool)
    }

    /// The hint for a waiting version, given this Mac's side.
    ///
    /// It offers a restart exactly where ``decide(_:local:file:)`` applies a newer version
    /// from another Mac, and a choice where it asks.
    static func hint(for local: Local) -> Hint {
        if local.isJoining {
            return .choice(isJoining: true)
        }
        return local.hasChanges ? .choice(isJoining: false) : .restart
    }

    /// The hint for a waiting version when the user acts on it, given this Mac's side and
    /// whether a layout change of the user's is still to be saved.
    ///
    /// Before macOS 27, an arrangement on the bar is saved a moment after the user made it,
    /// once the bar shows it. Restarting before then would lose it, so it counts as a layout
    /// change of the user's: the hint asks instead.
    static func hint(for local: Local, savesLayoutSoon: Bool) -> Hint {
        var local = local
        if savesLayoutSoon {
            local.editsLayout = true
        }
        return hint(for: local)
    }

    /// The hint for a given waiting version, given this Mac's side.
    ///
    /// For this Mac's own version, which holds another Mac's layout it kept
    /// (``Action/takeInLayout``), only that layout is taken in: the hint offers a restart
    /// unless the user changed this Mac's layout, whatever other changes this Mac made. A
    /// version from another Mac that is not newer than this Mac's last sync is asked about
    /// (``isUnsyncedChange(_:local:)``).
    static func hint(for local: Local, version: Version) -> Hint {
        if version.isFromThisMac, !local.isJoining {
            return local.editsLayout ? .choice(isJoining: false) : .restart
        }
        // A version that is not newer, or one written without a write this Mac's settings
        // hold, may lack changes this Mac has: it asks.
        if !version.isNewer || missesLastWrite(version, local: local), !local.isJoining {
            return .choice(isJoining: false)
        }
        return hint(for: local)
    }

    /// The hint for a given waiting version when the user acts on it, given this Mac's side
    /// and whether a layout change of the user's is still to be saved
    /// (``hint(for:savesLayoutSoon:)``).
    static func hint(for local: Local, version: Version, savesLayoutSoon: Bool) -> Hint {
        var local = local
        if savesLayoutSoon {
            local.editsLayout = true
        }
        return hint(for: local, version: version)
    }
}

// MARK: - Layouts

nonisolated extension SettingsSyncPolicy {
    /// The two layout keys as one Mac sees them: the layout of the macOS version it runs,
    /// which it compares, and the other version's, which it passes on and takes in (SA-05).
    struct Layouts: Equatable, Sendable {
        /// This Mac's layout key: `ItemSections` before macOS 27, `MacOS27Layout` from it.
        let own: String
        /// The other macOS version's layout key.
        let other: String
        /// The learned list of the items or apps ``own`` has seen: `KnownItemTags` before
        /// macOS 27, `KnownApplications27` from it.
        let ownKnown: String

        /// The layout keys of a Mac with the given backend.
        init(backend: MenuBarBackendKind) {
            switch backend {
            case .windowList, .service26:
                own = Defaults.Key.itemSections.rawValue
                other = Defaults.Key.macOS27Layout.rawValue
                ownKnown = Defaults.Key.knownItemTags.rawValue
            case .accessibility27:
                own = Defaults.Key.macOS27Layout.rawValue
                other = Defaults.Key.itemSections.rawValue
                ownKnown = Defaults.Key.knownApplications27.rawValue
            }
        }
    }

    /// The layout keys of both macOS versions. The user digest leaves them out.
    static let layoutKeys: Set<String> = [Defaults.Key.itemSections.rawValue, Defaults.Key.macOS27Layout.rawValue]

    /// The layout digest of settings without a layout for this Mac's macOS version.
    static let noLayoutDigest = digest(of: [:])

    /// The digest of the layout for this Mac's macOS version in `settings`, as holzBar would
    /// apply it; ``noLayoutDigest`` when there is none.
    static func layoutDigest(of settings: [String: Any], layouts: Layouts) -> String {
        guard let layout = validatedLayout(in: settings, key: layouts.own) else {
            return noLayoutDigest
        }
        return digest(of: [layouts.own: layout])
    }

    /// The layout under `key` in `settings`, if holzBar would apply it.
    private static func validatedLayout(in settings: [String: Any]?, key: String) -> [String: Any]? {
        guard let value = settings?[key] else {
            return nil
        }
        return Defaults.Key.validatedSettings([key: value]).accepted[key] as? [String: Any]
    }

    /// The learned list of the items or apps `settings` have seen for ``Layouts/own``.
    private static func knownEntries(in settings: [String: Any]?, layouts: Layouts) -> Set<String> {
        Set(settings?[layouts.ownKnown] as? [String] ?? [])
    }

    /// The settings without the layouts the sync file does not list as current.
    ///
    /// Files of earlier builds list none: their copy of the other macOS version's layout may
    /// be older than the layout it stands for, so it is neither compared, applied nor taken
    /// in.
    static func withoutStaleLayouts(_ settings: [String: Any], currentLayouts: Set<String>) -> [String: Any] {
        settings.filter { !layoutKeys.contains($0.key) || currentLayouts.contains($0.key) }
    }

    /// The `remote` layout with every entry of `local` it has never seen: neither in it nor
    /// in `seen`, the remote's learned list. An entry the remote knows but lacks follows the
    /// remote.
    static func mergedLayout(_ remote: [String: Any], keeping local: [String: Any]?, seen: Set<String>) -> [String: Any] {
        guard let local else {
            return remote
        }
        let unseen = local.filter { remote[$0.key] == nil && !seen.contains($0.key) }
        return remote.merging(unseen) { remoteValue, _ in remoteValue }
    }

    /// The settings to apply from a version of the sync file
    /// (``settingsToApply(_:over:)``), with the layouts handled per macOS version.
    ///
    /// The other macOS version's layout comes from the version, or stays when it has none.
    /// This Mac's layout stays when the version has none, or when the version did not change
    /// it since this Mac last synced and the user did not change it here: then only holzBar's
    /// own placements differ, and they are kept. Otherwise the version's layout is applied
    /// with this Mac's entries it has never seen.
    ///
    /// - Parameters:
    ///   - remote: The version's current settings (``withoutStaleLayouts(_:currentLayouts:)``).
    ///   - local: This Mac's settings.
    ///   - layouts: This Mac's layout keys.
    ///   - baseLayoutDigest: The layout digest this Mac last synced.
    ///   - editsLayout: Whether the user changed this Mac's layout since it last synced.
    static func settingsToApply(
        _ remote: [String: Any],
        over local: [String: Any],
        layouts: Layouts,
        baseLayoutDigest: String?,
        editsLayout: Bool
    ) -> [String: Any] {
        var applied = settingsToApply(remote, over: local)
        guard
            let remoteLayout = validatedLayout(in: remote, key: layouts.own),
            editsLayout || layoutDigest(of: remote, layouts: layouts) != baseLayoutDigest
        else {
            applied[layouts.own] = nil
            return applied
        }
        applied[layouts.own] = mergedLayout(
            remoteLayout,
            keeping: validatedLayout(in: local, key: layouts.own),
            seen: knownEntries(in: remote, layouts: layouts)
        )
        return applied
    }

    /// The settings to apply when the user chooses a version's settings over this Mac's, and
    /// the layout digest to record as synced.
    ///
    /// Of this Mac's own version only the layout is used (``keptLayoutToTakeIn(_:over:layouts:)``):
    /// its user settings are this Mac's, perhaps older than its current ones.
    ///
    /// When the user's layout change would have replaced a layout the version holds unlisted
    /// (``replacesUnlistedLayout(_:local:)``), the question was about that layout: it is
    /// applied, with this Mac's entries it has never seen, and recorded as synced, so the
    /// next change of the user's does not ask about it again. Otherwise the version's
    /// settings are applied as ``settingsToApply(_:over:layouts:baseLayoutDigest:editsLayout:)``
    /// applies them.
    ///
    /// - Parameters:
    ///   - remote: The version's current settings
    ///     (``withoutStaleLayouts(_:currentLayouts:)``).
    ///   - unlisted: The version's settings that hold its unlisted layout, if any.
    ///   - settings: This Mac's settings.
    ///   - layouts: This Mac's layout keys.
    ///   - version: The version.
    ///   - local: This Mac's side.
    static func settingsToUse(
        _ remote: [String: Any],
        unlisted: [String: Any]?,
        over settings: [String: Any],
        layouts: Layouts,
        version: Version,
        local: Local
    ) -> (settings: [String: Any], layoutDigest: String?) {
        var applied = if version.isFromThisMac {
            keptLayoutToTakeIn(remote, over: settings, layouts: layouts)
        } else {
            settingsToApply(
                remote,
                over: settings,
                layouts: layouts,
                baseLayoutDigest: local.baseLayoutDigest,
                editsLayout: local.editsLayout
            )
        }
        guard
            replacesUnlistedLayout(version, local: local),
            let unlistedLayout = validatedLayout(in: unlisted, key: layouts.own)
        else {
            return (applied, version.layoutDigest)
        }
        applied[layouts.own] = mergedLayout(
            unlistedLayout,
            keeping: validatedLayout(in: settings, key: layouts.own),
            seen: knownEntries(in: remote, layouts: layouts)
        )
        return (applied, version.unlistedLayoutDigest)
    }

    /// The other macOS version's layout from a version of the sync file, when it differs
    /// from this Mac's copy: taken in silently, like a learned key.
    ///
    /// - Parameter remote: The version's current settings
    ///   (``withoutStaleLayouts(_:currentLayouts:)``).
    /// - Returns: The layout to apply, or an empty dictionary when there is nothing to take in.
    static func layoutToTakeIn(_ remote: [String: Any], over local: [String: Any], layouts: Layouts) -> [String: Any] {
        guard let remoteLayout = validatedLayout(in: remote, key: layouts.other) else {
            return [:]
        }
        let localLayout = validatedLayout(in: local, key: layouts.other)
        guard localLayout.map({ digest(of: $0) }) != digest(of: remoteLayout) else {
            return [:]
        }
        return [layouts.other: remoteLayout]
    }

    /// The layout for this Mac's macOS version from this Mac's own version of the sync file,
    /// which holds another Mac's layout that this Mac kept (``Action/takeInLayout``), with
    /// this Mac's entries it has never seen.
    ///
    /// - Parameter remote: The version's current settings
    ///   (``withoutStaleLayouts(_:currentLayouts:)``).
    /// - Returns: The layout to apply, or an empty dictionary when the version has no current
    ///   layout for this Mac's macOS version.
    static func keptLayoutToTakeIn(_ remote: [String: Any], over settings: [String: Any], layouts: Layouts) -> [String: Any] {
        guard let remoteLayout = validatedLayout(in: remote, key: layouts.own) else {
            return [:]
        }
        let merged = mergedLayout(
            remoteLayout,
            keeping: validatedLayout(in: settings, key: layouts.own),
            seen: knownEntries(in: remote, layouts: layouts)
        )
        return [layouts.own: merged]
    }

    /// The layout for this Mac's macOS version that a joining Mac takes in when it adopts a
    /// version and the user did not change its layout since it last synced: the version's,
    /// with this Mac's entries it has never seen.
    ///
    /// Such a Mac's layout holds only holzBar's own placements, or a layout it synced with
    /// another folder or before sync was turned off, so it has no say: the folder's arrangement
    /// wins without a question. A Mac that is not joining keeps its own placements, as its
    /// last sync recorded the version's layout (``settingsToApply(_:over:layouts:baseLayoutDigest:editsLayout:)``).
    ///
    /// - Parameters:
    ///   - remote: The version's current settings
    ///     (``withoutStaleLayouts(_:currentLayouts:)``).
    ///   - settings: This Mac's settings.
    ///   - layouts: This Mac's layout keys.
    ///   - local: This Mac's side of the decision that adopted the version.
    ///   - version: The version. One from another Mac that is not newer than this Mac's last
    ///     sync (``Version/isNewer``) is in this Mac's layout already, apart from holzBar's
    ///     own placements since, which stay. One this Mac wrote may hold another Mac's layout
    ///     that this Mac kept and has not taken in
    ///     (``takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``), as when sync
    ///     was turned off and on before a restart; it is taken in like a newer one. When its
    ///     layout is this Mac's own, this Mac already holds it.
    /// - Returns: The layout to apply, or an empty dictionary when there is nothing to take in:
    ///   this Mac is not joining, the user changed its layout, the version is another Mac's
    ///   and not newer, it has no current layout for this Mac's macOS version, or this Mac
    ///   already holds it.
    static func ownLayoutToTakeIn(
        _ remote: [String: Any],
        over settings: [String: Any],
        layouts: Layouts,
        local: Local,
        version: Version
    ) -> [String: Any] {
        guard
            local.isJoining,
            !local.editsLayout,
            version.isNewer || version.isFromThisMac
        else {
            return [:]
        }
        let takenIn = keptLayoutToTakeIn(remote, over: settings, layouts: layouts)
        guard !takenIn.isEmpty, layoutDigest(of: takenIn, layouts: layouts) != layoutDigest(of: settings, layouts: layouts) else {
            return [:]
        }
        return takenIn
    }

    /// The settings to write into the sync file (``settingsToWrite(_:file:)``), with the
    /// layouts handled per macOS version, and the layouts the written file lists as current.
    ///
    /// The other macOS version's layout is the file's, never this Mac's copy, which may be
    /// older. Only when the file has none is this Mac's copy written, and not listed as
    /// current: this build ignores it, and builds before it, which delete a layout missing from
    /// a file they apply (F-60), keep one. This Mac's layout is written when the
    /// user changed it (`keepsOwnLayout`) or the file has no layout for this Mac's macOS
    /// version; otherwise the file's current layout is kept, with only this Mac's entries it
    /// has never seen, so holzBar's own placements never replace another Mac's layout, and a
    /// Mac's copy of it is passed on as a copy, never listed as current. A layout for this Mac's
    /// macOS version that the file holds unlisted, as an earlier build wrote it, is kept as
    /// it is and stays unlisted unless the user changed this Mac's layout. A layout written
    /// unlisted as a Mac's copy is marked as one, and the mark is passed on.
    ///
    /// - Parameters:
    ///   - local: This Mac's settings.
    ///   - remote: The file's settings as read, if any.
    ///   - fileCurrentLayouts: The layouts the file lists as current.
    ///   - fileCopiedLayouts: The layouts the file marks as a Mac's copy
    ///     (``SettingsSyncFile/copiedLayoutsKey``); a copy of this Mac's layout counts as none.
    ///   - layouts: This Mac's layout keys.
    ///   - keepsOwnLayout: Whether this Mac's layout is written as it is: the user changed
    ///     it, or chose to keep this Mac's settings.
    ///   - passesOtherLayoutAsCopy: Whether the file's current layout of the other macOS
    ///     version is passed on marked as a copy, as it may be stale
    ///     (``passesOtherLayoutAsCopy(_:local:)``).
    ///   - writesOwnLayoutAsCopy: Whether this Mac's layout, written as it is, is marked as a
    ///     copy instead of listed as current (``writesOwnLayoutAsCopy(fileSettings:layouts:local:)``).
    static func fileToWrite(
        _ local: [String: Any],
        file remote: [String: Any]?,
        fileCurrentLayouts: Set<String>,
        fileCopiedLayouts: Set<String> = [],
        layouts: Layouts,
        keepsOwnLayout: Bool,
        passesOtherLayoutAsCopy: Bool = false,
        writesOwnLayoutAsCopy: Bool = false
    ) -> (settings: [String: Any], currentLayouts: [String], copiedLayouts: [String]) {
        var settings = settingsToWrite(local, file: remote)
        var currentLayouts = Set<String>()
        var copiedLayouts = Set<String>()
        // Files of earlier builds list no layout; their copy is carried on for those builds.
        // Without one, this Mac's copy, from ``settingsToWrite(_:file:)``, stays unlisted and
        // is marked as a copy.
        // A current one from a version older than this Mac's last sync may be stale: it is
        // passed on as a copy, which this build never applies.
        if let fileOther = remote?[layouts.other] {
            settings[layouts.other] = fileOther
            if fileCurrentLayouts.contains(layouts.other), !passesOtherLayoutAsCopy {
                currentLayouts.insert(layouts.other)
            } else if fileCurrentLayouts.contains(layouts.other) || fileCopiedLayouts.contains(layouts.other) {
                copiedLayouts.insert(layouts.other)
            }
        } else if settings[layouts.other] != nil {
            copiedLayouts.insert(layouts.other)
        }
        let fileLayout = fileCurrentLayouts.contains(layouts.own) ? validatedLayout(in: remote, key: layouts.own) : nil
        if local[layouts.own] == nil {
            settings[layouts.own] = remote?[layouts.own]
            if fileLayout != nil {
                currentLayouts.insert(layouts.own)
            } else if remote?[layouts.own] != nil, fileCopiedLayouts.contains(layouts.own) {
                copiedLayouts.insert(layouts.own)
            }
        } else if
            !keepsOwnLayout,
            !fileCurrentLayouts.contains(layouts.own),
            fileCopiedLayouts.contains(layouts.own),
            let fileCopy = remote?[layouts.own]
        {
            // A Mac's copy of this macOS version's layout, as written over a missing file or
            // passed on from an older version: the arrangement it stands for, perhaps newer
            // than this Mac's, is on the Macs that made it. Listing this Mac's layout, which
            // may be stale or hold only holzBar's own placements, would make them apply it
            // silently (SA-05). The copy is passed on as a copy; only a layout change of the
            // user's lists this Mac's layout as current again.
            settings[layouts.own] = fileCopy
            copiedLayouts.insert(layouts.own)
        } else if
            !keepsOwnLayout,
            !fileCurrentLayouts.contains(layouts.own),
            !fileCopiedLayouts.contains(layouts.own),
            let fileOwn = remote?[layouts.own]
        {
            // A layout an earlier build wrote, unlisted: a Mac of this macOS version that
            // still runs that build may have arranged it, and applies the file as it is. It
            // is passed on as it is, unlisted, and only a change of the user's replaces it
            // (``replacesUnlistedLayout(_:local:)``): also one this Mac synced before, which
            // may be an old copy written back, but as well that Mac's return to an earlier
            // arrangement.
            settings[layouts.own] = fileOwn
        } else {
            if !keepsOwnLayout, let fileLayout {
                settings[layouts.own] = mergedLayout(
                    fileLayout,
                    keeping: validatedLayout(in: local, key: layouts.own),
                    seen: knownEntries(in: remote, layouts: layouts)
                )
            }
            if writesOwnLayoutAsCopy {
                copiedLayouts.insert(layouts.own)
            } else {
                currentLayouts.insert(layouts.own)
            }
        }
        return (settings, currentLayouts.sorted(), copiedLayouts.sorted())
    }

    /// The layout digest this Mac records as synced after it wrote the sync file
    /// (``fileToWrite(_:file:fileCurrentLayouts:fileCopiedLayouts:layouts:keepsOwnLayout:)``).
    ///
    /// It is the written layout for this Mac's macOS version when the file lists it. A layout
    /// passed on unlisted counts only when it is the one this Mac last synced, as after the
    /// user chose it (``settingsToUse(_:unlisted:over:layouts:version:local:)``); otherwise
    /// this Mac has not taken it in, and the next change of the user's asks about it.
    ///
    /// - Parameters:
    ///   - written: The written settings.
    ///   - currentLayouts: The layouts the written file lists as current.
    ///   - copiedLayouts: The layouts the written file marks as a Mac's copy.
    ///   - layouts: This Mac's layout keys.
    ///   - local: This Mac's side of the decision that wrote.
    /// - Returns: The layout digest, or `nil` for none.
    static func syncedLayoutDigest(
        afterWriting written: [String: Any],
        currentLayouts: Set<String>,
        copiedLayouts: Set<String> = [],
        layouts: Layouts,
        local: Local
    ) -> String? {
        if currentLayouts.contains(layouts.own) {
            return layoutDigest(of: written, layouts: layouts)
        }
        let unlisted = unlistedLayoutDigest(in: written, currentLayouts: currentLayouts, copiedLayouts: copiedLayouts, layouts: layouts)
        return unlisted != nil && unlisted == local.baseLayoutDigest ? unlisted : nil
    }

    /// Whether this Mac writes its own layout for its macOS version as it is: only after a
    /// change of the user's. Otherwise the file's current layout is kept, even when the user
    /// chose to keep this Mac's settings over a newer version: this Mac's layout then holds
    /// only holzBar's own placements, which never replace another Mac's arrangement (SA-05).
    /// Only a version whose layout may be stale is written over
    /// (``keepsOwnLayoutOverStale(_:local:)``).
    static func writesOwnLayout(_ local: Local) -> Bool {
        local.editsLayout
    }

    /// Whether the user's "Keep This Mac's Settings" writes this Mac's layout for its macOS
    /// version over the answered version's, although the user did not change it: the version
    /// is another Mac's, lists a layout other than the one this Mac last synced, and is not
    /// newer than this Mac's last sync (``Version/isNewer``) or lacks this Mac's last write
    /// (``missesLastWrite(_:local:)``).
    ///
    /// Such a layout may be older than the arrangement the Macs use now: a sync app brought
    /// back an older version, or a Mac that never read this Mac's last write, as when the file
    /// went away, listed its own. Kept with a fresh date, it would be listed as current
    /// again, and every Mac that arranged a newer one would apply it silently, this Mac too
    /// at its restart, so the arrangement would be lost whichever answer the user gave
    /// (F-02). This Mac's layout is the one it last synced, with only holzBar's own placements
    /// since, which is what the user chose to keep.
    ///
    /// - Parameter fileVersion: The file's version before the write, if it holds one.
    static func keepsOwnLayoutOverStale(_ fileVersion: Version?, local: Local) -> Bool {
        guard
            let fileVersion,
            !fileVersion.isFromThisMac,
            keepsThisMac(over: fileVersion, local: local),
            let layout = fileVersion.layoutDigest,
            layout != local.baseLayoutDigest
        else {
            return false
        }
        return !fileVersion.isNewer || missesLastWrite(fileVersion, local: local)
    }

    /// Whether a write that kept the file's current layout for this Mac's macOS version
    /// leaves this Mac with another Mac's layout to take in: the user did not change this
    /// Mac's layout, the file's layout is not the one this Mac last synced, and the written
    /// layout is not this Mac's.
    ///
    /// That happens when the user chose to keep this Mac's settings over a newer version whose
    /// layout differs (over one that may be stale, this Mac's layout is written:
    /// ``keepsOwnLayoutOverStale(_:local:)``), or when this Mac wrote over a version that is
    /// not newer than its last sync without a question, as when an earlier build synced last
    /// (``isUnsyncedChange(_:local:)``). holzBar reads the layout at launch, so it is not
    /// applied now: this Mac records
    /// its own layout as synced, and the version it wrote waits for a restart
    /// (``State/recordWrite(_:modified:local:)``, ``Action/takeInLayout``).
    ///
    /// - Parameters:
    ///   - fileLayoutDigest: The layout digest of the file's current layout before the
    ///     write (``Version/layoutDigest``).
    ///   - writtenLayoutDigest: The layout digest this Mac records after the write
    ///     (``syncedLayoutDigest(afterWriting:currentLayouts:copiedLayouts:layouts:local:)``).
    ///   - local: This Mac's side of the decision that wrote.
    static func takesInKeptLayout(fileLayoutDigest: String?, writtenLayoutDigest: String?, local: Local) -> Bool {
        guard !writesOwnLayout(local), let fileLayoutDigest, let writtenLayoutDigest else {
            return false
        }
        return fileLayoutDigest != local.baseLayoutDigest && writtenLayoutDigest != local.layoutDigest
    }

    /// Whether a version this Mac wrote holds a layout for its macOS version that it has not
    /// taken in: the one it kept from another Mac
    /// (``takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``), as this Mac
    /// recorded it (``Local/keptLayoutDigest``).
    ///
    /// The record stays when this Mac leaves the folder, so a Mac that joins again before a
    /// restart still knows the layout is another Mac's arrangement: a layout change of the
    /// user's asks instead of writing over it. Any other layout of this Mac's own version is an
    /// old copy of this Mac's, as a sync app may bring back, and is never taken in.
    static func holdsLayoutToTakeIn(_ version: Version, local: Local) -> Bool {
        guard version.isFromThisMac, let layout = version.layoutDigest, layout == local.keptLayoutDigest else {
            return false
        }
        return layout != local.baseLayoutDigest
    }

    /// The writes of the other Macs that a write holds (``SettingsSyncFile/seenKey``), without
    /// this Mac's own: those this Mac's settings hold (``Local/seen``) and those of the file's
    /// version it writes over, the newest of each Mac.
    ///
    /// The decision writes only over a version whose changes this Mac holds or the user chose
    /// to replace, so the write holds them. Over a missing or unusable file, only this Mac's
    /// own record counts: a write of another Mac that the file held is not in this Mac's
    /// settings, and that Mac asks (``missesLastWrite(_:local:)``).
    ///
    /// - Parameter fileVersion: The file's version before the write, if it holds one.
    static func seen(writingOver fileVersion: Version?, local: Local) -> [String: Date] {
        mergedSeen(local.seen, fileVersion?.seen ?? [:])
    }

    /// Two records of writes merged: the newest write of each Mac, at most
    /// ``SettingsSyncFile/seenLimit`` of them.
    static func mergedSeen(_ seen: [String: Date], _ other: [String: Date]) -> [String: Date] {
        SettingsSyncFile.limitedSeen(seen.merging(other) { max($0, $1) })
    }

    /// Whether a version from another Mac was written without a write this Mac's settings
    /// hold: it records the writes it holds (``Version/seen``), and this Mac's newest one among
    /// them (``Version/seenWrite``) is older than this Mac's last write (``Local/lastWritten``),
    /// or its entry for another Mac is older than that Mac's newest write this Mac holds
    /// (``Local/seen``), in whole seconds.
    ///
    /// Such a version replaced the file without that write, as when the file went missing or
    /// became unusable, a sync app kept another Mac's concurrent write, or a Mac wrote on top
    /// of such a version, however often: applying it would revert that change silently, here
    /// and so on every Mac that took it in, not only the one that made it, so holzBar asks.
    /// Each Mac's writes are dated by its own clock, and only compared with each other, so
    /// clocks that differ do not matter. Files of earlier builds record no writes and are
    /// decided as before.
    static func missesLastWrite(_ version: Version, local: Local) -> Bool {
        guard !version.isFromThisMac, !local.isJoining, let versionSeen = version.seen else {
            return false
        }
        if let lastWritten = local.lastWritten, wholeSeconds(version.seenWrite ?? .distantPast) < wholeSeconds(lastWritten) {
            return true
        }
        return local.seen.contains { id, written in
            wholeSeconds(versionSeen[id] ?? .distantPast) < wholeSeconds(written)
        }
    }

    /// Whether a version is dated before the newest version this Mac synced with
    /// (``Local/lastSynced``), compared in whole seconds, as the sync file stores its date.
    ///
    /// Such a version is older than one this Mac has seen: a sync app brought it back, by
    /// its conflict resolution or a late upload, or the Mac that wrote it has a clock behind
    /// this Mac's.
    static func isBeforeLastSync(_ version: Version, local: Local) -> Bool {
        guard let lastSynced = local.lastSynced else {
            return false
        }
        return wholeSeconds(version.modified) < wholeSeconds(lastSynced)
    }

    /// A date in whole seconds, as the sync file stores it.
    static func wholeSeconds(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.rounded(.down)
    }

    /// Whether this Mac takes in the other macOS version's layout from a version of the sync
    /// file (``layoutToTakeIn(_:over:layouts:)``): not from one dated before the newest
    /// version this Mac synced with (``isBeforeLastSync(_:local:)``), whose layout may be older
    /// than the one the other Macs use. That includes an older version of this Mac's own.
    static func takesInOtherLayout(from version: Version, local: Local) -> Bool {
        !isBeforeLastSync(version, local: local)
    }

    /// Whether a write passes the file's current layout of the other macOS version on marked
    /// as a copy instead of as current: the file's version is dated before the newest
    /// version this Mac synced with (``isBeforeLastSync(_:local:)``), so the layout may be
    /// older than the one the Macs of that version use.
    ///
    /// Listed as current, the other Macs would apply that stale layout over their
    /// arrangement. Marked as a copy, this build never applies it, and those Macs keep their
    /// arrangement and list it as current again when they next write. This Mac's own copy is
    /// never written instead: it may be older still.
    ///
    /// - Parameter fileVersion: The file's version before the write, if it holds one.
    static func passesOtherLayoutAsCopy(_ fileVersion: Version?, local: Local) -> Bool {
        guard let fileVersion else {
            return false
        }
        return isBeforeLastSync(fileVersion, local: local)
    }

    /// Whether a write marks this Mac's layout as a copy instead of listing it as current: the
    /// sync file is missing or unusable, or holds no layout for this Mac's macOS version, the
    /// user did not change this Mac's layout, and this Mac holds no current layout of the
    /// folder: it keeps another Mac's layout it has not taken in (``Local/keptLayoutDigest``),
    /// or its last sync had no current layout for its macOS version
    /// (``Local/baseLayoutDigest`` is ``noLayoutDigest``), as after it applied a version that
    /// held that layout only as a copy.
    ///
    /// This Mac's layout then holds only holzBar's own placements over a layout that may be
    /// older than the arrangement the copy, or the kept layout, stands for; the record of
    /// writes this Mac passes on (``seen(writingOver:local:)``) may as well claim the write
    /// that made that arrangement. Listed as current, it would replace that arrangement on the
    /// Mac that made it, silently (SA-05, F-02). Marked as a copy, the Macs of this build keep
    /// their arrangement; the copy is passed on as one until the user changes the layout on a
    /// Mac of this macOS version. This Mac still keeps the record of a kept layout
    /// (``WriteRecord/keepsLayoutToTakeIn``). A Mac that has not synced with the folder, as
    /// one that sets up a new folder, lists its layout.
    ///
    /// - Parameters:
    ///   - fileSettings: The file's settings as read; `nil` when it is missing or unusable.
    ///   - layouts: This Mac's layout keys.
    ///   - local: This Mac's side of the decision that writes.
    static func writesOwnLayoutAsCopy(fileSettings: [String: Any]?, layouts: Layouts, local: Local) -> Bool {
        guard fileSettings?[layouts.own] == nil, !local.editsLayout else {
            return false
        }
        return local.keptLayoutDigest != nil || (local.baseLayoutDigest == noLayoutDigest && local.lastSynced != nil)
    }

    /// Whether a layout for this Mac's macOS version that this Mac's own version of the sync
    /// file lists as current is an old copy of this Mac's: the version is dated before this
    /// Mac's last sync (``isBeforeLastSync(_:local:)``), and its layout is neither the one this
    /// Mac last synced nor another Mac's that it kept and has not taken in
    /// (``holdsLayoutToTakeIn(_:local:)``).
    ///
    /// The date is the evidence: when the record of a kept layout was lost, as when sync was
    /// turned off while the write ran or holzBar quit right after it, this Mac's last version
    /// is not older than its last sync, and its layout is kept and taken in rather than
    /// replaced by holzBar's own layout (SA-05).
    ///
    /// A sync app may bring back an older version this Mac wrote, by its conflict resolution
    /// or a late upload. Its layout is never taken in, and a write over it writes this Mac's
    /// layout instead of passing the stale one on to the other Macs
    /// (``planWrite(_:file:fileCurrentLayouts:fileCopiedLayouts:fileVersion:layouts:local:)``).
    /// While this Mac joins, its own version's layout is the folder's arrangement, which a
    /// joining Mac without a layout change takes in
    /// (``ownLayoutToTakeIn(_:over:layouts:local:version:)``), so it is no old copy.
    ///
    /// - Parameter version: This Mac's own version.
    static func isOldOwnLayout(_ version: Version, local: Local) -> Bool {
        guard !local.isJoining, let layoutDigest = version.layoutDigest, isBeforeLastSync(version, local: local) else {
            return false
        }
        return layoutDigest != local.baseLayoutDigest && layoutDigest != local.keptLayoutDigest
    }

    /// Whether the user's "Keep This Mac's Settings" writes over a version: one this Mac
    /// wrote, or the version the user answered (``Local/keepsOver``), recognized by its date
    /// and contents (``Version/isSame(as:)``).
    ///
    /// Any other version from another Mac was never asked about, so the usual rules decide
    /// about it, and a change of this Mac's makes them ask: one that arrived while the
    /// question was open, also when it is dated before the answered one, as by a Mac whose
    /// clock runs behind or a sync app that delivered an earlier upload late, and an older one
    /// a sync app brought back.
    static func keepsThisMac(over version: Version, local: Local) -> Bool {
        guard local.forcesWrite else {
            return false
        }
        if version.isFromThisMac {
            return true
        }
        guard let keepsOver = local.keepsOver else {
            return false
        }
        return version.isSame(as: keepsOver)
    }

    /// Whether a joining Mac asks about another Mac's version that is not newer than its last
    /// sync instead of adopting it: the version's layout for this Mac's macOS version is
    /// neither the one this Mac last synced (``Local/baseLayoutDigest``, kept when it left the
    /// folder) nor this Mac's.
    ///
    /// A joining Mac takes in only a newer version's layout
    /// (``ownLayoutToTakeIn(_:over:layouts:local:version:)``). Adopting this one would record
    /// a layout as synced that this Mac never took in, so the user's next change of this
    /// Mac's layout would replace that arrangement without a question. It asks instead, as a
    /// Mac that is not joining does (``isUnsyncedChange(_:local:)``). A layout this Mac last
    /// synced differs from its own only by holzBar's placements, which never ask. When the
    /// user answers with "Keep This Mac's Settings" (``keepsThisMac(over:local:)``), the
    /// decision writes, with this Mac's layout (``keepsOwnLayoutOverStale(_:local:)``).
    static func holdsOlderLayoutToJoin(_ version: Version, local: Local) -> Bool {
        guard
            local.isJoining,
            !local.editsLayout,
            !version.isFromThisMac,
            !version.isNewer,
            let layout = version.layoutDigest,
            let baseLayout = local.baseLayoutDigest
        else {
            return false
        }
        return layout != baseLayout && layout != local.layoutDigest
    }

    /// Whether a version holds this Mac's settings: equal user settings, and a layout for
    /// this Mac's macOS version that is equal to the one this Mac holds against it
    /// (``Local/comparedLayout``), or none while the user did not change this Mac's.
    static func holdsLocalSettings(_ version: Version, local: Local) -> Bool {
        guard version.userDigest == local.userDigest else {
            return false
        }
        guard let versionLayout = version.layoutDigest else {
            return !local.editsLayout
        }
        guard let comparedLayout = local.comparedLayout else {
            return true
        }
        return versionLayout == comparedLayout
    }

    /// The layout digest of a layout for this Mac's macOS version that the sync file holds
    /// but does not list as current, or `nil`.
    ///
    /// Builds before this one list no layout. A Mac of this macOS version that runs one may
    /// have arranged the layout, and applies a file it finds newer as it is, at launch,
    /// removing what it lacks; but the layout may as well be an old copy kept by a Mac of the
    /// other macOS version. So it is never compared, applied or taken in, and never replaced
    /// without asking (``replacesUnlistedLayout(_:local:)``).
    ///
    /// A layout this build wrote as a Mac's copy for earlier builds
    /// (``SettingsSyncFile/copiedLayoutsKey``) is no Mac's arrangement and does not count.
    ///
    /// - Parameters:
    ///   - settings: The file's settings as read.
    ///   - currentLayouts: The layouts the file lists as current.
    ///   - copiedLayouts: The layouts the file marks as a Mac's copy.
    ///   - layouts: This Mac's layout keys.
    /// - Returns: The digest as ``layoutDigest(of:layouts:)`` computes it, comparable with
    ///   this Mac's (``Local/layoutDigest``); `nil` when the file lists the layout, holds none
    ///   or holds one holzBar would not apply.
    static func unlistedLayoutDigest(
        in settings: [String: Any],
        currentLayouts: Set<String>,
        copiedLayouts: Set<String> = [],
        layouts: Layouts
    ) -> String? {
        guard
            !currentLayouts.contains(layouts.own),
            !copiedLayouts.contains(layouts.own),
            let layout = validatedLayout(in: settings, key: layouts.own)
        else {
            return nil
        }
        return digest(of: [layouts.own: layout])
    }

    /// Whether writing this Mac's layout, which the user changed, would replace a layout of
    /// its macOS version that the version holds unlisted
    /// (``Version/unlistedLayoutDigest``), and that this Mac neither holds nor synced.
    /// Such a layout may be another Mac's arrangement, made on a build before this one, which
    /// that Mac would lose at its next launch: holzBar asks instead.
    ///
    /// A layout this Mac recently synced (``Local/recentLayouts``) is most likely an old copy
    /// of one it had: a Mac still on 0.0.7 beta 1, of either macOS version, writes back the
    /// copy it applied, and a Mac that kept it unchanged loses nothing. A layout change of the
    /// user's writes over it without a question, and it is never applied; any other write
    /// passes it on unchanged, as it may as well be a beta 1 Mac's return to that arrangement
    /// (``fileToWrite(_:file:fileCurrentLayouts:fileCopiedLayouts:layouts:keepsOwnLayout:)``).
    static func replacesUnlistedLayout(_ version: Version, local: Local) -> Bool {
        guard local.editsLayout, let unlisted = version.unlistedLayoutDigest else {
            return false
        }
        return unlisted != local.layoutDigest && unlisted != local.baseLayoutDigest && !local.recentLayouts.contains(unlisted)
    }

    /// Whether a version from another Mac that is not newer than this Mac's last sync holds a
    /// change this Mac has not synced: user settings other than those this Mac last synced
    /// (``Local/base``) and those of the version it last synced (``Local/versionDigest``), which
    /// differ after applying a version that lacks some of this Mac's settings, or a layout for
    /// this Mac's macOS version other than the one it last synced.
    ///
    /// Without the digest of the version this Mac last synced, as an earlier build left it,
    /// the date alone decides, as before.
    static func isUnsyncedChange(_ version: Version, local: Local) -> Bool {
        guard !version.isFromThisMac, let base = local.base, let versionDigest = local.versionDigest else {
            return false
        }
        if version.userDigest != base, version.userDigest != versionDigest {
            return true
        }
        guard let layout = version.layoutDigest else {
            return false
        }
        return layout != local.baseLayoutDigest
    }

    /// Whether a version changed nothing this Mac uses since this Mac last synced: its user
    /// settings are those of the last sync, and its layout for this Mac's macOS version is
    /// none or the one last synced. Another Mac may have changed only its learned keys or
    /// the other macOS version's layout, which a write keeps.
    static func changedNothingSinceBase(_ version: Version, local: Local) -> Bool {
        guard let base = local.base, version.userDigest == base else {
            return false
        }
        return version.layoutDigest == nil || version.layoutDigest == local.baseLayoutDigest
    }

    // MARK: Layout Edits

    /// The number of layout edits an install starts counting from, at the first launch of a
    /// build that counts them.
    ///
    /// A Mac that has synced already had its layout from the sync folder, which earlier
    /// builds synced whole, so only holzBar's own placements can set it apart: it counts as
    /// unchanged, and the first sync takes in the folder's layout without a question. On a
    /// Mac that has not synced, sync off or on but never in reach of the folder, whether an
    /// existing layout is the user's arrangement or holzBar's own is unknown, so it counts as
    /// changed until the first sync. A fresh install's does not, as holzBar writes it.
    ///
    /// - Parameters:
    ///   - hasLayout: Whether this Mac has a layout for its macOS version.
    ///   - syncs: Whether settings sync is on.
    ///   - hasSynced: Whether this Mac has written or applied the sync file (it has a date
    ///     of its last sync).
    static func initialLayoutEdits(hasLayout: Bool, syncs: Bool, hasSynced: Bool) -> Int {
        hasLayout && !(syncs && hasSynced) ? 1 : 0
    }

    /// Whether saving a layout counts as a change of the user's
    /// (`SettingsSync.userChangedLayout()`): the user arranged the items, and the saved
    /// layout differs from the one before. A Command-click on the bar that moves nothing
    /// saves the same layout, and holzBar's own placements never count (SA-05).
    ///
    /// - Parameters:
    ///   - byUser: Whether the user arranged the items.
    ///   - saved: The layout saved now.
    ///   - before: The layout saved before.
    static func countsAsLayoutEdit<Layout: Equatable>(byUser: Bool, saved: Layout, before: Layout) -> Bool {
        byUser && saved != before
    }

    /// The sections to save for the items on the bar before macOS 27, and whether the save
    /// counts as a change of the user's (`SettingsSync.userChangedLayout()`).
    ///
    /// Without a record of the bar from before the user's arrangement, every item is saved
    /// where it is, and the save counts when the user arranged the items and an item that
    /// had a saved section is saved in another one. An item saved for the first time holds
    /// the section macOS or holzBar gave it, not one the user chose (SA-05).
    ///
    /// With that record (``capturesBarBeforeArrangement(isDragging:savesArrangementSoon:commandHeld:mouseButtonPressed:)``),
    /// what the user moved is known: an item now in another section than the record moved,
    /// and counts when that changes its saved section, also for an item saved for the first
    /// time. An item in the recorded section did not move: macOS may have displaced it before
    /// the arrangement, as after a display change or wake, so it keeps its saved section,
    /// which the restore brings back, and is never saved as the user's arrangement.
    ///
    /// - Parameters:
    ///   - byUser: Whether the user arranged the items; holzBar's first-run save is not.
    ///   - onBar: The section of each item on the bar now.
    ///   - saved: The section of each item saved before.
    ///   - beforeArrangement: The section of each item on the bar when holzBar last read it
    ///     before the user's arrangement, if it has that record.
    /// - Returns: The sections to save, and whether the save counts as the user's change.
    static func sectionsToSave<Key: Hashable, Section: Equatable>(
        byUser: Bool,
        onBar: [Key: Section],
        saved: [Key: Section],
        beforeArrangement: [Key: Section]?
    ) -> (sections: [Key: Section], countsAsEdit: Bool) {
        var sections = saved
        var countsAsEdit = false
        for (key, section) in onBar {
            let savedSection = saved[key]
            guard byUser, let recorded = beforeArrangement?[key] else {
                sections[key] = section
                countsAsEdit = countsAsEdit || (byUser && savedSection.map { $0 != section } ?? false)
                continue
            }
            if section != recorded {
                // The user moved it.
                sections[key] = section
                countsAsEdit = countsAsEdit || savedSection != section
            } else if savedSection == nil {
                // Unmoved and never saved: holzBar's own record of where it is.
                sections[key] = section
            }
        }
        return (sections, countsAsEdit)
    }

    /// Whether holzBar records the sections of the bar it just read as the bar before the
    /// user's next arrangement (``sectionsToSave(byUser:onBar:saved:beforeArrangement:)``).
    ///
    /// Only a read the user cannot be arranging during counts: no item is being dragged, no
    /// save of an arrangement is pending, and neither Command nor a mouse button is held, as
    /// a Command-drag on the bar needs both and holzBar may not see it start.
    static func capturesBarBeforeArrangement(
        isDragging: Bool,
        savesArrangementSoon: Bool,
        commandHeld: Bool,
        mouseButtonPressed: Bool
    ) -> Bool {
        !isDragging && !savesArrangementSoon && !commandHeld && !mouseButtonPressed
    }

    /// The sections of holzBar's own placements to save before macOS 27, after a
    /// reconciliation: where it placed new items, and where macOS put an item it left there
    /// (`MenuBarItemManager.performReconciliation`).
    ///
    /// The reconciliation chose them from the saved sections it read before it moved items.
    /// A move may take long enough for the user to drag an item and for that arrangement to
    /// be saved meanwhile; holzBar's placement must not replace the section the user just
    /// saved, which the restore would then undo. So only items that still have no saved
    /// section, and that a profile does not place, are saved.
    ///
    /// - Parameters:
    ///   - placements: The section of each item holzBar placed or left in place.
    ///   - savedNow: The saved section of each item, read right before saving.
    ///   - wanted: The section of each item a profile places, if one is applied.
    static func ownPlacementsToStore<Key: Hashable, Section>(
        _ placements: [Key: Section],
        savedNow: [Key: Section],
        wanted: [Key: Section]?
    ) -> [Key: Section] {
        placements.filter { savedNow[$0.key] == nil && wanted?[$0.key] == nil }
    }

    /// Whether the user changed this Mac's layout since it last synced
    /// (``Local/editsLayout``).
    ///
    /// Only the user's changes of the layout are counted; holzBar's own placements of new
    /// items are not. A sync records the count it was made with, so an edit made while an
    /// exchange ran still counts afterwards.
    ///
    /// - Parameters:
    ///   - count: The number of layout edits on this Mac.
    ///   - synced: The number the last sync recorded.
    static func editsLayout(count: Int, synced: Int) -> Bool {
        count != synced
    }
}

// MARK: - Sync State

nonisolated extension SettingsSyncPolicy {
    /// What this Mac remembers of its last sync, kept in its defaults, and how each outcome
    /// of an exchange changes it.
    struct State: Equatable, Sendable {
        /// The digest of the user settings this Mac last wrote or applied
        /// (``Local/base``); `nil` while it joins the folder.
        var base: String?
        /// The layout digest this Mac last synced (``Local/baseLayoutDigest``).
        var baseLayoutDigest: String?
        /// The number of changes the user made to this Mac's layout. It is never reset.
        var layoutEdits = 0
        /// The number of layout edits the last sync recorded.
        var syncedLayoutEdits = 0
        /// The date of the newest version this Mac wrote or applied.
        var lastSynced: Date?
        /// The date of a version that waits for the user; while it waits, this Mac's changes
        /// are not written.
        var pending: Date?
        /// The digest of the user settings of the version this Mac last wrote, applied or
        /// adopted. It is the ``base`` unless this Mac applied a version that lacks some of
        /// its settings; `nil` while it joins, or when an earlier build synced last.
        var versionDigest: String?
        /// The layout digests for this Mac's macOS version that this Mac recently wrote,
        /// applied, adopted or took in, the newest first, at most ``recentLayoutLimit``. A Mac
        /// still on 0.0.7 beta 1 may write one of them back unlisted, as an old copy
        /// (``SettingsSyncPolicy/replacesUnlistedLayout(_:local:)``). Another Mac's layout that
        /// a write of this Mac's kept, or an adoption is to take in, counts only once this Mac
        /// took it in: until then it is that Mac's arrangement, which a beta 1 Mac writing it
        /// back must not let this Mac's own layout replace (SA-05). They depend only on the
        /// layout, so they stay when this Mac leaves the folder.
        var recentLayouts: [String] = []

        /// The layout digest of another Mac's layout for this Mac's macOS version that this
        /// Mac's own version holds and this Mac has not taken in yet: its last write kept it
        /// (``SettingsSyncPolicy/takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``),
        /// or a joining Mac adopted its own version to take it in
        /// (``SettingsSyncPolicy/ownLayoutToTakeIn(_:over:layouts:local:version:)``); `nil` when
        /// none waits. Taking it in, applying a version or any other sync clears it. It stays
        /// when this Mac leaves the folder, so a re-join before a restart still asks before a
        /// layout change of the user's replaces it.
        var keptLayoutDigest: String?

        /// The date of this Mac's newest write whose changes its settings hold: the last version
        /// it wrote, as written into the file, or after it applied a version, this Mac's newest
        /// write that version holds. `nil` when there is none to look for: it has not written
        /// since it joined a folder it had not synced with, or it applied a version of an
        /// earlier build. Another Mac's version that holds an older write of this Mac's lacks it
        /// (``SettingsSyncPolicy/missesLastWrite(_:local:)``).
        var lastWritten: Date?

        /// The newest write of each other Mac whose changes this Mac's settings hold, by sync
        /// id: from the versions this Mac wrote over, adopted or applied. A write passes it on
        /// with this Mac's own (``SettingsSyncPolicy/seen(writingOver:local:)``), so a Mac can
        /// tell a version that lacks its last write, however many writes lie between.
        var seen: [String: Date] = [:]

        /// How many layout digests ``recentLayouts`` keeps: enough for many days of
        /// rearranging while a Mac still on 0.0.7 beta 1 writes an old copy back now and then.
        /// An old copy this Mac writes over is remembered anew
        /// (``SettingsSyncPolicy/WriteRecord/oldCopyDigest``).
        static let recentLayoutLimit = 64

        /// Remembers a layout digest this Mac synced (``recentLayouts``).
        mutating func rememberLayout(_ digest: String?) {
            guard let digest, digest != SettingsSyncPolicy.noLayoutDigest else {
                return
            }
            recentLayouts.removeAll { $0 == digest }
            recentLayouts.insert(digest, at: 0)
            if recentLayouts.count > Self.recentLayoutLimit {
                recentLayouts.removeLast(recentLayouts.count - Self.recentLayoutLimit)
            }
        }

        /// Whether the user changed this Mac's layout since it last synced
        /// (``SettingsSyncPolicy/editsLayout(count:synced:)``).
        var editsLayout: Bool {
            SettingsSyncPolicy.editsLayout(count: layoutEdits, synced: syncedLayoutEdits)
        }

        /// Counts a change of this Mac's layout that the user made. The count wraps instead
        /// of trapping.
        mutating func countLayoutEdit() {
            layoutEdits &+= 1
        }

        /// Remembers that this Mac has synced the given user settings and layout with the
        /// file of the given date, and that no version waits for the user.
        ///
        /// - Parameters:
        ///   - layout: The layout digest of the file's layout for this Mac's macOS version,
        ///     or `nil` when it has none.
        ///   - layoutEdits: The number of layout edits the sync saw; edits made since still
        ///     count.
        ///   - modified: The file's date, or `nil` to keep the date of the last sync, so a
        ///     version from another Mac stays newer.
        mutating func markSynced(base: String, layout: String?, layoutEdits: Int, modified: Date?) {
            self.base = base
            versionDigest = base
            baseLayoutDigest = layout ?? SettingsSyncPolicy.noLayoutDigest
            rememberLayout(layout)
            syncedLayoutEdits = layoutEdits
            if let modified {
                lastSynced = max(lastSynced ?? .distantPast, modified)
            }
            pending = nil
            keptLayoutDigest = nil
        }

        /// Records a version that holds this Mac's settings (``Action/adopt``) as synced.
        ///
        /// When this Mac takes in the version's layout for its macOS version
        /// (``SettingsSyncPolicy/ownLayoutToTakeIn(_:over:layouts:local:version:)``), holzBar
        /// reads that layout only at launch: this Mac's own layout is recorded as synced. A
        /// version from another Mac keeps the date of the last sync, so it is one to apply,
        /// and it waits. This Mac's own version holds a layout to take in, recorded as
        /// ``keptLayoutDigest`` (``SettingsSyncPolicy/holdsLayoutToTakeIn(_:local:)``), and
        /// waits without pausing this Mac's pushes.
        ///
        /// - Parameters:
        ///   - version: The version, or `nil` for none.
        ///   - local: This Mac's side of the decision that adopted the version; its layout
        ///     edits (``Local/layoutEdits``) are recorded.
        ///   - takesInOwnLayout: Whether this Mac takes in the version's layout.
        mutating func recordAdoption(_ version: Version?, local: Local, takesInOwnLayout: Bool) {
            // A layout this Mac has not taken in is not one it synced: a beta 1 Mac writing it
            // back is no old copy of this Mac's, and is passed on (``recentLayouts``).
            if !takesInOwnLayout {
                rememberLayout(version?.layoutDigest)
            }
            // The version holds this Mac's settings, and so the writes it holds, unless its
            // layout waits for a restart.
            if let version, !takesInOwnLayout || version.isFromThisMac {
                seen = SettingsSyncPolicy.mergedSeen(seen, version.seen ?? [:])
            }
            guard takesInOwnLayout, let version else {
                markSynced(base: local.userDigest, layout: version?.layoutDigest, layoutEdits: local.layoutEdits, modified: version?.syncedDate)
                return
            }
            guard !version.isFromThisMac else {
                markSynced(base: local.userDigest, layout: local.layoutDigest, layoutEdits: local.layoutEdits, modified: version.syncedDate)
                keptLayoutDigest = version.layoutDigest
                return
            }
            markSynced(base: local.userDigest, layout: local.layoutDigest, layoutEdits: local.layoutEdits, modified: nil)
            pending = version.modified
        }

        /// Records a write of this Mac's settings (``Action/write``) as synced.
        ///
        /// When the write kept another Mac's layout that this Mac has not taken in
        /// (``SettingsSyncPolicy/takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``),
        /// this Mac's own layout is recorded as synced instead and the kept one as the layout to
        /// take in (``keptLayoutDigest``), so the written version holds a layout to take in
        /// (``SettingsSyncPolicy/holdsLayoutToTakeIn(_:local:)``), and it
        /// waits: Restart takes it in, or the next launch (``Action/takeInLayout``). It does not
        /// pause this Mac's pushes, which keep that layout. A write that left this Mac's layout
        /// unlisted keeps the record of a kept layout (``WriteRecord/keepsLayoutToTakeIn``).
        ///
        /// - Parameters:
        ///   - record: What the write records (``WritePlan/record``).
        ///   - modified: The date written into the file.
        ///   - local: This Mac's side of the decision that wrote; its layout edits
        ///     (``Local/layoutEdits``) are recorded.
        mutating func recordWrite(_ record: WriteRecord, modified: Date?, local: Local) {
            if let modified {
                lastWritten = modified
            }
            seen = SettingsSyncPolicy.mergedSeen(seen, record.seen)
            rememberLayout(record.oldCopyDigest)
            guard record.takesInLayout else {
                let kept = keptLayoutDigest
                rememberLayout(record.layoutDigest)
                markSynced(base: local.userDigest, layout: record.layoutDigest, layoutEdits: local.layoutEdits, modified: modified)
                if record.keepsLayoutToTakeIn {
                    keptLayoutDigest = kept
                }
                return
            }
            markSynced(base: local.userDigest, layout: local.layoutDigest, layoutEdits: local.layoutEdits, modified: modified)
            keptLayoutDigest = record.layoutDigest
        }

        /// Records that this Mac took in the layout of its own version that it kept from
        /// another Mac (``Action/takeInLayout``), or a layout the user chose from it. The user
        /// settings this Mac last synced stay, so its other changes are still written; a
        /// layout change of the user's that the layout replaced no longer counts.
        ///
        /// - Parameter layoutDigest: The layout digest taken in.
        mutating func recordLayoutTakeIn(layoutDigest: String?) {
            baseLayoutDigest = layoutDigest ?? SettingsSyncPolicy.noLayoutDigest
            rememberLayout(layoutDigest)
            syncedLayoutEdits = layoutEdits
            pending = nil
            keptLayoutDigest = nil
        }

        /// Records that the user chose a version's settings
        /// (``SettingsSyncPolicy/settingsToUse(_:unlisted:over:layouts:version:local:)``) and
        /// they were applied.
        ///
        /// The layout edits made so far no longer count.
        ///
        /// - Parameters:
        ///   - version: The version.
        ///   - layoutDigest: The layout digest the choice records.
        ///   - base: The digest of this Mac's user settings after they were applied.
        mutating func recordUse(of version: Version, layoutDigest: String?, base: String) {
            guard !version.isFromThisMac else {
                // Only the layout of this Mac's own version was used.
                recordLayoutTakeIn(layoutDigest: layoutDigest)
                return
            }
            recordApplied(version, base: base, layoutDigest: layoutDigest)
        }

        /// Records that a version from another Mac was applied: at launch, or after the user
        /// chose it. The layout edits made so far no longer count.
        ///
        /// - Parameters:
        ///   - version: The version.
        ///   - base: The digest of this Mac's user settings after they were applied, which may
        ///     differ from the version's when it lacks some of this Mac's settings.
        ///   - layoutDigest: The layout digest to record as synced.
        mutating func recordApplied(_ version: Version, base: String, layoutDigest: String?) {
            markSynced(base: base, layout: layoutDigest, layoutEdits: layoutEdits, modified: version.syncedDate)
            versionDigest = version.userDigest
            // This Mac's settings are the version's now: they hold the writes it holds, and of
            // this Mac's, only the newest it holds. A version of an earlier build records none.
            seen = version.seen ?? [:]
            lastWritten = version.seen == nil ? nil : version.seenWrite
        }

        /// Records what the launch did for a decision (``launchApplication(for:)``), after it
        /// applied it.
        ///
        /// - An applied version is recorded with its layout, and the user settings it left.
        /// - An adoption records the version as synced; a layout the launch took in with it is
        ///   in this Mac's settings already.
        /// - A kept layout taken in is recorded as synced, and this Mac's other changes stay to
        ///   be written after launch.
        /// - A version to ask about waits (``pending``): the check after launch asks.
        /// - Without anything to do, no version waits any more.
        ///
        /// - Parameters:
        ///   - action: The decision at launch.
        ///   - version: The file's version, if it holds one.
        ///   - local: This Mac's side of the decision.
        ///   - appliedBase: The digest of this Mac's user settings after the launch applied
        ///     the version's; needed only for ``Action/apply``.
        mutating func recordLaunch(_ action: Action, version: Version?, local: Local, appliedBase: String?) {
            switch action {
            case .apply:
                if let version, let appliedBase {
                    recordApplied(version, base: appliedBase, layoutDigest: version.layoutDigest)
                }
            case .adopt:
                recordAdoption(version, local: local, takesInOwnLayout: false)
            case .takeInLayout:
                if let version {
                    recordLayoutTakeIn(layoutDigest: version.layoutDigest)
                }
            case .ask:
                pending = version?.modified
            case .none:
                pending = nil
                recordUnchanged(version, local: local)
            case .write, .wait, .retry:
                break
            }
        }

        /// Records that a newer version from another Mac changed nothing this Mac uses since it
        /// last synced (``SettingsSyncPolicy/changedNothingSinceBase(_:local:)``), and that this
        /// Mac had no changes to write over it (``Action/none``): this Mac has synced with it,
        /// so its date is the last sync. A version brought back later, dated before it, is then
        /// known to be older (``SettingsSyncPolicy/isBeforeLastSync(_:local:)``), and its other
        /// macOS version's layout is neither taken in nor passed on as current.
        ///
        /// - Parameters:
        ///   - version: The file's version, if it holds one.
        ///   - local: This Mac's side of the decision.
        mutating func recordUnchanged(_ version: Version?, local: Local) {
            guard
                let version,
                !local.isJoining,
                !version.isFromThisMac,
                version.isNewer,
                SettingsSyncPolicy.changedNothingSinceBase(version, local: local)
            else {
                return
            }
            lastSynced = max(lastSynced ?? .distantPast, version.modified)
        }

        /// Forgets the folder this Mac synced with, so it joins a folder again: sync was
        /// turned off, another folder was chosen, or this Mac's settings come from another
        /// Mac. The layout last synced, a kept layout not taken in yet and the layout edits
        /// stay, as they depend only on the layout.
        ///
        /// - Parameter forgetsLastSync: Whether the date of the last sync, the last write and
        ///   the writes this Mac's settings hold go too, for a folder this Mac has not synced
        ///   with.
        mutating func leaveFolder(forgetsLastSync: Bool) {
            base = nil
            versionDigest = nil
            pending = nil
            if forgetsLastSync {
                lastSynced = nil
                lastWritten = nil
                seen = [:]
            }
        }
    }

    /// What a write of the sync file records (``State/recordWrite(_:modified:local:)``).
    struct WriteRecord: Equatable, Sendable {
        /// The layout digest this Mac records as synced
        /// (``syncedLayoutDigest(afterWriting:currentLayouts:copiedLayouts:layouts:local:)``).
        var layoutDigest: String?
        /// Whether the write kept another Mac's layout that this Mac takes in
        /// (``takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``).
        var takesInLayout: Bool
        /// The layout digest of an old copy of a layout this Mac synced that the file held
        /// unlisted (``replacesUnlistedLayout(_:local:)``), or `nil`. It is remembered anew
        /// (``State/recentLayouts``), whether the write replaced it or passed it on: a Mac
        /// still on 0.0.7 beta 1 keeps
        /// writing the same copy back, which must stay recognized however often the user
        /// rearranges this Mac's layout meanwhile.
        var oldCopyDigest: String?
        /// Whether the write left this Mac's layout unlisted, without a layout change of the
        /// user's, while this Mac keeps another Mac's layout it has not taken in
        /// (``Local/keptLayoutDigest``), as over a missing file
        /// (``writesOwnLayoutAsCopy(fileSettings:layouts:local:)``). The record of that layout stays:
        /// an older version of this Mac's own that holds it, as a sync app may bring back, is
        /// then still taken in rather than written over as an old copy
        /// (``isOldOwnLayout(_:local:)``), and a later write over a missing file still marks
        /// this Mac's layout as a copy.
        var keepsLayoutToTakeIn = false
        /// The writes of the other Macs that the written settings hold
        /// (``seen(writingOver:local:)``); this Mac's settings hold them from now on
        /// (``State/seen``).
        var seen: [String: Date] = [:]
    }

    /// A write of the sync file: what is written and what the write records.
    struct WritePlan {
        /// The settings to write.
        var settings: [String: Any]
        /// The layouts the written file lists as current.
        var currentLayouts: [String]
        /// The layouts the written file marks as a Mac's copy.
        var copiedLayouts: [String]
        /// What the write records.
        var record: WriteRecord
        /// Whether the write adds this Mac's copy of the other macOS version's layout, as the
        /// file has none. A Mac of that version still on 0.0.7 beta 1 applies it at its next
        /// launch, and it may be older than that Mac's layout (F-60).
        var insertsCopy = false
        /// Whether the write passes the file's current layout of the other macOS version on
        /// as a copy, as the file's version is older than this Mac's last sync
        /// (``passesOtherLayoutAsCopy(_:local:)``).
        var passesOtherAsCopy = false

        /// The writes of the other Macs that the written settings hold, without this Mac's own
        /// (``seen(writingOver:local:)``); the file records them with this Mac's write
        /// (``SettingsSyncFile/seenToWrite(_:deviceID:modified:)``).
        var seen: [String: Date] {
            record.seen
        }
    }

    /// Plans a write of this Mac's settings into the sync file
    /// (``fileToWrite(_:file:fileCurrentLayouts:fileCopiedLayouts:layouts:keepsOwnLayout:)``),
    /// with the layout digest it records and whether this Mac then takes in a layout the
    /// write kept.
    ///
    /// This Mac's layout is written as it is after a change of the user's
    /// (``writesOwnLayout(_:)``), and over an old copy of this Mac's own
    /// (``isOldOwnLayout(_:local:)``): passing that copy on would bring a stale arrangement
    /// back to the other Macs. So is it when the user kept this Mac's settings over another
    /// Mac's version whose layout may be stale (``keepsOwnLayoutOverStale(_:local:)``). For
    /// the same reason, the other macOS version's layout of a
    /// version older than this Mac's last sync is passed on as a copy
    /// (``passesOtherLayoutAsCopy(_:local:)``).
    ///
    /// - Parameters:
    ///   - settings: This Mac's settings.
    ///   - remote: The file's settings as read, if any.
    ///   - fileCurrentLayouts: The layouts the file lists as current.
    ///   - fileCopiedLayouts: The layouts the file marks as a Mac's copy.
    ///   - fileVersion: The file's version as the decision saw it, if it holds one.
    ///   - layouts: This Mac's layout keys.
    ///   - local: This Mac's side of the decision that writes.
    static func planWrite(
        _ settings: [String: Any],
        file remote: [String: Any]?,
        fileCurrentLayouts: Set<String>,
        fileCopiedLayouts: Set<String>,
        fileVersion: Version? = nil,
        layouts: Layouts,
        local: Local
    ) -> WritePlan {
        let fileIsFromThisMac = fileVersion?.isFromThisMac == true
        let passesOtherAsCopy = passesOtherLayoutAsCopy(fileVersion, local: local)
        // The file's current layout for this Mac's macOS version, as the decision saw it
        // (``Version/layoutDigest``).
        let fileLayoutDigest = remote.flatMap { remote in
            let digest = self.layoutDigest(of: withoutStaleLayouts(remote, currentLayouts: fileCurrentLayouts), layouts: layouts)
            return digest == noLayoutDigest ? nil : digest
        }
        let overwritesOldOwnLayout = fileVersion.map { fileIsFromThisMac && isOldOwnLayout($0, local: local) } ?? false
        let written = fileToWrite(
            settings,
            file: remote,
            fileCurrentLayouts: fileCurrentLayouts,
            fileCopiedLayouts: fileCopiedLayouts,
            layouts: layouts,
            keepsOwnLayout: writesOwnLayout(local) || overwritesOldOwnLayout || keepsOwnLayoutOverStale(fileVersion, local: local),
            passesOtherLayoutAsCopy: passesOtherAsCopy,
            writesOwnLayoutAsCopy: writesOwnLayoutAsCopy(fileSettings: remote, layouts: layouts, local: local)
        )
        let layoutDigest = syncedLayoutDigest(
            afterWriting: written.settings,
            currentLayouts: Set(written.currentLayouts),
            copiedLayouts: Set(written.copiedLayouts),
            layouts: layouts,
            local: local
        )
        let takesInLayout = takesInKeptLayout(fileLayoutDigest: fileLayoutDigest, writtenLayoutDigest: layoutDigest, local: local)
        let fileUnlisted = remote.flatMap {
            unlistedLayoutDigest(in: $0, currentLayouts: fileCurrentLayouts, copiedLayouts: fileCopiedLayouts, layouts: layouts)
        }
        let oldCopyDigest = fileUnlisted.flatMap { local.recentLayouts.contains($0) ? $0 : nil }
        return WritePlan(
            settings: written.settings,
            currentLayouts: written.currentLayouts,
            copiedLayouts: written.copiedLayouts,
            record: WriteRecord(
                layoutDigest: layoutDigest,
                takesInLayout: takesInLayout,
                oldCopyDigest: oldCopyDigest,
                keepsLayoutToTakeIn: local.keptLayoutDigest != nil && !local.editsLayout && !written.currentLayouts.contains(layouts.own),
                seen: seen(writingOver: fileVersion, local: local)
            ),
            insertsCopy: remote?[layouts.other] == nil && written.copiedLayouts.contains(layouts.other),
            passesOtherAsCopy: passesOtherAsCopy && fileCurrentLayouts.contains(layouts.other) && remote?[layouts.other] != nil
        )
    }
}

// MARK: - Acting on Decisions

nonisolated extension SettingsSyncPolicy {
    /// What holzBar does with the hint after it acted on a decision while it runs.
    enum HintChange: Equatable, Sendable {
        /// The hint stays as it is.
        case unchanged
        /// No version waits for the user any more: the hint goes.
        case withdraw
        /// The file's version waits for the user: a newer one from another Mac, or this Mac's
        /// own with a layout to take in.
        case offerFileVersion
        /// The version this Mac just wrote waits to have the layout it kept taken in.
        case offerWrittenVersion
    }

    /// What acting on a decision while holzBar runs does: the sync state to store, the hint,
    /// and whether a push follows.
    struct Outcome: Equatable, Sendable {
        /// The sync state to store.
        var state: State
        /// What happens to the hint.
        var hint: HintChange
        /// Whether a push of this Mac's changes follows: a check found changes to write, and
        /// a check never writes.
        var pushes = false
    }

    /// What acting on a decision while holzBar runs does
    /// (`SettingsSync.handle(_:of:)`, and a chosen folder that is joined without a question).
    ///
    /// - A newer version from another Mac that is applied or asked about waits for the user
    ///   with ``State/pending``, so no push writes over it while the hint is shown.
    /// - This Mac's own version with a layout to take in (``Action/takeInLayout``) is offered
    ///   without ``State/pending``: this Mac's pushes go on, keeping that layout.
    /// - An adoption that takes in a layout offers it; any other adoption withdraws the hint.
    /// - A write that kept another Mac's layout offers the written version; any other write
    ///   withdraws the hint.
    ///
    /// - Parameters:
    ///   - action: The decision (``decide(_:local:file:)``).
    ///   - isCheck: Whether the exchange was a check, which never writes.
    ///   - version: The file's version, if it holds one.
    ///   - local: This Mac's side of the decision.
    ///   - state: The sync state stored now.
    ///   - takesInOwnLayout: For an adoption, whether this Mac takes in the version's layout
    ///     for its macOS version (``ownLayoutToTakeIn(_:over:layouts:local:version:)``).
    ///   - written: For a write, what it records and the date it wrote.
    static func outcome(
        of action: Action,
        isCheck: Bool,
        version: Version?,
        local: Local,
        state: State,
        takesInOwnLayout: Bool = false,
        written: (record: WriteRecord, modified: Date?)? = nil
    ) -> Outcome {
        var state = state
        switch action {
        case .none:
            state.pending = nil
            state.recordUnchanged(version, local: local)
            return Outcome(state: state, hint: .withdraw)
        case .wait, .retry:
            return Outcome(state: state, hint: .unchanged)
        case .adopt:
            let takesIn = takesInOwnLayout && version != nil
            state.recordAdoption(version, local: local, takesInOwnLayout: takesIn)
            return Outcome(state: state, hint: takesIn ? .offerFileVersion : .withdraw)
        case .write:
            if isCheck {
                state.pending = nil
                return Outcome(state: state, hint: .withdraw, pushes: true)
            }
            guard let written else {
                return Outcome(state: state, hint: .unchanged)
            }
            state.recordWrite(written.record, modified: written.modified, local: local)
            return Outcome(state: state, hint: written.record.takesInLayout ? .offerWrittenVersion : .withdraw)
        case .apply, .ask:
            guard let version else {
                return Outcome(state: state, hint: .unchanged)
            }
            state.pending = version.modified
            return Outcome(state: state, hint: .offerFileVersion)
        case .takeInLayout:
            return Outcome(state: state, hint: version == nil ? .unchanged : .offerFileVersion)
        }
    }

    /// What the launch applies for a decision, before anything reads the settings
    /// (`SettingsSync.pullIfNeeded()`).
    enum LaunchApplication: Equatable, Sendable {
        /// Nothing.
        case nothing
        /// The version's settings (``settingsToApply(_:over:layouts:baseLayoutDigest:editsLayout:)``).
        case settings
        /// The folder's layout for this Mac's macOS version, when a joining Mac adopts
        /// (``ownLayoutToTakeIn(_:over:layouts:local:version:)``).
        case ownLayout
        /// The layout this Mac kept from another Mac (``keptLayoutToTakeIn(_:over:layouts:)``).
        case keptLayout
    }

    /// The settings the launch applies for a decision (``launchApplication(for:)``), without
    /// removing any this Mac has; empty when there is nothing to apply.
    ///
    /// - Parameters:
    ///   - action: The decision at launch.
    ///   - remote: The version's current settings
    ///     (``withoutStaleLayouts(_:currentLayouts:)``).
    ///   - settings: This Mac's settings.
    ///   - layouts: This Mac's layout keys.
    ///   - local: This Mac's side of the decision.
    ///   - version: The version.
    static func settingsToApplyAtLaunch(
        for action: Action,
        remote: [String: Any],
        over settings: [String: Any],
        layouts: Layouts,
        local: Local,
        version: Version
    ) -> [String: Any] {
        switch launchApplication(for: action) {
        case .settings:
            settingsToApply(remote, over: settings, layouts: layouts, baseLayoutDigest: local.baseLayoutDigest, editsLayout: local.editsLayout)
        case .ownLayout:
            ownLayoutToTakeIn(remote, over: settings, layouts: layouts, local: local, version: version)
        case .keptLayout:
            keptLayoutToTakeIn(remote, over: settings, layouts: layouts)
        case .nothing:
            [:]
        }
    }

    /// The other macOS version's layout to take in from a version, silently, as at launch or
    /// with an adoption: none from a version older than this Mac's last sync
    /// (``takesInOtherLayout(from:local:)``), or when this Mac holds it already
    /// (``layoutToTakeIn(_:over:layouts:)``).
    static func otherLayoutToTakeIn(
        _ remote: [String: Any],
        over settings: [String: Any],
        layouts: Layouts,
        version: Version,
        local: Local
    ) -> [String: Any] {
        guard takesInOtherLayout(from: version, local: local) else {
            return [:]
        }
        return layoutToTakeIn(remote, over: settings, layouts: layouts)
    }

    /// What a Mac that has synced takes in silently at launch when it applied no version
    /// whole: what the other Macs have learned (``learnedKeys``) and the other macOS
    /// version's layout (``otherLayoutToTakeIn(_:over:layouts:version:local:)``).
    static func settingsToTakeInAtLaunch(
        from remote: [String: Any],
        over settings: [String: Any],
        layouts: Layouts,
        version: Version,
        local: Local
    ) -> [String: Any] {
        learnedSettings(merging: remote, into: settings)
            .merging(otherLayoutToTakeIn(remote, over: settings, layouts: layouts, version: version, local: local)) { _, layout in layout }
    }

    /// What the launch applies for a decision. The launch never writes and never asks.
    static func launchApplication(for action: Action) -> LaunchApplication {
        switch action {
        case .apply:
            .settings
        case .adopt:
            .ownLayout
        case .takeInLayout:
            .keptLayout
        case .none, .wait, .retry, .write, .ask:
            .nothing
        }
    }
}

// MARK: - Stored Sync State

nonisolated extension SettingsSyncPolicy.State {
    /// The key of ``base``. Keys starting with "SettingsSync" are never exported, imported
    /// or synced.
    static let baseKey = "SettingsSyncBaseSettingsDigest"
    /// The key of ``baseLayoutDigest``.
    static let baseLayoutKey = "SettingsSyncBaseLayoutDigest"
    /// The key of ``layoutEdits``.
    static let layoutEditsKey = "SettingsSyncLayoutEdits"
    /// The key of ``syncedLayoutEdits``.
    static let syncedLayoutEditsKey = "SettingsSyncSyncedLayoutEdits"
    /// The key of ``lastSynced``.
    static let lastSyncedKey = "SettingsSyncLastSynced"
    /// The key of ``pending``.
    static let pendingKey = "SettingsSyncPendingModified"
    /// The key of ``versionDigest``.
    static let versionDigestKey = "SettingsSyncVersionSettingsDigest"
    /// The key of ``recentLayouts``.
    static let recentLayoutsKey = "SettingsSyncRecentLayoutDigests"
    /// The key of ``keptLayoutDigest``.
    static let keptLayoutKey = "SettingsSyncKeptLayoutDigest"
    /// The key of ``lastWritten``.
    static let lastWrittenKey = "SettingsSyncLastWritten"
    /// The key of ``seen``.
    static let seenKey = "SettingsSyncSeenWrites"
    /// The key of the base of earlier test builds, which held the layouts too.
    static let legacyBaseKey = "SettingsSyncBaseDigest"

    /// The sync state stored under its keys, read with `value`.
    init(reading value: (String) -> Any?) {
        self.init(
            base: value(Self.baseKey) as? String,
            baseLayoutDigest: value(Self.baseLayoutKey) as? String,
            layoutEdits: value(Self.layoutEditsKey) as? Int ?? 0,
            syncedLayoutEdits: value(Self.syncedLayoutEditsKey) as? Int ?? 0,
            lastSynced: value(Self.lastSyncedKey) as? Date,
            pending: value(Self.pendingKey) as? Date,
            versionDigest: value(Self.versionDigestKey) as? String,
            recentLayouts: Array((value(Self.recentLayoutsKey) as? [String] ?? []).prefix(Self.recentLayoutLimit)),
            keptLayoutDigest: value(Self.keptLayoutKey) as? String,
            lastWritten: value(Self.lastWrittenKey) as? Date,
            seen: (value(Self.seenKey) as? [String: Any]).map { SettingsSyncFile.limitedSeen($0.compactMapValues { $0 as? Date }) } ?? [:]
        )
    }

    /// The values to store for the fields that differ from `old`, under their keys; `nil`
    /// removes the key.
    func changes(from old: Self) -> [(key: String, value: Any?)] {
        var changes = [(key: String, value: Any?)]()
        if base != old.base {
            changes.append((Self.baseKey, base))
        }
        if baseLayoutDigest != old.baseLayoutDigest {
            changes.append((Self.baseLayoutKey, baseLayoutDigest))
        }
        if layoutEdits != old.layoutEdits {
            changes.append((Self.layoutEditsKey, layoutEdits))
        }
        if syncedLayoutEdits != old.syncedLayoutEdits {
            changes.append((Self.syncedLayoutEditsKey, syncedLayoutEdits))
        }
        if lastSynced != old.lastSynced {
            changes.append((Self.lastSyncedKey, lastSynced))
        }
        if pending != old.pending {
            changes.append((Self.pendingKey, pending))
        }
        if versionDigest != old.versionDigest {
            changes.append((Self.versionDigestKey, versionDigest))
        }
        if recentLayouts != old.recentLayouts {
            changes.append((Self.recentLayoutsKey, recentLayouts.isEmpty ? nil : recentLayouts))
        }
        if keptLayoutDigest != old.keptLayoutDigest {
            changes.append((Self.keptLayoutKey, keptLayoutDigest))
        }
        if lastWritten != old.lastWritten {
            changes.append((Self.lastWrittenKey, lastWritten))
        }
        if seen != old.seen {
            changes.append((Self.seenKey, seen.isEmpty ? nil : seen))
        }
        return changes
    }

    /// What bringing the sync state of an earlier build up to date changes.
    struct Migration: Equatable, Sendable {
        /// Whether the base of earlier test builds, which held the layouts too, is removed,
        /// so this Mac joins the folder once more.
        var removesLegacyBase: Bool
        /// The number of layout edits to start counting from
        /// (``SettingsSyncPolicy/initialLayoutEdits(hasLayout:syncs:hasSynced:)``), or `nil`
        /// when this Mac counts them already.
        var layoutEdits: Int?
    }

    /// What bringing the stored sync state of an earlier build up to date changes, from the
    /// values stored under their keys, read with `value`.
    static func migration(reading value: (String) -> Any?, layouts: SettingsSyncPolicy.Layouts) -> Migration {
        var layoutEdits: Int?
        if value(layoutEditsKey) == nil {
            layoutEdits = SettingsSyncPolicy.initialLayoutEdits(
                hasLayout: value(layouts.own) != nil,
                syncs: value(Defaults.Key.syncsSettingsWithICloud.rawValue) as? Bool ?? false,
                hasSynced: value(lastSyncedKey) != nil
            )
        }
        return Migration(removesLegacyBase: value(legacyBaseKey) != nil, layoutEdits: layoutEdits)
    }
}

nonisolated extension SettingsSyncPolicy.Local {
    /// This Mac's side, with the digests of its settings.
    init(
        settings: [String: Any],
        layouts: SettingsSyncPolicy.Layouts,
        base: String?,
        baseLayoutDigest: String?,
        editsLayout: Bool,
        pending: Date?,
        postponed: Date?,
        forcesWrite: Bool
    ) {
        self.init(
            userDigest: SettingsSyncPolicy.userDigest(of: settings),
            base: base,
            pending: pending,
            postponed: postponed,
            forcesWrite: forcesWrite,
            layoutDigest: SettingsSyncPolicy.layoutDigest(of: settings, layouts: layouts),
            baseLayoutDigest: baseLayoutDigest,
            editsLayout: editsLayout
        )
    }

    /// This Mac's side, with the digests of its settings and the sync state it keeps.
    ///
    /// - Parameter layoutEdits: The number of layout edits the decision sees; the user
    ///   changed the layout when the last sync recorded another.
    init(
        settings: [String: Any],
        layouts: SettingsSyncPolicy.Layouts,
        state: SettingsSyncPolicy.State,
        layoutEdits: Int,
        postponed: Date?,
        forcesWrite: Bool
    ) {
        self.init(
            settings: settings,
            layouts: layouts,
            base: state.base,
            baseLayoutDigest: state.baseLayoutDigest,
            editsLayout: SettingsSyncPolicy.editsLayout(count: layoutEdits, synced: state.syncedLayoutEdits),
            pending: state.pending,
            postponed: postponed,
            forcesWrite: forcesWrite
        )
        self.layoutEdits = layoutEdits
        versionDigest = state.versionDigest
        recentLayouts = Set(state.recentLayouts)
        keptLayoutDigest = state.keptLayoutDigest
        lastSynced = state.lastSynced
        lastWritten = state.lastWritten
        seen = state.seen
    }
}

nonisolated extension SettingsSyncPolicy.Version {
    /// Whether this is the same version of the sync file as `other`: the same date, writer
    /// and settings. Whether it is newer than this Mac's last sync is left out, as it depends
    /// on when the file was read.
    func isSame(as other: Self) -> Bool {
        isFromThisMac == other.isFromThisMac &&
            modified == other.modified &&
            userDigest == other.userDigest &&
            layoutDigest == other.layoutDigest &&
            unlistedLayoutDigest == other.unlistedLayoutDigest
    }

    /// The date a sync with this version records as the last sync
    /// (``SettingsSyncPolicy/State/lastSynced``): its own, unless it is another Mac's version
    /// that is not newer. Such a version may be dated far in the future, and recording that
    /// date would make every later version of the other Macs look older.
    var syncedDate: Date? {
        isNewer || isFromThisMac ? modified : nil
    }

    /// A version with the digests of its settings.
    ///
    /// - Parameter settings: The version's current settings
    ///   (``SettingsSyncPolicy/withoutStaleLayouts(_:currentLayouts:)``).
    ///   - unlistedLayoutDigest: The layout digest of a layout for this Mac's macOS version
    ///     that the file holds unlisted
    ///     (``SettingsSyncPolicy/unlistedLayoutDigest(in:currentLayouts:copiedLayouts:layouts:)``).
    ///   - seen: The newest write of each other Mac that the version holds, if the file
    ///     records them (``SettingsSyncFile/Contents/seen``).
    ///   - seenWrite: The date of this Mac's newest write that the version holds
    ///     (``SettingsSyncFile/Contents/seenWrite``).
    init(
        settings: [String: Any],
        layouts: SettingsSyncPolicy.Layouts,
        isFromThisMac: Bool,
        modified: Date,
        isNewer: Bool,
        unlistedLayoutDigest: String? = nil,
        seen: [String: Date]? = nil,
        seenWrite: Date? = nil
    ) {
        let layoutDigest = SettingsSyncPolicy.layoutDigest(of: settings, layouts: layouts)
        self.init(
            isFromThisMac: isFromThisMac,
            modified: modified,
            isNewer: isNewer,
            userDigest: SettingsSyncPolicy.userDigest(of: settings),
            layoutDigest: layoutDigest == SettingsSyncPolicy.noLayoutDigest ? nil : layoutDigest,
            unlistedLayoutDigest: unlistedLayoutDigest,
            seen: seen,
            seenWrite: seenWrite
        )
    }
}
