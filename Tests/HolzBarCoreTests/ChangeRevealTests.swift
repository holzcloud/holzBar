import Foundation
import Testing
@testable import HolzBarCore

@Suite("ChangeReveal")
struct ChangeRevealTests {
    @Test("Changes within a second count once")
    func changesWithinASecondCountOnce() {
        var reveal = ChangeReveal()
        for time in [10.0, 10.25, 10.75] {
            reveal.noteChange(key: "timer", isZenActive: false, isVisible: false, at: time)
        }
        #expect(reveal.nextDueTime == 11.75)
        #expect(reveal.due(at: 11.5).isEmpty)
        #expect(reveal.due(at: 11.75) == ["timer"])
        #expect(reveal.due(at: 12.5).isEmpty)
        #expect(reveal.nextDueTime == nil)
    }

    @Test("An item is revealed at most every 30 s")
    func revealedAtMostEveryThirtySeconds() {
        var reveal = ChangeReveal()
        reveal.noteChange(key: "timer", isZenActive: false, isVisible: false, at: 0)
        #expect(reveal.due(at: 1) == ["timer"])
        reveal.noteChange(key: "timer", isZenActive: false, isVisible: false, at: 21)
        #expect(reveal.due(at: 23).isEmpty)
        reveal.noteChange(key: "timer", isZenActive: false, isVisible: false, at: 32)
        #expect(reveal.due(at: 33) == ["timer"])
        // Another item has its own limit.
        reveal.noteChange(key: "mail", isZenActive: false, isVisible: false, at: 33.5)
        #expect(reveal.due(at: 34.5) == ["mail"])
    }

    @Test("Nothing is revealed in Zen mode or for a visible item")
    func nothingInZenModeOrForVisibleItems() {
        var reveal = ChangeReveal()
        reveal.noteChange(key: "timer", isZenActive: true, isVisible: false, at: 0)
        reveal.noteChange(key: "clock", isZenActive: false, isVisible: true, at: 0)
        #expect(reveal.due(at: 5).isEmpty)
        #expect(reveal.nextDueTime == nil)
    }
}
