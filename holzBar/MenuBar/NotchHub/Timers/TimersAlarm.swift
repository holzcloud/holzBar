//
//  TimersAlarm.swift
//  holzBar
//

import AppKit

/// The only waiting the Timers module owns: one one-shot task until the earliest end of a
/// running timer, three notification observers that exist only while a timer runs, and the
/// sound that rings when a timer ends.
///
/// There is no repeating timer and no per-second refresh. The remaining time on screen is
/// drawn by the system from a date range. The wait runs on `ContinuousClock`, which keeps
/// counting while the Mac sleeps, so a wait that spans a sleep ends at once on wake. The
/// observers (wake, clock change, time-zone change) make the module look at its timers again,
/// because a moved clock moves the ends; with no timer running they do not exist.
@MainActor
final class TimersAlarm {
    /// The task that waits for the next end.
    private var wait: Task<Void, Never>?

    /// The tasks that listen for wake, clock and time-zone changes.
    private var observers = [Task<Void, Never>]()

    /// What to do when the wait ends or the clock may have moved.
    private var onFire: (@MainActor () -> Void)?

    /// The sound that rings, kept until it is done.
    private var sound: NSSound?

    /// Waits for `deadline` and then calls `onFire`, once. A previous wait is cancelled. A
    /// `nil` deadline (no timer runs) leaves neither a wait nor an observer. While there is a
    /// deadline, `onFire` is also called when the Mac wakes and when the clock or the time
    /// zone changes, so the caller can look at its timers and arm again.
    func arm(deadline: Date?, onFire: @escaping @MainActor () -> Void) {
        wait?.cancel()
        wait = nil
        guard let deadline else {
            stopObserving()
            return
        }
        self.onFire = onFire
        startObserving()
        // A deadline in the past waits no time; a wait that ends early re-arms for the rest.
        let seconds = max(0, deadline.timeIntervalSinceNow)
        wait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.wait = nil
            self?.onFire?()
        }
    }

    /// Cancels the wait and the observers.
    func cancel() {
        wait?.cancel()
        wait = nil
        stopObserving()
        sound?.stop()
        sound = nil
    }

    /// Plays the finish sound once; nothing for none.
    func playFinishSound(_ choice: TimerFinishSound) {
        guard let name = choice.systemName, let sound = NSSound(named: NSSound.Name(name)) else {
            return
        }
        self.sound?.stop()
        self.sound = sound
        sound.play()
    }

    private func startObserving() {
        guard observers.isEmpty else {
            return
        }
        let sources: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NotificationCenter.default, .NSSystemClockDidChange),
            (NotificationCenter.default, .NSSystemTimeZoneDidChange),
        ]
        observers = sources.map { center, name in
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    self?.onFire?()
                }
            }
        }
    }

    private func stopObserving() {
        for task in observers {
            task.cancel()
        }
        observers.removeAll()
        onFire = nil
    }

    deinit {
        wait?.cancel()
        for task in observers {
            task.cancel()
        }
    }
}
