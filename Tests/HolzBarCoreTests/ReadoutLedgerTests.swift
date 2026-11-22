import Foundation
import Testing
@testable import HolzBarCore

@Suite("ReadoutLedger")
struct ReadoutLedgerTests {
    // The clock is a fixed start instant plus seconds.
    private let start = ContinuousClock.now

    private func request(
        _ metrics: Set<ReadoutMetric>,
        seconds: Int = 5,
        needsBaseline: Bool = false
    ) -> ReadoutRequest {
        ReadoutRequest(metrics: metrics, intervalSeconds: seconds, needsBaseline: needsBaseline)
    }

    private func tick(
        _ ledger: ReadoutLedger,
        _ deliveries: [String: ReadoutSchedule.Delivery] = [:],
        after seconds: Double = 0,
        isLowPowerMode: Bool = false,
        isPaused: Bool = false
    ) -> ReadoutSchedule.Tick? {
        ReadoutSchedule.nextTick(
            ledger: ledger,
            deliveries: deliveries,
            now: start + .milliseconds(Int(seconds * 1_000)),
            isLowPowerMode: isLowPowerMode,
            isPaused: isPaused
        )
    }

    // MARK: The ledger

    @Test("A new ledger is idle")
    func newLedgerIsIdle() {
        let ledger = ReadoutLedger()
        #expect(ledger.isIdle)
        #expect(ledger.metrics.isEmpty)
        #expect(ledger.eventMetrics.isEmpty)
        #expect(ledger.visibleCount == 0)
        #expect(ledger.backgroundCount == 0)
    }

    @Test("Registering and unregistering")
    func registerAndUnregister() {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu]))
        #expect(!ledger.isIdle)
        #expect(ledger.metrics == [.cpu])
        #expect(ledger.visibleCount == 1)
        #expect(ledger.request(for: "a") == request([.cpu]))

        // The same id again replaces the consumer.
        ledger.register("a", kind: .visible, request: request([.network]))
        #expect(ledger.metrics == [.network])
        #expect(ledger.visibleCount == 1)

        // An unknown id changes nothing.
        let before = ledger
        ledger.unregister("unknown")
        #expect(ledger == before)

        ledger.unregister("a")
        #expect(ledger.isIdle)
        #expect(ledger.request(for: "a") == nil)
    }

    @Test("A background consumer counts as a background consumer only")
    func backgroundCounts() {
        var ledger = ReadoutLedger()
        ledger.register("alert", kind: .background, request: request([.memoryPressure]))
        #expect(!ledger.isIdle)
        #expect(ledger.backgroundCount == 1)
        #expect(ledger.visibleCount == 0)
    }

    @Test("The event metrics are the metrics that are announced")
    func eventMetrics() {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu, .thermal]))
        ledger.register("b", kind: .visible, request: request([.memoryPressure, .power, .network]))
        #expect(ledger.metrics == [.cpu, .thermal, .memoryPressure, .power, .network])
        #expect(ledger.eventMetrics == [.thermal, .memoryPressure, .power])
        let events = Set(ReadoutMetric.allCases.filter(\.isEvent))
        #expect(events == [.memoryPressure, .power, .thermal])
    }

    @Test("The device battery is the last metric, timed and not an event")
    func deviceBatteryMetric() throws {
        #expect(ReadoutMetric.allCases.last == .deviceBattery)
        #expect(!ReadoutMetric.deviceBattery.isEvent)
        let events = Set(ReadoutMetric.allCases.filter(\.isEvent))
        #expect(events == [.memoryPressure, .power, .thermal])

        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        #expect(ledger.eventMetrics.isEmpty)
        let deliveries = ["a": ReadoutSchedule.Delivery(last: start, count: 1)]
        let next = try #require(tick(ledger, deliveries, after: 1))
        #expect(next.at == start + .seconds(300))
        #expect(next.metrics == [.deviceBattery])
    }

    // MARK: The schedule, MON-08

    @Test("An idle ledger measures nothing")
    func idleMeasuresNothing() {
        let idle = ReadoutLedger()
        #expect(tick(idle) == nil)
        #expect(ReadoutSchedule.observers(ledger: idle, isPaused: false).isEmpty)

        // A ledger whose only consumer came and went is idle again.
        var used = ReadoutLedger()
        used.register("a", kind: .visible, request: request([.cpu, .thermal]))
        used.unregister("a")
        #expect(tick(used) == nil)
        #expect(ReadoutSchedule.observers(ledger: used, isPaused: false).isEmpty)
    }

    @Test("A paused Mac gives no tick and no observer")
    func pausedMeasuresNothing() {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu, .thermal]))
        #expect(tick(ledger, isPaused: true) == nil)
        #expect(ReadoutSchedule.observers(ledger: ledger, isPaused: true).isEmpty)
        #expect(ReadoutSchedule.observers(ledger: ledger, isPaused: false) == [.thermal])
    }

    @Test("The device battery follows the power source event and nothing else")
    func deviceBatteryObservesThePowerSource() {
        var only = ReadoutLedger()
        only.register("a", kind: .visible, request: request([.deviceBattery]))
        #expect(ReadoutSchedule.observers(ledger: only, isPaused: false) == [.power])
        #expect(ReadoutSchedule.observers(ledger: only, isPaused: true).isEmpty)

        var mixed = ReadoutLedger()
        mixed.register("a", kind: .visible, request: request([.deviceBattery, .cpu]))
        mixed.register("b", kind: .visible, request: request([.thermal]))
        #expect(ReadoutSchedule.observers(ledger: mixed, isPaused: false) == [.power, .thermal])
        #expect(ReadoutSchedule.observers(ledger: mixed, isPaused: true).isEmpty)

        // A consumer of the power alone observes the power, as before.
        var power = ReadoutLedger()
        power.register("a", kind: .visible, request: request([.power]))
        #expect(ReadoutSchedule.observers(ledger: power, isPaused: false) == [.power])
    }

    @Test("A consumer never delivered is due at once with all its metrics")
    func firstDeliveryIsImmediate() throws {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu, .thermal]))
        let first = try #require(tick(ledger, after: 3))
        #expect(first.at == start + .seconds(3))
        #expect(first.consumers == ["a"])
        #expect(first.metrics == [.cpu, .thermal])
    }

    @Test("After one delivery a baseline consumer is due one second later")
    func baselineDelay() throws {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu], seconds: 5, needsBaseline: true))
        let deliveries = ["a": ReadoutSchedule.Delivery(last: start, count: 1)]
        let second = try #require(tick(ledger, deliveries, after: 0.1))
        #expect(second.at == start + .seconds(1))
        #expect(second.metrics == [.cpu])

        // Low Power Mode does not double the baseline delay.
        let lowPower = try #require(tick(ledger, deliveries, after: 0.1, isLowPowerMode: true))
        #expect(lowPower.at == start + .seconds(1))
    }

    @Test("After two deliveries a consumer is due at its interval, doubled in Low Power Mode")
    func intervalAndLowPowerMode() throws {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu], seconds: 5, needsBaseline: true))
        let deliveries = ["a": ReadoutSchedule.Delivery(last: start, count: 2)]
        let normal = try #require(tick(ledger, deliveries, after: 1))
        #expect(normal.at == start + .seconds(5))
        #expect(normal.tolerance == .milliseconds(500))

        let lowPower = try #require(tick(ledger, deliveries, after: 1, isLowPowerMode: true))
        #expect(lowPower.at == start + .seconds(10))
        #expect(lowPower.tolerance == .seconds(1))
    }

    @Test("An event-only request is due once and then never on the timer")
    func eventOnlyIsDueOnce() throws {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.thermal, .memoryPressure]))
        let first = try #require(tick(ledger))
        #expect(first.metrics == [.thermal, .memoryPressure])

        let deliveries = ["a": ReadoutSchedule.Delivery(last: start, count: 1)]
        #expect(tick(ledger, deliveries, after: 60) == nil)
        #expect(ReadoutSchedule.observers(ledger: ledger, isPaused: false) == [.thermal, .memoryPressure])
    }

    @Test("A timed tick is never sooner than 250 ms from now")
    func minimumDelay() throws {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu], seconds: 5))
        let deliveries = ["a": ReadoutSchedule.Delivery(last: start, count: 2)]
        // The tick was due five seconds after the start; it is much later now.
        let overdue = try #require(tick(ledger, deliveries, after: 30))
        #expect(overdue.at == start + .seconds(30) + ReadoutSchedule.minimumDelay)
        #expect(ReadoutSchedule.minimumDelay == .milliseconds(250))
    }

    @Test("Consumers due within a tenth of the earliest interval share one tick")
    func consumersShareATick() throws {
        var ledger = ReadoutLedger()
        ledger.register("a", kind: .visible, request: request([.cpu, .thermal], seconds: 10))
        ledger.register("b", kind: .visible, request: request([.network], seconds: 10))
        ledger.register("c", kind: .visible, request: request([.memory], seconds: 10))
        let deliveries = [
            "a": ReadoutSchedule.Delivery(last: start, count: 2),
            "b": ReadoutSchedule.Delivery(last: start + .milliseconds(500), count: 2),
            "c": ReadoutSchedule.Delivery(last: start + .seconds(2), count: 2),
        ]
        let shared = try #require(tick(ledger, deliveries, after: 1))
        #expect(shared.at == start + .seconds(10))
        #expect(shared.tolerance == .seconds(1))
        #expect(shared.consumers == ["a", "b"])
        // Timed metrics only: the event metric of "a" is not read on the timer.
        #expect(shared.metrics == [.cpu, .network])
    }

    @Test("A background-only ledger ticks like a visible one")
    func backgroundOnlyTicks() throws {
        var ledger = ReadoutLedger()
        ledger.register("alert", kind: .background, request: request([.memory], seconds: 30))
        #expect(!ledger.isIdle)
        let first = try #require(tick(ledger))
        #expect(first.consumers == ["alert"])
        let deliveries = ["alert": ReadoutSchedule.Delivery(last: start, count: 2)]
        let next = try #require(tick(ledger, deliveries, after: 1))
        #expect(next.at == start + .seconds(30))
    }

    @Test("A stored interval outside 1 to 3600 seconds is brought into the range")
    func intervalIsClamped() throws {
        var ledger = ReadoutLedger()
        ledger.register("zero", kind: .visible, request: request([.cpu], seconds: 0))
        let zero = try #require(tick(
            ledger,
            ["zero": ReadoutSchedule.Delivery(last: start, count: 2)],
            after: 0
        ))
        #expect(zero.at == start + .seconds(1))

        var huge = ReadoutLedger()
        huge.register("huge", kind: .visible, request: request([.cpu], seconds: 10_000))
        let long = try #require(tick(
            huge,
            ["huge": ReadoutSchedule.Delivery(last: start, count: 2)],
            after: 0
        ))
        #expect(long.at == start + .seconds(3_600))

        var negative = ReadoutLedger()
        negative.register("n", kind: .visible, request: request([.cpu], seconds: Int.min))
        let floor = try #require(tick(
            negative,
            ["n": ReadoutSchedule.Delivery(last: start, count: 2)],
            after: 0,
            isLowPowerMode: true
        ))
        #expect(floor.at >= start + ReadoutSchedule.minimumDelay)
    }

    @Test("Ticks of other ids are ignored and the ids of a tick are sorted")
    func idsAreSorted() throws {
        var ledger = ReadoutLedger()
        ledger.register("z", kind: .visible, request: request([.cpu]))
        ledger.register("m", kind: .visible, request: request([.memory]))
        ledger.register("a", kind: .visible, request: request([.network]))
        let deliveries = ["gone": ReadoutSchedule.Delivery(last: start, count: 5)]
        let first = try #require(tick(ledger, deliveries))
        #expect(first.consumers == ["a", "m", "z"])
    }

    @Test("The free disk space is read again after 60 seconds")
    func diskSpaceRefresh() {
        #expect(ReadoutSchedule.refreshesDiskSpace(lastRefresh: nil, now: start))
        #expect(!ReadoutSchedule.refreshesDiskSpace(lastRefresh: start, now: start + .seconds(59)))
        #expect(ReadoutSchedule.refreshesDiskSpace(lastRefresh: start, now: start + .seconds(60)))
        #expect(ReadoutSchedule.diskSpaceRefresh == .seconds(60))
    }

    // MARK: Gated reads after their switch changes (WR-01)

    private func delivered(_ seconds: Double, count: Int) -> ReadoutSchedule.Delivery {
        ReadoutSchedule.Delivery(last: start + .milliseconds(Int(seconds * 1_000)), count: count)
    }

    private func scheduledLedger(
        _ ledger: ReadoutLedger,
        _ deliveries: [String: ReadoutSchedule.Delivery],
        readsGPU: Bool = true,
        readsDeviceBattery: Bool = true
    ) -> ReadoutLedger {
        ReadoutSchedule.scheduledLedger(
            ledger,
            deliveries: deliveries,
            readsGPU: readsGPU,
            readsDeviceBattery: readsDeviceBattery
        )
    }

    @Test("A served device battery consumer rests while Read battery levels is off, which is the defect without the restart")
    func servedDeviceBatteryConsumerRestsWhileOff() {
        var ledger = ReadoutLedger()
        ledger.register("widget.a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        let deliveries = ["widget.a": delivered(0, count: 3)]
        let rested = scheduledLedger(ledger, deliveries, readsDeviceBattery: false)
        #expect(rested.isIdle)
        #expect(tick(rested, deliveries, after: 10) == nil)
        #expect(ReadoutSchedule.observers(ledger: rested, isPaused: false).isEmpty)
    }

    @Test("Switching Read battery levels off gives the consumer one empty reading, then it rests again")
    func switchingTheBatteryOffRestartsThenRests() throws {
        var ledger = ReadoutLedger()
        ledger.register("widget.a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        let restarted = ReadoutSchedule.restartingDeliveries(
            ["widget.a": delivered(0, count: 3)],
            of: .deviceBattery,
            in: ledger
        )
        #expect(restarted["widget.a"] == nil)

        let kept = scheduledLedger(ledger, restarted, readsDeviceBattery: false)
        #expect(kept.consumerIDs == ["widget.a"])
        let due = try #require(tick(kept, restarted, after: 10))
        #expect(due.at == start + .seconds(10))
        #expect(due.consumers == ["widget.a"])
        #expect(due.metrics.contains(.deviceBattery))
        #expect(ReadoutSchedule.observers(ledger: kept, isPaused: false) == [.power])

        let afterDelivery = ["widget.a": delivered(10, count: 1)]
        let rested = scheduledLedger(ledger, afterDelivery, readsDeviceBattery: false)
        #expect(rested.isIdle)
        #expect(tick(rested, afterDelivery, after: 11) == nil)
        #expect(ReadoutSchedule.observers(ledger: rested, isPaused: false).isEmpty)
    }

    @Test("Switching Read battery levels on reads at once, not after the interval")
    func switchingTheBatteryOnReadsAtOnce() throws {
        var ledger = ReadoutLedger()
        ledger.register("widget.a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        let deliveries = ["widget.a": delivered(0, count: 2)]
        let waiting = try #require(tick(scheduledLedger(ledger, deliveries), deliveries, after: 10))
        #expect(waiting.at == start + .seconds(300))

        let restarted = ReadoutSchedule.restartingDeliveries(deliveries, of: .deviceBattery, in: ledger)
        let kept = scheduledLedger(ledger, restarted)
        let due = try #require(tick(kept, restarted, after: 10))
        #expect(due.at == start + .seconds(10))
        #expect(due.consumers == ["widget.a"])
        #expect(due.metrics.contains(.deviceBattery))
        #expect(ReadoutSchedule.observers(ledger: kept, isPaused: false) == [.power])
    }

    @Test("Only the consumers of the metric restart")
    func onlyTheMetricConsumersRestart() {
        var ledger = ReadoutLedger()
        ledger.register("widget.a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        ledger.register("mixed", kind: .visible, request: request([.deviceBattery, .cpu]))
        ledger.register("tiles", kind: .visible, request: request([.cpu], needsBaseline: true))
        ledger.register("alerts", kind: .background, request: request([.thermal]))
        let deliveries = [
            "widget.a": delivered(0, count: 3),
            "mixed": delivered(1, count: 3),
            "tiles": delivered(2, count: 4),
            "alerts": delivered(3, count: 1),
            "gone": delivered(4, count: 2)
        ]
        let restarted = ReadoutSchedule.restartingDeliveries(deliveries, of: .deviceBattery, in: ledger)
        #expect(restarted["widget.a"] == nil)
        #expect(restarted["mixed"] == nil)
        #expect(restarted["tiles"] == deliveries["tiles"])
        #expect(restarted["alerts"] == deliveries["alerts"])
        // A record of an id that is not registered is kept as it is.
        #expect(restarted["gone"] == deliveries["gone"])
    }

    @Test("The rest rule stays: GPU and device battery only consumers rest, mixed ones and new ones never do")
    func restRuleIsUnchanged() {
        var ledger = ReadoutLedger()
        ledger.register("gpu", kind: .visible, request: request([.gpu], seconds: 60))
        ledger.register("both", kind: .visible, request: request([.gpu, .cpu], seconds: 60))
        ledger.register("fresh", kind: .visible, request: request([.deviceBattery], seconds: 300))
        let deliveries = ["gpu": delivered(0, count: 1), "both": delivered(0, count: 5)]

        let gpuOff = scheduledLedger(ledger, deliveries, readsGPU: false)
        #expect(gpuOff.consumerIDs == ["both", "fresh"])
        let gpuOn = scheduledLedger(ledger, deliveries, readsGPU: true)
        #expect(gpuOn == ledger)

        // A consumer with no delivery stays even with its switch off: its first, empty reading.
        let batteryOff = scheduledLedger(ledger, deliveries, readsDeviceBattery: false)
        #expect(batteryOff.consumerIDs == ["both", "fresh", "gpu"])
        let freshOnly = scheduledLedger(ledger, [:], readsGPU: false, readsDeviceBattery: false)
        #expect(freshOnly == ledger)
    }

    @Test("Switching Read GPU load off gives the consumer one empty reading, then it rests again")
    func switchingTheGPUOffRestartsThenRests() throws {
        var ledger = ReadoutLedger()
        ledger.register("widget.g", kind: .visible, request: request([.gpu], seconds: 60))
        let deliveries = ["widget.g": delivered(0, count: 3)]
        let rested = scheduledLedger(ledger, deliveries, readsGPU: false)
        #expect(rested.isIdle)
        #expect(tick(rested, deliveries, after: 10) == nil)

        let restarted = ReadoutSchedule.restartingDeliveries(deliveries, of: .gpu, in: ledger)
        #expect(restarted["widget.g"] == nil)
        let kept = scheduledLedger(ledger, restarted, readsGPU: false)
        #expect(kept.consumerIDs == ["widget.g"])
        let due = try #require(tick(kept, restarted, after: 10))
        #expect(due.at == start + .seconds(10))
        #expect(due.consumers == ["widget.g"])
        #expect(due.metrics == [.gpu])
        // The GPU is no event: nothing is observed.
        #expect(ReadoutSchedule.observers(ledger: kept, isPaused: false).isEmpty)

        let afterDelivery = ["widget.g": delivered(10, count: 1)]
        let restedAgain = scheduledLedger(ledger, afterDelivery, readsGPU: false)
        #expect(restedAgain.isIdle)
        #expect(tick(restedAgain, afterDelivery, after: 11) == nil)
    }

    @Test("Switching Read GPU load on reads at once, not after the refresh")
    func switchingTheGPUOnReadsAtOnce() throws {
        var ledger = ReadoutLedger()
        ledger.register("widget.g", kind: .visible, request: request([.gpu], seconds: 60))
        let deliveries = ["widget.g": delivered(0, count: 2)]
        let waiting = try #require(tick(scheduledLedger(ledger, deliveries), deliveries, after: 10))
        #expect(waiting.at == start + .seconds(60))

        let restarted = ReadoutSchedule.restartingDeliveries(deliveries, of: .gpu, in: ledger)
        let due = try #require(tick(scheduledLedger(ledger, restarted), restarted, after: 10))
        #expect(due.at == start + .seconds(10))
        #expect(due.metrics.contains(.gpu))
    }

    @Test("The two restarts are independent")
    func theRestartsAreIndependent() {
        var ledger = ReadoutLedger()
        ledger.register("widget.g", kind: .visible, request: request([.gpu], seconds: 60))
        ledger.register("tiles", kind: .visible, request: request([.cpu, .gpu, .memory]))
        ledger.register("widget.a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        let deliveries = [
            "widget.g": delivered(0, count: 3),
            "tiles": delivered(1, count: 3),
            "widget.a": delivered(2, count: 3)
        ]
        let gpu = ReadoutSchedule.restartingDeliveries(deliveries, of: .gpu, in: ledger)
        #expect(gpu["widget.g"] == nil)
        #expect(gpu["tiles"] == nil)
        #expect(gpu["widget.a"] == deliveries["widget.a"])

        let battery = ReadoutSchedule.restartingDeliveries(deliveries, of: .deviceBattery, in: ledger)
        #expect(battery["widget.a"] == nil)
        #expect(battery["widget.g"] == deliveries["widget.g"])
        #expect(battery["tiles"] == deliveries["tiles"])
    }

    @Test("A restart tick is shared by the schedule's existing rule: early, never late, others untouched")
    func theRestartTickSharesAsBefore() throws {
        var ledger = ReadoutLedger()
        ledger.register("widget.a", kind: .visible, request: request([.deviceBattery], seconds: 300))
        ledger.register("tiles", kind: .visible, request: request([.cpu], seconds: 60))
        ledger.register("slow", kind: .visible, request: request([.diskSpace], seconds: 600))
        let deliveries = [
            "widget.a": delivered(-200, count: 2),
            "tiles": delivered(-40, count: 2),
            "slow": delivered(-540, count: 2)
        ]
        let restarted = ReadoutSchedule.restartingDeliveries(deliveries, of: .deviceBattery, in: ledger)
        #expect(restarted["tiles"] == deliveries["tiles"])
        #expect(restarted["slow"] == deliveries["slow"])

        let shared = try #require(tick(scheduledLedger(ledger, restarted), restarted, after: 0))
        #expect(shared.at == start)
        #expect(shared.consumers == ["tiles", "widget.a"])
    }

    // MARK: The visibility of a surface

    @Test("Tiles pause with the Mac")
    func tilesPauseWithTheMac() {
        var visibility = ReadoutVisibility()
        #expect(!visibility.isVisible)

        // Shown while the Mac is in use: registers at once.
        #expect(visibility.handle(.shown(true), at: start) == .register)
        #expect(visibility.isVisible)
        #expect(visibility.handle(.shown(true), at: start + .seconds(1)) == .keep)

        // The Mac stops being in use: unregistered.
        #expect(visibility.handle(.paused(true), at: start + .seconds(2)) == .unregister)
        #expect(!visibility.isVisible)
        #expect(visibility.handle(.paused(true), at: start + .seconds(3)) == .keep)

        // The Mac is in use again: wait for the menu bar to settle, do not register yet.
        let settle = start + .seconds(10) + SystemActivity.settleDelay
        #expect(visibility.handle(.paused(false), at: start + .seconds(10)) == .waitUntil(settle))
        #expect(!visibility.isVisible)
        #expect(visibility.handle(.paused(false), at: start + .seconds(11)) == .keep)

        // The wait elapses while the surface is still shown.
        #expect(visibility.handle(.settleElapsed, at: settle) == .register)
        #expect(visibility.isVisible)

        // Hidden while registered.
        #expect(visibility.handle(.shown(false), at: settle + .seconds(1)) == .unregister)
        #expect(!visibility.isVisible)
        #expect(visibility.handle(.shown(false), at: settle + .seconds(2)) == .keep)
    }

    @Test("A surface closed during the pause never registers")
    func closedDuringThePause() {
        var visibility = ReadoutVisibility()
        _ = visibility.handle(.shown(true), at: start)
        _ = visibility.handle(.paused(true), at: start + .seconds(1))
        let settle = start + .seconds(5) + SystemActivity.settleDelay
        #expect(visibility.handle(.paused(false), at: start + .seconds(5)) == .waitUntil(settle))
        #expect(visibility.handle(.shown(false), at: start + .seconds(6)) == .keep)
        #expect(visibility.handle(.settleElapsed, at: settle) == .keep)
        #expect(!visibility.isVisible)
    }

    @Test("A settle wait that fires early waits again, and a surface shown inside it waits too")
    func earlySettleWait() {
        var visibility = ReadoutVisibility()
        _ = visibility.handle(.paused(true), at: start)
        let settle = start + .seconds(5) + SystemActivity.settleDelay
        // Shown while paused: nothing yet.
        #expect(visibility.handle(.shown(true), at: start + .seconds(1)) == .keep)
        #expect(visibility.handle(.paused(false), at: start + .seconds(5)) == .waitUntil(settle))
        #expect(visibility.handle(.settleElapsed, at: start + .seconds(6)) == .waitUntil(settle))
        #expect(visibility.handle(.settleElapsed, at: settle) == .register)

        // Shown inside a settle wait that began while hidden.
        var hidden = ReadoutVisibility()
        _ = hidden.handle(.paused(true), at: start)
        #expect(hidden.handle(.paused(false), at: start + .seconds(5)) == .keep)
        #expect(hidden.handle(.shown(true), at: start + .seconds(6)) == .waitUntil(settle))
        #expect(hidden.handle(.settleElapsed, at: settle) == .register)
    }
}
