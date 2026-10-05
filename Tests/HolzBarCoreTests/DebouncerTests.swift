import Testing
@testable import HolzBarCore

@MainActor
@Suite("Debouncer", .serialized)
struct DebouncerTests {
    /// The actions that ran, in order.
    @MainActor
    final class Recorder {
        var values = [Int]()
    }

    @Test("Only the last call runs")
    func onlyLastRuns() async throws {
        let debouncer = Debouncer(delay: .milliseconds(50))
        let runs = Recorder()
        debouncer.schedule { runs.values.append(1) }
        debouncer.schedule { runs.values.append(2) }
        debouncer.schedule { runs.values.append(3) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(runs.values == [3])
    }

    @Test("A cancelled debouncer runs nothing")
    func cancelDropsAction() async throws {
        let debouncer = Debouncer(delay: .milliseconds(50))
        let runs = Recorder()
        debouncer.schedule { runs.values.append(1) }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(400))
        #expect(runs.values.isEmpty)
    }

    /// Holds the main actor past the debouncer's delay once its task sleeps, so the sleep
    /// finishes while the task waits to resume, as when an event is queued just before the
    /// timer fires.
    private func blockAfterSleepStarts(for duration: Duration) async {
        await Task.yield()
        let end = ContinuousClock.now + duration
        while ContinuousClock.now < end {}
    }

    @Test("A call after the sleep finished still supersedes the pending action")
    func scheduleAfterFinishedSleepSupersedes() async throws {
        let debouncer = Debouncer(delay: .milliseconds(10))
        let runs = Recorder()
        debouncer.schedule { runs.values.append(1) }
        await blockAfterSleepStarts(for: .milliseconds(100))
        debouncer.schedule { runs.values.append(2) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(runs.values == [2])
    }

    @Test("Cancelling after the sleep finished still drops the action")
    func cancelAfterFinishedSleepDropsAction() async throws {
        let debouncer = Debouncer(delay: .milliseconds(10))
        let runs = Recorder()
        debouncer.schedule { runs.values.append(1) }
        await blockAfterSleepStarts(for: .milliseconds(100))
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(400))
        #expect(runs.values.isEmpty)
    }

    @Test("A cancelled throttle task does not take a newer pending action")
    func cancelledThrottleTaskIsStale() async throws {
        let debouncer = Debouncer(delay: .milliseconds(100))
        let runs = Recorder()
        debouncer.throttle { runs.values.append(1) }
        debouncer.throttle { runs.values.append(2) }
        await blockAfterSleepStarts(for: .milliseconds(200))
        debouncer.cancel()
        debouncer.throttle { runs.values.append(3) }
        debouncer.throttle { runs.values.append(4) }
        // The last call waits the delay; only the stale task would run it now.
        try await Task.sleep(for: .milliseconds(20))
        #expect(runs.values == [1, 3])
        try await Task.sleep(for: .milliseconds(400))
        #expect(runs.values == [1, 3, 4])
    }

    @Test("A throttled call runs at once, the next ones once after the delay")
    func throttleRunsFirstAtOnce() async throws {
        let debouncer = Debouncer(delay: .milliseconds(200))
        let runs = Recorder()
        debouncer.throttle { runs.values.append(1) }
        #expect(runs.values == [1])
        debouncer.throttle { runs.values.append(2) }
        debouncer.throttle { runs.values.append(3) }
        #expect(runs.values == [1])
        try await Task.sleep(for: .milliseconds(800))
        #expect(runs.values == [1, 2])
    }

    @Test("A latest throttle runs the last call of the delay")
    func throttleLatestRunsLast() async throws {
        let debouncer = Debouncer(delay: .milliseconds(200))
        let runs = Recorder()
        debouncer.throttle(latest: true) { runs.values.append(1) }
        debouncer.throttle(latest: true) { runs.values.append(2) }
        debouncer.throttle(latest: true) { runs.values.append(3) }
        try await Task.sleep(for: .milliseconds(800))
        #expect(runs.values == [1, 3])
    }
}
