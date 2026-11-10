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

    /// A change that moves only the given items and applications, such as an automation rule's.
    ///
    /// It knows exactly the applications it moves. On macOS 27 a profile that knows no
    /// applications but has sections replaces the whole layout, so a partial change without
    /// this record would make every other hidden application visible.
    static func partialChange(itemSections: [String: Int], applicationSections: [String: Int]) -> LayoutProfile {
        LayoutProfile(
            name: "",
            itemSections: itemSections,
            applicationSections: applicationSections,
            knownApplications: applicationSections.keys.sorted()
        )
    }

    /// The profile without the given applications, in its sections and in the applications it
    /// knew.
    ///
    /// A profile must not claim to know an application it leaves out, such as one an automation
    /// rule controls: on macOS 27 a known application missing from the sections becomes visible.
    func removingApplications(_ keys: Set<String>) -> LayoutProfile {
        var result = self
        result.applicationSections = applicationSections.filter { !keys.contains($0.key) }
        result.knownApplications = knownApplications?.filter { !keys.contains($0) }
        return result
    }
}
