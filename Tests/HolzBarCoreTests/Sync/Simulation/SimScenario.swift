import Foundation
import Testing

/// What a scenario expects at the point where it is written.
enum SimExpectation: Sendable {
    case value(mac: SimMacName, unit: String, SimValue)
    case unset(mac: SimMacName, unit: String)
    case prompts(count: Int, mac: SimMacName?)
    case hint(mac: SimMacName, present: Bool)
    case noWrite(mac: SimMacName)
    case folderFiles(mac: SimMacName, paths: [String])
    case noViolation([SimInvariantID]?)
}

/// The result of running a scenario: one message per failed expectation, each with the scenario name.
struct SimScenarioResult {
    var name: String
    var failures: [String]
    var world: SimWorld

    var passed: Bool { failures.isEmpty }
}

/// The scenario DSL for the fixed catalogue tests: Macs, steps and expectations written as builder calls, run
/// through the simulation world. A failing run prints with `SimScenarioPrinter` as the same builder calls.
struct SimScenario {
    enum Step {
        case event(SimEvent)
        case deliverAll
        case checkpoint
        case expect(SimExpectation)
        /// A free step: it may drive the world (settle, relaunch) or read it, and returns one text per failure.
        case perform(String, (SimWorld) -> [String])
    }

    var name: String
    var seed: UInt64
    var preset: SimProviderPreset?
    var policy: SimFaultPolicy?
    var specs: [SimMacSpec] = []
    var steps: [Step] = []
    var oracles = SimOracleSet.safety
    var brainFactory: SimWorld.BrainFactory?

    init(_ name: String, seed: UInt64 = 1, preset: SimProviderPreset? = nil, policy: SimFaultPolicy? = nil) {
        self.name = name
        self.seed = seed
        self.preset = preset
        self.policy = policy
    }

    // MARK: Setup

    func macs(_ specs: [SimMacSpec]) -> SimScenario { var copy = self; copy.specs = specs; return copy }
    func macs(_ specs: SimMacSpec...) -> SimScenario { macs(specs) }
    func oracles(_ set: SimOracleSet) -> SimScenario { var copy = self; copy.oracles = set; return copy }
    func brains(_ factory: @escaping SimWorld.BrainFactory) -> SimScenario { var copy = self; copy.brainFactory = factory; return copy }

    // MARK: Steps

    private func add(_ step: Step) -> SimScenario { var copy = self; copy.steps.append(step); return copy }

    func event(_ event: SimEvent) -> SimScenario { add(.event(event)) }
    func provider(_ event: SimProviderEvent) -> SimScenario { add(.event(.provider(event))) }

    func edit(_ mac: SimMacName, _ unit: String, value: SimValue? = nil) -> SimScenario { event(.userEdit(mac: mac, unit: unit, value: value)) }
    func delete(_ mac: SimMacName, _ unit: String) -> SimScenario { event(.userDelete(mac: mac, unit: unit)) }
    func importFile(_ mac: SimMacName, units: [String]) -> SimScenario { event(.userImport(mac: mac, units: units)) }
    func setHotkey(_ mac: SimMacName, action: String, combo: Int) -> SimScenario { event(.setHotkey(mac: mac, action: action, combo: combo)) }
    func chooseItemIcon(_ mac: SimMacName, item: String) -> SimScenario { event(.chooseItemIcon(mac: mac, item: item)) }
    func oversizeIcon(_ mac: SimMacName) -> SimScenario { event(.oversizeIcon(mac: mac)) }
    func moveApp27(_ mac: SimMacName, bundle: String, section: Int) -> SimScenario { event(.moveApp27(mac: mac, bundle: bundle, section: section)) }
    func applyProfile(_ mac: SimMacName, _ profile: String, byUser: Bool = true) -> SimScenario { event(.applyProfile(mac: mac, profile: profile, byUser: byUser)) }
    func saveProfile(_ mac: SimMacName, _ profile: String) -> SimScenario { event(.saveProfile(mac: mac, profile: profile)) }
    func renameProfile(_ mac: SimMacName, _ profile: String) -> SimScenario { event(.renameProfile(mac: mac, profile: profile)) }
    func deleteProfile(_ mac: SimMacName, _ profile: String) -> SimScenario { event(.deleteProfile(mac: mac, profile: profile)) }
    func turnOn(_ mac: SimMacName, folder: String = "F1") -> SimScenario { event(.turnOn(mac: mac, folder: folder)) }
    func turnOff(_ mac: SimMacName) -> SimScenario { event(.turnOff(mac: mac)) }
    func changeFolder(_ mac: SimMacName, folder: String) -> SimScenario { event(.changeFolder(mac: mac, folder: folder)) }
    func answer(_ mac: SimMacName, _ answer: SimAnswer) -> SimScenario { event(.answer(mac: mac, answer)) }
    func autoPlace(_ mac: SimMacName, _ unit: String) -> SimScenario { event(.autoPlace(mac: mac, unit: unit)) }
    func learn(_ mac: SimMacName, _ key: String) -> SimScenario { event(.learn(mac: mac, key: key)) }
    func setFlag(_ mac: SimMacName, _ key: String) -> SimScenario { event(.setFlag(mac: mac, key: key)) }
    func seed27(_ mac: SimMacName) -> SimScenario { event(.seed27(mac: mac)) }
    func placeNewApp27(_ mac: SimMacName, bundle: String) -> SimScenario { event(.placeNewApp27(mac: mac, bundle: bundle)) }
    func upgradeOS(_ mac: SimMacName) -> SimScenario { event(.upgradeOS(mac: mac)) }
    func launch(_ mac: SimMacName) -> SimScenario { event(.launch(mac: mac)) }
    func quit(_ mac: SimMacName) -> SimScenario { event(.quit(mac: mac)) }
    func crash(_ mac: SimMacName) -> SimScenario { event(.crash(mac: mac)) }
    func restartApp(_ mac: SimMacName) -> SimScenario { event(.restartApp(mac: mac)) }
    func updateApp(_ mac: SimMacName, _ version: SimMacVersion) -> SimScenario { event(.updateApp(mac: mac, version: version)) }
    func clone(from: SimMacName, to: SimMacName) -> SimScenario { event(.clone(from: from, to: to)) }
    func copyAccount(from: SimMacName, to: SimMacName) -> SimScenario { event(.copyAccount(from: from, to: to)) }
    func restorePrefs(_ mac: SimMacName) -> SimScenario { event(.restorePrefs(mac: mac)) }
    func restoreSigma(_ mac: SimMacName) -> SimScenario { event(.restoreSigma(mac: mac)) }
    func restoreHome(_ mac: SimMacName, keepCaches: Bool) -> SimScenario { event(.restoreHome(mac: mac, keepCaches: keepCaches)) }
    func sigmaLost(_ mac: SimMacName) -> SimScenario { event(.sigmaLost(mac: mac)) }
    func reinstall(_ mac: SimMacName) -> SimScenario { event(.reinstall(mac: mac)) }
    func advance(seconds: Int64) -> SimScenario { event(.advance(milliseconds: seconds * 1000)) }
    func advance(milliseconds: Int64) -> SimScenario { event(.advance(milliseconds: milliseconds)) }
    func clockStep(_ mac: SimMacName, milliseconds: Int64) -> SimScenario { event(.clockStep(mac: mac, milliseconds: milliseconds)) }
    /// The Mac neither sends nor receives for `seconds`.
    func offline(_ mac: SimMacName, seconds: Int64) -> SimScenario { provider(.offline(mac: mac, forMilliseconds: seconds * 1000)) }
    /// The Mac is back at once.
    func online(_ mac: SimMacName) -> SimScenario { provider(.offline(mac: mac, forMilliseconds: 0)) }
    /// Delivers every queued write and lets every timer run.
    func deliverAll() -> SimScenario { add(.deliverAll) }
    /// Marks the point `expectNoWrite` counts from.
    func checkpoint() -> SimScenario { add(.checkpoint) }

    // MARK: Expectations

    func expectValue(_ mac: SimMacName, _ unit: String, _ value: SimValue) -> SimScenario { add(.expect(.value(mac: mac, unit: unit, value))) }
    func expectUnset(_ mac: SimMacName, _ unit: String) -> SimScenario { add(.expect(.unset(mac: mac, unit: unit))) }
    func expectPrompts(count: Int, mac: SimMacName? = nil) -> SimScenario { add(.expect(.prompts(count: count, mac: mac))) }
    func expectHint(_ mac: SimMacName, present: Bool = true) -> SimScenario { add(.expect(.hint(mac: mac, present: present))) }
    /// The Mac wrote nothing since the last checkpoint (or the start).
    func expectNoWrite(_ mac: SimMacName) -> SimScenario { add(.expect(.noWrite(mac: mac))) }
    func expectFolderFiles(_ paths: [String], mac: SimMacName = .A) -> SimScenario { add(.expect(.folderFiles(mac: mac, paths: paths))) }
    func expectNoViolation(_ ids: [SimInvariantID]? = nil) -> SimScenario { add(.expect(.noViolation(ids))) }

    /// A free step: `body` drives or reads the world and returns a text for every failed expectation.
    func perform(_ label: String, _ body: @escaping (SimWorld) -> [String]) -> SimScenario { add(.perform(label, body)) }

    // MARK: Running

    /// The events of the scenario, in order.
    var events: [SimEvent] {
        steps.compactMap { if case .event(let event) = $0 { event } else { nil } }
    }

    func run() -> SimScenarioResult {
        let world = SimWorld(seed: seed, macs: specs, preset: preset, policy: policy, brainFactory: brainFactory, oracles: oracles)
        var failures: [String] = []
        var checkpointWrites = world.writeLog.count
        func fail(_ text: String) { failures.append("scenario \"\(name)\": \(text)") }
        for step in steps {
            switch step {
            case .event(let event):
                world.step(event)
            case .deliverAll:
                SimDrain.settle(world)
            case .checkpoint:
                checkpointWrites = world.writeLog.count
            case .perform(let label, let body):
                for text in body(world) { fail("\(label): \(text)") }
            case .expect(let expectation):
                switch expectation {
                case .value(let mac, let unit, let expected):
                    let actual = SimUnits.value(of: unit, in: world.defaults(of: mac))
                    if actual != expected { fail("\(mac) holds \(actual?.canonical ?? "nothing") at \(unit), expected \(expected.canonical)") }
                case .unset(let mac, let unit):
                    if let actual = SimUnits.value(of: unit, in: world.defaults(of: mac)) {
                        fail("\(mac) holds \(actual.canonical) at \(unit), expected it to be unset")
                    }
                case .prompts(let count, let mac):
                    let shown = world.allSteps.flatMap(\.prompts).filter { mac == nil || $0.mac == mac }.count
                    if shown != count { fail("\(shown) prompts\(mac.map { " on \($0)" } ?? ""), expected \(count)") }
                case .hint(let mac, let present):
                    let hint = world.brains[mac]?.hint
                    if (hint != nil) != present { fail("\(mac) hint is \(hint ?? "absent"), expected it \(present ? "present" : "absent")") }
                case .noWrite(let mac):
                    let writes = world.writeLog.dropFirst(checkpointWrites).filter { $0.mac == mac }
                    if let first = writes.first { fail("\(mac) wrote \(first.path) after the checkpoint") }
                case .folderFiles(let mac, let paths):
                    let present = world.replica(of: mac).entries.compactMap { path, entry -> String? in
                        if case .absent = entry { return nil }
                        return path
                    }.sorted()
                    if present != paths.sorted() { fail("\(mac) sees the files \(present), expected \(paths.sorted())") }
                case .noViolation(let ids):
                    let found = world.oracleViolations.filter { ids == nil || ids!.contains($0.id) }
                    if let first = found.first { fail("\(first.id) violated: \(first.description)") }
                }
            }
        }
        return SimScenarioResult(name: name, failures: failures, world: world)
    }

    /// Runs the scenario and records one test issue per failed expectation.
    @discardableResult
    func check(sourceLocation: SourceLocation = #_sourceLocation) -> SimScenarioResult {
        let result = run()
        for failure in result.failures { Issue.record(Comment(rawValue: failure), sourceLocation: sourceLocation) }
        return result
    }
}
