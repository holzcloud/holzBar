//
//  ShortcutLink.swift
//  holzBar
//

import Foundation

/// The link that runs a Shortcut of the user's, and the rules for the name it carries (D-21).
///
/// A widget button runs a Shortcut chosen by typing its name, because no public API lists a
/// user's Shortcuts without an extra permission. holzBar opens the link and nothing else: the
/// link has no callback parameter of any kind and nothing is returned, so the Shortcut runs in
/// the Shortcuts app and holzBar never sees its input or output. The name comes from the user's
/// defaults, which any process of the user can write, so it is cleaned before it is used.
nonisolated enum ShortcutLink {
    /// The most bytes of a Shortcut name.
    static let maximumNameBytes = 255

    private static let prefix = "shortcuts://run-shortcut?name="

    /// The general categories a name never holds: control, format (which includes the
    /// zero-width and the bidirectional characters, such as a right-to-left override), private
    /// use, surrogate, unassigned, and the line and paragraph separators. These are the
    /// categories `ScriptGate.isPlainName` refuses in a file name.
    private static let refusedCategories: Set<Unicode.GeneralCategory> = [
        .control, .format, .privateUse, .surrogate, .unassigned, .lineSeparator, .paragraphSeparator,
    ]

    /// The name as it is run: trimmed of the spaces, tabs and line breaks around it, or `nil`
    /// when it cannot be a Shortcut name: it is empty, over ``maximumNameBytes`` UTF-8 bytes, or
    /// holds a character of a refused category (a line break inside the name is one).
    ///
    /// Only space separators, the tab and the ASCII line breaks are trimmed, whatever the
    /// platform's character sets say, so an invisible character at an edge (a zero-width space,
    /// a next-line or a separator) is refused, not dropped.
    static func cleanedName(_ name: String) -> String? {
        let scalars = Array(name.unicodeScalars)
        guard
            let first = scalars.firstIndex(where: { !isTrimmed($0) }),
            let last = scalars.lastIndex(where: { !isTrimmed($0) })
        else {
            return nil
        }
        let kept = scalars[first...last]
        guard !kept.contains(where: { refusedCategories.contains($0.properties.generalCategory) }) else {
            return nil
        }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: kept)
        let trimmed = String(view)
        guard trimmed.utf8.count <= maximumNameBytes else {
            return nil
        }
        return trimmed
    }

    /// The link that runs the Shortcut with the given name, or `nil` when the name is not clean
    /// (``cleanedName(_:)``).
    ///
    /// The name is the one value of the one query item. Every byte of it that is not an ASCII
    /// letter, a digit or one of `-._~` is percent-encoded, so no character of a name (`&`, `=`,
    /// `#`, `%`, `+`, `?`, a space, a line break) can end the value or start another parameter.
    /// `URLComponents` is not used for it: it leaves `+` and `&` unencoded in a value.
    static func runURL(forShortcutNamed name: String) -> URL? {
        guard let name = cleanedName(name) else {
            return nil
        }
        let digits = Array("0123456789ABCDEF".unicodeScalars)
        var encoded = String.UnicodeScalarView()
        for byte in name.utf8 {
            if isUnreserved(byte) {
                encoded.append(Unicode.Scalar(byte))
            } else {
                encoded.append("%")
                encoded.append(digits[Int(byte >> 4)])
                encoded.append(digits[Int(byte & 0x0F)])
            }
        }
        return URL(string: prefix + String(encoded))
    }

    /// The stored Shortcut names of the widgets that exist: the keys that are widget identifiers
    /// in `ids`, with a value that is a clean name (cleaned). Anything else in the stored
    /// dictionary is dropped, and at most ``WidgetDefinition/maximumCount`` names are kept, the
    /// same ones every time.
    ///
    /// - Parameters:
    ///   - stored: The dictionary under `Defaults.Key.widgetShortcutNames`, as the defaults give
    ///     it, or `nil` when none is stored.
    ///   - ids: The identifiers of the widgets that exist.
    static func storedNames(_ stored: [String: Any]?, keeping ids: Set<UUID>) -> [UUID: String] {
        guard let stored else {
            return [:]
        }
        var names = [UUID: String]()
        // Sorted keys: a lower-case and an upper-case spelling of one identifier, or more names
        // than widgets, give the same result on every launch.
        for key in stored.keys.sorted() {
            guard
                names.count < WidgetDefinition.maximumCount,
                let id = UUID(uuidString: key),
                ids.contains(id),
                names[id] == nil,
                let value = stored[key] as? String,
                let name = cleanedName(value)
            else {
                continue
            }
            names[id] = name
        }
        return names
    }

    private static func isTrimmed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09, 0x0A, 0x0D:
            return true
        default:
            return scalar.properties.generalCategory == .spaceSeparator
        }
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"),
            UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"),
            UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }
}
