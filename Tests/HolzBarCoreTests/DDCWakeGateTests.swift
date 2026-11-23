import Testing
@testable import HolzBarCore

@Suite("DDCWakeGate")
struct DDCWakeGateTests {
    private let start = ContinuousClock.now

    @Test("A gate that saw no event is open and has no opening time")
    func freshGate() {
        let gate = DDCWakeGate()
        #expect(gate.isOpen(at: start))
        #expect(gate.opensAt == nil)
        #expect(gate.lastEvent == nil)
    }

    @Test("After an event the gate is closed until exactly the wait has passed")
    func boundary() {
        var gate = DDCWakeGate()
        gate.record(at: start)
        #expect(!gate.isOpen(at: start))
        #expect(!gate.isOpen(at: start + .seconds(2) + .milliseconds(999)))
        #expect(gate.isOpen(at: start + .seconds(3)))
        #expect(gate.isOpen(at: start + .seconds(10)))
        #expect(gate.opensAt == start + .seconds(3))
    }

    @Test("A later event extends the wait")
    func laterEventExtends() {
        var gate = DDCWakeGate()
        gate.record(at: start)
        gate.record(at: start + .seconds(2))
        #expect(gate.opensAt == start + .seconds(5))
        #expect(!gate.isOpen(at: start + .seconds(4)))
        #expect(gate.isOpen(at: start + .seconds(5)))
    }

    @Test("An older event never shortens the wait")
    func olderEventIgnored() {
        var gate = DDCWakeGate()
        gate.record(at: start + .seconds(2))
        gate.record(at: start)
        #expect(gate.opensAt == start + .seconds(5))
    }
}
