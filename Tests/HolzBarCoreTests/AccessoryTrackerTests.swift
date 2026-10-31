import Foundation
import Testing
@testable import HolzBarCore

@Suite("AccessoryTracker")
struct AccessoryTrackerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    private func device(_ name: String, _ last: String = "01") -> AccessoryDevice {
        guard let device = AccessoryDevice(
            address: "aa-bb-cc-dd-ee-\(last)", name: name, majorClass: 4, minorClass: 6
        ) else {
            fatalError("The test address is valid.")
        }
        return device
    }

    @Test("The first update is a baseline and returns no event")
    func baseline() {
        var tracker = AccessoryTracker()
        #expect(tracker.update(connected: [device("A"), device("B", "02")], now: at(0)).isEmpty)
        var empty = AccessoryTracker()
        #expect(empty.update(connected: [], now: at(0)).isEmpty)
    }

    @Test("One more device is one connected event, and one less is one disconnected event")
    func connectAndDisconnect() {
        var tracker = AccessoryTracker()
        let a = device("A")
        let b = device("B", "02")
        _ = tracker.update(connected: [a], now: at(0))
        #expect(tracker.update(connected: [a, b], now: at(20)) == [.connected(b)])
        #expect(tracker.update(connected: [a], now: at(40)) == [.disconnected(b)])
    }

    @Test("A disconnect carries the device as it was in the previous snapshot")
    func disconnectCarriesOldDevice() {
        var tracker = AccessoryTracker()
        let a = device("A")
        _ = tracker.update(connected: [a], now: at(0))
        let events = tracker.update(connected: [], now: at(20))
        #expect(events == [.disconnected(a)])
    }

    @Test("The same snapshot, a rename and a repeated device raise nothing")
    func noChange() {
        var tracker = AccessoryTracker()
        let a = device("A")
        _ = tracker.update(connected: [a], now: at(0))
        #expect(tracker.update(connected: [a], now: at(20)).isEmpty)
        #expect(tracker.update(connected: [device("Renamed")], now: at(40)).isEmpty)
        #expect(tracker.update(connected: [a, a, device("Other", "09")], now: at(60)).count == 1)
        var fresh = AccessoryTracker()
        _ = fresh.update(connected: [a], now: at(0))
        #expect(fresh.update(connected: [a, a, a], now: at(20)).isEmpty)
    }

    @Test("Disconnects come before connects, each ordered by name and then id")
    func ordering() {
        var tracker = AccessoryTracker()
        let old1 = device("Zed", "01")
        let old2 = device("Amy", "02")
        _ = tracker.update(connected: [old1, old2], now: at(0))
        let new1 = device("Same", "05")
        let new2 = device("Same", "04")
        let new3 = device("Bob", "03")
        let events = tracker.update(connected: [new1, new2, new3], now: at(20))
        #expect(events == [.disconnected(old2), .disconnected(old1), .connected(new3), .connected(new2), .connected(new1)])
    }

    @Test("A repeated event of one kind for one device inside ten seconds is dropped, at ten seconds it is kept")
    func quietPeriod() {
        var tracker = AccessoryTracker()
        let a = device("A")
        _ = tracker.update(connected: [], now: at(0))
        #expect(tracker.update(connected: [a], now: at(1)) == [.connected(a)])
        #expect(tracker.update(connected: [], now: at(2)) == [.disconnected(a)])
        // Back inside the quiet period of the connected event: dropped.
        #expect(tracker.update(connected: [a], now: at(10.9)).isEmpty)
        #expect(tracker.update(connected: [], now: at(11.5)).isEmpty)
        // Exactly ten seconds after the last reported connected event (at 1 s): kept.
        #expect(tracker.update(connected: [a], now: at(11)) == [.connected(a)])
    }

    @Test("Connected and disconnected events do not suppress each other")
    func kindsAreIndependent() {
        var tracker = AccessoryTracker()
        let a = device("A")
        _ = tracker.update(connected: [a], now: at(0))
        #expect(tracker.update(connected: [], now: at(1)) == [.disconnected(a)])
        #expect(tracker.update(connected: [a], now: at(2)) == [.connected(a)])
        #expect(tracker.update(connected: [], now: at(12)) == [.disconnected(a)])
    }

    @Test("A clock that goes back does not hide an event")
    func clockGoesBack() {
        var tracker = AccessoryTracker()
        let a = device("A")
        _ = tracker.update(connected: [], now: at(100))
        #expect(tracker.update(connected: [a], now: at(100)) == [.connected(a)])
        _ = tracker.update(connected: [], now: at(101))
        #expect(tracker.update(connected: [a], now: at(0)) == [.connected(a)])
    }

    @Test("Reset makes the next update a baseline again")
    func resetBaseline() {
        var tracker = AccessoryTracker()
        let a = device("A")
        _ = tracker.update(connected: [], now: at(0))
        #expect(tracker.update(connected: [a], now: at(20)) == [.connected(a)])
        tracker.reset()
        #expect(tracker.update(connected: [a], now: at(40)).isEmpty)
        #expect(tracker.update(connected: [], now: at(60)) == [.disconnected(a)])
    }
}
