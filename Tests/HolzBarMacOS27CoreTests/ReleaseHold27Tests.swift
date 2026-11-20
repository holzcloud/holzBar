import Testing
@testable import HolzBarMacOS27Core

@Suite("ReleaseHold27")
@MainActor
struct ReleaseHold27Tests {
    /// Counts the begins and ends of a hold, in order.
    final class Recorder {
        var begins = 0
        var ends = 0
        var log = [String]()
        var landed = true

        func begin(_ name: String = "") async -> Bool {
            begins += 1
            log.append("begin \(name)")
            return landed
        }

        func end(_ name: String = "") {
            ends += 1
            log.append("end \(name)")
        }
    }

    struct Failure: Error {}

    @Test("A new hold is not held")
    func startsFree() {
        let hold = ReleaseHold27()
        #expect(!hold.isHeld)
        #expect(hold.count == 0)
    }

    @Test("Two begins and one end are still held")
    func nested() {
        var hold = ReleaseHold27()
        hold.begin()
        hold.begin()
        let first = hold.end()
        #expect(first)
        #expect(hold.isHeld)
        #expect(hold.count == 1)
    }

    @Test("Ends never take the count below zero")
    func neverBelowZero() {
        var hold = ReleaseHold27()
        hold.begin()
        hold.begin()
        hold.end()
        let second = hold.end()
        let third = hold.end()
        #expect(second)
        #expect(!third)
        #expect(hold.count == 0)
        #expect(!hold.isHeld)
    }

    @Test("The target is empty while held and unchanged otherwise")
    func target() {
        var hold = ReleaseHold27()
        let sets: [Set<String>] = [["a"], ["b", "c"], []]
        #expect(hold.target(sets) == sets)
        hold.begin()
        #expect(hold.target(sets).isEmpty)
        hold.end()
        #expect(hold.target(sets) == sets)
    }

    @Test("The body gets true when the hold landed, and the hold ends once")
    func landed() async {
        let recorder = Recorder()
        let answer = await ReleaseHold27.withHold(begin: { await recorder.begin() }, end: { recorder.end() }) { landed in
            landed
        }
        #expect(answer)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 1)
    }

    @Test("The body still runs when the hold did not land, and the hold ends once")
    func notLanded() async {
        let recorder = Recorder()
        recorder.landed = false
        let answer = await ReleaseHold27.withHold(begin: { await recorder.begin() }, end: { recorder.end() }) { landed in
            landed
        }
        #expect(!answer)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 1)
    }

    @Test("A body that returns early ends the hold once")
    func earlyReturn() async {
        let recorder = Recorder()
        func run(early: Bool) async -> Int {
            await ReleaseHold27.withHold(begin: { await recorder.begin() }, end: { recorder.end() }) { _ in
                if early {
                    return 1
                }
                return 2
            }
        }
        let value = await run(early: true)
        #expect(value == 1)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 1)
    }

    @Test("A body that throws ends the hold once and the error is rethrown")
    func throwing() async {
        let recorder = Recorder()
        var caught = false
        do {
            try await ReleaseHold27.withHold(begin: { await recorder.begin() }, end: { recorder.end() }) { _ in
                throw Failure()
            }
        } catch is Failure {
            caught = true
        } catch {}
        #expect(caught)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 1)
    }

    @Test("A cancelled task ends the hold once")
    func cancelled() async {
        let recorder = Recorder()
        let task = Task { @MainActor in
            try await ReleaseHold27.withHold(begin: { await recorder.begin() }, end: { recorder.end() }) { _ in
                try await Task.sleep(for: .seconds(30))
            }
        }
        // Let the body start waiting.
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        #expect((try? result.get()) == nil)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 1)
    }

    @Test("Nested holds end inner first, then outer")
    func nestedHolds() async {
        let recorder = Recorder()
        await ReleaseHold27.withHold(begin: { await recorder.begin("outer") }, end: { recorder.end("outer") }) { _ in
            await ReleaseHold27.withHold(begin: { await recorder.begin("inner") }, end: { recorder.end("inner") }) { _ in }
        }
        #expect(recorder.begins == 2)
        #expect(recorder.ends == 2)
        #expect(recorder.log == ["begin outer", "begin inner", "end inner", "end outer"])
    }
}
