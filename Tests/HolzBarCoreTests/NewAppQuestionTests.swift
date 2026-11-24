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
}
