//
//  TidyUpOffer.swift
//  holzBar
//

import AppKit

/// Offers the clean-up assistant once, a while after the first launch.
///
/// Only when the user has not arranged anything yet: no imported settings, no saved profile,
/// and at least six visible items of which some are proposed for hiding. The offer is a
/// plain question; "Not Now" and every answer end it, and the Menu Bar Layout pane has
/// "Tidy Up…" for later.
@MainActor
enum TidyUpOffer {
    /// How many visible items make an untidy bar.
    private static let minimumVisibleItems = 6

    static func offerIfFirstLaunch(appState: AppState) async {
        guard !Defaults.bool(forKey: .cleanUpOffered), !Defaults.bool(forKey: .hasImportedPreviousSettings) else {
            return
        }
        // The items are read some seconds after launch, and the first minute belongs to the user.
        try? await Task.sleep(for: .seconds(90))
        guard
            appState.isSetUp,
            appState.profiles.profiles.isEmpty,
            !appState.navigationState.isSettingsPresented,
            appState.itemManager.itemCache[.visible].filter({ !$0.isControlItem }).count >= minimumVisibleItems,
            !TidyUpEntry.proposals(from: appState).isEmpty
        else {
            return
        }
        Defaults.set(true, forKey: .cleanUpOffered)
        appState.activate(for: .settings)
        let alert = NSAlert()
        alert.messageText = String(localized: "Tidy up your menu bar?")
        alert.informativeText = String(localized: "holzBar can propose which items to hide, from what it knows of your apps. Nothing leaves your Mac, you decide, and you can undo it. You can do this any time in Menu Bar Layout.")
        alert.addButton(withTitle: String(localized: "Tidy Up…"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        appState.navigationState.settingsNavigationIdentifier = .menuBarLayout
        appState.navigationState.isTidyUpPresented = true
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }
}
