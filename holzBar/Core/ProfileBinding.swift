//
//  ProfileBinding.swift
//  holzBar
//

import Foundation

/// Which layout profile to apply when a display is connected or the Space changes
/// (THAW-11).
///
/// A profile can be bound to a display (by the display's UUID) and to a Space (by the
/// Space's UUID). Connecting a bound display, or switching to a bound Space, applies the
/// profile; when both match, the Space wins, because it is the more specific choice. The
/// profile that is already applied is never applied again, so a flickering display or a
/// Space switch back and forth does not move items in a loop.
nonisolated enum ProfileBinding {
    /// The bindings of one profile.
    nonisolated struct Profile: Equatable, Sendable {
        /// The profile's name.
        var name: String
        /// The UUID of the display the profile is bound to.
        var displayUUID: String?
        /// The UUID of the Space the profile is bound to.
        var spaceUUID: String?
    }

    /// What happened.
    nonisolated enum Event: Equatable, Sendable {
        /// Displays were connected (only the new ones), while the given Space is active.
        case displaysConnected(Set<String>, activeSpace: String?)
        /// The given Space became active.
        case spaceChanged(String)
    }

    /// The name of the profile to apply after the event, or `nil` for none.
    ///
    /// - Parameters:
    ///   - profiles: The saved profiles with their bindings, in their order.
    ///   - event: What happened.
    ///   - currentProfile: The name of the profile that was applied last.
    static func profileToApply(profiles: [Profile], event: Event, currentProfile: String?) -> String? {
        let match: Profile?
        switch event {
        case .displaysConnected(let displays, let activeSpace):
            guard !displays.isEmpty else {
                return nil
            }
            let spaceMatch = activeSpace.flatMap { space in
                profiles.first { $0.spaceUUID == space }
            }
            let displayMatch = profiles.first { profile in
                profile.displayUUID.map { displays.contains($0) } ?? false
            }
            // A Space-bound profile only wins over a display that is bound as well.
            match = displayMatch == nil ? nil : (spaceMatch ?? displayMatch)
        case .spaceChanged(let space):
            match = profiles.first { $0.spaceUUID == space }
        }
        guard let name = match?.name, name != currentProfile else {
            return nil
        }
        return name
    }

    /// The displays in `current` that were not in `previous`.
    static func newlyConnected(previous: Set<String>, current: Set<String>) -> Set<String> {
        current.subtracting(previous)
    }
}
