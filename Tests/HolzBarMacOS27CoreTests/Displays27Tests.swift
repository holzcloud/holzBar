import CoreGraphics
import Foundation
import Testing
@testable import HolzBarMacOS27Core

@Suite("NotchCover27")
struct NotchCover27Tests {
    // A 14-inch MacBook: the notch covers x 662...850.
    let notch: ClosedRange<CGFloat> = 662...850
    let own = "com.holzcloud.holzBar"

    @Test("The icon under the notch frees itself")
    func iconUnderTheNotchFreesItself() {
        let icon = CGRect(x: 760, y: 0, width: 28, height: 37)
        let a = (bundleID: "a", frame: CGRect(x: 790, y: 0, width: 100, height: 37))
        let b = (bundleID: "b", frame: CGRect(x: 892, y: 0, width: 30, height: 37))
        // 90 points are needed; a alone frees 100.
        #expect(NotchCover27.appsToConceal(iconFrame: icon, visibleApps: [b, a], notchSpan: notch, concealed: [], ownBundleID: own) == ["a"])
        // Narrower apps: a frees 60, so b is needed too.
        let narrowA = (bundleID: "a", frame: CGRect(x: 790, y: 0, width: 60, height: 37))
        #expect(NotchCover27.appsToConceal(iconFrame: icon, visibleApps: [narrowA, b], notchSpan: notch, concealed: [], ownBundleID: own) == ["a", "b"])
        // The icon is clear of the notch.
        let clearIcon = CGRect(x: 860, y: 0, width: 28, height: 37)
        #expect(NotchCover27.appsToConceal(iconFrame: clearIcon, visibleApps: [a, b], notchSpan: notch, concealed: [], ownBundleID: own).isEmpty)
    }

    @Test("Only visible apps are concealed")
    func onlyVisibleAppsAreConcealed() {
        let icon = CGRect(x: 760, y: 0, width: 28, height: 37)
        let ownItem = (bundleID: own, frame: CGRect(x: 790, y: 0, width: 200, height: 37))
        let concealedApp = (bundleID: "c", frame: CGRect(x: 990, y: 0, width: 200, height: 37))
        let a = (bundleID: "a", frame: CGRect(x: 1190, y: 0, width: 100, height: 37))
        let answer = NotchCover27.appsToConceal(iconFrame: icon, visibleApps: [ownItem, concealedApp, a], notchSpan: notch, concealed: ["c"], ownBundleID: own)
        #expect(answer == ["a"])
    }

    @Test("Apps concealed for the notch join every assertion")
    func notchAppsJoinEveryAssertion() {
        #expect(NotchCover27.adding([], to: [["x"]]) == [["x"]])
        #expect(NotchCover27.adding(["a"], to: []) == [["a"]])
        #expect(NotchCover27.adding(["a"], to: [["x"], ["x", "y"]]) == [["x", "a"], ["x", "y", "a"]])
    }
}

@Suite("LaunchGrace27")
struct LaunchGrace27Tests {
    // The grace is changed outside `#expect`, whose expansion cannot call a mutating method.

    private let start = ContinuousClock.now

    @Test("A launching app is allowed until its item appears")
    func allowedUntilItsItemAppears() {
        var grace = LaunchGrace27()
        grace.begin("a", isConcealed: true, at: start)
        #expect(grace.allowed == ["a"])
        let ended = grace.itemsAppeared(["a", "b"])
        #expect(ended == ["a"])
        #expect(grace.allowed.isEmpty)
        // A grace ends once.
        let endedAgain = grace.itemsAppeared(["a"])
        #expect(endedAgain.isEmpty)
    }

    @Test("A grace ends after 10 s without an item")
    func endsAfterTenSeconds() {
        var grace = LaunchGrace27()
        grace.begin("a", isConcealed: true, at: start)
        let early = grace.expired(at: start + .seconds(9))
        #expect(early.isEmpty)
        let late = grace.expired(at: start + .seconds(10))
        #expect(late == ["a"])
        #expect(grace.allowed.isEmpty)
    }

    @Test("Visible apps get no grace")
    func visibleAppsGetNoGrace() {
        var grace = LaunchGrace27()
        let began = grace.begin("v", isConcealed: false, at: start)
        #expect(!began)
        #expect(grace.allowed.isEmpty)
    }
}
