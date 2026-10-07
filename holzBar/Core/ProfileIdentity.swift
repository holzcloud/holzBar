//
//  ProfileIdentity.swift
//  holzBar
//

import CryptoKit
import Foundation

/// The result of ``ProfileIdentity/migrate(profilesData:hotkeys:)``.
nonisolated struct ProfileIdentityMigration: Equatable, Sendable {
    /// The `LayoutProfiles` value, every profile with its ID.
    var profilesData: Data?

    /// The `Hotkeys` dictionary, the profile hotkeys keyed by profile ID.
    var hotkeys: [String: Data]

    /// Whether the migration changed anything.
    var changed: Bool
}

/// Gives layout profiles a stable ID.
///
/// A rename keeps the ID, so syncing a rename is a change of one profile, never a delete plus
/// a create. A profile that existed before IDs get an ID derived from its name
/// (``legacyProfileID(forName:)``), so the same profile on two Macs gets the same ID without
/// the Macs talking to each other; a new profile gets a random one (``newProfileID()``).
/// The derivation is one-way: changing it later would duplicate the profiles of every Mac
/// that already migrated.
nonisolated enum ProfileIdentity {
    /// What the legacy derivation hashes before the name.
    static let legacyNamespace = "com.holzcloud.holzBar.LayoutProfile:"

    /// The ID of a profile that existed before profiles had IDs: the first 16 bytes of the
    /// SHA-256 of ``legacyNamespace`` and the name, as an uppercase UUID string with the
    /// RFC 4122 variant bits and version 8 (a custom UUID).
    static func legacyProfileID(forName name: String) -> String {
        var bytes = Array(SHA256.hash(data: Data((legacyNamespace + name).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = bytes.withUnsafeBytes { $0.load(as: uuid_t.self) }
        return UUID(uuid: uuid).uuidString
    }

    /// A new random profile ID.
    static func newProfileID() -> String {
        UUID().uuidString
    }

    /// Gives every stored profile an ID and re-keys the profiles' hotkeys by it, once.
    ///
    /// Idempotent: a second run reports `changed == false`. The profiles are edited as JSON, so
    /// fields this build does not know survive. Data that is not a JSON array of objects, or
    /// profiles that all have an ID already, leave the profiles untouched. Only exact-name
    /// `ApplyProfile:<name>` hotkeys whose name belongs to a profile are re-keyed; the others
    /// stay as they are.
    ///
    /// Two profiles with the same name get distinct IDs: the first derives from the name, the
    /// second from the name plus `#2`, and so on.
    static func migrate(profilesData: Data?, hotkeys: [String: Data]) -> ProfileIdentityMigration {
        let unchanged = ProfileIdentityMigration(profilesData: profilesData, hotkeys: hotkeys, changed: false)
        guard
            let profilesData,
            let parsed = try? JSONSerialization.jsonObject(with: profilesData),
            var profiles = parsed as? [[String: Any]]
        else {
            return unchanged
        }

        var profilesChanged = false
        var occurrences = [String: Int]()
        var idByName = [String: String]()
        for index in profiles.indices {
            guard let name = profiles[index]["name"] as? String else {
                continue
            }
            let occurrence = (occurrences[name] ?? 0) + 1
            occurrences[name] = occurrence
            if let existing = profiles[index]["profileID"] as? String, !existing.isEmpty {
                if idByName[name] == nil {
                    idByName[name] = existing
                }
                continue
            }
            let id = legacyProfileID(forName: occurrence == 1 ? name : "\(name)#\(occurrence)")
            profiles[index]["profileID"] = id
            profilesChanged = true
            if idByName[name] == nil {
                idByName[name] = id
            }
        }

        let allIDs = Set(idByName.values)
        var migratedHotkeys = hotkeys
        var hotkeysChanged = false
        for (key, data) in hotkeys.sorted(by: { $0.key < $1.key }) where key.hasPrefix(HotkeyTarget.profilePrefix) {
            let name = String(key.dropFirst(HotkeyTarget.profilePrefix.count))
            // A key that already carries a profile ID is migrated.
            guard !allIDs.contains(name), let id = idByName[name] else {
                continue
            }
            let newKey = HotkeyTarget.profilePrefix + id
            guard migratedHotkeys[newKey] == nil else {
                continue
            }
            migratedHotkeys[newKey] = data
            migratedHotkeys[key] = nil
            hotkeysChanged = true
        }

        guard profilesChanged || hotkeysChanged else {
            return unchanged
        }
        var result = ProfileIdentityMigration(profilesData: profilesData, hotkeys: migratedHotkeys, changed: true)
        if profilesChanged {
            guard let data = try? JSONSerialization.data(withJSONObject: profiles, options: [.sortedKeys]) else {
                return unchanged
            }
            result.profilesData = data
        }
        return result
    }
}
