//
//  MenuBarShapes.swift
//  holzBar
//

import SwiftUI

/// An end cap in a menu bar shape.
enum MenuBarEndCap: Int, CaseIterable, Codable, Hashable {
    /// An end cap with a square shape.
    case square = 0
    /// An end cap with a rounded shape.
    case round = 1

    /// Decodes an end cap; one this version does not know (from a newer version or a
    /// damaged file) reads as round, the default, instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = MenuBarEndCap(rawValue: rawValue) ?? .round
    }
}

/// A type that specifies a custom shape kind for the menu bar.
enum MenuBarShapeKind: Int, CaseIterable, Codable, Identifiable {
    /// The menu bar does not use a custom shape.
    case noShape = 0
    /// A custom shape that takes up the full menu bar.
    case full = 1
    /// A custom shape that splits the menu bar between its leading
    /// and trailing sides.
    case split = 2
    /// One shape for the application menus and one for each section the bar shows
    /// (macOS 14 to 26).
    case sections = 3

    var id: Int { rawValue }

    /// Decodes a shape kind; one this version does not know (from a newer version or a
    /// damaged file) reads as no shape instead of failing the whole appearance.
    init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(Int.self)
        self = MenuBarShapeKind(rawValue: rawValue) ?? .noShape
    }

    /// Whether the running macOS can draw the shape: Sections needs holzBar's own section
    /// dividers, which only macOS 14 to 26 lays out (macOS 27 decides the order of the items).
    var isAvailable: Bool {
        guard self == .sections else {
            return true
        }
        if #available(macOS 27.0, *) {
            return false
        }
        return true
    }

    /// The shape the overlay draws: a stored Sections is drawn as Paired where it is not
    /// available, because a section is no contiguous run of the bar on macOS 27.
    var drawnKind: MenuBarShapeKind {
        isAvailable ? self : .split
    }

    /// Localized string key representation.
    ///
    /// Full and Split read as Single and Paired; their stored values are unchanged.
    var localized: LocalizedStringKey {
        switch self {
        case .noShape: "None"
        case .full: "Single"
        case .split: "Paired"
        case .sections: "Sections"
        }
    }
}

/// Information for the ``MenuBarShapeKind/full`` menu bar shape kind.
struct MenuBarFullShapeInfo: Codable, Hashable {
    /// The leading end cap of the shape.
    var leadingEndCap: MenuBarEndCap
    /// The trailing end cap of the shape.
    var trailingEndCap: MenuBarEndCap
}

extension MenuBarFullShapeInfo {
    var hasRoundedShape: Bool {
        leadingEndCap == .round || trailingEndCap == .round
    }
}

extension MenuBarFullShapeInfo {
    static let `default` = MenuBarFullShapeInfo(leadingEndCap: .round, trailingEndCap: .round)
}

/// Information for the ``MenuBarShapeKind/split`` menu bar shape kind.
struct MenuBarSplitShapeInfo: Codable, Hashable {
    /// The leading information of the shape.
    var leading: MenuBarFullShapeInfo
    /// The trailing information of the shape.
    var trailing: MenuBarFullShapeInfo
}

extension MenuBarSplitShapeInfo {
    var hasRoundedShape: Bool {
        leading.hasRoundedShape || trailing.hasRoundedShape
    }
}

extension MenuBarSplitShapeInfo {
    static let `default` = MenuBarSplitShapeInfo(leading: .default, trailing: .default)
}
