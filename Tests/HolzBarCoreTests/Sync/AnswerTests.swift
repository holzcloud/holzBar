//
//  AnswerTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

@Suite("SyncAnswer")
struct AnswerTests {
    private typealias Fixtures = SyncFixtures

    private let realTable = SyncUnitTable.version1(normalizers: .canonical)
    private let hotkeys = Defaults.Key.hotkeys.rawValue

    // MARK: Builders

    private func environment(floors: SyncCounterFloors = SyncCounterFloors(), table: SyncUnitTable? = nil) -> SyncEnvironment {
        Fixtures.environment(floors: floors, table: table ?? Fixtures.table)
    }

    /// Mac A holds `local` at S1 and so do B's and C's entries `others`: a conflict this Mac takes part in.
    private func conflict(local: String = "mine", others: [(mac: SyncMacID, n: UInt64, value: String)] = [(Fixtures.macB, 5, "theirs")]) -> SyncState {
        let mine = Fixtures.entry(Fixtures.macA, 4, .string(local))
        var state = Fixtures.state()
        state.replica = Fixtures.replica([Fixtures.s1: [mine] + others.map { Fixtures.entry($0.mac, $0.n, .string($0.value)) }])
        state.applied[Fixtures.s1] = [mine.dot]
        state.baseline[Fixtures.s1] = SyncValue.string(local).digest
        state.counter = 4
        state.publishedCounter = 4
        state.session.isTrusted = true
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string(local)])
        return state
    }

    private func ask(_ state: SyncState, scope: SyncQuestionScope = .mine, table: SyncUnitTable? = nil) throws -> SyncQuestion {
        try #require(SyncEngine.question(for: state, scope: scope, environment: environment(table: table)))
    }

    private func answer(
        _ button: SyncAnswerButton,
        _ question: SyncQuestion,
        choices: [SyncUnitKey: Int] = [:],
        state: SyncState,
        environment: SyncEnvironment? = nil
    ) -> SyncStep {
        SyncEngine.handle(
            .command(.answer(SyncAnswerRequest(button: button, choices: choices, question: question))),
            state: state,
            environment: environment ?? self.environment()
        )
    }

    private func applied(_ step: SyncStep) -> [SyncUnitKey: SyncPayload] {
        for effect in step.effects {
            if case .applyUnits(let changes) = effect {
                return changes
            }
        }
        return [:]
    }

    private func relaunches(_ step: SyncStep) -> Bool {
        step.effects.contains { if case .relaunch = $0 { true } else { false } }
    }

    private func written(_ step: SyncStep) -> SyncDeviceFile.Contents? {
        for effect in step.effects {
            if case .writeOwnFile(let request) = effect {
                return request.contents
            }
        }
        return nil
    }

    // MARK: The question

    @Test("The question has one row per unit that is this Mac's, sorted by unit, and shows the exact dots")
    func questionRows() throws {
        var state = conflict()
        let other = Fixtures.entry(Fixtures.macB, 6, .string("other"))
        let mineToo = Fixtures.entry(Fixtures.macA, 3, .string("mine2"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s2: [mineToo, other]]) { $0 + $1 })
        state.applied[Fixtures.s2] = [mineToo.dot]
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine"), Fixtures.s2: .string("mine2")])
        let question = try ask(state)
        #expect(question.kind == .running)
        #expect(question.rows.map(\.unit) == [Fixtures.s1, Fixtures.s2])
        #expect(question.rows.allSatisfy { $0.style == .twoWay })
        let row = try #require(question.rows.first)
        #expect(row.local?.value == .value(.string("mine")))
        #expect(row.folder.map(\.value) == [.value(.string("theirs"))])
        #expect(row.folder.first?.source == .entry(SyncDot(mac: Fixtures.macB, n: 5)))
        #expect(question.shown[Fixtures.s1] == [SyncDot(mac: Fixtures.macA, n: 4), SyncDot(mac: Fixtures.macB, n: 5)])
        // Nothing to ask: no question.
        #expect(SyncEngine.question(for: Fixtures.state(), scope: .mine, environment: environment()) == nil)
        #expect(SyncEngine.question(for: state, scope: .bystander, environment: environment()) == nil)
    }

    // MARK: Use and Keep

    @Test("Use writes one fresh entry with the folder's value that covers exactly the shown dots, applies it and relaunches")
    func useWritesAFreshEntry() throws {
        let state = conflict()
        let question = try ask(state)
        let step = answer(.use, question, state: state)
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.count == 1)
        let entry = try #require(live.first)
        #expect(entry.value == .string("theirs"))
        #expect(entry.dot.mac == Fixtures.macA)
        #expect(entry.dot.n > 5, "a fresh dot, above every counter")
        #expect(step.state.applied[Fixtures.s1] == [entry.dot])
        #expect(step.state.baseline[Fixtures.s1] == SyncValue.string("theirs").digest)
        #expect(applied(step) == [Fixtures.s1: .value(.string("theirs"))])
        #expect(relaunches(step))
        // Persist before the write, and the write carries the answer.
        let names = step.effects.map { effect -> String in
            switch effect {
            case .applyUnits: "apply"
            case .persist: "persist"
            case .writeOwnFile: "write"
            case .relaunch: "relaunch"
            default: "other"
            }
        }
        #expect(names == ["apply", "persist", "write", "relaunch"])
        #expect(written(step)?.replica.live(Fixtures.s1) == live)
    }

    @Test("Keep writes one fresh entry with this Mac's value, applies nothing and does not relaunch")
    func keepWritesThisMacsValue() throws {
        let state = conflict()
        let question = try ask(state)
        let step = answer(.keep, question, state: state)
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.map(\.value) == [.string("mine")])
        #expect(live.first?.dot != SyncDot(mac: Fixtures.macA, n: 4))
        #expect(step.state.applied[Fixtures.s1] == [live[0].dot])
        #expect(applied(step).isEmpty)
        #expect(!relaunches(step))
        #expect(written(step) != nil)
        // The unit is settled: equal, no question left.
        let plan = SyncPlan.plan(state: step.state, snapshot: step.state.session.snapshot ?? SyncSnapshot(), environment: environment())
        #expect(plan.outcomes[Fixtures.s1] == .equal)
        #expect(SyncEngine.question(for: step.state, scope: .mine, environment: environment()) == nil)
    }

    @Test("Keep relaunches when fast-forwards of other units still wait")
    func keepRelaunchesForWaitingFastForwards() throws {
        var state = conflict()
        let waiting = Fixtures.entry(Fixtures.macB, 7, .string("waiting"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s2: [waiting]]) { $0 + $1 })
        state.baseline[Fixtures.s2] = .unset
        let question = try ask(state)
        let step = answer(.keep, question, state: state)
        #expect(applied(step).isEmpty)
        #expect(relaunches(step))
    }

    @Test("Every counter of an answer goes through the counter rule: above the mirror and the high-water mark")
    func countersGoThroughNextCounter() throws {
        let state = conflict()
        let question = try ask(state)
        let floors = SyncCounterFloors(mirror: 5_000, highWater: 7_000)
        let step = answer(.keep, question, state: state, environment: environment(floors: floors))
        let dot = try #require(step.state.replica.live(Fixtures.s1).first?.dot)
        #expect(dot.n > 7_000)
        #expect(step.state.counter == dot.n)
        guard case .persist(let persist) = step.effects.first(where: { if case .persist = $0 { true } else { false } }) else {
            Issue.record("a persist is due")
            return
        }
        #expect(persist.counter == dot.n)
    }

    // MARK: Late entries and decisions elsewhere

    @Test("An entry that arrived after the sheet opened survives as a sibling and is asked about again")
    func lateEntrySurvives() throws {
        var state = conflict()
        let question = try ask(state)
        let late = Fixtures.entry(Fixtures.macC, 9, .string("late"))
        state.replica = Fixtures.replica(state.replica.registers.merging([Fixtures.s1: [late]]) { $0 + $1 })
        let step = answer(.use, question, state: state)
        let live = step.state.replica.live(Fixtures.s1)
        #expect(live.count == 2)
        #expect(live.contains(late))
        #expect(live.contains { $0.value == .string("theirs") && $0.dot.mac == Fixtures.macA })
        // The late value is a new question, and this Mac took part in it.
        let again = try ask(step.state)
        #expect(again.rows.map(\.unit) == [Fixtures.s1])
        #expect(again.rows.first?.folder.map(\.value) == [.value(.string("late"))])
        // Without the filter on the shown dots the answer would have removed the late entry too.
        #expect(!(again.shown[Fixtures.s1] ?? []).isEmpty)
    }

    @Test("A row whose shown dots are no longer all live was decided elsewhere and is left out; with every row gone the answer writes nothing")
    func rowDecidedElsewhere() throws {
        var state = conflict()
        let question = try ask(state)
        // Another Mac answered: its entry covers both shown dots and replaces them.
        let decided = Fixtures.entry(Fixtures.macC, 12, .string("decided"))
        state.replica = Fixtures.replica([Fixtures.s1: [decided]], extraContext: [Fixtures.macA: 4, Fixtures.macB: 5])
        let step = answer(.use, question, state: state)
        #expect(step.state.replica == state.replica)
        #expect(step.effects.isEmpty)
        #expect(step.state.counter == state.counter)
    }

    // MARK: Later

    @Test("Later writes nothing and hides the hint until the next launch, and the sheet is still there when asked for")
    func laterHidesTheHint() throws {
        var state = conflict()
        state.launchCount = 3
        let question = try ask(state)
        #expect(SyncEngine.view(of: state, environment: environment()).hint == .choose)
        let step = answer(.later, question, state: state)
        #expect(step.state.replica == state.replica)
        #expect(step.state.laterLaunch == 3)
        #expect(step.effects.contains { if case .writeOwnFile = $0 { true } else { false } } == false)
        #expect(SyncEngine.view(of: step.state, environment: environment()).hint == nil)
        #expect(SyncEngine.question(for: step.state, scope: .mine, environment: environment()) == question)
        var relaunched = step.state
        relaunched.launchCount = 4
        #expect(SyncEngine.view(of: relaunched, environment: environment()).hint == .choose)
    }

    // MARK: Explicit choices

    private var threeValues: [(mac: SyncMacID, n: UInt64, value: String)] {
        [(Fixtures.macB, 5, "b"), (Fixtures.macC, 6, "c")]
    }

    @Test("A row with three values needs a choice: Use, Keep and the chosen button are refused without one")
    func multiRowNeedsAChoice() throws {
        let state = conflict(others: threeValues)
        let question = try ask(state)
        let row = try #require(question.rows.first)
        #expect(row.style == .multi)
        #expect(row.folder.count == 3)
        for button in [SyncAnswerButton.use, .keep, .useChosen] {
            let refused = answer(button, question, state: state)
            #expect(refused.state.replica == state.replica)
            #expect(refused.effects.isEmpty)
        }
        let outOfRange = answer(.use, question, choices: [Fixtures.s1: 3], state: state)
        #expect(outOfRange.effects.isEmpty)
    }

    @Test("The chosen value is written whichever button is pressed")
    func chosenValueWins() throws {
        let state = conflict(others: threeValues)
        let question = try ask(state)
        let index = try #require(question.rows.first?.folder.firstIndex { $0.value == .value(.string("c")) })
        for button in [SyncAnswerButton.use, .keep, .useChosen] {
            let step = answer(button, question, choices: [Fixtures.s1: index], state: state)
            #expect(step.state.replica.live(Fixtures.s1).map(\.value) == [.string("c")], "button \(button)")
            #expect(applied(step) == [Fixtures.s1: .value(.string("c"))])
        }
        // Choosing this Mac's own value applies nothing.
        let own = try #require(question.rows.first?.folder.firstIndex { $0.value == .value(.string("mine")) })
        let keep = answer(.useChosen, question, choices: [Fixtures.s1: own], state: state)
        #expect(keep.state.replica.live(Fixtures.s1).map(\.value) == [.string("mine")])
        #expect(applied(keep).isEmpty)
    }

    @Test("A conflict between other Macs is answered with an explicit choice, and then this Mac applies it")
    func bystanderAnswer() throws {
        var state = conflict()
        // This Mac has no stake: B and C differ, A's entry is gone and its value is the old one.
        let b = Fixtures.entry(Fixtures.macB, 5, .string("b"))
        let c = Fixtures.entry(Fixtures.macC, 6, .string("c"))
        state.replica = Fixtures.replica([Fixtures.s1: [b, c]], extraContext: [Fixtures.macA: 4])
        state.applied[Fixtures.s1] = nil
        state.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("old")])
        state.baseline[Fixtures.s1] = SyncValue.string("old").digest
        #expect(SyncEngine.question(for: state, scope: .mine, environment: environment()) == nil)
        let question = try ask(state, scope: .bystander)
        #expect(question.kind == .bystander)
        #expect(question.rows.first?.style == .bystander)
        let refused = answer(.useChosen, question, state: state)
        #expect(refused.effects.isEmpty)
        let step = answer(.useChosen, question, choices: [Fixtures.s1: 1], state: state)
        #expect(step.state.replica.live(Fixtures.s1).map(\.value) == [.string("c")])
        #expect(step.state.replica.live(Fixtures.s1).first?.dot.mac == Fixtures.macA)
        #expect(applied(step) == [Fixtures.s1: .value(.string("c"))])
        #expect(relaunches(step))
    }

    // MARK: Hotkey clashes

    private func clashState() -> (SyncState, SyncUnitKey, SyncUnitKey, SyncValue) {
        let search = SyncUnitKey.split(family: hotkeys, item: "SearchMenuBarItems")
        let toggle = SyncUnitKey.split(family: hotkeys, item: "ToggleHiddenSection")
        let combination = SyncValue.data(HotkeyStorage.encode(key: 4, modifiers: 8))
        var state = Fixtures.state(baseline: [toggle: combination.digest])
        state.replica = Fixtures.replica([search: [Fixtures.entry(Fixtures.macB, 5, combination)]])
        state.session.isTrusted = true
        state.session.ownFile = .absent
        state.session.snapshot = Fixtures.snapshot([toggle: combination])
        return (state, search, toggle, combination)
    }

    @Test("A clash answer gives both hotkey units a fresh entry: Keep keeps this Mac's, Use applies the other and clears this Mac's")
    func clashAnswers() throws {
        let (state, search, toggle, combination) = clashState()
        let env = environment(table: realTable)
        let question = try #require(SyncEngine.question(for: state, scope: .mine, environment: env))
        #expect(question.rows.map(\.style) == [.clash(partner: toggle)])
        #expect(question.shown[toggle] == [])
        let keep = answer(.keep, question, state: state, environment: env)
        #expect(keep.state.replica.live(search).map(\.payload) == [.deleted])
        #expect(keep.state.replica.live(toggle).map(\.value) == [combination])
        #expect(applied(keep).isEmpty)
        #expect(keep.state.replica.live(search).first?.dot.mac == Fixtures.macA)
        let use = answer(.use, question, state: state, environment: env)
        #expect(use.state.replica.live(search).map(\.value) == [combination])
        #expect(use.state.replica.live(toggle).map(\.payload) == [.deleted])
        #expect(applied(use) == [search: .value(combination), toggle: .deleted])
        #expect(relaunches(use))
    }

    // MARK: Simultaneous answers

    @Test("Two Macs answering the same conflict at once make one new pair of siblings and one more question, and converge after any answer")
    func simultaneousAnswers() throws {
        let env = environment()
        var one = conflict(local: "a", others: [(Fixtures.macB, 5, "b")])
        let questionOne = try ask(one)
        // B's state: the same two entries, B's own value applied.
        var two = Fixtures.state(Fixtures.macB)
        two.replica = one.replica
        two.applied[Fixtures.s1] = [SyncDot(mac: Fixtures.macB, n: 5)]
        two.baseline[Fixtures.s1] = SyncValue.string("b").digest
        two.counter = 5
        two.publishedCounter = 5
        two.session.isTrusted = true
        two.session.ownFile = .absent
        two.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("b")])
        let questionTwo = try ask(two)
        let keepOne = published(answer(.keep, questionOne, state: one))
        let keepTwo = published(answer(.keep, questionTwo, state: two))
        func exchange(_ left: SyncStep, _ right: SyncStep) throws -> (SyncState, SyncState) {
            let leftFile = try #require(written(left))
            let rightFile = try #require(written(right))
            let first = SyncEngine.handle(.folderRead(SyncFolderRead(files: [file(rightFile)]), purpose: .check), state: left.state, environment: env)
            let second = SyncEngine.handle(.folderRead(SyncFolderRead(files: [file(leftFile)]), purpose: .check), state: right.state, environment: env)
            return (first.state, second.state)
        }
        (one, two) = try exchange(keepOne, keepTwo)
        for state in [one, two] {
            #expect(Set(state.replica.live(Fixtures.s1).map(\.value)) == [.string("a"), .string("b")])
            #expect(state.replica.live(Fixtures.s1).count == 2)
        }
        // One more question on each Mac; one answer settles it, and no value is lost on the way.
        let again = try ask(one)
        let settled = published(answer(.use, again, state: one))
        let received = SyncEngine.handle(.folderRead(SyncFolderRead(files: [file(try #require(written(settled)))]), purpose: .check), state: two, environment: env)
        #expect(settled.state.replica.live(Fixtures.s1).count == 1)
        #expect(received.state.replica.live(Fixtures.s1) == settled.state.replica.live(Fixtures.s1))
        #expect(SyncEngine.question(for: received.state, scope: .mine, environment: env) == nil)
    }

    /// The step after the host wrote the file it asked for and read it back intact.
    private func published(_ step: SyncStep) -> SyncStep {
        var effects: [SyncEffect] = []
        var state = step.state
        for effect in step.effects {
            effects.append(effect)
            if case .writeOwnFile(let request) = effect {
                let receipt = SyncWriteReceipt(counter: request.counter, replicaDigest: request.replicaDigest, fileDigest: request.contents.replica.digest)
                state = SyncPublish.apply(.verified(receipt), to: state)
            }
        }
        return SyncStep(state: state, effects: effects)
    }

    private func file(_ contents: SyncDeviceFile.Contents) -> SyncFileOutcome {
        SyncFileOutcome(macID: contents.mac, size: 200, modified: Fixtures.now, state: .contents(contents))
    }

    // MARK: What an answer never touches

    @Test("An answer supersedes dots only: a unit that is local-only, aliased or holds a value this build cannot use is left alone")
    func answersTouchOnlyDots() throws {
        let state = conflict()
        let question = try ask(state)
        var localOnly = state
        localOnly.localOnly[Fixtures.s1] = .invalid
        let first = answer(.use, question, state: localOnly)
        #expect(first.state.replica == state.replica)
        #expect(first.state.localOnly[Fixtures.s1] == .invalid)
        #expect(first.effects.isEmpty)
        var aliased = state
        aliased.session.snapshot = Fixtures.snapshot([Fixtures.s1: .string("mine")], aliased: [Fixtures.s1])
        let second = answer(.use, question, state: aliased)
        #expect(second.state.replica == state.replica)
        #expect(second.effects.isEmpty)
        // A value this build cannot use ("bad" is invalid for every unit of the test table).
        let unusable = conflict(others: [(Fixtures.macB, 5, "bad")])
        let third = answer(.use, try ask(unusable), state: unusable)
        #expect(third.state.replica == unusable.replica)
        #expect(third.effects.isEmpty)
    }

    @Test("Use without a choice at a two-way row takes the folder's value, and the question never names another Mac")
    func chosenButtonAtTwoWayRows() throws {
        let state = conflict()
        let question = try ask(state)
        let step = answer(.useChosen, question, state: state)
        #expect(step.state.replica.live(Fixtures.s1).map(\.value) == [.string("theirs")])
        // The sheet shows a value and a date; the row carries nothing else about the other Mac.
        let row = try #require(question.rows.first)
        #expect(row.folder.allSatisfy { $0.at == Fixtures.now })
        #expect(row.folder.allSatisfy { if case .entry = $0.source { true } else { false } })
    }
}
