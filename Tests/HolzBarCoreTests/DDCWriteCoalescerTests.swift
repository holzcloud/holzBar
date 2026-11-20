import Testing
@testable import HolzBarCore

@Suite("DDCWriteCoalescer")
struct DDCWriteCoalescerTests {
    @Test("A submit while idle starts the writer, a second one while it writes does not")
    func oneWriter() {
        var coalescer = DDCWriteCoalescer()
        let first = coalescer.submit(10)
        let second = coalescer.submit(20)
        #expect(first)
        #expect(!second)
    }

    @Test("The writer gets the latest value, then nothing")
    func latestWins() {
        var coalescer = DDCWriteCoalescer()
        _ = coalescer.submit(10)
        let first = coalescer.next()
        let second = coalescer.submit(20)
        let third = coalescer.submit(30)
        let fourth = coalescer.submit(40)
        let latest = coalescer.next()
        let end = coalescer.next()
        #expect(first == 10)
        #expect(!second && !third && !fourth)
        #expect(latest == 40)
        #expect(end == nil)
    }

    @Test("After the writer ended a submit starts a new one")
    func restarts() {
        var coalescer = DDCWriteCoalescer()
        let started = coalescer.submit(1)
        let value = coalescer.next()
        let end = coalescer.next()
        let startedAgain = coalescer.submit(2)
        let next = coalescer.next()
        #expect(started)
        #expect(value == 1)
        #expect(end == nil)
        #expect(startedAgain)
        #expect(next == 2)
    }

    @Test("Several submits while the writer writes leave only the latest")
    func onlyTheLatest() {
        var coalescer = DDCWriteCoalescer()
        _ = coalescer.submit(5)
        _ = coalescer.submit(6)
        _ = coalescer.submit(7)
        _ = coalescer.submit(8)
        let value = coalescer.next()
        let end = coalescer.next()
        #expect(value == 8)
        #expect(end == nil)
    }
}
