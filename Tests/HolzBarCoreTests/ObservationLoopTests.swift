import Observation
import Testing
@testable import HolzBarCore

@MainActor
@Suite("ObservationLoop")
struct ObservationLoopTests {
    @MainActor
    @Observable
    final class Counter {
        var value = 0
    }

    /// The values a loop reported, in order.
    @MainActor
    final class Recorder {
        var values = [Int]()
    }

    /// Lets the main actor run the hops the loop schedules.
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    @Test("A change is reported after it happens")
    func reportsNewValue() async throws {
        let counter = Counter()
        let reports = Recorder()
        let loop = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        counter.value = 1
        try await settle()
        #expect(reports.values == [1])
        loop.cancel()
    }

    @Test("Changes in one turn are reported once")
    func coalescesChanges() async throws {
        let counter = Counter()
        let reports = Recorder()
        let loop = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        counter.value = 1
        counter.value = 2
        counter.value = 3
        try await settle()
        #expect(reports.values == [3])
        loop.cancel()
    }

    @Test("Observing goes on after a report")
    func reArms() async throws {
        let counter = Counter()
        let reports = Recorder()
        let loop = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        counter.value = 1
        try await settle()
        counter.value = 2
        try await settle()
        #expect(reports.values == [1, 2])
        loop.cancel()
    }

    @Test("An assignment of the same value is not reported")
    func skipsEqualValue() async throws {
        let counter = Counter()
        let reports = Recorder()
        let loop = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        counter.value = 0
        try await settle()
        counter.value = 4
        try await settle()
        #expect(reports.values == [4])
        loop.cancel()
    }

    @Test("A cancelled observation reports nothing")
    func cancelStops() async throws {
        let counter = Counter()
        let reports = Recorder()
        let loop = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        loop.cancel()
        counter.value = 1
        try await settle()
        #expect(reports.values.isEmpty)
    }

    @Test("A released observation reports nothing")
    func releaseStops() async throws {
        let counter = Counter()
        let reports = Recorder()
        var loop: ObservationLoop? = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        #expect(loop != nil)
        loop = nil
        counter.value = 1
        try await settle()
        #expect(reports.values.isEmpty)
    }
}
