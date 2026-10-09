import Testing
@testable import HolzBarCore

/// The item image cache runs one capture pass at a time; requests during a pass join one
/// re-run, so no request waits behind a pile of queued captures (F-13).
@MainActor
@Suite("Coalesced run")
struct CoalescedRunTests {
    /// Records the batches, the most operations running at once, and holds the first batch
    /// until the test opens the gate.
    @MainActor
    final class Recorder {
        var batches = [Set<Int>]()
        var running = 0
        var maxRunning = 0
        var started = false
        private var isOpen = false
        private var waiter: CheckedContinuation<Void, Never>?

        func operation(_ batch: Set<Int>, holds: Bool) async {
            running += 1
            maxRunning = max(maxRunning, running)
            started = true
            if holds, !isOpen {
                await withCheckedContinuation { waiter = $0 }
            }
            batches.append(batch)
            running -= 1
        }

        func open() {
            isOpen = true
            waiter?.resume()
            waiter = nil
        }
    }

    /// Yields until the condition holds, at most 1000 times, so a bug fails the test
    /// instead of hanging it.
    private func yield(until condition: () -> Bool) async -> Bool {
        for _ in 0..<1000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }

    @Test("Requests while a batch runs share one re-run")
    func requestsShareOneRerun() async {
        let run = CoalescedRun<Int>()
        let recorder = Recorder()
        let operation: @MainActor (Set<Int>) async -> Void = { batch in
            await recorder.operation(batch, holds: batch == [1])
        }
        let first = Task { await run.run([1], operation: operation) }
        #expect(await yield { recorder.started })
        let second = Task { await run.run([2], operation: operation) }
        let third = Task { await run.run([3, 2], operation: operation) }
        #expect(await yield { run.pending == [2, 3] })
        recorder.open()
        await first.value
        await second.value
        await third.value
        #expect(recorder.batches == [[1], [2, 3]])
        #expect(recorder.maxRunning == 1)
        #expect(!run.isRunning)
    }

    @Test("Each waiter returns only after its elements ran")
    func waiterReturnsAfterItsElements() async {
        let run = CoalescedRun<Int>()
        let recorder = Recorder()
        let operation: @MainActor (Set<Int>) async -> Void = { batch in
            await recorder.operation(batch, holds: batch == [1])
        }
        let first = Task { await run.run([1], operation: operation) }
        #expect(await yield { recorder.started })
        let second = Task {
            await run.run([2], operation: operation)
            return recorder.batches
        }
        let third = Task { await run.run([3, 2], operation: operation) }
        #expect(await yield { run.pending == [2, 3] })
        recorder.open()
        #expect(await second.value.contains([2, 3]))
        await first.value
        await third.value
    }

    @Test("A request after the run ended starts a new run")
    func laterRequestStartsNewRun() async {
        let run = CoalescedRun<Int>()
        let recorder = Recorder()
        let operation: @MainActor (Set<Int>) async -> Void = { batch in
            await recorder.operation(batch, holds: false)
        }
        await run.run([1], operation: operation)
        await run.run([2], operation: operation)
        #expect(recorder.batches == [[1], [2]])
    }

    @Test("An empty request runs nothing")
    func emptyRequestRunsNothing() async {
        let run = CoalescedRun<Int>()
        let recorder = Recorder()
        await run.run([]) { batch in
            await recorder.operation(batch, holds: false)
        }
        #expect(recorder.batches.isEmpty)
        #expect(!run.isRunning)
    }
}
