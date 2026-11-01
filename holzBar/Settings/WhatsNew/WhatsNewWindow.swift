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
            WhatsNewView(settings: appState.settings.general) {
                appState.dismissWindow(.whatsNew)
            }
            .onWindowChange { window in
                model.observe(window)
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 560, height: 640)
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

    /// Follows the given window; a `nil` window stops following the previous one.
    func observe(_ window: NSWindow?) {
        observation = nil
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
