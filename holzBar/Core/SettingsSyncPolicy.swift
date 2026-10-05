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
    /// (`Defaults.Key.validatedSettings`) without the ``learnedKeys``.
    static func userDigest(of settings: [String: Any]) -> String {
        digest(of: userSettings(Defaults.Key.validatedSettings(settings).accepted))
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

        /// Whether this Mac joins the folder.
        var isJoining: Bool {
            base == nil
        }

        /// Whether the user changed settings since this Mac last wrote or applied them.
        var hasChanges: Bool {
            base != userDigest
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
            if version.userDigest == local.userDigest {
                return .adopt
            }
            if local.forcesWrite {
                return isLaunch ? .none : .write
            }
            if version.isFromThisMac {
                return writesChanges
            }
            if local.isJoining {
                return .ask
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
