//
//  NewAppQuestion.swift
//  holzBar
//

import Foundation

/// The apps that macOS 27 showed in the menu bar for the first time and that holzBar may ask
/// about (Phase 97, D-12, D-19), as a queue.
///
/// An app is noticed first and waits; it is asked about only while the gate is open: no drag runs,
/// the system has settled after a wake or a display change, the app is not in its launch grace, the
/// quiet start after the model started is over and ten seconds have passed since the last new app,
/// so several apps at login become one question. A noticed app is never dropped by the gate. Time
/// is passed in and nothing here reads a clock or starts a timer. The names come from other apps: callers clean them, keep them in memory
/// only and never log them.
nonisolated struct NewAppQuestion: Equatable, Sendable {
    /// What the user can answer. `dontAskAgain` moves nothing and is kept on this Mac; the three
    /// sections move the app.
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
        /// When the model that holds the question started: nothing is asked during the first
        /// ``Policy/quietStart`` after it.
        let startedAt: ContinuousClock.Instant

        /// Whether no event holds every app back: no drag runs and the system has settled.
        var isOpen: Bool {
            !isDragging && isSettled
        }
    }

    /// The fixed numbers of the question.
    nonisolated enum Policy {
        /// How long after the model started nothing is asked, so apps that start at login are all
        /// noticed first (D-19).
        static let quietStart = Duration.seconds(60)
        /// How long after the last new app the question waits, so several apps at login become one
        /// combined question (D-12).
        static let coalescing = Duration.seconds(10)
        /// The most bundle identifiers either stored list keeps; the oldest go first.
        static let maximumRemembered = 512
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
            !declined.contains(bundleID),
            !declined.contains(id)
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

    /// Moves the waiting apps to the asked ones when the gate allows it; nothing is ever dropped.
    ///
    /// An app in its launch grace waits while the others move. Nothing moves before the quiet start
    /// is over and until ``Policy/coalescing`` has passed since the last waiting app was noticed,
    /// so a burst of apps becomes one question.
    ///
    /// - Returns: The earliest instant a waiting app could move when only time holds it back, so
    ///   the caller waits once until then; `nil` when nothing is due or when only an event (a drag,
    ///   the system settling, a launch grace ending) can open the gate: the caller follows the
    ///   events.
    mutating func release(gate: Gate, at now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        guard gate.isOpen else {
            return nil
        }
        let ready = waiting.filter { !gate.launchGrace.contains($0.bundleID) }
        guard let newest = ready.map(\.noticedAt).max() else {
            return nil
        }
        let due = max(gate.startedAt.advanced(by: Policy.quietStart), newest.advanced(by: Policy.coalescing))
        guard now >= due else {
            return due
        }
        let readyIDs = Set(ready.map(\.bundleID))
        asked.append(contentsOf: ready)
        waiting.removeAll { readyIDs.contains($0.bundleID) }
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

    /// The stored list of waiting questions with identifiers added: each once, in the order of
    /// first adding, with empty ones skipped and only the newest ``Policy/maximumRemembered`` kept.
    static func remembered(adding bundleIDs: [String], to stored: [String]) -> [String] {
        var seen = Set<String>()
        var list = [String]()
        for id in stored + bundleIDs where !id.isEmpty && seen.insert(id).inserted {
            list.append(id)
        }
        return Array(list.suffix(Policy.maximumRemembered))
    }

    /// The stored list of apps never to ask about again with one identifier added: once, newest
    /// last, the oldest dropped first past ``Policy/maximumRemembered``.
    static func declined(adding bundleID: String, to stored: [String]) -> [String] {
        remembered(adding: [bundleID], to: stored)
    }

    /// The stored list of waiting questions without one identifier.
    static func remembered(removing bundleID: String, from stored: [String]) -> [String] {
        remembered(adding: [], to: stored.filter { $0 != bundleID })
    }

    /// The rows a card shows and how many apps come after them.
    static func shown(_ apps: [App], limit: Int = defaultRowLimit) -> (rows: [App], more: Int) {
        let count = max(0, limit)
        return (Array(apps.prefix(count)), max(0, apps.count - count))
    }
}
