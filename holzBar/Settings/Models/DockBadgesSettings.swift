//
//  DockBadgesSettings.swift
//  holzBar
//

import Foundation
import Observation

/// Model for the Dock badges module's own settings: the apps whose Dock badge shows in the menu
/// bar, the switch that reads the badge and what an item shows while its count is zero. The choice
/// is stored as bundle identifiers, in the order chosen, and is exported with the settings, and so
/// is the zero mode; the switch uses a private macOS interface, so it is off by default and stored
/// on this Mac only. Each saves itself in its `didSet`.
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

    /// Whether the badge on the Dock icons of the chosen apps is read: the Read badge counts
    /// switch. It uses a private macOS interface, so it is off by default and stored on this Mac
    /// only. A change makes the module start its read afresh.
    var readsCounts = false {
        didSet {
            guard readsCounts != oldValue else {
                return
            }
            Defaults.set(readsCounts, forKey: .dockBadgesReadsCounts)
            appState?.dockBadges.readsCountsDidChange()
        }
    }

    /// What an item shows while its count is zero: the one setting for every item. Dim by default.
    /// The module follows it through the badge inputs it observes.
    var zeroMode = DockBadgeZeroMode.dim {
        didSet {
            guard zeroMode != oldValue else {
                return
            }
            Defaults.set(zeroMode.rawValue, forKey: .dockBadgeZeroMode)
        }
    }

    @ObservationIgnored private weak var appState: AppState?

    /// Whether the app is chosen.
    func isChosen(_ bundleID: String) -> Bool {
        apps.contains(bundleID)
    }

    /// Chooses an app or takes it out of the choice.
    func setChosen(_ bundleID: String, _ isChosen: Bool) {
        apps = DockBadgeApps.setting(bundleID, chosen: isChosen, in: apps)
    }

    /// Loads the stored switch, choice and zero mode; a stored list that holds anything but valid,
    /// unique bundle identifiers is cut down to those.
    func performSetup(with appState: AppState) {
        self.appState = appState
        Defaults.ifPresent(key: .dockBadgesReadsCounts, assign: &readsCounts)
        Defaults.ifPresent(key: .dockBadgeApps) { (stored: [String]) in
            apps = DockBadgeApps.sanitized(stored)
        }
        // Anything stored that is not one of the two modes reads as the default.
        Defaults.ifPresent(key: .dockBadgeZeroMode) { (stored: Int) in
            zeroMode = DockBadgeZeroMode.stored(stored)
        }
    }
}
