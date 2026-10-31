//
//  DisplayControlsSettings.swift
//  holzBar
//

import Observation

/// Model for the Display controls module's own setting: whether brightness sliders show. It is
/// the switch for the part of the module that uses a private macOS interface; with it off, the
/// interface is never loaded. It saves itself in its `didSet`.
@MainActor
@Observable
final class DisplayControlsSettings {
    /// A Boolean value that indicates whether the module shows brightness sliders. On by default.
    var showsBrightness = true {
        didSet {
            Defaults.set(showsBrightness, forKey: .displayControlsBrightness)
        }
    }

    /// Loads the stored setting.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .displayControlsBrightness, assign: &showsBrightness)
    }
}
