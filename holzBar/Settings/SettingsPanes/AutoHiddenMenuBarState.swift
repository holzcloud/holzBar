//
//  AutoHiddenMenuBarState.swift
//  holzBar
//

import AppKit
import SwiftUI

/// The one empty state of the panes that cannot work while macOS hides the menu bar by itself:
/// what is the matter, and the way to change it (D-26).
struct AutoHiddenMenuBarState: View {
    enum Kind {
        /// Layout and Profiles & History: items cannot be arranged.
        case arrange
        /// Appearance: the look cannot be changed.
        case appearance
    }

    let kind: Kind

    var body: some View {
        EmptyState(
            systemImage: "menubar.rectangle",
            title: Text("The menu bar hides automatically"),
            message: kind == .arrange
                ? Text("holzBar cannot arrange items in a menu bar that hides automatically.")
                : Text("holzBar cannot change the look of a menu bar that hides automatically."),
            actionTitle: "Open System Settings",
            action: openMenuBarSettings
        )
    }

    /// Opens the menu bar settings of System Settings, or System Settings itself when that link
    /// does not open; both are local.
    private func openMenuBarSettings() {
        if
            let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"),
            NSWorkspace.shared.open(url)
        {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
