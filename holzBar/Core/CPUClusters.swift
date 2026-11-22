//
//  CPUClusters.swift
//  holzBar
//

import Foundation

/// One performance level of the processor, as the kernel lists it (`hw.perflevelN`).
nonisolated struct ClusterLevel: Equatable, Sendable {
    /// The level's index: 0 is the fastest.
    var index: Int
    /// The name the kernel gives the level. It is only a label; nothing depends on it.
    var name: String
    /// The number of logical processors in the level.
    var logicalCPUs: Int
}

/// The short label of a cluster in the tile and the widget (UI contract "Cluster labels").
nonisolated enum ClusterLabel: Equatable, Sendable {
    case performance
    case efficiency
    /// Any other level: its name's first letter, or its index when it has no name.
    case other(String)

    /// The label of the level the kernel calls `kernelName`. A level named Performance or
    /// Efficiency has its own label (translated by the app); any other name gives its first letter
    /// in capitals, and a level without a name its index.
    init(kernelName: String, index: Int) {
        let name = kernelName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name.lowercased() {
        case "performance":
            self = .performance
        case "efficiency":
            self = .efficiency
        case "":
            self = .other(String(index))
        default:
            self = .other(String(name.prefix(1)).uppercased())
        }
    }
}

/// The load of one cluster between two readings, from 0 to 1.
nonisolated struct ClusterLoad: Equatable, Sendable {
    var level: ClusterLevel
    var label: ClusterLabel
    var load: Double
}

/// Which cores of the per-core list belong to which performance level (MON-01, D-10).
///
/// The kernel lists the levels fastest first (`hw.perflevel0`), but `host_processor_info` lists the
/// cores slowest first: the cores of level 0 are the last ones of the list, and the slowest level
/// takes the first. The split uses counts and indexes only, never a chip table and never a level's
/// name, so a chip that has not been released yet works too. When the numbers do not add up the
/// split is not made, and the caller shows the total.
nonisolated enum CPUClusters {
    /// The range of core indexes of every level, in level order (fastest first).
    ///
    /// - Returns: `nil` when there are fewer than two levels (the total is the cluster), when the
    ///   level indexes are not 0, 1, 2, ..., when a level has no processor, or when the sizes do
    ///   not add up to `coreCount`.
    static func ranges(levels: [ClusterLevel], coreCount: Int) -> [Range<Int>]? {
        guard levels.count >= 2, coreCount > 0 else {
            return nil
        }
        let ordered = levels.sorted { $0.index < $1.index }
        guard ordered.indices.allSatisfy({ ordered[$0].index == $0 && ordered[$0].logicalCPUs > 0 }) else {
            return nil
        }
        var total = 0
        for level in ordered {
            let (sum, overflow) = total.addingReportingOverflow(level.logicalCPUs)
            guard !overflow else {
                return nil
            }
            total = sum
        }
        guard total == coreCount else {
            return nil
        }
        var end = coreCount
        var result: [Range<Int>] = []
        for level in ordered {
            let start = end - level.logicalCPUs
            result.append(start..<end)
            end = start
        }
        return result
    }

    /// The load of every cluster between two per-core readings, in level order.
    ///
    /// - Returns: `nil` when the levels do not partition the cores, when the two readings have
    ///   different numbers of cores, or when the counters of a cluster went backwards or did not
    ///   move; the caller then shows the total.
    static func loads(
        levels: [ClusterLevel],
        previous: [CPUTicks],
        current: [CPUTicks]
    ) -> [ClusterLoad]? {
        guard previous.count == current.count, let ranges = ranges(levels: levels, coreCount: current.count) else {
            return nil
        }
        let ordered = levels.sorted { $0.index < $1.index }
        var result: [ClusterLoad] = []
        for (level, range) in zip(ordered, ranges) {
            let before = sum(previous[range])
            let after = sum(current[range])
            guard let load = WidgetReadings.cpuLoad(from: before, to: after) else {
                return nil
            }
            result.append(ClusterLoad(
                level: level,
                label: ClusterLabel(kernelName: level.name, index: level.index),
                load: load
            ))
        }
        return result
    }

    /// The ticks of some cores added up; a counter that would overflow stays at its maximum.
    private static func sum(_ ticks: ArraySlice<CPUTicks>) -> CPUTicks {
        func add(_ first: UInt64, _ second: UInt64) -> UInt64 {
            let (sum, overflow) = first.addingReportingOverflow(second)
            return overflow ? UInt64.max : sum
        }
        return ticks.reduce(CPUTicks(user: 0, system: 0, idle: 0, nice: 0)) { total, next in
            CPUTicks(
                user: add(total.user, next.user),
                system: add(total.system, next.system),
                idle: add(total.idle, next.idle),
                nice: add(total.nice, next.nice)
            )
        }
    }
}
