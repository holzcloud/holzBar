//
//  PrivateFeatureGate.swift
//  holzBar
//

import Foundation

/// Whether a part of a module that uses a private macOS interface may run.
///
/// It is the start check and the self-switch-off of such a part. The part starts only when the
/// user's setting is on and loading the interface worked; it stops by itself when the interface
/// is missing, and for the rest of the session after it failed three calls in a row. Once
/// unavailable it stays so: only the user switching the part off and on again starts afresh.
/// The value does no loading and makes no call; whoever calls the interface records what
/// happened, and the module's view follows the state.
nonisolated struct PrivateFeatureGate: Equatable, Sendable {
    /// What loading the private interface gave.
    enum LoadResult: Equatable, Sendable {
        /// The framework loaded and every function the part needs was found.
        case loaded
        /// The framework is not on this Mac.
        case frameworkMissing
        /// The framework loaded but a function the part needs was not found.
        case symbolMissing
    }

    /// Why a part is unavailable.
    enum Reason: Equatable, Sendable {
        /// The user's setting is off.
        case switchedOff
        /// The framework is not on this Mac.
        case frameworkMissing
        /// A function the part needs is missing.
        case symbolMissing
        /// Three calls in a row failed.
        case failedRepeatedly
    }

    /// Whether the part may run.
    enum State: Equatable, Sendable {
        case available
        case unavailable(Reason)
    }

    /// The number of failed calls in a row that switches the part off: 3.
    static let failureLimit = 3

    /// Whether the interface should be loaded at all: only while the user's setting is on.
    static func shouldLoad(isEnabled: Bool) -> Bool {
        isEnabled
    }

    /// The state of the part.
    private(set) var state: State

    private var isEnabled: Bool
    private var failures = 0

    /// Starts from the user's setting and what loading the interface gave. With the setting off
    /// the load result is ignored, because nothing should have been loaded.
    init(isEnabled: Bool, load: LoadResult) {
        self.isEnabled = isEnabled
        state = Self.startState(isEnabled: isEnabled, load: load)
    }

    /// A Boolean value that indicates whether the part may run.
    var isAvailable: Bool {
        state == .available
    }

    /// Records a call that worked: the count of failures in a row starts again.
    mutating func recordSuccess() {
        guard state == .available else {
            return
        }
        failures = 0
    }

    /// Records a call that failed. The third in a row switches the part off for the session.
    mutating func recordFailure() {
        guard state == .available else {
            return
        }
        failures += 1
        if failures >= Self.failureLimit {
            state = .unavailable(.failedRepeatedly)
        }
    }

    /// Applies a change of the user's setting. A change starts afresh with an empty count;
    /// the same value again changes nothing, so a part that failed stays off until the user
    /// switches it off and on.
    mutating func setEnabled(_ newValue: Bool, load: LoadResult) {
        guard newValue != isEnabled else {
            return
        }
        isEnabled = newValue
        failures = 0
        state = Self.startState(isEnabled: newValue, load: load)
    }

    private static func startState(isEnabled: Bool, load: LoadResult) -> State {
        guard isEnabled else {
            return .unavailable(.switchedOff)
        }
        switch load {
        case .loaded: return .available
        case .frameworkMissing: return .unavailable(.frameworkMissing)
        case .symbolMissing: return .unavailable(.symbolMissing)
        }
    }
}
