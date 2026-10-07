//
//  LayoutProfiles.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// A saved arrangement of menu bar items into sections.
struct LayoutProfile: Codable, Hashable, Identifiable {
    /// The profile's stable ID, which a rename keeps (``ProfileIdentity``). Profiles that
    /// existed before IDs get one derived from their name, so the same profile on two Macs
    /// has the same ID.
    var profileID: String

    /// The profile's name as the user sees it.
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

    var id: String { profileID }

    init(
        profileID: String,
        name: String,
        itemSections: [String: Int],
        applicationSections: [String: Int],
        knownApplications: [String]?,
        displayUUID: String?,
        spaceUUID: String?
    ) {
        self.profileID = profileID
        self.name = name
        self.itemSections = itemSections
        self.applicationSections = applicationSections
        self.knownApplications = knownApplications
        self.displayUUID = displayUUID
        self.spaceUUID = spaceUUID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        // Profiles of older builds pass through `ProfileIdentity.migrate` first; a missing ID
        // here is only a safety net and gets the same ID the migration would give.
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
            ?? ProfileIdentity.legacyProfileID(forName: name)
        self.name = name
        itemSections = try container.decode([String: Int].self, forKey: .itemSections)
        applicationSections = try container.decode([String: Int].self, forKey: .applicationSections)
        knownApplications = try container.decodeIfPresent([String].self, forKey: .knownApplications)
        displayUUID = try container.decodeIfPresent(String.self, forKey: .displayUUID)
        spaceUUID = try container.decodeIfPresent(String.self, forKey: .spaceUUID)
    }

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

    /// Gives the stored profiles their IDs and re-keys the profile hotkeys by them, once.
    ///
    /// Runs before the app state and before sync looks at the defaults, so the first launch
    /// of this build already has the IDs in place and nothing is captured as a user change.
    static func migrateStoredProfileIdentities() {
        let hotkeys = Defaults.dictionary(forKey: .hotkeys) as? [String: Data] ?? [:]
        let migration = ProfileIdentity.migrate(profilesData: Defaults.data(forKey: .layoutProfiles), hotkeys: hotkeys)
        guard migration.changed else {
            return
        }
        if let data = migration.profilesData {
            Defaults.set(data, forKey: .layoutProfiles)
        }
        if migration.hotkeys != hotkeys {
            Defaults.set(migration.hotkeys, forKey: .hotkeys)
        }
    }

    /// The IDs of the stored profiles. The hotkeys load before the profiles do, and register
    /// only the profile hotkeys whose profile exists.
    static func storedProfileIDs() -> Set<String> {
        guard
            let data = Defaults.data(forKey: .layoutProfiles),
            let decoded = try? JSONDecoder().decode([LayoutProfile].self, from: data)
        else {
            return []
        }
        return Set(decoded.map(\.profileID))
    }

    /// Orders profiles by name, then by ID for equal names, so every Mac sorts alike.
    private static func areInOrder(_ lhs: LayoutProfile, _ rhs: LayoutProfile) -> Bool {
        switch lhs.name.localizedStandardCompare(rhs.name) {
        case .orderedAscending:
            true
        case .orderedDescending:
            false
        case .orderedSame:
            lhs.profileID < rhs.profileID
        }
    }

    private func load() {
        if
            let data = Defaults.data(forKey: .layoutProfiles),
            let decoded = try? JSONDecoder().decode([LayoutProfile].self, from: data)
        {
            profiles = decoded.sorted(by: Self.areInOrder)
        }
        currentProfileName = Defaults.string(forKey: .currentLayoutProfile)
    }

    private func save() {
        profiles.sort(by: Self.areInOrder)
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
        var itemApplications = Set<String>()
        for section in MenuBarSection.Name.allCases {
            for item in cache[section] where !item.isControlItem {
                // Stored under the item's identity, which survives a changing title.
                itemSections[itemManager.identityKey(for: item)] = section.profileIndex
                if let bundleID = item.sourceApplication?.bundleIdentifier {
                    itemApplications.insert(bundleID)
                }
            }
        }
        // A profile saved again under its name keeps its ID and its bindings.
        let previous = profiles.first { $0.name == name }
        // A profile records only the part of the running macOS generation and keeps the other
        // part of a profile saved before, so saving on one generation never wipes what the
        // other one saved (D-05). A Mac before macOS 27 never copies its own macOS 27 layout
        // into a profile.
        var itemSectionsToSave = previous?.itemSections ?? [:]
        var applicationSections = previous?.applicationSections ?? [:]
        var knownApplications = previous?.knownApplications
        if #available(macOS 27.0, *) {
            applicationSections = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
            // The layout leaves visible applications out, so the profile records which ones it
            // knew; applying it makes those visible unless it has them in another section.
            let known = Defaults.array(forKey: .knownApplications27) as? [String] ?? []
            knownApplications = itemApplications.union(known).union(applicationSections.keys).sorted()
        } else {
            itemSectionsToSave = itemSections
        }
        let profile = LayoutProfile(
            profileID: previous?.profileID ?? ProfileIdentity.newProfileID(),
            name: name,
            itemSections: itemSectionsToSave,
            applicationSections: applicationSections,
            knownApplications: knownApplications,
            displayUUID: previous?.displayUUID,
            spaceUUID: previous?.spaceUUID
        )
        registerUndo(named: String(localized: "Save Profile"))
        profiles.removeAll { $0.profileID == profile.profileID }
        profiles.append(profile)
        currentProfileName = name
        save()
        logger.notice("Saved layout profile \(name, privacy: .private)")
    }

    /// The profiles this Mac can apply: every profile on macOS 27, and before it the ones
    /// that have a part for the item layout. A profile saved only on macOS 27 changes nothing
    /// on an older Mac.
    var applicableProfiles: [LayoutProfile] {
        if #available(macOS 27.0, *) {
            return profiles
        }
        return profiles.filter { !$0.itemSections.isEmpty }
    }

    /// Deletes the profile with the given ID and its hotkey.
    func delete(profileID: String) {
        guard let profile = profile(withID: profileID) else {
            return
        }
        registerUndo(named: String(localized: "Delete Profile"))
        profiles.removeAll { $0.profileID == profileID }
        if currentProfileName == profile.name, !profiles.contains(where: { $0.name == profile.name }) {
            currentProfileName = nil
        }
        save()
        appState?.settings.hotkeys.removeHotkey(for: .applyProfile(profileID))
    }

    /// The profile with the given ID.
    func profile(withID profileID: String) -> LayoutProfile? {
        profiles.first { $0.profileID == profileID }
    }

    /// The profile with the given name. An exact match wins, since names may differ only in
    /// case; without one, the name is matched without regard to case. Of several exact
    /// matches (two Macs may create the same name independently), the one with the smallest
    /// ID wins, so every Mac picks the same.
    func profile(named name: String) -> LayoutProfile? {
        profiles.filter { $0.name == name }.min { $0.profileID < $1.profileID }
            ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Applies the profile with the given name, matched as in ``profile(named:)``.
    func apply(named name: String, byUser: Bool) {
        guard let profile = self.profile(named: name) else {
            logger.warning("No layout profile named \(name, privacy: .private)")
            return
        }
        apply(profile, byUser: byUser)
    }

    /// Applies the profile with the given ID.
    func apply(profileID: String, byUser: Bool) {
        guard let profile = profile(withID: profileID) else {
            logger.warning("No layout profile with ID \(profileID, privacy: .private)")
            return
        }
        apply(profile, byUser: byUser)
    }

    /// Applies the given profile.
    ///
    /// - Parameters:
    ///   - profile: The profile to apply.
    ///   - byUser: Whether the user did it: the menu, Settings, a hotkey, Shortcuts and
    ///     `holzbar://` pass `true`; a Space or display binding passes `false`, since it is
    ///     automatic (D-04).
    func apply(_ profile: LayoutProfile, byUser: Bool) {
        guard let appState else {
            return
        }
        currentProfileName = profile.name
        save()
        logger.notice("Applying layout profile \(profile.name, privacy: .private)")
        if #available(macOS 27.0, *) {
            // Merged into the saved layout, so applications the profile does not know keep
            // their section. A profile saved before macOS 27 knows none and changes nothing.
            if profile.knownApplications == nil, profile.applicationSections.isEmpty {
                logger.notice("Layout profile \(profile.name, privacy: .private) has no macOS 27 layout, so the current one stays")
            } else {
                let stored = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
                let layout = SectionLayout27.applyingProfile(
                    profile.applicationSections.compactMapValues(MacOS27Section.init(rawValue:)),
                    knownApplications: profile.knownApplications.map(Set.init),
                    to: stored.compactMapValues(MacOS27Section.init(rawValue:))
                )
                Defaults.set(layout.mapValues(\.rawValue), forKey: .macOS27Layout)
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

    /// Renames a profile. Its ID, and with it its hotkey and bindings, stay. A name that
    /// another profile has is refused.
    func rename(_ profile: LayoutProfile, to newName: String) {
        let newName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !newName.isEmpty,
            newName != profile.name,
            !profiles.contains(where: { $0.name == newName }),
            let index = profiles.firstIndex(where: { $0.profileID == profile.profileID })
        else {
            return
        }
        registerUndo(named: String(localized: "Rename Profile"))
        profiles[index].name = newName
        if currentProfileName == profile.name {
            currentProfileName = newName
        }
        save()
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
        let removedIDs = Set(profiles.map(\.profileID)).subtracting(restored.map(\.profileID))
        profiles = restored
        currentProfileName = restoredCurrent
        save()
        guard let hotkeySettings = appState?.settings.hotkeys else {
            return
        }
        for profileID in removedIDs where hotkeys[profileID] == nil {
            hotkeySettings.removeHotkey(for: .applyProfile(profileID))
        }
        for (profileID, keyCombination) in hotkeys {
            // Another hotkey may have taken the combination since, and the system
            // registers a combination only once per app.
            guard hotkeySettings.hotkey(using: keyCombination, except: .applyProfile(profileID)) == nil else {
                logger.info("Not restoring a profile's hotkey: another hotkey uses its combination")
                continue
            }
            hotkeySettings.setKeyCombination(keyCombination, for: .applyProfile(profileID))
        }
    }

    /// The key combinations of the profiles' hotkeys, by profile ID.
    private func profileHotkeys() -> [String: KeyCombination] {
        guard let hotkeySettings = appState?.settings.hotkeys else {
            return [:]
        }
        var result = [String: KeyCombination]()
        for profile in profiles {
            if let keyCombination = hotkeySettings.existingHotkey(for: .applyProfile(profile.profileID))?.keyCombination {
                result[profile.profileID] = keyCombination
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
            if profiles[index].profileID == profile.profileID {
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
            if profiles[index].profileID == profile.profileID {
                profiles[index].spaceUUID = spaceUUID
            } else if spaceUUID != nil, profiles[index].spaceUUID == spaceUUID {
                profiles[index].spaceUUID = nil
            }
        }
        save()
    }

    /// Removes both bindings of a profile.
    func unbind(_ profile: LayoutProfile) {
        guard let index = profiles.firstIndex(where: { $0.profileID == profile.profileID }) else {
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
        // `ProfileBinding` identifies profiles by the string in `name`; here it is the profile ID,
        // so two profiles with the same name stay apart.
        let bindings = profiles.map { profile in
            ProfileBinding.Profile(name: profile.profileID, displayUUID: profile.displayUUID, spaceUUID: profile.spaceUUID)
        }
        let currentProfileID = profiles.first { $0.name == currentProfileName }?.profileID
        guard
            let profileID = ProfileBinding.profileToApply(profiles: bindings, event: event, currentProfile: currentProfileID),
            let profile = profile(withID: profileID)
        else {
            return
        }
        logger.notice("Applying the bound layout profile \(profile.name, privacy: .private)")
        // A Space or display applies it by itself, so it is not the user's change.
        apply(profile, byUser: false)
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
