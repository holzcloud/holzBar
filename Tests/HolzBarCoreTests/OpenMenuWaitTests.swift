import Testing
@testable import HolzBarCore

@Suite("OpenMenuWait")
struct OpenMenuWaitTests {
    @Test("No open menu, no wait")
    func nothingOpen() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [1, 2])
        #expect(wait.check(openMenus: [], now: 0) == .init(waits: false, newlyGivenUp: []))
    }

    @Test("A window on screen before the reveal never counts")
    func windowBeforeTheRevealNeverCounts() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [7])
        for now in [0.0, 10, 1000] {
            #expect(!wait.check(openMenus: [7], now: now).waits)
        }
        #expect(wait.givenUp.isEmpty)
    }

    @Test("A menu that appeared after the reveal keeps the hide waiting")
    func menuAfterTheRevealWaits() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [7])
        #expect(wait.check(openMenus: [7, 9], now: 0).waits)
        #expect(wait.check(openMenus: [7, 9], now: OpenMenuWait.longestWait - 1).waits)
    }

    @Test("A window stops counting once it has kept the hide waiting for the longest wait")
    func waitIsCapped() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [])
        #expect(wait.check(openMenus: [9], now: 100).waits)
        let capped = wait.check(openMenus: [9], now: 100 + OpenMenuWait.longestWait)
        #expect(capped == .init(waits: false, newlyGivenUp: [9]))
        // Logged once: later checks report nothing new and never wait for it again.
        #expect(wait.check(openMenus: [9], now: 500) == .init(waits: false, newlyGivenUp: []))
        #expect(wait.givenUp == [9])
    }

    @Test("Another menu still waits while one is given up")
    func otherMenuStillWaits() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [])
        _ = wait.check(openMenus: [9], now: 0)
        let decision = wait.check(openMenus: [9, 11], now: OpenMenuWait.longestWait)
        #expect(decision == .init(waits: true, newlyGivenUp: [9]))
    }

    @Test("A window that closed waits anew when it comes back")
    func closedWindowWaitsAnew() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [])
        _ = wait.check(openMenus: [9], now: 0)
        _ = wait.check(openMenus: [], now: 30)
        #expect(wait.check(openMenus: [9], now: 70).waits)
        #expect(wait.check(openMenus: [9], now: 70 + OpenMenuWait.longestWait - 1).waits)
    }

    @Test("A new reveal forgets the windows of the last one")
    func newRevealStartsOver() {
        var wait = OpenMenuWait()
        wait.revealStarted(windowsOnScreen: [1])
        _ = wait.check(openMenus: [9], now: 0)
        _ = wait.check(openMenus: [9], now: OpenMenuWait.longestWait)
        wait.revealStarted(windowsOnScreen: [2])
        #expect(wait.windowsBeforeReveal == [2])
        #expect(wait.givenUp.isEmpty)
        #expect(wait.check(openMenus: [1, 9], now: 1000).waits)
    }
}
