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
    /// (``ownLayoutToTakeIn(_:over:layouts:local:isNewer:)``). A version that changed nothing
    /// this Mac uses since it last synced lets this Mac's changes win
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
                // it is applied like a newer version, and a layout change of the user's asks.
                if local.editsLayout {
                    if !isLaunch, let postponed = local.postponed, version.modified <= postponed {
                        return .wait
                    }
                    return .ask
                }
                return local.hasChanges ? writesChanges : .apply
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
        var applied = settingsToApply(
            remote,
            over: settings,
            layouts: layouts,
            baseLayoutDigest: local.baseLayoutDigest,
            editsLayout: local.editsLayout
        )
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
    ///   - isNewer: Whether the version is newer than this Mac's last sync
    ///     (``Version/isNewer``). One this Mac already wrote or applied is in its layout,
    ///     apart from holzBar's own placements since, which stay.
    /// - Returns: The layout to apply, or an empty dictionary when there is nothing to take in:
    ///   this Mac is not joining, the user changed its layout, the version is not newer, it
    ///   has no current layout for this Mac's macOS version, or this Mac already holds it.
    static func ownLayoutToTakeIn(
        _ remote: [String: Any],
        over settings: [String: Any],
        layouts: Layouts,
        local: Local,
        isNewer: Bool
    ) -> [String: Any] {
        guard local.isJoining, !local.editsLayout, isNewer, let remoteLayout = validatedLayout(in: remote, key: layouts.own) else {
            return [:]
        }
        let merged = mergedLayout(
            remoteLayout,
            keeping: validatedLayout(in: settings, key: layouts.own),
            seen: knownEntries(in: remote, layouts: layouts)
        )
        let takenIn = [layouts.own: merged]
        guard layoutDigest(of: takenIn, layouts: layouts) != layoutDigest(of: settings, layouts: layouts) else {
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
    /// user changed it (`keepsOwnLayout`) or the file has no current one; otherwise the
    /// file's current layout is kept, with only this Mac's entries it has never seen, so
    /// holzBar's own placements never replace another Mac's layout. A layout for this Mac's
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
    static func fileToWrite(
        _ local: [String: Any],
        file remote: [String: Any]?,
        fileCurrentLayouts: Set<String>,
        fileCopiedLayouts: Set<String> = [],
        layouts: Layouts,
        keepsOwnLayout: Bool
    ) -> (settings: [String: Any], currentLayouts: [String], copiedLayouts: [String]) {
        var settings = settingsToWrite(local, file: remote)
        var currentLayouts = Set<String>()
        var copiedLayouts = Set<String>()
        // Files of earlier builds list no layout; their copy is carried on for those builds.
        // Without one, this Mac's copy, from ``settingsToWrite(_:file:)``, stays unlisted and
        // is marked as a copy.
        if let fileOther = remote?[layouts.other] {
            settings[layouts.other] = fileOther
            if fileCurrentLayouts.contains(layouts.other) {
                currentLayouts.insert(layouts.other)
            } else if fileCopiedLayouts.contains(layouts.other) {
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
            !fileCopiedLayouts.contains(layouts.own),
            let fileOwn = remote?[layouts.own]
        {
            // A layout an earlier build wrote, unlisted: a Mac of this macOS version that
            // still runs that build may have arranged it, and applies the file as it is. It
            // is passed on as it is, unlisted, and only a change of the user's replaces it
            // (``replacesUnlistedLayout(_:local:)``).
            settings[layouts.own] = fileOwn
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
    /// chose to keep this Mac's settings: this Mac's layout then holds only holzBar's own
    /// placements, which never replace another Mac's arrangement (SA-05).
    static func writesOwnLayout(_ local: Local) -> Bool {
        local.editsLayout
    }

    /// Whether a write that kept the file's current layout for this Mac's macOS version
    /// leaves this Mac with another Mac's layout to take in: the user did not change this
    /// Mac's layout, the file's layout is not the one this Mac last synced, and the written
    /// layout is not this Mac's.
    ///
    /// That happens when the user chose to keep this Mac's settings over a version whose
    /// layout differs, or when this Mac wrote over a version that is not newer than its last
    /// sync. holzBar reads the layout at launch, so it is not applied now: this Mac records
    /// its own layout as synced, and the version it wrote waits for a restart
    /// (``State/recordWrite(layoutDigest:modified:local:layoutEdits:takesInLayout:)``).
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
    /// taken in: one it kept from another Mac
    /// (``takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``).
    static func holdsLayoutToTakeIn(_ version: Version, local: Local) -> Bool {
        guard version.isFromThisMac, !local.isJoining, let layout = version.layoutDigest else {
            return false
        }
        return layout != local.baseLayoutDigest
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
    /// (``Version/unlistedLayoutDigest``), and that this Mac neither holds nor last synced.
    /// Such a layout may be another Mac's arrangement, made on a build before this one, which
    /// that Mac would lose at its next launch: holzBar asks instead.
    static func replacesUnlistedLayout(_ version: Version, local: Local) -> Bool {
        guard local.editsLayout, let unlisted = version.unlistedLayoutDigest else {
            return false
        }
        return unlisted != local.layoutDigest && unlisted != local.baseLayoutDigest
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
    /// A Mac that syncs already had its layout from the sync folder, which earlier builds
    /// synced whole, so only holzBar's own placements can set it apart: it counts as
    /// unchanged, and the first sync takes in the folder's layout without a question. On a
    /// Mac that does not sync, whether an existing layout is the user's arrangement or
    /// holzBar's own is unknown, so it counts as changed until the first sync. A fresh
    /// install's does not, as holzBar writes it.
    ///
    /// - Parameters:
    ///   - hasLayout: Whether this Mac has a layout for its macOS version.
    ///   - syncs: Whether settings sync is on.
    static func initialLayoutEdits(hasLayout: Bool, syncs: Bool) -> Int {
        hasLayout && !syncs ? 1 : 0
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
            baseLayoutDigest = layout ?? SettingsSyncPolicy.noLayoutDigest
            syncedLayoutEdits = layoutEdits
            if let modified {
                lastSynced = max(lastSynced ?? .distantPast, modified)
            }
            pending = nil
        }

        /// Records a version that holds this Mac's settings (``Action/adopt``) as synced.
        ///
        /// When this Mac takes in the version's layout for its macOS version
        /// (``SettingsSyncPolicy/ownLayoutToTakeIn(_:over:layouts:local:isNewer:)``), holzBar
        /// reads that layout only at launch: this Mac's own layout is recorded as synced and
        /// the date of the last sync is kept, so the version is one to apply, and it waits.
        ///
        /// - Parameters:
        ///   - layoutDigest: The version's layout digest (``Version/layoutDigest``).
        ///   - modified: The version's date.
        ///   - local: This Mac's side of the decision that adopted the version.
        ///   - layoutEdits: The number of layout edits that decision saw.
        ///   - takesInOwnLayout: Whether this Mac takes in the version's layout.
        mutating func recordAdoption(layoutDigest: String?, modified: Date?, local: Local, layoutEdits: Int, takesInOwnLayout: Bool) {
            guard takesInOwnLayout else {
                markSynced(base: local.userDigest, layout: layoutDigest, layoutEdits: layoutEdits, modified: modified)
                return
            }
            markSynced(base: local.userDigest, layout: local.layoutDigest, layoutEdits: layoutEdits, modified: nil)
            pending = modified
        }

        /// Records a write of this Mac's settings (``Action/write``) as synced.
        ///
        /// When the write kept another Mac's layout that this Mac has not taken in
        /// (``SettingsSyncPolicy/takesInKeptLayout(fileLayoutDigest:writtenLayoutDigest:local:)``),
        /// this Mac's own layout is recorded as synced instead, so the written version holds a
        /// layout to take in (``SettingsSyncPolicy/holdsLayoutToTakeIn(_:local:)``), and it
        /// waits: Restart applies it, or the next launch.
        ///
        /// - Parameters:
        ///   - layoutDigest: The layout digest the write records
        ///     (``SettingsSyncPolicy/syncedLayoutDigest(afterWriting:currentLayouts:copiedLayouts:layouts:local:)``).
        ///   - modified: The date written into the file.
        ///   - local: This Mac's side of the decision that wrote.
        ///   - layoutEdits: The number of layout edits that decision saw.
        ///   - takesInLayout: Whether the write kept a layout this Mac takes in.
        mutating func recordWrite(layoutDigest: String?, modified: Date?, local: Local, layoutEdits: Int, takesInLayout: Bool) {
            guard takesInLayout else {
                markSynced(base: local.userDigest, layout: layoutDigest, layoutEdits: layoutEdits, modified: modified)
                return
            }
            markSynced(base: local.userDigest, layout: local.layoutDigest, layoutEdits: layoutEdits, modified: modified)
            pending = modified
        }
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
    }
}

nonisolated extension SettingsSyncPolicy.Version {
    /// A version with the digests of its settings.
    ///
    /// - Parameter settings: The version's current settings
    ///   (``SettingsSyncPolicy/withoutStaleLayouts(_:currentLayouts:)``).
    ///   - unlistedLayoutDigest: The layout digest of a layout for this Mac's macOS version
    ///     that the file holds unlisted
    ///     (``SettingsSyncPolicy/unlistedLayoutDigest(in:currentLayouts:copiedLayouts:layouts:)``).
    init(
        settings: [String: Any],
        layouts: SettingsSyncPolicy.Layouts,
        isFromThisMac: Bool,
        modified: Date,
        isNewer: Bool,
        unlistedLayoutDigest: String? = nil
    ) {
        let layoutDigest = SettingsSyncPolicy.layoutDigest(of: settings, layouts: layouts)
        self.init(
            isFromThisMac: isFromThisMac,
            modified: modified,
            isNewer: isNewer,
            userDigest: SettingsSyncPolicy.userDigest(of: settings),
            layoutDigest: layoutDigest == SettingsSyncPolicy.noLayoutDigest ? nil : layoutDigest,
            unlistedLayoutDigest: unlistedLayoutDigest
        )
    }
}
