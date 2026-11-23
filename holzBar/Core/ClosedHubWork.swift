//
//  ClosedHubWork.swift
//  holzBar
//

import Foundation

/// The one rule that says which observers, listeners, taps and monitors exist while the Notch hub
/// is closed (Phase 96, D-05, D-15, HUB-10: off means no cost).
///
/// Every piece of work this phase adds to the closed hub is listed here as an ``Observer`` with the
/// switches that own it. The owners (the Indicators runtime, the gestures) start exactly what
/// ``observers(_:)`` returns for the switches as they are now and nothing else, so "does this exist
/// right now" has one tested answer. With every switch off, or the hub off, the answer is nothing.
/// Later plans append their cases (notifications, countdown wakes, the media-key tap, the brightness
/// keys) and the switches that own them.
nonisolated enum ClosedHubWork {
    /// The state of the switches that decide what exists. A value is the user's setting, or for the
    /// hub and its modules whether they are switched on.
    nonisolated struct Switches: Equatable, Sendable {
        /// The Notch hub is on.
        var hubOn = false
        /// The Indicators module is on.
        var indicatorsOn = false
        /// Indicators: Input source.
        var inputSourceOn = false
        /// Indicators: Volume and brightness.
        var volumeBrightnessOn = false
        /// Notch hub: Gestures.
        var gesturesOn = false
        /// The Calendar module is on.
        var calendarOn = false
        /// Calendar: the countdown before a meeting is not Off.
        var countdownOn = false
        /// Calendar access has been granted.
        var calendarAccess = false
    }

    /// A piece of work that runs while the hub is closed.
    nonisolated enum Observer: String, CaseIterable, Sendable {
        /// The system's input source notifications.
        case inputSource
        /// The observation of app activations that tells a user's switch from the system's.
        case appActivation
        /// The listener for the default output's volume and mute.
        case volumeListener
        /// The listen-only scroll monitor of the gestures.
        case scrollMonitor
        /// The meeting countdown of the Calendar module: the next meeting's start time held in
        /// memory and up to two one-shot wakes (never a title, never polling, D-24).
        case countdown
    }

    /// The observers that exist for these switches: none unless the hub is on.
    static func observers(_ switches: Switches) -> Set<Observer> {
        guard switches.hubOn else {
            return []
        }
        var result = Set<Observer>()
        if switches.indicatorsOn {
            if switches.inputSourceOn {
                result.insert(.inputSource)
                result.insert(.appActivation)
            }
            if switches.volumeBrightnessOn {
                result.insert(.volumeListener)
            }
        }
        if switches.gesturesOn {
            result.insert(.scrollMonitor)
        }
        if switches.calendarOn, switches.countdownOn, switches.calendarAccess {
            result.insert(.countdown)
        }
        return result
    }
}
