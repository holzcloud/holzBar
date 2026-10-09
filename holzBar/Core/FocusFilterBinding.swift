//
//  FocusFilterBinding.swift
//  holzBar
//

import Foundation

/// Remembers what a Focus filter changed, so the layout comes back when the Focus ends.
///
/// The system calls the filter with a profile when a Focus turns on, and with none when it
/// turns off. A profile that the user applied meanwhile is left alone.
nonisolated struct FocusFilterBinding: Equatable, Sendable {
    /// The profile the filter applied, while its Focus is on.
    private(set) var applied: String?
    /// The profile that was active before the filter applied its own.
    private(set) var previous: String?

    /// Records the call of the filter and says which profile to apply, if any.
    ///
    /// - Parameters:
    ///   - requested: The profile of the filter, or `nil` when its Focus turned off.
    ///   - current: The profile that is applied now.
    /// - Returns: The name of the profile to apply, or `nil` for none.
    mutating func profileToApply(requested: String?, current: String?) -> String? {
        if let requested {
            // Another Focus replacing this one keeps the profile from before the first.
            if applied == nil {
                previous = current
            }
            applied = requested
            return requested == current ? nil : requested
        }
        defer {
            applied = nil
            previous = nil
        }
        guard let applied, applied == current, let previous, previous != current else {
            return nil
        }
        return previous
    }
}
