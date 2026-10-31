//
//  TimersRuntime.swift
//  holzBar
//

import Foundation
import Observation
import SwiftUI

/// The running part of the Timers module of the Notch hub.
///
/// The hub creates it only while the hub and the module are both on and calls ``shutDown()``
/// when either goes off, so nothing of the module exists while it is off. Every change goes
/// through the pure ``TimerBoard``; the alarm is armed from ``TimerBoard/nextDeadline`` after
/// every change.
@MainActor
@Observable
final class TimersRuntime: HubModuleRuntime {
    /// The identifier of the module in ``ModuleCatalog``.
    static let identifier = "timers"

    let moduleID = TimersRuntime.identifier
    let tint = HubTint.red
    let offersTab = true

    /// The timers.
    private(set) var board = TimerBoard()

    @ObservationIgnored private let alarm = TimersAlarm()
    @ObservationIgnored private weak var appState: AppState?

    /// Reads the stored timers. What ended while holzBar was not watching is marked finished,
    /// and nothing rings: a late ending is silent, and nothing rings at launch.
    init(appState: AppState) {
        self.appState = appState
        board = TimerBoard.decoded(from: Defaults.data(forKey: .timersBoard))
        let before = board
        _ = board.collectFinished(now: .now)
        if board != before {
            persist()
        }
        rearm()
    }

    // MARK: Operations

    /// Starts a timer for a length of time.
    @discardableResult
    func startLength(_ seconds: Double, label: String) -> TimerBoard.StartResult {
        let result = board.startLength(seconds, label: label, now: .now)
        persist()
        rearm()
        return result
    }

    /// Starts a countdown to a moment.
    @discardableResult
    func startMoment(_ moment: Date, label: String) -> TimerBoard.StartResult {
        let result = board.startMoment(moment, label: label, now: .now)
        persist()
        rearm()
        return result
    }

    /// Starts a stopwatch that counts up from zero.
    @discardableResult
    func startStopwatch(label: String) -> TimerBoard.StartResult {
        let result = board.startStopwatch(label: label, now: .now)
        persist()
        rearm()
        return result
    }

    func pause(_ id: UUID) {
        board.pause(id, now: .now)
        persist()
        rearm()
    }

    func resume(_ id: UUID) {
        board.resume(id, now: .now)
        persist()
        rearm()
    }

    func restart(_ id: UUID) {
        board.restart(id, now: .now)
        persist()
        rearm()
    }

    func remove(_ id: UUID) {
        board.remove(id)
        persist()
        rearm()
    }

    // MARK: Hub

    /// The Overview card: the leading timer, with its live remaining time.
    var tile: HubTile? {
        guard let item = board.leading else {
            return nil
        }
        let name = TimersFormat.name(of: item)
        let value = name.count > 14 ? String(name.prefix(13)) + "…" : name
        let detail: Text
        switch item.state {
        case .running(let start, let end): detail = Text(timerInterval: start...end, countsDown: true)
        case .counting(let since): detail = Text(timerInterval: since...TimersFormat.stopwatchEnd(from: since), countsDown: false)
        case .paused, .halted: detail = Text("Paused")
        case .finished: detail = Text("Done")
        }
        return HubTile(
            symbol: "timer",
            title: title(of: item),
            value: value,
            detail: detail
        )
    }

    private func title(of item: TimerItem) -> Text {
        if board.items.count > 1 {
            return Text("Timers")
        }
        return item.kind == .stopwatch ? Text("Stopwatch") : Text("Timer")
    }

    /// The pill beside the notch: Done while a finished timer waits, else the end time of the
    /// soonest running timer; none with neither.
    var statusPill: HubStatusPill? {
        if board.items.contains(where: { item in
            if case .finished = item.state {
                return true
            }
            return false
        }) {
            return HubStatusPill(symbol: "bell.fill", text: String(localized: "Done"), accessibilityLabel: Text("Timer done"))
        }
        guard let end = board.nextDeadline else {
            return nil
        }
        let time = TimersFormat.time(end)
        return HubStatusPill(symbol: "timer", text: time, accessibilityLabel: Text("Timer ends at \(time)"))
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(TimersBodyView(runtime: self, host: host))
    }

    /// Stops the alarm and its observers and lets go of the timers in memory. The stored board
    /// stays, so a running timer's end still stands when the module is switched on again.
    func shutDown() {
        alarm.cancel()
        board = TimerBoard()
    }

    // MARK: Storage

    /// Stores the board on this Mac (a local-only key), or removes the key for an empty one.
    private func persist() {
        if board.items.isEmpty {
            Defaults.removeObject(forKey: .timersBoard)
        } else {
            Defaults.set(board.encoded(), forKey: .timersBoard)
        }
    }

    // MARK: Alarm

    /// Arms the one wait for the next end, or none when no timer runs.
    private func rearm() {
        alarm.arm(deadline: board.nextDeadline) { [weak self] in
            self?.fire()
        }
    }

    /// Called when the wait ends: finishes what ended, rings once and arms for the rest.
    private func fire() {
        let finished = board.collectFinished(now: .now)
        if !finished.rang.isEmpty {
            alarm.playFinishSound(appState?.settings.timers.finishSound ?? .glass)
        }
        if !finished.rang.isEmpty || !finished.missed.isEmpty {
            persist()
        }
        rearm()
    }
}
