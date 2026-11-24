import Foundation
import Testing
@testable import HolzBarCore

@Suite("DockBadgeRefresh")
struct DockBadgeRefreshTests {
    private typealias Instant = ContinuousClock.Instant

    private let t0 = ContinuousClock.now

    /// A refresh that is visible and whose start read has been taken and finished without a
    /// change, 0.1 s after `t0`. Its timer is pending 30 s after that.
    private func probing() -> DockBadgeRefresh {
        var refresh = DockBadgeRefresh()
        _ = refresh.visible(true, at: t0)
        #expect(refresh.fire(at: t0) == .start)
        _ = refresh.passFinished(trigger: .start, changed: false, failed: false, at: t0 + .milliseconds(100))
        return refresh
    }

    /// Runs the timer pass that is due at `at`, with the given result, and returns the action.
    private func timerPass(_ refresh: inout DockBadgeRefresh, at: Instant, changed: Bool) -> DockBadgeRefresh.Action {
        #expect(refresh.fire(at: at) == .timer)
        return refresh.passFinished(trigger: .timer, changed: changed, failed: false, at: at)
    }

    /// A refresh in polling mode, 0.1 s after `t0` plus 30 s: a timer pass found a change.
    private func polling() -> (DockBadgeRefresh, Instant) {
        var refresh = probing()
        let due = t0 + .milliseconds(100) + .seconds(30)
        _ = timerPass(&refresh, at: due, changed: true)
        return (refresh, due)
    }

    /// A refresh in following mode, and the instant of its last pass.
    private func following() -> (DockBadgeRefresh, Instant) {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.notified(at: at)
        let due = at + DockBadgeRefresh.coalescing
        #expect(refresh.fire(at: due) == .notification)
        let action = refresh.passFinished(trigger: .notification, changed: true, failed: false, at: due)
        #expect(action == .none)
        return (refresh, due)
    }

    // MARK: Start

    @Test("Becoming visible reads at once in probing mode, and becoming visible again does nothing")
    func startsProbing() {
        var refresh = DockBadgeRefresh()
        #expect(refresh.visible(true, at: t0) == .readAt(t0))
        #expect(refresh.mode == .probing)
        #expect(!refresh.showsPollingLine)
        #expect(refresh.visible(true, at: t0 + .seconds(1)) == .none)
    }

    @Test("Hiding what was never shown does nothing")
    func hiddenStaysHidden() {
        var refresh = DockBadgeRefresh()
        #expect(refresh.visible(false, at: t0) == .none)
        #expect(refresh.fire(at: t0) == nil)
    }

    @Test("The first read is a start read, and the next one is 30 seconds after it")
    func startThenBase() {
        var refresh = DockBadgeRefresh()
        _ = refresh.visible(true, at: t0)
        #expect(refresh.fire(at: t0) == .start)
        let end = t0 + .milliseconds(200)
        #expect(refresh.passFinished(trigger: .start, changed: false, failed: false, at: end) == .readAt(end + .seconds(30)))
    }

    @Test("A start pass that found a change does not change the mode")
    func startChangeIsNoEvidence() {
        var refresh = DockBadgeRefresh()
        _ = refresh.visible(true, at: t0)
        _ = refresh.fire(at: t0)
        let action = refresh.passFinished(trigger: .start, changed: true, failed: false, at: t0)
        #expect(action == .readAt(t0 + .seconds(30)))
        #expect(refresh.mode == .probing)
    }

    // MARK: Timer and back-off

    @Test("A timer pass without a change backs off: 60 seconds, then 120, never more")
    func backOff() {
        var refresh = probing()
        var due = t0 + .milliseconds(100) + .seconds(30)
        for seconds in [60, 120, 120, 120] {
            let action = timerPass(&refresh, at: due, changed: false)
            #expect(action == .readAt(due + .seconds(seconds)))
            due += .seconds(seconds)
        }
        #expect(refresh.mode == .probing)
        #expect(!refresh.showsPollingLine)
    }

    @Test("A timer pass that found a change means the Dock is silent: polling, the line, 30 seconds")
    func timerChangeIsPolling() {
        var refresh = probing()
        let due = t0 + .milliseconds(100) + .seconds(30)
        #expect(timerPass(&refresh, at: due, changed: true) == .readAt(due + .seconds(30)))
        #expect(refresh.mode == .polling)
        #expect(refresh.showsPollingLine)
    }

    @Test("In polling the back-off goes on and starts again at 30 seconds after a change")
    func pollingBackOff() {
        var (refresh, due) = polling()
        due += .seconds(30)
        #expect(timerPass(&refresh, at: due, changed: false) == .readAt(due + .seconds(60)))
        due += .seconds(60)
        #expect(timerPass(&refresh, at: due, changed: false) == .readAt(due + .seconds(120)))
        due += .seconds(120)
        #expect(timerPass(&refresh, at: due, changed: true) == .readAt(due + .seconds(30)))
        #expect(refresh.mode == .polling)
    }

    @Test("A failed timer pass backs off and does not change the mode, even with a change reported")
    func failedTimerPass() {
        var refresh = probing()
        let due = t0 + .milliseconds(100) + .seconds(30)
        #expect(refresh.fire(at: due) == .timer)
        let action = refresh.passFinished(trigger: .timer, changed: true, failed: true, at: due)
        #expect(action == .readAt(due + .seconds(60)))
        #expect(refresh.mode == .probing)
    }

    @Test("Polling ends with the visible state: hiding clears the line")
    func hidingClearsPolling() {
        var (refresh, due) = polling()
        #expect(refresh.showsPollingLine)
        #expect(refresh.visible(false, at: due) == .stop)
        #expect(!refresh.showsPollingLine)
    }

    // MARK: Notifications

    @Test("A notification gives a read half a second later, and a second one in that window gives none")
    func coalescing() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        #expect(refresh.notified(at: at) == .readAt(at + .milliseconds(500)))
        #expect(refresh.notified(at: at + .milliseconds(100)) == .none)
        #expect(refresh.notified(at: at + .milliseconds(400)) == .none)
        #expect(refresh.fire(at: at + .milliseconds(499)) == nil)
        #expect(refresh.fire(at: at + .milliseconds(500)) == .notification)
    }

    @Test("Reads that notifications trigger are never closer than two seconds")
    func spacing() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.notified(at: at)
        let due = at + .milliseconds(500)
        #expect(refresh.fire(at: due) == .notification)
        #expect(refresh.notified(at: due + .milliseconds(100)) == .readAt(due + .seconds(2)))
        #expect(refresh.fire(at: due + .seconds(1)) == nil)
        #expect(refresh.passFinished(trigger: .notification, changed: false, failed: false, at: due + .milliseconds(300)) == .none)
        #expect(refresh.fire(at: due + .seconds(2)) == .notification)
    }

    @Test("A notification pass that found a change means the Dock announces: following, and no timer")
    func notificationChangeIsFollowing() {
        let (refresh, due) = following()
        var next = refresh
        #expect(next.mode == .following)
        #expect(!next.showsPollingLine)
        #expect(next.fire(at: due + .seconds(10_000)) == nil)
    }

    @Test("In following a pass without a change arms nothing either")
    func followingPassArmsNothing() {
        var (refresh, due) = following()
        due += .seconds(40)
        #expect(refresh.notified(at: due) == .readAt(due + .milliseconds(500)))
        #expect(refresh.fire(at: due + .milliseconds(500)) == .notification)
        let end = due + .milliseconds(600)
        #expect(refresh.passFinished(trigger: .notification, changed: false, failed: false, at: end) == .none)
        #expect(refresh.mode == .following)
    }

    @Test("A notification pass that found a change also ends polling")
    func notificationChangeEndsPolling() {
        var (refresh, due) = polling()
        due += .seconds(5)
        _ = refresh.notified(at: due)
        #expect(refresh.fire(at: due + .milliseconds(500)) == .notification)
        let action = refresh.passFinished(trigger: .notification, changed: true, failed: false, at: due + .milliseconds(600))
        #expect(action == .none)
        #expect(refresh.mode == .following)
        #expect(!refresh.showsPollingLine)
    }

    @Test("A notification pass without a change or with a failure keeps the mode and the timer")
    func notificationWithoutEvidence() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.notified(at: at)
        #expect(refresh.fire(at: at + .milliseconds(500)) == .notification)
        let timer = t0 + .milliseconds(100) + .seconds(30)
        let end = at + .milliseconds(600)
        #expect(refresh.passFinished(trigger: .notification, changed: false, failed: false, at: end) == .readAt(timer))
        #expect(refresh.mode == .probing)

        _ = refresh.notified(at: at + .seconds(10))
        #expect(refresh.fire(at: at + .seconds(10) + .milliseconds(500)) == .notification)
        let failed = refresh.passFinished(trigger: .notification, changed: true, failed: true, at: at + .seconds(11))
        #expect(failed == .readAt(timer))
        #expect(refresh.mode == .probing)
    }

    @Test("Becoming visible again starts probing again, and the timer comes back for the start pass")
    func visibleAgainProbes() {
        var (refresh, due) = following()
        #expect(refresh.visible(false, at: due) == .stop)
        let back = due + .seconds(60)
        #expect(refresh.visible(true, at: back) == .readAt(back))
        #expect(refresh.mode == .probing)
        #expect(refresh.fire(at: back) == .start)
        let end = back + .milliseconds(200)
        #expect(refresh.passFinished(trigger: .start, changed: false, failed: false, at: end) == .readAt(end + .seconds(30)))
    }

    // MARK: Activation

    @Test("An activation gives a read a second later in every mode")
    func activation() {
        var inProbing = probing()
        let at = t0 + .seconds(5)
        #expect(inProbing.activated(at: at) == .readAt(at + .seconds(1)))
        #expect(inProbing.fire(at: at + .seconds(1)) == .activation)

        var (inPolling, _) = polling()
        let later = t0 + .seconds(40)
        #expect(inPolling.activated(at: later) == .readAt(later + .seconds(1)))
        #expect(inPolling.fire(at: later + .seconds(1)) == .activation)

        var (inFollowing, _) = following()
        #expect(inFollowing.activated(at: later) == .readAt(later + .seconds(1)))
        #expect(inFollowing.fire(at: later + .seconds(1)) == .activation)
    }

    @Test("A second activation within the wait gives no second read")
    func activationCoalesces() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.activated(at: at)
        #expect(refresh.activated(at: at + .milliseconds(300)) == .none)
    }

    @Test("An activation pass that found a change is no evidence of anything")
    func activationChangeIsNoEvidence() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.activated(at: at)
        #expect(refresh.fire(at: at + .seconds(1)) == .activation)
        _ = refresh.passFinished(trigger: .activation, changed: true, failed: false, at: at + .seconds(1))
        #expect(refresh.mode == .probing)
    }

    @Test("An activation pass in following arms no timer")
    func activationInFollowingArmsNothing() {
        var (refresh, due) = following()
        let at = due + .seconds(50)
        _ = refresh.activated(at: at)
        #expect(refresh.fire(at: at + .seconds(1)) == .activation)
        #expect(refresh.passFinished(trigger: .activation, changed: true, failed: false, at: at + .seconds(1)) == .none)
        #expect(refresh.mode == .following)
    }

    @Test("A timer that an event read took along is armed again after that read")
    func timerTakenAlong() {
        var refresh = probing()
        // The timer, due 30.1 seconds in, was not taken in time (a pass was running).
        let at = t0 + .seconds(100)
        _ = refresh.activated(at: at)
        #expect(refresh.fire(at: at + .seconds(1)) == .activation)
        let end = at + .seconds(1)
        #expect(refresh.passFinished(trigger: .activation, changed: false, failed: false, at: end) == .readAt(end + .seconds(30)))
    }

    @Test("A notification and an activation due together make one read, and the activation wins")
    func dueTogether() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.activated(at: at)
        _ = refresh.notified(at: at + .milliseconds(200))
        #expect(refresh.fire(at: at + .seconds(1)) == .activation)
        // Both were taken by that read.
        #expect(refresh.passFinished(trigger: .activation, changed: false, failed: false, at: at + .seconds(1)) == .readAt(t0 + .milliseconds(100) + .seconds(30)))
    }

    // MARK: Not visible

    @Test("Hiding stops everything and clears every pending read")
    func hiding() {
        var refresh = probing()
        let at = t0 + .seconds(5)
        _ = refresh.notified(at: at)
        _ = refresh.activated(at: at)
        #expect(refresh.visible(false, at: at) == .stop)
        #expect(refresh.fire(at: at + .seconds(1000)) == nil)
    }

    @Test("While not visible nothing is armed: a notification, an activation or a result gives none")
    func nothingWhileHidden() {
        var refresh = probing()
        _ = refresh.visible(false, at: t0 + .seconds(1))
        let at = t0 + .seconds(2)
        #expect(refresh.notified(at: at) == .none)
        #expect(refresh.activated(at: at) == .none)
        #expect(refresh.passFinished(trigger: .timer, changed: true, failed: false, at: at) == .none)
        #expect(refresh.passFinished(trigger: .notification, changed: true, failed: false, at: at) == .none)
        #expect(refresh.fire(at: at + .seconds(1000)) == nil)
        #expect(refresh.mode == .probing)
    }

    @Test("While a pass runs no other starts, and the next read is armed when it finishes")
    func onePassAtATime() {
        var refresh = DockBadgeRefresh()
        _ = refresh.visible(true, at: t0)
        #expect(refresh.fire(at: t0) == .start)
        #expect(refresh.fire(at: t0 + .seconds(5)) == nil)
        let end = t0 + .seconds(1)
        #expect(refresh.passFinished(trigger: .start, changed: false, failed: false, at: end) == .readAt(end + .seconds(30)))
        #expect(refresh.fire(at: end + .seconds(30)) == .timer)
    }

    @Test("Hiding during a pass lets the next visible state read again")
    func hidingDuringAPass() {
        var refresh = DockBadgeRefresh()
        _ = refresh.visible(true, at: t0)
        #expect(refresh.fire(at: t0) == .start)
        #expect(refresh.visible(false, at: t0 + .milliseconds(10)) == .stop)
        #expect(refresh.visible(true, at: t0 + .seconds(5)) == .readAt(t0 + .seconds(5)))
        #expect(refresh.fire(at: t0 + .seconds(5)) == .start)
    }

    // MARK: Failures

    @Test("Three failed reads in a row set the failure, and a read that works clears it")
    func failureAfterThree() {
        var refresh = probing()
        var at = t0 + .seconds(2)
        for _ in 1...3 {
            #expect(!refresh.readerFailed)
            _ = refresh.notified(at: at)
            #expect(refresh.fire(at: at + .milliseconds(500)) == .notification)
            _ = refresh.passFinished(trigger: .notification, changed: false, failed: true, at: at + .milliseconds(600))
            at += .seconds(3)
        }
        #expect(refresh.readerFailed)
        _ = refresh.notified(at: at)
        #expect(refresh.fire(at: at + .milliseconds(500)) == .notification)
        _ = refresh.passFinished(trigger: .notification, changed: false, failed: false, at: at + .milliseconds(600))
        #expect(!refresh.readerFailed)
    }

    @Test("A read that works in between starts the count again")
    func failureCountResets() {
        var refresh = probing()
        var at = t0 + .seconds(2)
        for failed in [true, true, false, true, true] {
            _ = refresh.notified(at: at)
            #expect(refresh.fire(at: at + .milliseconds(500)) == .notification)
            _ = refresh.passFinished(trigger: .notification, changed: false, failed: failed, at: at + .milliseconds(600))
            at += .seconds(3)
        }
        #expect(!refresh.readerFailed)
    }

    @Test("The failure survives hiding and showing and clears on the next pass that works")
    func failureSurvivesVisibility() {
        var refresh = DockBadgeRefresh()
        var at = t0
        for _ in 1...3 {
            _ = refresh.visible(true, at: at)
            #expect(refresh.fire(at: at) == .start)
            _ = refresh.passFinished(trigger: .start, changed: false, failed: true, at: at)
            _ = refresh.visible(false, at: at + .seconds(1))
            at += .seconds(60)
        }
        #expect(refresh.readerFailed)
        _ = refresh.visible(true, at: at)
        #expect(refresh.readerFailed)
        #expect(refresh.fire(at: at) == .start)
        _ = refresh.passFinished(trigger: .start, changed: false, failed: false, at: at)
        #expect(!refresh.readerFailed)
    }

    @Test("Reading the Dock's list in the settings clears the failure")
    func readWorkedClears() {
        var refresh = DockBadgeRefresh()
        for _ in 1...3 {
            _ = refresh.visible(true, at: t0)
            _ = refresh.fire(at: t0)
            _ = refresh.passFinished(trigger: .start, changed: false, failed: true, at: t0)
            _ = refresh.visible(false, at: t0)
        }
        #expect(refresh.readerFailed)
        refresh.readWorked()
        #expect(!refresh.readerFailed)
        _ = refresh.visible(true, at: t0)
        _ = refresh.fire(at: t0)
        _ = refresh.passFinished(trigger: .start, changed: false, failed: true, at: t0)
        #expect(!refresh.readerFailed)
    }

    // MARK: Change

    @Test("A change is a different badge of an app that was read, an app with a badge that was not, or a badge that went")
    func changeBetweenReads() {
        let one = DockBadgeLabel.count(1)
        #expect(!DockBadgeRefresh.changed(from: [:], to: [:]))
        #expect(!DockBadgeRefresh.changed(from: ["a": one], to: ["a": one]))
        #expect(DockBadgeRefresh.changed(from: ["a": one], to: ["a": .count(2)]))
        #expect(DockBadgeRefresh.changed(from: ["a": one], to: ["a": .mark("•")]))
        #expect(DockBadgeRefresh.changed(from: [:], to: ["a": one]))
        #expect(DockBadgeRefresh.changed(from: ["a": one], to: [:]))
        #expect(DockBadgeRefresh.changed(from: ["a": one], to: ["a": DockBadgeLabel.none]))
    }

    @Test("An app without a badge is the same as an app that is not in the Dock")
    func noBadgeIsAbsent() {
        #expect(!DockBadgeRefresh.changed(from: [:], to: ["a": DockBadgeLabel.none]))
        #expect(!DockBadgeRefresh.changed(from: ["a": DockBadgeLabel.none], to: [:]))
    }
}
