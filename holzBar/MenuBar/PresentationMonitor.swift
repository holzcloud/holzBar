//
//  PresentationMonitor.swift
//  holzBar
//

import AppKit
import OSLog

/// Turns Zen mode on while the screen is mirrored or shared, and off again afterwards
/// ("Turn on Zen mode while the screen is mirrored or shared", THAW-10).
///
/// The mirroring check (`CGDisplayIsInMirrorSet` when the displays change) is adapted
/// from Thaw's `PresentationMonitor` (see NOTICE). Thaw found screen sharing by reading the
/// process table every 5 seconds; holzBar looks for macOS's screen sharing agent among the
/// running applications when they change instead (see ``PresentationSignals``), so nothing
/// polls and no permission is needed. The change is observed through NSWorkspace's
/// `runningApplications`: its launch and quit notifications reach regular apps only, and the
/// agent is a background agent. Nothing runs while the setting is off.
@MainActor
final class PresentationMonitor {
    /// The shared app state.
    private weak var appState: AppState?

    /// Follows the setting.
    private var settingObserver: ObservationLoop?

    /// The task that receives display changes, while the setting is on.
    private var screenParametersTask: Task<Void, Never>?

    /// Observes the running applications, while the setting is on.
    private var runningApplicationsObservation: NSKeyValueObservation?

    /// The running applications last evaluated, so only a change of their set is evaluated.
    private var trigger = PresentationSignals.Trigger()

    /// The last answer, so only a change turns Zen mode on or off.
    private var isPresenting = false

    private let logger = Logger(category: "PresentationMonitor")

    /// Starts following the setting.
    func performSetup(with appState: AppState) {
        self.appState = appState
        let advanced = appState.settings.advanced
        settingObserver = ObservationLoop.observe { advanced.autoZenWhileSharingScreen } onChange: { [weak self] isOn in
            self?.setRunning(isOn)
        }
        setRunning(advanced.autoZenWhileSharingScreen)
    }

    private func setRunning(_ isOn: Bool) {
        if isOn {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard screenParametersTask == nil else {
            return
        }
        screenParametersTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.evaluate()
            }
        }
        // Reads only the bundle identifiers of the changed applications, keeps no reference to
        // them, takes no lock and never waits: the handler runs on the main thread.
        runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old, .new]) { [weak self] _, change in
            let changed = (change.newValue ?? []) + (change.oldValue ?? [])
            guard changed.contains(where: { $0.bundleIdentifier != nil }) else {
                return
            }
            Task { @MainActor in
                self?.runningApplicationsDidChange()
            }
        }
        evaluate()
    }

    /// Stops listening and withdraws only the automatic part of Zen mode.
    private func stop() {
        screenParametersTask?.cancel()
        screenParametersTask = nil
        runningApplicationsObservation?.invalidate()
        runningApplicationsObservation = nil
        trigger.reset()
        isPresenting = false
        appState?.menuBarManager.setAutomaticZenMode(false)
    }

    /// Evaluates when the set of running bundle identifiers changed.
    private func runningApplicationsDidChange() {
        let running = Self.runningBundleIDs()
        guard trigger.needsEvaluation(running: running) else {
            return
        }
        evaluate(running: running)
    }

    /// Evaluates with the applications running now, and records them as evaluated.
    private func evaluate() {
        let running = Self.runningBundleIDs()
        _ = trigger.needsEvaluation(running: running)
        evaluate(running: running)
    }

    private func evaluate(running: Set<String>) {
        let mirroredDisplays = NSScreen.screens.filter { screen in
            CGDisplayIsInMirrorSet(screen.displayID) != 0
        }.count
        let presenting = PresentationSignals.isPresenting(mirroredDisplays: mirroredDisplays, runningBundleIDs: running)
        guard presenting != isPresenting else {
            return
        }
        isPresenting = presenting
        if presenting {
            logger.notice("The screen is mirrored or shared: Zen mode on")
        } else {
            logger.notice("The screen is no longer mirrored or shared: Zen mode off")
        }
        appState?.menuBarManager.setAutomaticZenMode(presenting)
    }

    /// The bundle identifiers of the running applications.
    private static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}
