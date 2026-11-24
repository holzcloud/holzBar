import Foundation
import Testing
@testable import HolzBarCore

@Suite("Menu bar fit")
struct MenuBarFitTests {
    /// An app of the given item widths, movable unless said otherwise.
    private func app(
        _ key: String,
        _ widths: [Double] = [34],
        movable: Bool = true,
        clicks: Int? = nil,
        launchedAt: Date? = nil,
        distance: Double = 0
    ) -> MenuBarFit.App {
        MenuBarFit.App(
            key: key,
            name: key,
            itemWidths: widths,
            isMovable: movable,
            clicks: clicks,
            launchedAt: launchedAt,
            distanceFromNotch: distance
        )
    }

    private func input(
        room: Double? = 643,
        apps: [MenuBarFit.App],
        native: MenuBarFit.Native = .none,
        wasOverflowing: Bool = false
    ) -> MenuBarFit.Input {
        MenuBarFit.Input(room: room, apps: apps, native: native, revealsAll: false, wasOverflowing: wasOverflowing)
    }

    /// `count` one-item apps of 34 points, nearest the notch first.
    private func apps(_ count: Int) -> [MenuBarFit.App] {
        (0..<count).map { app("app\($0)", distance: Double($0) * 32) }
    }

    // MARK: - Room

    @Test("The room beside a notch is the right side minus 130 minus 17 points")
    func roomBesideNotch() {
        #expect(MenuBarFit.room(rightAreaWidth: 790) == 643)
        #expect(MenuBarFit.room(rightAreaWidth: 100) == 0)
    }

    @Test("The room without a notch is the space right of the frontmost application's menu minus the same two values")
    func roomWithoutNotch() {
        #expect(MenuBarFit.room(displayMaxX: 1512, applicationMenuMaxX: 600) == 765)
        // A menu that reaches into the system items leaves no room, never a negative one.
        #expect(MenuBarFit.room(displayMaxX: 1512, applicationMenuMaxX: 1500) == 0)
        #expect(MenuBarFit.room(displayMaxX: 1512, applicationMenuMaxX: 1512) == 0)
        // A frame that is not a number leaves no room.
        #expect(MenuBarFit.room(displayMaxX: 1512, applicationMenuMaxX: .nan) == 0)
        #expect(MenuBarFit.room(rightAreaWidth: .infinity) == 0)
    }

    // MARK: - Widths

    @Test("An app's width is the sum of its items minus 2 points per neighbour, and it frees its width minus 2")
    func appWidth() {
        let three = app("three", [34, 34, 34])
        #expect(three.width == 98)
        #expect(three.pitch == 96)
        let one = app("one", [34])
        #expect(one.width == 34)
        #expect(one.pitch == 32)
        let none = app("none", [])
        #expect(none.width == 0)
        #expect(none.pitch == 0)
    }

    // MARK: - Prediction

    @Test("Five one-item apps in a room of 643 fit")
    func fivefit() {
        #expect(MenuBarFit.evaluate(input(apps: apps(5))) == .fits)
    }

    @Test("Twenty-one one-item apps (674 points) do not fit and one item has to go")
    func twentyOneDoNotFit() {
        let verdict = MenuBarFit.evaluate(input(apps: apps(21)))
        #expect(verdict == .doesNotFit(items: 1))
        #expect(verdict.isOverflowing)
    }

    @Test("A sum exactly equal to the room fits, one point above does not")
    func boundary() {
        // One item has no overlap: its width is the sum.
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [643])])) == .fits)
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [644])])) == .doesNotFit(items: 1))
        // Neighbours overlap: 321 + 322 - 2 = 641; 322 + 323 - 2 = 643 fits; 323 + 323 - 2 = 644 does not.
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [322]), app("b", [323])])) == .fits)
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [323]), app("b", [323])])) == .doesNotFit(items: 1))
    }

    @Test("The number of items that do not fit counts items, not apps")
    func itemsAreNotApps() {
        // One app of ten 34-point items is 322 wide; two of them are 642 wide: they fit.
        let tenItems = Array(repeating: 34.0, count: 10)
        let fitting = input(apps: [app("a", tenItems, distance: 0), app("b", tenItems, distance: 400)])
        #expect(MenuBarFit.evaluate(fitting) == .fits)
        // Three of them are 962 wide: 319 points too many, 10 items of 32 points free 320.
        let tooMany = input(apps: [
            app("a", tenItems, distance: 0),
            app("b", tenItems, distance: 400),
            app("c", tenItems, distance: 800),
        ])
        #expect(MenuBarFit.evaluate(tooMany) == .doesNotFit(items: 10))
        // The planner moves apps, so the pass is smaller than the item count.
        #expect(MenuBarFit.plan(tooMany, verdict: .doesNotFit(items: 10), usesUsage: false).count < 10)
    }

    @Test("An overflowing bar clears only at the room minus the margin")
    func hysteresis() {
        let near = input(apps: [app("a", [630])], wasOverflowing: true)
        #expect(MenuBarFit.evaluate(near) == .doesNotFit(items: 1))
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [630])], wasOverflowing: false)) == .fits)
        // 611 is the room minus the 32-point margin: it clears.
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [611])], wasOverflowing: true)) == .fits)
        #expect(MenuBarFit.evaluate(input(apps: [app("a", [612])], wasOverflowing: true)) == .doesNotFit(items: 1))
    }

    @Test("The policy's numbers are pinned")
    func policy() {
        #expect(MenuBarFit.Policy.itemOverlap == 2)
        #expect(MenuBarFit.Policy.systemItemsSpan == 130)
        #expect(MenuBarFit.Policy.overflowControlWidth == 17)
        #expect(MenuBarFit.Policy.margin == 32)
        #expect(MenuBarFit.Policy.maximumPerPass == 3)
        #expect(MenuBarFit.Policy.bannerSettle == .seconds(3))
        #expect(MenuBarFit.Policy.quietAfterPass == .seconds(3))
    }

    @Test("No Visible app fits, whatever the room")
    func emptyFits() {
        #expect(MenuBarFit.evaluate(input(apps: [])) == .fits)
        #expect(MenuBarFit.evaluate(input(room: nil, apps: [], native: .unknown)) == .fits)
        #expect(MenuBarFit.evaluate(input(apps: [app("none", [])])) == .fits)
    }

    @Test("Without a room the verdict is unknown")
    func unknownWithoutRoom() {
        #expect(MenuBarFit.evaluate(input(room: nil, apps: apps(3), native: .unknown)) == .unknown)
        #expect(!MenuBarFit.Verdict.unknown.isOverflowing)
        #expect(!MenuBarFit.Verdict.fits.isOverflowing)
    }

    // MARK: - Planner

    @Test("The plan takes movable apps only")
    func movableOnly() {
        let list = [app("own", movable: false), app("apple", movable: false), app("tool")]
        let plan = MenuBarFit.plan(input(room: 40, apps: list), verdict: .doesNotFit(items: 2), usesUsage: false)
        #expect(plan.map(\.key) == ["tool"])
    }

    @Test("The plan is empty when nothing may move")
    func nothingMovable() {
        let list = [app("own", movable: false), app("apple", movable: false)]
        #expect(MenuBarFit.plan(input(room: 40, apps: list), verdict: .doesNotFit(items: 1), usesUsage: true).isEmpty)
    }

    @Test("The plan is empty when the bar fits")
    func fitsMeansEmptyPlan() {
        #expect(MenuBarFit.plan(input(apps: apps(3)), verdict: .fits, usesUsage: true).isEmpty)
        #expect(MenuBarFit.plan(input(apps: apps(3)), verdict: .unknown, usesUsage: true).isEmpty)
    }

    @Test("The plan moves at most 3 apps")
    func atMostThree() {
        let plan = MenuBarFit.plan(input(room: 40, apps: apps(8)), verdict: .doesNotFit(items: 7), usesUsage: false)
        #expect(plan.count == 3)
    }

    @Test("The plan stops once the freed pitches reach the deficit")
    func stopsAtDeficit() {
        // Ten 34-point apps are 322 points wide; a room of 282 minus the 32-point margin leaves 250,
        // so 72 points have to go: apps free 32 points each, three of them free 96.
        let tenApps = apps(10)
        let plan = MenuBarFit.plan(input(room: 282, apps: tenApps), verdict: .doesNotFit(items: 3), usesUsage: false)
        #expect(plan.count == 3)
        // Nine apps are 290 points wide; a room of 302 leaves 270, a deficit of 20: one app is enough.
        let nineApps = apps(9)
        #expect(MenuBarFit.plan(input(room: 302, apps: nineApps), verdict: .doesNotFit(items: 1), usesUsage: false).count == 1)
        // One app frees 32; a deficit of 33 needs two.
        let twoApps = apps(2)
        let two = MenuBarFit.plan(input(room: 66 - 33 + 32, apps: twoApps), verdict: .doesNotFit(items: 1), usesUsage: false)
        #expect(two.count == 2)
    }

    @Test("With usage on, the apps used least go first")
    func usageOrder() {
        let list = [app("five", clicks: 5), app("none", clicks: 0), app("two", clicks: 2)]
        let plan = MenuBarFit.plan(input(room: 40, apps: list), verdict: .doesNotFit(items: 2), usesUsage: true)
        #expect(plan.map(\.key) == ["none", "two", "five"])
    }

    @Test("Equal clicks put the newer launch first, then the app nearer the notch")
    func usageTies() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let list = [
            app("old", clicks: 1, launchedAt: old, distance: 0),
            app("new", clicks: 1, launchedAt: new, distance: 100),
            app("unknown", clicks: 1, launchedAt: nil, distance: 50),
        ]
        let plan = MenuBarFit.plan(input(room: 40, apps: list), verdict: .doesNotFit(items: 2), usesUsage: true)
        #expect(plan.map(\.key) == ["new", "old", "unknown"])
        let sameLaunch = [
            app("far", clicks: 1, launchedAt: new, distance: 90),
            app("near", clicks: 1, launchedAt: new, distance: 10),
        ]
        let nearFirst = MenuBarFit.plan(input(room: 40, apps: sameLaunch), verdict: .doesNotFit(items: 1), usesUsage: true)
        #expect(nearFirst.map(\.key) == ["near", "far"])
    }

    @Test("With usage off, clicks are ignored and the newest launch goes first")
    func newestFirstWithoutUsage() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let list = [
            app("busy-old", clicks: 0, launchedAt: old),
            app("busy-new", clicks: 99, launchedAt: new),
        ]
        let plan = MenuBarFit.plan(input(room: 40, apps: list), verdict: .doesNotFit(items: 1), usesUsage: false)
        #expect(plan.map(\.key) == ["busy-new", "busy-old"])
    }

    @Test("An app with no clicks recorded counts as unused while usage is on")
    func missingClicksAreZero() {
        let list = [app("some", clicks: 3), app("unrecorded", clicks: nil)]
        let plan = MenuBarFit.plan(input(room: 40, apps: list), verdict: .doesNotFit(items: 1), usesUsage: true)
        #expect(plan.first?.key == "unrecorded")
    }
}
