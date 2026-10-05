//
//  AppPermissions.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// A type that manages the permissions of the app.
@MainActor
@Observable
final class AppPermissions {
    /// Keys to access individual permissions.
    enum PermissionKey {
        case accessibility
        case screenRecording
    }

    /// The state of the app's granted permissions.
    enum PermissionsState {
        case missing
        case hasAll
        case hasRequired
    }

    /// The manager's logger.
    @ObservationIgnored let logger = Logger(category: "Permissions")

    /// The permission for Accessibility features.
    let accessibility = AccessibilityPermission()

    /// The permission for Screen Recording features.
    let screenRecording = ScreenRecordingPermission()

    /// The state of the app's granted permissions.
    private(set) var permissionsState: PermissionsState = .missing

    /// Observes the permissions to update ``permissionsState``.
    @ObservationIgnored private var observer: ObservationLoop?

    /// Checks the permissions again whenever holzBar becomes active.
    @ObservationIgnored private var activationObserver: Task<Void, Never>?

    /// The permissions required for full app functionality.
    var allPermissions: [Permission] {
        [accessibility, screenRecording]
    }

    /// The permissions required for basic app functionality.
    var requiredPermissions: [Permission] {
        allPermissions.filter { $0.isRequired }
    }

    /// Creates a new permissions manager.
    init() {
        self.updatePermissionsState()
        let permissions = allPermissions
        self.observer = ObservationLoop.observe {
            permissions.map(\.hasPermission)
        } onChange: { [weak self] _ in
            self?.updatePermissionsState()
        }
        self.activationObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                self?.refresh()
            }
        }
    }

    /// Checks every permission again (see ``Permission/refresh()``).
    func refresh() {
        for permission in allPermissions {
            permission.refresh()
        }
    }

    /// Updates the current permissions state.
    private func updatePermissionsState() {
        let state: PermissionsState
        if allPermissions.allSatisfy({ $0.hasPermission }) {
            state = .hasAll
        } else if requiredPermissions.allSatisfy({ $0.hasPermission }) {
            state = .hasRequired
        } else {
            state = .missing
        }
        if permissionsState != state {
            permissionsState = state
        }
    }

    /// Stops running all permissions checks.
    func stopAllChecks() {
        logger.info("Stopping all permissions checks")
        for permission in allPermissions {
            permission.stopCheck()
        }
    }
}
