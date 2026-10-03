//
//  SystemActivityMonitor.swift
//  holzBar
//

import Cocoa
import Observation
import OSLog

/// Follows whether the Mac is in use, and tells holzBar when the menu bar has settled after
/// it was not or after the displays changed (see `SystemActivity`).
///
/// It listens to notifications only: the workspace's sleep, wake and session notifications,
/// the screen lock's distributed notifications and the screen parameters. After an event
/// that resumes or changes the bar it waits once for ``SystemActivity/settleDelay`` and then
/// runs the settle handlers; nothing repeats.
@MainActor
@Observable
final class SystemActivityMonitor {
    /// Whether holzBar rests: the screen is locked, the Mac sleeps or the session is away.
    /// Item reads, moves and captures wait while it is `true`.
    private(set) var isPaused = false

    /// The state fed by the notifications.
    @ObservationIgnored private var activity = SystemActivity()

    /// The handlers that run once the bar has settled.
    @ObservationIgnored private var settleHandlers = [@MainActor () -> Void]()

    /// Tasks that observe the notifications.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// The one-shot wait for the bar to settle.
    @ObservationIgnored private var settleTask: Task<Void, Never>?

    @ObservationIgnored private let logger = Logger(category: "SystemActivityMonitor")

    deinit {
        for task in observerTasks {
            task.cancel()
        }
        settleTask?.cancel()
    }

    /// Starts listening to the notifications.
    func performSetup() {
        let workspaceEvents: [(Notification.Name, SystemActivity.Event)] = [
            (NSWorkspace.willSleepNotification, .willSleep),
            (NSWorkspace.didWakeNotification, .didWake),
            (NSWorkspace.screensDidSleepNotification, .willSleep),
            (NSWorkspace.screensDidWakeNotification, .didWake),
            (NSWorkspace.sessionDidResignActiveNotification, .sessionResigned),
            (NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive),
        ]
        for (name, event) in workspaceEvents {
            observe(name, in: NSWorkspace.shared.notificationCenter, as: event)
        }
        // macOS posts no public notification for the screen lock; these distributed ones
        // are what the system's own clients listen to.
        let screenLockEvents: [(Notification.Name, SystemActivity.Event)] = [
            (Notification.Name("com.apple.screenIsLocked"), .screenLocked),
            (Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked),
        ]
        for (name, event) in screenLockEvents {
            observe(name, in: DistributedNotificationCenter.default(), as: event)
        }
        observe(NSApplication.didChangeScreenParametersNotification, in: NotificationCenter.default, as: .displaysChanged)
    }

    /// Adds a handler that runs each time the bar has settled after the Mac was not in use
    /// or the displays changed.
    func onSettled(_ handler: @escaping @MainActor () -> Void) {
        settleHandlers.append(handler)
    }

    /// Feeds each notification with the given name to the state as the given event.
    private func observe(_ name: Notification.Name, in center: NotificationCenter, as event: SystemActivity.Event) {
        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: name) {
                self?.handle(event)
            }
        })
    }

    /// Records an event, publishes the pause and waits for the bar to settle.
    private func handle(_ event: SystemActivity.Event) {
        activity.handle(event, at: .now)
        logger.info("System activity: \(String(describing: event), privacy: .public), paused: \(self.activity.isPaused, privacy: .public)")
        if isPaused != activity.isPaused {
            isPaused = activity.isPaused
        }
        switch event {
        case .screenUnlocked, .didWake, .sessionBecameActive, .displaysChanged:
            scheduleSettle()
        case .screenLocked, .willSleep, .sessionResigned:
            settleTask?.cancel()
            settleTask = nil
        }
    }

    /// Runs the settle handlers once the bar has settled, unless holzBar rests again first.
    private func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            do {
                try await Task.sleep(for: SystemActivity.settleDelay)
            } catch {
                return
            }
            guard let self, activity.settled(at: .now) else {
                return
            }
            logger.info("System activity: the menu bar has settled")
            for handler in settleHandlers {
                handler()
            }
        }
    }
}
