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
    ///
    /// - Parameter returningFocus: Whether the app the user was in gets the keyboard back
    ///   after the answer (approved or not), so typing goes on without a click. holzBar comes
    ///   to the front for the prompt; a reveal that takes no keys itself (the bar, the Shelf
    ///   opened by the pointer) gives the focus back, a search or the palette keeps it.
    func authenticate(returningFocus: Bool = false, then proceed: @escaping @MainActor () -> Void) {
        guard requiresAuthentication else {
            proceed()
            return
        }
        guard !isAuthenticating else {
            return
        }
        isAuthenticating = true
        // The app the user was in, and whether holzBar had no Dock icon. Its name is never
        // logged.
        let current = NSRunningApplication.current
        let previous = returningFocus
            ? NSWorkspace.shared.frontmostApplication.flatMap { $0.processIdentifier == current.processIdentifier ? nil : $0 }
            : nil
        let hadNoDockIcon = NSApp.activationPolicy() == .accessory
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
            // Before the reveal, so the reveal happens as it does without the lock.
            if let previous {
                giveFocusBack(to: previous, hadNoDockIcon: hadNoDockIcon)
            }
            if isApproved {
                gate.unlock(now: .now)
                proceed()
            } else {
                logger.notice("The hidden items stay hidden: not authenticated")
            }
        }
    }

    /// Gives the keyboard back to the app the user was in before the prompt, unless Settings
    /// is open, and takes away the Dock icon the prompt may have brought (pre27-L3).
    private func giveFocusBack(to application: NSRunningApplication, hadNoDockIcon: Bool) {
        guard
            let appState,
            !appState.navigationState.isSettingsPresented,
            !application.isTerminated
        else {
            return
        }
        application.activate(from: NSRunningApplication.current)
        if hadNoDockIcon {
            appState.hideDockIconIfUnneeded()
        }
    }
}
