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

    /// What the Focus filter changed, so it can be undone.
    @ObservationIgnored private var focusBinding = FocusFilterBinding()

    /// Receives the changes of the active Space.
    @ObservationIgnored private var spaceTask: Task<Void, Never>?

    /// The apply that waits for its before hooks. A newer apply cancels it (D-13).
    @ObservationIgnored private var pendingApply: Task<Void, Never>?

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
    }

    /// The arrangement of the items now, as a profile without a name or bindings.
    func currentLayout() -> LayoutProfile {
        guard let appState else {
            return LayoutProfile(name: "", itemSections: [:], applicationSections: [:])
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
        let applicationSections = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        // The layout leaves visible applications out, so the profile records which ones it
        // knew; applying it makes those visible unless it has them in another section.
        var knownApplications: [String]?
        if #available(macOS 27.0, *) {
            let known = Defaults.array(forKey: .knownApplications27) as? [String] ?? []
            knownApplications = itemApplications.union(known).union(applicationSections.keys).sorted()
        }
        return LayoutProfile(
            name: "",
            itemSections: itemSections,
            applicationSections: applicationSections,
            knownApplications: knownApplications
        )
    }

    /// Saves the current layout under the given name, replacing a profile of
    /// the same name.
    func saveCurrentLayout(as name: String) {
        guard appState != nil else {
            return
        }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }
        let layout = currentLayout()
        // A profile saved again under its name keeps its bindings.
        let previous = profiles.first { $0.name == name }
        let profile = LayoutProfile(
            name: name,
            itemSections: layout.itemSections,
            applicationSections: layout.applicationSections,
            knownApplications: layout.knownApplications,
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

    /// Adds a profile that someone shared. It does not move any item: the user applies it like
    /// any other. A name that is taken gets a number.
    func importShared(_ shared: SharedProfile) {
        let name = SharedProfile.uniqueName(shared.name, among: profiles.map(\.name))
        var applicationSections = [String: Int]()
        for entry in shared.apps where entry.section != 0 {
            applicationSections[entry.id] = entry.section
        }
        // Before macOS 27 the profile is by item: the items of the shared applications that
        // are in the menu bar now.
        var itemSections = [String: Int]()
        if let appState {
            let wanted = Dictionary(shared.apps.map { ($0.id, $0.section) }, uniquingKeysWith: { first, _ in first })
            let itemManager = appState.itemManager
            for section in MenuBarSection.Name.allCases {
                for item in itemManager.itemCache[section] where !item.isControlItem {
                    if let bundleID = item.sourceApplication?.bundleIdentifier, let wantedSection = wanted[bundleID] {
                        itemSections[itemManager.identityKey(for: item)] = wantedSection
                    }
                }
            }
        }
        registerUndo(named: String(localized: "Import Profile"))
        profiles.append(LayoutProfile(
            name: name,
            itemSections: itemSections,
            applicationSections: applicationSections,
            knownApplications: shared.apps.map(\.id)
        ))
        save()
        logger.notice("Imported a shared layout profile with \(shared.apps.count, privacy: .public) applications")
    }

    /// Deletes the profile with the given name. Its script hooks go with it; undoing the
    /// deletion brings the profile back without them.
    func delete(named name: String) {
        registerUndo(named: String(localized: "Delete Profile"))
        profiles.removeAll { $0.name == name }
        if currentProfileName == name {
            currentProfileName = nil
        }
        save()
        appState?.settings.hotkeys.removeHotkey(for: .applyProfile(name))
        appState?.automation.scriptStore.removeProfileHooks(named: name)
    }

    /// The profile with the given name. An exact match wins, since names may differ only in
    /// case; without one, the name is matched without regard to case.
    func profile(named name: String) -> LayoutProfile? {
        profiles.first { $0.name == name }
            ?? profiles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Applies the profile with the given name, matched as in ``profile(named:)``.
    ///
    /// - Parameters:
    ///   - name: The profile's name.
    ///   - runsHooks: Whether the profile's script hooks run and the apply counts as a
    ///     profile-change event for script conditions. A change from a URL command, a Shortcut or
    ///     the Focus filter passes `false` (D-12, T-11-M5).
    func apply(named name: String, runsHooks: Bool = true) {
        guard let profile = self.profile(named: name) else {
            logger.warning("No layout profile named \(name, privacy: .private)")
            return
        }
        apply(profile, runsHooks: runsHooks)
    }

    /// A Focus filter turned on with a profile, or off (`nil`): applies the profile, and
    /// brings the one from before back when the Focus ends.
    ///
    /// A Shortcut's Set Focus action can switch a Focus and so this filter, so the apply is one
    /// from outside holzBar: it runs no hooks and is no profile-change event (D-12).
    func focusFilterChanged(to name: String?) {
        guard let target = focusBinding.profileToApply(requested: name, current: currentProfileName) else {
            return
        }
        apply(named: target, runsHooks: false)
    }

    /// Applies the given profile.
    ///
    /// With `runsHooks`, the profile's before hooks run first (at most five) and holzBar waits
    /// for them, each at most its time limit and all together at most a minute, then applies the
    /// profile whatever their outcome; its after hooks
    /// start once the items moved and are not awaited. A newer apply cancels one that still
    /// waits (D-13). Without hooks the profile is applied at once. The profile's name is never
    /// given to a script (D-06).
    func apply(_ profile: LayoutProfile, runsHooks: Bool = true) {
        guard let appState else {
            return
        }
        pendingApply?.cancel()
        pendingApply = nil
        guard runsHooks else {
            applyNow(profile, with: appState)
            return
        }
        let automation = appState.automation
        let before = ProfileHooks.scriptNames(
            for: profile.name,
            timing: .beforeApplying,
            in: automation.scriptStore.profileHooks
        )
        guard !before.isEmpty else {
            applyAndRunAfterHooks(profile, with: appState)
            return
        }
        logger.notice("Waiting for \(before.count, privacy: .public) script hooks before applying a profile")
        pendingApply = Task { [weak self] in
            await automation.runScripts(
                before,
                event: .profileWillApply,
                totalSeconds: ProfileHooks.beforeWaitSeconds
            )
            guard !Task.isCancelled, let self, let appState = self.appState else {
                return
            }
            pendingApply = nil
            // The profile may have been renamed or deleted while the hooks ran.
            guard let current = self.profile(named: profile.name) else {
                logger.notice("The layout profile is gone; it is not applied")
                return
            }
            applyAndRunAfterHooks(current, with: appState)
        }
    }

    /// Applies the profile, then starts its after hooks once the items moved, and tells the
    /// automation that a profile changed.
    private func applyAndRunAfterHooks(_ profile: LayoutProfile, with appState: AppState) {
        let moved = applyNow(profile, with: appState)
        let automation = appState.automation
        let after = ProfileHooks.scriptNames(
            for: profile.name,
            timing: .afterApplying,
            in: automation.scriptStore.profileHooks
        )
        if !after.isEmpty {
            Task {
                await moved?.value
                automation.startScripts(after, event: .profileDidApply)
            }
        }
        automation.profileDidChange()
    }

    /// Makes the profile the current one and moves the items.
    @discardableResult
    private func applyNow(_ profile: LayoutProfile, with appState: AppState) -> Task<Void, Never>? {
        currentProfileName = profile.name
        save()
        logger.notice("Applying layout profile \(profile.name, privacy: .private)")
        appState.snapshots.willApplyProfile()
        return applyLayout(of: profile)
    }

    /// Moves the items to the sections the layout names, without changing which profile is
    /// the current one. Items it does not know stay where they are.
    ///
    /// - Returns: The task that finishes the move, so a caller can wait for it; `nil` when
    ///   nothing was started.
    @discardableResult
    func applyLayout(of profile: LayoutProfile) -> Task<Void, Never>? {
        guard let appState else {
            return nil
        }
        if #available(macOS 27.0, *) {
            // Merged into the saved layout, so applications the profile does not know keep
            // their section. A profile saved before macOS 27 knows none and changes nothing.
            if profile.knownApplications == nil, profile.applicationSections.isEmpty {
                logger.notice("The layout has no macOS 27 part, so the current one stays")
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
            return Task {
                await appState.itemManager.cacheItemsRegardless()
            }
        }
        // Keys of earlier versions (`namespace:title`) match through the item identity.
        let itemManager = appState.itemManager
        var wanted = [String: Int]()
        for (key, index) in profile.itemSections {
            wanted[itemManager.storedIdentityKey(key)] = index
        }
        // The clock, the battery, Wi-Fi, Control Center and the sound control stay visible.
        if !Defaults.bool(forKey: .systemItemsMayHide) {
            wanted = PinnedSystemItems.keepingPinnedVisible(wanted)
        }
        var sections = [String: MenuBarSection.Name]()
        for (key, index) in wanted {
            if let section = MenuBarSection.Name(profileIndex: index) {
                sections[key] = section
            }
        }
        return Task {
            await itemManager.reconcileSections(wanted: sections, trigger: .profile)
        }
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
        appState?.automation.scriptStore.renameProfileHooks(from: profile.name, to: newName)
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
        let addedNames = Set(restored.map(\.name)).subtracting(profiles.map(\.name))
        // An undone or redone rename: the hooks follow the profile back.
        if removedNames.count == 1, addedNames.count == 1, let removed = removedNames.first, let added = addedNames.first {
            appState?.automation.scriptStore.renameProfileHooks(from: removed, to: added)
        }
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
            // Another hotkey may have taken the combination since, and the system
            // registers a combination only once per app.
            guard hotkeySettings.hotkey(using: keyCombination, except: .applyProfile(name)) == nil else {
                logger.info("Not restoring a profile's hotkey: another hotkey uses its combination")
                continue
            }
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
