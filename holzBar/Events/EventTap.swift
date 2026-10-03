//
//  EventTap.swift
//  holzBar
//

import Cocoa
import OSLog

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
                tap.enable()
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
    ///   - callback: A closure the tap calls to handle received events.
    init(
        label: String = #function,
        types: [CGEventType],
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.label = label
        self.callback = callback
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
    ///   - callback: A closure the tap calls to handle received events.
    convenience init(
        label: String = #function,
        type: CGEventType,
        location: Location,
        placement: CGEventTapPlacement,
        option: CGEventTapOptions,
        callback: @escaping (_ tap: EventTap, _ event: CGEvent) -> CGEvent?
    ) {
        self.init(
            label: label,
            types: [type],
            location: location,
            placement: placement,
            option: option,
            callback: callback
        )
    }

    /// Creates the tap's mach port and run loop source, or returns `nil` when macOS refuses
    /// the tap (before Accessibility is granted, for one).
    private func makeResources() -> Resources? {
        guard
            let machPort = EventTap.createMachPort(
                mask: mask,
                location: location,
                place: placement,
                options: option,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ),
            let source = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        else {
            EventTap.logger.error(#"Error creating event tap "\#(label, privacy: .public)""#)
            return nil
        }
        return Resources(machPort: machPort, source: source, runLoop: CFRunLoopGetMain())
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
        EventTap.logger.info(#"Recreated event tap "\#(label, privacy: .public)""#)
        return true
    }

    /// Creates an event tap mach port.
    private static func createMachPort(
        mask: CGEventMask,
        location: Location,
        place: CGEventTapPlacement,
        options: CGEventTapOptions,
        userInfo: UnsafeMutableRawPointer
    ) -> CFMachPort? {
        func createMachPort(at tapLocation: CGEventTapLocation) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: tapLocation,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: sharedCallback,
                userInfo: userInfo
            )
        }

        func createMachPort(for pid: pid_t) -> CFMachPort? {
            CGEvent.tapCreateForPid(
                pid: pid,
                place: place,
                options: options,
                eventsOfInterest: mask,
                callback: sharedCallback,
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
        CGEvent.tapEnable(tap: resources.machPort, enable: true)
    }

    /// Disables the tap.
    func disable() {
        guard let resources else { return }
        CFRunLoopRemoveSource(resources.runLoop, resources.source, .commonModes)
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

        init(machPort: CFMachPort, source: CFRunLoopSource, runLoop: CFRunLoop) {
            self.machPort = machPort
            self.source = source
            self.runLoop = runLoop
        }

        deinit {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: machPort, enable: false)
            CFMachPortInvalidate(machPort)
        }
    }
}
