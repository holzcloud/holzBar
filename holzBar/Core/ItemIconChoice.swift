//
//  ItemIconChoice.swift
//  holzBar
//

import Foundation

/// What picture a menu bar item shows in the holzBar Shelf, the search, the Layout pane and
/// the item hints (THAW-16).
///
/// The order: an image the user chose, the item's own picture (a capture, which needs
/// Screen Recording), the icon of the item's app, and its name when there is nothing else.
/// "Use App Icon" puts the app icon before the capture.
nonisolated enum ItemIconChoice {
    /// A choice stored in the `ItemIcons` setting, by item identity.
    nonisolated enum Stored: Equatable, Sendable {
        /// The icon of the item's app.
        case appIcon
        /// An image file in holzBar's `ItemIcons` folder.
        case file(String)
    }

    /// What the item shows.
    nonisolated enum Source: Equatable, Sendable {
        case custom
        case captured
        case appIcon
        case name
    }

    /// The stored value of "Use App Icon".
    static let appIconValue = "app"

    /// The prefix of a stored image file.
    static let filePrefix = "file:"

    /// Reads a stored choice; anything else, and any file name that could reach outside
    /// holzBar's folder, reads as no choice.
    static func parse(_ value: String?) -> Stored? {
        guard let value else {
            return nil
        }
        if value == appIconValue {
            return .appIcon
        }
        guard value.hasPrefix(filePrefix) else {
            return nil
        }
        let name = String(value.dropFirst(filePrefix.count))
        return isValidFileName(name) ? .file(name) : nil
    }

    /// The value a choice is stored as.
    static func storedValue(_ stored: Stored) -> String {
        switch stored {
        case .appIcon:
            appIconValue
        case .file(let name):
            filePrefix + name
        }
    }

    /// Whether a name can be a file in holzBar's image folder: a PNG with letters, digits,
    /// hyphens and underscores only, so never a path.
    static func isValidFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else {
            return false
        }
        let base = name.dropLast(4)
        guard !base.isEmpty, base.count <= 64 else {
            return false
        }
        return base.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
        }
    }

    /// What an item shows.
    ///
    /// - Parameters:
    ///   - stored: The user's choice for the item.
    ///   - hasCustomImage: Whether the chosen image file could be read.
    ///   - hasCapture: Whether a picture of the item was taken.
    ///   - hasAppIcon: Whether the item's app has an icon.
    static func source(stored: Stored?, hasCustomImage: Bool, hasCapture: Bool, hasAppIcon: Bool) -> Source {
        switch stored {
        case .file:
            if hasCustomImage {
                return .custom
            }
        case .appIcon:
            if hasAppIcon {
                return .appIcon
            }
        case nil:
            break
        }
        if hasCapture {
            return .captured
        }
        return hasAppIcon ? .appIcon : .name
    }
}

/// Colours stored as `#RRGGBB` strings, as a group's colour is.
nonisolated enum HexColor {
    /// The red, green and blue components (0 to 1) of a `#RRGGBB` string, or `nil`.
    static func components(_ hex: String) -> (red: Double, green: Double, blue: Double)? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            return nil
        }
        return (
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The `#RRGGBB` string of the given components, each clamped to 0 to 1.
    static func string(red: Double, green: Double, blue: Double) -> String {
        func byte(_ component: Double) -> Int {
            Int((min(max(component, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
