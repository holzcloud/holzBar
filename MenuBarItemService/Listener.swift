//
//  Listener.swift
//  MenuBarItemService
//

import Foundation
import LightweightCodeRequirements
import OSLog
import XPC
import os

/// A wrapper around an XPC listener object.
final class Listener: Sendable {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object, behind a lock because the
    /// listener's handlers run on XPC's queues.
    private let listener = OSAllocatedUnfairLock<XPCListener?>(uncheckedState: nil)

    /// Creates the shared listener.
    private init() { }

    deinit {
        cancel()
    }

    /// Handles a received message.
    private func handleMessage(_ message: XPCReceivedMessage) -> MenuBarItemService.Response? {
        do {
            let request = try message.decode(as: MenuBarItemService.Request.self)
            switch request {
            case .start:
                Logger.default.debug("Listener received start request")
                return .start
            case .sourcePID(let window):
                let pid = SourcePIDCache.shared.pid(for: window)
                return .sourcePID(pid)
            }
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error, privacy: .private)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the given requirement that session peers must satisfy.
    @available(macOS 26.0, *)
    private func uncheckedActivate(requirement: XPCPeerRequirement) throws {
        let listener = try XPCListener(service: name, requirement: requirement) { request in
            // The listener is shared and lives as long as the service.
            request.accept { message in
                self.handleMessage(message)
            }
        }
        self.listener.withLockUnchecked { $0 = listener }
    }

    /// Returns the requirement that session peers must satisfy: holzBar, and
    /// no other process.
    ///
    /// A build signed with a team requires the same team and holzBar's signing
    /// identifier. Ad hoc code has no team, and Apple's implicit designated
    /// requirement for such code is its code directory hash (cdhash), so an ad
    /// hoc build requires the signing identifier and one of the cdhashes of the
    /// app this service is embedded in: exactly that app's code is accepted, and
    /// every other process is rejected, including ad hoc code that claims the
    /// same identifier. This throws when the requirement cannot be built.
    @available(macOS 26.0, *)
    private func peerRequirement() throws -> XPCPeerRequirement {
        if CodeSignature.currentTeamIdentifier != nil {
            Logger.default.notice("Listener requires a peer from the same team with the app's signing identifier")
            return .isFromSameTeam(andMatchesSigningIdentifier: MenuBarItemService.appIdentifier)
        }

        // The service lives at <app>/Contents/XPCServices/MenuBarItemService.xpc.
        let appURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard Bundle(url: appURL)?.bundleIdentifier == MenuBarItemService.appIdentifier else {
            throw PeerRequirementError.notEmbeddedInApp
        }
        let hashes = try CodeSignature.codeDirectoryHashes(ofCodeAt: appURL)
        let requirement = try ProcessCodeRequirement.allOf {
            SigningIdentifier(MenuBarItemService.appIdentifier)
            CodeDirectoryHash.in(hashes)
        }
        Logger.default.notice("Listener requires the app's exact code (\(hashes.count, privacy: .public) code directory hashes)")
        return .codeRequirement(requirement)
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        let listener = try XPCListener(service: name) { request in
            // The listener is shared and lives as long as the service.
            request.accept { message in
                self.handleMessage(message)
            }
        }
        self.listener.withLockUnchecked { $0 = listener }
    }

    /// Activates the listener.
    ///
    /// On macOS 26 and later the listener does not listen at all when its
    /// peer requirement cannot be built (fail closed); the app then looks up
    /// source processes itself.
    func activate() {
        guard listener.withLockUnchecked({ $0 == nil }) else {
            Logger.default.notice("Listener is already active")
            return
        }

        Logger.default.debug("Activating listener")

        do {
            if #available(macOS 26.0, *) {
                try uncheckedActivate(requirement: peerRequirement())
            } else {
                try uncheckedActivate()
            }
        } catch {
            Logger.default.error("Failed to activate listener with error \(error, privacy: .private)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.withLockUnchecked { $0.take() }?.cancel()
    }
}

// MARK: - Listener.PeerRequirementError

extension Listener {
    /// An error that keeps the listener from building its peer requirement.
    private enum PeerRequirementError: Error, CustomStringConvertible {
        /// The service is not inside holzBar's app bundle.
        case notEmbeddedInApp

        var description: String {
            switch self {
            case .notEmbeddedInApp:
                return "The service is not embedded in \(MenuBarItemService.appIdentifier)"
            }
        }
    }
}
