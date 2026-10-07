//
//  AgentLaunches27.swift
//  holzBar
//

import Foundation

/// Which changes of the running applications the concealer answers on macOS 27.
///
/// NSWorkspace posts its launch and quit notifications for regular apps only, so a menu bar
/// agent that starts after holzBar is noticed only as a change of `runningApplications`. That
/// list holds every process with a bundle, helpers included, and every concealment update makes
/// MenuBarAgent lay the bar out again (about 250 ms, then four Accessibility reads). So only
/// applications that may own an item on the bar count: those holzBar has seen there, and
/// top-level applications.
nonisolated enum AgentLaunches27 {
    /// `NSApplication.ActivationPolicy` without AppKit.
    nonisolated enum Policy: Equatable, Sendable {
        case regular
        case accessory
        case prohibited
    }

    /// One running process: its bundle identifier, the path of its bundle, its policy.
    typealias Instance = (bundleID: String, bundlePath: String?, policy: Policy)

    /// What the concealer does about one change.
    nonisolated struct Reaction: Equatable, Sendable {
        /// The bundle identifiers running now, which the next change is compared with.
        var running: Set<String>

        /// The added applications whose saved section is concealed, sorted. Each is shown
        /// until its item exists: concealed before its status item exists, the item is
        /// squashed to 3 points (jordanbaird/Ice#1007).
        var graces: [String]

        /// Whether concealment is worked out again, once.
        var updatesConcealment: Bool
    }

    /// Path parts that mark a bundle nested in another one.
    static let nestingMarkers = [
        ".app/",
        ".framework/",
        ".xpc/",
        ".appex/",
        ".bundle/",
    ]

    /// Whether a process is an application of its own rather than a helper of another one.
    ///
    /// A top-level test kept the 41 identifiers of real menu bar apps and system agents and
    /// dropped 14 nested helper apps and 10 non-`.app` identifiers (measured 2026-10-05).
    /// `activationPolicy` cannot tell helpers apart: WebKit's `.xpc` services and Electron and
    /// browser helpers run as accessories with `LSUIElement`, and OneDrive declares
    /// `LSBackgroundOnly` yet runs as an accessory. A regular app counts in any case, as the
    /// launch notifications counted every one.
    static func isStandalone(bundlePath: String?, policy: Policy) -> Bool {
        if policy == .regular {
            return true
        }
        guard let bundlePath else {
            return false
        }
        let url = URL(filePath: bundlePath)
        guard url.pathExtension.lowercased() == "app" else {
            return false
        }
        let parent = url.deletingLastPathComponent().path(percentEncoded: false).lowercased()
        let parentPath = parent.hasSuffix("/") ? parent : parent + "/"
        return !nestingMarkers.contains { parentPath.contains($0) }
    }

    /// How the concealer answers a change of the running applications.
    ///
    /// An added application counts when holzBar knows it or it is standalone; a removed one
    /// only when holzBar knows it, because an unknown application never had an item holzBar
    /// placed. A change that leaves the set of bundle identifiers as it was does nothing.
    ///
    /// - Parameters:
    ///   - previous: The bundle identifiers running at the last change.
    ///   - instances: The processes running now that have a bundle identifier.
    ///   - known: The applications holzBar has seen on the bar or keeps in its layout.
    ///   - concealedInLayout: The applications whose saved section is not the visible one.
    static func reaction(
        previous: Set<String>,
        instances: [Instance],
        known: Set<String>,
        concealedInLayout: Set<String>
    ) -> Reaction {
        let running = Set(instances.map(\.bundleID))
        let added = running.subtracting(previous)
        let removed = previous.subtracting(running)
        let standalone = Set(instances.lazy.filter { isStandalone(bundlePath: $0.bundlePath, policy: $0.policy) }.map(\.bundleID))
        let relevantAdded = added.filter { known.contains($0) || standalone.contains($0) }
        return Reaction(
            running: running,
            graces: added.intersection(concealedInLayout).sorted(),
            updatesConcealment: !relevantAdded.isEmpty || !removed.isDisjoint(with: known)
        )
    }
}
