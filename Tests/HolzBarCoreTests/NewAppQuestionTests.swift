import Testing
@testable import HolzBarCore

@Suite("NewAppQuestion")
struct NewAppQuestionTests {
    private let own = "com.holzcloud.holzBar"
    private let open = NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: [])

    private func app(_ id: String, name: String? = nil) -> NewAppQuestion.App {
        NewAppQuestion.App(bundleID: id, name: name ?? id, noticedAt: .now)
    }

    @Test("An app is noted once, also when it is already asked")
    func notesOnce() {
        var question = NewAppQuestion()
        question.note(app("com.example.One"))
        question.note(app("com.example.One", name: "Other name"))
        #expect(question.waiting.map(\.bundleID) == ["com.example.One"])
        #expect(question.waiting.first?.name == "com.example.One")
        _ = question.release(gate: open, at: .now)
        question.note(app("com.example.One"))
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.One"])
    }

    @Test("The open gate asks every waiting app, in the order they were noticed")
    func releaseWhenOpen() {
        var question = NewAppQuestion()
        question.note(app("com.example.B"))
        question.note(app("com.example.A"))
        #expect(question.release(gate: open, at: .now) == nil)
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.B", "com.example.A"])
        question.note(app("com.example.C"))
        _ = question.release(gate: open, at: .now)
        #expect(question.asked.map(\.bundleID) == ["com.example.B", "com.example.A", "com.example.C"])
    }

    @Test("A drag, an unsettled bar or a launch grace keeps apps waiting, and drops none")
    func closedGates() {
        var question = NewAppQuestion()
        question.note(app("com.example.One"))
        let closed = [
            NewAppQuestion.Gate(isDragging: true, isSettled: true, launchGrace: []),
            NewAppQuestion.Gate(isDragging: false, isSettled: false, launchGrace: []),
            NewAppQuestion.Gate(isDragging: false, isSettled: true, launchGrace: ["com.example.Other"]),
        ]
        for gate in closed {
            _ = question.release(gate: gate, at: .now)
            #expect(question.waiting.map(\.bundleID) == ["com.example.One"])
            #expect(question.asked.isEmpty)
        }
        _ = question.release(gate: open, at: .now)
        #expect(question.waiting.isEmpty)
        #expect(question.asked.map(\.bundleID) == ["com.example.One"])
    }

    @Test("Remove takes an app out of both lists, clear empties them")
    func removeAndClear() {
        var question = NewAppQuestion()
        question.note(app("com.example.A"))
        question.note(app("com.example.B"))
        _ = question.release(gate: open, at: .now)
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
