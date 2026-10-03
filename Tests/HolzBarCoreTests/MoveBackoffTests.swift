import Testing
@testable import HolzBarCore

@Suite("MoveBackoff")
struct MoveBackoffTests {
    // The back-off is changed outside `#expect`, whose expansion cannot call a mutating
    // method.

    private let start = ContinuousClock.now

    /// Records the given number of failed automatic moves at the given time.
    private func fail(_ count: Int, _ backoff: inout MoveBackoff, at now: ContinuousClock.Instant) {
        for _ in 0..<count {
            backoff.recordFailure(at: now)
        }
    }

    @Test("Failures trip it")
    func failuresTripIt() {
        var backoff = MoveBackoff()
        fail(7, &backoff, at: start)
        #expect(backoff.allowsAutomaticMove(at: start))
        let tripped = backoff.recordFailure(at: start + .seconds(30))
        #expect(tripped)
        #expect(!backoff.allowsAutomaticMove(at: start + .seconds(30)))
        #expect(!backoff.allowsAutomaticMove(at: start + .seconds(89)))
        #expect(backoff.allowsAutomaticMove(at: start + .seconds(90)))
    }

    @Test("Failures outside the window are not counted")
    func oldFailuresAreNotCounted() {
        var backoff = MoveBackoff()
        fail(7, &backoff, at: start)
        let tripped = backoff.recordFailure(at: start + .seconds(61))
        #expect(!tripped)
        #expect(backoff.allowsAutomaticMove(at: start + .seconds(61)))
    }

    @Test("The same item moved too often trips it")
    func sameItemTripsIt() {
        var sameItem = MoveBackoff()
        var trips = [Bool]()
        for second in 0..<5 {
            trips.append(sameItem.recordAutomaticMove(identifier: "com.example.app:Item", at: start + .seconds(second)))
        }
        #expect(trips == [false, false, false, false, true])
        #expect(!sameItem.allowsAutomaticMove(at: start + .seconds(5)))

        var differentItems = MoveBackoff()
        for index in 0..<5 {
            differentItems.recordAutomaticMove(identifier: "com.example.app:Item\(index)", at: start + .seconds(index))
        }
        #expect(differentItems.allowsAutomaticMove(at: start + .seconds(5)))
    }

    @Test("The pause doubles and is capped")
    func pauseDoublesAndIsCapped() throws {
        var backoff = MoveBackoff()
        var now = start
        var pauses = [Duration]()
        for _ in 0..<6 {
            fail(MoveBackoff.failureLimit, &backoff, at: now)
            let pausedUntil = try #require(backoff.pausedUntil)
            pauses.append(now.duration(to: pausedUntil))
            // The next trip comes right as the pause ends.
            now = pausedUntil
        }
        #expect(pauses == [.seconds(60), .seconds(120), .seconds(240), .seconds(480), .seconds(600), .seconds(600)])
    }

    @Test("300 s without a trip after a pause start the pause over")
    func pauseStartsOverAfterQuietInterval() throws {
        var backoff = MoveBackoff()
        fail(MoveBackoff.failureLimit, &backoff, at: start)
        let secondTrip = start + .seconds(100)
        fail(MoveBackoff.failureLimit, &backoff, at: secondTrip)
        let secondPause = try #require(backoff.pausedUntil)
        #expect(secondTrip.duration(to: secondPause) == .seconds(120))

        let thirdTrip = secondPause + MoveBackoff.resetInterval
        fail(MoveBackoff.failureLimit, &backoff, at: thirdTrip)
        let thirdPause = try #require(backoff.pausedUntil)
        #expect(thirdTrip.duration(to: thirdPause) == .seconds(60))
    }

    @Test("A user move ends the pause")
    func userMoveEndsThePause() {
        var backoff = MoveBackoff()
        fail(MoveBackoff.failureLimit, &backoff, at: start)
        #expect(!backoff.allowsAutomaticMove(at: start))
        backoff.recordUserMove()
        #expect(backoff.allowsAutomaticMove(at: start))
        #expect(backoff.pausedUntil == nil)
        // The counts started over: one more failure does not trip it again.
        let tripped = backoff.recordFailure(at: start + .seconds(1))
        #expect(!tripped)
    }
}
