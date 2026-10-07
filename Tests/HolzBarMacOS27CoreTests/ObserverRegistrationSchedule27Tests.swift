import Foundation
import Testing
@testable import HolzBarMacOS27Core

@Suite("ObserverRegistrationSchedule27")
struct ObserverRegistrationSchedule27Tests {
    @Test("A process never asked may be asked")
    func unknown() {
        let schedule = ObserverRegistrationSchedule27()
        #expect(schedule.allowsRegistration(of: 42, now: 0))
        #expect(schedule.isEmpty)
    }

    @Test("A timeout waits 5 s, doubling up to 60 s")
    func backoff() {
        var schedule = ObserverRegistrationSchedule27()
        var now: TimeInterval = 100
        for pause: TimeInterval in [5, 10, 20, 40, 60, 60] {
            schedule.record(.timedOut, for: 42, now: now)
            #expect(!schedule.allowsRegistration(of: 42, now: now))
            #expect(!schedule.allowsRegistration(of: 42, now: now + pause - 0.1))
            #expect(schedule.allowsRegistration(of: 42, now: now + pause))
            now += pause
        }
    }

    @Test("A refresh before the pause ended does not count as a failure")
    func refreshDuringPause() {
        var schedule = ObserverRegistrationSchedule27()
        schedule.record(.timedOut, for: 42, now: 0)
        // The refreshes at 1 s and 3 s do not ask the process, so nothing is recorded.
        #expect(!schedule.allowsRegistration(of: 42, now: 1))
        #expect(!schedule.allowsRegistration(of: 42, now: 3))
        #expect(schedule.allowsRegistration(of: 42, now: 5))
    }

    @Test("A success clears the pause, and the next timeout starts over")
    func successClears() {
        var schedule = ObserverRegistrationSchedule27()
        schedule.record(.timedOut, for: 42, now: 0)
        schedule.record(.timedOut, for: 42, now: 5)
        schedule.record(.registered, for: 42, now: 15)
        #expect(schedule.isEmpty)
        #expect(schedule.allowsRegistration(of: 42, now: 15))
        schedule.record(.timedOut, for: 42, now: 20)
        #expect(schedule.allowsRegistration(of: 42, now: 25))
    }

    @Test("A process without the notifications is not asked again while it runs")
    func unsupported() {
        var schedule = ObserverRegistrationSchedule27()
        schedule.record(.unsupported, for: 42, now: 0)
        #expect(!schedule.allowsRegistration(of: 42, now: 10_000))
        schedule.retain(running: [42])
        #expect(!schedule.allowsRegistration(of: 42, now: 10_000))
    }

    @Test("Processes that quit are forgotten; others are not affected")
    func retain() {
        var schedule = ObserverRegistrationSchedule27()
        schedule.record(.unsupported, for: 42, now: 0)
        schedule.record(.timedOut, for: 43, now: 0)
        #expect(schedule.allowsRegistration(of: 44, now: 0))
        schedule.retain(running: [43])
        #expect(schedule.allowsRegistration(of: 42, now: 0))
        #expect(!schedule.allowsRegistration(of: 43, now: 0))
        schedule.retain(running: [])
        #expect(schedule.isEmpty)
    }
}
