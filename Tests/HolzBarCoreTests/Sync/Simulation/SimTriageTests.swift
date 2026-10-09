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

    @Test("S5 seed 230 reduced")
    func s5() {
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_SCENARIOS"] != nil else { return }
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
        guard ProcessInfo.processInfo.environment["SYNC_TRIAGE_SCENARIOS"] != nil else { return }
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
