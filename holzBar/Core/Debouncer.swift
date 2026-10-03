//
//  Debouncer.swift
//  holzBar
//

/// Runs an action once calls to it have paused, or at most once per interval.
///
/// It replaces Combine's `debounce` and `throttle` operators:
///
/// - ``schedule(_:)`` debounces: each call cancels the pending action and waits the full
///   delay again, so only the last action runs, once the calls stop for the delay.
/// - ``throttle(latest:_:)`` throttles like `throttle(for:latest:)`: a call when nothing ran
///   within the delay runs at once; the calls during the delay are collected into one
///   action that runs when the delay has passed, the first of them (`latest: false`, as
///   Combine keeps the first value) or the last (`latest: true`).
///
/// Both run on the main actor. Releasing or cancelling the debouncer drops the pending action.
@MainActor
final class Debouncer {
    /// How long calls must pause (``schedule(_:)``) or how far apart runs are (``throttle(latest:_:)``).
    let delay: Duration

    /// How much later than the delay the system may run the action, to save wake-ups.
    let tolerance: Duration?

    /// The task that waits for the delay and then runs the pending action.
    private var task: Task<Void, Never>?

    /// The action the throttle runs when the delay has passed.
    private var pendingAction: (@MainActor () -> Void)?

    /// When the last throttled action ran.
    private var lastRun: ContinuousClock.Instant?

    /// Creates a debouncer with the given delay and tolerance.
    init(delay: Duration, tolerance: Duration? = nil) {
        self.delay = delay
        self.tolerance = tolerance
    }

    deinit {
        task?.cancel()
    }

    /// Runs the action after the delay, unless another call comes first.
    func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task { [delay, tolerance] in
            do {
                try await Task.sleep(for: delay, tolerance: tolerance)
            } catch {
                return
            }
            action()
        }
    }

    /// Runs the action at once if nothing ran within the delay; otherwise runs one of the
    /// actions of the calls made during the delay once it has passed.
    ///
    /// - Parameters:
    ///   - latest: Whether the last action of the calls during the delay runs (`true`)
    ///     or the first one (`false`).
    ///   - action: The action to run.
    func throttle(latest: Bool = false, _ action: @escaping @MainActor () -> Void) {
        if task != nil {
            if latest {
                pendingAction = action
            }
            return
        }
        let now = ContinuousClock.now
        guard let lastRun, lastRun.duration(to: now) < delay else {
            self.lastRun = now
            action()
            return
        }
        pendingAction = action
        let wait = delay - lastRun.duration(to: now)
        task = Task { [weak self, tolerance] in
            do {
                try await Task.sleep(for: wait, tolerance: tolerance)
            } catch {
                return
            }
            guard let self else {
                return
            }
            let action = pendingAction
            pendingAction = nil
            task = nil
            self.lastRun = .now
            action?()
        }
    }

    /// Drops the pending action.
    func cancel() {
        task?.cancel()
        task = nil
        pendingAction = nil
    }
}
