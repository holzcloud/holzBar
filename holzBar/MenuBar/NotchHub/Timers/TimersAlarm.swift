//
//  TimersAlarm.swift
//  holzBar
//

import AppKit

/// The only wait the Timers module owns: one one-shot task until the earliest end of a
/// running timer, and the sound that rings when a timer ends.
///
/// There is no repeating timer and no per-second refresh. The remaining time on screen is
/// drawn by the system from a date range. The wait runs on `ContinuousClock`, which keeps
/// counting while the Mac sleeps, so a wait that spans a sleep ends at once on wake.
@MainActor
final class TimersAlarm {
    /// The task that waits for the next end.
    private var wait: Task<Void, Never>?

    /// The sound that rings, kept until it is done.
    private var sound: NSSound?

    /// Waits for `deadline` and then calls `onFire`, once. A previous wait is cancelled; a
    /// `nil` deadline (no timer runs) leaves no wait at all.
    func arm(deadline: Date?, onFire: @escaping @MainActor () -> Void) {
        wait?.cancel()
        wait = nil
        guard let deadline else {
            return
        }
        // A deadline in the past waits no time; a wait that ends early re-arms for the rest.
        let seconds = max(0, deadline.timeIntervalSinceNow)
        wait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds), clock: .continuous)
            guard !Task.isCancelled else {
                return
            }
            self?.wait = nil
            onFire()
        }
    }

    /// Cancels the wait.
    func cancel() {
        wait?.cancel()
        wait = nil
        sound?.stop()
        sound = nil
    }

    /// Plays the finish sound, once.
    func playFinishSound() {
        guard let sound = NSSound(named: NSSound.Name("Glass")) else {
            return
        }
        self.sound?.stop()
        self.sound = sound
        sound.play()
    }

    deinit {
        wait?.cancel()
    }
}
