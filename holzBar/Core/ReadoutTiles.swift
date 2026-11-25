//
//  ReadoutTiles.swift
//  holzBar
//

import Foundation

/// The readout tiles of the System readouts module, in the order the hub shows them (D-04). The
/// raw values are stored in the settings (`ReadoutTiles`): new cases are appended and the
/// existing ones never change.
nonisolated enum ReadoutTileKind: String, CaseIterable, Sendable {
    case cpu
    case gpu
    case memory
    case network
    case disk
    case battery
}

/// Which tiles the user switched on, as one stored allow-list (51 P-04).
///
/// An absent list means every tile is on, so a tile a later version adds is on for everyone who
/// never chose. The list also holds ``thermalID``, the thermal state line under the CPU tile. A
/// value from the defaults or from an imported settings file can be anything, so every stored
/// list goes through ``sanitized(_:)``.
nonisolated enum ReadoutTileChoice {
    /// The id of the thermal state line under the CPU tile (D-04, D-17).
    static let thermalID = "thermal"

    /// Every id a stored list may hold, in the order the settings show them: the tiles, then the
    /// thermal state line.
    static let knownIDs: [String] = ReadoutTileKind.allCases.map(\.rawValue) + [thermalID]

    /// How many entries of a stored list are looked at.
    static let maximumChecked = 16

    /// The known ids of a stored list, each once, in the order of ``knownIDs``. Only the first
    /// ``maximumChecked`` entries are looked at. An empty list stays empty: every tile is off.
    static func sanitized(_ ids: [String]) -> [String] {
        let checked = Set(ids.prefix(maximumChecked))
        return knownIDs.filter { checked.contains($0) }
    }

    /// Whether the tile or the thermal line with this id is on. With nothing stored, every one is.
    static func isOn(_ id: String, stored: [String]?) -> Bool {
        guard let stored else {
            return true
        }
        return stored.contains(id)
    }

    /// The list to store after switching one id on or off: with nothing stored, a switch-off
    /// stores every known id but that one. The result is `nil`, storing nothing, when every id is
    /// on again, so a tile added later stays on for this user. An unknown id changes nothing.
    static func setting(_ id: String, on: Bool, stored: [String]?) -> [String]? {
        guard knownIDs.contains(id) else {
            return stored
        }
        var chosen = Set(stored ?? knownIDs)
        if on {
            chosen.insert(id)
        } else {
            chosen.remove(id)
        }
        let list = knownIDs.filter { chosen.contains($0) }
        return list.count == knownIDs.count ? nil : list
    }
}

/// How often the tiles read CPU, GPU, memory and network while the hub is open (D-19).
nonisolated enum ReadoutTileRefresh {
    /// The seconds the settings offer, ascending.
    static let choices = [2, 5, 10, 30]

    /// The seconds used when nothing is stored.
    static let defaultSeconds = 2

    /// The offered choice nearest to a stored value; the shorter one on a tie, ``defaultSeconds``
    /// for none. A value from the defaults can be anything.
    static func snapped(_ seconds: Int?) -> Int {
        guard let seconds else {
            return defaultSeconds
        }
        // Kept in a small range first, so the distances cannot overflow.
        let value = min(max(seconds, 0), 1_000)
        return choices.min { abs($0 - value) < abs($1 - value) } ?? defaultSeconds
    }
}

// MARK: Tile contents

/// What the tiles of the System readouts show, as plain values (D-04, D-11): one input of the
/// latest readings, one list of contents out. The app turns a content into words, units and
/// colours; the rules here decide which tile exists, what its value, ring and detail are, and
/// when a value is missing.
nonisolated struct ReadoutTileInput: Equatable, Sendable {
    /// The load of all processors from 0 to 1, or `nil` while it is not known.
    var cpuLoad: Double?
    /// The thermal state, or `nil` while it is not known.
    var thermal: ReadoutThermal?
    /// Whether the CPU tile carries the thermal state (the "Thermal state" switch).
    var showsThermalLine = true
    /// The load of every cluster, when the chip reports two or more whose sums agree.
    var clusters: [ClusterLoad] = []
    /// Whether the GPU tile exists: the Read GPU load switch is on.
    var gpuEnabled = false
    /// The load of the graphics processor in percent, or `nil` while it is not known.
    var gpuPercent: Int?
    /// Whether the GPU part switched itself off for this session.
    var gpuUnavailable = false
    var memory: MemoryUse?
    var swap: SwapUsage?
    var pressure: ReadoutPressure?
    /// The bytes per second received (first) and sent (second), or `nil` while they are not known.
    var networkRates: ReadoutRates?
    var diskSpace: DiskSpace?
    /// Whether this Mac has a battery, which the first power reading tells.
    var hasBattery = false
    var power: PowerReading?
}

/// The value of a tile, before it is written in the user's language.
nonisolated enum ReadoutTileValue: Equatable, Sendable {
    /// A whole percent from 0 to 100.
    case percent(Int)
    /// A rate in bytes per second.
    case rate(Double)
    /// An amount in bytes.
    case bytes(Int64)
    /// A missing, stuck or impossible value: the tile shows an en dash (R4).
    case unavailable
}

/// The one quiet line under a tile's value, before it is written in words.
nonisolated enum ReadoutTileDetail: Equatable, Sendable {
    /// The thermal state: Fair, Serious or Critical.
    case thermal(ReadoutThermal)
    /// The load of every cluster.
    case clusters([ClusterLoad])
    /// The memory pressure while it is not normal.
    case pressure(ReadoutPressure)
    /// The swap in use, in bytes.
    case swap(Int64)
    /// The capacity behind the value, in bytes.
    case capacity(Int64)
    /// The upload rate in bytes per second.
    case upload(Double)
    /// The time until the battery is empty.
    case timeLeft(Duration)
    /// The time until the battery is full.
    case timeToFull(Duration)
    case onBattery
    case charging
    case charged
    case onAdapter
    /// The adapter's watts.
    case adapterWatts(Int)
    /// The part behind the tile switched itself off for this session.
    case notAvailable
}

/// One tile: its value, its ring and its detail.
nonisolated struct ReadoutTileContent: Equatable, Sendable {
    var kind: ReadoutTileKind
    var value: ReadoutTileValue
    /// The ring's fill from 0 to 1, or `nil` for a track without an arc.
    var fraction: Double?
    /// The ring's colour, or `nil` where the ring has no arc.
    var level: GaugeLevel?
    var detail: ReadoutTileDetail?
    /// The thermal state the tile's spoken value and tooltip carry while the thermal switch is on,
    /// Nominal included; `nil` for a tile without one.
    var spokenThermal: ReadoutThermal?
}

/// The rules of the tiles (D-04, D-05, D-11).
nonisolated enum ReadoutTiles {
    /// The contents of the tiles that are on, in the order of the hub: CPU, GPU, Memory, Network,
    /// Disk, Battery. A tile that is off, or that this Mac has none of, is not in the list.
    static func contents(_ input: ReadoutTileInput, stored: [String]?) -> [ReadoutTileContent] {
        ReadoutTileKind.allCases.compactMap { kind in
            guard ReadoutTileChoice.isOn(kind.rawValue, stored: stored) else {
                return nil
            }
            return content(of: kind, input)
        }
    }

    private static func content(of kind: ReadoutTileKind, _ input: ReadoutTileInput) -> ReadoutTileContent? {
        switch kind {
        case .cpu: cpu(input)
        case .gpu: gpu(input)
        case .memory: memory(input)
        case .network: network(input)
        case .disk: disk(input)
        case .battery: battery(input)
        }
    }

    /// A tile whose value is missing, stuck or impossible: an en dash, no arc, no detail (R4).
    private static func unavailable(_ kind: ReadoutTileKind, detail: ReadoutTileDetail? = nil) -> ReadoutTileContent {
        ReadoutTileContent(kind: kind, value: .unavailable, detail: detail)
    }

    // MARK: CPU

    private static func cpu(_ input: ReadoutTileInput) -> ReadoutTileContent {
        let spoken = input.showsThermalLine ? input.thermal : nil
        guard let load = input.cpuLoad, load.isFinite, (0...1).contains(load) else {
            return ReadoutTileContent(kind: .cpu, value: .unavailable, spokenThermal: spoken)
        }
        var detail: ReadoutTileDetail?
        if let spoken, spoken >= .fair {
            detail = .thermal(spoken)
        } else if input.clusters.count >= 2 {
            detail = .clusters(input.clusters)
        }
        return ReadoutTileContent(
            kind: .cpu,
            value: .percent(percent(load)),
            fraction: load,
            level: GaugeLevel.level(for: load),
            detail: detail,
            spokenThermal: spoken
        )
    }

    // MARK: GPU

    private static func gpu(_ input: ReadoutTileInput) -> ReadoutTileContent? {
        guard input.gpuEnabled else {
            return nil
        }
        if input.gpuUnavailable {
            return unavailable(.gpu, detail: .notAvailable)
        }
        guard let percent = GPUValues.percent(input.gpuPercent) else {
            return unavailable(.gpu)
        }
        let fraction = Double(percent) / 100
        return ReadoutTileContent(
            kind: .gpu,
            value: .percent(percent),
            fraction: fraction,
            level: GaugeLevel.level(for: fraction)
        )
    }

    // MARK: Memory

    /// The used share is the ring; its colour is the memory pressure, not the share (R3). The line
    /// names the pressure while it is not normal, else the swap in use, else the capacity.
    private static func memory(_ input: ReadoutTileInput) -> ReadoutTileContent {
        guard let memory = input.memory, memory.total > 0, memory.used <= memory.total else {
            return unavailable(.memory)
        }
        let fraction = Double(memory.used) / Double(memory.total)
        let pressure = input.pressure ?? .normal
        let level: GaugeLevel = switch pressure {
        case .normal: .normal
        case .warning: .elevated
        case .critical: .critical
        }
        let detail: ReadoutTileDetail
        if pressure != .normal {
            detail = .pressure(pressure)
        } else if let swap = input.swap, swap.used > 0 {
            detail = .swap(Int64(clamping: swap.used))
        } else {
            detail = .capacity(Int64(clamping: memory.total))
        }
        return ReadoutTileContent(
            kind: .memory,
            value: .percent(percent(fraction)),
            fraction: fraction,
            level: level,
            detail: detail
        )
    }

    // MARK: Network

    /// A rate has no limit, so the ring is a track only.
    private static func network(_ input: ReadoutTileInput) -> ReadoutTileContent {
        guard let rates = input.networkRates, rates.first.isFinite, rates.second.isFinite,
              rates.first >= 0, rates.second >= 0 else {
            return unavailable(.network)
        }
        return ReadoutTileContent(kind: .network, value: .rate(rates.first), detail: .upload(rates.second))
    }

    // MARK: Disk

    /// The free space is the value (D-05); the used share is the ring.
    private static func disk(_ input: ReadoutTileInput) -> ReadoutTileContent {
        guard let space = input.diskSpace, space.total > 0, space.available >= 0, space.available <= space.total else {
            return unavailable(.disk)
        }
        let used = 1 - Double(space.available) / Double(space.total)
        return ReadoutTileContent(
            kind: .disk,
            value: .bytes(space.available),
            fraction: used,
            level: GaugeLevel.level(for: used),
            detail: .capacity(space.total)
        )
    }

    // MARK: Battery

    /// The charge is the ring and its colour comes from what is left (R3). A Mac without a battery
    /// has no tile.
    private static func battery(_ input: ReadoutTileInput) -> ReadoutTileContent? {
        guard input.hasBattery else {
            return nil
        }
        guard let power = input.power, (0...100).contains(power.percent) else {
            return unavailable(.battery)
        }
        let fraction = Double(power.percent) / 100
        return ReadoutTileContent(
            kind: .battery,
            value: .percent(power.percent),
            fraction: fraction,
            level: GaugeLevel.level(forRemaining: fraction),
            detail: batteryDetail(power)
        )
    }

    private static func batteryDetail(_ power: PowerReading) -> ReadoutTileDetail {
        switch power.state {
        case .onBattery:
            return power.timeToEmpty.map(ReadoutTileDetail.timeLeft) ?? .onBattery
        case .charging:
            return power.timeToFull.map(ReadoutTileDetail.timeToFull) ?? .charging
        case .onAdapter:
            return power.adapterWatts.map(ReadoutTileDetail.adapterWatts) ?? .onAdapter
        case .charged:
            return power.adapterWatts.map(ReadoutTileDetail.adapterWatts) ?? .charged
        }
    }

    /// A share from 0 to 1 as a whole percent.
    static func percent(_ share: Double) -> Int {
        min(max(Int((share * 100).rounded()), 0), 100)
    }
}
