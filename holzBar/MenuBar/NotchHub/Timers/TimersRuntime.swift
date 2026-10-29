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

    init(appState: AppState) {}

    // MARK: Operations

    /// Starts a timer for a length of time.
    @discardableResult
    func startLength(_ seconds: Double, label: String) -> TimerBoard.StartResult {
        let result = board.startLength(seconds, label: label, now: .now)
        rearm()
        return result
    }

    /// Starts a countdown to a moment.
    @discardableResult
    func startMoment(_ moment: Date, label: String) -> TimerBoard.StartResult {
        let result = board.startMoment(moment, label: label, now: .now)
        rearm()
        return result
    }

    func pause(_ id: UUID) {
        board.pause(id, now: .now)
        rearm()
    }

    func resume(_ id: UUID) {
        board.resume(id, now: .now)
        rearm()
    }

    func restart(_ id: UUID) {
        board.restart(id, now: .now)
        rearm()
    }

    func remove(_ id: UUID) {
        board.remove(id)
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
        case .paused: detail = Text("Paused")
        case .finished: detail = Text("Done")
        }
        return HubTile(
            symbol: "timer",
            title: board.items.count > 1 ? Text("Timers") : Text("Timer"),
            value: value,
            detail: detail
        )
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

    func shutDown() {
        alarm.cancel()
        board = TimerBoard()
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
            alarm.playFinishSound()
        }
        rearm()
    }
}
