import Foundation
import Testing
@testable import HolzBarCore

@Suite("WidgetReadings")
struct WidgetReadingsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The CPU load is busy ticks over all ticks of the difference (D-03)")
    func cpuLoad() {
        let before = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let after = CPUTicks(user: 160, system: 90, idle: 1100, nice: 50)
        // Busy: 60 + 40 + 0 = 100; idle: 300.
        #expect(WidgetReadings.cpuLoad(from: before, to: after) == 0.25)
        let busy = CPUTicks(user: 200, system: 50, idle: 800, nice: 50)
        #expect(WidgetReadings.cpuLoad(from: before, to: busy) == 1)
        let nice = CPUTicks(user: 100, system: 50, idle: 900, nice: 150)
        #expect(WidgetReadings.cpuLoad(from: before, to: nice) == 0.5)
    }

    @Test("No ticks or a counter that went backwards give no CPU load")
    func cpuLoadWithoutTicks() {
        let ticks = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        #expect(WidgetReadings.cpuLoad(from: ticks, to: ticks) == nil)
        let wrapped = CPUTicks(user: 100, system: 50, idle: 10, nice: 50)
        #expect(WidgetReadings.cpuLoad(from: ticks, to: wrapped) == nil)
        let backwards = CPUTicks(user: 90, system: 60, idle: 900, nice: 50)
        #expect(WidgetReadings.cpuLoad(from: ticks, to: backwards) == nil)
    }

    @Test("Memory in use is internal less purgeable, plus wired and compressed, in pages of the page size")
    func memoryUsedBytes() {
        let pages = MemoryPages(internalPages: 1000, purgeable: 200, wired: 100, compressed: 50)
        #expect(pages.usedBytes(pageSize: 16_384) == 950 * 16_384)
        let mostlyPurgeable = MemoryPages(internalPages: 100, purgeable: 400, wired: 10, compressed: 5)
        #expect(mostlyPurgeable.usedBytes(pageSize: 4096) == 15 * 4096)
        let huge = MemoryPages(internalPages: .max, purgeable: 0, wired: .max, compressed: .max)
        #expect(huge.usedBytes(pageSize: 16_384) == .max)
    }

    @Test("Used memory and free disk space are shares of a total, and nil without one")
    func fractions() {
        #expect(WidgetReadings.usedFraction(used: 8, total: 32) == 0.25)
        #expect(WidgetReadings.usedFraction(used: 40, total: 32) == 1)
        #expect(WidgetReadings.usedFraction(used: 1, total: 0) == nil)
        #expect(WidgetReadings.diskFreeFraction(available: 250, total: 1000) == 0.25)
        #expect(WidgetReadings.diskFreeFraction(available: 2000, total: 1000) == 1)
        #expect(WidgetReadings.diskFreeFraction(available: 10, total: 0) == nil)
        #expect(WidgetReadings.diskFreeFraction(available: 10, total: -5) == nil)
        #expect(WidgetReadings.diskFreeFraction(available: -1, total: 1000) == nil)
    }

    @Test("Uptime is now minus boot, and nil when the boot is in the future")
    func uptime() {
        #expect(WidgetReadings.uptime(now: now, boot: now.addingTimeInterval(-3600)) == .seconds(3600))
        #expect(WidgetReadings.uptime(now: now, boot: now) == .zero)
        #expect(WidgetReadings.uptime(now: now, boot: now.addingTimeInterval(1)) == nil)
    }

    @Test("A countdown never has negative time and changes at the next minute (D-02)")
    func countdown() {
        let target = now.addingTimeInterval(125.5)
        let remaining = Countdown.remaining(now: now, target: target)
        #expect(remaining == .seconds(125.5))
        #expect(Countdown.secondsToNextChange(remaining: remaining) == 5.5)
        #expect(Countdown.secondsToNextChange(remaining: .seconds(120)) == 60)
        #expect(Countdown.secondsToNextChange(remaining: .seconds(30)) == 30)
        let past = Countdown.remaining(now: now, target: now.addingTimeInterval(-10))
        #expect(past == .zero)
        #expect(Countdown.secondsToNextChange(remaining: past) == nil)
        #expect(Countdown.remaining(now: now, target: now) == .zero)
    }

    @Test("A countdown reading tells when its moment has passed (D-02)")
    func countdownReading() {
        #expect(Countdown.reading(now: now, target: now.addingTimeInterval(90))
            == .countdown(remaining: .seconds(90), isPassed: false))
        #expect(Countdown.reading(now: now, target: now.addingTimeInterval(-90))
            == .countdown(remaining: .zero, isPassed: true))
        #expect(Countdown.reading(now: now, target: now)
            == .countdown(remaining: .zero, isPassed: true))
    }

    @Test("The battery state follows the power source flags")
    func batteryState() {
        #expect(BatteryState(isOnBattery: true, isCharging: false, isCharged: false) == .onBattery)
        #expect(BatteryState(isOnBattery: false, isCharging: true, isCharged: false) == .charging)
        #expect(BatteryState(isOnBattery: false, isCharging: false, isCharged: true) == .charged)
        #expect(BatteryState(isOnBattery: false, isCharging: false, isCharged: false) == .onAdapter)
        // A source on battery power is discharging, whatever else it reports.
        #expect(BatteryState(isOnBattery: true, isCharging: true, isCharged: false) == .onBattery)
    }
}
