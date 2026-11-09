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
    /// The most profiles a list can reach by adding one (saving under a new name, importing a
    /// shared profile). A list that already holds more (versions up to 1.0.3 had no limit) keeps
    /// them all up to ``maximumStoredProfiles``; its profiles can still be replaced, renamed and
    /// deleted. The Profiles pane names the number in its text; change both together.
    static let maximumProfiles = 100

    /// The most profiles a stored list keeps when it is read: a safety cap against a hostile list,
    /// far above ``maximumProfiles``, so no user's list loses a profile.
    static let maximumStoredProfiles = 1000

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
    /// already has gets the first number (" 2", " 3", …) that no stored name has, instead of
    /// dropping the profile. The first
    /// ``maximumStoredProfiles`` stay. Within a profile, a key that is empty or over
    /// ``maximumKeyLength`` bytes and a section outside 0 to 2 are dropped, the first
    /// ``maximumEntriesPerProfile`` entries by key stay, and a display or Space UUID that is empty
    /// or longer than ``maximumIdentifierLength`` becomes `nil`.
    static func profiles(from data: Data) -> [LayoutProfile]? {
        guard data.count <= maximumDataSize,
            let elements = try? JSONDecoder().decode([LossyLayoutProfile].self, from: data) else {
            return nil
        }
        let valid = elements.compactMap(\.value).filter { isValidStoredName($0.name) }
        // Every real stored name is reserved first, so a numbered repeat never takes the name of
        // a later profile that hotkeys and Shortcuts refer to.
        let reserved = Set(valid.map(\.name))
        var seenNames = Set<String>()
        var profiles = [LayoutProfile]()
        for element in valid {
            guard profiles.count < maximumStoredProfiles else {
                break
            }
            var name = element.name
            if !seenNames.insert(name).inserted {
                var number = 2
                repeat {
                    name = "\(element.name) \(number)"
                    number += 1
                } while reserved.contains(name) || !seenNames.insert(name).inserted
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

    /// Whether a list the app is about to store loads again in full and, when the change adds a
    /// profile, stays within the limit for adding (``limitViolation(_:adding:)``). A change that
    /// breaks this is refused, so the next load never drops a profile the user saw.
    static func fitsLimits(_ profiles: [LayoutProfile], adding: Bool = false) -> Bool {
        limitViolation(profiles, adding: adding) == nil
    }

    /// A limit that a list breaks.
    enum LimitViolation: Equatable, Sendable {
        /// More than ``maximumProfiles`` after adding one, or more than
        /// ``maximumStoredProfiles``.
        case tooMany
        /// Over ``maximumDataSize`` once encoded.
        case tooLarge
    }

    /// The limit a list the app is about to store breaks, or `nil` when it fits
    /// (``fitsLimits(_:adding:)``).
    ///
    /// - Parameters:
    ///   - profiles: The list after the change.
    ///   - adding: Whether the change adds a profile: it may then not hold more than
    ///     ``maximumProfiles``. A change that replaces, renames or binds one only has to stay
    ///     within what the next load keeps (``maximumStoredProfiles``).
    static func limitViolation(_ profiles: [LayoutProfile], adding: Bool = false) -> LimitViolation? {
        if profiles.count > (adding ? maximumProfiles : maximumStoredProfiles) {
            return .tooMany
        }
        return encoded(profiles) == nil ? .tooLarge : nil
    }

    /// The stored name a typed name refers to: the stored name that is exactly the typed text
    /// (white space trimmed), else the first whose cleaned form is the cleaned typed name, else
    /// `nil`. A profile saved by an earlier version can have a name the cleaning changes (a joiner
    /// in an emoji, a soft hyphen, more than 80 characters); typing or keeping that name still
    /// means that profile.
    static func existingName(matching typed: String, among names: [String]) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if names.contains(trimmed) {
            return trimmed
        }
        let cleaned = cleanedName(trimmed)
        guard !cleaned.isEmpty else {
            return nil
        }
        return names.first { cleanedName($0) == cleaned }
    }

    /// The name a typed name is saved under: the stored name it refers to
    /// (``existingName(matching:among:)``), so the profile is replaced and keeps its identity,
    /// else the cleaned typed name. Empty when nothing is left.
    static func savedName(forTyped typed: String, among names: [String]) -> String {
        existingName(matching: typed, among: names) ?? cleanedName(typed)
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
