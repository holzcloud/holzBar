//
//  NotchHubSettings.swift
//  holzBar
//

import Observation

/// Model for the Notch hub's own settings: whether resting the pointer at the notch opens it,
/// and on which displays it may open. Each saves itself in its `didSet`; the last tab the hub
/// showed is kept by the hub's model, on this Mac only.
@MainActor
@Observable
final class NotchHubSettings {
    /// A Boolean value that indicates whether the hub opens when the pointer rests at the
    /// notch, or at the top centre of a display without one.
    var opensOnHover = true {
        didSet {
            Defaults.set(opensOnHover, forKey: .notchHubOpensOnHover)
        }
    }

    /// The displays the hub may open on.
    var displays: NotchHubDisplays = .all {
        didSet {
            Defaults.set(displays.rawValue, forKey: .notchHubDisplays)
        }
    }

    /// Loads the stored settings. A value of the displays that no case knows is ignored.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .notchHubOpensOnHover, assign: &opensOnHover)
        Defaults.ifPresent(key: .notchHubDisplays) { (rawValue: Int) in
            if let stored = NotchHubDisplays(rawValue: rawValue) {
                displays = stored
            }
        }
    }
}
