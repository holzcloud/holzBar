import Foundation
import Testing
@testable import HolzBarMacOS27Core

@Suite("ApplyLedger27")
struct ApplyLedger27Tests {
    // The ledger is changed outside `#expect`, whose expansion cannot call a mutating method.

    @Test("Applies are numbered in the order they are queued")
    func numberedInOrder() {
        var ledger = ApplyLedger27<String>()
        #expect(!ledger.hasPending)
        let first = ledger.queue()
        let second = ledger.queue()
        let third = ledger.queue()
        #expect(first == 1)
        #expect(second == 2)
        #expect(third == 3)
        #expect(ledger.hasPending)
        _ = ledger.finish(3, succeeded: true)
        #expect(!ledger.hasPending)
    }

    @Test("A waiter is answered when its apply succeeds")
    func answeredOnSuccess() {
        var ledger = ApplyLedger27<String>()
        let apply = ledger.queue()
        let id = ledger.wait(for: apply, waiter: "click")
        #expect(id != nil)
        let resumed = ledger.finish(apply, succeeded: true)
        #expect(resumed == ["click"])
        #expect(ledger.lastSucceeded)
    }

    @Test("A waiter is answered when its apply fails")
    func answeredOnFailure() {
        var ledger = ApplyLedger27<String>()
        let apply = ledger.queue()
        _ = ledger.wait(for: apply, waiter: "click")
        let resumed = ledger.finish(apply, succeeded: false)
        #expect(resumed == ["click"])
        #expect(!ledger.lastSucceeded)
    }

    @Test("A wait for an apply that already finished is answered at once")
    func alreadyFinished() {
        var ledger = ApplyLedger27<String>()
        let apply = ledger.queue()
        _ = ledger.finish(apply, succeeded: true)
        let id = ledger.wait(for: apply, waiter: "late")
        #expect(id == nil)
    }

    @Test("An apply answers the waiters of itself and those before it, in order")
    func answersEarlierWaitersInOrder() {
        var ledger = ApplyLedger27<String>()
        let first = ledger.queue()
        let second = ledger.queue()
        let third = ledger.queue()
        _ = ledger.wait(for: second, waiter: "b")
        _ = ledger.wait(for: first, waiter: "a")
        _ = ledger.wait(for: third, waiter: "c")
        let resumed = ledger.finish(second, succeeded: true)
        #expect(resumed == ["b", "a"])
        let rest = ledger.finish(third, succeeded: true)
        #expect(rest == ["c"])
    }

    @Test("An abandoned waiter is handed back once and never by the apply")
    func abandonOnce() throws {
        var ledger = ApplyLedger27<String>()
        let apply = ledger.queue()
        let waiting = ledger.wait(for: apply, waiter: "timeout")
        let id = try #require(waiting)
        let abandoned = ledger.abandon(id)
        #expect(abandoned == "timeout")
        let resumed = ledger.finish(apply, succeeded: true)
        #expect(resumed.isEmpty)
        let again = ledger.abandon(id)
        #expect(again == nil)
    }

    @Test("A waiter the apply answered is not handed back by abandon")
    func abandonAfterFinish() throws {
        var ledger = ApplyLedger27<String>()
        let apply = ledger.queue()
        let waiting = ledger.wait(for: apply, waiter: "click")
        let id = try #require(waiting)
        let resumed = ledger.finish(apply, succeeded: true)
        #expect(resumed == ["click"])
        let abandoned = ledger.abandon(id)
        #expect(abandoned == nil)
    }

    @Test("A wait for the next apply, made before it is queued, is answered by that apply")
    func waitForTheNextApply() {
        var ledger = ApplyLedger27<String>()
        let earlier = ledger.queue()
        _ = ledger.finish(earlier, succeeded: true)
        let next = ledger.nextApply
        let id = ledger.wait(for: next, waiter: "suspended")
        #expect(id != nil)
        let queued = ledger.queue()
        #expect(queued == next)
        let resumed = ledger.finish(queued, succeeded: true)
        #expect(resumed == ["suspended"])
    }
}
