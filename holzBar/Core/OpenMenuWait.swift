//
//  OpenMenuWait.swift
//  holzBar
//

import Foundation

/// Which windows keep an automatic hide of the hidden sections waiting, as an item's open menu,
/// and for how long.
///
/// No automatic hide pulls a hidden item away under its open menu (D-04, D-05). A window counts
/// only when it looks like the open menu of an item in a shown section (`InterfaceWindowRule`)
/// and appeared after the reveal: a window that was on screen when the sections were shown (a
/// notch or HUD utility's status-level panel, a pinned widget, a lasting Control Center window)
/// is no menu the user opened from the shown items and would keep the section open forever.
/// A window that appeared later still keeps a hide waiting for ``longestWait`` at most; then it
/// no longer counts for the rest of the reveal, so nothing keeps a section open for good.
nonisolated struct OpenMenuWait: Equatable, Sendable {
    /// How long one window may keep a hide waiting.
    static let longestWait: TimeInterval = 60

    /// The windows on screen when the reveal started; they never count.
    private(set) var windowsBeforeReveal: Set<UInt32> = []

    /// Since when each counting window has kept a hide waiting (system uptime in seconds).
    private var waitingSince: [UInt32: TimeInterval] = [:]

    /// The windows that kept a hide waiting for ``longestWait``; they no longer count during
    /// this reveal.
    private(set) var givenUp: Set<UInt32> = []

    /// What one hide check decided.
    struct Decision: Equatable, Sendable {
        /// Whether the hide waits.
        let waits: Bool
        /// The windows that reached ``longestWait`` at this check, to log once.
        let newlyGivenUp: Set<UInt32>
    }

    /// A reveal starts: the windows on screen now never count as its open menu, and nothing
    /// of an earlier reveal is kept.
    mutating func revealStarted(windowsOnScreen: Set<UInt32>) {
        windowsBeforeReveal = windowsOnScreen
        waitingSince = [:]
        givenUp = []
    }

    /// Whether a hide waits now.
    ///
    /// - Parameters:
    ///   - openMenus: The windows on screen now that look like the open menu of a shown item.
    ///   - now: The system uptime in seconds.
    mutating func check(openMenus: Set<UInt32>, now: TimeInterval) -> Decision {
        let counting = openMenus.subtracting(windowsBeforeReveal).subtracting(givenUp)
        // A window that closed waits anew should it come back.
        waitingSince = waitingSince.filter { counting.contains($0.key) }
        var newlyGivenUp = Set<UInt32>()
        for window in counting {
            let since = waitingSince[window] ?? now
            if now - since >= Self.longestWait {
                newlyGivenUp.insert(window)
                waitingSince[window] = nil
            } else {
                waitingSince[window] = since
            }
        }
        givenUp.formUnion(newlyGivenUp)
        return Decision(waits: !counting.subtracting(newlyGivenUp).isEmpty, newlyGivenUp: newlyGivenUp)
    }
}
