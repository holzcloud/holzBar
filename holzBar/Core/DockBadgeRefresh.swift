//
//  DockBadgeRefresh.swift
//  holzBar
//

import Foundation

/// When the Dock badges are read again: the Dock's own notifications drive the reads where it
/// posts them, a slow timer with back-off covers a Dock that stays silent, and nothing runs while
/// no badge item can be seen.
///
/// Whether the Dock announces a badge change is not known until it is seen on a real Mac, so the
/// rule decides at run time, from what the Dock does, and both answers are right without a
/// rebuild:
/// - A change found by a read that a notification triggered proves that the Dock announces
///   changes. The mode becomes ``Mode/following`` and no timer runs at all.
/// - A change found by a timed read proves that it does not (or not for badges). The mode becomes
///   ``Mode/polling``, the timer stays with a floor of ``baseInterval``, and Settings says so.
/// - Until one of the two has happened the mode is ``Mode/probing``: a timer runs, starting at
///   ``baseInterval`` after the first read and doubling after every read that found nothing, up to
///   ``maximumInterval``.
///
/// Notifications are coalesced (one read ``coalescing`` after the first, whatever follows in that
/// window) and the reads they trigger are never closer than ``minimumSpacing``. An activation,
/// launch or quit of a chosen app gives one read ``activationDelay`` later in every mode, so the
/// Dock has time to change the badge; it is no evidence of anything. A failed read proves nothing
/// about the mode. Three failed reads in a row set ``readerFailed``, and a read that works clears
/// it.
///
/// Becoming visible starts afresh in ``Mode/probing``; becoming invisible stops everything: no
/// pending read stays and nothing is armed until it is visible again. The value holds no clock and
/// no task: every call takes the instant it happened at, and the host arms the one wait that the
/// returned ``Action`` names. The host calls ``fire(at:)`` when that wait is over, runs the pass it
/// names and reports it with ``passFinished(trigger:changed:failed:at:)``.
nonisolated struct DockBadgeRefresh: Equatable, Sendable {
    /// What the rule has learned about the Dock.
    nonisolated enum Mode: Equatable, Sendable {
        /// Not known yet: a timer with back-off runs.
        case probing
        /// The Dock announces changes: no timer.
        case following
        /// The Dock does not announce changes: the timer stays.
        case polling
    }

    /// What caused a read.
    nonisolated enum Trigger: Equatable, Sendable {
        /// The first read after becoming visible.
        case start
        /// The Dock posted a notification.
        case notification
        /// The timer ran out.
        case timer
        /// A chosen app was activated, launched or quit, or the Dock itself launched.
        case activation
    }

    /// What the host does with its one wait after a call.
    nonisolated enum Action: Equatable, Sendable {
        /// Leave the wait as it is.
        case none
        /// Replace the wait by one that ends at the instant, then call ``fire(at:)``.
        case readAt(ContinuousClock.Instant)
        /// Cancel the wait; nothing is pending.
        case stop
    }

    /// The wait after the first read, and the wait after a change found by a timed read.
    static let baseInterval = Duration.seconds(30)

    /// The longest wait of the back-off.
    static let maximumInterval = Duration.seconds(120)

    /// How long after a notification the read follows, so a burst makes one read.
    static let coalescing = Duration.milliseconds(500)

    /// The least time between the start of two reads that notifications or activations trigger.
    static let minimumSpacing = Duration.seconds(2)

    /// How long after an activation the read follows.
    static let activationDelay = Duration.seconds(1)

    /// How many failed reads in a row make the Dock unreadable for the settings.
    static let failureLimit = 3

    /// What the rule has learned. ``Mode/probing`` while nothing is visible.
    private(set) var mode = Mode.probing

    /// Whether the rule is armed: something that shows a badge can be seen.
    private(set) var isVisible = false

    /// Whether the last ``failureLimit`` reads in a row failed. Survives becoming invisible; a
    /// read that works clears it.
    private(set) var readerFailed = false

    /// Whether the Dock stays silent about changes, so that the timer stays.
    var showsPollingLine: Bool {
        mode == .polling
    }

    private struct Pending: Equatable, Sendable {
        var start: ContinuousClock.Instant?
        var timer: ContinuousClock.Instant?
        var notification: ContinuousClock.Instant?
        var activation: ContinuousClock.Instant?
    }

    private var pending = Pending()
    private var interval = baseInterval
    private var failures = 0
    private var isReading = false
    private var lastRead: ContinuousClock.Instant?
    private var armedFor: ContinuousClock.Instant?
    private var timerTakenAlong = false

    // MARK: Events

    /// Something that shows a badge became visible or invisible. Becoming visible reads at once.
    mutating func visible(_ isVisible: Bool, at now: ContinuousClock.Instant) -> Action {
        guard isVisible != self.isVisible else {
            return .none
        }
        self.isVisible = isVisible
        mode = .probing
        interval = Self.baseInterval
        pending = Pending()
        armedFor = nil
        isReading = false
        lastRead = nil
        timerTakenAlong = false
        guard isVisible else {
            return .stop
        }
        pending.start = now
        return arm()
    }

    /// The Dock posted a notification. Only the fact counts.
    mutating func notified(at now: ContinuousClock.Instant) -> Action {
        guard isVisible else {
            return .none
        }
        if pending.notification == nil {
            pending.notification = now + Self.coalescing
        }
        return arm()
    }

    /// A chosen app was activated, launched or quit, or the Dock itself launched.
    mutating func activated(at now: ContinuousClock.Instant) -> Action {
        guard isVisible else {
            return .none
        }
        if pending.activation == nil {
            pending.activation = now + Self.activationDelay
        }
        return arm()
    }

    /// The wait the last ``Action/readAt(_:)`` named is over. Returns what caused the read that is
    /// due, which the host runs and then reports with
    /// ``passFinished(trigger:changed:failed:at:)``; or `nil` when no read is due now (nothing
    /// pending, a pass still running, or not visible). Everything due is taken by that one read.
    /// A wait never ends early, so a `nil` with a read pending only happens while a pass runs, and
    /// that pass's result arms it again.
    mutating func fire(at now: ContinuousClock.Instant) -> Trigger? {
        // The wait that calls this is over; a call before its instant leaves it armed.
        if let armed = armedFor, armed <= now {
            armedFor = nil
        }
        guard isVisible, !isReading else {
            return nil
        }
        var trigger: Trigger?
        if let start = pending.start, start <= now {
            pending.start = nil
            trigger = .start
        }
        if let activation = pending.activation, spaced(activation) <= now {
            pending.activation = nil
            trigger = trigger ?? .activation
        }
        if let timer = pending.timer, timer <= now {
            pending.timer = nil
            if trigger == nil {
                trigger = .timer
            } else {
                timerTakenAlong = true
            }
        }
        if let notification = pending.notification, spaced(notification) <= now {
            pending.notification = nil
            trigger = trigger ?? .notification
        }
        guard let trigger else {
            return nil
        }
        isReading = true
        lastRead = now
        return trigger
    }

    /// The pass that ``fire(at:)`` named is over.
    ///
    /// - Parameters:
    ///   - trigger: What ``fire(at:)`` returned.
    ///   - changed: Whether the pass found a badge that differs from the pass before
    ///     (``changed(from:to:)``). It counts as evidence for the mode only after a timer or a
    ///     notification, and only when the read worked.
    ///   - failed: Whether the Dock could not be read.
    mutating func passFinished(
        trigger: Trigger,
        changed: Bool,
        failed: Bool,
        at now: ContinuousClock.Instant
    ) -> Action {
        guard isVisible else {
            return .none
        }
        isReading = false
        if failed {
            failures += 1
            if failures >= Self.failureLimit {
                readerFailed = true
            }
        } else {
            failures = 0
            readerFailed = false
        }
        let foundChange = changed && !failed
        switch trigger {
        case .notification where foundChange:
            mode = .following
            pending.timer = nil
        case .timer where foundChange:
            mode = .polling
            interval = Self.baseInterval
        case .timer:
            interval = min(interval * 2, Self.maximumInterval)
        case .start, .notification, .activation:
            break
        }
        if mode != .following {
            switch trigger {
            case .start:
                interval = Self.baseInterval
                pending.timer = now + interval
            case .timer:
                pending.timer = now + interval
            case .notification, .activation:
                // A timer that this read took along is armed again.
                if timerTakenAlong {
                    pending.timer = now + interval
                }
            }
        }
        timerTakenAlong = false
        return arm()
    }

    /// The list of apps in the Dock was read in the settings and worked: that is a read that works.
    mutating func readWorked() {
        failures = 0
        readerFailed = false
    }

    // MARK: Change

    /// Whether the badges of the chosen apps differ between two passes. An app that is not in the
    /// Dock has no badge, which is the same as an app without one.
    static func changed(from old: [String: DockBadgeLabel], to new: [String: DockBadgeLabel]) -> Bool {
        for key in Set(old.keys).union(new.keys) where (old[key] ?? .none) != (new[key] ?? .none) {
            return true
        }
        return false
    }

    // MARK: Arming

    /// A read caused by an event is never closer than ``minimumSpacing`` to the last read.
    private func spaced(_ instant: ContinuousClock.Instant) -> ContinuousClock.Instant {
        guard let lastRead else {
            return instant
        }
        return max(instant, lastRead + Self.minimumSpacing)
    }

    /// The instant of the first pending read.
    private func earliest() -> ContinuousClock.Instant? {
        var instants = [ContinuousClock.Instant]()
        if let start = pending.start {
            instants.append(start)
        }
        if let timer = pending.timer {
            instants.append(timer)
        }
        if let notification = pending.notification {
            instants.append(spaced(notification))
        }
        if let activation = pending.activation {
            instants.append(spaced(activation))
        }
        return instants.min()
    }

    /// The action that brings the host's wait to the first pending read.
    private mutating func arm() -> Action {
        guard let next = earliest() else {
            armedFor = nil
            return .none
        }
        guard next != armedFor else {
            return .none
        }
        armedFor = next
        return .readAt(next)
    }
}
