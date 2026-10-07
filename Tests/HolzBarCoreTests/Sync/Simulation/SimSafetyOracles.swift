import Foundation

/// The safety invariants of analysis section 2.2 that the world can observe, by invariant ID. Each oracle reads
/// the ground truth and the world's observations (writes, reads, prompts, answers, transitions), never the
/// engine's own metadata; where it needs the engine's word (claimedPast, its device ID) it asks the optional
/// introspection hooks and skips a brain that cannot answer. Violations are charged to redesigned Macs only.
enum SimSafetyOracles {
    // MARK: Registry

    /// Every safety oracle, in ID order.
    static var all: [any SimOracle] { catalogue.sorted { $0.id < $1.id } }

    /// An oracle by ID.
    static func oracle(_ id: SimInvariantID) -> SimClosureOracle? {
        catalogue.first { $0.id == id }
    }

    private static let catalogue: [SimClosureOracle] = [s1, s1g]

    // MARK: Helpers

    /// The step record the oracle was called for.
    static func step(_ world: SimWorld) -> SimStepRecord? {
        if case .step(let record)? = world.focus { return record }
        return nil
    }

    /// Whether a user token was live just before a hook, judged by the ground truth over the changes that
    /// existed then (justified supersession, A2 section 2.5). A `pre` token is live until an answer loses it.
    static func liveBefore(_ world: SimWorld, token: String, unit: String, changeCount: Int) -> Bool {
        let truth = world.groundTruth
        guard let change = truth.change(forToken: token) else {
            if case .pre? = SimValue.origin(ofToken: token) {
                return !truth.changes.contains { $0.id < changeCount && $0.kind == .answer && $0.lostTokens.contains(token) }
            }
            return false
        }
        guard change.id < changeCount else { return false }
        for other in truth.changes where other.id < changeCount && other.id != change.id {
            switch other.kind {
            case .user:
                if other.unit == unit, other.id > change.id, (other.clock[change.mac] ?? 0) >= change.sequence { return false }
            case .answer:
                if other.lostTokens.contains(token) { return false }
            }
        }
        return true
    }

    /// Whether some ingested version's past holds a later user change of the unit (or an answer that lost the token).
    static func supersededByIngest(_ world: SimWorld, token: String, unit: String, ingests: [Int]) -> Bool {
        let truth = world.groundTruth
        let change = truth.change(forToken: token)
        for version in ingests {
            let past = truth.past(ofVersion: version)
            for other in truth.changes where past.contains(other.id) {
                switch other.kind {
                case .user:
                    guard let change else { continue }
                    if other.unit == unit, other.id > change.id, (other.clock[change.mac] ?? 0) >= change.sequence {
                        return true
                    }
                case .answer:
                    if other.lostTokens.contains(token) { return true }
                }
            }
        }
        return false
    }

    /// Whether a hook's changes are charged to a redesigned engine: the Mac runs one, or it applied a version
    /// that a redesigned Mac wrote (INV-B1).
    static func charged(_ world: SimWorld, _ hook: SimHookRecord) -> Bool {
        if world.isRedesign(hook.mac) { return true }
        return hook.ingests.contains { version in
            world.writer(ofVersion: version).map { world.isRedesign($0) } ?? false
        }
    }

    /// The user-change tokens a hook took away from a unit that were still live and not justifiably superseded.
    static func unjustifiedLosses(_ world: SimWorld, _ hook: SimHookRecord, _ transition: SimTransition) -> [String] {
        var lost: [String] = []
        for token in transition.oldTokens.subtracting(transition.newTokens).sorted() {
            switch world.groundTruth.origin(of: token) {
            case .user, .pre: break
            case .automatic, .unknown: continue
            }
            guard liveBefore(world, token: token, unit: transition.unit, changeCount: hook.changeCountBefore) else { continue }
            if let answered = hook.answered, answered.prompt.losingTokens(for: answered.answer).contains(token) { continue }
            if supersededByIngest(world, token: token, unit: transition.unit, ingests: hook.ingests) { continue }
            lost.append(token)
        }
        return lost
    }

    // MARK: INV-S1 and INV-S1g

    /// INV-S1: a sync-caused change never replaces a live user value (or a `pre` value) except by an answer whose
    /// prompt showed it as losing, or by a version whose past holds a later user change of that unit.
    static let s1 = SimClosureOracle("INV-S1", .step) { world, _ in
        guard let step = step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && charged(world, hook) {
            for transition in hook.transitions {
                let lost = unjustifiedLosses(world, hook, transition)
                if !lost.isEmpty {
                    return "Mac \(hook.mac) lost \(lost.joined(separator: ", ")) at \(transition.unit) in its \(hook.name.rawValue) "
                        + "hook without an answer that showed it as losing and without a version holding a later user change"
                }
            }
        }
        return nil
    }

    /// INV-S1g: no live user change of a redesigned Mac is lost everywhere: not in any Mac's settings, any readable
    /// replica or any pending entry (losses where every holder was destroyed by non-sync events are excluded).
    static let s1g = SimClosureOracle("INV-S1g", .step) { world, _ in
        let lost = world.groundTruth.globallyLost().filter { token in
            world.groundTruth.change(forToken: token).map { world.isRedesign($0.mac) } ?? false
        }
        guard !lost.isEmpty else { return nil }
        return "live user change \(lost.joined(separator: ", ")) is held nowhere: no settings, no readable file, no pending entry"
    }
}
