//
//  DisplayControlsSettings.swift
//  holzBar
//

import Observation

/// Model for the Display controls module's own settings: whether brightness sliders show, and
/// whether external monitors are controlled over DDC/CI. Each is the switch for a part of the
/// module that uses a private macOS interface; with it off, that interface is never loaded.
/// External monitors is off by default and stored on this Mac only. It saves itself in its
/// `didSet`.
@MainActor
@Observable
final class DisplayControlsSettings {
    /// A Boolean value that indicates whether the module shows brightness sliders. On by default.
    var showsBrightness = true {
        didSet {
            Defaults.set(showsBrightness, forKey: .displayControlsBrightness)
        }
    }

    /// A Boolean value that indicates whether the module controls external monitors over DDC/CI.
    /// Off by default.
    var showsExternalMonitors = false {
        didSet {
            Defaults.set(showsExternalMonitors, forKey: .displayControlsExternalMonitors)
        }
    }

    /// Loads the stored settings.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .displayControlsBrightness, assign: &showsBrightness)
        Defaults.ifPresent(key: .displayControlsExternalMonitors, assign: &showsExternalMonitors)
    }
}
