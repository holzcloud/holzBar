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
}
