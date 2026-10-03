//
//  HolzBarIntents.swift
//  holzBar
//

import AppIntents

// Shortcuts actions (App Intents). They run the same code as holzBar's hotkeys and menu,
// inside holzBar, without a script, a command line tool or a new permission. An action
// only does what the user put into a shortcut, so nothing here asks first (unlike
// `holzbar://profile/<name>`, which any app can open).

// MARK: - Errors

/// Why a Shortcuts action could not run.
nonisolated enum HolzBarIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// holzBar has not finished starting, or waits for its permissions.
    case notReady

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            "holzBar is not ready yet. Open holzBar and grant its permissions first."
        }
    }
}

/// The app's state for an action, or an error when holzBar is not ready.
@MainActor
private func intentAppState() throws -> AppState {
    guard let appState = AppState.current else {
        throw HolzBarIntentError.notReady
    }
    return appState
}

// MARK: - Zen Mode

/// Turns Zen mode on or off.
nonisolated struct ToggleZenModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Zen Mode"

    @MainActor
    func perform() async throws -> some IntentResult {
        try intentAppState().menuBarManager.toggleZenMode()
        return .result()
    }
}

// MARK: - App Shortcuts

/// The actions Shortcuts and Spotlight offer without any setup.
nonisolated struct HolzBarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleZenModeIntent(),
            phrases: ["Toggle Zen mode in \(.applicationName)"],
            shortTitle: "Zen Mode",
            systemImageName: "moon"
        )
    }
}
