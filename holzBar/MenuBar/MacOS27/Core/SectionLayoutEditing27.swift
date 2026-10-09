//
//  SectionLayoutEditing27.swift
//  holzBar
//

nonisolated extension SectionLayout27 {
    /// The saved layout after moving an application to a section. Applications missing
    /// from the layout are visible, so moving one to Visible removes its entry.
    static func settingSection(_ section: MacOS27Section, for bundleID: String, in saved: [String: MacOS27Section]) -> [String: MacOS27Section] {
        var updated = saved
        updated[bundleID] = section == .visible ? nil : section
        return updated
    }

    /// The saved layout with the seeded sections of the applications it has no entry for.
    ///
    /// Seeding is holzBar's own placement, so it never overwrites intent: an entry of `saved` stays as it
    /// is, and an application backed by applied intent (`protected`) is left out even when it has no entry
    /// (an application the user moved to Visible has none, and seeding would hide it again).
    ///
    /// - Parameters:
    ///   - seeded: The layout read from the order on the bar.
    ///   - saved: The saved layout.
    ///   - protected: The applications whose arrangement sync's applied intent decides.
    static func fillingMissing(
        _ seeded: [String: MacOS27Section],
        into saved: [String: MacOS27Section],
        except protected: Set<String>
    ) -> [String: MacOS27Section] {
        var filled = saved
        for (bundleID, section) in seeded where saved[bundleID] == nil && !protected.contains(bundleID) {
            filled[bundleID] = section
        }
        return filled
    }

    /// Whether the bar's order may still be read into the saved layout: the layout is empty, or every
    /// entry of it is backed by applied intent, such as the arrangement a group applied at launch. A layout
    /// with any entry holzBar placed or the user arranged without intent is kept as it is.
    static func canSeed(into saved: [String: MacOS27Section], except protected: Set<String>) -> Bool {
        saved.keys.allSatisfy { protected.contains($0) }
    }

    /// The saved layout after applying a layout profile.
    ///
    /// A profile holds the layout as saved, which leaves visible applications out, so the
    /// applications it knew tell a visible one from one it never saw: a known application
    /// missing from the profile becomes visible, and one the profile does not know keeps its
    /// section.
    ///
    /// - Parameters:
    ///   - profile: The profile's sections, keyed by bundle identifier.
    ///   - knownApplications: The applications holzBar knew when the profile was saved, or
    ///     `nil` for a profile that predates that record. Such a profile with no sections was
    ///     saved before macOS 27 and leaves the layout as it is; one with sections was saved on
    ///     macOS 27 and replaces the layout.
    ///   - saved: The saved layout.
    static func applyingProfile(
        _ profile: [String: MacOS27Section],
        knownApplications: Set<String>?,
        to saved: [String: MacOS27Section]
    ) -> [String: MacOS27Section] {
        let known: Set<String>
        if let knownApplications {
            known = knownApplications
        } else if profile.isEmpty {
            return saved
        } else {
            known = Set(saved.keys)
        }
        var updated = saved.filter { !known.contains($0.key) }
        for (bundleID, section) in profile {
            updated = settingSection(section, for: bundleID, in: updated)
        }
        return updated
    }
}
