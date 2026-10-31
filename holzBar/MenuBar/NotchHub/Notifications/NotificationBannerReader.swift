//
//  NotificationBannerReader.swift
//  holzBar
//

@preconcurrency import ApplicationServices
import AppKit
import Foundation
import Observation

/// Reads the banners that macOS shows, through one Accessibility observer on the Notification
/// Center process. It is the only place the Notifications module touches the system.
///
/// There is no public way to read other apps' notifications. What holzBar can do within the
/// permission it already requires is to watch the process that draws the banners. The reader
/// registers one `AXObserver` on that process for the notifications that delivered an event in
/// the spike (`AXWindowCreated`, `AXCreated` and `AXLayoutChanged`). When one fires it copies the
/// fired element's subtree into plain ``AXSnapshot`` values on a utility queue, never on the main
/// thread, and hands the cleaned snapshot to its owner. Nothing is read between banners, and
/// nothing is polled.
///
/// Every call into the other process waits at most ``messagingTimeout`` seconds, and a read gives
/// up after ``readDeadline``. Registering asks the process and runs on its own queue for the same
/// reason as in `ItemChangeObserver27`: a busy process must not hold the main thread. A
/// registration that fails is tried again as `ObserverRegistrationSchedule27` decides, by one
/// one-shot wait, and the reader registers again when Notification Center is relaunched and lets
/// go of the observer when it quits. ``stop()`` removes the observer and cancels every task.
///
/// The text of a notification is the most personal text holzBar handles. It passes through here
/// as values, is never logged, and is not kept after the owner has taken it.
@MainActor
@Observable
final class NotificationBannerReader {
    /// What the reader is doing, as the tab says it.
    enum State: Equatable {
        /// It has been started and has not finished registering.
        case registering
        /// The observer is registered; banners are read.
        case running
        /// Accessibility is not granted.
        case noPermission
        /// Notification Center is not running.
        case notificationCenterMissing
        /// macOS did not let holzBar observe Notification Center.
        case unavailable
    }

    /// The bundle identifier of the process that draws the banners, as the spike's TARGET line
    /// recorded it on macOS 27.2.
    nonisolated static let bundleIdentifier = "com.apple.notificationcenterui"

    /// The Accessibility notifications that delivered an event for a banner in the spike.
    private nonisolated static let notificationNames = [
        kAXWindowCreatedNotification,
        kAXCreatedNotification,
        kAXLayoutChangedNotification,
    ]

    /// How long each call into the Notification Center process waits for an answer.
    private nonisolated static let messagingTimeout: Float = 0.25

    /// How long the copy of one subtree may take before it stops, in nanoseconds.
    private nonisolated static let readDeadline: UInt64 = 2_000_000_000

    /// The queue the registration runs on.
    private nonisolated static let registrationQueue = DispatchQueue(
        label: "com.holzcloud.holzBar.NotificationBannerReader.registration",
        qos: .utility
    )

    /// The queue the subtrees are copied on, one at a time.
    private nonisolated static let readQueue = DispatchQueue(
        label: "com.holzcloud.holzBar.NotificationBannerReader.read",
        qos: .utility
    )

    /// What the reader is doing.
    private(set) var state = State.registering

    @ObservationIgnored private var onSnapshot: (@MainActor (AXSnapshot) -> Void)?
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var observer: AXObserver?
    @ObservationIgnored private var observedProcess: pid_t?
    @ObservationIgnored private var sink: BannerEventSink?
    @ObservationIgnored private var isRegistering = false
    @ObservationIgnored private var schedule = ObserverRegistrationSchedule27()
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var launchTask: Task<Void, Never>?
    @ObservationIgnored private var terminateTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// Starts reading. `onSnapshot` is called on the main actor with the cleaned snapshot of
    /// every element that fired, banner or not; the owner decides what it is.
    func start(onSnapshot: @escaping @MainActor (AXSnapshot) -> Void) {
        guard !isStarted else {
            return
        }
        isStarted = true
        self.onSnapshot = onSnapshot
        let center = NSWorkspace.shared.notificationCenter
        launchTask = Task { [weak self] in
            for await notification in center.notifications(named: NSWorkspace.didLaunchApplicationNotification) {
                let launched = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if launched?.bundleIdentifier == Self.bundleIdentifier {
                    self?.attach()
                }
            }
        }
        terminateTask = Task { [weak self] in
            for await notification in center.notifications(named: NSWorkspace.didTerminateApplicationNotification) {
                let quit = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if quit?.bundleIdentifier == Self.bundleIdentifier {
                    self?.notificationCenterDidQuit()
                }
            }
        }
        attach()
    }

    /// Stops reading: removes the observer, cancels every task and forgets the owner.
    func stop() {
        isStarted = false
        generation &+= 1
        launchTask?.cancel()
        launchTask = nil
        terminateTask?.cancel()
        terminateTask = nil
        retryTask?.cancel()
        retryTask = nil
        registrationTask?.cancel()
        registrationTask = nil
        isRegistering = false
        detach()
        onSnapshot = nil
        schedule = ObserverRegistrationSchedule27()
        failures = 0
    }

    /// Reads the permission and the process again, for the case that Accessibility was granted or
    /// withdrawn while the reader runs.
    func permissionDidChange() {
        guard isStarted else {
            return
        }
        if AXIsProcessTrusted() {
            attach()
        } else {
            detach()
            state = .noPermission
        }
    }

    // MARK: Registration

    private static func notificationCenter() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    }

    /// Registers the observer when it can be, and says why when it cannot.
    private func attach() {
        guard isStarted, observer == nil, !isRegistering else {
            return
        }
        guard AXIsProcessTrusted() else {
            state = .noPermission
            return
        }
        guard let application = Self.notificationCenter() else {
            state = .notificationCenterMissing
            return
        }
        let process = application.processIdentifier
        let now = ProcessInfo.processInfo.systemUptime
        guard schedule.allowsRegistration(of: process, now: now) else {
            // Its pause is not over: the one-shot wait comes back when it is.
            scheduleRetry()
            return
        }
        state = .registering
        isRegistering = true
        let sink = BannerEventSink(reader: self)
        let token = generation
        // The sink travels as a number: it is only turned back into a pointer by the callback,
        // and the reader keeps the sink alive for as long as the observer exists.
        let context = Int(bitPattern: Unmanaged.passUnretained(sink).toOpaque())
        registrationTask = Task { [weak self] in
            let registration = await Self.makeRegistration(for: process, context: context)
            self?.finishRegistration(registration, process: process, sink: sink, token: token)
        }
    }

    private func finishRegistration(_ registration: Registration, process: pid_t, sink: BannerEventSink, token: Int) {
        guard token == generation, isStarted else {
            // The reader stopped meanwhile; the observer was never given a run-loop source.
            return
        }
        isRegistering = false
        schedule.record(registration.outcome, for: process, now: ProcessInfo.processInfo.systemUptime)
        guard let observer = registration.observer else {
            state = .unavailable
            if registration.outcome != .unsupported {
                failures += 1
                scheduleRetry()
            }
            return
        }
        failures = 0
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        observedProcess = process
        self.sink = sink
        state = .running
    }

    /// Waits once, as long as the schedule pauses a process that did not answer (the first pause,
    /// doubled for each failure up to the longest), then registers again.
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

    private func notificationCenterDidQuit() {
        detach()
        if isStarted, AXIsProcessTrusted() {
            state = .notificationCenterMissing
        }
    }

    /// Removes the run-loop source and lets go of the observer.
    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedProcess = nil
        sink = nil
    }

    // MARK: Events

    /// An element that fired. Accessibility elements are references that any thread may use.
    private nonisolated struct FiredElement: @unchecked Sendable {
        let element: AXUIElement
    }

    /// Called on the main thread by the observer's callback.
    fileprivate func elementDidFire(_ element: AXUIElement) {
        guard isStarted else {
            return
        }
        let fired = FiredElement(element: element)
        let token = generation
        // One short task per event; it ends when the copy ends, and its result is dropped when
        // the reader was stopped meanwhile.
        Task { [weak self] in
            let snapshot = await Self.copySnapshot(of: fired)
            self?.deliver(snapshot, token: token)
        }
    }

    private func deliver(_ snapshot: AXSnapshot, token: Int) {
        guard isStarted, token == generation else {
            return
        }
        onSnapshot?(snapshot)
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
        guard AXObserverCreate(process, bannerObserverCallback, &created) == .success, let observer = created else {
            return Registration(observer: nil, outcome: .timedOut)
        }
        let application = AXUIElementCreateApplication(process)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        let pointer = UnsafeMutableRawPointer(bitPattern: context)
        var results = [AXError]()
        for name in notificationNames {
            let result = AXObserverAddNotification(observer, application, name as CFString, pointer)
            results.append(result)
            // A process that did not answer once would cost the next wait too.
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

    private nonisolated static func copySnapshot(of fired: FiredElement) async -> AXSnapshot {
        await withCheckedContinuation { continuation in
            readQueue.async {
                continuation.resume(returning: snapshot(of: fired.element))
            }
        }
    }

    /// Copies the element's subtree, to the caps of ``AXSnapshot`` and before the deadline, and
    /// cleans it. Runs on the read queue.
    private nonisolated static func snapshot(of element: AXUIElement) -> AXSnapshot {
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        let deadline = DispatchTime.now().uptimeNanoseconds + readDeadline
        var count = 0
        let root = node(of: element, depth: 0, count: &count, deadline: deadline) ?? AXSnapshot.Node()
        return AXSnapshot.normalized(root)
    }

    private nonisolated static func node(
        of element: AXUIElement,
        depth: Int,
        count: inout Int,
        deadline: UInt64
    ) -> AXSnapshot.Node? {
        guard depth <= AXSnapshot.maximumDepth, count < AXSnapshot.maximumNodes else {
            return nil
        }
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            return nil
        }
        count += 1
        var node = AXSnapshot.Node(
            role: string(element, kAXRoleAttribute),
            subrole: string(element, kAXSubroleAttribute),
            identifier: string(element, kAXIdentifierAttribute),
            text: [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute]
                .lazy
                .compactMap { string(element, $0) }
                .first { !$0.isEmpty }
        )
        if depth < AXSnapshot.maximumDepth {
            for child in elements(element, kAXChildrenAttribute) {
                guard let copied = Self.node(of: child, depth: depth + 1, count: &count, deadline: deadline) else {
                    break
                }
                node.children.append(copied)
            }
        }
        return node
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private nonisolated static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return []
        }
        return value as? [AXUIElement] ?? []
    }
}

/// The object the observer's callback finds through its context pointer. It holds the reader
/// weakly, so a callback that outlives the reader reaches nothing.
private final class BannerEventSink {
    weak var reader: NotificationBannerReader?

    init(reader: NotificationBannerReader) {
        self.reader = reader
    }
}

/// The observer's callback; it runs on the main run loop, where the reader lives. The context
/// is the unretained sink that `attach()` made; the reader keeps it alive for as long as the
/// observer's source is on the run loop.
nonisolated private func bannerObserverCallback(
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
        let sink = Unmanaged<BannerEventSink>.fromOpaque(pointer).takeUnretainedValue()
        sink.reader?.elementDidFire(element)
    }
}
