//
//  MenuBarItemServiceConnection.swift
//  holzBar
//

import Foundation
import OSLog
import os

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's target queue.
        private let queue: DispatchQueue

        /// The connection's logger.
        private let logger: Logger

        /// A Boolean value that indicates whether the service could not be reached.
        ///
        /// On macOS 26.7.1 the service failed to start for some users, and every
        /// request failed with `XPCRichError` code 1 (the app's own items then went
        /// unrecognised and the layout settings showed "Loading menu bar items…"
        /// forever). Once that happens, the same lookup runs in the app instead, on
        /// its own queue so that its blocking Accessibility calls stay off the main
        /// thread and the concurrency pool.
        private let usesLocalCache = OSAllocatedUnfairLock(initialState: false)

        /// The queue for lookups that run in the app.
        private let localQueue = DispatchQueue(label: "MenuBarItemService.Connection.local", qos: .userInitiated)

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let logger = Logger(category: "MenuBarItemService.Connection")
            self.session = Session(queue: queue, logger: logger)
            self.queue = queue
            self.logger = logger
        }

        /// Starts the connection.
        func start() async {
            logger.debug("Starting MenuBarItemService connection")

            await withCheckedContinuation { continuation in
                guard let response = session.send(request: .start) else {
                    logger.error("Start request returned nil, looking up source processes in the app instead")
                    switchToLocalCache()
                    continuation.resume()
                    return
                }
                if case .start = response {
                    continuation.resume()
                } else {
                    logger.error("Start request returned invalid response \(String(describing: response))")
                    continuation.resume()
                }
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            if usesLocalCache.withLock({ $0 }) {
                return await localSourcePID(for: window)
            }
            let response: MenuBarItemService.Response? = await withCheckedContinuation { continuation in
                continuation.resume(returning: session.send(request: .sourcePID(window)))
            }
            guard let response else {
                logger.error("Source PID request returned nil, looking up source processes in the app instead")
                switchToLocalCache()
                return await localSourcePID(for: window)
            }
            if case .sourcePID(let pid) = response {
                return pid
            }
            logger.error("Source PID request returned invalid response \(String(describing: response))")
            return nil
        }

        /// Stops using the service and looks up source processes in the app.
        private func switchToLocalCache() {
            let isFirstSwitch = usesLocalCache.withLock { usesLocalCache in
                defer { usesLocalCache = true }
                return !usesLocalCache
            }
            guard isFirstSwitch else {
                return
            }
            localQueue.async {
                SourcePIDCache.shared.start()
            }
        }

        /// Looks up the source process of the given window in the app.
        private func localSourcePID(for window: WindowInfo) async -> pid_t? {
            await withCheckedContinuation { continuation in
                localQueue.async {
                    continuation.resume(returning: SourcePIDCache.shared.pid(for: window))
                }
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC session.
    private final class Session: Sendable {
        /// A session's underlying storage.
        private final class Storage: @unchecked Sendable {
            private let name = MenuBarItemService.name
            private var session: XPCSession?
            private let queue: DispatchQueue
            private let logger: Logger

            init(queue: DispatchQueue, logger: Logger) {
                self.queue = queue
                self.logger = logger
            }

            private func getOrCreateSession() throws -> XPCSession {
                if let session {
                    return session
                }
                let session = try XPCSession(xpcService: name, options: .inactive) { [weak self] error in
                    guard let self else {
                        return
                    }
                    logger.warning("Session was cancelled with error \(error.localizedDescription)")
                    self.session = nil
                }
                // A build signed with a team requires the service to be from the
                // same team. An ad hoc build has no team to compare: launchd
                // resolves this service name only inside this app's own bundle,
                // so no other code can answer, and the service in turn pins this
                // app's exact code. LightweightCodeRequirements, which could pin
                // the service's code here too, needs macOS 14.4, and the app
                // still launches on macOS 14.0.
                if CodeSignature.currentTeamIdentifier != nil {
                    session.setPeerRequirement(.isFromSameTeam(andMatchesSigningIdentifier: MenuBarItemService.name))
                }
                session.setTargetQueue(queue)
                try session.activate()
                self.session = session
                return session
            }

            func cancel(reason: String) {
                guard let session = session.take() else {
                    return
                }
                session.cancel(reason: reason)
            }

            func send(request: Request) -> Response? {
                do {
                    let session = try getOrCreateSession()
                    let reply = try session.sendSync(request)
                    return try reply.decode(as: Response.self)
                } catch {
                    logger.error("Session failed with error \(error)")
                    return nil
                }
            }
        }

        /// Protected storage for the underlying XPC session.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// The session's target queue.
        private let queue: DispatchQueue

        /// The session's logger.
        private let logger: Logger

        /// Creates a new session.
        init(queue: DispatchQueue, logger: Logger) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue, logger: logger))
            self.queue = queue
            self.logger = logger
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) -> Response? {
            storage.withLock { $0.send(request: request) }
        }
    }
}
