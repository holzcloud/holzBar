//
//  AppNavigationState.swift
//  holzBar
//

import AppKit
import Observation

/// The model for app-wide navigation.
@MainActor
@Observable
final class AppNavigationState {
    var isAppFrontmost = false
    var isSettingsPresented = false
    var isShelfPresented = false
    var isSearchPresented = false
    /// Whether the panel of a menu bar item group is shown.
    var isItemGroupPanelPresented = false
    var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general

    /// The Settings window, while it exists. Its visibility is ``isSettingsPresented``.
    @ObservationIgnored weak var settingsWindow: NSWindow?
}
