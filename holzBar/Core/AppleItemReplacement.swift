//
//  AppleItemReplacement.swift
//  holzBar
//

import Foundation

/// An icon of holzBar's own that opens one Apple item.
///
/// macOS 27 hides whole applications, and several of Apple's items can belong to one Apple
/// application, so hiding one of them can hide the others too. A replacement lets the user
/// hide the application's items and keep the wanted one one click away. The raw field names
/// are stored and never change.
nonisolated struct AppleItemReplacement: Codable, Equatable, Identifiable, Sendable {
    /// The most replacements there can be.
    static let maximumCount = 6

    /// The autosave name of a replacement's status item is this prefix and the replacement's
    /// identifier, the pattern of `holzBar.Group.<uuid>`.
    static let autosaveNamePrefix = "holzBar.Replacement."

    let id: UUID
    /// The identity key of the Apple item (`ItemIdentity`).
    var itemKey: String
    /// The name shown as tooltip and read by VoiceOver.
    var title: String
    /// The SF Symbol on the icon, one of ``AppleItemCatalog/symbolNames``.
    var symbolName: String

    /// The name of the replacement's status item.
    var autosaveName: String {
        Self.autosaveNamePrefix + id.uuidString
    }

    /// The identifier an autosave name holds, or `nil` when the name is not exactly
    /// ``autosaveNamePrefix`` and an uppercase UUID.
    static func id(fromAutosaveName name: String) -> UUID? {
        guard name.hasPrefix(autosaveNamePrefix) else {
            return nil
        }
        let suffix = String(name.dropFirst(autosaveNamePrefix.count))
        guard let id = UUID(uuidString: suffix), id.uuidString == suffix else {
            return nil
        }
        return id
    }
}

nonisolated extension AppleItemReplacement {
    /// Only the identifier and the item key are required, so a list with a missing name or
    /// symbol still decodes; the list then drops an entry without a name and replaces a
    /// missing symbol with the default.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        itemKey = try container.decode(String.self, forKey: .itemKey)
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        symbolName = (try? container.decodeIfPresent(String.self, forKey: .symbolName)) ?? AppleItemCatalog.defaultSymbolName
    }
}

/// Which items can be replaced, and the symbols a replacement can wear.
nonisolated enum AppleItemCatalog {
    /// The start of the namespace of every Apple application.
    static let namespacePrefix = "com.apple."

    /// The namespace of the numbered system items (the clock, the battery, Wi-Fi and Control
    /// Centre). They are hidden through `SystemItem27` and cannot be opened from the item
    /// cache, so they are never replaced.
    static let numberedSystemNamespace = "com.apple.MenuBarAgent"

    /// The most bytes of an item key.
    static let maximumKeyBytes = 255

    /// The symbol of a replacement that has none of its own.
    static let defaultSymbolName = "star"

    /// The symbols a replacement can use.
    static let symbolNames = [
        "moon", "music.note", "clock.arrow.circlepath", "person.crop.circle",
        "antenna.radiowaves.left.and.right", "keyboard", "display", "airplayaudio",
        "bell", "bolt", "gearshape", "star",
    ]

    /// Whether the item with the given identity key can be replaced: it belongs to an Apple
    /// application other than the numbered system items. The key is `namespace:title`, or the
    /// bare namespace for an item without a title.
    static func isReplaceable(itemKey: String) -> Bool {
        guard !itemKey.isEmpty, itemKey.utf8.count <= maximumKeyBytes else {
            return false
        }
        let forbidden: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator]
        guard !itemKey.unicodeScalars.contains(where: { forbidden.contains($0.properties.generalCategory) }) else {
            return false
        }
        let namespace = itemKey.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard namespace.hasPrefix(namespacePrefix), namespace.count > namespacePrefix.count else {
            return false
        }
        return namespace.lowercased() != numberedSystemNamespace.lowercased()
    }

    /// The symbol that fits an item best, judged by its key; ``defaultSymbolName`` when
    /// nothing fits.
    static func suggestedSymbol(forItemKey key: String) -> String {
        let lowered = key.lowercased()
        let rules: [(words: [String], symbol: String)] = [
            (["focus"], "moon"),
            (["nowplaying"], "music.note"),
            (["timemachine"], "clock.arrow.circlepath"),
            (["userswitcher"], "person.crop.circle"),
            (["airdrop"], "antenna.radiowaves.left.and.right"),
            (["textinput", "keyboard"], "keyboard"),
            (["display"], "display"),
        ]
        return rules.first { rule in rule.words.contains { lowered.contains($0) } }?.symbol ?? defaultSymbolName
    }
}

/// One element of a stored list that is skipped when it cannot be decoded, instead of making the
/// whole list unreadable.
nonisolated private struct LossyReplacement: Decodable {
    let value: AppleItemReplacement?

    init(from decoder: any Decoder) {
        value = try? AppleItemReplacement(from: decoder)
    }
}

/// The stored list of replacements: decoded element by element, validated, capped and encoded
/// again.
///
/// The list comes from the defaults, an imported settings file or any process of the user, so
/// nothing in it is trusted.
nonisolated enum AppleItemReplacementList {
    /// The most bytes of a list that is read or written.
    static let maximumDataSize = 16_384

    /// The replacements of a stored list, in order. Data that is too large or is not a JSON
    /// array gives an empty list.
    static func decode(_ data: Data) -> [AppleItemReplacement] {
        list(from: data) ?? []
    }

    /// The JSON to store, with sorted keys, or `nil` when it would be over ``maximumDataSize``.
    static func encoded(_ list: [AppleItemReplacement]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(list), data.count <= maximumDataSize else {
            return nil
        }
        return data
    }

    /// An imported list as it may be applied: the decoded and validated replacements, encoded
    /// again, so that unknown fields and a seventh replacement never reach the defaults.
    /// `nil` when the data is too large or is not a JSON array.
    static func normalized(_ data: Data) -> Data? {
        guard let list = list(from: data) else {
            return nil
        }
        return encoded(list)
    }

    /// The validated replacements of a list, or `nil` when the data is too large or is not a
    /// JSON array. An element is kept only if its key is replaceable, its name is not empty once cleaned, and neither its
    /// identifier nor its key was seen before; an unknown symbol becomes the default.
    private static func list(from data: Data) -> [AppleItemReplacement]? {
        guard data.count <= maximumDataSize,
            let elements = try? JSONDecoder().decode([LossyReplacement].self, from: data) else {
            return nil
        }
        var seenIDs = Set<UUID>()
        var seenKeys = Set<String>()
        var replacements = [AppleItemReplacement]()
        for case let element? in elements.map(\.value) {
            guard replacements.count < AppleItemReplacement.maximumCount else {
                break
            }
            var replacement = element
            replacement.title = WidgetDefinition.cleanedTitle(element.title)
            guard
                AppleItemCatalog.isReplaceable(itemKey: replacement.itemKey),
                !replacement.title.isEmpty,
                !seenIDs.contains(replacement.id),
                !seenKeys.contains(replacement.itemKey)
            else {
                continue
            }
            if !AppleItemCatalog.symbolNames.contains(replacement.symbolName) {
                replacement.symbolName = AppleItemCatalog.defaultSymbolName
            }
            seenIDs.insert(replacement.id)
            seenKeys.insert(replacement.itemKey)
            replacements.append(replacement)
        }
        return replacements
    }
}
