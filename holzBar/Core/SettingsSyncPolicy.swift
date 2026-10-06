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
        /// Whether the user chose to keep this Mac's settings.
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

        /// Whether this Mac joins the folder.
        var isJoining: Bool {
            base == nil
        }

        /// Whether the user changed settings since this Mac last wrote or applied them.
        var hasChanges: Bool {
            base != userDigest || editsLayout
        }

        /// The layout this Mac holds against a version's: its own after a change of the
        /// user's; otherwise none while it joins, as holzBar's own layout has no say, and the
        /// one it last synced, as only holzBar's own placements differ from it.
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
    }

    /// What reading the sync file gave.
    nonisolated enum File: Equatable, Sendable {
        /// There is no file.
        case missing
        /// The file holds nothing holzBar can use (too large, not a regular file, no date
        /// or settings); holzBar may write over it.
        case unusable
        /// The file could not be read now; holzBar must not write over it.
        case unreadable
        /// A version of the file.
        case version(Version)
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
    /// A version that holds this Mac's settings is adopted (``holdsLocalSettings(_:local:)``);
    /// one that changed nothing this Mac uses since it last synced lets this Mac's changes win
    /// (``changedNothingSinceBase(_:local:)``).
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
            return !isLaunch && (local.isJoining || local.forcesWrite || local.hasChanges) ? .write : .none
        case .version(let version):
            if holdsLocalSettings(version, local: local) {
                return .adopt
            }
            if local.forcesWrite {
                return isLaunch ? .none : .write
            }
            if version.isFromThisMac {
                return writesChanges
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
                return writesChanges
            }
            if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                return .wait
            }
            return local.hasChanges ? .ask : .apply
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

    /// The settings to write into the sync file (``settingsToWrite(_:file:)``), with the
    /// layouts handled per macOS version, and the layouts the written file lists as current.
    ///
    /// The other macOS version's layout is the file's, never this Mac's copy, which may be
    /// older; it is left out when the file has none. This Mac's layout is written when the
    /// user changed it (`keepsOwnLayout`) or the file has no current one; otherwise the
    /// file's current layout is kept, with only this Mac's entries it has never seen, so
    /// holzBar's own placements never replace another Mac's layout.
    ///
    /// - Parameters:
    ///   - local: This Mac's settings.
    ///   - remote: The file's settings as read, if any.
    ///   - fileCurrentLayouts: The layouts the file lists as current.
    ///   - layouts: This Mac's layout keys.
    ///   - keepsOwnLayout: Whether this Mac's layout is written as it is: the user changed
    ///     it, or chose to keep this Mac's settings.
    static func fileToWrite(
        _ local: [String: Any],
        file remote: [String: Any]?,
        fileCurrentLayouts: Set<String>,
        layouts: Layouts,
        keepsOwnLayout: Bool
    ) -> (settings: [String: Any], currentLayouts: [String]) {
        var settings = settingsToWrite(local, file: remote)
        var currentLayouts = Set<String>()
        // Files of earlier builds list no layout; their copy is carried on for those builds.
        settings[layouts.other] = remote?[layouts.other]
        if settings[layouts.other] != nil, fileCurrentLayouts.contains(layouts.other) {
            currentLayouts.insert(layouts.other)
        }
        let fileLayout = fileCurrentLayouts.contains(layouts.own) ? validatedLayout(in: remote, key: layouts.own) : nil
        if local[layouts.own] == nil {
            settings[layouts.own] = remote?[layouts.own]
            if fileLayout != nil {
                currentLayouts.insert(layouts.own)
            }
        } else {
            if !keepsOwnLayout, let fileLayout {
                settings[layouts.own] = mergedLayout(
                    fileLayout,
                    keeping: validatedLayout(in: local, key: layouts.own),
                    seen: knownEntries(in: remote, layouts: layouts)
                )
            }
            currentLayouts.insert(layouts.own)
        }
        return (settings, currentLayouts.sorted())
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
}

nonisolated extension SettingsSyncPolicy.Version {
    /// A version with the digests of its settings.
    ///
    /// - Parameter settings: The version's current settings
    ///   (``SettingsSyncPolicy/withoutStaleLayouts(_:currentLayouts:)``).
    init(settings: [String: Any], layouts: SettingsSyncPolicy.Layouts, isFromThisMac: Bool, modified: Date, isNewer: Bool) {
        let layoutDigest = SettingsSyncPolicy.layoutDigest(of: settings, layouts: layouts)
        self.init(
            isFromThisMac: isFromThisMac,
            modified: modified,
            isNewer: isNewer,
            userDigest: SettingsSyncPolicy.userDigest(of: settings),
            layoutDigest: layoutDigest == SettingsSyncPolicy.noLayoutDigest ? nil : layoutDigest
        )
    }
}
