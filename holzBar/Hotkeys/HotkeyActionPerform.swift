//
//  HotkeyActionPerform.swift
//  holzBar
//

// What each hotkey does. The actions and their stored names are in
// `holzBar/Core/HotkeyAction.swift`, the targets in `holzBar/Core/HotkeyTarget.swift`.

extension HotkeyTarget {
    /// Performs what the hotkey is for.
    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .action(let action):
            action.perform(appState: appState)
        case .applyProfile(let profileID):
            // No question, unlike `holzbar://profile/<name>`: the user gave the profile
            // this hotkey.
            appState.profiles.apply(profileID: profileID, byUser: true)
        case .openItem(let key):
            appState.itemManager.openItem(withIdentityKey: key)
        }
    }
}

extension HotkeyAction {
    /// Lets the holzBar Shelf take keys when a hotkey opens it, so the arrows, Return and
    /// Escape work in it.
    @MainActor
    private func prepareShelfForKeyboard(opening section: MenuBarSection, appState: AppState) {
        if appState.settings.general.usesShelf, section.isHidden {
            appState.menuBarManager.shelfPanel.acceptsKeyboard = true
        }
    }

    /// Performs the action.
    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            prepareShelfForKeyboard(opening: section, appState: appState)
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            prepareShelfForKeyboard(opening: section, appState: appState)
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .showHiddenSectionTemporarily:
            // Shows the hidden section for the "Temporarily shown item delay", then
            // hides it again, whether or not auto-rehide is on. Another press starts the
            // delay again.
            let menuBarManager = appState.menuBarManager
            guard let section = menuBarManager.section(withName: .hidden) else {
                return
            }
            menuBarManager.temporaryShowTask?.cancel()
            section.show()
            menuBarManager.showOnHoverAllowed = false
            let interval = appState.settings.advanced.tempShowInterval
            menuBarManager.temporaryShowTask = Task {
                try? await Task.sleep(for: .seconds(interval))
                if !Task.isCancelled, !section.isHidden {
                    section.hide()
                }
            }
        case .searchMenuBarItems:
            appState.menuBarManager.searchPanel.toggle()
        case .enableShelf:
            appState.settings.general.useShelf.toggle()
        case .toggleApplicationMenus:
            appState.menuBarManager.toggleApplicationMenus()
        case .toggleAutoRehide:
            appState.settings.general.autoRehide.toggle()
        case .toggleZenMode:
            appState.menuBarManager.toggleZenMode()
        case .showItemHints:
            appState.menuBarManager.itemHintsPanel.toggle()
        }
    }
}
