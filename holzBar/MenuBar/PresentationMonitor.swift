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
/// running applications when an application launches or quits instead (see
/// ``PresentationSignals``), so nothing polls and no permission is needed. Nothing runs
/// while the setting is off.
@MainActor
final class PresentationMonitor {
    /// The shared app state.
    private weak var appState: AppState?

    /// Follows the setting.
    private var settingObserver: ObservationLoop?

    /// The tasks that receive the notifications, while the setting is on.
    private var notificationTasks = [Task<Void, Never>]()

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
        guard notificationTasks.isEmpty else {
            return
        }
        notificationTasks = [
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                    self?.evaluate()
                }
            },
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.didLaunchApplicationNotification) {
                    self?.evaluate()
                }
            },
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.didTerminateApplicationNotification) {
                    self?.evaluate()
                }
            },
        ]
        evaluate()
    }

    /// Stops listening and withdraws only the automatic part of Zen mode.
    private func stop() {
        for task in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
        isPresenting = false
        appState?.menuBarManager.setAutomaticZenMode(false)
    }

    private func evaluate() {
        let mirroredDisplays = NSScreen.screens.filter { screen in
            CGDisplayIsInMirrorSet(screen.displayID) != 0
        }.count
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
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
}
