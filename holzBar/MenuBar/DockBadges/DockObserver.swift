//
//  DockObserver.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import AppKit
import Foundation

/// Tells the Dock badges when the Dock posts an Accessibility notification, through one
/// `AXObserver` on the Dock's process. It reads nothing: the callback hands over the bare fact
/// that the Dock notified (no element, no text), and the owner decides whether a read follows.
///
/// The observer is registered for the public notifications that a change of a badge, a title or an
/// icon can raise (value changed, title changed, created and destroyed), on the Dock's application
/// element and on its list element. Which of them the Dock really posts for a badge on macOS 27.2
/// is for the first run on a Mac to show; ``DockBadgeRefresh`` decides from what arrives whether
/// notifications can drive the reads at all, so a Dock that stays silent costs nothing but the
/// observer itself. It names no undocumented attribute and calls no wrapper.
///
/// Registering asks the Dock process and runs on its own queue, with a 0.25 s messaging timeout, so
/// a busy Dock cannot hold the main thread. A registration that fails is tried again as
/// `ObserverRegistrationSchedule27` decides, by one one-shot wait. A Dock that restarts is a new
/// process: ``dockDidLaunch()`` drops the old observer and every callback of it (a generation
/// number), and registers on the new process; ``dockDidQuit()`` drops it until the Dock is back.
/// ``stop()`` removes the run-loop source and lets go of the observer, which ends every
/// notification, and cancels every task.
@MainActor
final class DockObserver {
    /// The Accessibility notifications a change of the Dock can raise.
    private nonisolated static let notificationNames = [
        kAXValueChangedNotification,
        kAXTitleChangedNotification,
        kAXCreatedNotification,
        kAXUIElementDestroyedNotification,
    ]

    /// How long each call into the Dock process waits for an answer, in seconds.
    private nonisolated static let messagingTimeout: Float = 0.25

    /// The queue the registration runs on.
    private nonisolated static let registrationQueue = DispatchQueue(
        label: "com.holzcloud.holzBar.DockObserver.registration",
        qos: .utility
    )

    private var onNotification: (@MainActor () -> Void)?
    private var isStarted = false
    private var observer: AXObserver?
    private var sink: DockEventSink?
    private var isRegistering = false
    private var schedule = ObserverRegistrationSchedule27()
    private var failures = 0
    private var generation = 0
    private var registrationTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// Starts observing. `onNotification` is called on the main actor each time the Dock posts one
    /// of the notifications; it carries nothing.
    func start(onNotification: @escaping @MainActor () -> Void) {
        guard !isStarted else {
            return
        }
        isStarted = true
        self.onNotification = onNotification
        attach()
    }

    /// Stops observing: removes the observer, cancels every task and forgets the owner.
    func stop() {
        isStarted = false
        generation &+= 1
        cancelTasks()
        detach()
        onNotification = nil
        schedule = ObserverRegistrationSchedule27()
        failures = 0
    }

    /// The Dock launched, so it is a new process: every element and callback of the old one is
    /// dropped and the observer registers on the new one.
    func dockDidLaunch() {
        guard isStarted else {
            return
        }
        generation &+= 1
        cancelTasks()
        detach()
        schedule = ObserverRegistrationSchedule27()
        failures = 0
        attach()
    }

    /// The Dock quit: the observer is dropped until it is back.
    func dockDidQuit() {
        guard isStarted else {
            return
        }
        generation &+= 1
        cancelTasks()
        detach()
    }

    private func cancelTasks() {
        retryTask?.cancel()
        retryTask = nil
        registrationTask?.cancel()
        registrationTask = nil
        isRegistering = false
    }

    // MARK: Registration

    /// Registers the observer when it can be: Accessibility granted and the Dock running.
    private func attach() {
        guard isStarted, observer == nil, !isRegistering, AXIsProcessTrusted() else {
            return
        }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: DockReader.bundleIdentifier).first
        else {
            // Its launch calls ``dockDidLaunch()``.
            return
        }
        let process = dock.processIdentifier
        guard schedule.allowsRegistration(of: process, now: ProcessInfo.processInfo.systemUptime) else {
            // Its pause is not over: the one-shot wait comes back when it is.
            scheduleRetry()
            return
        }
        isRegistering = true
        let sink = DockEventSink(owner: self, generation: generation)
        let token = generation
        // The sink travels as a number: it is only turned back into a pointer by the callback. An
        // AXObserver does not retain its refcon, so the sink stays valid only because
        // `DockObserver.sink` holds it strongly until `detach()` has removed the run-loop source.
        let context = Int(bitPattern: Unmanaged.passUnretained(sink).toOpaque())
        registrationTask = Task { [weak self] in
            let registration = await Self.makeRegistration(for: process, context: context)
            self?.finishRegistration(registration, process: process, sink: sink, token: token)
        }
    }

    private func finishRegistration(_ registration: Registration, process: pid_t, sink: DockEventSink, token: Int) {
        guard token == generation, isStarted else {
            // Stopped, or the Dock restarted, meanwhile; the observer was never given a source.
            return
        }
        isRegistering = false
        schedule.record(registration.outcome, for: process, now: ProcessInfo.processInfo.systemUptime)
        guard let observer = registration.observer else {
            if registration.outcome != .unsupported {
                failures += 1
                scheduleRetry()
            }
            return
        }
        failures = 0
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        self.sink = sink
    }

    /// Waits once, as long as the schedule pauses a process that did not answer, then registers
    /// again.
    private func scheduleRetry() {
        retryTask?.cancel()
        let doubled = ObserverRegistrationSchedule27.firstPause * pow(2, Double(max(failures - 1, 0)))
        let pause = min(doubled, ObserverRegistrationSchedule27.longestPause)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(pause), tolerance: .seconds(1))
            guard !Task.isCancelled else {
                return
            }
            self?.attach()
        }
    }

    /// Removes the run-loop source and lets go of the observer. The source goes first: the sink is
    /// released only after no callback can reach it any more.
    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        sink = nil
    }

    // MARK: Events

    /// Called on the main thread by the observer's callback.
    fileprivate func dockDidNotify(generation token: Int) {
        guard isStarted, token == generation else {
            return
        }
        onNotification?()
    }

    // MARK: Off the main thread

    /// The result of a registration: the observer, when a notification was added, and how it
    /// ended. Observers are references that any thread may use; this one is not used on the
    /// registration queue once it is handed over.
    private nonisolated struct Registration: @unchecked Sendable {
        let observer: AXObserver?
        let outcome: ObserverRegistrationSchedule27.Outcome
    }

    private nonisolated static func makeRegistration(for process: pid_t, context: Int) async -> Registration {
        await withCheckedContinuation { continuation in
            registrationQueue.async {
                continuation.resume(returning: registration(for: process, context: context))
            }
        }
    }

    /// Creates the observer and adds the notifications; runs on the registration queue.
    private nonisolated static func registration(for process: pid_t, context: Int) -> Registration {
        var created: AXObserver?
        guard AXObserverCreate(process, dockObserverCallback, &created) == .success, let observer = created else {
            return Registration(observer: nil, outcome: .timedOut)
        }
        let application = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var elements = [application]
        if let list = listElement(of: application) {
            elements.append(list)
        }
        let pointer = UnsafeMutableRawPointer(bitPattern: context)
        var results = [AXError]()
        search: for element in elements {
            for name in notificationNames {
                let result = AXObserverAddNotification(observer, element, name as CFString, pointer)
                results.append(result)
                // A process that did not answer once would cost the next wait too.
                if result == .cannotComplete {
                    break search
                }
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

    /// The list among the Dock's children, which holds its items.
    private nonisolated static func listElement(of application: AXUIElement) -> AXUIElement? {
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXChildrenAttribute as CFString, &children) == .success,
            let elements = children as? [AXUIElement]
        else {
            return nil
        }
        return elements.first { element in
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success else {
                return false
            }
            return (role as? String) == kAXListRole
        }
    }
}

/// The object the observer's callback finds through its context pointer. It holds the observer
/// weakly, so a callback that outlives it reaches nothing, and the number of the registration it
/// was made for, so a callback of an earlier registration is dropped.
private final class DockEventSink {
    weak var owner: DockObserver?
    let generation: Int

    init(owner: DockObserver, generation: Int) {
        self.owner = owner
        self.generation = generation
    }
}

/// The observer's callback; it runs on the main run loop, where the observer lives. The context is
/// the unretained sink that `attach()` made. An AXObserver does not retain its refcon: the sink
/// is valid only because `DockObserver.sink` holds it until `detach()` has removed the run-loop
/// source, and both happen on the main thread, so the callback never sees a freed sink. The
/// element is not looked at: only the fact that the Dock notified counts.
nonisolated private func dockObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else {
        return
    }
    // The pointer is carried as a number into the main actor's closure.
    let address = Int(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeRawPointer(bitPattern: address) else {
            return
        }
        let sink = Unmanaged<DockEventSink>.fromOpaque(pointer).takeUnretainedValue()
        sink.owner?.dockDidNotify(generation: sink.generation)
    }
}
