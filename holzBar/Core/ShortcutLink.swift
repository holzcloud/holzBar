//
//  ShortcutLink.swift
//  holzBar
//

import Foundation

/// The link that runs a Shortcut of the user's.
nonisolated enum ShortcutLink {
    /// The most bytes of a Shortcut name.
    static let maximumNameBytes = 255

    static func cleanedName(_ name: String) -> String? {
        nil
    }

    static func runURL(forShortcutNamed name: String) -> URL? {
        nil
    }

    static func storedNames(_ stored: [String: Any]?, keeping ids: Set<UUID>) -> [UUID: String] {
        [:]
    }
}
