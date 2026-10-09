import Foundation

// MARK: - Facts the drain phase collects

/// What the drain phase found. The liveness oracles read these facts from the world, so a later plan can register
/// more oracles over the same drain without running another one.
struct SimDrainFacts: Equatable, Sendable {
    var rounds = 0
    var quiescent = false
    /// Writes in the last round (all that mattered when the drain never became quiet).
    var finalRoundWrites = 0
    /// Macs that still show a hint or an open sheet after the last round.
    var finalHints: [String] = []
    var promptsAfterT0 = 0
    var promptBound = 0
    var laters = 0
    /// INV-C1: one entry per synced unit the Macs do not agree on.
    var disagreements: [String] = []
    /// INV-C5: live changes some Mac neither applied, nor waits on, nor saw superseded.
    var unreached: [String] = []
    /// INV-P6: real conflicts that persisted with no hint and no sheet.
    var unansweredConflicts: [String] = []
    /// INV-C6: units where a fresh Mac joining after the drain differs from the agreed state.
    var freshMismatches: [String] = []
    var freshChecked = false
    var freshConverged = true
}

/// How the drain answers prompts: every choice is adversarial, drawn from the run's random stream, or scripted.
enum SimDrainAnswers: Sendable {
    case random
    case use
    case keep
    /// The answers in order, cycling.
    case script([SimAnswer])
}

struct SimDrainConfig: Sendable {
    var maximumLaters = 2
    var maximumRounds = 14
    /// Consecutive rounds with no write, no hint and no sheet that count as quiescence.
    var quietRounds = 2
    var answers = SimDrainAnswers.random
    /// The Mac that joins after the drain (INV-C6); `nil` skips the check.
    var fresh: SimMacName? = "Z"
    /// Where the fresh Mac joins and its generation; defaults to the first redesigned Mac's.
    var freshFolder: String?
    /// Whether the drain answers one open sheet and delivers everything before it looks at the next, as people answer
    /// one after the other. Off, every open sheet is answered before anything is delivered, which is how two Macs press
    /// Use for one conflict at the same moment.
    var answerOneAtATime = false

    init() {}
}

// MARK: - The drain

/// The quiescence and drain phase of analysis section 5.4 (A2 section 5.6): from T0 no user events except answers,
/// every write delivered, every dataless file readable, every Mac launched until two rounds produce no write and no
/// hint, every prompt answered Use or Keep with Later allowed finitely often; then INV-C1 to C6 and INV-P6.
enum SimDrain {
    /// Delivers everything and lets every timer run.
    static func settle(_ world: SimWorld) {
        world.materializeDatalessFiles()
        var iterations = 0
        while let due = world.nextDueTime, iterations < 600 {
            world.step(.advance(milliseconds: max(due - world.now, 1)))
            world.materializeDatalessFiles()
            iterations += 1
        }
    }

    static func redesignMacs(_ world: SimWorld) -> [SimMacName] {
        world.macs.keys.sorted().filter { world.isRedesign($0) }
    }

    private static func openSheets(_ world: SimWorld) -> [SimMacName] {
        world.macs.keys.sorted().filter { world.macs[$0]?.running == true && world.brains[$0]?.openPrompt != nil }
    }

    private static func hints(_ world: SimWorld) -> [String] {
        var found: [String] = []
        for mac in redesignMacs(world) {
            if world.macs[mac]?.running == true, world.brains[mac]?.hint != nil || world.brains[mac]?.openPrompt != nil {
                found.append(mac.name)
            }
        }
        return found
    }

    private static func conflicts(_ world: SimWorld) -> [String] {
        var found: [String] = []
        for mac in redesignMacs(world) where world.macs[mac]?.enabled == true {
            for unit in SimSafetyOracles.conflictedUnits(world, mac) { found.append("\(mac):\(unit)") }
        }
        return found
    }

    /// The conflicts that exist at T0 whether or not the files that show them have been delivered: a unit where two users changed it
    /// without knowing of each other. Each Mac that compares the unit may be asked once.
    private static func concurrentConflicts(_ world: SimWorld) -> Int {
        var count = 0
        // Answers that crossed (two Macs answered one conflict without knowing of each other's answer) leave the conflict standing: it is
        // as open as one that nobody has answered.
        for unit in world.groundTruth.unitsWithCrossedAnswers() {
            for mac in redesignMacs(world) where world.macs[mac]?.enabled == true && world.groundTruth.isComparable(unit: unit, on: mac) {
                count += 1
            }
        }
        for unit in world.groundTruth.unitsWithConcurrentValues() {
            for mac in redesignMacs(world) where world.macs[mac]?.enabled == true && world.groundTruth.isComparable(unit: unit, on: mac) {
                count += 1
            }
        }
        return count
    }

    private static func chooseAnswer(_ config: SimDrainConfig, random: inout SimRandom, laters: inout Int, index: inout Int) -> SimAnswer {
        switch config.answers {
        case .use: return .use
        case .keep: return .keep
        case .script(let answers):
            guard !answers.isEmpty else { return .use }
            defer { index += 1 }
            let answer = answers[index % answers.count]
            if answer == .later { laters += 1 }
            return answer
        case .random:
            if laters < config.maximumLaters, random.chance(0.25) {
                laters += 1
                return .later
            }
            return random.chance(0.5) ? .use : .keep
        }
    }

    /// Runs the drain on a world that has played its trace, collects the facts, stores them in `world.drainFacts` and
    /// runs the oracles registered at the `.drain` moment.
    @discardableResult
    static func run(_ world: SimWorld, config: SimDrainConfig = SimDrainConfig(), random seed: UInt64? = nil) -> SimDrainFacts {
        var random = SimRandom(seed: seed ?? world.seed).fork("drain")
        var facts = SimDrainFacts()
        let macs = redesignMacs(world)
        let promptsBefore = world.allSteps.flatMap(\.prompts).count
        let conflictsAtT0 = max(conflicts(world).count, concurrentConflicts(world))
        var laters = 0
        var answerIndex = 0
        var quiet = 0
        var seenConflicts = Set<String>()
        world.healProviders()
        settle(world)
        for round in 1...max(config.maximumRounds, 1) {
            facts.rounds = round
            let writesBefore = world.writeLog.count
            let promptsAtStart = world.allSteps.flatMap(\.prompts).count
            // A Mac reads the folder at launch and when it is told of a change: a conflict that came into being while the round ran
            // (a file written after the Macs read, on a provider that tells nothing) is shown from the next round on.
            let conflictsAtStart = Set(conflicts(world))
            for mac in macs {
                world.step(world.macs[mac]?.running == true ? .restartApp(mac: mac) : .launch(mac: mac))
            }
            settle(world)
            // A real conflict must be shown before anything is answered (INV-P6).
            for conflict in conflicts(world) where conflictsAtStart.contains(conflict) && seenConflicts.insert(conflict).inserted {
                let mac = SimMacName(String(conflict.prefix(while: { $0 != ":" })))
                if world.brains[mac]?.hint == nil, world.brains[mac]?.openPrompt == nil {
                    facts.unansweredConflicts.append(conflict)
                }
            }
            var guardCount = 0
            while !openSheets(world).isEmpty, guardCount < (config.answerOneAtATime ? 24 : 8) {
                for mac in config.answerOneAtATime ? Array(openSheets(world).prefix(1)) : openSheets(world) {
                    world.step(.answer(mac: mac, chooseAnswer(config, random: &random, laters: &laters, index: &answerIndex)))
                }
                settle(world)
                guardCount += 1
            }
            facts.finalRoundWrites = world.writeLog.count - writesBefore
            facts.finalHints = hints(world)
            let newPrompts = world.allSteps.flatMap(\.prompts).count - promptsAtStart
            if facts.finalRoundWrites == 0, facts.finalHints.isEmpty, newPrompts == 0 {
                quiet += 1
            } else {
                quiet = 0
            }
            if quiet >= config.quietRounds {
                facts.quiescent = true
                break
            }
        }
        facts.laters = laters
        facts.promptsAfterT0 = world.allSteps.flatMap(\.prompts).count - promptsBefore
        facts.promptBound = conflictsAtT0 + macs.count + laters + 2 * world.groundTruth.crossingAnswerPairs()
        facts.disagreements = agreement(world, macs: macs)
        facts.unreached = progress(world, macs: macs)
        if let fresh = config.fresh, let reference = macs.first(where: { world.macs[$0]?.enabled == true }) {
            joinFresh(world, fresh: fresh, reference: reference, config: config, facts: &facts)
        }
        world.drainFacts = facts
        for oracle in SimOracleSet.liveness.oracles {
            if let violation = oracle.check(world, event: nil) { world.report(violation) }
        }
        world.runOracles(.drain)
        return facts
    }

    /// Whether two Macs hold different values of a unit in a way that counts as a disagreement. The same setting in
    /// another encoding is no difference (`SimUnits.equivalent`), and neither is a unit one Mac holds only as
    /// an automatic value and the other lacks or holds as one: an automatic store is no change of the user's, so it is
    /// never synchronized and never wins (decision D-04). The same holds for a value of the macOS 27 arrangement that its Mac's sync
    /// state lost before it left the Mac (a restore): the arrangement is captured from the user's intents only, because holzBar's own
    /// stores write the same keys, so nothing finds the value again until the user moves the application once more.
    static func differs(_ world: SimWorld, _ unit: String, _ left: SimValue?, _ right: SimValue?) -> Bool {
        if SimUnits.equivalent(unit, left, right) { return false }
        let scoped = SimUnits.generationScope(unit) == 27
        func isAutomaticOrAbsent(_ value: SimValue?) -> Bool {
            guard let value else { return true }
            let tokens = value.tokens
            return !tokens.isEmpty && tokens.allSatisfy {
                world.groundTruth.origin(of: $0) == .automatic || world.groundTruth.wasPlacedAutomatically($0)
                    || (scoped && world.groundTruth.lostToAmnesia(token: $0))
            }
        }
        return !(isAutomaticOrAbsent(left) && isAutomaticOrAbsent(right))
    }

    /// Whether the unit is in a conflict that no Mac can answer: one of its live values was made by a Mac that lost its sync state (and
    /// with it the identity under which the entry stands), so the entry belongs to no Mac that runs, and the Macs that remain are
    /// bystanders of it, which the drain does not ask.
    static func isOrphanConflict(_ world: SimWorld, _ unit: String) -> Bool {
        guard world.groundTruth.unitsWithConcurrentValues().contains(unit) else { return false }
        if hasNoPartyThatRuns(world, unit) { return true }
        return world.groundTruth.changes.contains { change in
            change.unit == unit && change.tokens.contains { token in
                world.groundTruth.lostToAmnesia(token: token) && world.groundTruth.isLive(token: token, unit: unit)
            }
        }
    }

    /// Whether no Mac that synchronizes made a live value of the unit's conflict. The Macs that stopped sync (Turn Off) are not asked any
    /// more, and the Macs that remain are bystanders: they get a Settings line, not a hint or a sheet (D-10, INV-P7), and answer it only
    /// by choosing in Settings, which the drain does not do. Until someone does, they hold what they held, which the conflict allows (a
    /// bystander applies neither value).
    static func hasNoPartyThatRuns(_ world: SimWorld, _ unit: String) -> Bool {
        let truth = world.groundTruth
        for change in truth.changes where change.unit == unit && change.kind == .user && world.macs[change.mac]?.enabled == true
            && SimWorld.isRedesign(build: change.build) {
            if change.tokens.contains(where: { truth.isLive(token: $0, unit: unit) }) { return false }
            // A deletion of a Mac that still synchronizes stands until a later change that knew of it.
            if change.tokens.isEmpty, !truth.changes.contains(where: { $0.unit == unit && $0.id > change.id && truth.knew($0, of: change) }) { return false }
        }
        for change in truth.changes where change.unit == unit && change.kind == .answer && world.macs[change.mac]?.enabled == true {
            if !change.retainedTokens.isEmpty { return false }
        }
        return true
    }

    /// INV-C1: every pair of redesigned Macs agrees on every synced unit that is comparable between them.
    static func agreement(_ world: SimWorld, macs: [SimMacName]) -> [String] {
        let live = macs.filter { world.macs[$0]?.enabled == true }
        var units = Set<String>()
        for mac in live {
            let state = world.macs[mac]!
            for (unit, _) in SimUnits.units(of: state.defaults) where SimLocalKeys.isSyncedUnit(unit, generation: state.generation) {
                units.insert(unit)
            }
        }
        var found: [String] = []
        for unit in units.sorted() where !isOrphanConflict(world, unit) {
            let comparable = live.filter { world.groundTruth.isComparable(unit: unit, on: $0) }
            guard let first = comparable.first else { continue }
            let reference = SimUnits.value(of: unit, in: world.macs[first]!.defaults)
            for other in comparable.dropFirst() where differs(world, unit, SimUnits.value(of: unit, in: world.macs[other]!.defaults), reference) {
                found.append("\(unit): \(first) and \(other) differ")
                break
            }
        }
        return found
    }

    /// INV-C5: every live user change of a redesigned Mac reaches every other comparable redesigned Mac as an applied
    /// value, a waiting change, a sheet that shows it, or a later informed change.
    static func progress(_ world: SimWorld, macs: [SimMacName]) -> [String] {
        let live = macs.filter { world.macs[$0]?.enabled == true }
        var found: [String] = []
        for change in world.groundTruth.changes where change.kind == .user && !change.tokens.isEmpty {
            // A change that its own Mac's settings lost (a restore, a copy) before it left the Mac has nothing to reach the others.
            guard let unit = change.unit, live.contains(change.mac), !world.groundTruth.userForgot(change) else { continue }
            for token in change.tokens where world.groundTruth.isLive(token: token, unit: unit) && !world.groundTruth.wasDestroyedByNonSync(token)
                && !(SimUnits.generationScope(unit) == 27 && world.groundTruth.lostToAmnesia(token: token)) {
                // A value that a beta1 or beta2 build made, and that its Mac no longer holds (that build's own sync removed it from the
                // settings, as a file without it does at a launch), is no change of a redesigned Mac: nothing holds it to send.
                let holder = world.macs[change.mac]
                let held = holder.map { SimUnits.tokens(in: $0.defaults).contains(token) } ?? false
                if !SimWorld.isRedesign(build: change.build), !held, !(world.brains[change.mac]?.heldTokens.contains(token) ?? false) { continue }
                for mac in live where mac != change.mac && world.groundTruth.isComparable(unit: unit, on: mac) {
                    let state = world.macs[mac]!
                    var holds = SimUnits.tokens(in: state.defaults).contains(token)
                    holds = holds || (world.brains[mac]?.heldTokens.contains(token) ?? false)
                    if let prompt = world.brains[mac]?.openPrompt {
                        holds = holds || prompt.shown.contains { $0.local == token || $0.folder == token }
                    }
                    if !holds { found.append("\(token) of \(change.mac) never reached \(mac)") }
                }
            }
        }
        return found
    }

    /// INV-C6: a fresh Mac that joins after the drain decodes exactly the agreed state.
    private static func joinFresh(
        _ world: SimWorld, fresh: SimMacName, reference: SimMacName, config: SimDrainConfig, facts: inout SimDrainFacts
    ) {
        guard let source = world.macs[reference], world.macs[fresh] == nil else { return }
        let folder = config.freshFolder ?? source.folderID ?? "F1"
        world.addMac(SimMacSpec(fresh, .redesign, generation: source.generation, enabled: true, folder: folder, running: false))
        facts.freshChecked = true
        var previous: [String: SimValue]?
        for _ in 0..<config.maximumRounds {
            world.step(world.macs[fresh]?.running == true ? .restartApp(mac: fresh) : .launch(mac: fresh))
            settle(world)
            var guardCount = 0
            while world.brains[fresh]?.openPrompt != nil, guardCount < 8 {
                world.step(.answer(mac: fresh, .use))
                settle(world)
                guardCount += 1
            }
            let current = world.macs[fresh]!.defaults
            if current == previous { break }
            previous = current
        }
        let freshState = world.macs[fresh]!
        var units = Set<String>()
        for state in [source, freshState] {
            for (unit, _) in SimUnits.units(of: state.defaults) where SimLocalKeys.isSyncedUnit(unit, generation: state.generation) {
                units.insert(unit)
            }
        }
        for unit in units.sorted()
        where !isOrphanConflict(world, unit)
            && differs(world, unit, SimUnits.value(of: unit, in: source.defaults), SimUnits.value(of: unit, in: freshState.defaults)) {
            facts.freshMismatches.append(unit)
        }
    }
}

// MARK: - Liveness oracles

/// INV-C1 to C6 and INV-P6, over the facts of one drain. They run at the `.drain` moment.
enum SimLivenessOracles {
    static var all: [any SimOracle] { [c1, c2, c3, c4, c5, c6, p6] }

    private static func facts(_ world: SimWorld) -> SimDrainFacts? { world.drainFacts }

    static let c1 = SimClosureOracle("INV-C1", .drain) { world, _ in
        facts(world)?.disagreements.first.map { "the Macs disagree on a synced unit after the drain: \($0)" }
    }

    static let c2 = SimClosureOracle("INV-C2", .drain) { world, _ in
        guard let facts = facts(world), !facts.quiescent, facts.finalRoundWrites > 0 else { return nil }
        return "Macs still write after \(facts.rounds) rounds of relaunches and deliveries (\(facts.finalRoundWrites) writes in the last)"
    }

    static let c3 = SimClosureOracle("INV-C3", .drain) { world, _ in
        guard let facts = facts(world), facts.promptsAfterT0 > facts.promptBound else { return nil }
        return "\(facts.promptsAfterT0) questions after T0, above the bound of \(facts.promptBound)"
    }

    static let c4 = SimClosureOracle("INV-C4", .drain) { world, _ in
        guard let facts = facts(world), !facts.quiescent, facts.finalRoundWrites == 0, !facts.finalHints.isEmpty else { return nil }
        return "relaunches alone keep a hint or sheet open on \(facts.finalHints.joined(separator: ", "))"
    }

    static let c5 = SimClosureOracle("INV-C5", .drain) { world, _ in
        facts(world)?.unreached.first.map { "no progress: \($0)" }
    }

    static let c6 = SimClosureOracle("INV-C6", .drain) { world, _ in
        guard let facts = facts(world), facts.freshChecked, !facts.freshMismatches.isEmpty else { return nil }
        return "a fresh Mac joining after the drain differs from the agreed state at \(facts.freshMismatches.joined(separator: ", "))"
    }

    static let p6 = SimClosureOracle("INV-P6", .drain) { world, _ in
        facts(world)?.unansweredConflicts.first.map { "a real conflict persists with no hint and no sheet: \($0)" }
    }
}
