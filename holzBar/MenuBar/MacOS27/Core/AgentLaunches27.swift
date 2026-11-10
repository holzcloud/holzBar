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
/// applications that may own an item on the bar count: those holzBar has seen there, top-level
/// applications, and helper apps nested where item helpers live.
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

    /// The folders of an application bundle where a helper app that draws the application's
    /// menu bar item lives, lowercased: a login item (`Contents/Library/LoginItems`, such as
    /// iStat Menus' status agent), other agents in `Contents/Library`, and status helpers in
    /// `Contents/Resources`, `Contents/Helpers` or `Contents/MacOS`. A folder counts with every
    /// folder in it, so `contents/library/` covers the login items as well.
    static let itemOwnerFolders = [
        "contents/library/",
        "contents/resources/",
        "contents/helpers/",
        "contents/macos/",
    ]

    /// Path parts, lowercased, of the places where renderers, services and plug-ins live.
    static let serviceMarkers = [
        ".framework/",
        ".xpc/",
        ".appex/",
        ".bundle/",
        "contents/frameworks/",
        "contents/library/xpcservices/",
    ]

    /// Whether a process may own a menu bar item: a standalone application
    /// (``isStandalone(bundlePath:policy:)``) or a helper app nested in another application where
    /// item helpers live (``itemOwnerFolders``).
    ///
    /// A login item helper that draws its application's item counted as nested before, so its
    /// launch while holzBar conceals left the item concealed from birth, with nothing to correct
    /// it (D-11). Renderers and services stay out: Electron, Chromium and WebKit start their
    /// helpers in `Contents/Frameworks`, in a `.framework` or as `.xpc` services, again and
    /// again while the app runs (14 nested helper apps among the processes measured
    /// 2026-10-05), and each counted launch would make MenuBarAgent lay the bar out again.
    static func mayOwnItem(bundlePath: String?, policy: Policy) -> Bool {
        if isStandalone(bundlePath: bundlePath, policy: policy) {
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
        guard
            !serviceMarkers.contains(where: { parentPath.contains($0) }),
            let host = parentPath.range(of: ".app/", options: .backwards)
        else {
            return false
        }
        let inside = parentPath[host.upperBound...]
        return itemOwnerFolders.contains { inside.hasPrefix($0) }
    }

    /// How the concealer answers a change of the running applications.
    ///
    /// An added application counts when holzBar knows it or it may own an item
    /// (``mayOwnItem(bundlePath:policy:)``); a removed one
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
        let mayOwn = Set(instances.lazy.filter { mayOwnItem(bundlePath: $0.bundlePath, policy: $0.policy) }.map(\.bundleID))
        let relevantAdded = added.filter { known.contains($0) || mayOwn.contains($0) }
        return Reaction(
            running: running,
            graces: added.intersection(concealedInLayout).sorted(),
            updatesConcealment: !relevantAdded.isEmpty || !removed.isDisjoint(with: known)
        )
    }
}
