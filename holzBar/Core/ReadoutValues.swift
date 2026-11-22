//
//  ReadoutValues.swift
//  holzBar
//

import Foundation

// The values of the system readouts and the rules that make them honest (D-10, D-11): a rate that
// is not there is `nil` and shown as an en dash, never an old value, a negative number or a huge
// one. Foundation only; the samplers that call the kernel hand their numbers in.

/// Two counters of one source that only grow: bytes received and sent, or bytes read and written.
nonisolated struct CounterPair: Equatable, Sendable {
    var first: UInt64
    var second: UInt64

    /// The sum of two pairs; a counter that would overflow stays at ``UInt64/max``.
    func adding(_ other: CounterPair) -> CounterPair {
        CounterPair(
            first: first.addingReportingOverflow(other.first).overflow ? UInt64.max : first + other.first,
            second: second.addingReportingOverflow(other.second).overflow ? UInt64.max : second + other.second
        )
    }
}

/// The counters of several sources (interfaces) at one instant, by the source's name.
nonisolated struct CounterSnapshot: Equatable, Sendable {
    var at: ContinuousClock.Instant
    var counters: [String: CounterPair]
}

/// Two rates, per second.
nonisolated struct ReadoutRates: Equatable, Sendable {
    var first: Double
    var second: Double
}

/// Turns two readings of growing counters into a rate (MON-09).
///
/// The first snapshot is only a baseline. After that, a rate is the growth of the counters that
/// both snapshots have, over the time between them. It is `nil` when there is nothing honest to
/// say: no earlier snapshot, no time between the two or more than ``maximumGap`` (the Mac slept,
/// and the average would be a lie), no counter in common, or every common counter went backwards.
/// A counter that went backwards (its interface was reset or wrapped) and a counter that only one
/// of the snapshots has (an interface that came or went) are left out of that interval, so a rate
/// is never negative and never made of a jump; the newest snapshot is always the next baseline.
nonisolated struct RateBaseline: Equatable, Sendable {
    /// The longest time between two snapshots that still gives a rate.
    static let maximumGap = Duration.seconds(300)

    private var previous: CounterSnapshot?

    /// Takes the next snapshot and gives the rates since the one before it.
    ///
    /// - Parameter snapshot: The counters now; `nil` when the read failed, which also drops the
    ///   baseline.
    mutating func rates(_ snapshot: CounterSnapshot?) -> ReadoutRates? {
        guard let snapshot else {
            previous = nil
            return nil
        }
        defer {
            previous = snapshot
        }
        guard let previous else {
            return nil
        }
        let elapsed = WidgetReadings.seconds(of: snapshot.at - previous.at)
        guard elapsed > 0, snapshot.at - previous.at <= Self.maximumGap else {
            return nil
        }
        var first = 0.0
        var second = 0.0
        var counted = false
        for (name, now) in snapshot.counters {
            guard let before = previous.counters[name], now.first >= before.first, now.second >= before.second else {
                continue
            }
            first += Double(now.first - before.first)
            second += Double(now.second - before.second)
            counted = true
        }
        guard counted else {
            return nil
        }
        return ReadoutRates(first: first / elapsed, second: second / elapsed)
    }
}

/// One network interface as the kernel lists it.
nonisolated struct InterfaceRecord: Equatable, Sendable {
    var name: String
    /// The interface type (`ifi_type`).
    var type: UInt8
    /// Whether the interface is up.
    var isUp: Bool
    var inputBytes: UInt64
    var outputBytes: UInt64
}

/// Which interfaces count as the Mac's network traffic (MON-03, D-10).
///
/// Only a wired or wireless interface of the kind `en0`, `en1`, ... counts: the name is `en` and
/// ASCII digits, the type is Ethernet and the interface is up. Tunnels (`utun`), the bridge,
/// peer-to-peer and wake interfaces (`awdl`, `llw`, `anpi`, `ap`, `nan`), `gif`, `stf` and the
/// loopback do not: they carry the same bytes again, or none of the user's traffic. The type alone
/// is not enough, because several of them report Ethernet too.
nonisolated enum NetworkInterfaceRule {
    /// `IFT_ETHER`.
    static let ethernetType: UInt8 = 6

    /// Whether the interface counts.
    static func counts(_ record: InterfaceRecord) -> Bool {
        guard record.isUp, record.type == ethernetType, record.name.hasPrefix("en") else {
            return false
        }
        let digits = record.name.dropFirst(2)
        return !digits.isEmpty && digits.utf8.allSatisfy { (0x30...0x39).contains($0) }
    }

    /// The counters of the interfaces that count, by name; two records of one name add up.
    static func counters(_ records: [InterfaceRecord]) -> [String: CounterPair] {
        var result: [String: CounterPair] = [:]
        for record in records where counts(record) {
            let pair = CounterPair(first: record.inputBytes, second: record.outputBytes)
            result[record.name] = result[record.name]?.adding(pair) ?? pair
        }
        return result
    }
}

/// The counters of one block storage driver (MON-04): the bytes it read and wrote since boot.
nonisolated enum DiskStatistics {
    /// The key of the bytes read in the statistics dictionary.
    static let readKey = "Bytes (Read)"
    /// The key of the bytes written in the statistics dictionary.
    static let writeKey = "Bytes (Write)"

    /// The read and written bytes; `nil` when a key is missing or a value is negative.
    static func counters(_ statistics: [String: Int64]) -> CounterPair? {
        guard let read = statistics[readKey], let written = statistics[writeKey], read >= 0, written >= 0 else {
            return nil
        }
        return CounterPair(first: UInt64(read), second: UInt64(written))
    }
}

/// Which block storage drivers count toward the disk activity (MON-04, M-04): the real disks, not
/// the virtual devices on top of them. A mounted disk image (or a sparse bundle) has a driver of
/// its own, and a read from it is counted again on the driver of the physical disk that holds the
/// file, so counting both would show about twice the real rate.
nonisolated enum DiskDriverRule {
    /// The physical interconnect macOS reports for a virtual device such as a disk image.
    static let virtualInterconnect = "Virtual Interface"

    /// Whether a driver counts, given the class of the device it sits on and that device's
    /// physical interconnect. What cannot be read counts: an unknown device is taken for a disk.
    static func counts(deviceClass: String?, physicalInterconnect: String?) -> Bool {
        if physicalInterconnect == virtualInterconnect {
            return false
        }
        if let deviceClass, deviceClass == "AppleDiskImageDevice" || deviceClass.hasPrefix("IOHDIX") {
            return false
        }
        return true
    }
}

/// The memory in use and the total, in bytes.
nonisolated struct MemoryUse: Equatable, Sendable {
    var used: UInt64
    var total: UInt64
}

/// The swap in use and its total, in bytes.
nonisolated struct SwapUsage: Equatable, Sendable {
    var total: UInt64
    var used: UInt64
}

/// The free and the total space of a volume, in bytes.
nonisolated struct DiskSpace: Equatable, Sendable {
    /// The space available, counting what the system may free (the figure Finder shows).
    var available: Int64
    var total: Int64
    /// The space available as the file system reports it, which is cheap to read; `nil` when it
    /// was not read.
    var quickAvailable: Int64?
}

/// The memory pressure the system reports.
nonisolated enum ReadoutPressure: Int, CaseIterable, Comparable, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4

    /// The level of a memory pressure event mask (`DispatchSource.MemoryPressureEvent`); the worst
    /// level in the mask when it has several, `nil` for none.
    init?(eventMask: UInt) {
        if eventMask & 4 != 0 {
            self = .critical
        } else if eventMask & 2 != 0 {
            self = .warning
        } else if eventMask & 1 != 0 {
            self = .normal
        } else {
            return nil
        }
    }

    /// The level the kernel reports (`kern.memorystatus_vm_pressure_level`).
    init?(kernelLevel: Int) {
        self.init(rawValue: kernelLevel)
    }

    static func < (first: ReadoutPressure, second: ReadoutPressure) -> Bool {
        first.rawValue < second.rawValue
    }
}

/// The thermal state of the Mac (`ProcessInfo.ThermalState`).
nonisolated enum ReadoutThermal: Int, CaseIterable, Comparable, Sendable {
    case nominal = 0
    case fair = 1
    case serious = 2
    case critical = 3

    /// The state from the raw value of `ProcessInfo.ThermalState`; `nil` for one that is unknown.
    init?(rawState: Int) {
        self.init(rawValue: rawState)
    }

    static func < (first: ReadoutThermal, second: ReadoutThermal) -> Bool {
        first.rawValue < second.rawValue
    }
}

/// The battery as one reading: what a power widget and a power tile show (MON-05).
nonisolated struct PowerReading: Equatable, Sendable {
    /// The charge, as the system counts it (it respects a charge limit).
    var percent: Int
    var state: BatteryState
    /// The time until the battery is empty; `nil` while it is not known.
    var timeToEmpty: Duration?
    /// The time until the battery is full; `nil` while it is not known.
    var timeToFull: Duration?
    /// The power of the adapter in watts; `nil` while it is not known.
    var adapterWatts: Int?
}

/// The checks of the power values: what the system cannot know is `nil`, never zero (D-11).
nonisolated enum PowerValues {
    /// The longest time that is believed (100 hours); the system answers 65 535 minutes for
    /// "calculating".
    static let maximumMinutes = 6_000
    /// The largest adapter that is believed, in watts.
    static let maximumWatts = 1_000

    /// The time of a minutes value from the power source; `nil` for a missing, negative, zero or
    /// impossible one (-1 means "calculating", 65 535 "unknown").
    static func duration(minutes: Int?) -> Duration? {
        guard let minutes, minutes > 0, minutes <= maximumMinutes else {
            return nil
        }
        return .seconds(minutes * 60)
    }

    /// The adapter's watts; `nil` for a missing one, for zero (an adapter cannot deliver none: the
    /// system gave no answer) and for an impossible one.
    static func watts(_ value: Int?) -> Int? {
        guard let value, value > 0, value <= maximumWatts else {
            return nil
        }
        return value
    }
}

/// The checks of the graphics load.
nonisolated enum GPUValues {
    /// The load in percent; `nil` for a missing one or one outside 0 to 100.
    static func percent(_ value: Int?) -> Int? {
        guard let value, (0...100).contains(value) else {
            return nil
        }
        return value
    }
}

/// What one pass of the sampler read: only the metrics in ``read`` are set (D-01).
nonisolated struct ReadoutSample: Equatable, Sendable {
    /// When the sample was taken.
    var at: ContinuousClock.Instant
    /// The metrics this sample read; the other fields are not from it.
    var read: Set<ReadoutMetric> = []
    var cpuTicks: CPUTicks?
    var cpuCoreTicks: [CPUTicks]?
    var memory: MemoryUse?
    var swap: SwapUsage?
    var memoryPressure: ReadoutPressure?
    var network: CounterSnapshot?
    var disk: CounterSnapshot?
    var diskSpace: DiskSpace?
    var power: PowerReading?
    var thermal: ReadoutThermal?
    var gpuPercent: Int?

    /// This sample with the metrics of a newer one on top: the newer one's time, and its value for
    /// every metric it read, a missing value included; the older fields it did not read are kept.
    func merging(_ newer: ReadoutSample) -> ReadoutSample {
        var merged = self
        merged.at = newer.at
        merged.read.formUnion(newer.read)
        for metric in newer.read {
            switch metric {
            case .cpu: merged.cpuTicks = newer.cpuTicks
            case .cpuCores: merged.cpuCoreTicks = newer.cpuCoreTicks
            case .memory: merged.memory = newer.memory
            case .swap: merged.swap = newer.swap
            case .memoryPressure: merged.memoryPressure = newer.memoryPressure
            case .network: merged.network = newer.network
            case .diskActivity: merged.disk = newer.disk
            case .diskSpace: merged.diskSpace = newer.diskSpace
            case .power: merged.power = newer.power
            case .thermal: merged.thermal = newer.thermal
            case .gpu: merged.gpuPercent = newer.gpuPercent
            }
        }
        return merged
    }
}

/// The earlier readings of one consumer, from which the rates and loads of the next sample are
/// made (the first sample is only the baseline).
nonisolated struct ReadoutBaseline: Equatable, Sendable {
    private var cpu: CPUTicks?
    private var cores: [CPUTicks]?
    private var network = RateBaseline()
    private var disk = RateBaseline()

    /// The load of all processors since the last call; `nil` for the first call, after a failed
    /// read and when a counter went backwards.
    mutating func cpuLoad(_ current: CPUTicks?) -> Double? {
        defer {
            cpu = current
        }
        guard let current, let previous = cpu else {
            return nil
        }
        return WidgetReadings.cpuLoad(from: previous, to: current)
    }

    /// Stores the per-core ticks and gives the pair of the last two lists once an earlier one
    /// exists; `nil` for the first call and after a failed read.
    mutating func coreTicks(_ current: [CPUTicks]?) -> (previous: [CPUTicks], current: [CPUTicks])? {
        defer {
            cores = current
        }
        guard let current, let previous = cores else {
            return nil
        }
        return (previous, current)
    }

    /// The bytes per second received and sent since the last call.
    mutating func networkRates(_ snapshot: CounterSnapshot?) -> ReadoutRates? {
        network.rates(snapshot)
    }

    /// The bytes per second read and written since the last call.
    mutating func diskRates(_ snapshot: CounterSnapshot?) -> ReadoutRates? {
        disk.rates(snapshot)
    }

    /// Drops every baseline, so the next reading is a baseline again.
    mutating func reset() {
        self = ReadoutBaseline()
    }
}
