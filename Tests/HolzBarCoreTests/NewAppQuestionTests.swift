import Testing
@testable import HolzBarCore

@Suite("NewAppQuestion")
struct NewAppQuestionTests {
    private let own = "com.holzcloud.holzBar"
    private let start = ContinuousClock.now
    private var open: NewAppQuestion.Gate {
        NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: [], startedAt: start)
    }

    /// Long after the quiet start and the coalescing of an app noticed at `start`.
    private var later: ContinuousClock.Instant {
        start.advanced(by: .seconds(120))
    }

    private func app(_ id: String, name: String? = nil, noticedAfter delay: Duration = .zero) -> NewAppQuestion.App {
        NewAppQuestion.App(bundleID: id, name: name ?? id, noticedAt: start.advanced(by: delay))
    }

    @Test("An app is noted once, also when it is already asked")
    func notesOnce() {
        var question = NewAppQuestion()
        question.note(app("com.example.One"))
        question.note(app("com.example.One", name: "Other name"))
        #expect(question.waiting.map(\.bundleID) == ["com.example.One"])
        #expect(question.waiting.first?.name == "com.example.One")
        _ = question.release(gate: open, at: later)
        question.note(app("com.example.One"))
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.One"])
    }

    @Test("The open gate asks every waiting app, in the order they were noticed")
    func releaseWhenOpen() {
        var question = NewAppQuestion()
        question.note(app("com.example.B"))
        question.note(app("com.example.A"))
        #expect(question.release(gate: open, at: later) == nil)
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.B", "com.example.A"])
        question.note(app("com.example.C"))
        _ = question.release(gate: open, at: later)
        #expect(question.asked.map(\.bundleID) == ["com.example.B", "com.example.A", "com.example.C"])
    }

    @Test("A drag, an unsettled bar or a launch grace keeps apps waiting, and drops none")
    func closedGates() {
        var question = NewAppQuestion()
        question.note(app("com.example.One"))
        let closed = [
            NewAppQuestion.Gate(isDragging: true, isSettled: true, launchGrace: [], startedAt: start),
            NewAppQuestion.Gate(isDragging: false, isSettled: false, launchGrace: [], startedAt: start),
            NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: ["com.example.One"], startedAt: start),
        ]
        for gate in closed {
            _ = question.release(gate: gate, at: later)
            #expect(question.waiting.map(\.bundleID) == ["com.example.One"])
            #expect(question.asked.isEmpty)
        }
        _ = question.release(gate: open, at: later)
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.One"])
    }

    @Test("Remove takes an app out of both lists, clear empties them")
    func removeAndClear() {
        var question = NewAppQuestion()
        question.note(app("com.example.A"))
        question.note(app("com.example.B"))
        _ = question.release(gate: open, at: later)
        question.note(app("com.example.C"))
        question.remove("com.example.A")
        question.remove("com.example.C")
        #expect(question.asked.map(\.bundleID) == ["com.example.B"])
        #expect(question.waiting.isEmpty)
        question.note(app("com.example.D"))
        question.clear()
        #expect(question.asked.isEmpty)
        #expect(question.waiting.isEmpty)
    }

    @Test("The answers are the three sections and Don't ask again")
    func answers() {
        #expect(NewAppQuestion.Answer.allCases.map(\.rawValue) == ["visible", "hidden", "alwaysHidden", "dontAskAgain"])
    }

    @Test("Apple's apps, holzBar's own bundle, declined apps, helpers and empty identifiers are never asked")
    func eligibility() {
        func eligible(_ id: String, _ path: String? = "/Applications/Tool.app", declined: Set<String> = []) -> Bool {
            NewAppQuestion.isEligible(bundleID: id, bundlePath: path, ownBundleID: own, declined: declined)
        }
        #expect(eligible("com.example.Tool"))
        #expect(!eligible("com.apple.Notes"))
        #expect(!eligible("COM.APPLE.Notes"))
        #expect(!eligible(own))
        #expect(!eligible("COM.HOLZCLOUD.HOLZBAR"))
        #expect(!eligible("com.example.Tool", declined: ["com.example.Tool"]))
        // Whitespace around the identifier does not get past a decline, whichever form was stored.
        #expect(!eligible(" com.example.Tool ", declined: ["com.example.Tool"]))
        #expect(!eligible(" com.example.Tool ", declined: [" com.example.Tool "]))
        #expect(!eligible("com.example.Helper", "/Applications/Tool.app/Contents/Library/LoginItems/Helper.app"))
        #expect(!eligible(""))
        #expect(!eligible("  "))
        // An app named like Apple's is judged by its identifier, not by what it calls itself.
        #expect(eligible("com.example.Notes"))
    }

    @Test("The rows are cut at the limit with the rest counted")
    func shownRows() {
        let six = (1...6).map { app("com.example.\($0)") }
        let cut = NewAppQuestion.shown(six, limit: 4)
        #expect(cut.rows.map(\.bundleID) == six.prefix(4).map(\.bundleID))
        #expect(cut.more == 2)
        let three = NewAppQuestion.shown(Array(six.prefix(3)), limit: 4)
        #expect(three.rows.count == 3)
        #expect(three.more == 0)
        #expect(NewAppQuestion.shown(six).rows.count == NewAppQuestion.defaultRowLimit)
        #expect(NewAppQuestion.shown(six, limit: -1).rows.isEmpty)
    }

    @Test("A name with a writing-direction override is cleaned before it is noted")
    func cleanedNames() {
        let cleaned = ItemRuleNotices.cleanedName("Tool\u{202E}elppA", fallback: "com.example.Tool")
        #expect(cleaned == "ToolelppA")
        #expect(ItemRuleNotices.cleanedName("\u{202E}\n", fallback: "com.example.Tool") == "com.example.Tool")
    }

    @Test("Before the quiet start every app waits, none is dropped, and all come together after it")
    func quietStart() {
        var question = NewAppQuestion()
        question.note(app("com.example.A"))
        question.note(app("com.example.B", noticedAfter: .seconds(3)))
        let end = start.advanced(by: .seconds(60))
        #expect(question.release(gate: open, at: start.advanced(by: .seconds(30))) == end)
        #expect(question.waiting.map(\.bundleID) == ["com.example.A", "com.example.B"])
        #expect(question.asked.isEmpty)
        #expect(question.release(gate: open, at: end.advanced(by: .seconds(-1))) == end)
        #expect(question.asked.isEmpty)
        #expect(question.release(gate: open, at: end) == nil)
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.A", "com.example.B"])
    }

    @Test("An app in its launch grace waits while the others are asked, and is asked after its grace")
    func perAppLaunchGrace() {
        var question = NewAppQuestion()
        question.note(app("com.example.A"))
        question.note(app("com.example.B"))
        let grace = NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: ["com.example.B"], startedAt: start)
        #expect(question.release(gate: grace, at: later) == nil)
        #expect(question.asked.map(\.bundleID) == ["com.example.A"])
        #expect(question.waiting.map(\.bundleID) == ["com.example.B"])
        _ = question.release(gate: open, at: later)
        #expect(question.asked.map(\.bundleID) == ["com.example.A", "com.example.B"])
        #expect(question.waiting.isEmpty)
    }

    @Test("Apps noticed a few seconds apart are asked together, ten seconds after the last one")
    func coalescesABurst() {
        var question = NewAppQuestion()
        let gate = NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: [], startedAt: start.advanced(by: .seconds(-3600)))
        question.note(app("com.example.A"))
        question.note(app("com.example.B", noticedAfter: .seconds(2)))
        question.note(app("com.example.C", noticedAfter: .seconds(4)))
        let first = start.advanced(by: .seconds(14))
        #expect(question.release(gate: gate, at: start.advanced(by: .seconds(13))) == first)
        #expect(question.asked.isEmpty)
        // A fourth app noticed during the ten seconds joins the others and moves the end.
        question.note(app("com.example.D", noticedAfter: .seconds(8)))
        let second = start.advanced(by: .seconds(18))
        #expect(question.release(gate: gate, at: first) == second)
        #expect(question.asked.isEmpty)
        #expect(question.release(gate: gate, at: second) == nil)
        #expect(question.asked.map(\.bundleID) == ["com.example.A", "com.example.B", "com.example.C", "com.example.D"])
        #expect(question.waiting.isEmpty)
    }

    @Test("A closed gate names no instant, because only an event can open it")
    func closedGateNamesNoInstant() {
        var question = NewAppQuestion()
        question.note(app("com.example.A"))
        let dragging = NewAppQuestion.Gate(isDragging: true, isSettled: true, launchGrace: [], startedAt: start)
        #expect(question.release(gate: dragging, at: start) == nil)
        let allInGrace = NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: ["com.example.A"], startedAt: start)
        #expect(question.release(gate: allInGrace, at: start) == nil)
        #expect(question.waiting.map(\.bundleID) == ["com.example.A"])
    }

    @Test("The declined list adds once, keeps the newest 512 and drops the oldest first")
    func declinedList() {
        #expect(NewAppQuestion.declined(adding: "b", to: ["a"]) == ["a", "b"])
        #expect(NewAppQuestion.declined(adding: "a", to: ["a", "b"]) == ["a", "b"])
        let cap = NewAppQuestion.Policy.maximumRemembered
        let full = (0..<cap).map { "com.example.\($0)" }
        let grown = NewAppQuestion.declined(adding: "com.example.new", to: full)
        #expect(grown.count == cap)
        #expect(grown.first == "com.example.1")
        #expect(grown.last == "com.example.new")
    }

    @Test("The waiting list adds once in order, drops the oldest past the cap and removes one")
    func rememberedList() {
        #expect(NewAppQuestion.remembered(adding: ["b", "c"], to: ["a", "b"]) == ["a", "b", "c"])
        #expect(NewAppQuestion.remembered(adding: ["c", "c"], to: []) == ["c"])
        #expect(NewAppQuestion.remembered(adding: [""], to: ["a"]) == ["a"])
        let cap = NewAppQuestion.Policy.maximumRemembered
        #expect(cap == 512)
        let full = (0..<cap).map { "com.example.\($0)" }
        let grown = NewAppQuestion.remembered(adding: ["com.example.new"], to: full)
        #expect(grown.count == cap)
        #expect(grown.first == "com.example.1")
        #expect(grown.last == "com.example.new")
        let hugeEdit = (0..<(cap + 40)).map { "com.example.\($0)" }
        #expect(NewAppQuestion.remembered(adding: [], to: hugeEdit).count == cap)
        #expect(NewAppQuestion.remembered(removing: "b", from: ["a", "b", "c"]) == ["a", "c"])
        #expect(NewAppQuestion.remembered(removing: "z", from: ["a"]) == ["a"])
    }
}
