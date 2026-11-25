import Foundation
import Testing
@testable import HolzBarCore

@Suite("WidgetRefreshPolicy")
struct WidgetRefreshPolicyTests {
    // The state is changed outside `#expect`, whose expansion cannot call a mutating method.
    // The clock is a fixed start instant plus seconds; the date is a fixed day in GMT.

    private let start = ContinuousClock.now

    /// 2026-01-01 12:00:00 GMT plus `seconds`.
    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_767_268_800 + seconds)
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    private func handle(
        _ policy: inout WidgetRefreshPolicy,
        _ event: WidgetRefreshPolicy.Event,
        after seconds: Int,
        date offset: TimeInterval
    ) -> WidgetRefreshPolicy.Command {
        policy.handle(event, at: start + .seconds(seconds), date: date(offset), calendar: calendar)
    }

    /// A policy for `cadence` that has been revealed at the start and is visible.
    private func visible(_ cadence: WidgetCadence, atSecond second: TimeInterval = 30) -> WidgetRefreshPolicy {
        var policy = WidgetRefreshPolicy(cadence: cadence)
        _ = handle(&policy, .shown(true), after: 0, date: second)
        return policy
    }

    // MARK: D-14, the four promises

    @Test("No timer while hidden")
    func noTimerWhileHidden() {
        var policy = visible(.clock(showsSeconds: false))
        #expect(policy.isVisible)

        let hide = handle(&policy, .shown(false), after: 5, date: 35)
        #expect(hide.timer == .cancel)
        #expect(hide.marksUnavailable)
        #expect(!hide.refreshes)
        #expect(!policy.isVisible)

        // A timer that still fires while hidden refreshes nothing and arms nothing.
        let stray = handle(&policy, .timerFired, after: 30, date: 60)
        #expect(!stray.refreshes)
        #expect(stray.timer == .cancel)

        // Neither does a clock change or a source event.
        let changed = handle(&policy, .clockChanged, after: 31, date: 61)
        #expect(changed == .unchanged)
        let source = handle(&policy, .sourceChanged, after: 32, date: 62)
        #expect(source == .unchanged)
    }

    @Test("One refresh on reveal")
    func oneRefreshOnReveal() {
        var policy = WidgetRefreshPolicy(cadence: .clock(showsSeconds: false))
        #expect(!policy.isVisible)

        let reveal = handle(&policy, .shown(true), after: 0, date: 30)
        #expect(reveal.refreshes)
        #expect(!reveal.marksUnavailable)
        #expect(reveal.timer == .arm(start + .milliseconds(30_050), tolerance: .seconds(6)))
        #expect(policy.isVisible)

        let again = handle(&policy, .shown(true), after: 1, date: 31)
        #expect(!again.refreshes)
        #expect(again.timer == .keep)

        // Hidden and revealed again: one refresh again.
        _ = handle(&policy, .shown(false), after: 2, date: 32)
        let second = handle(&policy, .shown(true), after: 3, date: 33)
        #expect(second.refreshes)
        #expect(second.timer == .arm(start + .seconds(3) + .milliseconds(27_050), tolerance: .seconds(6)))
    }

    @Test("Cancelled on lock")
    func cancelledOnLock() {
        var policy = visible(.clock(showsSeconds: false))

        let lock = handle(&policy, .paused(true), after: 10, date: 40)
        #expect(lock.timer == .cancel)
        #expect(lock.marksUnavailable)
        #expect(!lock.refreshes)
        #expect(!policy.isVisible)

        let stray = handle(&policy, .timerFired, after: 30, date: 60)
        #expect(!stray.refreshes)
        #expect(stray.timer == .cancel)

        // A reveal while locked changes nothing yet.
        _ = handle(&policy, .shown(false), after: 31, date: 61)
        let reveal = handle(&policy, .shown(true), after: 32, date: 62)
        #expect(reveal == .unchanged)
    }

    @Test("Re-armed on unlock after settleDelay")
    func rearmedOnUnlockAfterSettleDelay() {
        var policy = visible(.clock(showsSeconds: false))
        _ = handle(&policy, .paused(true), after: 10, date: 40)

        // Unlocked: only the settle timer, no refresh yet.
        let unlock = handle(&policy, .paused(false), after: 40, date: 70)
        #expect(!unlock.refreshes)
        #expect(!unlock.marksUnavailable)
        #expect(unlock.timer == .arm(start + .seconds(40) + SystemActivity.settleDelay, tolerance: .milliseconds(200)))
        #expect(!policy.isVisible)

        // The settle timer fires: one refresh, and the clock's next change is armed.
        let settled = handle(&policy, .timerFired, after: 42, date: 72)
        #expect(settled.refreshes)
        #expect(settled.timer == .arm(start + .seconds(42) + .milliseconds(48_050), tolerance: .seconds(6)))
        #expect(policy.isVisible)
    }

    // MARK: Settling and locking in other orders

    @Test("A timer that fires early in the settle wait waits for the end")
    func earlySettleTimer() {
        var policy = visible(.clock(showsSeconds: false))
        _ = handle(&policy, .paused(true), after: 10, date: 40)
        _ = handle(&policy, .paused(false), after: 40, date: 70)

        let early = policy.handle(
            .timerFired,
            at: start + .seconds(40) + .milliseconds(1_000),
            date: date(71),
            calendar: calendar
        )
        #expect(!early.refreshes)
        #expect(early.timer == .arm(start + .seconds(40) + SystemActivity.settleDelay, tolerance: .milliseconds(200)))
        #expect(!policy.isVisible)
    }

    @Test("Revealed after a settle that ended while hidden refreshes at once")
    func revealAfterSettleWhileHidden() {
        var policy = visible(.clock(showsSeconds: false))
        _ = handle(&policy, .shown(false), after: 5, date: 35)
        _ = handle(&policy, .paused(true), after: 6, date: 36)

        // Unlocked while hidden: nothing to arm.
        let unlock = handle(&policy, .paused(false), after: 20, date: 50)
        #expect(unlock == .unchanged)

        // Revealed after the settle delay has passed: refresh and arm at once.
        let reveal = handle(&policy, .shown(true), after: 30, date: 60)
        #expect(reveal.refreshes)
        #expect(reveal.timer == .arm(start + .seconds(30) + .milliseconds(60_050), tolerance: .seconds(6)))
        #expect(policy.isVisible)

        // Revealed inside the settle delay: only the settle timer.
        var inside = visible(.clock(showsSeconds: false))
        _ = handle(&inside, .shown(false), after: 5, date: 35)
        _ = handle(&inside, .paused(true), after: 6, date: 36)
        _ = handle(&inside, .paused(false), after: 20, date: 50)
        let early = handle(&inside, .shown(true), after: 21, date: 51)
        #expect(!early.refreshes)
        #expect(early.timer == .arm(start + .seconds(20) + SystemActivity.settleDelay, tolerance: .milliseconds(200)))
    }

    // MARK: D-15, the cadences

    @Test("The clock arms at the next whole minute plus 50 ms")
    func clockArmsAtNextMinute() {
        let onTheMinute = WidgetRefreshPolicy.nextFire(
            for: .clock(showsSeconds: false),
            date: date(0),
            calendar: calendar,
            isLowPowerMode: false
        )
        #expect(onTheMinute == WidgetRefreshPolicy.Fire(delay: .milliseconds(60_050), tolerance: .seconds(6)))

        let midMinute = WidgetRefreshPolicy.nextFire(
            for: .clock(showsSeconds: false),
            date: date(30),
            calendar: calendar,
            isLowPowerMode: false
        )
        #expect(midMinute == WidgetRefreshPolicy.Fire(delay: .milliseconds(30_050), tolerance: .seconds(6)))
    }

    @Test("A clock with seconds arms at the next whole second with a tolerance of 0.1 s")
    func clockWithSeconds() {
        let fire = WidgetRefreshPolicy.nextFire(
            for: .clock(showsSeconds: true),
            date: date(30.25),
            calendar: calendar,
            isLowPowerMode: false
        )
        #expect(fire == WidgetRefreshPolicy.Fire(delay: .milliseconds(800), tolerance: .milliseconds(100)))
    }

    @Test("A fire is never sooner than 250 ms")
    func neverSoonerThan250Milliseconds() {
        // 100 ms before the minute: the delay is 150 ms with the 50 ms, and is raised.
        let nearBoundary = WidgetRefreshPolicy.nextFire(
            for: .clock(showsSeconds: false),
            date: date(59.9),
            calendar: calendar,
            isLowPowerMode: false
        )
        #expect(nearBoundary?.delay == .milliseconds(250))

        // An interval that is zero or negative is raised too, and nothing traps.
        for seconds in [0, -5, Int.min] {
            let fire = WidgetRefreshPolicy.nextFire(
                for: .interval(seconds: seconds, needsBaseline: false),
                date: date(0),
                calendar: calendar,
                isLowPowerMode: true
            )
            #expect((fire?.delay ?? .zero) >= .milliseconds(250))
        }
        let huge = WidgetRefreshPolicy.nextFire(
            for: .interval(seconds: Int.max, needsBaseline: false),
            date: date(0),
            calendar: calendar,
            isLowPowerMode: true
        )
        #expect(huge != nil)
    }

    @Test("A countdown arms at its next minute change and arms nothing once passed")
    func countdownArmsAtNextMinuteChange() {
        let target = date(150)
        let running = WidgetRefreshPolicy.nextFire(
            for: .countdown(target: target),
            date: date(0),
            calendar: calendar,
            isLowPowerMode: false
        )
        // 150 s left: the shown minutes change in 30 s.
        #expect(running == WidgetRefreshPolicy.Fire(delay: .milliseconds(30_050), tolerance: .seconds(6)))

        let wholeMinutes = WidgetRefreshPolicy.nextFire(
            for: .countdown(target: target),
            date: date(30),
            calendar: calendar,
            isLowPowerMode: false
        )
        // 120 s left: a whole number of minutes, so a full minute.
        #expect(wholeMinutes == WidgetRefreshPolicy.Fire(delay: .milliseconds(60_050), tolerance: .seconds(6)))

        let passed = WidgetRefreshPolicy.nextFire(
            for: .countdown(target: target),
            date: date(150),
            calendar: calendar,
            isLowPowerMode: false
        )
        #expect(passed == nil)

        // On the policy: the last change is read, then nothing is armed.
        var policy = visible(.countdown(target: target), atSecond: 120)
        let last = policy.handle(
            .timerFired,
            at: start + .seconds(30),
            date: date(150),
            calendar: calendar
        )
        #expect(last.refreshes)
        #expect(last.timer == .cancel)
    }

    @Test("Battery and buttons never arm a timer and refresh on a source event only while visible")
    func eventOnlyNeverArms() {
        var policy = WidgetRefreshPolicy(cadence: .eventOnly)
        let hiddenEvent = handle(&policy, .sourceChanged, after: 0, date: 0)
        #expect(hiddenEvent == .unchanged)

        let reveal = handle(&policy, .shown(true), after: 1, date: 1)
        #expect(reveal.refreshes)
        #expect(reveal.timer == .cancel)

        let event = handle(&policy, .sourceChanged, after: 2, date: 2)
        #expect(event.refreshes)
        #expect(event.timer == .keep)

        let lowPower = handle(&policy, .lowPowerMode(true), after: 3, date: 3)
        #expect(lowPower == .unchanged)

        _ = handle(&policy, .paused(true), after: 4, date: 4)
        let whileLocked = handle(&policy, .sourceChanged, after: 5, date: 5)
        #expect(whileLocked == .unchanged)

        // After the settle timer the source is read once and no timer follows.
        _ = handle(&policy, .paused(false), after: 6, date: 6)
        let settled = handle(&policy, .timerFired, after: 8, date: 8)
        #expect(settled.refreshes)
        #expect(settled.timer == .cancel)
    }

    @Test("A source event means nothing to a clock")
    func sourceEventMeansNothingToClock() {
        var policy = visible(.clock(showsSeconds: false))
        let event = handle(&policy, .sourceChanged, after: 1, date: 31)
        #expect(event == .unchanged)
    }

    @Test("Polling intervals arm at their interval with a tolerance of a tenth")
    func pollingIntervals() {
        let cases: [(WidgetCadence, Int, Duration)] = [
            (.interval(seconds: 60, needsBaseline: false), 60, .seconds(6)),
            (.interval(seconds: 300, needsBaseline: false), 300, .seconds(30)),
            (.interval(seconds: 10, needsBaseline: false), 10, .seconds(1)),
            (.interval(seconds: 5, needsBaseline: false), 5, .milliseconds(500)),
        ]
        for (cadence, seconds, tolerance) in cases {
            var policy = WidgetRefreshPolicy(cadence: cadence)
            let reveal = handle(&policy, .shown(true), after: 0, date: 0)
            #expect(reveal.refreshes)
            #expect(reveal.timer == .arm(start + .seconds(seconds), tolerance: tolerance))

            let fired = handle(&policy, .timerFired, after: seconds, date: TimeInterval(seconds))
            #expect(fired.refreshes)
            #expect(fired.timer == .arm(start + .seconds(seconds * 2), tolerance: tolerance))
        }
    }

    @Test("Polling intervals double in Low Power Mode")
    func pollingIntervalsDoubleInLowPowerMode() {
        // Switched on while visible: re-armed without a refresh.
        var policy = visible(.interval(seconds: 10, needsBaseline: false))
        let low = handle(&policy, .lowPowerMode(true), after: 4, date: 4)
        #expect(!low.refreshes)
        #expect(low.timer == .arm(start + .seconds(24), tolerance: .seconds(2)))

        // Switched off again.
        let normal = handle(&policy, .lowPowerMode(false), after: 5, date: 5)
        #expect(normal.timer == .arm(start + .seconds(15), tolerance: .seconds(1)))

        // Already on at the reveal.
        var revealed = WidgetRefreshPolicy(cadence: .interval(seconds: 60, needsBaseline: false))
        let early = handle(&revealed, .lowPowerMode(true), after: 0, date: 0)
        #expect(early == .unchanged)
        let reveal = handle(&revealed, .shown(true), after: 1, date: 1)
        #expect(reveal.timer == .arm(start + .seconds(121), tolerance: .seconds(12)))

        // The clock does not poll: Low Power Mode changes nothing.
        var clock = visible(.clock(showsSeconds: false))
        let clockLow = handle(&clock, .lowPowerMode(true), after: 1, date: 31)
        #expect(clockLow == .unchanged)
    }

    @Test("CPU takes its second sample one second after a reveal")
    func cpuSecondSample() {
        var policy = WidgetRefreshPolicy(cadence: .interval(seconds: 5, needsBaseline: true))
        let reveal = handle(&policy, .shown(true), after: 0, date: 0)
        #expect(reveal.refreshes)
        #expect(reveal.timer == .arm(start + .seconds(1), tolerance: .milliseconds(100)))

        let second = handle(&policy, .timerFired, after: 1, date: 1)
        #expect(second.refreshes)
        #expect(second.timer == .arm(start + .seconds(6), tolerance: .milliseconds(500)))

        let third = handle(&policy, .timerFired, after: 6, date: 6)
        #expect(third.timer == .arm(start + .seconds(11), tolerance: .milliseconds(500)))

        // Hidden and revealed again: a new baseline.
        _ = handle(&policy, .shown(false), after: 7, date: 7)
        let again = handle(&policy, .shown(true), after: 100, date: 100)
        #expect(again.refreshes)
        #expect(again.timer == .arm(start + .seconds(101), tolerance: .milliseconds(100)))
    }

    @Test("A clock change refreshes and re-arms a visible widget")
    func clockChangeRefreshes() {
        var policy = visible(.clock(showsSeconds: false), atSecond: 30)
        // The user set the clock back an hour.
        let changed = handle(&policy, .clockChanged, after: 10, date: -3_570)
        #expect(changed.refreshes)
        #expect(changed.timer == .arm(start + .seconds(10) + .milliseconds(30_050), tolerance: .seconds(6)))

        _ = handle(&policy, .shown(false), after: 11, date: -3_569)
        let hidden = handle(&policy, .clockChanged, after: 12, date: -3_568)
        #expect(hidden == .unchanged)
    }

    @Test("Turning the module off cancels everything")
    func moduleOffCancelsEverything() {
        var policy = visible(.interval(seconds: 60, needsBaseline: false))
        let off = handle(&policy, .moduleEnabled(false), after: 5, date: 5)
        #expect(off.timer == .cancel)
        #expect(off.marksUnavailable)
        #expect(!off.refreshes)
        #expect(!policy.isVisible)

        let stray = handle(&policy, .timerFired, after: 60, date: 60)
        #expect(!stray.refreshes)
        #expect(stray.timer == .cancel)

        // Showing a widget of a module that is off arms nothing.
        _ = handle(&policy, .shown(false), after: 61, date: 61)
        let shown = handle(&policy, .shown(true), after: 62, date: 62)
        #expect(shown == .unchanged)

        // Switched on again, the widget is visible and refreshes.
        let on = handle(&policy, .moduleEnabled(true), after: 63, date: 63)
        #expect(on.refreshes)
        #expect(on.timer == .arm(start + .seconds(123), tolerance: .seconds(6)))
    }

    @Test("A changed cadence reads again and arms the new cadence")
    func cadenceChange() {
        var policy = visible(.interval(seconds: 60, needsBaseline: false))
        let command = handle(&policy, .cadenceChanged(.interval(seconds: 5, needsBaseline: true)), after: 3, date: 3)
        #expect(command.refreshes)
        #expect(command.timer == .arm(start + .seconds(4), tolerance: .milliseconds(100)))

        // While hidden nothing is armed.
        _ = handle(&policy, .shown(false), after: 4, date: 4)
        let hidden = handle(&policy, .cadenceChanged(.clock(showsSeconds: false)), after: 5, date: 5)
        #expect(hidden == .unchanged)
        let reveal = handle(&policy, .shown(true), after: 6, date: 36)
        #expect(reveal.timer == .arm(start + .seconds(6) + .milliseconds(24_050), tolerance: .seconds(6)))
    }

    // MARK: The sampled cadence (D-01, D-12)

    private let sampledRequest = ReadoutRequest(metrics: [.cpu], intervalSeconds: 5, needsBaseline: true)

    @Test("A sampled widget registers when visible and arms no timer")
    func sampledRegistersWhenVisible() {
        var policy = WidgetRefreshPolicy(cadence: .sampled(sampledRequest))
        let reveal = handle(&policy, .shown(true), after: 0, date: 0)
        #expect(reveal.readout == .register(sampledRequest))
        #expect(reveal.marksUnavailable)
        #expect(!reveal.refreshes)
        #expect(reveal.timer == .cancel)
        #expect(policy.isVisible)

        let again = handle(&policy, .shown(true), after: 1, date: 1)
        #expect(again == .unchanged)

        let hide = handle(&policy, .shown(false), after: 2, date: 2)
        #expect(hide.readout == .unregister)
        #expect(hide.marksUnavailable)
        #expect(hide.timer == .cancel)

        let hiddenAgain = handle(&policy, .shown(false), after: 3, date: 3)
        #expect(hiddenAgain == .unchanged)
    }

    @Test("A sampled widget unregisters on a pause and registers only after the settle wait")
    func sampledPausesAndSettles() {
        var policy = WidgetRefreshPolicy(cadence: .sampled(sampledRequest))
        _ = handle(&policy, .shown(true), after: 0, date: 0)

        let lock = handle(&policy, .paused(true), after: 10, date: 10)
        #expect(lock.readout == .unregister)
        #expect(lock.marksUnavailable)

        // The Mac is in use again: only the settle timer, no register yet.
        let unlock = handle(&policy, .paused(false), after: 40, date: 40)
        #expect(unlock.readout == .keep)
        #expect(unlock.timer == .arm(start + .seconds(40) + SystemActivity.settleDelay, tolerance: .milliseconds(200)))
        #expect(!policy.isVisible)

        let early = handle(&policy, .timerFired, after: 41, date: 41)
        #expect(early.readout == .keep)
        #expect(early.timer == .arm(start + .seconds(40) + SystemActivity.settleDelay, tolerance: .milliseconds(200)))

        let settled = handle(&policy, .timerFired, after: 42, date: 42)
        #expect(settled.readout == .register(sampledRequest))
        #expect(settled.marksUnavailable)
        #expect(settled.timer == .cancel)
        #expect(policy.isVisible)
    }

    @Test("A hidden or locked sampled widget never registers")
    func sampledHiddenNeverRegisters() {
        var policy = WidgetRefreshPolicy(cadence: .sampled(sampledRequest))
        _ = handle(&policy, .paused(true), after: 0, date: 0)
        let shown = handle(&policy, .shown(true), after: 1, date: 1)
        #expect(shown.readout == .keep)

        var off = WidgetRefreshPolicy(cadence: .sampled(sampledRequest))
        _ = handle(&off, .moduleEnabled(false), after: 0, date: 0)
        let offShown = handle(&off, .shown(true), after: 1, date: 1)
        #expect(offShown.readout == .keep)
        let on = handle(&off, .moduleEnabled(true), after: 2, date: 2)
        #expect(on.readout == .register(sampledRequest))
        let gone = handle(&off, .moduleEnabled(false), after: 3, date: 3)
        #expect(gone.readout == .unregister)
    }

    @Test("A changed request registers the new one; the same one changes nothing")
    func sampledRequestChange() {
        var policy = visible(.sampled(sampledRequest))
        let other = ReadoutRequest(metrics: [.network], intervalSeconds: 2, needsBaseline: true)
        let changed = handle(&policy, .cadenceChanged(.sampled(other)), after: 1, date: 31)
        #expect(changed.readout == .register(other))
        #expect(changed.marksUnavailable)
        #expect(changed.timer == .cancel)

        let same = handle(&policy, .cadenceChanged(.sampled(other)), after: 2, date: 32)
        #expect(same == .unchanged)
    }

    @Test("Changing between sampled and polling hands the timer over")
    func sampledToIntervalAndBack() {
        var policy = visible(.sampled(sampledRequest))
        let toInterval = handle(
            &policy,
            .cadenceChanged(.interval(seconds: 10, needsBaseline: false)),
            after: 1,
            date: 31
        )
        #expect(toInterval.readout == .unregister)
        #expect(toInterval.refreshes)
        #expect(toInterval.timer == .arm(start + .seconds(11), tolerance: .seconds(1)))

        let back = handle(&policy, .cadenceChanged(.sampled(sampledRequest)), after: 5, date: 35)
        #expect(back.readout == .register(sampledRequest))
        #expect(back.timer == .cancel)
        #expect(back.marksUnavailable)
        #expect(!back.refreshes)

        // Hidden: the change registers nothing.
        _ = handle(&policy, .shown(false), after: 6, date: 36)
        let hidden = handle(&policy, .cadenceChanged(.interval(seconds: 10, needsBaseline: false)), after: 7, date: 37)
        #expect(hidden == .unchanged)
    }

    @Test("A sampled widget ignores a timer and the clock, refreshes on a source event, ignores Low Power Mode")
    func sampledOtherEvents() {
        var policy = visible(.sampled(sampledRequest))
        let fired = handle(&policy, .timerFired, after: 5, date: 35)
        #expect(fired == .unchanged)
        let clock = handle(&policy, .clockChanged, after: 6, date: 36)
        #expect(clock == .unchanged)
        let source = handle(&policy, .sourceChanged, after: 7, date: 37)
        #expect(source.refreshes)
        #expect(source.readout == .keep)
        let low = handle(&policy, .lowPowerMode(true), after: 8, date: 38)
        #expect(low == .unchanged)
        let normal = handle(&policy, .lowPowerMode(false), after: 9, date: 39)
        #expect(normal == .unchanged)
    }

    @Test("A source event means nothing to a hidden sampled widget")
    func sampledSourceWhileHidden() {
        var policy = WidgetRefreshPolicy(cadence: .sampled(sampledRequest))
        let event = handle(&policy, .sourceChanged, after: 0, date: 0)
        #expect(event == .unchanged)
    }

    @Test("A sampled cadence has no timer of its own")
    func sampledNextFire() {
        let fire = WidgetRefreshPolicy.nextFire(
            for: .sampled(sampledRequest),
            date: date(0),
            calendar: calendar,
            isLowPowerMode: false
        )
        #expect(fire == nil)
    }

    // MARK: The cadence of a definition

    /// The cadence of a CPU text widget: the shared monitor feeds it (D-01), with a baseline.
    private func cpuCadence(seconds: Int) -> WidgetCadence {
        .sampled(ReadoutRequest(metrics: [.cpu], intervalSeconds: seconds, needsBaseline: true))
    }

    /// The cadence of a network speed widget: the shared monitor feeds it, with a baseline.
    private func networkCadence(seconds: Int) -> WidgetCadence {
        .sampled(ReadoutRequest(metrics: [.network], intervalSeconds: seconds, needsBaseline: true))
    }

    /// The cadence of a disk activity widget: the shared monitor feeds it, with a baseline.
    private func diskCadence(seconds: Int) -> WidgetCadence {
        .sampled(ReadoutRequest(metrics: [.diskActivity], intervalSeconds: seconds, needsBaseline: true))
    }

    /// The cadence of a memory or disk space widget: the shared monitor feeds it, with no baseline.
    private func memoryCadence(_ metrics: Set<ReadoutMetric>, seconds: Int) -> WidgetCadence {
        .sampled(ReadoutRequest(metrics: metrics, intervalSeconds: seconds, needsBaseline: false))
    }

    @Test("The cadence follows the source of the definition")
    func cadenceFromDefinition() {
        let now = date(0)
        func make(_ source: WidgetSource, preset: WidgetPreset? = nil, refreshSeconds: Int? = nil) -> WidgetDefinition {
            var made = WidgetDefinition.text(source: source, uses24HourClock: true, now: now)
            if let preset {
                made.preset = preset
            }
            if let refreshSeconds {
                made.refreshSeconds = refreshSeconds
            }
            return made
        }

        #expect(WidgetCadence(definition: make(.dateTime)) == .clock(showsSeconds: false))
        var withSeconds = make(.dateTime)
        withSeconds.showsSeconds = true
        #expect(WidgetCadence(definition: withSeconds) == .clock(showsSeconds: true))
        // The battery and the thermal state announce their changes themselves: sampled, no interval
        // and no baseline, every format (D-02, D-10).
        for preset in WidgetSource.battery.presets {
            #expect(WidgetCadence(definition: make(.battery, preset: preset)) == memoryCadence([.power], seconds: 0))
        }
        #expect(WidgetCadence(definition: make(.thermalState)) == memoryCadence([.thermal], seconds: 0))
        #expect(WidgetCadence(definition: make(.cpu)) == cpuCadence(seconds: 5))
        #expect(WidgetCadence(definition: make(.cpu, refreshSeconds: 30)) == cpuCadence(seconds: 30))
        // The per core cluster format reads the cores instead of the total (MON-01).
        #expect(
            WidgetCadence(definition: make(.cpu, preset: .perCluster))
                == .sampled(ReadoutRequest(metrics: [.cpuCores], intervalSeconds: 5, needsBaseline: true))
        )
        #expect(WidgetCadence(definition: make(.networkSpeed)) == networkCadence(seconds: 2))
        #expect(WidgetCadence(definition: make(.networkSpeed, refreshSeconds: 30)) == networkCadence(seconds: 30))
        #expect(WidgetCadence(definition: make(.networkSpeed, refreshSeconds: 1)) == networkCadence(seconds: 2))
        #expect(WidgetCadence(definition: make(.networkSpeed, refreshSeconds: 999)) == networkCadence(seconds: 60))
        #expect(WidgetCadence(definition: make(.diskActivity)) == diskCadence(seconds: 2))
        #expect(WidgetCadence(definition: make(.diskActivity, refreshSeconds: 10)) == diskCadence(seconds: 10))
        #expect(WidgetCadence(definition: make(.diskActivity, refreshSeconds: 1)) == diskCadence(seconds: 2))
        #expect(WidgetCadence(definition: make(.gpuLoad)) == memoryCadence([.gpu], seconds: 5))
        #expect(WidgetCadence(definition: make(.gpuLoad, refreshSeconds: 30)) == memoryCadence([.gpu], seconds: 30))
        #expect(WidgetCadence(definition: make(.gpuLoad, refreshSeconds: 1)) == memoryCadence([.gpu], seconds: 2))
        // The accessories' lowest level: the 5-minute wait of the Accessory alerts; the power-source
        // events and the rest while the read is off come from the monitor (D-26, D-27), and the
        // tuned interval of a stored definition changes nothing.
        #expect(WidgetCadence(definition: make(.deviceBattery)) == memoryCadence([.deviceBattery], seconds: 300))
        #expect(
            WidgetCadence(definition: make(.deviceBattery, refreshSeconds: 5)) == memoryCadence([.deviceBattery], seconds: 300)
        )
        #expect(WidgetCadence(definition: make(.memory)) == memoryCadence([.memory], seconds: 10))
        #expect(WidgetCadence(definition: make(.memory, preset: .gigabytesUsed)) == memoryCadence([.memory], seconds: 10))
        #expect(WidgetCadence(definition: make(.memory, preset: .swapUsed)) == memoryCadence([.swap], seconds: 10))
        #expect(
            WidgetCadence(definition: make(.memory, preset: .swapUsed, refreshSeconds: 30))
                == memoryCadence([.swap], seconds: 30)
        )
        // Pressure is fed by the system's event: no interval, no baseline (D-10).
        #expect(WidgetCadence(definition: make(.memory, preset: .pressure)) == memoryCadence([.memoryPressure], seconds: 0))
        #expect(WidgetCadence(definition: make(.memory, preset: .pressure, refreshSeconds: 30)) == memoryCadence([.memoryPressure], seconds: 0))
        #expect(WidgetCadence(definition: make(.uptime)) == .interval(seconds: 60, needsBaseline: false))
        #expect(WidgetCadence(definition: make(.freeDisk)) == memoryCadence([.diskSpace], seconds: 300))
        #expect(WidgetCadence(definition: make(.freeDisk, preset: .percentFree)) == memoryCadence([.diskSpace], seconds: 300))
        let countdown = make(.countdown)
        let target = countdown.countdownTarget ?? now
        #expect(WidgetCadence(definition: countdown) == .countdown(target: target))
        #expect(WidgetCadence(definition: WidgetDefinition.button(title: "Run")) == .eventOnly)
    }

    @Test("An interval outside the range of the source is brought into it")
    func intervalIsClamped() {
        var cpu = WidgetDefinition.text(source: .cpu, uses24HourClock: true, now: date(0))
        cpu.refreshSeconds = 0
        #expect(WidgetCadence(definition: cpu) == cpuCadence(seconds: 2))
        cpu.refreshSeconds = Int.max
        #expect(WidgetCadence(definition: cpu) == cpuCadence(seconds: 60))

        var memory = WidgetDefinition.text(source: .memory, uses24HourClock: true, now: date(0))
        memory.refreshSeconds = 1
        #expect(WidgetCadence(definition: memory) == memoryCadence([.memory], seconds: 5))
        memory.refreshSeconds = nil
        #expect(WidgetCadence(definition: memory) == memoryCadence([.memory], seconds: 10))
    }

    @Test("A countdown without a moment has nothing to count")
    func countdownWithoutTarget() {
        var countdown = WidgetDefinition.text(source: .countdown, uses24HourClock: true, now: date(0))
        countdown.countdownTarget = nil
        #expect(WidgetCadence(definition: countdown) == .eventOnly)
    }
}
