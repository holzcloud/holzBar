//
//  TransparencyObserver.swift
//  holzBar
//

import AppKit
import Observation

extension TransparencyOptions {
    /// The system's current Reduce Transparency and Increase Contrast options, read from
    /// `NSWorkspace` (public API, available since macOS 10.10).
    static var system: TransparencyOptions {
        TransparencyOptions(
            reduceTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

/// Follows the system's Reduce Transparency and Increase Contrast options between
/// ``start()`` and ``stop()``.
///
/// It listens to one notification and never polls: nothing runs while it is stopped, and
/// nothing is scheduled while it follows.
@MainActor
@Observable
final class TransparencyObserver {
    /// The options as of the last read.
    private(set) var options = TransparencyOptions.system

    /// The task that follows the change notification, while the observer follows.
    @ObservationIgnored private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    /// Reads the options and follows their change notification. Does nothing if it already follows.
    func start() {
        guard task == nil else {
            return
        }
        refresh()
        // The notification is posted on the workspace's own notification center, not the
        // default one, and carries no payload.
        task = Task { [weak self] in
            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
            for await _ in notifications {
                self?.refresh()
            }
        }
    }

    /// Stops following the notification.
    func stop() {
        task?.cancel()
        task = nil
    }

    /// Reads the options again and stores them only when they differ: every accessibility
    /// display option (Reduce Motion, for one) posts the notification, and what depends on
    /// the options must not render again for those.
    private func refresh() {
        let current = TransparencyOptions.system
        if current != options {
            options = current
        }
    }
}
