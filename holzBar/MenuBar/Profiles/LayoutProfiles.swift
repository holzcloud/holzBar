//
//  LayoutProfiles.swift
//  holzBar
//

import Observation
import Foundation
import OSLog

/// A saved arrangement of menu bar items into sections.
struct LayoutProfile: Codable, Hashable, Identifiable {
    /// The profile's name, which also identifies it.
    var name: String

    /// The section of each item, keyed by the item's tag (macOS 26 and earlier).
    var itemSections: [String: Int]

    /// The section of each application, keyed by bundle identifier (macOS 27).
    var applicationSections: [String: Int]

    var id: String { name }
}

/// Saves and applies layout profiles, such as "Work" and "Home"
/// (jordanbaird/Ice#26).
///
/// A profile records which section each item is in. Applying it moves the items
/// that are in a different section now; items the profile does not know stay
/// where they are.
@MainActor
@Observable
final class LayoutProfiles {
    /// The saved profiles, sorted by name.
    private(set) var profiles = [LayoutProfile]()

    /// The name of the profile that was applied last.
    private(set) var currentProfileName: String?

    @ObservationIgnored private let logger = Logger(category: "LayoutProfiles")
    @ObservationIgnored private weak var appState: AppState?

    func performSetup(with appState: AppState) {
        self.appState = appState
        load()
    }

    private func load() {
        if
            let data = Defaults.data(forKey: .layoutProfiles),
            let decoded = try? JSONDecoder().decode([LayoutProfile].self, from: data)
        {
            profiles = decoded.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        currentProfileName = Defaults.string(forKey: .currentLayoutProfile)
    }

    private func save() {
        profiles.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let data = try? JSONEncoder().encode(profiles) {
            Defaults.set(data, forKey: .layoutProfiles)
        }
        Defaults.set(currentProfileName, forKey: .currentLayoutProfile)
        // Profiles are part of what iCloud sync carries.
        appState?.settingsSync.settingsDidChange()
    }

    /// Saves the current layout under the given name, replacing a profile of
    /// the same name.
    func saveCurrentLayout(as name: String) {
        guard let appState else {
            return
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        let cache = appState.itemManager.itemCache
        var itemSections = [String: Int]()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where !item.isControlItem {
                itemSections[item.tag.description] = section.profileIndex
            }
        }
        let applicationSections = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        let profile = LayoutProfile(name: name, itemSections: itemSections, applicationSections: applicationSections)
        profiles.removeAll { $0.name == name }
        profiles.append(profile)
        currentProfileName = name
        save()
        logger.notice("Saved layout profile \(name, privacy: .private)")
    }

    /// Deletes the profile with the given name.
    func delete(named name: String) {
        profiles.removeAll { $0.name == name }
        if currentProfileName == name {
            currentProfileName = nil
        }
        save()
    }

    /// Applies the profile with the given name, matched without regard to case.
    func apply(named name: String) {
        guard let profile = profiles.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            logger.warning("No layout profile named \(name, privacy: .private)")
            return
        }
        apply(profile)
    }

    /// Applies the given profile.
    func apply(_ profile: LayoutProfile) {
        guard let appState else {
            return
        }
        currentProfileName = profile.name
        save()
        logger.notice("Applying layout profile \(profile.name, privacy: .private)")
        if #available(macOS 27.0, *) {
            Defaults.set(profile.applicationSections, forKey: .macOS27Layout)
            appState.concealer27.update()
            Task {
                await appState.itemManager.cacheItemsRegardless()
            }
            return
        }
        let sections = profile.itemSections.compactMapValues(MenuBarSection.Name.init(profileIndex:))
        Task {
            await appState.itemManager.move(itemsTo: sections)
        }
    }

    /// Replaces all profiles, for example with the ones from another Mac.
    func replaceProfiles(with profiles: [LayoutProfile]) {
        self.profiles = profiles
        save()
    }
}

extension MenuBarSection.Name {
    /// The section's index in a saved profile.
    var profileIndex: Int {
        switch self {
        case .visible: 0
        case .hidden: 1
        case .alwaysHidden: 2
        }
    }

    /// Creates a section name from its index in a saved profile.
    init?(profileIndex: Int) {
        switch profileIndex {
        case 0: self = .visible
        case 1: self = .hidden
        case 2: self = .alwaysHidden
        default: return nil
        }
    }
}
