import Testing
@testable import HolzBarCore

@Suite("AccessoryLowBatteryGate")
struct AccessoryLowBatteryGateTests {
    @Test("A first reading at or below the threshold alerts once")
    func firstReadingAlerts() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 15], threshold: 20) == ["a"])
        #expect(gate.update(levels: ["a": 15], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 10], threshold: 20).isEmpty)
    }

    @Test("A level above the threshold does not alert")
    func highLevelDoesNotAlert() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 21], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 100], threshold: 20).isEmpty)
    }

    @Test("A level exactly at the threshold alerts")
    func exactlyAtTheThresholdAlerts() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 20], threshold: 20) == ["a"])
    }

    @Test("A level more than five points above the threshold re-arms it and the next descent alerts")
    func risingAboveTheMarginReArms() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 18], threshold: 20) == ["a"])
        #expect(gate.update(levels: ["a": 26], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 19], threshold: 20) == ["a"])
    }

    @Test("A level up to five points above the threshold does not re-arm it")
    func risingWithinTheMarginDoesNotReArm() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 18], threshold: 20) == ["a"])
        #expect(gate.update(levels: ["a": 25], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 19], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 22], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 20], threshold: 20).isEmpty)
    }

    @Test("An id missing from a reading is forgotten and alerts again when it returns low")
    func leavingTheListForgets() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 10], threshold: 20) == ["a"])
        #expect(gate.update(levels: [:], threshold: 20).isEmpty)
        #expect(gate.update(levels: ["a": 10], threshold: 20) == ["a"])
    }

    @Test("Two ids are independent and the result is sorted")
    func idsAreIndependent() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["b": 5, "a": 5, "c": 80], threshold: 20) == ["a", "b"])
        #expect(gate.update(levels: ["b": 5, "a": 30, "c": 10], threshold: 20) == ["c"])
        #expect(gate.update(levels: ["b": 5, "a": 10, "c": 10], threshold: 20) == ["a"])
    }

    @Test("Lowering the threshold below a fired level changes nothing until the level rises")
    func loweringTheThreshold() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 18], threshold: 20) == ["a"])
        #expect(gate.update(levels: ["a": 18], threshold: 15).isEmpty)
        #expect(gate.update(levels: ["a": 14], threshold: 15).isEmpty)
        #expect(gate.update(levels: ["a": 20], threshold: 15).isEmpty)
        #expect(gate.update(levels: ["a": 14], threshold: 15).isEmpty)
        #expect(gate.update(levels: ["a": 21], threshold: 15).isEmpty)
        #expect(gate.update(levels: ["a": 14], threshold: 15) == ["a"])
    }

    @Test("Reset forgets everything")
    func resetForgets() {
        var gate = AccessoryLowBatteryGate()
        #expect(gate.update(levels: ["a": 10], threshold: 20) == ["a"])
        gate.reset()
        #expect(gate.update(levels: ["a": 10], threshold: 20) == ["a"])
    }

    @Test("The re-arm margin is five points")
    func margin() {
        #expect(AccessoryLowBatteryGate.hysteresis == 5)
    }
}
