//
//  ItemChangeObserver27.swift
//  holzBar
//

import ApplicationServices
import Cocoa

nonisolated extension Notification.Name {
    /// Posted on the main thread when a process that owns menu bar items created or
    /// destroyed an Accessibility element, so its items may have changed. The user info
    /// holds the process identifier under `"pid"`.
    static let menuBarItemsMayHaveChanged27 = Notification.Name("com.holzcloud.holzBar.MenuBarItemsMayHaveChanged27")
}

/// Notices when the processes that own menu bar items change their items on macOS 27,
/// so the item list is read again on an event instead of on a timer.
///
/// One `AXObserver` per owning process (the owners of the last item list) listens for
/// `kAXCreatedNotification` and `kAXUIElementDestroyedNotification` on the application
/// element; its run-loop source runs on the main run loop. The callback posts
/// `menuBarItemsMayHaveChanged27`, which `MenuBarItemManager` debounces into a refresh.
///
/// Trade-off: an item that appears without an application launch (a running app adding
/// a second item) is found within seconds when its process posts one of these
/// notifications; otherwise within the manager's 60 s fallback. Launches and quits are
/// seen through `NSWorkspace.runningApplications` as before.
@MainActor
final class ItemChangeObserver27 {
    /// The observers, by process identifier.
    private var observers = [pid_t: AXObserver]()

    /// Observes exactly the given processes: adds observers for new owners and removes
    /// those of processes that own no items any more or have quit.
    func observe(owners pids: Set<pid_t>) {
        for pid in observers.keys where !pids.contains(pid) {
            removeObserver(for: pid)
        }
        for pid in pids where observers[pid] == nil {
            addObserver(for: pid)
        }
    }

    /// Removes every observer.
    func removeAll() {
        for pid in observers.keys {
            removeObserver(for: pid)
        }
    }

    private func addObserver(for pid: pid_t) {
        var created: AXObserver?
        guard AXObserverCreate(pid, itemChangeObserverCallback, &created) == .success, let observer = created else {
            return
        }
        let application = AXUIElementCreateApplication(pid)
        // The process identifier travels as the context pointer (it is never 0 here).
        let context = UnsafeMutableRawPointer(bitPattern: Int(pid))
        let added = [kAXCreatedNotification, kAXUIElementDestroyedNotification].filter { notification in
            AXObserverAddNotification(observer, application, notification as CFString, context) == .success
        }
        guard !added.isEmpty else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else {
            return
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// The observers' callback; it runs on the main run loop.
nonisolated private func itemChangeObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    let pid = context.map { pid_t(truncatingIfNeeded: Int(bitPattern: $0)) } ?? 0
    NotificationCenter.default.post(name: .menuBarItemsMayHaveChanged27, object: nil, userInfo: ["pid": pid])
}
