//
//  EventMonitor.swift
//  holzBar
//

import Cocoa
import Combine
import os.lock

/// Monitors events that AppKit delivers to the app (local), to other apps
/// (global) or to both (universal).
///
/// AppKit calls event monitor handlers on the main thread, so the monitor
/// and its handlers are main-actor isolated.
@MainActor
final class EventMonitor {
    /// Scopes where an event monitor can listen for events.
    enum Scope {
        case local
        case global
        case universal
    }

    /// The scope where the monitor listens for events.
    let scope: Scope

    private let mask: NSEvent.EventTypeMask
    private let localHandler: @MainActor (NSEvent) -> NSEvent?
    private let globalHandler: @MainActor (NSEvent) -> Void

    /// The installed AppKit monitors, behind a lock so that the nonisolated
    /// deinitializer can remove them.
    private let monitors = OSAllocatedUnfairLock<[Any]>(uncheckedState: [])

    private init(
        mask: NSEvent.EventTypeMask,
        scope: Scope,
        localHandler: @escaping @MainActor (NSEvent) -> NSEvent?,
        globalHandler: @escaping @MainActor (NSEvent) -> Void
    ) {
        self.mask = mask
        self.scope = scope
        self.localHandler = localHandler
        self.globalHandler = globalHandler
    }

    deinit {
        let installed = monitors.withLockUnchecked { monitors in
            defer {
                monitors.removeAll()
            }
            return monitors
        }
        for monitor in installed {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Installs the monitor and begins listening for events.
    func start() {
        guard monitors.withLockUnchecked({ $0.isEmpty }) else {
            return
        }
        var installed = [Any]()
        if scope != .global {
            let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else {
                    return event
                }
                return localHandler(event)
            }
            guard let local else {
                return
            }
            installed.append(local)
        }
        if scope != .local {
            let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                guard let self else {
                    return
                }
                globalHandler(event)
            }
            guard let global else {
                for monitor in installed {
                    NSEvent.removeMonitor(monitor)
                }
                return
            }
            installed.append(global)
        }
        monitors.withLockUnchecked { $0 = installed }
    }

    /// Uninstalls the monitor and stops listening for events.
    func stop() {
        let installed = monitors.withLockUnchecked { monitors in
            defer {
                monitors.removeAll()
            }
            return monitors
        }
        for monitor in installed {
            NSEvent.removeMonitor(monitor)
        }
    }
}

extension EventMonitor {
    static func local(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        EventMonitor(mask: mask, scope: .local, localHandler: handler) { _ = handler($0) }
    }

    static func global(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) -> EventMonitor {
        EventMonitor(mask: mask, scope: .global, localHandler: { handler($0); return $0 }, globalHandler: handler)
    }

    static func universal(
        for mask: NSEvent.EventTypeMask,
        localHandler: @escaping @MainActor (NSEvent) -> NSEvent?,
        globalHandler: @escaping @MainActor (NSEvent) -> Void
    ) -> EventMonitor {
        EventMonitor(mask: mask, scope: .universal, localHandler: localHandler, globalHandler: globalHandler)
    }

    static func universal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        EventMonitor(mask: mask, scope: .universal, localHandler: handler) { _ = handler($0) }
    }

    static func passive(
        for mask: NSEvent.EventTypeMask,
        scope: Scope,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) -> EventMonitor {
        EventMonitor(mask: mask, scope: scope, localHandler: { handler($0); return $0 }, globalHandler: handler)
    }
}

extension EventMonitor {
    @discardableResult
    static func startLocal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        let monitor = local(for: mask, handler: handler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startGlobal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) -> EventMonitor {
        let monitor = global(for: mask, handler: handler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startUniversal(
        for mask: NSEvent.EventTypeMask,
        localHandler: @escaping @MainActor (NSEvent) -> NSEvent?,
        globalHandler: @escaping @MainActor (NSEvent) -> Void
    ) -> EventMonitor {
        let monitor = universal(for: mask, localHandler: localHandler, globalHandler: globalHandler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startUniversal(
        for mask: NSEvent.EventTypeMask,
        handler: @escaping @MainActor (NSEvent) -> NSEvent?
    ) -> EventMonitor {
        let monitor = universal(for: mask, handler: handler)
        monitor.start()
        return monitor
    }

    @discardableResult
    static func startPassive(
        for mask: NSEvent.EventTypeMask,
        scope: Scope,
        handler: @escaping @MainActor (NSEvent) -> Void
    ) -> EventMonitor {
        let monitor = passive(for: mask, scope: scope, handler: handler)
        monitor.start()
        return monitor
    }
}

extension EventMonitor {
    /// A publisher that emits events received within a defined scope.
    struct EventPublisher: Publisher {
        typealias Output = NSEvent
        typealias Failure = Never

        /// The event type mask that determines the events the publisher receives.
        let mask: NSEvent.EventTypeMask

        /// The scope where the publisher receives events.
        let scope: EventMonitor.Scope

        func receive<S: Subscriber>(subscriber: S) where S.Input == Output, S.Failure == Failure {
            let subscription = EventSubscription(mask: mask, scope: scope, subscriber: subscriber)
            subscriber.receive(subscription: subscription)
        }
    }

    /// Returns a publisher that emits events received within a defined scope.
    ///
    /// - Parameters:
    ///   - events: A mask that determines the events the publisher receives.
    ///   - scope: A scope that determines where the publisher receives events.
    static func publish(events: NSEvent.EventTypeMask, scope: Scope) -> EventPublisher {
        EventPublisher(mask: events, scope: scope)
    }
}

extension EventMonitor.EventPublisher {
    private final class EventSubscription<S: Subscriber>: Subscription where S.Input == Output, S.Failure == Failure {
        private final class SubscriberBox {
            private let subscriber: S

            init(subscriber: S) {
                self.subscriber = subscriber
            }

            @discardableResult
            func receive(_ event: NSEvent) -> Subscribers.Demand {
                subscriber.receive(event)
            }
        }

        private var box: SubscriberBox?
        private let monitor: EventMonitor

        init(mask: NSEvent.EventTypeMask, scope: EventMonitor.Scope, subscriber: S) {
            self.box = SubscriberBox(subscriber: subscriber)
            self.monitor = .startPassive(for: mask, scope: scope) { [weak box] event in
                box?.receive(event)
            }
        }

        func request(_ demand: Subscribers.Demand) { }

        func cancel() {
            box = nil
            monitor.stop()
        }
    }
}
