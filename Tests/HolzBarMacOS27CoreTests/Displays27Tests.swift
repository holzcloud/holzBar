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

    @Test("Only sections that conceal more free room for the notch")
    func freeRoom() {
        // Hiding the Hidden section again conceals more.
        #expect(NotchCover27.sectionsMayFreeRoom(before: ["x"], after: ["x", "h"]))
        // A layout edit that moves one app into a concealed section and another out of it.
        #expect(NotchCover27.sectionsMayFreeRoom(before: ["x"], after: ["y"]))
        // Revealing the Hidden section conceals less, so the bar is no roomier.
        #expect(!NotchCover27.sectionsMayFreeRoom(before: ["x", "h"], after: ["x"]))
        #expect(!NotchCover27.sectionsMayFreeRoom(before: ["x"], after: ["x"]))
        #expect(!NotchCover27.sectionsMayFreeRoom(before: ["x"], after: []))
    }

    /// The display change with the defaults of a move from a notched 1512-point display to a
    /// wider external one, with folded items, while concealing; each test changes one input.
    private func change(
        previousID: CGDirectDisplayID? = 1,
        currentID: CGDirectDisplayID = 2,
        previousWidth: CGFloat = 1512,
        currentWidth: CGFloat = 2560,
        hasNotch: Bool = false,
        notchConcealedEmpty: Bool = true,
        hadFoldedItems: Bool = true,
        hasFoldedItemsNow: Bool = true,
        isConcealing: Bool = true
    ) -> NotchCover27.DisplayChange {
        NotchCover27.displayChange(
            previousID: previousID,
            currentID: currentID,
            previousWidth: previousWidth,
            currentWidth: currentWidth,
            hasNotch: hasNotch,
            notchConcealedEmpty: notchConcealedEmpty,
            hadFoldedItems: hadFoldedItems,
            hasFoldedItemsNow: hasFoldedItemsNow,
            isConcealing: isConcealing
        )
    }

    @Test("The same display, or none before, changes nothing")
    func sameOrNoPreviousDisplay() {
        #expect(change(currentID: 1) == .none)
        #expect(change(currentID: 1, notchConcealedEmpty: false) == .none)
        #expect(change(previousID: nil) == .none)
        #expect(change(previousID: nil, notchConcealedEmpty: false) == .none)
    }

    @Test("Another display with apps concealed for the notch works them out again")
    func notchConcealedRecomputes() {
        #expect(change(notchConcealedEmpty: false) == .recompute)
        // Whatever else holds.
        #expect(change(hasNotch: true, notchConcealedEmpty: false, hadFoldedItems: false, isConcealing: false) == .recompute)
    }

    @Test("A roomier display with folded items while concealing lays the bar out again")
    func roomierRelayouts() {
        // No notch.
        #expect(change(currentWidth: 1200) == .relayout)
        // A notch, but wider.
        #expect(change(hasNotch: true) == .relayout)
    }

    @Test("No folded items, not roomier or not concealing changes nothing")
    func otherwiseNothing() {
        #expect(change(hadFoldedItems: false) == .none)
        #expect(change(currentWidth: 1512, hasNotch: true) == .none)
        #expect(change(currentWidth: 1200, hasNotch: true) == .none)
        #expect(change(isConcealing: false) == .none)
    }

    @Test("Moving to a roomier display whose read shows no fold does not relayout")
    func roomierWithoutFoldStays() {
        // The old display's bar was crowded, the new one shows everything: an ordinary switch
        // between apps on two displays never releases the concealment.
        #expect(change(hasFoldedItemsNow: false) == .none)
        #expect(change(hasNotch: true, hasFoldedItemsNow: false) == .none)
        #expect(change(currentWidth: 1200, hasFoldedItemsNow: false) == .none)
        // The apps concealed for the notch are still worked out again.
        #expect(change(notchConcealedEmpty: false, hasFoldedItemsNow: false) == .recompute)
    }

    @Test("Folded items count only on the display that holds the overflow button")
    func foldedItemsOnTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let chevron = CGRect(x: 900, y: 0, width: 30, height: 24)
        let folded = CGRect(x: 905, y: 0, width: 22, height: 24)
        let drawn = CGRect(x: 1000, y: 0, width: 22, height: 24)
        #expect(NotchCover27.showsFoldedItems(itemFrames: [drawn, folded], chevronFrame: chevron, displayBounds: display))
        #expect(!NotchCover27.showsFoldedItems(itemFrames: [drawn], chevronFrame: chevron, displayBounds: display))
        #expect(!NotchCover27.showsFoldedItems(itemFrames: [folded], chevronFrame: nil, displayBounds: display))
        // A display stacked above: an item of its bar shares the button's horizontal span, but
        // the button sits on the other display, so nothing is folded there.
        let above = CGRect(x: 0, y: -1440, width: 2560, height: 1440)
        let itemAbove = CGRect(x: 905, y: -1440, width: 22, height: 24)
        #expect(!NotchCover27.showsFoldedItems(itemFrames: [itemAbove], chevronFrame: chevron, displayBounds: above))
        // An item of the other display never counts for this one.
        #expect(!NotchCover27.showsFoldedItems(itemFrames: [itemAbove], chevronFrame: chevron, displayBounds: display))
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
