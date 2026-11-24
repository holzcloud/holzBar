//
//  NewAppQuestion.swift
//  holzBar
//

import Foundation

/// The apps that macOS 27 showed in the menu bar for the first time and that holzBar may ask
/// about (Phase 97, D-12, D-19), as a queue.
///
/// An app is noticed first and waits; it is asked about only while the gate is open: no drag runs,
/// the system has settled after a wake or a display change, and no app is in its launch grace.
/// A noticed app is never dropped by the gate. Time is passed in and nothing here reads a clock
/// or starts a timer. The names come from other apps: callers clean them, keep them in memory
/// only and never log them.
nonisolated struct NewAppQuestion: Equatable, Sendable {
    /// What the user can answer. `dontAskAgain` is stored by a later step; the three sections move
    /// the app.
    nonisolated enum Answer: String, CaseIterable, Sendable {
        case visible
        case hidden
        case alwaysHidden
        case dontAskAgain
    }

    /// One app, by its bundle identifier.
    nonisolated struct App: Identifiable, Equatable, Sendable {
        let bundleID: String
        /// The cleaned name to show.
        let name: String
        /// When holzBar noticed the app.
        let noticedAt: ContinuousClock.Instant

        var id: String { bundleID }
    }

    /// What decides whether the question may be asked now.
    nonisolated struct Gate: Equatable, Sendable {
        /// A menu bar item is being dragged.
        let isDragging: Bool
        /// The system has settled after a wake, an unlock or a display change.
        let isSettled: Bool
        /// The apps that are in their launch grace; empty almost always.
        let launchGrace: Set<String>

        /// Whether the question may be asked now.
        var isOpen: Bool {
            !isDragging && isSettled && launchGrace.isEmpty
        }
    }

    /// The most rows a card shows before it says "+N more".
    static let defaultRowLimit = 4

    /// The apps that were noticed and wait for the gate, in the order of noticing.
    private(set) var waiting = [App]()

    /// The apps that are asked about now, in the order of noticing.
    private(set) var asked = [App]()

    /// Whether an app may be asked about at all.
    ///
    /// Never asked: Apple's apps, holzBar's own bundle, an app declined before, a helper that sits
    /// inside another app's bundle and an empty identifier. The identity is the bundle identifier,
    /// never a title.
    ///
    /// - Parameters:
    ///   - bundleID: The app's bundle identifier.
    ///   - bundlePath: The path of the app's bundle, when known.
    ///   - ownBundleID: holzBar's own bundle identifier.
    ///   - declined: The identifiers the user asked never to be asked about.
    static func isEligible(bundleID: String, bundlePath: String?, ownBundleID: String, declined: Set<String>) -> Bool {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !id.isEmpty,
            !id.lowercased().hasPrefix("com.apple."),
            !OwnBundle.matches(id, bundleIdentifier: ownBundleID),
            !declined.contains(bundleID)
        else {
            return false
        }
        if let bundlePath, bundlePath.contains(".app/Contents/") {
            return false
        }
        return true
    }

    /// Notes an app once. One already waiting or asked about changes nothing.
    mutating func note(_ app: App) {
        guard !waiting.contains(where: { $0.bundleID == app.bundleID }), !asked.contains(where: { $0.bundleID == app.bundleID }) else {
            return
        }
        waiting.append(app)
    }

    /// Moves every waiting app to the asked ones while the gate is open; with it closed nothing
    /// moves and nothing is dropped.
    ///
    /// - Returns: The instant to look again, or `nil` when nothing is due. This step has no time
    ///   rule: the caller follows the gate's own events.
    mutating func release(gate: Gate, at now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        if gate.isOpen, !waiting.isEmpty {
            asked.append(contentsOf: waiting)
            waiting.removeAll()
        }
        return nil
    }

    /// Takes an app out of both lists: it was answered.
    mutating func remove(_ bundleID: String) {
        waiting.removeAll { $0.bundleID == bundleID }
        asked.removeAll { $0.bundleID == bundleID }
    }

    /// Empties both lists.
    mutating func clear() {
        waiting.removeAll()
        asked.removeAll()
    }

    /// The rows a card shows and how many apps come after them.
    static func shown(_ apps: [App], limit: Int = defaultRowLimit) -> (rows: [App], more: Int) {
        let count = max(0, limit)
        return (Array(apps.prefix(count)), max(0, apps.count - count))
    }
}
