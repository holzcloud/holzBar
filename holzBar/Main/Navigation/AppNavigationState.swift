//
//  AppNavigationState.swift
//  holzBar
//

import Combine

/// The model for app-wide navigation.
@MainActor
final class AppNavigationState: ObservableObject {
    @Published var isAppFrontmost = false
    @Published var isSettingsPresented = false
    @Published var isShelfPresented = false
    @Published var isSearchPresented = false
    /// Whether the panel of a menu bar item group is shown.
    @Published var isItemGroupPanelPresented = false
    @Published var settingsNavigationIdentifier: SettingsNavigationIdentifier = .general
}
