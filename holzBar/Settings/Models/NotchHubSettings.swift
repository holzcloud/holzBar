//
//  NotchHubSettings.swift
//  holzBar
//

import Observation

/// Model for the Notch hub's own settings: whether it opens on what is active, whether resting
/// the pointer at the notch opens it, on which displays it may open, and how it treats the
/// camera cutout. Each saves itself in its
/// `didSet`; the last tab the hub showed is kept by the hub's model, on this Mac only.
@MainActor
@Observable
final class NotchHubSettings {
    /// A Boolean value that indicates whether the hub opens on what is active (a meeting soon, a
    /// live activity, music) instead of on the module the user chose last. The hub reads it once,
    /// when it opens.
    var showsActiveFirst = true {
        didSet {
            Defaults.set(showsActiveFirst, forKey: .notchHubShowsActiveFirst)
        }
    }

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

    /// How the hub treats the camera cutout of a display: as detected, or as the user chose where
    /// the detection is wrong. Stored on this Mac only.
    var cutoutOverride: DisplayCutoutOverride = .automatic {
        didSet {
            Defaults.set(cutoutOverride.rawValue, forKey: .notchHubCutout)
        }
    }

    /// Loads the stored settings. A value of the displays or the cutout that no case knows is
    /// ignored.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .notchHubShowsActiveFirst, assign: &showsActiveFirst)
        Defaults.ifPresent(key: .notchHubOpensOnHover, assign: &opensOnHover)
        Defaults.ifPresent(key: .notchHubDisplays) { (rawValue: Int) in
            if let stored = NotchHubDisplays(rawValue: rawValue) {
                displays = stored
            }
        }
        Defaults.ifPresent(key: .notchHubCutout) { (rawValue: Int) in
            if let stored = DisplayCutoutOverride(rawValue: rawValue) {
                cutoutOverride = stored
            }
        }
    }
}
