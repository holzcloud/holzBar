import Testing
@testable import HolzBarCore

@MainActor
@Suite("Debouncer")
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
