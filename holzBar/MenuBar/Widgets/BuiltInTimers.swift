//
//  BuiltInTimers.swift
//  holzBar
//

import AppKit

/// The countdowns of the timer items.
///
/// A timer exists only after a click starts it. While it runs, one task waits for the moment the
/// text changes (every second while the item is seen) or, when the item is hidden, for the end
/// only; there is no repeating timer, and an idle timer has no task at all. The rules of the
/// countdown are ``ItemTimer``'s; this class only waits and plays the sound at the end.
@MainActor
final class BuiltInTimers {
    private struct Entry {
        var timer = ItemTimer()
        var task: Task<Void, Never>?
        /// Tells a wait that was replaced from the current one.
        var token = 0
        var isSeen = true
    }

    private var entries = [UUID: Entry]()

    /// Called after the text of the timer with the given identifier changed.
    var onChange: ((UUID) -> Void)?

    /// The text of the timer: its length while idle, the time left while it runs.
    func label(for id: UUID, minutes: Int) -> String {
        (entries[id]?.timer ?? ItemTimer()).label(minutes: minutes, now: Date())
    }

    /// A click on the item: starts the timer, cancels a running one or clears a finished one.
    func tap(_ id: UUID, minutes: Int) {
        var entry = entries[id] ?? Entry()
        entry.timer.tap(minutes: minutes, now: Date())
        entries[id] = entry
        rearm(id)
        onChange?(id)
    }

    /// Tells whether the item is seen, so that a hidden timer waits for its end only.
    func setSeen(_ isSeen: Bool, for id: UUID) {
        guard var entry = entries[id], entry.isSeen != isSeen else {
            return
        }
        entry.isSeen = isSeen
        entries[id] = entry
        if entry.timer.isRunning {
            rearm(id)
            onChange?(id)
        }
    }

    /// Forgets the timer of an item that is gone.
    func forget(_ id: UUID) {
        entries[id]?.task?.cancel()
        entries[id] = nil
    }

    /// Cancels every wait and every timer, when the module is switched off.
    func removeAll() {
        for entry in entries.values {
            entry.task?.cancel()
        }
        entries.removeAll()
    }

    private func rearm(_ id: UUID) {
        guard var entry = entries[id] else {
            return
        }
        entry.task?.cancel()
        entry.task = nil
        entry.token &+= 1
        let token = entry.token
        if let wake = entry.timer.nextWake(now: Date(), isSeen: entry.isSeen) {
            let delay = max(wake.timeIntervalSinceNow, 0)
            entry.task = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(50), clock: ContinuousClock())
                } catch {
                    return
                }
                self?.woke(id, token: token)
            }
        }
        entries[id] = entry
    }

    private func woke(_ id: UUID, token: Int) {
        guard var entry = entries[id], entry.token == token else {
            return
        }
        entry.task = nil
        let finished = entry.timer.advance(now: Date())
        entries[id] = entry
        rearm(id)
        onChange?(id)
        if finished {
            (NSSound(named: "Glass") ?? NSSound(named: "Funk"))?.play()
            LayoutBarItemView.announce(String(localized: "Timer finished"))
        }
    }
}
