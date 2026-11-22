import Testing
@testable import HolzBarCore

@Suite("ThresholdRule")
struct ThresholdRuleTests {
    @Test("The five signals come in the order of the alert rules and the settings")
    func signalOrder() {
        #expect(AlertSignal.allCases.map(\.rawValue) == ["cpu", "memoryPressure", "thermal", "freeDisk", "macBattery"])
    }

    @Test("A rule nobody stored starts with the defaults of the decisions")
    func defaults() {
        let cpu = ThresholdRule.defaultRule(for: .cpu)
        #expect(cpu == ThresholdRule(signal: .cpu, isOn: true, limit: 90, hold: .fiveMinutes))
        let memory = ThresholdRule.defaultRule(for: .memoryPressure)
        #expect(memory == ThresholdRule(signal: .memoryPressure, isOn: false, limit: 1, hold: .oneMinute))
        let thermal = ThresholdRule.defaultRule(for: .thermal)
        #expect(thermal == ThresholdRule(signal: .thermal, isOn: true, limit: 2, hold: .immediately))
        let disk = ThresholdRule.defaultRule(for: .freeDisk)
        #expect(disk == ThresholdRule(signal: .freeDisk, isOn: true, limit: 10, hold: .oneMinute))
        let battery = ThresholdRule.defaultRule(for: .macBattery)
        #expect(battery == ThresholdRule(signal: .macBattery, isOn: true, limit: 20, hold: .immediately))
    }

    @Test("Every default limit is already valid")
    func defaultsAreValid() {
        for signal in AlertSignal.allCases {
            let rule = ThresholdRule.defaultRule(for: signal)
            #expect(ThresholdRule.validatedLimit(rule.limit, for: signal) == rule.limit)
        }
    }

    @Test("The durations are the presets, in order")
    func holdPresets() {
        #expect(AlertHold.allCases.map(\.rawValue) == [0, 10, 30, 60, 300, 900])
        #expect(AlertHold.fiveMinutes.duration == .seconds(300))
        #expect(AlertHold.immediately.duration == .zero)
    }

    @Test("Any number of seconds snaps to the nearest preset, a tie to the shorter")
    func holdSnapping() {
        #expect(AlertHold.snapped(seconds: 0) == .immediately)
        #expect(AlertHold.snapped(seconds: 20) == .tenSeconds)
        #expect(AlertHold.snapped(seconds: 45) == .thirtySeconds)
        #expect(AlertHold.snapped(seconds: 100_000) == .fifteenMinutes)
        #expect(AlertHold.snapped(seconds: -5) == .immediately)
        #expect(AlertHold.snapped(seconds: Int.min) == .immediately)
        #expect(AlertHold.snapped(seconds: Int.max) == .fifteenMinutes)
        #expect(AlertHold.snapped(seconds: 300) == .fiveMinutes)
        #expect(AlertHold.snapped(seconds: 200) == .fiveMinutes)
    }

    @Test("A CPU limit is clamped to 50 to 95 and snapped to steps of 5")
    func cpuLimits() {
        #expect(ThresholdRule.validatedLimit(120, for: .cpu) == 95)
        #expect(ThresholdRule.validatedLimit(47, for: .cpu) == 50)
        #expect(ThresholdRule.validatedLimit(92, for: .cpu) == 90)
        #expect(ThresholdRule.validatedLimit(93, for: .cpu) == 95)
        #expect(ThresholdRule.validatedLimit(-1, for: .cpu) == 50)
        #expect(ThresholdRule.validatedLimit(Int.max, for: .cpu) == 95)
        #expect(ThresholdRule.validatedLimit(Int.min, for: .cpu) == 50)
    }

    @Test("A battery limit is clamped to 5 to 50 and snapped to steps of 5")
    func batteryLimits() {
        #expect(ThresholdRule.validatedLimit(3, for: .macBattery) == 5)
        #expect(ThresholdRule.validatedLimit(52, for: .macBattery) == 50)
        #expect(ThresholdRule.validatedLimit(22, for: .macBattery) == 20)
        #expect(ThresholdRule.validatedLimit(23, for: .macBattery) == 25)
    }

    @Test("A disk limit snaps to the nearest preset, a tie to the smaller")
    func diskLimits() {
        #expect(ThresholdRule.validatedLimit(7, for: .freeDisk) == 5)
        #expect(ThresholdRule.validatedLimit(15, for: .freeDisk) == 10)
        #expect(ThresholdRule.validatedLimit(1_000, for: .freeDisk) == 200)
        #expect(ThresholdRule.validatedLimit(-3, for: .freeDisk) == 5)
        #expect(ThresholdRule.validatedLimit(50, for: .freeDisk) == 50)
        #expect(ThresholdRule.validatedLimit(Int.max, for: .freeDisk) == 200)
    }

    @Test("A memory level is 1 for Warning or 2 for Critical, anything else falls back to Warning")
    func memoryLevels() {
        #expect(ThresholdRule.validatedLimit(1, for: .memoryPressure) == 1)
        #expect(ThresholdRule.validatedLimit(2, for: .memoryPressure) == 2)
        #expect(ThresholdRule.validatedLimit(0, for: .memoryPressure) == 1)
        #expect(ThresholdRule.validatedLimit(3, for: .memoryPressure) == 1)
        #expect(ThresholdRule.validatedLimit(4, for: .memoryPressure) == 1)
        #expect(ThresholdRule.memoryLevels == 1...2)
    }

    @Test("A thermal level is 1, 2 or 3, anything else falls back to Serious")
    func thermalLevels() {
        #expect(ThresholdRule.validatedLimit(1, for: .thermal) == 1)
        #expect(ThresholdRule.validatedLimit(2, for: .thermal) == 2)
        #expect(ThresholdRule.validatedLimit(3, for: .thermal) == 3)
        #expect(ThresholdRule.validatedLimit(0, for: .thermal) == 2)
        #expect(ThresholdRule.validatedLimit(9, for: .thermal) == 2)
        #expect(ThresholdRule.thermalLevels == 1...3)
    }

    @Test("The stored levels map to the system's levels")
    func levelMapping() {
        #expect(ThresholdRule(signal: .memoryPressure, isOn: true, limit: 1, hold: .oneMinute).pressureLevel == .warning)
        #expect(ThresholdRule(signal: .memoryPressure, isOn: true, limit: 2, hold: .oneMinute).pressureLevel == .critical)
        #expect(ThresholdRule(signal: .thermal, isOn: true, limit: 1, hold: .immediately).thermalLevel == .fair)
        #expect(ThresholdRule(signal: .thermal, isOn: true, limit: 2, hold: .immediately).thermalLevel == .serious)
        #expect(ThresholdRule(signal: .thermal, isOn: true, limit: 3, hold: .immediately).thermalLevel == .critical)
    }

    @Test("A disk rule's threshold is in decimal gigabytes")
    func thresholdBytes() {
        #expect(ThresholdRule.defaultRule(for: .freeDisk).thresholdBytes == 10_000_000_000)
        #expect(ThresholdRule.bytesPerGigabyte == 1_000_000_000)
        let huge = ThresholdRule(signal: .freeDisk, isOn: true, limit: 200, hold: .oneMinute)
        #expect(huge.thresholdBytes == 200_000_000_000)
    }

    @Test("A rule with a stray limit is brought back by its validated copy")
    func validatedCopy() {
        let stray = ThresholdRule(signal: .cpu, isOn: true, limit: 120, hold: .tenSeconds)
        #expect(stray.validated == ThresholdRule(signal: .cpu, isOn: true, limit: 95, hold: .tenSeconds))
    }
}
