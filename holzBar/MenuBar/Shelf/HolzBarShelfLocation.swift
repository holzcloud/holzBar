//
//  HolzBarShelfLocation.swift
//  holzBar
//

import SwiftUI

/// Locations where the holzBar Shelf can appear.
enum HolzBarShelfLocation: Int, CaseIterable, Identifiable {
    /// The holzBar Shelf will appear in different locations based on context.
    case dynamic = 0

    /// The holzBar Shelf will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The holzBar Shelf will appear centered below the holzBar icon.
    case holzBarIcon = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .holzBarIcon: "holzBar icon"
        }
    }
}
