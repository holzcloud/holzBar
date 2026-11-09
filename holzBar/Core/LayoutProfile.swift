//
//  LayoutProfile.swift
//  holzBar
//

import Foundation

/// A saved arrangement of menu bar items into sections.
///
/// The field names are stored in the defaults and in exported settings, so they never change.
nonisolated struct LayoutProfile: Codable, Hashable, Identifiable, Sendable {
    /// The profile's name, which also identifies it.
    var name: String

    /// The section of each item, keyed by the item's tag (macOS 26 and earlier).
    var itemSections: [String: Int]

    /// The section of each application, keyed by bundle identifier (macOS 27).
    var applicationSections: [String: Int]

    /// The applications holzBar knew when the profile was saved on macOS 27, keyed by bundle
    /// identifier. Visible applications are missing from `applicationSections`, so a known
    /// one missing there is visible. Optional, so profiles saved before macOS 27, or before
    /// this was recorded, decode unchanged.
    var knownApplications: [String]?

    /// The UUID of the display whose connection applies the profile. Optional, so
    /// profiles saved before bindings existed decode unchanged.
    var displayUUID: String?

    /// The UUID of the Space whose activation applies the profile.
    var spaceUUID: String?

    var id: String { name }

    /// Whether the profile is bound to a display or a Space.
    var isBound: Bool {
        displayUUID != nil || spaceUUID != nil
    }
}
