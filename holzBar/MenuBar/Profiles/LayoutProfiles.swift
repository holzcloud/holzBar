//
//  LayoutProfiles.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// A saved arrangement of menu bar items into sections.
struct LayoutProfile: Codable, Hashable, Identifiable {
    /// The profile's name, which also identifies it.
    var name: String

    /// The section of each item, keyed by the item's tag (macOS 26 and earlier).
    var itemSections: [String: Int]

    /// The section of each application, keyed by bundle identifier (macOS 27).
    var applicationSections: [String: Int]

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

    /// Whether an item is being dragged in the Menu Bar Layout pane; a bound profile waits
    /// until the drop.
    @ObservationIgnored var isLayoutDragInProgress = false

    @ObservationIgnored private let logger = Logger(category: "LayoutProfiles")
    @ObservationIgnored private weak var appState: AppState?

    /// The UUIDs of the displays connected at the last check.
    @ObservationIgnored private var connectedDisplays = Set<String>()

    /// Receives the changes of the active Space.
    @ObservationIgnored private var spaceTask: Task<Void, Never>?

    func performSetup(with appState: AppState) {
        self.appState = appState
        load()
        connectedDisplays = Self.connectedDisplayUUIDs()
        // A display change is acted on once the bar has settled after it (THAW-11): only
        // the displays that are new then can apply a profile.
        appState.systemActivityMonitor.onSettled { [weak self] in
            self?.systemActivityDidSettle()
        }
        spaceTask = Task { [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                self?.activeSpaceDidChange()
            }
        }
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
        let itemManager = appState.itemManager
        let cache = itemManager.itemCache
        var itemSections = [String: Int]()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where !item.isControlItem {
                // Stored under the item's identity, which survives a changing title.
                itemSections[itemManager.identityKey(for: item)] = section.profileIndex
            }
        }
        let applicationSections = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        // A profile saved again under its name keeps its bindings.
        let previous = profiles.first { $0.name == name }
        let profile = LayoutProfile(
            name: name,
            itemSections: itemSections,
            applicationSections: applicationSections,
            displayUUID: previous?.displayUUID,
            spaceUUID: previous?.spaceUUID
        )
        registerUndo(named: String(localized: "Save Profile"))
        profiles.removeAll { $0.name == name }
        profiles.append(profile)
        currentProfileName = name
        save()
        logger.notice("Saved layout profile \(name, privacy: .private)")
    }

    /// Deletes the profile with the given name.
    func delete(named name: String) {
        registerUndo(named: String(localized: "Delete Profile"))
        profiles.removeAll { $0.name == name }
        if currentProfileName == name {
            currentProfileName = nil
        }
        save()
        appState?.settings.hotkeys.removeHotkey(for: .applyProfile(name))
    }

    /// The profile with the given name. An exact match wins, since names may differ only in
    /// case; without one, the name is matched without regard to case.
    func profile(named name: String) -> LayoutProfile? {
        profiles.first { $0.name == name }
            ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Applies the profile with the given name, matched as in ``profile(named:)``.
    func apply(named name: String) {
        guard let profile = self.profile(named: name) else {
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
            // Merged into the saved layout, so applications the profile does not know keep
            // their section. A profile saved before macOS 27 knows none and changes nothing.
            if profile.applicationSections.isEmpty {
                logger.notice("Layout profile \(profile.name, privacy: .private) has no macOS 27 layout, so the current one stays")
            } else {
                var layout = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
                layout.merge(profile.applicationSections) { _, new in new }
                Defaults.set(layout, forKey: .macOS27Layout)
            }
            appState.concealer27.update()
            Task {
                await appState.itemManager.cacheItemsRegardless()
            }
            return
        }
        // Keys of earlier versions (`namespace:title`) match through the item identity.
        let itemManager = appState.itemManager
        var sections = [String: MenuBarSection.Name]()
        for (key, index) in profile.itemSections {
            if let section = MenuBarSection.Name(profileIndex: index) {
                sections[itemManager.storedIdentityKey(key)] = section
            }
        }
        Task {
            await itemManager.reconcileSections(wanted: sections, trigger: .profile)
        }
    }

    /// Replaces all profiles, for example with the ones from another Mac.
    func replaceProfiles(with profiles: [LayoutProfile]) {
        self.profiles = profiles
        save()
    }

    /// Renames a profile; its hotkey moves with it. A name that another profile has is
    /// refused.
    func rename(_ profile: LayoutProfile, to newName: String) {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !newName.isEmpty,
            newName != profile.name,
            !profiles.contains(where: { $0.name == newName }),
            let index = profiles.firstIndex(where: { $0.name == profile.name })
        else {
            return
        }
        registerUndo(named: String(localized: "Rename Profile"))
        profiles[index].name = newName
        if currentProfileName == profile.name {
            currentProfileName = newName
        }
        save()
        appState?.settings.hotkeys.moveHotkey(from: .applyProfile(profile.name), to: .applyProfile(newName))
    }

    // MARK: Undo

    /// Registers "restore the profiles as they are now" on the Settings window's undo
    /// manager, before a change. Undo restores the list, the applied profile's name and
    /// the profiles' hotkeys; it never touches the menu bar.
    private func registerUndo(named actionName: String) {
        guard let undoManager = appState?.navigationState.settingsWindow?.undoManager else {
            return
        }
        let profiles = self.profiles
        let currentProfileName = self.currentProfileName
        let hotkeys = profileHotkeys()
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(profiles: profiles, currentProfileName: currentProfileName, hotkeys: hotkeys, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Puts back the profiles of an undone change, and registers the redo.
    private func restore(
        profiles restored: [LayoutProfile],
        currentProfileName restoredCurrent: String?,
        hotkeys: [String: KeyCombination],
        actionName: String
    ) {
        registerUndo(named: actionName)
        let removedNames = Set(profiles.map(\.name)).subtracting(restored.map(\.name))
        profiles = restored
        currentProfileName = restoredCurrent
        save()
        guard let hotkeySettings = appState?.settings.hotkeys else {
            return
        }
        for name in removedNames where hotkeys[name] == nil {
            hotkeySettings.removeHotkey(for: .applyProfile(name))
        }
        for (name, keyCombination) in hotkeys {
            hotkeySettings.setKeyCombination(keyCombination, for: .applyProfile(name))
        }
    }

    /// The key combinations of the profiles' hotkeys, by profile name.
    private func profileHotkeys() -> [String: KeyCombination] {
        guard let hotkeySettings = appState?.settings.hotkeys else {
            return [:]
        }
        var result = [String: KeyCombination]()
        for profile in profiles {
            if let keyCombination = hotkeySettings.existingHotkey(for: .applyProfile(profile.name))?.keyCombination {
                result[profile.name] = keyCombination
            }
        }
        return result
    }

    // MARK: Bindings

    /// Binds a profile to a display, or removes its display binding (`nil`). A display is
    /// bound to one profile at most.
    func bind(_ profile: LayoutProfile, toDisplay displayUUID: String?) {
        registerUndo(named: String(localized: "Bind Profile"))
        for index in profiles.indices {
            if profiles[index].name == profile.name {
                profiles[index].displayUUID = displayUUID
            } else if displayUUID != nil, profiles[index].displayUUID == displayUUID {
                profiles[index].displayUUID = nil
            }
        }
        save()
    }

    /// Binds a profile to a Space, or removes its Space binding (`nil`). A Space is bound
    /// to one profile at most.
    func bind(_ profile: LayoutProfile, toSpace spaceUUID: String?) {
        registerUndo(named: String(localized: "Bind Profile"))
        for index in profiles.indices {
            if profiles[index].name == profile.name {
                profiles[index].spaceUUID = spaceUUID
            } else if spaceUUID != nil, profiles[index].spaceUUID == spaceUUID {
                profiles[index].spaceUUID = nil
            }
        }
        save()
    }

    /// Removes both bindings of a profile.
    func unbind(_ profile: LayoutProfile) {
        guard let index = profiles.firstIndex(where: { $0.name == profile.name }) else {
            return
        }
        registerUndo(named: String(localized: "Remove Binding"))
        profiles[index].displayUUID = nil
        profiles[index].spaceUUID = nil
        save()
    }

    /// The UUIDs of the connected displays.
    static func connectedDisplayUUIDs() -> Set<String> {
        Set(NSScreen.screens.compactMap { screen in
            Bridging.getDisplayUUIDString(for: screen.displayID)
        })
    }

    /// Applies the profile bound to a display that was connected meanwhile.
    private func systemActivityDidSettle() {
        let current = Self.connectedDisplayUUIDs()
        let newlyConnected = ProfileBinding.newlyConnected(previous: connectedDisplays, current: current)
        connectedDisplays = current
        guard !newlyConnected.isEmpty, profiles.contains(where: { $0.displayUUID != nil }) else {
            return
        }
        applyBoundProfile(for: .displaysConnected(newlyConnected, activeSpace: Bridging.getActiveSpaceUUID()))
    }

    /// Applies the profile bound to the Space that became active.
    private func activeSpaceDidChange() {
        guard
            profiles.contains(where: { $0.spaceUUID != nil }),
            let spaceUUID = Bridging.getActiveSpaceUUID()
        else {
            return
        }
        applyBoundProfile(for: .spaceChanged(spaceUUID))
    }

    /// Applies the profile `ProfileBinding` chooses for the event, unless Zen mode is on or
    /// an item is being dragged in the Menu Bar Layout pane.
    private func applyBoundProfile(for event: ProfileBinding.Event) {
        guard
            let appState,
            !appState.menuBarManager.zenMode.isActive,
            !isLayoutDragInProgress
        else {
            return
        }
        let bindings = profiles.map { profile in
            ProfileBinding.Profile(name: profile.name, displayUUID: profile.displayUUID, spaceUUID: profile.spaceUUID)
        }
        guard
            let name = ProfileBinding.profileToApply(profiles: bindings, event: event, currentProfile: currentProfileName),
            let profile = profiles.first(where: { $0.name == name })
        else {
            return
        }
        logger.notice("Applying the bound layout profile \(name, privacy: .private)")
        apply(profile)
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
