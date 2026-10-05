//
//  SourcePIDClaims.swift
//  holzBar
//

import Foundation

/// Decides which app an item window belongs to on macOS 26, from the apps that report an
/// item at the window's centre.
///
/// On macOS 26 Control Center owns every item window, so holzBar asks the running apps
/// through Accessibility where their items are. Those frames are what each app reports
/// about itself, so any app could report an item where another app's item is, such as
/// Control Center's camera and microphone indicator. Apps signed by Apple are asked first
/// and win: the first of them to claim a window gets it. Any other app gets a window only
/// when a scan that asked every app found no other app claiming it. A window that two such
/// apps claim belongs to none of them.
///
/// The type knows nothing about Accessibility or windows, so it can be tested on its own.
nonisolated struct SourcePIDClaims {
    /// One app's report of an item at the window's centre.
    nonisolated struct Claim: Equatable {
        /// The app's process.
        let pid: pid_t
        /// Whether the app's code is signed by Apple.
        let isSignedByApple: Bool
    }

    /// Which app a window belongs to.
    nonisolated enum Decision: Equatable {
        /// The window belongs to the app with this process.
        case owner(pid_t)
        /// Two or more apps that are not signed by Apple claim the window, so it belongs
        /// to none of them.
        case contested
        /// No app claims the window, or the only claim comes from an app that is not
        /// signed by Apple and the scan stopped before it asked every app.
        case unresolved
    }

    /// The claims, in the order the apps were asked.
    private(set) var claims = [Claim]()

    /// Creates an empty set of claims.
    init() {}

    /// Adds an app's claim.
    mutating func add(_ claim: Claim) {
        claims.append(claim)
    }

    /// Whether no later claim can change the decision: an app signed by Apple claims the
    /// window, so a scan stops asking about it.
    var isSettled: Bool {
        claims.contains(where: \.isSignedByApple)
    }

    /// Which app the window belongs to.
    ///
    /// - Parameter scanFinished: Whether the scan asked every app it could ask, rather
    ///   than running out of time or being cancelled.
    func decision(scanFinished: Bool) -> Decision {
        if let claim = claims.first(where: \.isSignedByApple) {
            return .owner(claim.pid)
        }
        let pids = Set(claims.map(\.pid))
        guard pids.count < 2 else {
            return .contested
        }
        guard scanFinished, let pid = pids.first else {
            return .unresolved
        }
        return .owner(pid)
    }
}
