//
//  RevealGate.swift
//  holzBar
//

import Foundation

/// Decides whether showing the hidden items needs the owner's authentication.
///
/// With the lock on, showing asks for Touch ID or the login password; a successful answer
/// opens a short grace period in which showing needs no new answer, so a hover does not ask
/// again and again. The lock is not a security boundary against someone who can change
/// holzBar's settings: turning it off asks too.
nonisolated struct RevealGate: Equatable, Sendable {
    /// How long a successful authentication lasts, in seconds.
    static let grace: TimeInterval = 60

    private(set) var unlockedUntil: Date?

    /// Whether showing now needs an authentication.
    func requiresAuthentication(isLockOn: Bool, now: Date) -> Bool {
        guard isLockOn else {
            return false
        }
        guard let unlockedUntil else {
            return true
        }
        return now >= unlockedUntil
    }

    /// Records a successful authentication.
    mutating func unlock(now: Date) {
        unlockedUntil = now.addingTimeInterval(Self.grace)
    }

    /// Ends the grace period, for example when the screen locks or the Mac sleeps.
    mutating func lock() {
        unlockedUntil = nil
    }
}
