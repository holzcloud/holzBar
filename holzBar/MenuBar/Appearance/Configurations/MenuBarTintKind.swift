//
//  MenuBarTintKind.swift
//  holzBar
//

import SwiftUI

/// A type that specifies how the menu bar is tinted.
///
/// The raw values are stored in the appearance configuration; new kinds go at the end.
enum MenuBarTintKind: Int, CaseIterable, Codable, Identifiable {
    /// The menu bar is not tinted.
    case noTint = 0
    /// The menu bar is tinted with a solid color.
    case solid = 1
    /// The menu bar is tinted with a gradient.
    case gradient = 2
    /// The menu bar is tinted with the dominant colors of the wallpaper (THAW-17).
    case adaptive = 3
    /// The menu bar shows the system's glass (macOS 26 and later; THAW-17).
    case systemGlass = 4

    var id: Int { rawValue }

    /// Decodes a tint kind; one this version does not know (from a newer version or a
    /// damaged file) reads as no tint instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = MenuBarTintKind(rawValue: rawValue) ?? .noTint
    }

    /// Whether the running macOS can draw the tint.
    var isAvailable: Bool {
        guard self == .systemGlass else {
            return true
        }
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .noTint: "None"
        case .solid: "Solid"
        case .gradient: "Gradient"
        case .adaptive: "Follow Wallpaper"
        case .systemGlass: "System Glass"
        }
    }
}
