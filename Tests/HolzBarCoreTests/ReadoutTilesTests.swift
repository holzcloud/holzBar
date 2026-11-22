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
}
