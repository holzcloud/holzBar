//
//  EventBarrierPolicy.swift
//  holzBar
//

/// Bounds of the event barriers that move and click menu bar items before macOS 27.
///
/// A barrier posts an entry event and waits until its exit event comes back through
/// holzBar's event taps. A successful round trip returns as soon as the exit event arrives,
/// so these bounds only matter when an event is lost: then the barrier gives up, the
/// pointer comes back and the next move or click can run.
nonisolated enum EventBarrierPolicy {
    /// The shortest wait of a main barrier.
    ///
    /// Far above the adaptive 25-150 ms move timeouts, so a slow but successful round
    /// trip is never cut short; only a lost one ends here.
    static let minimumMainWait = Duration.milliseconds(500)

    /// The kind of barrier, which decides how long it waits.
    enum Bound: Sendable {
        /// A barrier of the move or click itself; waits at least ``minimumMainWait``.
        case main
        /// The double mouse-up after a failed move or click; keeps its designed bound.
        case fallback

        /// How long a barrier with the given timeout per round trip and repeat count waits.
        func wait(timeout: Duration, count: Int) -> Duration {
            switch self {
            case .main: max(timeout * count, EventBarrierPolicy.minimumMainWait)
            case .fallback: timeout * count
            }
        }
    }

    /// Caps the attempts of a move or click once a barrier timed out.
    ///
    /// A barrier timeout means an event was lost; one further attempt covers a transient
    /// loss, more would only keep the pointer hidden longer.
    struct AttemptBudget: Sendable {
        private var limit: Int

        /// Creates a budget that allows `maxAttempts` attempts while no barrier times out.
        init(maxAttempts: Int) {
            limit = maxAttempts
        }

        /// Whether another attempt may follow the given failed one (counted from 1).
        mutating func allowsRetry(afterFailedAttempt attempt: Int, barrierTimedOut: Bool) -> Bool {
            if barrierTimedOut {
                limit = min(limit, attempt + 1)
            }
            return attempt < limit
        }
    }

    /// The adaptive move timeout after a failed move attempt.
    ///
    /// A late item response grows it by half; a barrier timeout does not, because a lost
    /// event says nothing about how fast the item responds.
    static func moveTimeout(afterFailure timeout: Duration, barrierTimedOut: Bool) -> Duration {
        barrierTimedOut ? timeout : timeout + timeout / 2
    }
}
