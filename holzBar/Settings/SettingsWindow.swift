//
//  SettingsWindow.swift
//  holzBar
//

import SwiftUI

// MARK: - SettingsWindow

struct SettingsWindow: Scene {
    let appState: AppState
    @State private var model = SettingsWindowModel()

    var body: some Scene {
        HolzBarWindow(id: .settings, appState: appState) {
            SettingsView(navigationState: appState.navigationState)
                .onWindowChange { window in
                    model.observe(window, navigationState: appState.navigationState)
                }
                .frame(minWidth: 825, maxWidth: 1150, minHeight: 500, maxHeight: 750)
        }
        .commandsRemoved()
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 625)
        .environment(appState)
    }
}

// MARK: - SettingsWindowModel

@MainActor
@Observable
private final class SettingsWindowModel {
    /// Observers of the window's visibility and toolbar.
    @ObservationIgnored private var observations = [NSKeyValueObservation]()

    /// Follows the given window: its visibility becomes the navigation state's
    /// `isSettingsPresented`, and its toolbar keeps icons only.
    func observe(_ window: NSWindow?, navigationState: AppNavigationState) {
        observations.removeAll()
        guard let window else {
            return
        }
        navigationState.settingsWindow = window

        observations.append(window.observe(\.isVisible, options: [.initial, .new]) { [weak navigationState] window, _ in
            Task { @MainActor in
                let isVisible = window.isVisible
                if let navigationState, navigationState.isSettingsPresented != isVisible {
                    navigationState.isSettingsPresented = isVisible
                }
            }
        })

        if #available(macOS 15.0, *) {
            // TODO: Switch to the SwiftUI equivalent once we're targeting macOS 15.
            //
            // Performing availability checks in @SceneBuilder is annoyingly difficult,
            // so we're cheating for now and doing it here.
            //
            // SwiftUI seems to create a new toolbar each time the window is opened, so
            // we're using KVO to make sure the values stay set.
            //
            // - FOR FUTURE REFERENCE: Add `.windowToolbarLabelStyle(fixed: .iconOnly)`
            //   to the body of `SettingsWindow` and remove these observers.
            let fixToolbar: @Sendable (NSWindow) -> Void = { window in
                Task { @MainActor in
                    guard let toolbar = window.toolbar else {
                        return
                    }
                    if toolbar.displayMode != .iconOnly {
                        toolbar.displayMode = .iconOnly
                    }
                    if toolbar.allowsDisplayModeCustomization {
                        toolbar.allowsDisplayModeCustomization = false
                    }
                }
            }
            observations.append(window.observe(\.toolbar, options: [.initial, .new]) { window, _ in
                fixToolbar(window)
            })
            observations.append(window.observe(\.toolbar?.displayMode, options: [.new]) { window, _ in
                fixToolbar(window)
            })
            observations.append(window.observe(\.toolbar?.allowsDisplayModeCustomization, options: [.new]) { window, _ in
                fixToolbar(window)
            })
        }
    }
}
