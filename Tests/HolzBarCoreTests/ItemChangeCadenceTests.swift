import Foundation
import Testing
@testable import HolzBarCore

@Suite("ItemChangeCadence")
struct ItemChangeCadenceTests {
    /// The times at which the events of one app, every 0.5 s from `start` to `end`, force a read.
    private static func forcedTimes(
        _ cadence: inout ItemChangeCadence,
        pid: Int32?,
        from start: TimeInterval,
        through end: TimeInterval
    ) -> [TimeInterval] {
        var forced = [TimeInterval]()
        var time = start
        while time <= end {
            if cadence.noteEvent(pid: pid, at: time) == .readNow {
                forced.append(time)
            }
            time += 0.5
        }
        return forced
    }

    @Test("A busy app forces a read 5 s into its burst, then at most every 30 s")
    func busyAppForcesAtMostEveryThirtySeconds() {
        var cadence = ItemChangeCadence()
        let forced = Self.forcedTimes(&cadence, pid: 7, from: 0, through: 70)
        #expect(forced == [5, 35, 65])
        #expect(cadence.forcedReads == 3)
        // The bursts after the reads at 5 and 35 were each held back once.
        #expect(cadence.heldBack == 2)
    }

    @Test("Each held-back burst counts once")
    func heldBackCountsOncePerBurst() {
        var cadence = ItemChangeCadence()
        _ = Self.forcedTimes(&cadence, pid: 7, from: 0, through: 5)
        #expect(cadence.heldBack == 0)
        _ = Self.forcedTimes(&cadence, pid: 7, from: 5.5, through: 20)
        #expect(cadence.heldBack == 1)
        // A quiet second: the debounced read ends the burst.
        cadence.didRead()
        _ = Self.forcedTimes(&cadence, pid: 7, from: 22, through: 30)
        #expect(cadence.heldBack == 2)
        #expect(cadence.forcedReads == 1)
    }

    @Test("Another app forces its own read while the first is held back")
    func secondAppForcesItsOwnRead() {
        var cadence = ItemChangeCadence()
        var forced7 = [TimeInterval]()
        var forced9 = [TimeInterval]()
        var time = 0.0
        while time <= 20 {
            if cadence.noteEvent(pid: 7, at: time) == .readNow {
                forced7.append(time)
            }
            if time >= 6, cadence.noteEvent(pid: 9, at: time) == .readNow {
                forced9.append(time)
            }
            time += 0.5
        }
        #expect(forced7 == [5])
        // Within 5 s of its first event at 6, although app 7 forced one at 5.
        #expect(forced9.count == 1)
        #expect(forced9.allSatisfy { $0 > 6 && $0 <= 11 })
        #expect(cadence.forcedReads == 2)
    }

    @Test("Events without an app keep today's 5 s rule")
    func eventsWithoutAnAppKeepTheFiveSecondRule() {
        var cadence = ItemChangeCadence()
        let forced = Self.forcedTimes(&cadence, pid: nil, from: 0, through: 20)
        #expect(forced == [5, 10.5, 16])
        #expect(cadence.heldBack == 0)
    }

    @Test("A busy app plus helper launches every 3 s forces no more than every 30 s")
    func helpersDoNotBypassTheGap() {
        var cadence = ItemChangeCadence()
        var forced = [TimeInterval]()
        var time = 0.0
        while time <= 70 {
            if cadence.noteEvent(.app(7), at: time) == .readNow {
                forced.append(time)
            }
            if time.truncatingRemainder(dividingBy: 3) == 0, cadence.noteEvent(.helper, at: time) == .readNow {
                forced.append(time)
            }
            time += 0.5
        }
        #expect(forced == [5, 35, 65])
        #expect(cadence.forcedReads == 3)
        // Helper events alone, before the app is held back, keep the 5 s rule.
        var alone = ItemChangeCadence()
        #expect(alone.noteEvent(.helper, at: 0) == .waitForQuiet)
        #expect(alone.noteEvent(.helper, at: 5) == .readNow)
    }

    @Test("A launch that may add an item forces at the 5 s rule while a busy app is held back")
    func systemEventsStillForce() {
        var cadence = ItemChangeCadence()
        _ = Self.forcedTimes(&cadence, pid: 7, from: 0, through: 5)
        // The busy app goes on and is held back from 10.5 on.
        _ = Self.forcedTimes(&cadence, pid: 7, from: 5.5, through: 11)
        #expect(cadence.noteEvent(.helper, at: 11.2) == .waitForQuiet)
        #expect(cadence.noteEvent(.system, at: 11.4) == .readNow)
        #expect(cadence.noteEvent(pid: nil, at: 11.6) == .waitForQuiet)
        // An app that has not forced lately is not held back by the busy one either: once its
        // event is in the burst, a helper may force as well when no app of the burst is in its gap.
        var other = ItemChangeCadence()
        _ = other.noteEvent(.app(9), at: 0)
        #expect(other.noteEvent(.helper, at: 5) == .readNow)
    }

    @Test("A debounced read ends the burst")
    func didReadEndsTheBurst() {
        var cadence = ItemChangeCadence()
        #expect(cadence.noteEvent(pid: 7, at: 0) == .waitForQuiet)
        #expect(cadence.noteEvent(pid: 7, at: 4) == .waitForQuiet)
        cadence.didRead()
        // A new burst starts at 5.5; 5 s after the old one's start is not enough.
        #expect(cadence.noteEvent(pid: 7, at: 5.5) == .waitForQuiet)
        #expect(cadence.noteEvent(pid: 7, at: 10) == .waitForQuiet)
        #expect(cadence.noteEvent(pid: 7, at: 10.5) == .readNow)
        #expect(cadence.forcedReads == 1)
    }

    @Test("A held-back app may force again once 30 s passed, also in a later burst")
    func heldBackAppForcesAfterTheGap() {
        var cadence = ItemChangeCadence()
        _ = Self.forcedTimes(&cadence, pid: 7, from: 0, through: 5)
        cadence.didRead()
        #expect(cadence.noteEvent(pid: 7, at: 30) == .waitForQuiet)
        #expect(cadence.noteEvent(pid: 7, at: 34.5) == .waitForQuiet)
        #expect(cadence.noteEvent(pid: 7, at: 35) == .readNow)
    }

    @Test("Apps whose last forced read is older than 30 s are forgotten")
    func forgetsOldApps() {
        var cadence = ItemChangeCadence()
        _ = Self.forcedTimes(&cadence, pid: 7, from: 0, through: 5)
        _ = Self.forcedTimes(&cadence, pid: 9, from: 5.5, through: 10.5)
        #expect(cadence.rememberedApps == 2)
        cadence.didRead()
        _ = cadence.noteEvent(pid: nil, at: 36)
        #expect(cadence.rememberedApps == 1)
        _ = cadence.noteEvent(pid: nil, at: 41)
        #expect(cadence.rememberedApps == 0)
    }
}
