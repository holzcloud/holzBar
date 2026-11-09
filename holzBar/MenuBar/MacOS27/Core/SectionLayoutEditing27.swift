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

    /// The applications holzBar knows after a read of the bar, or `nil` when the read found
    /// none it did not know (nothing to write).
    ///
    /// Every application read is recorded, also one that already has a layout entry and is
    /// therefore not new: moved to Visible later, its entry is gone, and only this record keeps
    /// a later read from taking it for new and placing it again.
    static func knownAfterRead(bundleIDs: Set<String>, known: Set<String>) -> Set<String>? {
        bundleIDs.isSubset(of: known) ? nil : known.union(bundleIDs)
    }

    /// The layout with every always-hidden entry moved to Hidden.
    ///
    /// With the always-hidden section switched off nothing reveals it, so its applications go to
    /// Hidden, where the Shelf and holzBar's icon reach them. The fold is not undone when the
    /// section is switched on again.
    static func foldingAlwaysHidden(_ layout: [String: MacOS27Section]) -> [String: MacOS27Section] {
        layout.mapValues { $0 == .alwaysHidden ? .hidden : $0 }
    }

    /// The applications a read sees for the first time: neither known nor in the saved layout.
    /// Only these are placed in the section chosen for new items.
    static func newApplications(
        bundleIDs: Set<String>,
        known: Set<String>,
        saved: [String: MacOS27Section]
    ) -> Set<String> {
        bundleIDs.subtracting(known).subtracting(saved.keys)
    }
}
