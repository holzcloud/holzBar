import CryptoKit
import Foundation
import Testing

/// A hand-driven redesigned-style brain that can be told to misbehave in each specific way. Scripts run at the
/// hooks of the world; the test double answers the introspection hooks from `info` and the file format below.
struct SimScriptedBrain: SimSyncBrain, SimBrainIntrospection {
    typealias Script = @Sendable (inout SimMacContext, inout SimScriptedBrain) -> Void
    typealias CommandScript = @Sendable (SimUserCommand, inout SimMacContext, inout SimScriptedBrain) -> Void

    var kind: SimMacVersion = .redesign
    var info = SimBrainReport()
    var prompt: SimPrompt?
    var hintText: String?
    var pending: Set<String> = []
    var counter = 0
    var launchScript: Script?
    var quitScript: Script?
    var changedScript: Script?
    var signalScript: Script?
    var commandScript: CommandScript?

    init(id: String? = nil, kind: SimMacVersion = .redesign) {
        self.kind = kind
        if let id {
            info.deviceID = id
            info.ownFilePath = "holzBar/Macs/\(id).plist"
        }
    }

    mutating func launch(_ context: inout SimMacContext) { let script = launchScript; script?(&context, &self) }
    mutating func quit(_ context: inout SimMacContext) { let script = quitScript; script?(&context, &self) }
    mutating func defaultsChanged(origin: SimChangeOrigin, units: [String], _ context: inout SimMacContext) {
        let script = changedScript
        script?(&context, &self)
    }
    mutating func folderSignal(_ context: inout SimMacContext) { let script = signalScript; script?(&context, &self) }
    mutating func timerFired(tag: String, _ context: inout SimMacContext) {}
    mutating func userCommand(_ command: SimUserCommand, _ context: inout SimMacContext) {
        let script = commandScript
        script?(command, &context, &self)
    }

    var hint: String? { hintText }
    var openPrompt: SimPrompt? { prompt }
    var heldTokens: Set<String> { pending }
    func report() -> SimBrainReport { info }

    // MARK: File format: a property list with plain fields the test sets

    static func file(
        tokens: [String] = [],
        claimed: [String]? = nil,
        deleted: [String]? = nil,
        mentioned: [String]? = nil,
        writer: String? = nil,
        counters: [String: Int]? = nil,
        extra: [String: String] = [:]
    ) -> Data {
        var dictionary: [String: Any] = ["tokens": tokens]
        if let claimed { dictionary["claimed"] = claimed }
        if let deleted { dictionary["deleted"] = deleted }
        if let mentioned { dictionary["mentioned"] = mentioned }
        if let writer { dictionary["writer"] = writer }
        if let counters { dictionary["counters"] = counters }
        for (key, value) in extra { dictionary[key] = value }
        return (try? PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)) ?? Data()
    }

    private static func decode(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    func heldTokens(inFile path: String, data: Data) -> Set<String> {
        Set((Self.decode(data)?["tokens"] as? [String]) ?? [])
    }
    func claimedPast(ofFile path: String, data: Data) -> Set<String>? {
        (Self.decode(data)?["claimed"] as? [String]).map(Set.init)
    }
    func deletedUnits(inFile path: String, data: Data) -> Set<String>? {
        (Self.decode(data)?["deleted"] as? [String]).map(Set.init)
    }
    func mentionedUnits(inFile path: String, data: Data) -> Set<String>? {
        (Self.decode(data)?["mentioned"] as? [String]).map(Set.init)
    }
    func writerID(inFile path: String, data: Data) -> String? { Self.decode(data)?["writer"] as? String }
    func claimedCounter(ofDevice device: String, inFile path: String, data: Data) -> Int? {
        (Self.decode(data)?["counters"] as? [String: Int])?[device]
    }
}

/// One positive and one negative test per oracle, on hand-built worlds. A violation shows up when the brain is
/// told to misbehave and stays away when it does not.
@Suite("SimOracles")
struct SimOracleTests {
    static let a = SimMacName.A
    static let b = SimMacName.B
    static let ownA = "holzBar/Macs/A.plist"
    static let ownB = "holzBar/Macs/B.plist"
    static let unit = "ShowOnHover"
    static let token1 = "u1@ShowOnHover"

    static func running(_ name: SimMacName, _ version: SimMacVersion = .redesign, generation: Int = 26,
                        defaults: [String: SimValue] = [:]) -> SimMacSpec {
        SimMacSpec(name, version, generation: generation, running: true, defaults: defaults)
    }

    /// A world with the given brains and only the named oracles.
    static func world(
        _ specs: [SimMacSpec],
        _ brains: [SimMacName: SimScriptedBrain] = [:],
        ids: [SimInvariantID],
        policy: SimFaultPolicy? = nil
    ) -> SimWorld {
        SimWorld(seed: 1, macs: specs, policy: policy, brainFactory: { version, mac in
            switch version {
            case .beta1: SimMacBeta1()
            case .beta2: SimMacBeta2()
            default: brains[mac] ?? SimScriptedBrain(id: mac.name)
            }
        }, oracles: SimOracleSet.safety.only(ids))
    }

    static func found(_ world: SimWorld, _ id: SimInvariantID) -> Bool {
        world.oracleViolations.contains { $0.id == id }
    }

    /// Expects the oracle to fire in `bad` and to stay quiet in `good`.
    static func check(
        _ id: SimInvariantID,
        bad: () -> SimWorld,
        good: () -> SimWorld,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let violated = bad()
        #expect(found(violated, id), "\(id) did not fire on the violating world", sourceLocation: sourceLocation)
        let clean = good()
        #expect(!found(clean, id), "\(id) fired on the clean world: \(clean.oracleViolations.filter { $0.id == id }.map(\.description))", sourceLocation: sourceLocation)
    }

    static func shown(_ local: String?, _ folder: String?, unit: String = SimOracleTests.unit) -> SimPrompt {
        SimPrompt(id: 1, title: "Settings differ", shown: [SimPromptUnit(unit: unit, local: local, folder: folder)])
    }

    /// A brain that shows a sheet at its first defaults change and applies the folder value when answered Use.
    static func asking(_ prompt: SimPrompt, id: String = "A") -> SimScriptedBrain {
        var brain = SimScriptedBrain(id: id)
        brain.changedScript = { context, brain in
            guard brain.prompt == nil else { return }
            brain.counter += 1
            var sheet = prompt
            sheet.id = brain.counter
            brain.prompt = sheet
            context.reportPrompt(sheet)
        }
        brain.commandScript = { command, _, brain in
            if case .answer = command { brain.prompt = nil }
        }
        return brain
    }

    // MARK: Framework

    @Test("The safety set carries at least thirty invariant IDs and a later family can be added")
    func catalogue() {
        let ids = SimOracleSet.safety.ids
        #expect(ids.count >= 30)
        for required: SimInvariantID in ["INV-S1", "INV-S1g", "INV-S6", "INV-PR2", "INV-N1", "INV-J1", "INV-B9"] {
            #expect(ids.contains(required), "missing \(required)")
        }
        let extra = SimClosureOracle("INV-L27-TEST", .step) { _, _ in nil }
        let extended = SimOracleSet.safety.adding([extra]).adding([extra])
        #expect(extended.ids.count == ids.count + 1)
        #expect(SimOracleSet.safety.only(["INV-S1"]).ids == ["INV-S1"])
        #expect(!SimOracleSet.safety.without(["INV-S1"]).ids.contains("INV-S1"))
    }

    @Test("Violations are charged to redesigned Macs only: beta1 and beta2 peers run through every oracle quietly")
    func chargedToRedesignedOnly() {
        let world = SimWorld(seed: 3, macs: [SimMacSpec(.A, .beta1, running: true), SimMacSpec(.B, .beta1, running: true),
                                             SimMacSpec(.C, .beta2, running: true)], oracles: .safety)
        world.run(SimWorldTests.randomEvents(seed: 3, macs: [.A, .B, .C], count: 150))
        #expect(world.oracleViolations.isEmpty, "\(world.oracleViolations.map(\.description))")
    }

    // MARK: INV-S1 to INV-S5

    @Test("INV-S1 fires on an unjustified replacement and accepts one an answer justified")
    func s1() {
        Self.check("INV-S1", bad: {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, _ in context.defaults[SimOracleTests.unit] = .string("overwritten") }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }, good: {
            var brain = Self.asking(Self.shown(Self.token1, "folder-x"))
            let inner = brain.commandScript
            brain.commandScript = { command, context, brain in
                if case .answer(.use) = command { context.defaults[SimOracleTests.unit] = .string("folder-x") }
                inner?(command, &context, &brain)
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S1"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .answer(mac: .A, .use)])
            #expect(world.defaults(of: .A)[Self.unit] == .string("folder-x"))
            return world
        })
    }

    @Test("INV-S1g fires when a live change is held nowhere")
    func s1g() {
        Self.check("INV-S1g", bad: {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, _ in context.defaults[SimOracleTests.unit] = nil }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S1g"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }, good: {
            let world = Self.world([Self.running(.A)], ids: ["INV-S1g"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        })
    }

    @Test("INV-S2 fires on a move back to an older value and on an unset without a deletion")
    func s2() {
        Self.check("INV-S2", bad: {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, brain in
                brain.counter += 1
                if brain.counter == 2 { context.defaults[SimOracleTests.unit] = .string(SimOracleTests.token1) }
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S2"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .A, unit: Self.unit)])
            return world
        }, good: {
            let world = Self.world([Self.running(.A)], ids: ["INV-S2"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .A, unit: Self.unit)])
            return world
        })
        var unsetting = SimScriptedBrain(id: "A")
        unsetting.changedScript = { context, _ in context.defaults[SimOracleTests.unit] = nil }
        let world = Self.world([Self.running(.A)], [.A: unsetting], ids: ["INV-S2"])
        world.step(.userEdit(mac: .A, unit: Self.unit))
        #expect(Self.found(world, "INV-S2"))
    }

    /// A writes `holzBar/Macs/A.plist` after each of its own defaults changes, with the file built by `build`.
    static func publishing(
        id: String = "A",
        path: String = ownA,
        _ build: @escaping @Sendable (Int) -> Data
    ) -> SimScriptedBrain {
        var brain = SimScriptedBrain(id: id)
        brain.changedScript = { context, brain in
            brain.counter += 1
            _ = context.write(path, build(brain.counter))
        }
        return brain
    }

    @Test("INV-S3 fires on an over-claim and on a claim the file does not carry")
    func s3() {
        func world(tokens: [String], claimed: [String]) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file(tokens: tokens, claimed: claimed) }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S3"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-S3", bad: { world(tokens: [Self.token1], claimed: [Self.token1, "u9@Other"]) },
                   good: { world(tokens: [Self.token1], claimed: [Self.token1]) })
        #expect(Self.found(world(tokens: [], claimed: [Self.token1]), "INV-S3"))
    }

    @Test("INV-S4 fires when a unit is removed after reading a file that does not mention it")
    func s4() {
        func world(removing: Bool) -> SimWorld {
            var writer = Self.publishing { _ in
                SimScriptedBrain.file(tokens: ["u2@ShowOnHover"], mentioned: ["ShowOnHover"])
            }
            writer.signalScript = nil
            var reader = SimScriptedBrain(id: "B")
            reader.signalScript = { context, _ in
                if case .data(_, let version) = context.read(SimOracleTests.ownA, maximumBytes: 1 << 20) {
                    context.reportIngest(version: version)
                    if removing { context.defaults["UseIceBar"] = nil }
                }
            }
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: writer, .B: reader], ids: ["INV-S4"])
            world.run([.userEdit(mac: .B, unit: "UseIceBar"), .userEdit(mac: .A, unit: Self.unit)])
            return world
        }
        Self.check("INV-S4", bad: { world(removing: true) }, good: { world(removing: false) })
    }

    @Test("INV-S5 fires when a user deletion is not published as an explicit deletion")
    func s5() {
        func world(publishingDeletion: Bool) -> SimWorld {
            let brain = Self.publishing { count in
                SimScriptedBrain.file(tokens: [], deleted: count >= 2 && publishingDeletion ? [Self.unit] : [])
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S5"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userDelete(mac: .A, unit: Self.unit)])
            return world
        }
        Self.check("INV-S5", bad: { world(publishingDeletion: false) }, good: { world(publishingDeletion: true) })
    }

    // MARK: INV-S6, INV-S7

    @Test("INV-S6 fires on the shared file, another Mac's file and an unread overwrite")
    func s6() {
        let shared = Self.publishing(path: "holzBar/Settings.plist") { _ in SimScriptedBrain.file() }
        let world1 = Self.world([Self.running(.A)], [.A: shared], ids: ["INV-S6"])
        world1.step(.userEdit(mac: .A, unit: Self.unit))
        #expect(Self.found(world1, "INV-S6"))
        let other = Self.publishing(path: Self.ownB) { _ in SimScriptedBrain.file() }
        let world2 = Self.world([Self.running(.A)], [.A: other], ids: ["INV-S6"])
        world2.step(.userEdit(mac: .A, unit: Self.unit))
        #expect(Self.found(world2, "INV-S6"))
        func relaunched(reading: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, _ in
                if reading { _ = context.read(SimOracleTests.ownA, maximumBytes: 1 << 20) }
                _ = context.write(SimOracleTests.ownA, SimScriptedBrain.file())
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S6"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .quit(mac: .A), .launch(mac: .A), .userEdit(mac: .A, unit: Self.unit)])
            return world
        }
        Self.check("INV-S6", bad: { relaunched(reading: false) }, good: { relaunched(reading: true) })
    }

    @Test("INV-S7 fires when a waiting change is dropped by a quit")
    func s7() {
        func world(keeping: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, brain in
                brain.pending = [SimOracleTests.token1]
                context.defaults[SimOracleTests.unit] = nil
            }
            brain.quitScript = { _, brain in if !keeping { brain.pending = [] } }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S7"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .quit(mac: .A)])
            return world
        }
        Self.check("INV-S7", bad: { world(keeping: false) }, good: { world(keeping: true) })
    }

    // MARK: Privacy

    @Test("INV-S8 fires on a planted marker and on a local key in a written file")
    func s8() {
        func world(extra: [String: String]) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file(extra: extra) }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S8"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-S8", bad: { world(extra: ["computer": "MARKER-NAME-A"]) }, good: { world(extra: ["computer": "plain"]) })
        #expect(Self.found(world(extra: ["SettingsSyncDeviceID": "x"]), "INV-S8"))
        #expect(Self.found(world(extra: ["home": "/Users/MARKER-USER-A"]), "INV-S8"))
    }

    @Test("INV-PR2 fires on the SHA-256 of a marker, with or without the salt")
    func pr2() {
        func world(embedding text: String?) -> SimWorld {
            let brain = Self.publishing { _ in
                SimScriptedBrain.file(extra: text.map { ["digest": SimSafetyOracles.digestForms(of: $0)[0]] } ?? [:])
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-PR2"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-PR2", bad: { world(embedding: "MARKER-HW-A") }, good: { world(embedding: "something else") })
        #expect(Self.found(world(embedding: "MARKER-SALT-AMARKER-HW-A"), "INV-PR2"))
        #expect(Self.found(world(embedding: "MARKER-NAME-A"), "INV-PR2"))
    }

    @Test("INV-ID5 fires on the hardware ID, the salt and their digests")
    func id5() {
        func world(embedding text: String) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file(extra: ["value": text]) }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-ID5"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-ID5", bad: { world(embedding: "MARKER-HW-A") }, good: { world(embedding: "device-1") })
        #expect(Self.found(world(embedding: SimSafetyOracles.digestForms(of: "MARKER-SALT-A")[0]), "INV-ID5"))
    }

    // MARK: INV-N1, INV-S9, INV-A6

    @Test("INV-N1 fires on a local key and on the macOS 27 families of a generation 26 Mac")
    func n1() {
        func world(key: String, generation: Int = 26) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, _ in context.defaults[key] = .array([.string("x")]) }
            let world = Self.world([Self.running(.A, generation: generation)], [.A: brain], ids: ["INV-N1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-N1", bad: { world(key: "KnownItemTags") }, good: { world(key: "RevealRules") })
        #expect(Self.found(world(key: "MacOS27Layout"), "INV-N1"))
        #expect(!Self.found(world(key: "MacOS27Layout", generation: 27), "INV-N1"))
        #expect(Self.found(world(key: "SettingsSyncLastSynced"), "INV-N1"))
        #expect(Self.found(world(key: "HasImportedIceSettings"), "INV-N1"))
    }

    @Test("INV-S9 fires when an answer supersedes a value the sheet did not show and when Later changes settings")
    func s9() {
        func world(answer: SimAnswer, touching key: String) -> SimWorld {
            var brain = Self.asking(Self.shown(Self.token1, "folder-x"))
            let inner = brain.commandScript
            brain.commandScript = { command, context, brain in
                if case .answer = command { context.defaults[key] = .string("changed") }
                inner?(command, &context, &brain)
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-S9"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .A, unit: "UseIceBar"), .answer(mac: .A, answer)])
            return world
        }
        Self.check("INV-S9", bad: { world(answer: .use, touching: "UseIceBar") }, good: { world(answer: .use, touching: Self.unit) })
        #expect(Self.found(world(answer: .later, touching: Self.unit), "INV-S9"))
    }

    @Test("INV-A6 fires on a deletion that no user made")
    func a6() {
        func world(userDeleted: Bool) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file(deleted: ["ItemIcons/x"]) }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-A6"])
            if userDeleted { world.step(.userDelete(mac: .A, unit: "ItemIcons/x")) }
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-A6", bad: { world(userDeleted: false) }, good: { world(userDeleted: true) })
    }

    // MARK: Prompts

    @Test("INV-P1 fires on a prompt without a witness and accepts a real conflict")
    func p1() {
        let witnessed: () -> SimWorld = {
            let writer = Self.publishing { _ in SimScriptedBrain.file(tokens: [Self.token1]) }
            let asker = Self.asking(Self.shown("u2@ShowOnHover", Self.token1), id: "B")
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: writer, .B: asker], ids: ["INV-P1"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .B, unit: Self.unit)])
            return world
        }
        Self.check("INV-P1", bad: {
            let world = Self.world([Self.running(.A)], [.A: Self.asking(Self.shown(Self.token1, "folder-x"))], ids: ["INV-P1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }, good: witnessed)
    }

    @Test("INV-P2 fires on a prompt about equal values")
    func p2() {
        func world(folder: String) -> SimWorld {
            let world = Self.world([Self.running(.A)], [.A: Self.asking(Self.shown(Self.token1, folder))], ids: ["INV-P2"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-P2", bad: { world(folder: Self.token1) }, good: { world(folder: "folder-x") })
    }

    @Test("INV-P3 fires on a repeated question after Use and allows it after Later")
    func p3() {
        func world(answer: SimAnswer) -> SimWorld {
            let world = Self.world([Self.running(.A)], [.A: Self.asking(Self.shown("x", "y"))], ids: ["INV-P3"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .answer(mac: .A, answer), .userEdit(mac: .A, unit: "UseIceBar")])
            return world
        }
        Self.check("INV-P3", bad: { world(answer: .use) }, good: { world(answer: .later) })
    }

    @Test("INV-P4 fires when Later is ignored before the next launch")
    func p4() {
        func world(relaunching: Bool) -> SimWorld {
            let world = Self.world([Self.running(.A)], [.A: Self.asking(Self.shown("x", "y"))], ids: ["INV-P4"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .answer(mac: .A, .later)])
            if relaunching { world.step(.restartApp(mac: .A)) }
            world.step(.userEdit(mac: .A, unit: "UseIceBar"))
            return world
        }
        Self.check("INV-P4", bad: { world(relaunching: false) }, good: { world(relaunching: true) })
    }

    @Test("INV-P5 fires on a second sheet while one is open")
    func p5() {
        var second = SimScriptedBrain(id: "A")
        second.changedScript = { context, brain in
            brain.counter += 1
            let sheet = SimPrompt(id: brain.counter, title: "Settings differ", shown: [])
            brain.prompt = sheet
            context.reportPrompt(sheet)
        }
        Self.check("INV-P5", bad: {
            let world = Self.world([Self.running(.A)], [.A: second], ids: ["INV-P5"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .A, unit: "UseIceBar")])
            return world
        }, good: {
            let world = Self.world([Self.running(.A)], [.A: second], ids: ["INV-P5"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        })
    }

    @Test("INV-P7 fires on a menu hint for a bystander")
    func p7() {
        func world(menuHint: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { _, brain in brain.info.menuHint = menuHint }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-P7"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            // The hint is judged at the next step: the change the user just made is captured later.
            world.step(.advance(milliseconds: 1_000))
            return world
        }
        Self.check("INV-P7", bad: { world(menuHint: true) }, good: { world(menuHint: false) })
    }

    // MARK: Identity and join

    @Test("INV-ID1 fires when two launched installations share an ID")
    func id1() {
        func world(second: String) -> SimWorld {
            let world = Self.world([SimMacSpec(.A, .redesign), SimMacSpec(.B, .redesign)],
                                   [.A: SimScriptedBrain(id: "same"), .B: SimScriptedBrain(id: second)], ids: ["INV-ID1"])
            world.run([.clone(from: .A, to: .B), .launch(mac: .A), .launch(mac: .B)])
            return world
        }
        Self.check("INV-ID1", bad: { world(second: "same") }, good: { world(second: "other") })
    }

    @Test("INV-ID2 fires on an ID change that is no join with a reason")
    func id2() {
        func world(joining: Bool, reason: String?) -> SimWorld {
            var brain = SimScriptedBrain(id: "old")
            brain.launchScript = { _, brain in
                brain.info.deviceID = "new"
                brain.info.joining = joining
                brain.info.reidentifyReason = reason
            }
            let world = Self.world([SimMacSpec(.A, .redesign)], [.A: brain], ids: ["INV-ID2"])
            world.step(.launch(mac: .A))
            return world
        }
        Self.check("INV-ID2", bad: { world(joining: false, reason: "hardware") }, good: { world(joining: true, reason: "hardware") })
        #expect(Self.found(world(joining: true, reason: nil), "INV-ID2"))
    }

    @Test("INV-ID3 fires when a file with this Mac's ID written by another is treated as its own")
    func id3() {
        func world(marking: Bool) -> SimWorld {
            let writer = Self.publishing(id: "B", path: "holzBar/Macs/A.plist") { _ in SimScriptedBrain.file(writer: "A") }
            var reader = SimScriptedBrain(id: "A")
            reader.signalScript = { context, brain in
                _ = context.read("holzBar/Macs/A.plist", maximumBytes: 1 << 20)
                if marking { brain.info.foreignPaths.insert("holzBar/Macs/A.plist") }
            }
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: reader, .B: writer], ids: ["INV-ID3"])
            world.step(.userEdit(mac: .B, unit: Self.unit))
            return world
        }
        Self.check("INV-ID3", bad: { world(marking: false) }, good: { world(marking: true) })
    }

    @Test("INV-ID4 fires when an older version of its own is applied as new")
    func id4() {
        func world(changing: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, _ in _ = context.write(SimOracleTests.ownA, SimScriptedBrain.file()) }
            brain.signalScript = { context, brain in
                if case .data(_, let version) = context.read(SimOracleTests.ownA, maximumBytes: 1 << 20) {
                    context.reportIngest(version: version)
                    brain.counter += 1
                    if changing { context.defaults["UseIceBar"] = .string("applied-\(brain.counter)") }
                }
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-ID4"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .A, unit: Self.unit),
                       .provider(.restore(path: Self.ownA, version: 1))])
            return world
        }
        Self.check("INV-ID4", bad: { world(changing: true) }, good: { world(changing: false) })
    }

    @Test("INV-ID6 fires when a file covers dots this Mac never minted and it does not re-identify")
    func id6() {
        func world(claiming: Int) -> SimWorld {
            let writer = Self.publishing(id: "B", path: Self.ownB) { _ in SimScriptedBrain.file(counters: ["A": claiming]) }
            var reader = SimScriptedBrain(id: "A")
            reader.info.ownCounter = 3
            reader.signalScript = { context, _ in
                if case .data(_, let version) = context.read(SimOracleTests.ownB, maximumBytes: 1 << 20) {
                    context.reportIngest(version: version)
                }
            }
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: reader, .B: writer], ids: ["INV-ID6"])
            world.step(.userEdit(mac: .B, unit: Self.unit))
            return world
        }
        Self.check("INV-ID6", bad: { world(claiming: 5) }, good: { world(claiming: 2) })
    }

    @Test("INV-J1 fires on a join commit with unread files and on a write after Cancel")
    func j1() {
        func world(unread: Set<String>, refused: Set<String>) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { _, brain in
                brain.info.joinCommitted = true
                brain.info.unreadListedFiles = unread
                brain.info.refusedFiles = refused
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-J1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-J1", bad: { world(unread: ["holzBar/Macs/B.plist"], refused: []) },
                   good: { world(unread: ["holzBar/Macs/B.plist"], refused: ["holzBar/Macs/B.plist"]) })
        func cancelled(writing: Bool) -> SimWorld {
            var brain = Self.asking(Self.shown("x", "y"))
            let inner = brain.commandScript
            brain.commandScript = { command, context, brain in
                if case .answer = command, writing { _ = context.write(SimOracleTests.ownA, SimScriptedBrain.file()) }
                inner?(command, &context, &brain)
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-J1"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .answer(mac: .A, .cancel)])
            return world
        }
        #expect(Self.found(cancelled(writing: true), "INV-J1"))
        #expect(!Self.found(cancelled(writing: false), "INV-J1"))
    }

    // MARK: File-provider realities

    @Test("INV-F1 fires when settings change after reading foreign bytes")
    func f1() {
        func world(applying: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.signalScript = { context, brain in
                if case .data = context.read("holzBar/Macs/X.plist", maximumBytes: 1 << 20), applying {
                    brain.counter += 1
                    context.defaults["UseIceBar"] = .string("from-garbage-\(brain.counter)")
                }
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-F1"])
            world.step(.provider(.foreign(path: "holzBar/Macs/X.plist", kind: .garbage)))
            return world
        }
        Self.check("INV-F1", bad: { world(applying: true) }, good: { world(applying: false) })
    }

    /// A writes, B ingests; then `extra` events run and B's script `react`s to each folder signal.
    @Test("INV-F4 fires when a dominated conflict copy causes a change")
    func f4() {
        func world(reacting: Bool) -> SimWorld {
            var policy = SimFaultPolicy(medianDelayMilliseconds: 5_000, conflictCopyProbability: 1)
            policy.conflictStyles = [.dropbox]
            var writer = SimScriptedBrain(id: "A")
            writer.changedScript = { context, _ in _ = context.write("holzBar/Macs/P.plist", SimScriptedBrain.file()) }
            writer.signalScript = { context, brain in
                for name in context.list("holzBar/Macs").names(or: []) where name.contains("conflicted copy") {
                    if case .data(_, let version) = context.read("holzBar/Macs/\(name)", maximumBytes: 1 << 20) {
                        context.reportIngest(version: version)
                        brain.counter += 1
                        if reacting { context.defaults["UseIceBar"] = .string("react-\(brain.counter)") }
                    }
                }
            }
            var other = SimScriptedBrain(id: "B")
            other.changedScript = { context, _ in _ = context.write("holzBar/Macs/P.plist", SimScriptedBrain.file()) }
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: writer, .B: other], ids: ["INV-F4"], policy: policy)
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .B, unit: Self.unit), .advance(milliseconds: 600_000)])
            return world
        }
        Self.check("INV-F4", bad: { world(reacting: true) }, good: { world(reacting: false) })
    }

    @Test("INV-F5 fires when a restored dominated version causes a change and ignores fresh versions")
    func f5() {
        func world(reactingAt: Set<Int>) -> SimWorld {
            let writer = Self.publishing { _ in SimScriptedBrain.file() }
            var reader = SimScriptedBrain(id: "B")
            reader.signalScript = { context, brain in
                if case .data(_, let version) = context.read(SimOracleTests.ownA, maximumBytes: 1 << 20) {
                    context.reportIngest(version: version)
                    brain.counter += 1
                    if reactingAt.contains(brain.counter) { context.defaults["UseIceBar"] = .string("react-\(brain.counter)") }
                }
            }
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: writer, .B: reader], ids: ["INV-F5"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .A, unit: Self.unit),
                       .provider(.restore(path: Self.ownA, version: 1))])
            return world
        }
        // The third signal ingests the restored first version, which B's past already covers.
        Self.check("INV-F5", bad: { world(reactingAt: [3]) }, good: { world(reactingAt: [1, 2]) })
    }

    @Test("INV-F6 fires when deleting a file removes a local setting")
    func f6() {
        func world(removing: Bool) -> SimWorld {
            let writer = Self.publishing { _ in SimScriptedBrain.file() }
            var reader = SimScriptedBrain(id: "B")
            reader.signalScript = { context, _ in
                if context.read(SimOracleTests.ownA, maximumBytes: 1 << 20) == .absent, removing { context.defaults["UseIceBar"] = nil }
            }
            let world = Self.world([Self.running(.A), Self.running(.B, defaults: ["UseIceBar": .string("kept")])],
                                   [.A: writer, .B: reader], ids: ["INV-F6"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .provider(.delete(path: Self.ownA))])
            return world
        }
        Self.check("INV-F6", bad: { world(removing: true) }, good: { world(removing: false) })
    }

    @Test("INV-F7 fires on a write while the folder is unmounted")
    func f7() {
        func world(unmounted: Bool) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file() }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-F7"])
            if unmounted { world.step(.provider(.unmount(mac: .A))) }
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-F7", bad: { world(unmounted: true) }, good: { world(unmounted: false) })
    }

    @Test("INV-R2 fires when launch blocks on the folder for more than a second")
    func r2() {
        func world(stalled: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "B")
            brain.launchScript = { context, _ in _ = context.read(SimOracleTests.ownA, maximumBytes: 1 << 20) }
            let world = Self.world([SimMacSpec(.B, .redesign)], [.B: brain], ids: ["INV-R2"])
            if stalled { world.step(.provider(.stall(mac: .B, forMilliseconds: 3_000))) }
            world.step(.launch(mac: .B))
            return world
        }
        Self.check("INV-R2", bad: { world(stalled: true) }, good: { world(stalled: false) })
    }

    @Test("INV-R3 fires when the sync code tries to mount")
    func r3() {
        func world(mounting: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { _, brain in if mounting { brain.info.mountAttempts += 1 } }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-R3"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-R3", bad: { world(mounting: true) }, good: { world(mounting: false) })
    }

    // MARK: Size and refusal

    @Test("INV-Z1 fires on a file above the limit")
    func z1() {
        func world(size: Int) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file(extra: ["pad": String(repeating: "x", count: size)]) }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-Z1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-Z1", bad: { world(size: SimLimits.deviceFileWriter + 100) }, good: { world(size: 1_000) })
    }

    @Test("INV-Z2 fires when a reader refuses a file its writer wrote within the limit")
    func z2() {
        func world(readLimit: Int) -> SimWorld {
            let writer = Self.publishing(id: "B", path: Self.ownB) { _ in
                SimScriptedBrain.file(extra: ["pad": String(repeating: "x", count: 600_000)])
            }
            var reader = SimScriptedBrain(id: "A")
            reader.signalScript = { context, _ in _ = context.read(SimOracleTests.ownB, maximumBytes: readLimit) }
            let world = Self.world([Self.running(.A), Self.running(.B)], [.A: reader, .B: writer], ids: ["INV-Z2"])
            world.step(.userEdit(mac: .B, unit: Self.unit))
            return world
        }
        Self.check("INV-Z2", bad: { world(readLimit: 100_000) }, good: { world(readLimit: 1 << 20) })
    }

    @Test("INV-Z3 fires when a state too large to publish shows no warning")
    func z3() {
        func world(warning: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.info.sizeWarning = warning
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-Z3"])
            world.step(.oversizeIcon(mac: .A))
            return world
        }
        Self.check("INV-Z3", bad: { world(warning: false) }, good: { world(warning: true) })
    }

    @Test("INV-Z4 fires when the local sync state outgrows the devices seen")
    func z4() {
        func world(bytes: Int) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.info.devicesSeen = 2
            brain.changedScript = { _, brain in brain.info.sigmaBytes = bytes }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-Z4"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-Z4", bad: { world(bytes: 500_000) }, good: { world(bytes: 3_000) })
    }

    @Test("INV-Z5 fires when files multiply beyond the bound")
    func z5() {
        func world(files: Int) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.changedScript = { context, brain in
                brain.counter += 1
                _ = context.write("holzBar/Macs/\(brain.counter).plist", SimScriptedBrain.file())
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-Z5"])
            for _ in 0..<files { world.step(.userEdit(mac: .A, unit: Self.unit)) }
            return world
        }
        Self.check("INV-Z5", bad: { world(files: 30) }, good: { world(files: 5) })
    }

    @Test("INV-Z6 fires when a Mac writes over bytes it could not read")
    func z6() {
        func world(foreign: Bool) -> SimWorld {
            let brain = Self.publishing { _ in SimScriptedBrain.file() }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-Z6"])
            if foreign { world.step(.provider(.foreign(path: Self.ownA, kind: .garbage))) }
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-Z6", bad: { world(foreign: true) }, good: { world(foreign: false) })
    }

    // MARK: Compatibility

    @Test("INV-B1 fires when a redesigned Mac writes the older peers' file")
    func b1() {
        Self.check("INV-B1", bad: {
            let brain = Self.publishing(path: "holzBar/Settings.plist") { _ in SimScriptedBrain.file() }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-B1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }, good: {
            let world = Self.world([Self.running(.A)], [.A: Self.publishing { _ in SimScriptedBrain.file() }], ids: ["INV-B1"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        })
    }

    @Test("INV-B2 fires when the older peers' file lacks a key the Mac holds")
    func b2() {
        func world(including: Bool) -> SimWorld {
            let brain = Self.publishing(path: "holzBar/Settings.plist") { _ in
                let settings: [String: Any] = including ? [SimOracleTests.unit: "u1@ShowOnHover"] : [:]
                let file: [String: Any] = ["modified": Date(timeIntervalSince1970: 1_790_000_000), "settings": settings]
                return (try? PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)) ?? Data()
            }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-B2"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-B2", bad: { world(including: false) }, good: { world(including: true) })
    }

    /// A beta1 Mac B edits and pushes; A's script reads the shared file and applies it.
    private static func legacyReader(applying: Bool, prompting: Bool = false) -> SimScriptedBrain {
        var reader = SimScriptedBrain(id: "A")
        reader.signalScript = { context, brain in
            guard case .data(let data, let version) = context.read(SimLimits.legacyPath, maximumBytes: 1 << 20) else { return }
            if prompting, SimMacBeta1().heldTokens(inFile: SimLimits.legacyPath, data: data).isEmpty { return }
            context.reportIngest(version: version)
            if applying { context.defaults[SimOracleTests.unit] = .string("from-legacy") }
            if prompting, brain.prompt == nil {
                brain.counter += 1
                let sheet = SimOracleTests.shown(nil, SimOracleTests.token1)
                brain.prompt = SimPrompt(id: brain.counter, title: sheet.title, shown: sheet.shown)
                context.reportPrompt(brain.prompt!)
            }
        }
        reader.commandScript = { command, _, brain in if case .answer = command { brain.prompt = nil } }
        return reader
    }

    @Test("INV-B3 fires when an older peer's file replaces a live value without an answer")
    func b3() {
        func world(applying: Bool) -> SimWorld {
            let world = Self.world([Self.running(.A), Self.running(.B, .beta1)], [.A: Self.legacyReader(applying: applying)],
                                   ids: ["INV-B3"])
            world.run([.userEdit(mac: .A, unit: Self.unit), .userEdit(mac: .B, unit: "UseIceBar"), .advance(milliseconds: 6_000)])
            return world
        }
        Self.check("INV-B3", bad: { world(applying: true) }, good: { world(applying: false) })
    }

    @Test("INV-B4 fires on a second question about the same content of an older peer's file")
    func b4() {
        func world(repeating: Bool) -> SimWorld {
            let world = Self.world([Self.running(.A), Self.running(.B, .beta1)],
                                   [.A: Self.legacyReader(applying: false, prompting: true)], ids: ["INV-B4"])
            world.run([.userEdit(mac: .B, unit: Self.unit), .advance(milliseconds: 6_000), .answer(mac: .A, .later)])
            if repeating { world.run([.userEdit(mac: .B, unit: "UseIceBar"), .advance(milliseconds: 6_000)]) }
            return world
        }
        Self.check("INV-B4", bad: { world(repeating: true) }, good: { world(repeating: false) })
    }

    @Test("INV-B5 fires when a pre-existing value is replaced without an answer")
    func b5() {
        func world(replacing: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.launchScript = { context, _ in if replacing { context.defaults[SimOracleTests.unit] = .string("other") } }
            let world = Self.world([SimMacSpec(.A, .redesign, defaults: [Self.unit: .string("pre(A)")])], [.A: brain], ids: ["INV-B5"])
            world.step(.launch(mac: .A))
            return world
        }
        Self.check("INV-B5", bad: { world(replacing: true) }, good: { world(replacing: false) })
    }

    @Test("INV-B6 fires when old local state is used as evidence")
    func b6() {
        func world(using: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.launchScript = { _, brain in brain.info.usedLegacyStateAsEvidence = using }
            let world = Self.world([SimMacSpec(.A, .redesign)], [.A: brain], ids: ["INV-B6"])
            world.step(.launch(mac: .A))
            return world
        }
        Self.check("INV-B6", bad: { world(using: true) }, good: { world(using: false) })
    }

    @Test("INV-B7 fires when a Mac returns from an older build without joining again")
    func b7() {
        func world(joining: Bool) -> SimWorld {
            var brain = SimScriptedBrain(id: "A")
            brain.launchScript = { _, brain in brain.info.joining = joining }
            let world = Self.world([SimMacSpec(.A, .redesign)], [.A: brain], ids: ["INV-B7"])
            world.run([.updateApp(mac: .A, version: .beta1), .launch(mac: .A), .updateApp(mac: .A, version: .redesign), .launch(mac: .A)])
            return world
        }
        Self.check("INV-B7", bad: { world(joining: false) }, good: { world(joining: true) })
    }

    @Test("INV-B8 fires when a build rewrites another build's file")
    func b8() {
        func world(path: String) -> SimWorld {
            let newer = Self.publishing(id: "B", path: "holzBar/Macs/shared.plist") { _ in SimScriptedBrain.file() }
            var older = SimScriptedBrain(id: "A")
            older.changedScript = { context, _ in
                _ = context.read(path, maximumBytes: 1 << 20)
                _ = context.write(path, SimScriptedBrain.file())
            }
            let world = Self.world([Self.running(.A), Self.running(.B, .redesignSkew)], [.A: older, .B: newer], ids: ["INV-B8"])
            world.run([.userEdit(mac: .B, unit: Self.unit), .userEdit(mac: .A, unit: Self.unit)])
            return world
        }
        Self.check("INV-B8", bad: { world(path: "holzBar/Macs/shared.plist") }, good: { world(path: Self.ownA) })
    }

    @Test("INV-B9 fires on the oldest peer's device field and on holzIce")
    func b9() {
        func world(extra: [String: String], path: String = Self.ownA) -> SimWorld {
            let brain = Self.publishing(path: path) { _ in SimScriptedBrain.file(extra: extra) }
            let world = Self.world([Self.running(.A)], [.A: brain], ids: ["INV-B9"])
            world.step(.userEdit(mac: .A, unit: Self.unit))
            return world
        }
        Self.check("INV-B9", bad: { world(extra: ["device": "Old Mac"]) }, good: { world(extra: ["other": "x"]) })
        #expect(Self.found(world(extra: [:], path: "holzIce/Settings.plist"), "INV-B9"))
    }
}

private extension SimListResult {
    func names(or fallback: [String]) -> [String] {
        if case .names(let names) = self { return names }
        return fallback
    }
}
