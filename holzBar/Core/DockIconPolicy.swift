//
//  DockIconPolicy.swift
//  holzBar
//

import Foundation

/// Whether holzBar shows a Dock icon when it comes to the front.
///
/// holzBar used to switch to the regular activation policy — with a Dock icon — for
/// Settings, the search and hiding application menus, so a Dock icon appeared while items
/// were shown (jordanbaird/Ice#906, Thaw #1197). Settings and the search work without one.
/// macOS hides another app's menus only for an active regular app, so hiding application
/// menus needs the Dock icon; with "Keep the Dock icon hidden" (on by default) they are not
/// hidden instead.
nonisolated enum DockIconPolicy {
    /// Why holzBar comes to the front.
    nonisolated enum ActivationReason: Equatable {
        /// The Settings window opens.
        case settings
        /// The search panel opens.
        case search
        /// The permissions window opens at the first launch.
        case permissions
        /// Shown items reach the application menus, which holzBar hides by coming to the front.
        case hideApplicationMenus
        /// The user hides the application menus with the hotkey or URL command.
        case toggleApplicationMenus
    }

    /// An activation policy, matching `NSApplication.ActivationPolicy`.
    nonisolated enum ActivationPolicyChoice: Equatable {
        /// With a Dock icon and a menu bar of holzBar's own.
        case regular
        /// Without a Dock icon.
        case accessory
    }

    /// The activation policy for the given reason, or `nil` when holzBar should not come to
    /// the front at all.
    static func policy(for reason: ActivationReason, keepsDockIconHidden: Bool) -> ActivationPolicyChoice? {
        switch reason {
        case .settings, .search:
            .accessory
        case .permissions:
            // The first window of a fresh install, which must be found in the Dock and in
            // the app switcher until the permissions are granted.
            .regular
        case .hideApplicationMenus:
            keepsDockIconHidden ? nil : .regular
        case .toggleApplicationMenus:
            // The user asked for it, which the setting does not overrule.
            .regular
        }
    }
}
