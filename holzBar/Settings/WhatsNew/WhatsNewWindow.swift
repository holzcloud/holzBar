//
//  WhatsNewWindow.swift
//  holzBar
//

import SwiftUI

// MARK: - WhatsNewWindow

/// The scene of the What's New window: the release notes of the installed version and of the
/// versions before it.
struct WhatsNewWindow: Scene {
    let appState: AppState
    @State private var model = WhatsNewWindowModel()

    var body: some Scene {
        HolzBarWindow(id: .whatsNew, appState: appState) {
            // The first click on a tab or on Done acts at once, although the window opens
            // without activating holzBar.
            WhatsNewFirstMouseHost(idealSize: CGSize(width: WhatsNewView.width, height: WhatsNewView.heights.ideal)) {
                WhatsNewView(settings: appState.settings.general) {
                    appState.dismissWindow(.whatsNew)
                }
            }
            .ignoresSafeArea()
            .frame(width: WhatsNewView.width)
            .frame(minHeight: WhatsNewView.heights.min, idealHeight: WhatsNewView.heights.ideal, maxHeight: WhatsNewView.heights.max)
            .onWindowChange { window in
                model.observe(window, navigationState: appState.navigationState)
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 520)
        .environment(appState)
    }
}

// MARK: - WhatsNewWindowModel

/// Brings the window to the front once it is really shown, without activating the app.
///
/// An automatic open after an update must not take the keyboard from the app the user is
/// working in, so nothing here activates holzBar; `orderFrontRegardless()` only puts the
/// window above the other windows. The window is observed instead of ordered in at once,
/// because the scene opens and dismisses the window in one cycle at launch to create it.
@MainActor
private final class WhatsNewWindowModel {
    /// The observer of the window's visibility.
    private var observation: NSKeyValueObservation?

    /// Whether the window has been centred already.
    private var isCentered = false

    /// The navigation state that learns whether the window is shown.
    private weak var navigationState: AppNavigationState?

    /// Follows the given window; a `nil` window stops following the previous one.
    func observe(_ window: NSWindow?, navigationState: AppNavigationState) {
        observation = nil
        self.navigationState = navigationState
        guard let window else {
            return
        }
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        observation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] window, _ in
            Task { @MainActor in
                self?.windowVisibilityChanged(window)
            }
        }
    }

    private func windowVisibilityChanged(_ window: NSWindow) {
        // Others can tell whether the window is on screen.
        if navigationState?.isWhatsNewPresented != window.isVisible {
            navigationState?.isWhatsNewPresented = window.isVisible
        }
        guard window.isVisible else {
            return
        }
        if !isCentered {
            isCentered = true
            window.center()
        }
        window.orderFrontRegardless()
    }
}
