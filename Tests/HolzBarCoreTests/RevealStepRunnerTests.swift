import Testing
@testable import HolzBarCore

@MainActor
@Suite("RevealStepRunner", .serialized)
struct RevealStepRunnerTests {
    /// What the runner reported, in order.
    @MainActor
    final class Recorder {
        var lengths = [Double]()
        var finishes = 0
    }

    private func schedule(from start: Double = 100, to end: Double = 10) -> RevealAnimationSchedule {
        RevealAnimationSchedule.make(direction: .reveal, from: start, to: end, duration: 0.05)
    }

    /// Waits until the condition holds, at most five seconds, so a slow runner does not fail a run.
    private func wait(until condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test("A run applies every step in order, ends at the target and finishes once")
    func runsToTheEnd() async throws {
        let runner = RevealStepRunner()
        let recorder = Recorder()
        let plan = schedule()
        runner.run(plan, apply: { recorder.lengths.append($0) }, finish: { recorder.finishes += 1 })
        try await wait { recorder.finishes > 0 }
        #expect(recorder.lengths == plan.steps.map(\.length))
        #expect(recorder.lengths.last == 10)
        #expect(recorder.finishes == 1)
    }

    @Test("A cancelled run applies nothing more and never finishes")
    func cancelStops() async throws {
        let runner = RevealStepRunner()
        let recorder = Recorder()
        runner.run(schedule(), apply: { recorder.lengths.append($0) }, finish: { recorder.finishes += 1 })
        runner.cancel()
        try await Task.sleep(for: .milliseconds(500))
        #expect(recorder.lengths.isEmpty)
        #expect(recorder.finishes == 0)
    }

    @Test("A new run replaces the one before it, so they never queue")
    func newRunReplaces() async throws {
        let runner = RevealStepRunner()
        let first = Recorder()
        let second = Recorder()
        runner.run(schedule(from: 100, to: 10), apply: { first.lengths.append($0) }, finish: { first.finishes += 1 })
        runner.run(schedule(from: 50, to: 5), apply: { second.lengths.append($0) }, finish: { second.finishes += 1 })
        try await wait { second.finishes > 0 }
        #expect(first.lengths.isEmpty)
        #expect(first.finishes == 0)
        #expect(second.lengths.last == 5)
        #expect(second.finishes == 1)
    }

    @Test("An instant schedule finishes at once and applies nothing")
    func instant() {
        let runner = RevealStepRunner()
        let recorder = Recorder()
        runner.run(
            RevealAnimationSchedule.make(direction: .reveal, from: 5, to: 5),
            apply: { recorder.lengths.append($0) },
            finish: { recorder.finishes += 1 }
        )
        #expect(recorder.lengths.isEmpty)
        #expect(recorder.finishes == 1)
    }
}
