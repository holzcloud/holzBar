//
//  ClickPairing.swift
//  holzBar
//

import Foundation

/// Pairs each mouse press the click bridge holds back with its own release.
///
/// When the click bridge holds back a press (see `SystemItemClickBridge27`), it must hold back
/// the release of that same click as well: the system item's process would otherwise be handed a
/// release with no press behind it, moments before the replayed click that carries both. The
/// earlier version swallowed "the next left release within one second". That could take another
/// click's release: when the held press's own release was not seen (the tap was disabled by a
/// timeout in between), the next unrelated click's release was swallowed, its app never got a
/// mouse-up and a window followed the pointer.
///
/// The system gives a press and its release the same mouse event number (the SDK's
/// `CGEventTypes.h`: "Matching mouse-down and mouse-up events will have the same event number"),
/// so a release is swallowed only when a press with its number is held, and then once. Every held
/// press has a way out: its own release, ``flush()`` when the tap is stopped or disabled, or
/// ``expire(at:)`` after ``releaseWatchdog``. After a flush or an expiry the late physical
/// release of that press passes.
///
/// The invariants, checked by a seeded property test:
/// 1. A release is swallowed only if a press with that number is held.
/// 2. At most one release is swallowed per held press.
/// 3. After ``flush()`` or the expiry of a press, its release is not swallowed.
/// 4. ``Action/holdBack`` is answered only when the caller asked to hold the press.
/// 5. ``flush()`` returns exactly the presses still held, so every held press had a way out.
///
/// The reducer runs inside the tap's callback, which macOS disables when it is slow, so it stays
/// cheap: O(1) per call apart from ``expire(at:)``, which walks the handful of held presses. It
/// has no clock; the caller passes the time.
nonisolated struct ClickPairing: Equatable, Sendable {
    /// What the tap does with an event.
    nonisolated enum Action: Equatable, Sendable {
        /// Let the event through.
        case pass
        /// Hold the press back (the bridge replays the click itself).
        case holdBack
        /// Swallow the release of a held press.
        case swallowRelease
    }

    /// How long a held press waits for its release before the watchdog lets it go.
    static let releaseWatchdog = Duration.seconds(10)

    /// The held presses by mouse event number, and when each was taken.
    private var held = [Int64: ContinuousClock.Instant]()

    /// How many presses are held.
    var heldCount: Int {
        held.count
    }

    /// Notes a left press.
    ///
    /// - Parameters:
    ///   - number: The press's mouse event number.
    ///   - shouldHold: Whether the bridge holds the press back. A press that is not held forgets
    ///     an older press with the same number, which cannot be waiting any more.
    ///   - now: The current time.
    /// - Returns: ``Action/holdBack`` when the press is held, otherwise ``Action/pass``.
    mutating func press(number: Int64, shouldHold: Bool, at now: ContinuousClock.Instant) -> Action {
        guard shouldHold else {
            held[number] = nil
            return .pass
        }
        held[number] = now
        return .holdBack
    }

    /// Notes a left release.
    ///
    /// - Returns: ``Action/swallowRelease`` when a press with this number is held (and no longer
    ///   is afterwards), otherwise ``Action/pass``.
    mutating func release(number: Int64) -> Action {
        held.removeValue(forKey: number) == nil ? .pass : .swallowRelease
    }

    /// Lets every held press go, for when the tap is stopped or disabled.
    ///
    /// - Returns: The numbers of the presses that were held, in ascending order.
    mutating func flush() -> [Int64] {
        let numbers = held.keys.sorted()
        held.removeAll()
        return numbers
    }

    /// Lets go of the presses that waited ``releaseWatchdog`` or longer.
    ///
    /// - Returns: The numbers of the presses that expired, in ascending order.
    mutating func expire(at now: ContinuousClock.Instant) -> [Int64] {
        let due = held.filter { $0.value.duration(to: now) >= Self.releaseWatchdog }.keys.sorted()
        for number in due {
            held[number] = nil
        }
        return due
    }
}
