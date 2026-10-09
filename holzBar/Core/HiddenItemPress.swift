//
//  HiddenItemPress.swift
//  holzBar
//

import Foundation

/// Whether an app took the Accessibility press that opens a hidden item without showing it.
///
/// A status item's press blocks while the menu it opened is up, so a press that opened a
/// menu does not come back within ``timeout``: Accessibility gives up waiting with
/// "cannot complete". Giving up does not cancel the press; the app still performs it. So a
/// "cannot complete" that came back only after about the whole timeout counts as taken.
/// One that came back at once, and every other error, does not.
///
/// The timeout is not raised instead: the press blocks for as long as the menu stays open.
nonisolated enum HiddenItemPress {
    /// How long each call to the app may take.
    static let timeout = Duration.milliseconds(250)

    /// What the press returned, without the Accessibility types.
    enum Result: Equatable, Sendable {
        /// The app performed the press.
        case success
        /// The app did not answer in time (`AXError.cannotComplete`).
        case cannotComplete
        /// Any other error, or no element to press.
        case failed
    }

    /// Whether the app took the press.
    ///
    /// - Parameters:
    ///   - result: What the press returned.
    ///   - elapsed: How long the press took.
    ///   - timeout: The messaging timeout the press ran with.
    static func isTaken(_ result: Result, elapsed: Duration, timeout: Duration = timeout) -> Bool {
        switch result {
        case .success:
            true
        case .cannotComplete:
            isTimedOut(elapsed: elapsed, timeout: timeout)
        case .failed:
            false
        }
    }

    /// Whether a press that took the given time ran into the timeout; a little early counts,
    /// as the timeout is not exact.
    static func isTimedOut(elapsed: Duration, timeout: Duration = timeout) -> Bool {
        elapsed >= timeout * 0.8
    }
}
