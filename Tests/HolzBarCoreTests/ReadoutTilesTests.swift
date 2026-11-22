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
        #expect(ReadoutTiles.contents(input, stored: ["memory"]).isEmpty)
        #expect(ReadoutTiles.contents(input, stored: []).isEmpty)
        #expect(ReadoutTiles.contents(input, stored: ["cpu"]).map(\.kind) == [.cpu])
    }
}

