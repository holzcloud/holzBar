import Foundation

/// The invariants of the macOS 27 families (A2 sections 5.2 to 5.4), restricted to the units that only
/// generation-27 Macs author: `l27/<bundle>`, `prof/<profile>` and `known27`. Each reads the ground truth and
/// the world's observations (writes, prompts, hooks, snapshots), never the engine's own metadata, and is quiet
/// in a world that has no generation-27 Mac. Violations are charged to redesigned Macs only.
///
/// - INV-L1: a generation-26 Mac neither shows, compares nor applies the families, and its hints have a witness.
/// - INV-L2: it mints no value of the families (the tokens in its file were made on generation-27 Macs).
/// - INV-L3: its writes keep every relayed value, unless a later change of another Mac superseded it.
/// - INV-L4: its relays follow lineage: a value never replaces one that its change did not know.
/// - INV-L5: relays do not depend on clocks (metamorphic, `relayIndependence`).
/// - INV-L6: after an OS upgrade sync never removes the arrangement and asks only about what the user changed
///   or about a real conflict, never about what holzBar seeded.
/// - INV-K1: the known applications merge by union, silently, at launch and Restart only.
/// - INV-A3: the automatic stores publish no dot and never change an entry the user made.
enum SimLayout27Oracles {
    // MARK: Registry

    static var all: [any SimOracle] { catalogue.sorted { $0.id < $1.id } }

    static func oracle(_ id: SimInvariantID) -> SimClosureOracle? {
        catalogue.first { $0.id == id }
    }

    private static let catalogue: [SimClosureOracle] = [l1, l2, l3, l4, l6, k1, a3]

    // MARK: Helpers

    /// Whether the family's units exist at all in this world.
    static func hasGeneration27(_ world: SimWorld) -> Bool {
        world.macs.values.contains { $0.generation == 27 }
    }

    static func isScoped(_ unit: String) -> Bool {
        SimUnits.generationScope(unit) == 27
    }

    /// The tokens a file holds, by scoped unit (user tokens only; a token names its unit).
    static func scopedTokens(_ tokens: Set<String>) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for token in tokens {
            if case .user(_, let unit)? = SimValue.origin(ofToken: token), isScoped(unit) {
                result[unit, default: []].insert(token)
            }
        }
        return result
    }

    private static func tokens(in write: SimWriteRecord, _ world: SimWorld) -> Set<String> {
        world.brains[write.mac]?.heldTokens(inFile: write.path, data: write.data) ?? []
    }

    /// The write before `write` by the same Mac to the same file that reached the provider.
    private static func previousWrite(before write: SimWriteRecord, _ world: SimWorld) -> SimWriteRecord? {
        guard let index = world.writeLog.lastIndex(where: { $0.version == write.version && $0.path == write.path && $0.mac == write.mac }) else {
            return nil
        }
        return world.writeLog[..<index].last { $0.mac == write.mac && $0.path == write.path && $0.version != nil }
    }

    /// A write of a redesigned generation-26 Mac that reached the provider.
    private static func write26(_ world: SimWorld) -> SimWriteRecord? {
        guard
            let write = SimSafetyOracles.write(world), write.version != nil, SimLimits.isDeviceFile(write.path),
            world.isRedesign(write.mac), world.macs[write.mac]?.generation != 27, hasGeneration27(world)
        else {
            return nil
        }
        return write
    }

    // MARK: INV-L1

    /// INV-L1: a generation-26 Mac never shows the families in a sheet, never applies them, and a hint of its own
    /// has a witness outside them (a change of another Mac in a unit it compares, or a value that was there before sync).
    static let l1 = SimClosureOracle("INV-L1", .step) { world, _ in
        guard hasGeneration27(world), let step = SimSafetyOracles.step(world) else { return nil }
        for mac in world.macs.keys.sorted() where world.isRedesign(mac) && world.macs[mac]?.generation != 27 {
            if let prompt = world.brains[mac]?.openPrompt, let shown = prompt.shown.first(where: { isScoped($0.unit) }) {
                return "Mac \(mac) shows a sheet about \(shown.unit), a unit of the other generation"
            }
            for hook in step.hooks where hook.mac == mac && hook.syncCaused {
                if let transition = hook.transitions.first(where: { isScoped($0.unit) }) {
                    return "Mac \(mac) applied \(transition.unit) in its \(hook.name.rawValue) hook, a unit of the other generation"
                }
            }
            guard world.macs[mac]?.running == true, world.brains[mac]?.hint != nil else { continue }
            let truth = world.groundTruth
            let comparable = truth.changes.contains { change in
                change.kind == .user && (change.mac != mac || truth.isOfPreviousState(change, at: mac)) && change.unit.map { !isScoped($0) } == true
            }
            let pre = world.groundTruth.holders().allTokens.contains { truth.origin(of: $0) == .pre }
            if !comparable, !pre {
                return "Mac \(mac) shows a hint, and no unit it compares has a change of another Mac"
            }
        }
        return nil
    }

    // MARK: INV-L2, INV-L3, INV-L4

    /// INV-L2: a generation-26 Mac publishes no value of the families that it made: every token in its file was
    /// made by a user on a generation-27 Mac, and every deletion has a user deletion on such a Mac behind it.
    static let l2 = SimClosureOracle("INV-L2", .write) { world, _ in
        guard let write = write26(world) else { return nil }
        let truth = world.groundTruth
        for (unit, held) in scopedTokens(tokens(in: write, world)).sorted(by: { $0.key < $1.key }) {
            for token in held.sorted() {
                guard let change = truth.change(forToken: token) else {
                    return "Mac \(write.mac) published \(token) at \(unit), which no user made"
                }
                if truth.generation(of: change.mac) != 27 {
                    return "Mac \(write.mac) published \(token) at \(unit), made on the generation-26 Mac \(change.mac)"
                }
            }
        }
        let deleted = world.introspection(of: write.mac)?.deletedUnits(inFile: write.path, data: write.data) ?? []
        for unit in deleted.sorted() where isScoped(unit) {
            let userDeletion = truth.changes.contains { $0.kind == .user && $0.unit == unit && $0.tokens.isEmpty && truth.generation(of: $0.mac) == 27 }
            if !userDeletion {
                return "Mac \(write.mac) published a deletion of \(unit) that no user of a generation-27 Mac made"
            }
        }
        return nil
    }

    /// INV-L3: a write of a generation-26 Mac keeps every value of the families that its previous file held, unless
    /// a later change of the unit that knew of it superseded it.
    static let l3 = SimClosureOracle("INV-L3", .write) { world, _ in
        guard let write = write26(world), let previous = previousWrite(before: write, world) else { return nil }
        let now = scopedTokens(tokens(in: write, world))
        for (unit, held) in scopedTokens(tokens(in: previous, world)).sorted(by: { $0.key < $1.key }) {
            for token in held.sorted() where !(now[unit] ?? []).contains(token) {
                if world.groundTruth.lostToAmnesia(token: token) { continue }
                if !SimSafetyOracles.supersededByIngest(world, token: token, unit: unit, ingests: [], mac: write.mac) {
                    return "Mac \(write.mac) dropped \(token) at \(unit) from its file, and nothing it has seen superseded it"
                }
            }
        }
        return nil
    }

    /// INV-L4: a relay follows lineage. A value that goes out of a generation-26 Mac's file for another one was
    /// replaced by a value whose change knew of it, or by an answer that lost it, never by a date.
    static let l4 = SimClosureOracle("INV-L4", .write) { world, _ in
        guard let write = write26(world), let previous = previousWrite(before: write, world) else { return nil }
        let truth = world.groundTruth
        let seen = truth.seenPast(ofMac: write.mac)
        let before = scopedTokens(tokens(in: previous, world))
        let now = scopedTokens(tokens(in: write, world))
        for (unit, held) in now.sorted(by: { $0.key < $1.key }) where !held.isEmpty {
            guard let old = before[unit] else { continue }
            // A value that went out of the file was replaced: by a new value whose change knew of it, or by an
            // answer that lost it. A relay that decided by a date would drop it for a value of another lineage.
            for dropped in old.subtracting(held).sorted() where !truth.lostToAmnesia(token: dropped) {
                guard let older = truth.change(forToken: dropped) else { continue }
                let byLineage = held.contains { token in truth.change(forToken: token).map { truth.knew($0, of: older) } ?? false }
                let byAnswer = truth.changes.contains { $0.kind == .answer && seen.contains($0.id) && $0.lostTokens.contains(dropped) }
                // A deletion that knew of the value replaces it as well.
                let byDeletion = truth.changes.contains {
                    $0.kind == .user && $0.unit == unit && $0.tokens.isEmpty && seen.contains($0.id) && truth.knew($0, of: older)
                }
                if !byLineage, !byAnswer, !byDeletion {
                    return "Mac \(write.mac) replaced \(dropped) at \(unit) by \(held.sorted().joined(separator: ", ")), none of which knew of it"
                }
            }
        }
        return nil
    }

    // MARK: INV-L6

    /// The step records of the upgrades of `mac` so far.
    private static func upgrades(_ world: SimWorld, of mac: SimMacName) -> [SimStepRecord] {
        world.stepRecords.filter { if case .upgradeOS(let target) = $0.event { target == mac } else { false } }
    }

    /// INV-L6: after `upgradeOS(m)` sync never removes a value the user made from m's arrangement, and m is asked
    /// only about a unit its user changed since the upgrade (the group's intent arrives silently).
    static let l6 = SimClosureOracle("INV-L6", .step) { world, _ in
        guard hasGeneration27(world), let step = SimSafetyOracles.step(world) else { return nil }
        for mac in world.macs.keys.sorted() where world.isRedesign(mac) {
            guard let upgrade = upgrades(world, of: mac).first else { continue }
            for hook in step.hooks where hook.mac == mac && hook.syncCaused {
                for transition in hook.transitions where isScoped(transition.unit) && transition.new == nil {
                    let lost = SimSafetyOracles.unjustifiedLosses(world, hook, transition)
                    if !lost.isEmpty {
                        return "sync removed \(transition.unit) from the arrangement of \(mac) after its upgrade, losing \(lost.joined(separator: ", "))"
                    }
                }
            }
            for record in step.prompts where record.mac == mac && !record.prompt.title.hasPrefix("This folder") {
                for shown in record.prompt.shown where isScoped(shown.unit) {
                    let changed = world.groundTruth.changes.contains {
                        $0.kind == .user && $0.mac == mac && $0.unit == shown.unit && $0.time >= upgrade.time
                    }
                    // A conflict of the group's own changes is a real question; what holzBar seeded is none.
                    if !changed, !world.groundTruth.conflict(mac: mac, unit: shown.unit, visibleOnly: true) {
                        return "\(mac) was asked about \(shown.unit) after its upgrade, which its user did not change since and which is no conflict"
                    }
                }
            }
        }
        return nil
    }

    // MARK: INV-K1

    private static func strings(_ value: SimValue?) -> Set<String> {
        guard case .array(let elements)? = value else { return [] }
        return Set(elements.compactMap { if case .string(let text) = $0 { text } else { nil } })
    }

    /// INV-K1: the known applications merge by union and without a word. A sync-caused change of the set happens
    /// at launch or at Restart only, never removes an element, and no sheet shows it. A generation-26 Mac's set
    /// is never touched by sync.
    static let k1 = SimClosureOracle("INV-K1", .step) { world, _ in
        guard hasGeneration27(world), let step = SimSafetyOracles.step(world) else { return nil }
        for hook in step.hooks where hook.syncCaused && world.isRedesign(hook.mac) {
            for transition in hook.transitions where transition.unit == SimUnits.known27 {
                if world.macs[hook.mac]?.generation != 27 {
                    return "sync changed the known applications of the generation-26 Mac \(hook.mac)"
                }
                if hook.name != .launch, hook.name != .command {
                    return "Mac \(hook.mac) changed its known applications in its \(hook.name.rawValue) hook, not at launch or Restart"
                }
                let removed = strings(transition.old).subtracting(strings(transition.new))
                if !removed.isEmpty {
                    return "Mac \(hook.mac) lost the known applications \(removed.sorted().joined(separator: ", "))"
                }
            }
        }
        for record in step.prompts where record.prompt.shown.contains(where: { $0.unit == SimUnits.known27 }) {
            return "Mac \(record.mac) shows a sheet about its known applications"
        }
        return nil
    }

    // MARK: INV-A3

    /// INV-A3: automatic stores (seeding, the placement of a new application) publish no dot and never change an
    /// entry that the user made. A write holds no automatic token of the families, and an automatic event leaves
    /// every user value of the families on its Mac as it was.
    static let a3 = SimClosureOracle("INV-A3", .step) { world, _ in
        guard hasGeneration27(world), let step = SimSafetyOracles.step(world) else { return nil }
        let truth = world.groundTruth
        for write in step.writes where write.version != nil && SimLimits.isDeviceFile(write.path) && world.isRedesign(write.mac) {
            var automatic = Set<String>()
            for state in world.macs.values {
                for (unit, value) in SimUnits.units(of: state.defaults) where isScoped(unit) {
                    // holzBar's own note that it placed a value lives in Sigma. A Mac whose Sigma was lost, restored or replaced
                    // after the placement has no such note, and the value looks like one the user arranged (D-10): nothing
                    // the engine could know, so only placements it can still know of are judged.
                    automatic.formUnion(value.tokens.filter { truth.origin(of: $0) == .automatic && !truth.engineForgot($0, at: write.mac) })
                }
            }
            if let token = tokens(in: write, world).intersection(automatic).sorted().first {
                return "Mac \(write.mac) published the automatic placement \(token) as if it were the user's arrangement"
            }
        }
        switch step.event {
        case .seed27(let mac), .placeNewApp27(let mac, _), .learn(let mac, _), .setFlag(let mac, _):
            let before = scopedUserTokens(step.before[mac]?.defaultsTokens ?? [], truth)
            let after = scopedUserTokens(step.after[mac]?.defaultsTokens ?? [], truth)
            if let lost = before.subtracting(after).sorted().first {
                return "the automatic event \(step.event.canonical) changed the arrangement the user made on \(mac): \(lost) is gone"
            }
        default:
            break
        }
        return nil
    }

    private static func scopedUserTokens(_ tokens: Set<String>, _ truth: SimGroundTruth) -> Set<String> {
        Set(tokens.filter { token in
            if case .user(_, let unit)? = SimValue.origin(ofToken: token), isScoped(unit) { return truth.origin(of: token) == .user }
            return false
        })
    }

    // MARK: INV-L5 (metamorphic)

    /// What a run holds of the families, in a form two runs can be compared in: the tokens each generation-26 Mac
    /// published (in order) and the user tokens of the families each generation-27 Mac holds at the end.
    private static func observe(_ setup: SimMetaSetup, _ events: [SimEvent], insertions: [Int: [SimEvent]] = [:], macs: [SimMacSpec]? = nil) -> (published: [String], held: [String]) {
        let world = SimWorld(seed: setup.seed, macs: macs ?? setup.macs, preset: setup.preset, policy: setup.policy, brainFactory: setup.brainFactory)
        for (index, event) in events.enumerated() {
            world.run(insertions[index] ?? [])
            world.step(event)
        }
        var published: [String] = []
        for write in world.writeLog where write.version != nil && world.macs[write.mac]?.generation != 27 {
            let held = scopedTokens(world.brains[write.mac]?.heldTokens(inFile: write.path, data: write.data) ?? [])
            published.append("\(write.mac) \(held.keys.sorted().map { "\($0)=\(held[$0]!.sorted())" })")
        }
        var held: [String] = []
        for mac in world.macs.keys.sorted() {
            let units = SimUnits.units(of: world.macs[mac]!.defaults).filter { isScoped($0.unit) }
            let user = units.flatMap { $0.value.tokens }.filter { world.groundTruth.origin(of: $0) != .automatic }.sorted()
            held.append("\(mac) g\(world.macs[mac]!.generation) \(user)")
        }
        return (published, held)
    }

    /// INV-L5: the same trace with other clock offsets and clock steps gives the same relays of the families and
    /// the same arrangement on every Mac. A relay that decided "newer" by a date would differ.
    static func relayIndependence(_ setup: SimMetaSetup, _ events: [SimEvent], clockSeed: UInt64 = 1) -> [SimViolation] {
        var random = SimRandom(seed: clockSeed).fork("layout27-clocks")
        var skewed = setup.macs
        for index in skewed.indices {
            skewed[index].clockOffsetMilliseconds = Int64(random.int(in: -3...3)) * 3_600_000
        }
        var insertions: [Int: [SimEvent]] = [:]
        for index in events.indices where random.chance(0.25) {
            insertions[index] = [.clockStep(mac: random.pick(setup.macs.map(\.name)), milliseconds: Int64(random.int(in: -3...3)) * 3_600_000)]
        }
        let plain = observe(setup, events)
        let shifted = observe(setup, events, insertions: insertions, macs: skewed)
        func violation(_ description: String) -> SimViolation {
            SimViolation(id: "INV-L5", seed: setup.seed, stepIndex: events.count, description: description, trace: events.map(\.canonical))
        }
        var found: [SimViolation] = []
        if plain.published != shifted.published {
            found.append(violation("clock offsets changed what a generation-26 Mac relays of the macOS 27 families"))
        }
        if plain.held != shifted.held {
            found.append(violation("clock offsets changed the arrangement a Mac holds: \(plain.held) versus \(shifted.held)"))
        }
        return found
    }
}
