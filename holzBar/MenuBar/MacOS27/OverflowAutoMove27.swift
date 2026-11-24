//
//  OverflowAutoMove27.swift
//  holzBar
//

import Foundation
import OSLog

/// Runs Automatic, the third choice of "When the menu bar is full" (Phase 97, COMF-02, D-02,
/// D-10): when macOS 27 has folded Visible apps away and the bar stays that way, holzBar moves the
/// planner's apps (at most three) to Hidden by itself, with the undo toast at the menu bar.
///
/// This is the thin side of ``OverflowAutoMove``: that gate decides, this class reads the state,
/// hands it over and acts. It exists only while the mode is Automatic (``AppState/makeRoomModeDidChange()``
/// starts and stops it): in Off and Ask nothing observes and nothing waits. While it runs, it
/// reacts to the overflow state holzBar already observes (the overflow control, a drag, the
/// system resting, an application in its launch grace, Layout opening) and arms one one-shot wait
/// at a time for the instant the gate names; each new evaluation replaces it. No timer, no
/// polling. The gate is kept across a stop and start, so the breaker survives switching the mode.
///
/// Nothing here reaches a log line but counts: app names stay in memory.
@available(macOS 27.0, *)
@MainActor
final class OverflowAutoMove27 {
    /// What the observation watches: a change of any of it evaluates the gate again.
    private struct Watched: Equatable {
        var overflow: NativeOverflowReading27
        var isDragging: Bool
        var isPaused: Bool
        var isSettled: Bool
        var isLayoutOpen: Bool
        var isRunningPass: Bool
        var graceIDs: Set<String>

        /// The value while there is no app state.
        static let idle = Watched(
            overflow: .unknown,
            isDragging: false,
            isPaused: false,
            isSettled: false,
            isLayoutOpen: false,
            isRunningPass: false,
            graceIDs: []
        )
    }

    private weak var appState: AppState?
    private var gate: OverflowAutoMove?
    private var loop: ObservationLoop?
    /// The one one-shot wait; each evaluation replaces it.
    private var checkTask: Task<Void, Never>?
    private var isSettleHandlerRegistered = false
    private let logger = Logger(category: "OverflowAutoMove27")

    init(appState: AppState?) {
        self.appState = appState
    }

    /// Whether Automatic is running.
    var isRunning: Bool {
        loop != nil
    }

    /// Starts watching and evaluates once. The quiet start begins now, so nothing moves in the
    /// first minute after the mode is switched on.
    func start() {
        guard loop == nil, let appState else {
            return
        }
        if gate == nil {
            gate = OverflowAutoMove(startedAt: .now)
        } else {
            gate?.didSettle(at: .now)
        }
        if !isSettleHandlerRegistered {
            isSettleHandlerRegistered = true
            appState.systemActivityMonitor.onSettled { [weak self] in
                self?.systemDidSettle()
            }
        }
        loop = ObservationLoop.observe({ [weak self] in
            self?.watched() ?? Watched.idle
        }, onChange: { [weak self] _ in
            self?.evaluate()
        })
        evaluate()
    }

    /// Stops watching and drops the wait; the gate stays, so its breaker keeps counting.
    func stop() {
        loop?.cancel()
        loop = nil
        checkTask?.cancel()
        checkTask = nil
    }

    // MARK: - Evaluation

    /// Reads what the observation watches, which registers the observation too.
    private func watched() -> Watched {
        guard let appState else {
            return Watched.idle
        }
        let monitor = appState.systemActivityMonitor
        return Watched(
            overflow: appState.concealer27.nativeOverflow,
            isDragging: appState.isDraggingMenuBarItem,
            isPaused: monitor.isPaused,
            isSettled: monitor.isSettled,
            isLayoutOpen: appState.makeRoom27.isLayoutOpen,
            isRunningPass: appState.makeRoom27.isRunningPass,
            graceIDs: appState.concealer27.launchGraceBundleIDs
        )
    }

    /// The bar has settled after a wake or a display change: the quiet start begins again.
    private func systemDidSettle() {
        guard loop != nil else {
            return
        }
        gate?.didSettle(at: .now)
        evaluate()
    }

    /// Hands the gate the current reading and acts on its decision.
    private func evaluate() {
        checkTask?.cancel()
        checkTask = nil
        guard loop != nil, let appState else {
            return
        }
        let makeRoom = appState.makeRoom27
        guard !makeRoom.isRunningPass else {
            // The end of the pass is observed and evaluates again.
            return
        }
        let (reading, hasCandidates) = makeRoom.automaticReading()
        let monitor = appState.systemActivityMonitor
        let conditions = OverflowAutoMove.Conditions(
            isSettled: monitor.isSettled && !monitor.isPaused,
            isDragging: appState.isDraggingMenuBarItem,
            inLaunchGrace: !appState.concealer27.launchGraceBundleIDs.isEmpty,
            isLayoutOpen: makeRoom.isLayoutOpen,
            hasCandidates: hasCandidates
        )
        let now = ContinuousClock.now
        guard let decision = gate?.note(reading, conditions: conditions, at: now) else {
            return
        }
        switch decision {
        case .nothing:
            break
        case let .check(instant):
            arm(at: instant)
        case .runPass:
            if makeRoom.moveCandidates(place: .menuBar, origin: .automatic) {
                gate?.didRunPass(at: now)
                logger.info("Automatic made a pass")
            }
        }
    }

    /// Arms the one one-shot wait: at the instant the gate named, the overflow state is read again
    /// and the gate gets a second look.
    private func arm(at instant: ContinuousClock.Instant) {
        checkTask = Task { [weak self] in
            try? await Task.sleep(until: instant, tolerance: .milliseconds(200), clock: .continuous)
            guard !Task.isCancelled, let self else {
                return
            }
            await appState?.concealer27.refreshNativeOverflow()
            guard !Task.isCancelled else {
                return
            }
            evaluate()
        }
    }
}
