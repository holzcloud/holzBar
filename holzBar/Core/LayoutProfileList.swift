//
//  LayoutProfileList.swift
//  holzBar
//

import Foundation

/// One element of a stored list that is skipped when it cannot be decoded, instead of making the
/// whole list unreadable.
nonisolated private struct LossyLayoutProfile: Decodable {
    let value: LayoutProfile?

    init(from decoder: any Decoder) {
        value = try? LayoutProfile(from: decoder)
    }
}

/// The stored list of layout profiles: decoded element by element, validated, capped and encoded
/// again.
///
/// The list comes from the defaults, from an imported settings file or from any process of the
/// user, so nothing in it is trusted. The limits keep a hostile or broken list from filling
/// memory or making the Profiles pane unusable; profiles the app saves itself stay far below them.
nonisolated enum LayoutProfileList {
    /// The most profiles there can be.
    static let maximumProfiles = 100

    /// The most entries in each of a profile's maps and in its list of known applications.
    static let maximumEntriesPerProfile = 2000

    /// The most UTF-8 bytes of a key of a map or of a known application.
    static let maximumKeyLength = 512

    /// The most characters of a display or Space UUID string.
    static let maximumIdentifierLength = 128

    /// The most bytes of a list that is read or written (4 MB).
    static let maximumDataSize = 4 * 1024 * 1024

    /// The most UTF-8 bytes of a stored profile name. Far above what anyone types: earlier
    /// versions stored names uncut, so the cap only stops a hostile list.
    static let maximumStoredNameBytes = 4096

    /// The sections a profile can name: visible, hidden and always hidden.
    private static let sections = 0...2

    /// A name the user types now, as it is stored: the rule shared profiles use
    /// (``SharedProfile/cleanedName(_:)``), and no trailing white space where that cut the name.
    ///
    /// Only for new names (saving and renaming). A stored name is never cleaned on load, because
    /// hotkeys, script hooks, URL commands and Shortcuts refer to it as it is.
    static func cleanedName(_ name: String) -> String {
        SharedProfile.cleanedName(name).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The profiles of a stored list, in order, or `nil` when the data is over
    /// ``maximumDataSize`` or is not a JSON array.
    ///
    /// An element that cannot be decoded is dropped alone. A stored name is kept exactly as it
    /// is; a profile is dropped only when its name is empty or white space, or over
    /// ``maximumStoredNameBytes``, which no version of the app writes. A name an earlier profile
    /// already has gets a number (" 2", " 3", …) instead of dropping the profile. The first
    /// ``maximumProfiles`` stay. Within a profile, a key that is empty or over
    /// ``maximumKeyLength`` bytes and a section outside 0 to 2 are dropped, the first
    /// ``maximumEntriesPerProfile`` entries by key stay, and a display or Space UUID that is empty
    /// or longer than ``maximumIdentifierLength`` becomes `nil`.
    static func profiles(from data: Data) -> [LayoutProfile]? {
        guard data.count <= maximumDataSize,
            let elements = try? JSONDecoder().decode([LossyLayoutProfile].self, from: data) else {
            return nil
        }
        var seenNames = Set<String>()
        var profiles = [LayoutProfile]()
        for case let element? in elements.map(\.value) {
            guard profiles.count < maximumProfiles else {
                break
            }
            guard isValidStoredName(element.name) else {
                continue
            }
            var name = element.name
            var number = 2
            while !seenNames.insert(name).inserted {
                name = "\(element.name) \(number)"
                number += 1
            }
            profiles.append(LayoutProfile(
                name: name,
                itemSections: validSections(element.itemSections),
                applicationSections: validSections(element.applicationSections),
                knownApplications: element.knownApplications.map(validKeys),
                displayUUID: validIdentifier(element.displayUUID),
                spaceUUID: validIdentifier(element.spaceUUID)
            ))
        }
        return profiles
    }

    /// The JSON of a list of profiles with sorted keys, or `nil` when it would be over
    /// ``maximumDataSize``.
    static func encoded(_ profiles: [LayoutProfile]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(profiles), data.count <= maximumDataSize else {
            return nil
        }
        return data
    }

    /// An imported list as it may be applied: the validated profiles, encoded again, so that
    /// unknown fields and profiles over the limits never reach the defaults. `nil` when the data
    /// is too large or is not a JSON array.
    static func normalized(_ data: Data) -> Data? {
        guard let profiles = profiles(from: data) else {
            return nil
        }
        return encoded(profiles)
    }

    /// The entries of a map with a valid key and a section of 0 to 2, the first
    /// ``maximumEntriesPerProfile`` by key.
    private static func validSections(_ map: [String: Int]) -> [String: Int] {
        var result = [String: Int]()
        for key in map.keys.sorted() where isValidKey(key) {
            guard result.count < maximumEntriesPerProfile else {
                break
            }
            if let section = map[key], sections.contains(section) {
                result[key] = section
            }
        }
        return result
    }

    /// The valid keys of a list without repeats, the first ``maximumEntriesPerProfile``.
    private static func validKeys(_ keys: [String]) -> [String] {
        var seen = Set<String>()
        var result = [String]()
        for key in keys where isValidKey(key) && seen.insert(key).inserted {
            guard result.count < maximumEntriesPerProfile else {
                break
            }
            result.append(key)
        }
        return result
    }

    /// Whether a stored name is kept: not empty or white space, and at most
    /// ``maximumStoredNameBytes``. Earlier versions stored every trimmed name that was not empty.
    static func isValidStoredName(_ name: String) -> Bool {
        name.utf8.count <= maximumStoredNameBytes
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValidKey(_ key: String) -> Bool {
        !key.isEmpty && key.utf8.count <= maximumKeyLength
    }

    private static func validIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty, identifier.count <= maximumIdentifierLength else {
            return nil
        }
        return identifier
    }
}
