//
//  FocusChangeRehide.swift
//  holzBar
//

import Foundation

/// When the `focusedApp` rehide strategy hides the hidden section.
///
/// holzBar's own activation (to hide the application menus, or for Settings) and the
/// return to the application it came from are no focus change: counting them hid the
/// section right after it was shown.
nonisolated struct FocusChangeRehide: Equatable {
    /// The process identifier of the last frontmost application other than holzBar.
    private(set) var lastPID: pid_t?

    /// Creates the filter without a last application.
    init() {}

    /// Creates the filter with the frontmost application at launch.
    ///
    /// - Parameters:
    ///   - frontmostPID: The process identifier of the frontmost application, if any.
    ///   - ownPID: holzBar's process identifier.
    init(frontmostPID: pid_t?, ownPID: pid_t) {
        lastPID = frontmostPID == ownPID ? nil : frontmostPID
    }

    /// Whether the strategy applies: it is picked and "Automatically rehide" is on,
    /// as for the smart and timed strategies.
    ///
    /// - Parameters:
    ///   - autoRehide: The "Automatically rehide" setting.
    ///   - rehidesOnFocusChange: Whether the rehide strategy is `focusedApp`.
    static func applies(autoRehide: Bool, rehidesOnFocusChange: Bool) -> Bool {
        autoRehide && rehidesOnFocusChange
    }

    /// Records a new frontmost application and returns whether the focus changed.
    ///
    /// - Parameters:
    ///   - pid: The process identifier of the new frontmost application.
    ///   - ownPID: holzBar's process identifier.
    mutating func isFocusChange(to pid: pid_t, ownPID: pid_t) -> Bool {
        guard pid != ownPID, pid != lastPID else {
            return false
        }
        lastPID = pid
        return true
    }
}
