//
//  HiddenItemsLock.swift
//  holzBar
//

import AppKit
import LocalAuthentication
import Observation
import OSLog

/// Asks for Touch ID or the login password before the hidden items are shown, when the user
/// turned the lock on.
///
/// Every way of showing them goes through ``authenticate(then:)``: hover, click, scroll,
/// hotkeys, the Shelf, the search, `holzbar://` URLs and Shortcuts. The user's own safety
/// rules do not ask: showing the section when the battery runs low, when the connection is
/// lost, when an automation rule says so and when an item they chose changes. A successful
/// answer opens a grace period of a minute; the screen locking or the Mac sleeping ends it.
///
/// It keeps a bystander at an unlocked Mac from seeing what the hidden items show. It is not
/// a security boundary against the owner: turning the lock off asks too. The setting is local
/// to the Mac and is neither exported nor synced, so a file cannot turn it on or off.
@MainActor
@Observable
final class HiddenItemsLock {
    /// Whether showing the hidden items needs an authentication.
    private(set) var isEnabled = Defaults.bool(forKey: .lockHiddenItems) {
        didSet {
            Defaults.set(isEnabled, forKey: .lockHiddenItems)
        }
    }

    @ObservationIgnored private let logger = Logger(category: "HiddenItemsLock")
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var gate = RevealGate()
    @ObservationIgnored private var isAuthenticating = false
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Whether showing now needs an authentication.
    var requiresAuthentication: Bool {
        gate.requiresAuthentication(isLockOn: isEnabled, now: .now)
    }

    func performSetup(with appState: AppState) {
        self.appState = appState
        // The grace period ends with the screen lock and with sleep.
        let workspace = NSWorkspace.shared.notificationCenter
        let names: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")),
        ]
        observerTasks = names.map { center, name in
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    self?.gate.lock()
                }
            }
        }
    }

    /// Turns the lock on, or off after an authentication.
    func setEnabled(_ isOn: Bool) {
        guard isOn != isEnabled else {
            return
        }
        if isOn {
            gate.lock()
            isEnabled = true
        } else {
            authenticate { [weak self] in
                self?.isEnabled = false
            }
        }
    }

    /// Runs `proceed` at once when no authentication is needed, or after the user answered.
    /// Nothing runs when the answer is no.
    func authenticate(then proceed: @escaping @MainActor () -> Void) {
        guard requiresAuthentication else {
            proceed()
            return
        }
        guard !isAuthenticating else {
            return
        }
        isAuthenticating = true
        appState?.activate(for: .settings)
        Task {
            let context = LAContext()
            var error: NSError?
            var isApproved = true
            // A Mac that cannot ask (no password set) must not lock the user out.
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                let reason = String(localized: "Show your hidden menu bar items")
                isApproved = (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
            }
            isAuthenticating = false
            if isApproved {
                gate.unlock(now: .now)
                proceed()
            } else {
                logger.notice("The hidden items stay hidden: not authenticated")
            }
        }
    }
}
