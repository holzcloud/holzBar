//
//  ItemChangeObserver27.swift
//  holzBar
//

@preconcurrency import ApplicationServices
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
/// Registering asks the process, and a busy one (often one that just launched) would hold
/// the main thread, and with it SystemItemClickBridge27's click tap and every click on the
/// Mac, so it runs on ``registrationQueue`` and waits ``messagingTimeout`` per call. A
/// registration that failed is tried again on a later refresh, as
/// `ObserverRegistrationSchedule27` decides.
///
/// Trade-off: an item that appears without an application launch (a running app adding
/// a second item) is found within seconds when its process posts one of these
/// notifications; otherwise within the manager's 60 s fallback. Launches and quits are
/// seen through `NSWorkspace.runningApplications` as before.
@MainActor
final class ItemChangeObserver27 {
    /// The queue the registrations run on, one at a time. It is not `MenuBarItemProvider27`'s
    /// queue: clicks, the concealer, the image store and the item cache wait for that one.
    private nonisolated static let registrationQueue = DispatchQueue(
        label: "com.holzcloud.holzBar.ItemChangeObserver27",
        qos: .utility
    )

    /// How long each registration call waits for the process to answer. It is set on the
    /// observer's own application element, which nothing else uses.
    private nonisolated static let messagingTimeout: Float = 0.25

    /// The observers, by process identifier.
    private var observers = [pid_t: AXObserver]()

    /// The processes whose registration is under way.
    private var pending = Set<pid_t>()

    /// The processes to observe, from the last call to ``observe(owners:)``.
    private var wanted = Set<pid_t>()

    /// When failed registrations are tried again.
    private var schedule = ObserverRegistrationSchedule27()

    /// Counts ``removeAll()`` calls, so registrations under way before one are discarded.
    private var generation = 0

    /// Observes exactly the given processes: adds observers for new owners and removes
    /// those of processes that own no items any more or have quit.
    func observe(owners pids: Set<pid_t>) {
        wanted = pids
        for pid in observers.keys where !pids.contains(pid) {
            removeObserver(for: pid)
        }
        if !schedule.isEmpty {
            schedule.retain(running: Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)))
        }
        let now = ProcessInfo.processInfo.systemUptime
        for pid in pids where observers[pid] == nil && !pending.contains(pid) {
            guard schedule.allowsRegistration(of: pid, now: now) else {
                continue
            }
            register(pid)
        }
    }

    /// Removes every observer and discards the registrations under way.
    func removeAll() {
        generation += 1
        pending.removeAll()
        wanted.removeAll()
        for pid in observers.keys {
            removeObserver(for: pid)
        }
    }

    /// Registers an observer for the process off the main thread and adds it when it is
    /// still wanted.
    private func register(_ pid: pid_t) {
        pending.insert(pid)
        let generation = generation
        Task { [weak self] in
            let registration = await Self.makeObserver(for: pid)
            self?.finish(registration, for: pid, generation: generation)
        }
    }

    private func finish(_ registration: Registration, for pid: pid_t, generation: Int) {
        // After `removeAll()` the result is dropped, and the observer with it.
        guard generation == self.generation else {
            return
        }
        pending.remove(pid)
        schedule.record(registration.outcome, for: pid, now: ProcessInfo.processInfo.systemUptime)
        guard let observer = registration.observer, wanted.contains(pid), observers[pid] == nil else {
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

    // MARK: Registration

    /// The result of a registration: the observer, when a notification was added, and how
    /// it ended. Observers are references that any thread may use; this one is not used
    /// again on the registration queue once it is handed over.
    private nonisolated struct Registration: @unchecked Sendable {
        let observer: AXObserver?
        let outcome: ObserverRegistrationSchedule27.Outcome
    }

    private nonisolated static func makeObserver(for pid: pid_t) async -> Registration {
        await withCheckedContinuation { continuation in
            registrationQueue.async {
                continuation.resume(returning: registration(for: pid))
            }
        }
    }

    /// Creates the observer and adds the notifications; runs on the registration queue.
    private nonisolated static func registration(for pid: pid_t) -> Registration {
        var created: AXObserver?
        guard AXObserverCreate(pid, itemChangeObserverCallback, &created) == .success, let observer = created else {
            return Registration(observer: nil, outcome: .timedOut)
        }
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        // The process identifier travels as the context pointer (it is never 0 here).
        let context = UnsafeMutableRawPointer(bitPattern: Int(pid))
        var results = [AXError]()
        for notification in [kAXCreatedNotification, kAXUIElementDestroyedNotification] {
            let result = AXObserverAddNotification(observer, application, notification as CFString, context)
            results.append(result)
            // A process that did not answer once would cost the second wait too.
            if result == .cannotComplete {
                break
            }
        }
        if results.contains(.success) {
            return Registration(observer: observer, outcome: .registered)
        }
        let unsupported: Set<AXError> = [.notificationUnsupported, .notImplemented]
        if results.allSatisfy(unsupported.contains) {
            return Registration(observer: nil, outcome: .unsupported)
        }
        return Registration(observer: nil, outcome: .timedOut)
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
