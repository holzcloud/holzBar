//
//  SharedProfile.swift
//  holzBar
//

import Foundation

/// A layout profile that can be sent to someone else: its name and which section each
/// application is in. It is data only and never runs anything.
///
/// It carries nothing of the Mac it came from: no display or Space bindings, no Wi-Fi names,
/// no rules, hotkeys, groups, paths or user names. Applications are matched by bundle
/// identifier. A file is untrusted input: ``decode(_:)`` rejects the whole file when anything
/// in it is outside the limits.
nonisolated struct SharedProfile: Codable, Equatable, Sendable {
    /// The file format this version reads and writes.
    static let currentFormat = 1
    /// The largest file read, in bytes.
    static let maximumSize = 64 * 1024
    /// The most applications in a file.
    static let maximumEntries = 500
    /// The longest profile name kept.
    static let maximumNameLength = 80

    /// One application and its section: 0 visible, 1 hidden, 2 always hidden.
    nonisolated struct Entry: Codable, Equatable, Sendable {
        var id: String
        var section: Int
    }

    var format = SharedProfile.currentFormat
    var name: String
    var apps: [Entry]

    /// Why a file was refused.
    nonisolated enum Failure: Error, Equatable, Sendable {
        case tooLarge
        case notAProfile
        case unknownFormat
        case invalidName
        case tooManyApps
        case invalidApp
        case invalidSection
    }

    /// Reads and checks a file.
    static func decode(_ data: Data) -> Result<SharedProfile, Failure> {
        guard data.count <= maximumSize else {
            return .failure(.tooLarge)
        }
        guard let decoded = try? JSONDecoder().decode(SharedProfile.self, from: data) else {
            return .failure(.notAProfile)
        }
        guard decoded.format == currentFormat else {
            return .failure(.unknownFormat)
        }
        let name = cleanedName(decoded.name)
        guard !name.isEmpty else {
            return .failure(.invalidName)
        }
        guard decoded.apps.count <= maximumEntries else {
            return .failure(.tooManyApps)
        }
        var seen = Set<String>()
        var apps: [Entry] = []
        for entry in decoded.apps {
            guard isValidBundleIdentifier(entry.id) else {
                return .failure(.invalidApp)
            }
            guard (0...2).contains(entry.section) else {
                return .failure(.invalidSection)
            }
            if seen.insert(entry.id).inserted {
                apps.append(entry)
            }
        }
        return .success(SharedProfile(name: name, apps: apps))
    }

    /// The file's bytes.
    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }

    /// The name without control characters, trimmed and shortened.
    static func cleanedName(_ name: String) -> String {
        let withoutControls = name.unicodeScalars.filter { scalar in
            ![.control, .format, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
        }
        let text = String(String.UnicodeScalarView(withoutControls))
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumNameLength))
    }

    /// Whether the text is a reverse-DNS identifier: letters, digits, dots, hyphens and
    /// underscores, with at least one dot, up to 255 characters.
    static func isValidBundleIdentifier(_ text: String) -> Bool {
        guard (3...255).contains(text.utf8.count), text.contains(".") else {
            return false
        }
        return text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(Character(scalar)) || ".-_".unicodeScalars.contains(scalar))
        }
    }

    /// The applications of an arrangement, for export. The namespace of an item (the part of
    /// its key before the first colon) is the bundle identifier of its app; an application
    /// with items in several sections takes the most visible one. Namespaces that are not
    /// identifiers, such as the UUIDs of system items, are left out.
    ///
    /// - Parameters:
    ///   - itemSections: The section of each item by key (macOS 14 to 26).
    ///   - applicationSections: The section of each application (macOS 27).
    ///   - knownApplications: The applications known on macOS 27; those missing from
    ///     `applicationSections` are visible.
    static func applications(
        itemSections: [String: Int],
        applicationSections: [String: Int],
        knownApplications: [String]?
    ) -> [Entry] {
        var sections = [String: Int]()
        func note(_ id: String, _ section: Int) {
            guard isValidBundleIdentifier(id), (0...2).contains(section) else {
                return
            }
            sections[id] = min(sections[id] ?? section, section)
        }
        for (key, section) in itemSections {
            if let namespace = key.split(separator: ":", maxSplits: 1).first {
                note(String(namespace), section)
            }
        }
        for (id, section) in applicationSections {
            note(id, section)
        }
        for id in knownApplications ?? [] where sections[id] == nil {
            note(id, 0)
        }
        return sections.map { Entry(id: $0.key, section: $0.value) }.sorted { $0.id < $1.id }
    }

    /// A name that no profile in `existing` has: the name itself, or the name with a number.
    static func uniqueName(_ name: String, among existing: [String]) -> String {
        guard existing.contains(name) else {
            return name
        }
        var number = 2
        while existing.contains("\(name) \(number)") {
            number += 1
        }
        return "\(name) \(number)"
    }
}
