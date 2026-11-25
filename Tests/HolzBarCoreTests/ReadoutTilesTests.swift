import Foundation
import Testing
@testable import HolzBarCore

@Suite("ReadoutTiles")
struct ReadoutTilesTests {
    @Test("The tile kinds keep their stored raw values and the order of the hub (D-04)")
    func kindsKeepTheirRawValues() {
        #expect(ReadoutTileKind.allCases.map(\.rawValue) == ["cpu", "gpu", "memory", "network", "disk", "battery"])
        #expect(ReadoutTileChoice.thermalID == "thermal")
        #expect(ReadoutTileChoice.knownIDs == ["cpu", "gpu", "memory", "network", "disk", "battery", "thermal"])
    }

    @Test("A stored list keeps known ids once, in the order of the known ids, and at most 16 are checked")
    func sanitizedKeepsKnownIDsOnce() {
        #expect(ReadoutTileChoice.sanitized(["cpu", "bogus", "cpu", "thermal", "battery"]) == ["cpu", "battery", "thermal"])
        #expect(ReadoutTileChoice.sanitized([]).isEmpty)
        #expect(ReadoutTileChoice.sanitized(["Cpu", "", " cpu"]).isEmpty)
        // The seventeenth entry is never looked at: only the first 16 are checked.
        let padded = Array(repeating: "bogus", count: 16) + ["cpu"]
        #expect(ReadoutTileChoice.sanitized(padded).isEmpty)
        let late = Array(repeating: "bogus", count: 15) + ["cpu", "memory"]
        #expect(ReadoutTileChoice.sanitized(late) == ["cpu"])
    }

    @Test("With nothing stored every tile is on; a stored list is an allow-list")
    func nothingStoredMeansAllOn() {
        for id in ReadoutTileChoice.knownIDs {
            #expect(ReadoutTileChoice.isOn(id, stored: nil))
        }
        #expect(ReadoutTileChoice.isOn("memory", stored: nil))
        #expect(!ReadoutTileChoice.isOn("memory", stored: ["cpu"]))
        #expect(ReadoutTileChoice.isOn("cpu", stored: ["cpu"]))
        #expect(ReadoutTileChoice.isOn("thermal", stored: nil))
        #expect(!ReadoutTileChoice.isOn("thermal", stored: ["cpu"]))
        #expect(!ReadoutTileChoice.isOn("cpu", stored: []))
    }

    @Test("Switching a tile off stores every known id but that one; switching all on again stores nothing")
    func togglingTiles() {
        let off = ReadoutTileChoice.setting("memory", on: false, stored: nil)
        #expect(off == ["cpu", "gpu", "network", "disk", "battery", "thermal"])
        let offTwice = ReadoutTileChoice.setting("cpu", on: false, stored: off)
        #expect(offTwice == ["gpu", "network", "disk", "battery", "thermal"])
        let backOn = ReadoutTileChoice.setting("cpu", on: true, stored: offTwice)
        #expect(backOn == ["cpu", "gpu", "network", "disk", "battery", "thermal"])
        #expect(ReadoutTileChoice.setting("memory", on: true, stored: backOn) == nil)
        #expect(ReadoutTileChoice.setting("memory", on: true, stored: nil) == nil)
        #expect(ReadoutTileChoice.setting("bogus", on: true, stored: ["cpu"]) == ["cpu"])
    }

    @Test("The refresh snaps to 2, 5, 10 or 30 seconds, 2 by default")
    func refreshSnaps() {
        #expect(ReadoutTileRefresh.choices == [2, 5, 10, 30])
        #expect(ReadoutTileRefresh.defaultSeconds == 2)
        #expect(ReadoutTileRefresh.snapped(nil) == 2)
        #expect(ReadoutTileRefresh.snapped(7) == 5)
        for seconds in ReadoutTileRefresh.choices {
            #expect(ReadoutTileRefresh.snapped(seconds) == seconds)
        }
        #expect(ReadoutTileRefresh.snapped(1) == 2)
        #expect(ReadoutTileRefresh.snapped(0) == 2)
        #expect(ReadoutTileRefresh.snapped(-5) == 2)
        #expect(ReadoutTileRefresh.snapped(99) == 30)
        #expect(ReadoutTileRefresh.snapped(Int.max) == 30)
    }

    // MARK: Tile contents (the CPU tile)

    @Test("The CPU tile shows the total load as a whole percent, the load as its ring and the level of the load")
    func cpuTileShowsTheLoad() throws {
        let input = ReadoutTileInput(cpuLoad: 0.234, thermal: .nominal)
        let content = try #require(ReadoutTiles.contents(input, stored: nil).first)
        #expect(content.kind == .cpu)
        #expect(content.value == .percent(23))
        #expect(content.fraction == 0.234)
        #expect(content.level == .normal)
        #expect(content.detail == nil)
        let busy = try #require(ReadoutTiles.contents(ReadoutTileInput(cpuLoad: 0.9), stored: nil).first)
        #expect(busy.level == .critical)
    }

    @Test("The thermal line is the CPU detail from Fair on; Nominal is only spoken; a switched-off line is silent")
    func cpuTileCarriesTheThermalState() throws {
        let serious = try #require(
            ReadoutTiles.contents(ReadoutTileInput(cpuLoad: 0.2, thermal: .serious), stored: nil).first
        )
        #expect(serious.detail == .thermal(.serious))
        #expect(serious.spokenThermal == .serious)
        let nominal = try #require(
            ReadoutTiles.contents(ReadoutTileInput(cpuLoad: 0.2, thermal: .nominal), stored: nil).first
        )
        #expect(nominal.detail == nil)
        #expect(nominal.spokenThermal == .nominal)
        var off = ReadoutTileInput(cpuLoad: 0.2, thermal: .critical)
        off.showsThermalLine = false
        let silent = try #require(ReadoutTiles.contents(off, stored: nil).first)
        #expect(silent.detail == nil)
        #expect(silent.spokenThermal == nil)
    }

    @Test("Clusters come after the thermal line and only when the chip reports them")
    func cpuTileShowsClustersWhenThereIsNoThermalLine() throws {
        let clusters = [
            ClusterLoad(level: ClusterLevel(index: 0, name: "Performance", logicalCPUs: 4), label: .performance, load: 0.42),
            ClusterLoad(level: ClusterLevel(index: 1, name: "Efficiency", logicalCPUs: 4), label: .efficiency, load: 0.12),
        ]
        var input = ReadoutTileInput(cpuLoad: 0.3, thermal: .nominal)
        input.clusters = clusters
        let plain = try #require(ReadoutTiles.contents(input, stored: nil).first)
        #expect(plain.detail == .clusters(clusters))
        input.thermal = .fair
        let hot = try #require(ReadoutTiles.contents(input, stored: nil).first)
        #expect(hot.detail == .thermal(.fair))
        // One cluster is the total, not a split: no cluster line.
        input.thermal = .nominal
        input.clusters = Array(clusters.prefix(1))
        let single = try #require(ReadoutTiles.contents(input, stored: nil).first)
        #expect(single.detail == nil)
        input.clusters = []
        let none = try #require(ReadoutTiles.contents(input, stored: nil).first)
        #expect(none.detail == nil)
    }

    @Test("A missing load shows the en dash state: no fraction, no level, no detail (R4)")
    func missingLoadIsUnavailable() throws {
        var input = ReadoutTileInput(cpuLoad: nil, thermal: .serious)
        input.clusters = []
        let content = try #require(ReadoutTiles.contents(input, stored: nil).first)
        #expect(content.value == .unavailable)
        #expect(content.fraction == nil)
        #expect(content.level == nil)
        #expect(content.detail == nil)
    }

    @Test("A switched-off tile is absent")
    func switchedOffTileIsAbsent() {
        let input = ReadoutTileInput(cpuLoad: 0.5)
        #expect(ReadoutTiles.contents(input, stored: ["memory"]).map(\.kind) == [.memory])
        #expect(ReadoutTiles.contents(input, stored: []).isEmpty)
        #expect(ReadoutTiles.contents(input, stored: ["cpu"]).map(\.kind) == [.cpu])
    }

    // MARK: Memory, network, disk, battery and GPU

    private static let gibibyte: UInt64 = 1_073_741_824
    private static let gigabyte: Int64 = 1_000_000_000

    private func content(_ kind: ReadoutTileKind, _ input: ReadoutTileInput) -> ReadoutTileContent? {
        ReadoutTiles.contents(input, stored: nil).first { $0.kind == kind }
    }

    @Test("Memory shows the used share, takes its colour from the pressure and names swap, pressure or the capacity")
    func memoryTile() throws {
        var input = ReadoutTileInput()
        input.memory = MemoryUse(used: 11 * Self.gibibyte, total: 16 * Self.gibibyte)
        input.pressure = .normal
        var memory = try #require(content(.memory, input))
        #expect(memory.value == .percent(69))
        #expect(try #require(memory.fraction) > 0.68)
        #expect(try #require(memory.fraction) < 0.69)
        #expect(memory.level == .normal)
        #expect(memory.detail == .capacity(Int64(16 * Self.gibibyte)))
        input.swap = SwapUsage(total: 4 * Self.gibibyte, used: 1_200_000_000)
        memory = try #require(content(.memory, input))
        #expect(memory.detail == .swap(1_200_000_000))
        input.swap = SwapUsage(total: 4 * Self.gibibyte, used: 0)
        memory = try #require(content(.memory, input))
        #expect(memory.detail == .capacity(Int64(16 * Self.gibibyte)))
        input.pressure = .warning
        input.swap = SwapUsage(total: 4 * Self.gibibyte, used: 1_200_000_000)
        memory = try #require(content(.memory, input))
        #expect(memory.level == .elevated)
        #expect(memory.detail == .pressure(.warning))
        input.pressure = .critical
        memory = try #require(content(.memory, input))
        #expect(memory.level == .critical)
        #expect(memory.detail == .pressure(.critical))
    }

    @Test("Memory without a reading or with an impossible one shows the en dash")
    func memoryTileUnavailable() throws {
        #expect(try #require(content(.memory, ReadoutTileInput())).value == .unavailable)
        var input = ReadoutTileInput()
        input.memory = MemoryUse(used: 5, total: 0)
        let empty = try #require(content(.memory, input))
        #expect(empty.value == .unavailable)
        #expect(empty.fraction == nil)
        #expect(empty.level == nil)
        #expect(empty.detail == nil)
        input.memory = MemoryUse(used: 20 * Self.gibibyte, total: 16 * Self.gibibyte)
        #expect(try #require(content(.memory, input)).value == .unavailable)
    }

    @Test("Network shows the download rate with the upload as its line and has a track only")
    func networkTile() throws {
        var input = ReadoutTileInput()
        input.networkRates = ReadoutRates(first: 1_200_000, second: 85_000)
        let network = try #require(content(.network, input))
        #expect(network.value == .rate(1_200_000))
        #expect(network.fraction == nil)
        #expect(network.level == nil)
        #expect(network.detail == .upload(85_000))
        input.networkRates = nil
        let none = try #require(content(.network, input))
        #expect(none.value == .unavailable)
        #expect(none.detail == nil)
        input.networkRates = ReadoutRates(first: -1, second: 5)
        #expect(try #require(content(.network, input)).value == .unavailable)
    }

    @Test("Disk shows the free space, the used share as its ring and the capacity")
    func diskTile() throws {
        var input = ReadoutTileInput()
        input.diskSpace = DiskSpace(available: 212 * Self.gigabyte, total: 994 * Self.gigabyte)
        let disk = try #require(content(.disk, input))
        #expect(disk.value == .bytes(212 * Self.gigabyte))
        #expect(try #require(disk.fraction) > 0.78)
        #expect(try #require(disk.fraction) < 0.80)
        #expect(disk.level == .elevated)
        #expect(disk.detail == .capacity(994 * Self.gigabyte))
        input.diskSpace = DiskSpace(available: 5, total: 0)
        #expect(try #require(content(.disk, input)).value == .unavailable)
        input.diskSpace = nil
        #expect(try #require(content(.disk, input)).value == .unavailable)
    }

    @Test("Battery takes its level from the charge left and its line from the power state")
    func batteryTile() throws {
        var input = ReadoutTileInput()
        input.hasBattery = true
        input.power = PowerReading(percent: 80, state: .onBattery, timeToEmpty: .seconds(7_800))
        var battery = try #require(content(.battery, input))
        #expect(battery.value == .percent(80))
        #expect(battery.fraction == 0.8)
        #expect(battery.level == .normal)
        #expect(battery.detail == .timeLeft(.seconds(7_800)))
        input.power = PowerReading(percent: 12, state: .onBattery)
        battery = try #require(content(.battery, input))
        #expect(battery.level == .critical)
        #expect(battery.detail == .onBattery)
        input.power = PowerReading(percent: 25, state: .charging, timeToFull: .seconds(2_700))
        battery = try #require(content(.battery, input))
        #expect(battery.level == .elevated)
        #expect(battery.detail == .timeToFull(.seconds(2_700)))
        input.power = PowerReading(percent: 50, state: .charging)
        #expect(try #require(content(.battery, input)).detail == .charging)
        input.power = PowerReading(percent: 90, state: .onAdapter, adapterWatts: 96)
        #expect(try #require(content(.battery, input)).detail == .adapterWatts(96))
        input.power = PowerReading(percent: 100, state: .charged)
        #expect(try #require(content(.battery, input)).detail == .charged)
        input.power = PowerReading(percent: 90, state: .onAdapter)
        #expect(try #require(content(.battery, input)).detail == .onAdapter)
    }

    @Test("A Mac without a battery has no battery tile; a battery without a reading shows the en dash")
    func batteryTileAbsentOrUnavailable() throws {
        var input = ReadoutTileInput()
        input.power = PowerReading(percent: 80, state: .onBattery)
        #expect(content(.battery, input) == nil)
        input.hasBattery = true
        input.power = nil
        let missing = try #require(content(.battery, input))
        #expect(missing.value == .unavailable)
        #expect(missing.fraction == nil)
        #expect(missing.detail == nil)
        input.power = PowerReading(percent: 140, state: .onBattery)
        #expect(try #require(content(.battery, input)).value == .unavailable)
    }

    @Test("GPU is absent while its switch is off, shows the load, and says so when the part switched itself off")
    func gpuTile() throws {
        var input = ReadoutTileInput()
        input.gpuPercent = 23
        #expect(content(.gpu, input) == nil)
        input.gpuEnabled = true
        let gpu = try #require(content(.gpu, input))
        #expect(gpu.value == .percent(23))
        #expect(gpu.fraction == 0.23)
        #expect(gpu.level == .normal)
        input.gpuUnavailable = true
        let off = try #require(content(.gpu, input))
        #expect(off.value == .unavailable)
        #expect(off.fraction == nil)
        #expect(off.detail == .notAvailable)
        input.gpuUnavailable = false
        input.gpuPercent = nil
        #expect(try #require(content(.gpu, input)).value == .unavailable)
    }

    @Test("The tiles come in the order CPU, GPU, Memory, Network, Disk, Battery, and only those that are on")
    func tileOrder() {
        var input = ReadoutTileInput(cpuLoad: 0.1)
        input.gpuEnabled = true
        input.gpuPercent = 5
        input.memory = MemoryUse(used: 1, total: 2)
        input.networkRates = ReadoutRates(first: 1, second: 1)
        input.diskSpace = DiskSpace(available: 1, total: 2)
        input.hasBattery = true
        input.power = PowerReading(percent: 50, state: .onBattery)
        #expect(ReadoutTiles.contents(input, stored: nil).map(\.kind) == [.cpu, .gpu, .memory, .network, .disk, .battery])
        #expect(ReadoutTiles.contents(input, stored: ["battery", "cpu", "disk"]).map(\.kind) == [.cpu, .disk, .battery])
    }
}

