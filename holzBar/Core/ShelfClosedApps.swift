//
//  ShelfClosedApps.swift
//  holzBar
//

import Foundation

/// The applications the holzBar Shelf can show dimmed because they are not running.
///
/// holzBar remembers the section of every application whose item it moved or hid: on macOS 27
/// by bundle identifier (`Defaults.Key.macOS27Layout`), before by item (`Defaults.Key.itemSections`,
/// keyed `bundle identifier:title`). An application with such an entry that is not running has
/// no item on the bar, so the Shelf would not list it; with the setting on it lists the application
/// instead, and a click launches it.
nonisolated enum ShelfClosedApps {
    /// The most closed applications the Shelf lists for one section.
    static let maximumPerSection = 24

    /// The bundle identifiers of the applications that are not running and are remembered in
    /// the hidden and in the always-hidden section, each sorted.
    ///
    /// An application remembered in several sections goes to the most visible one of them, and
    /// one remembered as visible is not listed at all. The system's applications (`com.apple.`)
    /// are never listed: their items belong to the system, which is always running. Neither are
    /// holzBar's own bundle and widgets, or a name that is no bundle identifier (the UUID of a
    /// system item).
    ///
    /// - Parameters:
    ///   - usesMacOS27Layout: Whether the sections are remembered per application (macOS 27).
    ///   - macOS27Layout: The section index of each bundle identifier.
    ///   - itemSections: The section index of each item key.
    ///   - running: The bundle identifiers of the running applications.
    ///   - ownBundleIdentifier: holzBar's own bundle identifier (`Constants.bundleIdentifier`).
    static func bundleIdentifiers(
        usesMacOS27Layout: Bool,
        macOS27Layout: [String: Int],
        itemSections: [String: Int],
        running: Set<String>,
        ownBundleIdentifier: String
    ) -> (hidden: [String], alwaysHidden: [String]) {
        let runningLowercased = Set(running.map { $0.lowercased() })
        var mostVisible = [String: Int]()
        let remembered: [(id: String, section: Int)] = usesMacOS27Layout
            ? macOS27Layout.map { ($0.key, $0.value) }
            : itemSections.map { (String($0.key.prefix { $0 != ":" }), $0.value) }
        for entry in remembered {
            mostVisible[entry.id] = min(mostVisible[entry.id] ?? entry.section, entry.section)
        }

        var hidden = [String]()
        var alwaysHidden = [String]()
        for (id, section) in mostVisible.sorted(by: { $0.key < $1.key }) {
            guard
                section == 1 || section == 2,
                SharedProfile.isValidBundleIdentifier(id),
                !SharedProfile.isOwn(id, bundleIdentifier: ownBundleIdentifier),
                !id.lowercased().hasPrefix("com.apple."),
                !runningLowercased.contains(id.lowercased())
            else {
                continue
            }
            if section == 1 {
                hidden.append(id)
            } else {
                alwaysHidden.append(id)
            }
        }
        return (Array(hidden.prefix(maximumPerSection)), Array(alwaysHidden.prefix(maximumPerSection)))
    }
}
