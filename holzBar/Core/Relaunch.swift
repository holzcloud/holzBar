//
//  Relaunch.swift
//  holzBar
//

import Foundation

/// The hand-off between an instance of holzBar that relaunches itself and the new instance.
///
/// The old instance starts the new one with its process identifier in the environment, then
/// quits. The new instance waits until the old one has quit, for at most ``waitTimeout``,
/// before it sets up, so it never registers hotkeys or status items while the old instance
/// still holds them.
enum Relaunch {
    /// The environment variable that names the previous instance's process identifier.
    static let previousInstanceKey = "HOLZBAR_PREVIOUS_INSTANCE"

    /// How long the new instance waits for the previous one to quit.
    static let waitTimeout: Duration = .seconds(10)

    /// The environment that hands the previous instance over to the new one.
    ///
    /// - Parameter previousPID: The process identifier of the instance that relaunches.
    static func environment(previousPID: pid_t) -> [String: String] {
        [previousInstanceKey: String(previousPID)]
    }

    /// The previous instance's process identifier named in `environment`.
    ///
    /// - Parameter environment: The new instance's environment.
    /// - Returns: The process identifier, or `nil` when the environment names none or a
    ///   value that is not a positive 32-bit integer.
    static func previousPID(in environment: [String: String]) -> pid_t? {
        guard
            let value = environment[previousInstanceKey],
            let pid = Int32(value),
            pid > 0
        else {
            return nil
        }
        return pid
    }
}
