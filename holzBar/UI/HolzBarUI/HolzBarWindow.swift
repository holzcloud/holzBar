//
//  HolzBarWindow.swift
//  holzBar
//

import SwiftUI

// MARK: - HolzBarWindow

/// A custom scene representing one of holzBar's windows.
struct HolzBarWindow<Content: View>: Scene {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    /// The window's identifier.
    let id: HolzBarWindowIdentifier

    /// The app state, which opens and dismisses windows through this scene's actions.
    let appState: AppState

    /// The window's content view.
    let content: Content

    /// Creates a window with an identifier constant.
    ///
    /// - Parameters:
    ///   - id: A custom identifier constant.
    ///   - appState: The app state that receives the scene's window actions.
    ///   - content: The content view to display in the window.
    init(id: HolzBarWindowIdentifier, appState: AppState, @ViewBuilder content: () -> Content) {
        self.id = id
        self.appState = appState
        self.content = content()
    }

    var body: some Scene {
        windowScene.once {
            // Hand the real window actions to the app state, which opens and
            // dismisses holzBar's windows through them.
            appState.setWindowActions(open: openWindow, dismiss: dismissWindow)

            // SwiftUI waits to create the underlying NSWindow until the scene
            // is first presented. We may need a valid window reference before
            // that point, so we open the window and immediately dismiss it.
            //
            // - Note: Both actions are called during the same run loop cycle,
            //   so the window isn't actually opened. They run after the
            //   current scene update: on macOS 14, calling them while SwiftUI
            //   updates the scene is a fatal exclusive access conflict.
            Task {
                openWindow(id: id)
                dismissWindow(id: id)
            }
        }
    }

    @ViewBuilder
    private var windowContentView: some View {
        content.onWindowChange { window in
            window?.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    private var windowScene: some Scene {
        if #available(macOS 15.0, *) {
            return windowSceneModern
        } else {
            return windowSceneLegacy
        }
    }

    @available(macOS 15.0, *)
    private var windowSceneModern: some Scene {
        Window(id.titleKey, id: id.rawValue) {
            windowContentView
        }
        .defaultLaunchBehavior(.suppressed)
        // An empty set never matches, so SwiftUI never opens a holzBar window
        // for a holzbar:// URL; the app delegate handles them.
        .handlesExternalEvents(matching: [])
    }

    private var windowSceneLegacy: some Scene {
        Window(id.titleKey, id: id.rawValue) {
            windowContentView.once {
                // On launch, SwiftUI tries to show the first scene provided
                // to the app. Override this behavior and dismiss the window
                // the first time it is shown.
                dismissWindow(id: id)
            }
        }
        // An empty set never matches, so SwiftUI never opens a holzBar window
        // for a holzbar:// URL; the app delegate handles them.
        .handlesExternalEvents(matching: [])
    }
}

// MARK: - HolzBarWindowIdentifier

/// Custom identifier constants uses to create holzBar's windows.
enum HolzBarWindowIdentifier: String, Sendable, CustomStringConvertible {
    /// The identifier for holzBar's main settings window.
    case settings = "SettingsWindow"

    /// The identifier for holzBar's permissions window.
    case permissions = "PermissionsWindow"

    /// The non-localized title of the corresponding window.
    ///
    /// - Note: Use ``titleKey`` to get the localized title.
    var titleString: String {
        switch self {
        case .settings: "holzBar"
        case .permissions: "Permissions"
        }
    }

    /// The localized title of the corresponding window.
    ///
    /// - Note: Use ``titleString`` to get the non-localized title.
    var titleKey: LocalizedStringKey {
        LocalizedStringKey(titleString)
    }

    /// A textual representation of the identifier.
    var description: String {
        rawValue
    }
}

// MARK: - OpenWindowAction

extension OpenWindowAction {
    /// Opens the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of holzBar's windows.
    func callAsFunction(id: HolzBarWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}

// MARK: - DismissWindowAction

extension DismissWindowAction {
    /// Dismisses the corresponding window for the given identifier.
    ///
    /// - Parameter id: An identifier for one of holzBar's windows.
    func callAsFunction(id: HolzBarWindowIdentifier) {
        callAsFunction(id: id.rawValue)
    }
}
