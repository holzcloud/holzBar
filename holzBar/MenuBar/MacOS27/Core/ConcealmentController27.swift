//
//  ConcealmentController27.swift
//  holzBar
//

import Foundation
import OSLog

/// A live assessment-mode assertion.
nonisolated protocol ConcealmentToken27: AnyObject {}

/// Activates and releases assessment-mode assertions.
///
/// The app implements it with the private `MenuBarClientCore` API; tests use a fake.
@MainActor
protocol ConcealmentBackend27: AnyObject {
    /// Activates an assertion that keeps only the given applications' items and the given
    /// numbered system items on the bar.
    func activate(allowedBundleIDs: [String], allowedSystemItems: [Int]) async throws -> ConcealmentToken27

    /// Releases an assertion.
    func invalidate(_ token: ConcealmentToken27)
}

/// Tells when MenuBarAgent, the process that holds the assessment-mode assertions, was
/// restarted.
///
/// The assertions are assumed to die with the MenuBarAgent that took them, and the backend
/// reports no invalidation: holzBar would keep its tokens and, while the target stays the same,
/// never activate new ones, so hidden items would stay visible. A restart shows only as a change
/// of MenuBarAgent's process identifier. Acting on that change alone keeps the watch from ever
/// firing in normal use: it fires when the identifier changes to another live one, or comes back
/// after MenuBarAgent was gone, and never before any identifier was seen.
nonisolated struct MenuBarAgentWatch27 {
    /// MenuBarAgent's process identifier at the last note; `nil` while it is not running.
    private var current: Int32?

    /// Whether any process identifier was seen yet.
    private var hasSeenAgent = false

    init() {}

    /// Notes MenuBarAgent's process identifier, `nil` when it is not running.
    ///
    /// - Returns: Whether MenuBarAgent was restarted since the last note.
    mutating func note(pid: Int32?) -> Bool {
        defer { current = pid }
        guard let pid else {
            return false
        }
        guard hasSeenAgent else {
            hasSeenAgent = true
            return false
        }
        return current != pid
    }
}

/// Keeps the live assertions in step with a target.
///
/// Every transition activates the new assertions before releasing the old
/// ones. Because assertions combine as a union of allowlists, an application
/// concealed both before and after a transition stays concealed throughout. A hidden system
/// item is an entry of the concealed set like an application (``SystemItems27``).
///
/// Callers must not overlap calls to `apply(target:running:)` and `renew(target:running:)`.
@MainActor
final class ConcealmentController27 {
    nonisolated private struct Spec: Equatable {
        let concealed: Set<String>
        let allowlist: [String]
        let systemItems: [Int]
    }

    nonisolated private struct Live {
        let spec: Spec
        let token: ConcealmentToken27
    }

    private let backend: ConcealmentBackend27
    // The subsystem is derived like Logger(category:) does; the Core package cannot see Shared/Utilities/Logging.swift.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "ConcealmentController27")
    private var live = [Live]()

    /// Set when the app is quitting: no transition activates or keeps an assertion after it.
    private var isTerminating = false

    /// Whether any assertion is currently live.
    var isActive: Bool {
        !live.isEmpty
    }

    /// The applications the live assertions conceal, whatever target was last asked for.
    var liveConcealed: Set<String> {
        ConcealmentPlanner27.effectivelyConcealed(sets: live.map(\.spec.concealed))
    }

    init(backend: ConcealmentBackend27) {
        self.backend = backend
    }

    /// Applies the target concealed sets for the currently running applications.
    ///
    /// If an activation fails, the assertions activated during this call are
    /// released, the previous ones stay live, and the error is rethrown.
    func apply(target: [Set<String>], running: Set<String>) async throws {
        try await transition(target: target, running: running, reusingLive: true, name: "apply")
    }

    /// Takes every assertion of the target anew, even those a live one already matches.
    ///
    /// `apply` keeps a live token whose target is unchanged, so after a wake or a display
    /// change it asserts nothing again. An assertion that macOS dropped without restarting
    /// MenuBarAgent is not visible to holzBar (research assumption A8), and the hidden items
    /// would stay shown until something else changed. A renewal is right whether or not that
    /// happens. Every new assertion is activated before any old one is released; because
    /// assertions combine as a union of allowlists, every concealed app stays concealed
    /// throughout. If an activation fails, the old assertions stay live and the error is
    /// rethrown.
    func renew(target: [Set<String>], running: Set<String>) async throws {
        try await transition(target: target, running: running, reusingLive: false, name: "renew")
    }

    private func transition(target: [Set<String>], running: Set<String>, reusingLive: Bool, name: String) async throws {
        guard !isTerminating else {
            return
        }
        // Timed: every change has MenuBarAgent lay the bar out again, and that animation is
        // what a stutter of the bar would be made of.
        let started = ProcessInfo.processInfo.systemUptime
        logger.debug("Concealment \(name, privacy: .public): started, \(target.count, privacy: .public) sets")
        defer {
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            logger.debug("Concealment \(name, privacy: .public): took \(milliseconds, privacy: .public) ms")
        }
        let desired = target.map { concealed in
            Spec(
                concealed: concealed,
                allowlist: ConcealmentPlanner27.allowlist(concealing: concealed, running: running),
                systemItems: ConcealmentPlanner27.allowedSystemItems(concealing: concealed)
            )
        }
        var remaining = live
        var next = [Live]()
        var activated = [ConcealmentToken27]()
        do {
            for spec in desired {
                if reusingLive, let index = remaining.firstIndex(where: { $0.spec == spec }) {
                    next.append(remaining.remove(at: index))
                } else {
                    let token = try await backend.activate(allowedBundleIDs: spec.allowlist, allowedSystemItems: spec.systemItems)
                    activated.append(token)
                    next.append(Live(spec: spec, token: token))
                }
            }
        } catch {
            for token in activated {
                backend.invalidate(token)
            }
            throw error
        }
        guard !isTerminating else {
            // Quitting began while an activation was in flight: `releaseAllForTermination()`
            // already released the old assertions, and the new ones must not outlive it.
            for token in activated {
                backend.invalidate(token)
            }
            return
        }
        for old in remaining {
            backend.invalidate(old.token)
        }
        live = next
    }

    /// Releases every live assertion as the app quits and keeps later or in-flight
    /// transitions from asserting anything again.
    func releaseAllForTermination() {
        isTerminating = true
        releaseAll()
    }

    /// Releases every live assertion, which restores all items.
    func releaseAll() {
        // Timed like `apply`: releasing is the other half of the bar's movement, and it is
        // what a bridged click does before replaying itself.
        let started = ProcessInfo.processInfo.systemUptime
        logger.debug("Concealment release: started, \(self.live.count, privacy: .public) live")
        defer {
            let milliseconds = (ProcessInfo.processInfo.systemUptime - started) * 1000
            logger.debug("Concealment release: took \(milliseconds, privacy: .public) ms")
        }
        for entry in live {
            backend.invalidate(entry.token)
        }
        live.removeAll()
    }
}
