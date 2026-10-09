//
//  SimTriageTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// A tool, not a check: reproduces and shrinks one seed of the exploration for triage. It does nothing unless `SYNC_TRIAGE` is set to
/// `<invariant> <preset> <seed> [clean|disturbed] [steps]`, for example `SYNC_TRIAGE="INV-S5 hostile 173"`. The shrunk scenario and the
/// test that reproduces it are printed. The tool takes the violation of the invariant from the unfiltered oracle result, so it also
/// works for the invariants that a family leaves out.
@Suite("Simulation triage")
struct SimTriageTests {
    @Test("Reproduces and shrinks the seed named by SYNC_TRIAGE")
    func triage() {
        guard let spec = ProcessInfo.processInfo.environment["SYNC_TRIAGE"], !spec.isEmpty else { return }
        let parts = spec.split(separator: " ").map(String.init)
        guard parts.count >= 3, let preset = SimProviderPreset(rawValue: parts[1]), let seed = UInt64(parts[2]) else {
            Issue.record(Comment(rawValue: "SYNC_TRIAGE is `<invariant> <preset> <seed> [clean|disturbed] [steps]`, got \(spec)"))
            return
        }
        let disturbed = parts.count > 3 && parts[3] == "disturbed"
        let steps = parts.count > 4 ? Int(parts[4]) ?? 400 : 400
        let result = SimExploration.run(seed: seed, preset: preset, steps: steps, evidenceLoss: disturbed)
        let wanted = result.world.oracleViolations.filter { $0.id.rawValue == parts[0] }
        print("TRIAGE seed \(seed) \(preset.rawValue): \(result.macs.map { "\($0.name)=\($0.version)" }.joined(separator: " ")); \(result.events.count) events; violations: \(result.world.oracleViolations.map { $0.id.rawValue })")
        guard let violation = wanted.first else {
            print("TRIAGE no violation of \(parts[0])")
            return
        }
        let noShrink = ProcessInfo.processInfo.environment["SYNC_TRIAGE_NOSHRINK"] != nil
        if noShrink {
            print("TRIAGE writes\n\(Self.dump(result.world))")
            return
        }
        let failure = SimExploration.shrunkFailure(seed: seed, preset: preset, macs: result.macs, events: result.events, violation: violation)
        print("TRIAGE shrunk to \(failure.events.count) events\n\(SimExploration.text(of: failure))")
        let world = SimExploration.run(seed: seed, preset: preset, macs: result.macs, events: failure.events)
        print("TRIAGE writes\n\(Self.dump(world))")
    }

    /// Runs seeds without shrinking and says which invariants each trips (`SYNC_SWEEP="<preset>:<seed>[:disturbed],..."`, steps from `SYNC_SWEEP_STEPS`).
    @Test("Runs the seeds named by SYNC_SWEEP")
    func sweep() async {
        guard let spec = ProcessInfo.processInfo.environment["SYNC_SWEEP"], !spec.isEmpty else { return }
        let steps = ProcessInfo.processInfo.environment["SYNC_SWEEP_STEPS"].flatMap { Int($0) } ?? 400
        let items = spec.split(separator: ",").map { $0.split(separator: ":").map(String.init) }
        let lines = await withTaskGroup(of: String.self) { group in
            for item in items where item.count >= 2 {
                group.addTask {
                    guard let preset = SimProviderPreset(rawValue: item[0]), let seed = UInt64(item[1]) else { return "bad item \(item)" }
                    let disturbed = item.count > 2 && item[2] == "disturbed"
                    let result = SimExploration.run(seed: seed, preset: preset, steps: steps, evidenceLoss: disturbed)
                    let left = SimExploration.violations(in: result.world, family: disturbed ? .disturbed : .clean)
                    let all = Set(result.world.oracleViolations.map(\.id.rawValue)).sorted().joined(separator: " ")
                    return "SWEEP \(item.joined(separator: ":")): counted [\(left.map(\.id.rawValue).joined(separator: " "))] all [\(all)]"
                }
            }
            var found: [String] = []
            for await line in group { found.append(line) }
            return found.sorted()
        }
        for line in lines { print(line) }
    }

    /// Reproduces and shrinks a pair of the metamorphic tests: `SYNC_PAIR="<automatic|delivery> <preset> <seed> [invariant]"` runs the
    /// pair exactly as `SimulationTests.metamorphicPairs` / `deliveryPairs` do (50 resp. 40 quiet steps) and prints what differs and the
    /// shrunk trace.
    @Test("Reproduces the pair named by SYNC_PAIR")
    func pair() {
        guard let spec = ProcessInfo.processInfo.environment["SYNC_PAIR"], !spec.isEmpty else { return }
        let parts = spec.split(separator: " ").map(String.init)
        guard parts.count >= 3, let preset = SimProviderPreset(rawValue: parts[1]), let seed = UInt64(parts[2]) else {
            Issue.record(Comment(rawValue: "SYNC_PAIR is `<automatic|delivery> <preset> <seed>`, got \(spec)"))
            return
        }
        let delivery = parts[0] == "delivery"
        let macs = delivery ? SimExploration.mix(seed: seed, allowing: [.redesign, .redesignSkew]) : SimExploration.mix(seed: seed)
        let events = SimExploration.events(seed: seed, preset: nil, macs: macs, steps: delivery ? 40 : 50, quiet: true)
        let setup = SimMetaSetup(seed: seed, preset: preset, macs: macs, brainFactory: SimExploration.brain)
        func run(_ candidate: [SimEvent]) -> [SimViolation] {
            delivery ? SimMetamorphic.deliveryIndependence(setup, candidate) : SimMetamorphic.automaticEventsInvisible(setup, candidate, insertionSeed: seed)
        }
        let found = run(events)
        print("PAIR seed \(seed) \(preset.rawValue): \(macs.map { "\($0.name)=\($0.version)" }.joined(separator: " ")); \(events.count) events")
        for violation in found { print("PAIR \(violation.id.rawValue): \(violation.description)") }
        guard let first = found.first else {
            print("PAIR no violation")
            return
        }
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_NOSHRINK"] == nil else { return }
        let shrunk = SimShrinker(maximumRuns: 400).shrink(events) { run($0).contains { $0.id == first.id } }
        let violation = run(shrunk).first { $0.id == first.id } ?? first
        print("PAIR shrunk to \(shrunk.count) events: \(violation.description)")
        print(SimScenarioPrinter.a1Style(SimFailure(name: "pair \(parts[0]) seed \(seed)", seed: seed, preset: preset, macs: macs, events: shrunk, violation: violation)))
        if delivery, ProcessInfo.processInfo.environment["SYNC_PAIR_DUMP"] != nil {
            // The baseline and the variants of INV-F2, each settled the way the pair settles them, with what each Mac wrote and read.
            var permuted = SimFaultPolicy(medianDelayMilliseconds: 4_000, coalesceProbability: 0.5)
            permuted.signalsFolderChanges = true
            for (label, policy, variantSeed) in [("ideal", SimFaultPolicy.ideal, seed), ("permuted 11", permuted, 11), ("permuted 12", permuted, 12), ("permuted 13", permuted, 13)] {
                let run = SimMetamorphic.observe(setup, shrunk, policy: policy, seed: UInt64(variantSeed))
                var config = SimDrainConfig()
                config.answers = .use
                config.fresh = nil
                SimDrain.run(run.world, config: config)
                print("PAIRDUMP \(label)\n\(Self.dump(run.world))")
            }
        }
    }

    /// The writes of a world with what each file says, for reading a minimized trace.
    static func dump(_ world: SimWorld) -> String {
        var lines: [String] = []
        for write in world.writeLog {
            let name = write.path.split(separator: "/").last.map(String.init) ?? write.path
            lines.append("step \(write.stepIndex) t=\(write.time) \(write.mac) \(write.hook.rawValue) wrote \(write.path) v\(write.version.map(String.init) ?? "failed") changes<\(write.changeCount)")
            if case .success(let contents) = SyncDeviceFile.decode(write.data, fileName: name) {
                lines.append("    context \(contents.replica.context)")
                for key in contents.replica.keys {
                    lines.append("    \(key): \(contents.replica.live(key).map { "\($0.dot) \($0.payload)" }.joined(separator: " | "))")
                }
            }
        }
        for (name, _) in world.macs.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            let defaults = world.defaults(of: name)
            lines.append("final \(name) defaults: \(defaults.keys.sorted().map { "\($0)=\(defaults[$0]?.canonical ?? "nil")" }.joined(separator: ", "))")
        }
        // SYNC_TRIAGE_HOOKS="A,B": every hook of those Macs, with the reads, the ingests and the writes of each.
        if let macs = ProcessInfo.processInfo.environment["SYNC_TRIAGE_HOOKS"], !macs.isEmpty {
            let wanted = Set(macs.split(separator: ",").map(String.init))
            for step in world.allSteps {
                lines.append("step \(step.index) t=\(step.time) \(step.event)")
                for hook in step.hooks where wanted.contains("\(hook.mac)") {
                    var parts = ["    \(hook.mac) \(hook.name.rawValue)"]
                    for read in hook.reads {
                        let name = read.entry.path.split(separator: "/").last.map(String.init) ?? read.entry.path
                        parts.append("read \(name.prefix(8)) -> \(String(describing: read.entry.result).prefix(12)) v\(read.version) replicaV\(read.replicaVersion)")
                    }
                    if !hook.ingests.isEmpty { parts.append("ingest \(hook.ingests) dominated \(hook.dominatedIngests)") }
                    for write in hook.writes {
                        parts.append("write \(write.path.split(separator: "/").last.map { String($0.prefix(8)) } ?? "") v\(write.version.map(String.init) ?? "failed") prev v\(write.previousVersion) seen=\(write.previousSeenInSession) dominated=\(write.previousDominated)")
                    }
                    lines.append(parts.joined(separator: "; "))
                }
            }
        }
        for step in world.allSteps where step.hooks.contains(where: { !$0.prompts.isEmpty || $0.answered != nil }) {
            lines.append("hooks of step \(step.index) (\(step.event)) t=\(step.time)")
            for hook in step.hooks {
                lines.append("    hook \(hook.mac) \(hook.name.rawValue) reads=\(hook.reads.count) writes=\(hook.writes.count) prompts=\(hook.prompts.count) open=\(hook.openPromptAtStart != nil) transitions=\(hook.transitions.count)")
            }
        }
        for shown in world.groundTruth.prompts {
            lines.append("prompt \(shown.mac) t=\(shown.time) id \(shown.prompt.id) \(shown.prompt.title): \(shown.prompt.shown.map { "\($0.unit) local=\($0.local ?? "-") folder=\($0.folder ?? "-")" }.joined(separator: "; ")) answer=\(String(describing: shown.answer))")
        }
        for violation in world.oracleViolations {
            lines.append("violation \(violation.id.rawValue) step \(violation.stepIndex): \(violation.description)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Hand-written traces under triage (work in progress, not part of the checks that must pass).
@Suite("Simulation triage scenarios")
struct SimTriageScenarioTests {
    /// Runs a hand-written scenario with the drain of the exploration and prints it.
    static func show(_ scenario: SimScenario) {
        let world = SimExploration.run(seed: scenario.seed, preset: scenario.preset, macs: scenario.specs, events: scenario.events)
        print("TRIAGE writes\n\(SimTriageTests.dump(world))")
    }

    @Test("A6 seed 77 reduced")
    func a6() {
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_SCENARIOS"] == "a6" else { return }
        Self.show(SimScenario("A6", seed: 77, preset: .nextcloud)
            .macs([
                SimMacSpec(.A, .redesign, running: true),
                SimMacSpec(.B, .beta2, generation: 27, running: true, clockOffsetMilliseconds: 7200000),
                SimMacSpec(.C, .redesign, generation: 27, running: true),
            ])
            .setHotkey(.C, action: "show", combo: 0)
            .restartApp(.C)
            .reinstall(.C)
            .restoreSigma(.C)
            .launch(.C)
            .restartApp(.C)
            .turnOn(.C, folder: "F1"))
    }

    @Test("S6 seed 22 reduced")
    func s6() {
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_SCENARIOS"] == "s6" else { return }
        Self.show(SimScenario("S6", seed: 22, preset: .syncthing)
            .macs([
                SimMacSpec(.A, .redesign, generation: 27, running: true, clockOffsetMilliseconds: 3600000),
                SimMacSpec(.B, .beta1, running: true, clockOffsetMilliseconds: -3600000),
                SimMacSpec(.C, .redesignSkew, running: true),
            ])
            .edit(.A, "ItemSpacingOffset")
            .crash(.A)
            .launch(.A)
            .moveApp27(.A, bundle: "com.app.b", section: 2)
            .advance(seconds: 6)
            .restoreHome(.A, keepCaches: false))
    }

    @Test("S5 seed 230 reduced")
    func s5() {
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_SCENARIOS"] == "old" else { return }
        Self.show(SimScenario("S5", seed: 230, preset: .iCloud)
            .macs([
                SimMacSpec(.A, .redesign, generation: 27, running: true, clockOffsetMilliseconds: 3600000),
                SimMacSpec(.B, .redesign, generation: 27, running: true),
            ])
            .importFile(.B, units: ["RehideInterval", "UseIceBar", "UseIceBar"])
            .turnOff(.B)
            .delete(.B, "UseIceBar")
            .edit(.A, "Hotkeys/toggle")
            .provider(.deleteFolder())
            .advance(seconds: 6)
            .turnOn(.B, folder: "F1"))
    }

    @Test("S5 own file gone, the group holds the value")
    func s5OwnFileGone() {
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_SCENARIOS"] == "old" else { return }
        Self.show(SimScenario("S5b", seed: 230, preset: nil)
            .macs([
                SimMacSpec(.A, .redesign, generation: 27, running: true),
                SimMacSpec(.B, .redesign, generation: 27, running: true),
            ])
            .edit(.B, "UseIceBar")
            .advance(seconds: 20)
            .offline(.B, seconds: 3600)
            .edit(.A, "Hotkeys/toggle")
            .advance(seconds: 20)
            .turnOff(.B)
            .delete(.B, "UseIceBar")
            .provider(.delete(path: "holzBar/Macs/B.plist"))
            .advance(seconds: 20)
            .online(.B)
            .turnOn(.B, folder: "F1"))
    }
}
