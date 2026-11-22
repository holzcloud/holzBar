import Foundation
import Testing
@testable import HolzBarCore

@Suite("CPUClusters")
struct CPUClustersTests {
    /// One processor as `sysctl` lists it: the levels by index with the name and size the kernel
    /// reports, and the number of cores. `origin` says where the numbers come from.
    struct Fixture: Sendable {
        var name: String
        var origin: String
        var levels: [ClusterLevel]
        var coreCount: Int
        var expected: [Range<Int>]?
    }

    private static func levels(_ entries: [(String, Int)]) -> [ClusterLevel] {
        entries.enumerated().map { ClusterLevel(index: $0.offset, name: $0.element.0, logicalCPUs: $0.element.1) }
    }

    static let fixtures: [Fixture] = [
        // Measured on the maintainer's Mac (research V-2, V-3).
        Fixture(
            name: "M1 Max",
            origin: "measured",
            levels: levels([("Performance", 8), ("Efficiency", 2)]),
            coreCount: 10,
            expected: [2..<10, 0..<2]
        ),
        // Community sysctl dumps (research V-3b).
        Fixture(
            name: "M1",
            origin: "community dump",
            levels: levels([("Performance", 4), ("Efficiency", 4)]),
            coreCount: 8,
            expected: [4..<8, 0..<4]
        ),
        Fixture(
            name: "M3 Max",
            origin: "community dump",
            levels: levels([("Performance", 12), ("Efficiency", 4)]),
            coreCount: 16,
            expected: [4..<16, 0..<4]
        ),
        Fixture(
            name: "M5 (two-level)",
            origin: "community dump",
            levels: levels([("Super", 4), ("Efficiency", 6)]),
            coreCount: 10,
            expected: [6..<10, 0..<6]
        ),
        Fixture(
            name: "M5 Pro (two-level)",
            origin: "community dump",
            levels: levels([("Super", 5), ("Performance", 10)]),
            coreCount: 15,
            expected: [10..<15, 0..<10]
        ),
        Fixture(
            name: "M5 Max (two-level)",
            origin: "community dump",
            levels: levels([("Super", 6), ("Performance", 12)]),
            coreCount: 18,
            expected: [12..<18, 0..<12]
        ),
        // Synthetic per D-20: no real three-level dump exists, so these exercise the generic
        // partition of N levels.
        Fixture(
            name: "M5 Pro (three-level)",
            origin: "synthetic per D-20",
            levels: levels([("Super", 4), ("Performance", 6), ("Efficiency", 4)]),
            coreCount: 14,
            expected: [10..<14, 4..<10, 0..<4]
        ),
        Fixture(
            name: "M6",
            origin: "synthetic per D-20",
            levels: levels([("Super", 6), ("Performance", 6), ("Efficiency", 4)]),
            coreCount: 16,
            expected: [10..<16, 4..<10, 0..<4]
        ),
        // An Intel Mac has no hw.nperflevels, so no levels: the total is shown.
        Fixture(name: "Intel", origin: "no levels", levels: [], coreCount: 8, expected: nil),
    ]

    @Test("The cores are partitioned from the end by count and index", arguments: fixtures)
    func partition(fixture: Fixture) {
        let ranges = CPUClusters.ranges(levels: fixture.levels, coreCount: fixture.coreCount)
        #expect(ranges == fixture.expected, "\(fixture.name) (\(fixture.origin))")
    }

    @Test("One level, a size of zero or sizes that disagree give no clusters")
    func noClusters() {
        let one = Self.levels([("Performance", 8)])
        #expect(CPUClusters.ranges(levels: one, coreCount: 8) == nil)

        let empty = Self.levels([("Performance", 8), ("Efficiency", 0)])
        #expect(CPUClusters.ranges(levels: empty, coreCount: 8) == nil)

        let negative = Self.levels([("Performance", 10), ("Efficiency", -2)])
        #expect(CPUClusters.ranges(levels: negative, coreCount: 8) == nil)

        let two = Self.levels([("Performance", 8), ("Efficiency", 2)])
        #expect(CPUClusters.ranges(levels: two, coreCount: 9) == nil)
        #expect(CPUClusters.ranges(levels: two, coreCount: 11) == nil)
        #expect(CPUClusters.ranges(levels: two, coreCount: 0) == nil)

        let gap = [
            ClusterLevel(index: 0, name: "Performance", logicalCPUs: 8),
            ClusterLevel(index: 2, name: "Efficiency", logicalCPUs: 2),
        ]
        #expect(CPUClusters.ranges(levels: gap, coreCount: 10) == nil)

        let huge = Self.levels([("Performance", Int.max), ("Efficiency", 2)])
        #expect(CPUClusters.ranges(levels: huge, coreCount: 10) == nil)
    }

    @Test("Levels given in another order are split by their index")
    func unorderedLevels() {
        let levels = [
            ClusterLevel(index: 1, name: "Efficiency", logicalCPUs: 2),
            ClusterLevel(index: 0, name: "Performance", logicalCPUs: 8),
        ]
        #expect(CPUClusters.ranges(levels: levels, coreCount: 10) == [2..<10, 0..<2])
    }

    // MARK: Loads

    private func ticks(user: UInt64, idle: UInt64) -> CPUTicks {
        CPUTicks(user: user, system: 0, idle: idle, nice: 0)
    }

    @Test("The load of a cluster is its summed ticks through the CPU load")
    func clusterLoads() throws {
        let levels = Self.levels([("Performance", 8), ("Efficiency", 2)])
        let previous = Array(repeating: ticks(user: 0, idle: 0), count: 10)
        // The efficiency cores (the first two) are half busy, the performance cores a tenth.
        let current = Array(repeating: ticks(user: 50, idle: 50), count: 2)
            + Array(repeating: ticks(user: 10, idle: 90), count: 8)
        let loads = try #require(CPUClusters.loads(levels: levels, previous: previous, current: current))
        #expect(loads.count == 2)
        #expect(loads[0].level == levels[0])
        #expect(loads[0].label == .performance)
        #expect(abs(loads[0].load - 0.1) < 1e-9)
        #expect(loads[1].level == levels[1])
        #expect(loads[1].label == .efficiency)
        #expect(abs(loads[1].load - 0.5) < 1e-9)
    }

    @Test("A three-level chip gives three loads in level order")
    func threeClusterLoads() throws {
        let fixture = Self.fixtures[6]
        let previous = Array(repeating: ticks(user: 0, idle: 0), count: fixture.coreCount)
        var current = Array(repeating: ticks(user: 0, idle: 100), count: fixture.coreCount)
        for core in 10..<14 {
            current[core] = ticks(user: 100, idle: 0)
        }
        let loads = try #require(CPUClusters.loads(levels: fixture.levels, previous: previous, current: current))
        #expect(loads.map(\.load) == [1, 0, 0])
        #expect(loads.map(\.label) == [.other("S"), .performance, .efficiency])
    }

    @Test("Different lengths, a wrong core count or a backwards cluster give no loads")
    func noLoads() {
        let levels = Self.levels([("Performance", 8), ("Efficiency", 2)])
        let ten = Array(repeating: ticks(user: 1, idle: 1), count: 10)
        let later = Array(repeating: ticks(user: 2, idle: 2), count: 10)
        #expect(CPUClusters.loads(levels: levels, previous: ten, current: later) != nil)

        let nine = Array(repeating: ticks(user: 1, idle: 1), count: 9)
        #expect(CPUClusters.loads(levels: levels, previous: nine, current: later) == nil)
        #expect(CPUClusters.loads(levels: levels, previous: nine, current: nine) == nil)

        // One cluster's counters went backwards.
        var backwards = later
        backwards[0] = ticks(user: 0, idle: 0)
        backwards[1] = ticks(user: 0, idle: 0)
        #expect(CPUClusters.loads(levels: levels, previous: ten, current: backwards) == nil)

        // Nothing moved at all.
        #expect(CPUClusters.loads(levels: levels, previous: ten, current: ten) == nil)
        #expect(CPUClusters.loads(levels: [], previous: ten, current: later) == nil)
    }

    // MARK: Labels

    @Test("The label follows the role name, then the first letter, then the index")
    func labels() {
        #expect(ClusterLabel(kernelName: "Performance", index: 0) == .performance)
        #expect(ClusterLabel(kernelName: "Efficiency", index: 1) == .efficiency)
        #expect(ClusterLabel(kernelName: "Super", index: 0) == .other("S"))
        #expect(ClusterLabel(kernelName: "ultra", index: 0) == .other("U"))
        #expect(ClusterLabel(kernelName: "", index: 2) == .other("2"))
        #expect(ClusterLabel(kernelName: "  ", index: 1) == .other("1"))
    }
}
