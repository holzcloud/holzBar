import Testing
@testable import HolzBarCore

/// A seeded 64-bit generator (SplitMix64), so the property test below is reproducible without a
/// property-test package.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

@Suite("Click pairing")
struct ClickPairingTests {
    // The reducer is changed outside `#expect`, whose expansion cannot call a mutating method.

    private let start = ContinuousClock.now

    @Test("A held press swallows its own release once")
    func heldPressSwallowsItsRelease() {
        var pairing = ClickPairing()
        let press = pairing.press(number: 7, shouldHold: true, at: start)
        #expect(press == .holdBack)
        #expect(pairing.heldCount == 1)
        let first = pairing.release(number: 7)
        #expect(first == .swallowRelease)
        let second = pairing.release(number: 7)
        #expect(second == .pass)
        #expect(pairing.heldCount == 0)
    }

    @Test("A press that is not held passes with its release")
    func passedPressPassesItsRelease() {
        var pairing = ClickPairing()
        let press = pairing.press(number: 7, shouldHold: false, at: start)
        #expect(press == .pass)
        #expect(pairing.heldCount == 0)
        let release = pairing.release(number: 7)
        #expect(release == .pass)
    }

    @Test("The release of another click is never taken")
    func anotherClicksReleasePasses() {
        var pairing = ClickPairing()
        _ = pairing.press(number: 7, shouldHold: true, at: start)
        let other = pairing.release(number: 8)
        #expect(other == .pass)
        #expect(pairing.heldCount == 1)
    }

    @Test("A release before any press passes")
    func releaseWithoutPressPasses() {
        var pairing = ClickPairing()
        let release = pairing.release(number: 9)
        #expect(release == .pass)
    }

    @Test("After a flush the late release passes")
    func flushLetsTheLateReleasePass() {
        var pairing = ClickPairing()
        _ = pairing.press(number: 7, shouldHold: true, at: start)
        let flushed = pairing.flush()
        #expect(flushed == [7])
        let release = pairing.release(number: 7)
        #expect(release == .pass)
        #expect(pairing.heldCount == 0)
    }

    @Test("The watchdog lets a press go after ten seconds")
    func watchdogExpiresAPress() {
        var pairing = ClickPairing()
        _ = pairing.press(number: 7, shouldHold: true, at: start)
        let early = pairing.expire(at: start + .seconds(9))
        #expect(early.isEmpty)
        #expect(pairing.heldCount == 1)
        let due = pairing.expire(at: start + ClickPairing.releaseWatchdog)
        #expect(due == [7])
        let release = pairing.release(number: 7)
        #expect(release == .pass)
    }

    @Test("Two held presses are paired each with its own release")
    func twoHeldPresses() {
        var pairing = ClickPairing()
        _ = pairing.press(number: 7, shouldHold: true, at: start)
        _ = pairing.press(number: 8, shouldHold: true, at: start)
        let eight = pairing.release(number: 8)
        let seven = pairing.release(number: 7)
        #expect(eight == .swallowRelease)
        #expect(seven == .swallowRelease)
        #expect(pairing.heldCount == 0)
    }

    @Test("A number used again pairs again")
    func numberReuse() {
        var pairing = ClickPairing()
        _ = pairing.press(number: 7, shouldHold: true, at: start)
        let first = pairing.release(number: 7)
        #expect(first == .swallowRelease)
        let again = pairing.press(number: 7, shouldHold: true, at: start + .seconds(1))
        #expect(again == .holdBack)
        let second = pairing.release(number: 7)
        #expect(second == .swallowRelease)
    }

    @Test("A press that is not held forgets an older press with its number")
    func passedPressForgetsStaleEntry() {
        var pairing = ClickPairing()
        _ = pairing.press(number: 7, shouldHold: true, at: start)
        _ = pairing.press(number: 7, shouldHold: false, at: start + .seconds(1))
        #expect(pairing.heldCount == 0)
        let release = pairing.release(number: 7)
        #expect(release == .pass)
    }

    /// One operation of the property test.
    private enum Operation: CustomStringConvertible {
        case press(number: Int64, shouldHold: Bool)
        case release(number: Int64)
        case flush
        case expire(stepSeconds: Int)

        var description: String {
            switch self {
            case .press(let number, let shouldHold): "press(\(number), hold: \(shouldHold))"
            case .release(let number): "release(\(number))"
            case .flush: "flush"
            case .expire(let step): "expire(+\(step)s)"
            }
        }
    }

    @Test("Random interleavings keep the five invariants")
    func propertyOverRandomInterleavings() {
        let seed: UInt64 = 0x0105_2711_2026
        var generator = SplitMix64(seed: seed)
        for sequence in 0..<3000 {
            let length = Int.random(in: 1...40, using: &generator)
            var operations = [Operation]()
            for _ in 0..<length {
                switch Int.random(in: 0..<10, using: &generator) {
                case 0..<4:
                    operations.append(.press(
                        number: Int64.random(in: 0...5, using: &generator),
                        shouldHold: Bool.random(using: &generator)
                    ))
                case 4..<8:
                    operations.append(.release(number: Int64.random(in: 0...5, using: &generator)))
                case 8:
                    operations.append(.flush)
                default:
                    operations.append(.expire(stepSeconds: Int.random(in: 0...6, using: &generator)))
                }
            }
            if let failure = run(operations) {
                Issue.record("seed \(seed), sequence \(sequence): \(failure); operations: \(operations)")
                return
            }
        }
    }

    /// Runs the operations against the reducer and a reference model; returns the first broken
    /// invariant, or `nil`.
    private func run(_ operations: [Operation]) -> String? {
        var pairing = ClickPairing()
        // The reference model: the presses held and when each was taken.
        var model = [Int64: ContinuousClock.Instant]()
        var now = start
        var holds = 0
        var swallows = 0
        for operation in operations {
            switch operation {
            case .press(let number, let shouldHold):
                let action = pairing.press(number: number, shouldHold: shouldHold, at: now)
                // Invariant 4: held back only when asked to.
                if action == .holdBack, !shouldHold {
                    return "held back a press it was not asked to hold"
                }
                if action != (shouldHold ? .holdBack : .pass) {
                    return "wrong action \(action) for a press"
                }
                if shouldHold {
                    model[number] = now
                    holds += 1
                } else {
                    model[number] = nil
                }
            case .release(let number):
                let action = pairing.release(number: number)
                let wasHeld = model[number] != nil
                // Invariants 1 and 3: swallowed only when a press with that number is still held.
                if action == .swallowRelease, !wasHeld {
                    return "swallowed the release of \(number), which was not held"
                }
                if action == .pass, wasHeld {
                    return "passed the release of held \(number)"
                }
                if action == .swallowRelease {
                    swallows += 1
                    model[number] = nil
                }
            case .flush:
                let flushed = pairing.flush()
                if flushed != model.keys.sorted() {
                    return "flush returned \(flushed) while \(model.keys.sorted()) were held"
                }
                model.removeAll()
            case .expire(let step):
                now += .seconds(step)
                let expired = pairing.expire(at: now)
                let due = model.filter { $0.value.duration(to: now) >= ClickPairing.releaseWatchdog }.keys.sorted()
                if expired != due {
                    return "expire returned \(expired) while \(due) were due"
                }
                for number in due {
                    model[number] = nil
                }
            }
            // Invariant 2: never more swallows than held presses.
            if swallows > holds {
                return "more releases swallowed (\(swallows)) than presses held (\(holds))"
            }
            if pairing.heldCount != model.count {
                return "heldCount \(pairing.heldCount) differs from \(model.count)"
            }
        }
        // Invariant 5: every press still held has a way out, and the flush names exactly those.
        let rest = pairing.flush()
        if rest != model.keys.sorted() {
            return "final flush returned \(rest) while \(model.keys.sorted()) were held"
        }
        return nil
    }
}
