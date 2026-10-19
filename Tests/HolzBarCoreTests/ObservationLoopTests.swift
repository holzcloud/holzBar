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
        var optionalValue: Int?
        var point = Point(x: 0, y: 0)
    }

    struct Point: Equatable {
        var x: Int
        var y: Int
    }

    /// The values a loop reported, in order.
    @MainActor
    final class Recorder {
        var values = [Int]()
    }

    /// The values a loop of any value type reported, in order.
    @MainActor
    final class Reports<Value> {
        var values = [Value]()
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

    @Test("An optional value is reported when it changes, not when it stays")
    func optionalValue() async throws {
        let counter = Counter()
        let reports = Reports<Int?>()
        let loop = ObservationLoop.observe { counter.optionalValue } onChange: { reports.values.append($0) }
        counter.optionalValue = nil
        try await settle()
        counter.optionalValue = 5
        try await settle()
        counter.optionalValue = 5
        try await settle()
        counter.optionalValue = nil
        try await settle()
        #expect(reports.values == [5, nil])
        loop.cancel()
    }

    @Test("A struct value equal to the last one is not reported")
    func structValue() async throws {
        let counter = Counter()
        let reports = Reports<Point>()
        let loop = ObservationLoop.observe { counter.point } onChange: { reports.values.append($0) }
        counter.point = Point(x: 0, y: 0)
        try await settle()
        counter.point = Point(x: 1, y: 0)
        try await settle()
        counter.point = Point(x: 1, y: 0)
        try await settle()
        #expect(reports.values == [Point(x: 1, y: 0)])
        loop.cancel()
    }

    @Test("A value that changes and changes back in one turn is not reported")
    func changesBackInOneTurn() async throws {
        let counter = Counter()
        let reports = Recorder()
        let loop = ObservationLoop.observe { counter.value } onChange: { reports.values.append($0) }
        counter.value = 1
        counter.value = 0
        try await settle()
        #expect(reports.values.isEmpty)
        loop.cancel()
    }
}
