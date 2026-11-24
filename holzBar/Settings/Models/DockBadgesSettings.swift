//
//  DockBadgesSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the Dock badges module's own settings: the apps whose Dock badge shows in the menu
/// bar. The choice is stored as bundle identifiers, in the order chosen, and is exported with the
/// settings; it saves itself in its `didSet`.
@MainActor
@Observable
final class DockBadgesSettings {
    /// The bundle identifiers of the chosen apps, at most ``DockBadgeApps/maximumCount``. Change
    /// it through ``setChosen(_:_:)``.
    private(set) var apps = [String]() {
        didSet {
            guard apps != oldValue else {
                return
            }
            Defaults.set(apps, forKey: .dockBadgeApps)
        }
    }

    /// Whether the app is chosen.
    func isChosen(_ bundleID: String) -> Bool {
        apps.contains(bundleID)
    }

    /// Chooses an app or takes it out of the choice.
    func setChosen(_ bundleID: String, _ isChosen: Bool) {
        apps = DockBadgeApps.setting(bundleID, chosen: isChosen, in: apps)
    }

    /// Loads the stored choice; a stored list that holds anything but valid, unique bundle
    /// identifiers is cut down to those.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .dockBadgeApps) { (stored: [String]) in
            apps = DockBadgeApps.sanitized(stored)
        }
    }
}
