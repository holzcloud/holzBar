import Foundation
import Testing
@testable import HolzBarCore

@Suite("IndicatorPolicy")
struct IndicatorPolicyTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        base.addingTimeInterval(seconds)
    }

    // MARK: Input source

    @Test("The first source shows, the same source again is ignored, another one shows")
    func repeatSuppression() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        #expect(policy.offer(.inputSource, value: "DE", at: at(1)) == .ignored)
        #expect(policy.offer(.inputSource, value: "EN", at: at(1)) == .show)
        #expect(policy.offer(.inputSource, value: "EN", at: at(30)) == .ignored)
    }

    @Test("A change within 150 ms of an app activation is ignored, at 150 ms it shows")
    func activationQuiet() {
        #expect(IndicatorPolicy.activationQuiet == 0.15)
        var policy = IndicatorPolicy()
        policy.appDidActivate(at: at(0))
        #expect(policy.offer(.inputSource, value: "DE", at: at(0.149)) == .ignored)
        #expect(policy.offer(.inputSource, value: "DE", at: at(0.15)) == .show)
    }

    @Test("An ignored change during the quiet leaves the last shown value alone")
    func quietKeepsTheLastShown() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        policy.appDidActivate(at: at(10))
        #expect(policy.offer(.inputSource, value: "EN", at: at(10.05)) == .ignored)
        // The source went back to the one that is shown: nothing to show.
        #expect(policy.offer(.inputSource, value: "DE", at: at(11)) == .ignored)
        #expect(policy.offer(.inputSource, value: "EN", at: at(12)) == .show)
    }

    @Test("A second different source within 400 ms is deferred to its end and shows then")
    func rateLimit() {
        #expect(IndicatorPolicy.inputSourceRateLimit == 0.4)
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        #expect(policy.offer(.inputSource, value: "EN", at: at(0.2)) == .deferred(until: at(0.4)))
        // A later one in the same window waits for the same end, never dropped.
        #expect(policy.offer(.inputSource, value: "FR", at: at(0.3)) == .deferred(until: at(0.4)))
        #expect(policy.offer(.inputSource, value: "FR", at: at(0.4)) == .show)
        #expect(policy.offer(.inputSource, value: "FR", at: at(0.5)) == .ignored)
    }

    @Test("The 400 ms edge acts one step either side")
    func rateLimitEdge() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        #expect(policy.offer(.inputSource, value: "EN", at: at(0.399)) == .deferred(until: at(0.4)))
        #expect(policy.offer(.inputSource, value: "EN", at: at(0.4)) == .show)
    }

    @Test("A change back to the shown value inside the window leaves nothing to show")
    func changeBackInsideTheWindow() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        #expect(policy.offer(.inputSource, value: "EN", at: at(0.1)) == .deferred(until: at(0.4)))
        #expect(policy.offer(.inputSource, value: "DE", at: at(0.2)) == .ignored)
    }

    @Test("Reset lets the same value show again, and the rate limit still holds")
    func resetKind() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        policy.reset(.inputSource)
        #expect(policy.offer(.inputSource, value: "DE", at: at(0.1)) == .deferred(until: at(0.4)))
        #expect(policy.offer(.inputSource, value: "DE", at: at(1)) == .show)
        #expect(policy.offer(.inputSource, value: "DE", at: at(2)) == .ignored)
        policy.reset(.inputSource)
        #expect(policy.offer(.inputSource, value: "DE", at: at(3)) == .show)
    }

    // MARK: Volume, brightness, gesture

    @Test("A second volume value within 50 ms waits for the end of it")
    func volumeCoalescing() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.volume, value: "0.5", at: at(0)) == .show)
        #expect(policy.offer(.volume, value: "0.6", at: at(0.03)) == .deferred(until: at(0.05)))
        #expect(policy.offer(.volume, value: "0.6", at: at(0.05)) == .show)
    }

    @Test("An identical volume value is not ignored, a held key at the range end still shows")
    func identicalVolumeShows() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.volume, value: "1.0", at: at(0)) == .show)
        #expect(policy.offer(.volume, value: "1.0", at: at(0.2)) == .show)
        #expect(policy.offer(.volume, value: "1.0", at: at(0.21)) == .deferred(until: at(0.25)))
    }

    @Test("Brightness and gesture coalesce to 50 ms and the activation quiet does not touch them")
    func otherKindsCoalesce() {
        var policy = IndicatorPolicy()
        policy.appDidActivate(at: at(0))
        for kind in [IndicatorKind.brightness, .gesture] {
            #expect(policy.offer(kind, value: "a", at: at(0.01)) == .show)
            #expect(policy.offer(kind, value: "b", at: at(0.04)) == .deferred(until: at(0.06)))
            #expect(policy.offer(kind, value: "b", at: at(0.06)) == .show)
        }
    }

    @Test("Each kind keeps its own last value and instant")
    func kindsAreIndependent() {
        var policy = IndicatorPolicy()
        #expect(policy.offer(.inputSource, value: "DE", at: at(0)) == .show)
        #expect(policy.offer(.volume, value: "DE", at: at(0.01)) == .show)
        #expect(policy.offer(.inputSource, value: "DE", at: at(0.02)) == .ignored)
        policy.reset(.volume)
        #expect(policy.offer(.inputSource, value: "DE", at: at(1)) == .ignored)
    }

    // MARK: IndicatorLook

    @Test("The kinds and their activity ids")
    func kindsAndIDs() {
        #expect(IndicatorKind.allCases.map(\.rawValue) == ["inputSource", "volume", "brightness", "gesture"])
        #expect(IndicatorLook.moduleID == "indicators")
        #expect(IndicatorLook.activityID(.inputSource) == "indicator-inputSource")
        #expect(IndicatorLook.activityID(.gesture) == "indicator-gesture")
    }

    @Test("A flash is one activity per kind, finished at once, with its own hold above thermal")
    func flashActivity() {
        let icon = URL(string: "file:///Library/Icons/de.png")
        let activity = IndicatorLook.flash(
            kind: .inputSource,
            symbol: "keyboard",
            value: "DE",
            title: "Input source German",
            at: at(0),
            flash: LiveActivityFlash(secondaryValue: "German", symbolImageURL: icon)
        )
        #expect(activity.id == "indicator-inputSource")
        #expect(activity.moduleID == "indicators")
        #expect(activity.key == "indicators/indicator-inputSource")
        #expect(activity.kind == .other)
        #expect(activity.tint == .accent)
        #expect(activity.symbol == "keyboard")
        #expect(activity.compactValue == "DE")
        #expect(activity.priority == 40)
        #expect(activity.priority > AlertLook.priority(for: .thermal))
        #expect(activity.startedAt == at(0))
        #expect(activity.finishedAt == at(0))
        #expect(activity.holdSeconds == 1.5)
        #expect(activity.expiresAt == at(1.5))
        #expect(activity.announcesItself)
        #expect(activity.isFlash)
        #expect(activity.flash?.secondaryValue == "German")
        #expect(activity.flash?.symbolImageURL == icon)
    }

    @Test("A second change replaces the first one and restarts the hold")
    func secondChangeRestartsTheHold() {
        let first = IndicatorLook.flash(kind: .inputSource, symbol: "keyboard", value: "DE", title: "t", at: at(0))
        let second = IndicatorLook.flash(
            kind: .inputSource, symbol: "keyboard", value: "EN", title: "t", at: at(1), hold: 2
        )
        let closed = HubActivityBoard.board([first, second], now: at(2.5), forClosedNotch: true)
        #expect(closed.listed.count == 1)
        #expect(closed.compact?.compactValue == "EN")
        #expect(HubActivityBoard.board([first, second], now: at(3), forClosedNotch: true).compact == nil)
    }

    @Test("A stored duration snaps to the nearest choice, a tie to the shorter, a non-number to the default")
    func durationSnaps() {
        #expect(IndicatorLook.inputSourceDuration(1.2) == 1)
        #expect(IndicatorLook.inputSourceDuration(1.25) == 1)
        #expect(IndicatorLook.inputSourceDuration(1.3) == 1.5)
        #expect(IndicatorLook.inputSourceDuration(9) == 3)
        #expect(IndicatorLook.inputSourceDuration(0.1) == 0.5)
        #expect(IndicatorLook.inputSourceDuration(-4) == 0.5)
        #expect(IndicatorLook.inputSourceDuration(.nan) == 1.5)
        #expect(IndicatorLook.inputSourceDuration(.infinity) == 1.5)
        for choice in DesignTokens.Indicator.inputSourceDurations {
            #expect(IndicatorLook.inputSourceDuration(choice) == choice)
        }
    }
}
