import Foundation
import Testing
@testable import HolzBarCore

@Suite("RevealGate")
struct RevealGateTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Without the lock nothing is asked")
    func lockOff() {
        let gate = RevealGate()
        #expect(!gate.requiresAuthentication(isLockOn: false, now: now))
    }

    @Test("With the lock on, an answer is asked for")
    func lockOn() {
        let gate = RevealGate()
        #expect(gate.requiresAuthentication(isLockOn: true, now: now))
    }

    @Test("A successful answer opens a grace period")
    func grace() {
        var gate = RevealGate()
        gate.unlock(now: now)
        #expect(!gate.requiresAuthentication(isLockOn: true, now: now.addingTimeInterval(RevealGate.grace - 1)))
        #expect(gate.requiresAuthentication(isLockOn: true, now: now.addingTimeInterval(RevealGate.grace)))
    }

    @Test("Locking ends the grace period at once")
    func lockEndsGrace() {
        var gate = RevealGate()
        gate.unlock(now: now)
        gate.lock()
        #expect(gate.requiresAuthentication(isLockOn: true, now: now.addingTimeInterval(1)))
    }
}
