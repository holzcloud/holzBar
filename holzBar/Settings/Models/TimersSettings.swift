//
//  TimersSettings.swift
//  holzBar
//

import Observation

/// Model for the Timers module's own setting: the sound that rings when a timer ends. It saves
/// itself in its `didSet`. The timers themselves are stored by the module, on this Mac only.
@MainActor
@Observable
final class TimersSettings {
    /// The sound that rings when a timer ends. On by default: a timer nobody hears is of
    /// little use.
    var finishSound = TimerFinishSound.glass {
        didSet {
            Defaults.set(finishSound.rawValue, forKey: .timersFinishSound)
        }
    }

    /// Loads the stored setting. A number no sound has reads as the default.
    func performSetup(with appState: AppState) {
        Defaults.ifPresent(key: .timersFinishSound) { (raw: Int) in
            finishSound = TimerFinishSound.stored(raw)
        }
    }
}
