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

    /// Starts a timer for a length of time.
    func startLength(_ seconds: Double) {
        board.startLength(seconds, label: "", now: .now)
        rearm()
    }

    func makeBody(host: any HubHost) -> AnyView {
        AnyView(TimersBodyView(runtime: self))
    }

    func shutDown() {
        alarm.cancel()
        board = TimerBoard()
    }

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
