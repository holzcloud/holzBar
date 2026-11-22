import Testing
@testable import HolzBarCore

@Suite("Reopen gate")
struct ReopenGateTests {
    private let start = ContinuousClock.now

    private func decide(
        _ bundleID: String?,
        original: String? = nil,
        at now: ContinuousClock.Instant? = nil,
        last: ContinuousClock.Instant? = nil
    ) -> ReopenGate.Decision {
        ReopenGate.decide(
            sender: ReopenGate.Sender(bundleID: bundleID, originalBundleID: original),
            now: now ?? start,
            lastOpened: last
        )
    }

    @Test("A Dock, Finder, Spotlight or Launchpad reopen opens Settings", arguments: [
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.Spotlight",
        "com.apple.launchpad.launcher",
        "COM.APPLE.DOCK",
    ])
    func userLaunchOpens(_ bundleID: String) {
        #expect(decide(bundleID) == .openSettings)
    }

    @Test("The original sender alone can allow a reopen")
    func originalSenderAllows() {
        #expect(decide(nil, original: "com.apple.finder") == .openSettings)
    }

    @Test("Any other sender is ignored", arguments: [
        "com.apple.Siri",
        "com.apple.shortcuts",
        "com.apple.WorkflowKit.BackgroundShortcutRunner",
        "com.raycast.macos",
        "com.runningwithcrayons.Alfred",
        "com.apple.Terminal",
    ])
    func otherSendersAreIgnored(_ bundleID: String) {
        #expect(decide(bundleID) == .ignore(.notUserLaunch))
    }

    @Test("A never-marker beats the allow-list")
    func neverMarkerWins() {
        #expect(decide("com.apple.Siri", original: "com.apple.dock") == .ignore(.notUserLaunch))
        #expect(decide("com.apple.dock", original: "com.apple.shortcuts") == .ignore(.notUserLaunch))
    }

    @Test("Without any sender the reopen is ignored")
    func unknownSender() {
        #expect(decide(nil) == .ignore(.unknownSender))
    }

    @Test("A second reopen within the rate limit is ignored")
    func rateLimit() {
        let last = start
        #expect(decide("com.apple.dock", at: last + .milliseconds(1999), last: last) == .ignore(.rateLimited))
        #expect(decide("com.apple.dock", at: last + .seconds(2), last: last) == .openSettings)
        #expect(decide("com.apple.dock", at: last, last: nil) == .openSettings)
    }

    @Test("A rate-limited reopen does not move the last opened time")
    func rateLimitedDoesNotExtend() {
        var lastOpened: ContinuousClock.Instant?
        var outcomes = [ReopenGate.Decision]()
        // Opens at 0 s, ignored at 1 s, opens at 2 s: the ignored one did not push the window.
        for second in [0, 1, 2] {
            let now = start + .seconds(second)
            let decision = decide("com.apple.finder", at: now, last: lastOpened)
            if decision == .openSettings {
                lastOpened = now
            }
            outcomes.append(decision)
        }
        #expect(outcomes == [.openSettings, .ignore(.rateLimited), .openSettings])
    }

    @Test("A sender that is not allowed is ignored before the rate limit is asked")
    func notUserLaunchBeatsRateLimit() {
        #expect(decide("com.apple.Siri", at: start + .seconds(1), last: start) == .ignore(.notUserLaunch))
    }
}
