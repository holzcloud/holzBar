//
//  TimerFinishSound.swift
//  holzBar
//

import Foundation

/// The sound that rings when a timer ends: none, or one of five system sounds.
///
/// The raw values are stored in the settings; new cases go at the end.
nonisolated enum TimerFinishSound: Int, CaseIterable, Sendable {
    case none = 0
    case glass = 1
    case hero = 2
    case ping = 3
    case submarine = 4
    case tink = 5

    /// The name of the system sound in `/System/Library/Sounds`, or `nil` for none.
    var systemName: String? {
        switch self {
        case .none: nil
        case .glass: "Glass"
        case .hero: "Hero"
        case .ping: "Ping"
        case .submarine: "Submarine"
        case .tink: "Tink"
        }
    }

    /// The choice a stored number stands for. A number no case has (the settings can hold
    /// anything) reads as Glass, the default.
    static func stored(_ raw: Int) -> TimerFinishSound {
        TimerFinishSound(rawValue: raw) ?? .glass
    }
}
