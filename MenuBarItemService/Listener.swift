//
//  Listener.swift
//  MenuBarItemService
//

import Foundation
import LightweightCodeRequirements
import OSLog
import XPC

/// A wrapper around an XPC listener object.
final class Listener {
    /// The shared listener.
    static let shared = Listener()

    /// The service name.
    private let name = MenuBarItemService.name

    /// The underlying XPC listener object.
    private var listener: XPCListener?

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
            Logger.default.error("Listener failed to handle message with error \(error)")
            return nil
        }
    }

    /// Activates the listener without checking if it is already active,
    /// with the given requirement that session peers must satisfy.
    @available(macOS 26.0, *)
    private func uncheckedActivate(requirement: XPCPeerRequirement) throws {
        listener = try XPCListener(service: name, requirement: requirement) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
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
        Logger.default.notice("Listener requires the app's exact code (\(hashes.count) code directory hashes)")
        return .codeRequirement(requirement)
    }

    /// Activates the listener without checking if it is already active.
    private func uncheckedActivate() throws {
        listener = try XPCListener(service: name) { [weak self] request in
            request.accept { message in
                self?.handleMessage(message)
            }
        }
    }

    /// Activates the listener.
    ///
    /// On macOS 26 and later the listener does not listen at all when its
    /// peer requirement cannot be built (fail closed); the app then looks up
    /// source processes itself.
    func activate() {
        guard listener == nil else {
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
            Logger.default.error("Failed to activate listener with error \(error)")
        }
    }

    /// Cancels the listener.
    func cancel() {
        Logger.default.debug("Canceling listener")
        listener.take()?.cancel()
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
