//
//  EventTap.swift
//  holzBar
//

import Cocoa
import OSLog
import os

/// An object that receives events from a defined point in
/// the event stream.
final class EventTap {
    /// Constants that specify the possible insertion points
    /// for event taps.
    enum Location {
        /// The point where HID system events enter the window
        /// server.
        case hidEventTap

        /// The point where HID system and remote control events
        /// enter a login session.
        case sessionEventTap

        /// The point for session events that have been annotated
        /// to flow to an application.
        case annotatedSessionEventTap

        /// The point where events are delivered to the process
        /// with the specified identifier.
        case pid(pid_t)

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .hidEventTap: "HID event tap"
            case .sessionEventTap: "session event tap"
            case .annotatedSessionEventTap: "annotated session event tap"
            case .pid(let pid): "PID \(pid)"
            }
        }
    }

    /// Which run loop delivers a tap's events to its callback.
    ///
    /// A callback that runs on the main run loop times out (macOS disables the tap) whenever
    /// the main thread is busy. A tap on its own thread answers in microseconds whatever the
    /// main thread does. Only the macOS 27 click bridge uses ``ownThread(name:)`` (D-05); every
    /// other tap stays on the main run loop.
    nonisolated enum RunLoopChoice: Equatable, Sendable {
        /// The main run loop, where every tap runs unless it asks otherwise.
        case main

        /// A thread of the tap's own with the given name, started with the tap and ended
        /// with it.
        case ownThread(name: String)
    }

    /// What a tap does after macOS disabled it (a callback that took too long, or user input).
    nonisolated enum DisabledAction: Sendable {
        /// Enable the tap again. This is what a tap without a handler does.
        case reenable

        /// Leave the tap off.
        case stop
    }

    /// Shared logger for event taps.
    private static let logger = Logger(category: "EventTap")

    /// Shared callback for all event taps.
    private static let sharedCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let unretained: EventTap = Unmanaged.fromOpaque(refcon).takeUnretainedValue()
        return withExtendedLifetime(unretained) { tap in
            if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
                tap.mainDisableCount += 1
                switch tap.disabledHandler?(type) ?? .reenable {
                case .reenable:
                    tap.enable()
                case .stop:
                    tap.disable()
                }
                return nil
            }
            guard tap.isEnabled else {
                return Unmanaged.passUnretained(event)
            }
            return tap.callback(tap, event).map { eventFromCallback in
                Unmanaged.passUnretained(eventFromCallback)
            }
        }
    }

    /// The tap's mach port and run loop source, which remove themselves when released.
    private var resources: Resources?
    private let callback: (EventTap, CGEvent) -> CGEvent?

    /// The state a tap with its own callback path (``init(label:types:location:placement:option:runLoop:disabledHandler:callback:)``)
    /// shares with the thread that runs the callback; `nil` for every other tap.
    private let threaded: ThreadedContext?

    /// Which run loop the tap's source is added to.
    private let runLoopChoice: RunLoopChoice

    /// Asked what to do when macOS disables the tap; `nil` enables it again.
    private let disabledHandler: ((CGEventType) -> DisabledAction)?

    /// How many times macOS disabled the tap since it was created, on the main run loop.
    private var mainDisableCount = 0

    /// How many times macOS disabled the tap since it was created.
    var disableCount: Int {
        threaded?.disableCount ?? mainDisableCount
    }

    /// The events the tap receives.
    private let mask: CGEventMask

    /// Where the tap is inserted into the event stream.
    private let location: Location

    /// The tap's placement, relative to other taps at its location.
    private let placement: CGEventTapPlacement

    /// Whether the tap filters events or only listens.
    private let option: CGEventTapOptions

    /// A string label that identifies the tap.
    let label: String

    /// A Boolean value that indicates whether the tap is actively
    /// listening for events.
    var isEnabled: Bool {
        guard let resources else { return false }
        return CGEvent.tapIsEnabled(tap: resources.machPort)
    }

    /// A Boolean value that indicates whether the tap is valid and
    /// able to receive events.
    var isValid: Bool {
        guard let resources else { return false }
        return CFMachPortIsValid(resources.machPort)
    }

    /// Creates a new event tap for the specified event types.
    ///
    /// If the tap is an active filter, the callback can return
    /// one of the following:
    ///
    ///   * The (possibly modified) received event to pass back to
    ///     the event stream.
    ///   * A new event to pass to the event stream in place of the
    ///     received event.
    ///   * `nil` to remove the received event from the event stream.
    ///
    /// If the tap is a passive listener, the callback's return value
    /// does not affect the event stream.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging
    ///     and debugging contexts.
    ///   - types: The event types monitored by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement, relative to existing taps
    ///     at `location`.
    ///   - option: An option that specifies whether the tap is an
    ///     active filter or a passive listener.
    ///   - disabledHandler: A closure the tap calls when macOS disables it, which says
    ///     whether to enable it again. Without one the tap is enabled again.
    ///   - callback: A closure the tap calls to handle received events.
    init(
        label: String = #function,
        types: [CGEventType],
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        disabledHandler: ((CGEventType) -> DisabledAction)? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
        self.disabledHandler = disabledHandler
        self.threaded = nil
        self.runLoopChoice = .main
        self.mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        self.location = location
        self.placement = placement
        self.option = option
        self.resources = makeResources()
    }

    /// Creates a new event tap whose callback runs on the run loop of `runLoop`, which can be a
    /// thread of the tap's own.
    ///
    /// This is the path of the macOS 27 click bridge (D-05) and of nothing else. The callback
    /// and the handler are `@Sendable` and run off the main actor when `runLoop` is
    /// ``RunLoopChoice/ownThread(name:)``: they must read no main-actor state (no app state,
    /// no screens, no application object). With Swift 6 and main-actor default isolation, a
    /// callback that touches such state gets executor checks that either trap or hop to a busy
    /// main thread, which is the very wait the own thread avoids. Anything that needs the main
    /// actor happens in a task the callback starts after it has decided.
    ///
    /// The callback returns the event to pass on, a different event, or `nil` to remove it. The
    /// handler is asked when macOS disables the tap, on the tap's thread; the tap enables itself
    /// again or stays off as it answers.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging and debugging contexts.
    ///   - types: The event types monitored by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement, relative to existing taps at `location`.
    ///   - option: An option that specifies whether the tap is an active filter or a passive
    ///     listener.
    ///   - runLoop: Where the callback runs. A thread that cannot be started falls back to the
    ///     main run loop.
    ///   - disabledHandler: Says whether to enable the tap again after macOS disabled it.
    ///   - callback: A closure the tap calls to handle received events.
    init(
        label: String = #function,
        types: [CGEventType],
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        runLoop: RunLoopChoice,
        disabledHandler: @escaping @Sendable (CGEventType) -> DisabledAction,
        callback: @escaping @Sendable (CGEvent) -> CGEvent?
    ) {
        self.label = label
        // The main run loop's path is not used by this tap; the threaded callback is.
        self.callback = { _, event in event }
        self.disabledHandler = nil
        self.threaded = ThreadedContext(callback: callback, disabledHandler: disabledHandler)
        self.runLoopChoice = runLoop
        self.mask = types.reduce(0) { $0 | (1 << $1.rawValue) }
        self.location = location
        self.placement = placement
        self.option = option
        self.resources = makeResources()
    }

    /// Creates a new event tap for the specified event type.
    ///
    /// If the tap is an active filter, the callback can return
    /// one of the following:
    ///
    ///   * The (possibly modified) received event to pass back to
    ///     the event stream.
    ///   * A new event to pass to the event stream in place of the
    ///     received event.
    ///   * `nil` to remove the received event from the event stream.
    ///
    /// If the tap is a passive listener, the callback's return value
    /// does not affect the event stream.
    ///
    /// - Parameters:
    ///   - label: A string label that identifies the tap in logging
    ///     and debugging contexts.
    ///   - type: The event type monitored by the tap.
    ///   - location: The point in the event stream to insert the tap.
    ///   - placement: The tap's placement, relative to existing taps
    ///     at `location`.
    ///   - option: An option that specifies whether the tap is an
    ///     active filter or a passive listener.
    ///   - disabledHandler: A closure the tap calls when macOS disables it, which says
    ///     whether to enable it again. Without one the tap is enabled again.
    ///   - callback: A closure the tap calls to handle received events.
    convenience init(
        label: String = #function,
        type: CGEventType,
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        disabledHandler: ((CGEventType) -> DisabledAction)? = nil,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.init(
            label: label,
            types: [type],
            location: location,
            placement: placement,
            option: option,
            disabledHandler: disabledHandler,
            callback: callback
        )
    }

    /// Creates the tap's mach port and run loop source, or returns `nil` when macOS refuses
    /// the tap (before Accessibility is granted, for one).
    private func makeResources() -> Resources? {
        let userInfo: UnsafeMutableRawPointer
        if let threaded {
            userInfo = Unmanaged.passUnretained(threaded).toOpaque()
        } else {
            userInfo = Unmanaged.passUnretained(self).toOpaque()
        }
        guard
            let machPort = EventTap.createMachPort(
                mask: mask,
                location: location,
                place: placement,
                options: option,
                callback: threaded == nil ? EventTap.sharedCallback : EventTap.threadedCallback,
                userInfo: userInfo
            ),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            EventTap.logger.error(#"Error creating event tap "\#(self.label, privacy: .public)""#)
            return nil
        }
        threaded?.setPort(machPort)
        // The thread starts only once macOS accepted the tap, so a tap that is refused over and
        // over (no Accessibility) does not start and end a thread each time.
        var tapThread: TapThread?
        if case .ownThread(let name) = runLoopChoice {
            tapThread = TapThread(name: name)
            if tapThread == nil {
                EventTap.logger.error(
                    #"Event tap "\#(self.label, privacy: .public)" could not start its thread, using the main run loop"#
                )
            }
        }
        return Resources(
            machPort: machPort,
            source: source,
            runLoop: tapThread?.runLoop ?? CFRunLoopGetMain(),
            thread: tapThread,
            keepAlive: tapThread == nil ? nil : threaded
        )
    }

    /// Creates the tap's mach port again when it is missing or no longer valid.
    ///
    /// A tap created before Accessibility was granted has no port for the rest of the
    /// session otherwise, and macOS can invalidate a port (after the permission changes,
    /// for one).
    ///
    /// - Returns: `true` when a new port was created.
    @discardableResult
    func recreateIfInvalid() -> Bool {
        if let resources, CFMachPortIsValid(resources.machPort) {
            return false
        }
        // Releasing the old resources takes the old port out of the event stream.
        resources = nil
        resources = makeResources()
        guard resources != nil else {
            return false
        }
        EventTap.logger.info(#"Recreated event tap "\#(self.label, privacy: .public)""#)
        return true
    }

    /// Creates an event tap mach port.
    private static func createMachPort(
        mask: CGEventMask,
        location: Location,
        place: CGEventTapPlacement,
        options: CGEventTapOptions,
        callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> CFMachPort? {
        func createMachPort(at tapLocation: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: tapLocation,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            )
        }

        func createMachPort(for pid: pid_t) -> CFMachPort? {
            CGEvent.tapCreateForPid(
                pid: pid,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: userInfo
            )
        }

        switch location {
        case .hidEventTap:
            return createMachPort(at: .cghidEventTap)
        case .sessionEventTap:
            return createMachPort(at: .cgSessionEventTap)
        case .annotatedSessionEventTap:
            return createMachPort(at: .cgAnnotatedSessionEventTap)
        case .pid(let pid):
            return createMachPort(for: pid)
        }
    }

    /// Enables the tap.
    ///
    /// The port is created again first if it is missing or invalid, and the run loop
    /// source is added before the tap is enabled, so the first event after enabling is
    /// delivered.
    func enable() {
        recreateIfInvalid()
        guard let resources else { return }
        CFRunLoopAddSource(resources.runLoop, resources.source, .commonModes)
        // A run loop on another thread may be asleep.
        CFRunLoopWakeUp(resources.runLoop)
        CGEvent.tapEnable(tap: resources.machPort, enable: true)
    }

    /// Disables the tap.
    func disable() {
        guard let resources else { return }
        CFRunLoopRemoveSource(resources.runLoop, resources.source, .commonModes)
        CFRunLoopWakeUp(resources.runLoop)
        CGEvent.tapEnable(tap: resources.machPort, enable: false)
    }
}

// MARK: - EventTap.Resources

extension EventTap {
    /// The mach port and run loop source of a tap.
    ///
    /// They are released with the tap and take the tap out of the event stream when
    /// they are, without the tap's main-actor isolated deinitializer touching them.
    nonisolated private final class Resources {
        let machPort: CFMachPort
        let source: CFRunLoopSource
        let runLoop: CFRunLoop

        /// The tap's own thread, when it has one; it ends with the resources.
        private let thread: TapThread?

        /// The context the thread's callback reads, kept alive until the thread has run its last
        /// callback.
        private let keepAlive: ThreadedContext?

        init(
            machPort: CFMachPort,
            source: CFRunLoopSource,
            runLoop: CFRunLoop,
            thread: TapThread? = nil,
            keepAlive: ThreadedContext? = nil
        ) {
            self.machPort = machPort
            self.source = source
            self.runLoop = runLoop
            self.thread = thread
            self.keepAlive = keepAlive
        }

        deinit {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
            thread?.shutDown(keeping: keepAlive)
        }
    }
}

// MARK: - EventTap.ThreadedContext

extension EventTap {
    /// What the threaded callback of a tap reads: the callback, the handler for a disabled tap,
    /// the tap's port and the disable count.
    ///
    /// It is the tap's `userInfo` and touches nothing of ``EventTap`` itself, which is main-actor
    /// state. The port and the count sit behind a lock; the closures are `@Sendable`.
    nonisolated final class ThreadedContext: @unchecked Sendable {
        /// What changes after creation.
        private struct State {
            var port: CFMachPort?
            var disableCount = 0
        }

        let callback: @Sendable (CGEvent) -> CGEvent?
        let disabledHandler: @Sendable (CGEventType) -> DisabledAction
        private let state = OSAllocatedUnfairLock(uncheckedState: State())

        init(
            callback: @escaping @Sendable (CGEvent) -> CGEvent?,
            disabledHandler: @escaping @Sendable (CGEventType) -> DisabledAction
        ) {
            self.callback = callback
            self.disabledHandler = disabledHandler
        }

        /// How many times macOS disabled the tap.
        var disableCount: Int {
            state.withLock { $0.disableCount }
        }

        /// Gives the context the port of the tap it belongs to, to enable it again.
        func setPort(_ port: CFMachPort) {
            state.withLockUnchecked { $0.port = port }
        }

        /// Counts a disabled tap, asks the handler and enables the tap again or leaves it off.
        func handleDisabled(_ type: CGEventType) {
            let port = state.withLockUnchecked { state -> CFMachPort? in
                state.disableCount += 1
                return state.port
            }
            let action = disabledHandler(type)
            guard let port else { return }
            switch action {
            case .reenable:
                CGEvent.tapEnable(tap: port, enable: true)
            case .stop:
                CGEvent.tapEnable(tap: port, enable: false)
            }
        }
    }

    /// The callback of a tap with its own callback path.
    ///
    /// It must stay `nonisolated` and read no main-actor state: it runs on the tap's thread, and
    /// a main-actor read would wait for the main thread, which is what the own thread is for.
    nonisolated static let threadedCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }
        let context = Unmanaged<ThreadedContext>.fromOpaque(refcon).takeUnretainedValue()
        if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            context.handleDisabled(type)
            return nil
        }
        return context.callback(event).map { Unmanaged.passUnretained($0) }
    }
}

// MARK: - EventTap.TapThread

extension EventTap {
    /// A thread that runs a run loop for one tap, and ends when the tap is released.
    nonisolated final class TapThread: @unchecked Sendable {
        /// Hands the new thread's run loop back to the thread that started it, and tells the
        /// new thread when nobody waits for it any more.
        private final class RunLoopSlot: @unchecked Sendable {
            struct State {
                var runLoop: CFRunLoop?
                var isCancelled = false
            }

            let state = OSAllocatedUnfairLock(uncheckedState: State())
        }

        /// The thread's run loop.
        let runLoop: CFRunLoop

        /// Starts the thread and waits until its run loop runs.
        ///
        /// - Returns: `nil` when the thread did not start within two seconds. A thread that is
        ///   late then ends by itself instead of running for the rest of the session.
        init?(name: String) {
            let slot = RunLoopSlot()
            let ready = DispatchSemaphore(value: 0)
            let thread = Thread {
                guard let loop = CFRunLoopGetCurrent() else {
                    ready.signal()
                    return
                }
                // The run loop returns at once when it has no source, such as after the tap's
                // source is removed by `disable()`; a source that does nothing keeps it running.
                var context = CFRunLoopSourceContext()
                context.perform = { _ in }
                let keepAlive = CFRunLoopSourceCreate(nil, 0, &context)
                if let keepAlive {
                    CFRunLoopAddSource(loop, keepAlive, .defaultMode)
                }
                // Publishing and giving up are decided under one lock, so a thread that comes
                // late sees that the tap went without it.
                let isCancelled = slot.state.withLockUnchecked { state -> Bool in
                    if state.isCancelled {
                        return true
                    }
                    state.runLoop = loop
                    return false
                }
                ready.signal()
                if !isCancelled {
                    CFRunLoopRun()
                }
                if let keepAlive {
                    CFRunLoopRemoveSource(loop, keepAlive, .defaultMode)
                }
            }
            thread.name = name
            thread.qualityOfService = .userInteractive
            thread.start()
            guard
                ready.wait(timeout: .now() + .seconds(2)) == .success,
                let loop = slot.state.withLockUnchecked({ $0.runLoop })
            else {
                // The thread may still be on its way: it gives up when it gets to publish, or,
                // when it already published and is about to run, its run loop is stopped.
                let late = slot.state.withLockUnchecked { state -> CFRunLoop? in
                    state.isCancelled = true
                    return state.runLoop
                }
                if let late {
                    CFRunLoopPerformBlock(late, CFRunLoopMode.commonModes.rawValue) {
                        CFRunLoopStop(CFRunLoopGetCurrent())
                    }
                    CFRunLoopWakeUp(late)
                }
                return nil
            }
            runLoop = loop
        }

        /// Ends the thread after the callbacks already queued on it, and releases `object` there,
        /// so a callback that is still running never finds its context gone.
        func shutDown(keeping object: AnyObject?) {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                withExtendedLifetime(object) {
                    CFRunLoopStop(CFRunLoopGetCurrent())
                }
            }
            CFRunLoopWakeUp(runLoop)
        }
    }
}
