import Foundation
import Testing
@testable import HolzBarCore

/// On macOS 26 holzBar finds the app behind each menu bar item through Accessibility, and
/// one app that answers slowly must not hold up every item read.
@Suite("SourcePIDLookupSchedule")
struct SourcePIDLookupScheduleTests {
    // The schedule is changed outside `#expect`, whose expansion cannot call a mutating method.

    private let start = ContinuousClock.now
    private let ownPID: pid_t = 100
    private let app: pid_t = 200

    @Test("An app that answers in time is always asked")
    func answeredAppIsAsked() {
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        #expect(schedule.mayAsk(app, at: start))
        schedule.record(app, timedOut: false, at: start)
        #expect(schedule.mayAsk(app, at: start))
    }

    @Test("A timeout pauses the app for 10 s")
    func timeoutPauses() {
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        schedule.record(app, timedOut: true, at: start)
        #expect(!schedule.mayAsk(app, at: start + .milliseconds(9_999)))
        #expect(schedule.mayAsk(app, at: start + .seconds(10)))
        #expect(schedule.mayAsk(300, at: start))
    }

    @Test("Timeouts in a row double the pause up to 60 s")
    func pauseDoubles() {
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        var now = start
        for expected in [10, 20, 40, 60, 60] {
            schedule.record(app, timedOut: true, at: now)
            #expect(!schedule.mayAsk(app, at: now + .seconds(expected) - .milliseconds(1)))
            #expect(schedule.mayAsk(app, at: now + .seconds(expected)))
            now += .seconds(expected)
        }
    }

    @Test("An answer in time ends the pause and starts the doubling over")
    func answerResets() {
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        schedule.record(app, timedOut: true, at: start)
        schedule.record(app, timedOut: true, at: start + .seconds(10))
        schedule.record(app, timedOut: false, at: start + .seconds(30))
        #expect(schedule.mayAsk(app, at: start + .seconds(30)))
        schedule.record(app, timedOut: true, at: start + .seconds(31))
        #expect(schedule.mayAsk(app, at: start + .seconds(41)))
    }

    @Test("holzBar's own process is never paused")
    func ownProcessIsNeverPaused() {
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        schedule.record(ownPID, timedOut: true, at: start)
        #expect(schedule.mayAsk(ownPID, at: start))
    }

    @Test("Apps that quit are forgotten")
    func quitAppsAreForgotten() {
        var schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        schedule.record(app, timedOut: true, at: start)
        schedule.record(app, timedOut: true, at: start + .seconds(10))
        schedule.retain(running: [ownPID])
        #expect(schedule.mayAsk(app, at: start + .seconds(10)))
        schedule.record(app, timedOut: true, at: start + .seconds(10))
        #expect(!schedule.mayAsk(app, at: start + .seconds(20) - .milliseconds(1)))
        #expect(schedule.mayAsk(app, at: start + .seconds(20)))
    }

    @Test("A call counts as timed out from 450 ms")
    func timeoutThreshold() {
        #expect(!SourcePIDLookupSchedule.didTimeOut(after: .milliseconds(449)))
        #expect(SourcePIDLookupSchedule.didTimeOut(after: .milliseconds(450)))
        #expect(SourcePIDLookupSchedule.didTimeOut(after: .seconds(6)))
    }

    @Test("A lookup stops asking after 2 s")
    func budget() {
        #expect(!SourcePIDLookupSchedule.isOverBudget(startedAt: start, now: start + .milliseconds(1_999)))
        #expect(SourcePIDLookupSchedule.isOverBudget(startedAt: start, now: start + .seconds(2)))
    }

    @Test("One app is asked for 1 s at most in a scan")
    func appBudget() {
        #expect(!SourcePIDLookupSchedule.isOverAppBudget(startedAt: start, now: start + .milliseconds(999)))
        #expect(SourcePIDLookupSchedule.isOverAppBudget(startedAt: start, now: start + .seconds(1)))
    }

    @Test("Every app but holzBar's own process may be paused")
    func mayPause() {
        let schedule = SourcePIDLookupSchedule(ownPID: ownPID)
        #expect(schedule.mayPause(app))
        #expect(!schedule.mayPause(ownPID))
    }

    @Test("A window not found is scanned again after 30 s, or once a skipped app can be asked")
    func rescan() {
        #expect(!SourcePIDLookupSchedule.shouldRescan(failedAt: start, now: start + .seconds(29), skippedAppIsReady: false))
        #expect(SourcePIDLookupSchedule.shouldRescan(failedAt: start, now: start + .seconds(30), skippedAppIsReady: false))
        #expect(SourcePIDLookupSchedule.shouldRescan(failedAt: start, now: start + .seconds(1), skippedAppIsReady: true))
    }

    @Test("An app that has not reported finishing launching 10 s after its process started never will")
    func neverFinishesLaunching() {
        #expect(!SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching: false, runningFor: .zero))
        #expect(!SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching: false, runningFor: .milliseconds(9_999)))
        #expect(SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching: false, runningFor: .seconds(10)))
        #expect(SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching: false, runningFor: .seconds(86_400)))
        // A launched app, whatever its running time.
        #expect(!SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching: true, runningFor: .seconds(86_400)))
        // A process whose start time cannot be read still counts as launching.
        #expect(!SourcePIDLookupSchedule.neverFinishesLaunching(isFinishedLaunching: false, runningFor: nil))
    }

    @Test("The limits keep one lookup short")
    func limits() {
        #expect(SourcePIDLookupSchedule.messagingTimeout == 0.5)
        #expect(SourcePIDLookupSchedule.timeoutThreshold < .milliseconds(500))
        #expect(SourcePIDLookupSchedule.maximumChildren > 0)
        #expect(SourcePIDLookupSchedule.lookupBudget <= .seconds(2))
        // The first app a continued scan asks is done with before the scan stops, even
        // after one more call that runs into the timeout.
        #expect(SourcePIDLookupSchedule.appBudget + .milliseconds(600) < SourcePIDLookupSchedule.lookupBudget)
    }
}
