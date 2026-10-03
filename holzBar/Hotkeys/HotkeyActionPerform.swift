//
//  HotkeyActionPerform.swift
//  holzBar
//

// What each hotkey action does. The actions and their stored names are in
// `holzBar/Core/HotkeyAction.swift`.
extension HotkeyAction {
    /// Performs the action.
    @MainActor
    func perform(appState: AppState) {
        switch self {
        case .toggleHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .toggleAlwaysHiddenSection:
            guard let section = appState.menuBarManager.section(withName: .alwaysHidden) else {
                return
            }
            section.toggle()
            // Prevent the section from automatically rehiding after mouse movement.
            if !section.isHidden {
                appState.menuBarManager.showOnHoverAllowed = false
            }
        case .showHiddenSectionTemporarily:
            // Shows the hidden section for the "Temporarily shown item delay", then
            // hides it again, whether or not auto-rehide is on.
            guard let section = appState.menuBarManager.section(withName: .hidden) else {
                return
            }
            section.show()
            appState.menuBarManager.showOnHoverAllowed = false
            let interval = appState.settings.advanced.tempShowInterval
            Task {
                try await Task.sleep(for: .seconds(interval))
                if !section.isHidden {
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
        }
    }
}
