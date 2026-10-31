#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import HolzBarCore

@Suite("MenuBarDrop")
struct MenuBarDropTests {
    private enum Fixture {
        static let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        static let barMaxY: CGFloat = 24

        static let alwaysHiddenDivider: UInt32 = 3
        static let a: UInt32 = 10
        static let hiddenDivider: UInt32 = 2
        static let b: UInt32 = 11
        static let c: UInt32 = 12
        static let icon: UInt32 = 1
        static let controlCenter: UInt32 = 20

        static func item(
            _ id: UInt32,
            _ kind: MenuBarDrop.Item.Kind,
            x: CGFloat,
            width: CGFloat = 30
        ) -> MenuBarDrop.Item {
            MenuBarDrop.Item(id: id, kind: kind, frame: CGRect(x: x, y: 0, width: width, height: 24))
        }

        /// The bar with `b` at the given place and any extra items.
        static func bar(
            generation: MenuBarDrop.Generation = .before27,
            bX: CGFloat = 420,
            extra: [MenuBarDrop.Item] = []
        ) -> MenuBarDrop.Bar {
            MenuBarDrop.Bar(
                generation: generation,
                displayBounds: bounds,
                barMaxY: barMaxY,
                items: [
                    item(alwaysHiddenDivider, .alwaysHiddenDivider, x: 250, width: 18),
                    item(a, .app, x: 280),
                    item(hiddenDivider, .hiddenDivider, x: 380, width: 18),
                    item(b, .app, x: bX),
                    item(c, .app, x: 460),
                    item(icon, .holzBarIcon, x: 500, width: 26),
                    item(controlCenter, .system, x: 1300, width: 80),
                ] + extra
            )
        }
    }

    private let before27 = Fixture.bar()
    private let on27 = Fixture.bar(generation: .macOS27)
    private let dragged = Fixture.item(Fixture.b, .app, x: 420)

    private func target(
        _ x: CGFloat,
        y: CGFloat = 12,
        in bar: MenuBarDrop.Bar? = nil
    ) -> MenuBarDrop.Target? {
        MenuBarDrop.resolve(forDropAt: CGPoint(x: x, y: y), draggedID: Fixture.b, in: bar ?? before27).target
    }

    // MARK: Bar

    @Test("The bar finds the counted item under a point inside the bar strip")
    func barFindsItems() {
        #expect(before27.item(at: CGPoint(x: 435, y: 12))?.id == Fixture.b)
        #expect(before27.item(at: CGPoint(x: 435, y: 30)) == nil)
    }

    @Test("An item of 4 points or less takes no room and is never found")
    func narrowItemsDoNotCount() {
        let narrow = Fixture.item(99, .app, x: 700, width: 3)
        let bar = Fixture.bar(extra: [narrow])
        #expect(bar.item(at: CGPoint(x: 701, y: 12)) == nil)
        #expect(!narrow.counts)
        #expect(Fixture.item(98, .app, x: 700, width: 5).counts)
    }

    @Test("The bar finds nothing outside the display")
    func barIgnoresOtherDisplays() {
        #expect(before27.item(at: CGPoint(x: -20, y: 12)) == nil)
        #expect(before27.item(at: CGPoint(x: 1600, y: 12)) == nil)
    }

    // MARK: Target

    @Test("The right half of an item gives rightOf, the left half leftOf")
    func halves() {
        #expect(target(480) == .rightOf(Fixture.c))
        #expect(target(465) == .leftOf(Fixture.c))
    }

    @Test("A gap gives the item on its right, past the last item the last one")
    func gaps() {
        #expect(target(455) == .leftOf(Fixture.c))
        #expect(target(1450) == .rightOf(Fixture.controlCenter))
    }

    @Test("The dragged item is never its own target")
    func notItself() {
        #expect(target(435) == .leftOf(Fixture.c))
    }

    @Test("A release below the bar has no target")
    func belowTheBar() {
        #expect(target(480, y: 30) == nil)
        #expect(target(480, y: 28) != nil)
    }

    @Test("On macOS 27 holzBar's icon is the hidden section, before it an item with halves")
    func iconOn27() {
        #expect(target(510, in: on27) == .section(.hidden))
        #expect(target(505, in: before27) == .leftOf(Fixture.icon))
        #expect(target(520, in: before27) == .rightOf(Fixture.icon))
    }

    // MARK: Resolve on a bar modelled on a real one

    /// A 1512 point display with the bar bottom at 33: an app item P left of holzBar's icon, the
    /// icon, apps A and B right of it, the collapsed divider and two system items.
    private enum RealBar {
        static let p: UInt32 = 30
        static let icon: UInt32 = 31
        static let divider: UInt32 = 32
        static let a: UInt32 = 33
        static let b: UInt32 = 34
        static let system: UInt32 = 35

        static func item(_ id: UInt32, _ kind: MenuBarDrop.Item.Kind, x: CGFloat, width: CGFloat) -> MenuBarDrop.Item {
            MenuBarDrop.Item(id: id, kind: kind, frame: CGRect(x: x, y: 0, width: width, height: 33))
        }

        static let bar = MenuBarDrop.Bar(
            generation: .macOS27,
            displayBounds: CGRect(x: 0, y: 0, width: 1512, height: 982),
            barMaxY: 33,
            items: [
                item(p, .app, x: 760, width: 26),
                item(icon, .holzBarIcon, x: 1007, width: 35),
                item(divider, .hiddenDivider, x: 1300, width: 2),
                item(a, .app, x: 1105, width: 26),
                item(b, .app, x: 1140, width: 30),
                item(system, .system, x: 1196, width: 26),
                item(36, .system, x: 1383, width: 109),
            ]
        )
    }

    private func resolve(
        _ x: CGFloat,
        y: CGFloat = 12,
        dragged: UInt32 = RealBar.a,
        settled: CGRect? = nil,
        shelf: CGRect? = nil
    ) -> MenuBarDrop.Resolution {
        MenuBarDrop.resolve(
            forDropAt: CGPoint(x: x, y: y),
            draggedID: dragged,
            in: RealBar.bar,
            settledIconFrame: settled,
            shelfZone: shelf
        )
    }

    @Test("A release inside the icon's frame hides, with the zone icon")
    func dropOnTheIcon() {
        #expect(resolve(1020) == MenuBarDrop.Resolution(target: .section(.hidden), zone: .icon))
    }

    @Test("A release three points left of the icon is still on it, in the margin")
    func dropInTheMargin() {
        #expect(resolve(1004) == MenuBarDrop.Resolution(target: .section(.hidden), zone: .iconMargin))
    }

    @Test("An item that came from the right finds the icon slid right by its width and the gap")
    func iconShifted() {
        // A is 26 wide: the icon slides to 1037...1072.
        #expect(resolve(1060) == MenuBarDrop.Resolution(target: .section(.hidden), zone: .iconShifted))
        // The same point from the left of the icon is not on a shifted icon.
        #expect(resolve(1060, dragged: RealBar.p).target != .section(.hidden))
    }

    @Test("An item that came from the left finds the icon slid left")
    func iconShiftedLeft() {
        // P is 26 wide: the icon slides to 977...1012.
        #expect(resolve(985, dragged: RealBar.p) == MenuBarDrop.Resolution(target: .section(.hidden), zone: .iconShifted))
    }

    @Test("The icon where the settled bar has it counts too")
    func iconSettled() {
        let settled = CGRect(x: 1033, y: 0, width: 35, height: 33)
        #expect(resolve(1086, dragged: RealBar.p, settled: settled).zone != .iconSettled)
        #expect(
            resolve(1066, dragged: RealBar.p, settled: settled)
                == MenuBarDrop.Resolution(target: .section(.hidden), zone: .iconSettled)
        )
    }

    @Test("A release on the neighbour area is not the icon")
    func neighbourIsNotTheIcon() {
        let resolution = resolve(1090)
        #expect(resolution.target == .leftOf(RealBar.b))
        #expect(resolution.zone == .gap)
        #expect(resolve(1150, dragged: RealBar.a).zone == .item)
    }

    @Test("Below the bar a release has no target without a Shelf zone")
    func belowTheBarOn27() {
        #expect(resolve(1020, y: 120) == MenuBarDrop.Resolution(target: nil, zone: .outsideBar))
    }

    @Test("Below the bar a release inside the Shelf zone hides, and the Shelf wins over the icon")
    func dropOnTheShelf() {
        let shelf = CGRect(x: 600, y: 33, width: 300, height: 367)
        #expect(resolve(700, y: 120, shelf: shelf) == MenuBarDrop.Resolution(target: .section(.hidden), zone: .shelf))
        #expect(resolve(1020, y: 120, shelf: CGRect(x: 900, y: 33, width: 300, height: 367)).zone == .shelf)
        #expect(resolve(1500, y: 120, shelf: shelf) == MenuBarDrop.Resolution(target: nil, zone: .outsideBar))
    }

    @Test("A dragged item that is not an app item never resolves to hide")
    func onlyAppItemsHide() {
        let resolution = resolve(1020, dragged: RealBar.system)
        let dragged = RealBar.item(RealBar.system, .system, x: 1196, width: 26)
        let intent = MenuBarDrop.intent(for: resolution.target, dragged: dragged, in: RealBar.bar, currentSection: nil)
        #expect(intent == .refused(.notAnAppItem))
    }

    @Test("Before macOS 27 the icon and the Shelf zone change nothing")
    func before27Unchanged() {
        let bar = MenuBarDrop.Bar(
            generation: .before27,
            displayBounds: RealBar.bar.displayBounds,
            barMaxY: RealBar.bar.barMaxY,
            items: RealBar.bar.items
        )
        let onIcon = MenuBarDrop.resolve(forDropAt: CGPoint(x: 1020, y: 12), draggedID: RealBar.a, in: bar)
        #expect(onIcon.zone == .item)
        let shelf = CGRect(x: 600, y: 33, width: 300, height: 367)
        let below = MenuBarDrop.resolve(forDropAt: CGPoint(x: 700, y: 120), draggedID: RealBar.a, in: bar, shelfZone: shelf)
        #expect(below == MenuBarDrop.Resolution(target: nil, zone: .outsideBar))
    }

    // MARK: Summary

    @Test("The summary is made of fixed words only")
    func summaryWords() {
        let hide = MenuBarDrop.Intent.setSection(item: 7, section: .hidden)
        #expect(
            MenuBarDrop.summary(generation: .macOS27, zone: .shelf, intent: hide, result: .applied)
                == "macOS 27, shelf, hide, applied"
        )
        #expect(
            MenuBarDrop.summary(generation: .before27, zone: .gap, intent: .move(item: 7, target: .leftOf(8)), result: .noChange)
                == "before 27, gap, order, no change"
        )
        #expect(
            MenuBarDrop.summary(generation: .macOS27, zone: .outsideBar, intent: .refused(.outsideTheBar), result: .notApplied)
                == "macOS 27, outsideBar, refused, outside the bar, not applied"
        )
        #expect(MenuBarDrop.summary(generation: .macOS27, zone: .item, intent: nil, result: .noChange) == "macOS 27, item, none, no change")
    }

    // MARK: Intent

    @Test("Before macOS 27 a neighbour target moves the item next to it")
    func intentMovesBefore27() {
        let intent = MenuBarDrop.intent(
            for: .rightOf(Fixture.c), dragged: dragged, in: before27, currentSection: .visible
        )
        #expect(intent == .move(item: Fixture.b, target: .rightOf(Fixture.c)))
    }

    @Test("No target is refused as outside the bar")
    func intentOutsideTheBar() {
        let intent = MenuBarDrop.intent(for: nil, dragged: dragged, in: before27, currentSection: nil)
        #expect(intent == .refused(.outsideTheBar))
    }

    @Test("A system item and holzBar's own items are never moved")
    func intentOnlyAppItems() {
        let system = Fixture.item(Fixture.controlCenter, .system, x: 1300, width: 80)
        let own = Fixture.item(Fixture.icon, .holzBarIcon, x: 500, width: 26)
        let other = Fixture.item(77, .holzBarOther, x: 600)
        for item in [system, own, other] {
            let intent = MenuBarDrop.intent(for: .leftOf(Fixture.c), dragged: item, in: before27, currentSection: nil)
            #expect(intent == .refused(.notAnAppItem))
        }
    }

    @Test("On macOS 27 a drop on holzBar's icon sets the section to hidden")
    func intentSectionOn27() {
        let intent = MenuBarDrop.intent(for: .section(.hidden), dragged: dragged, in: on27, currentSection: .visible)
        #expect(intent == .setSection(item: Fixture.b, section: .hidden))
    }

    @Test("On macOS 27 a neighbour target is macOS's own reorder")
    func intentNeighbourOn27() {
        let intent = MenuBarDrop.intent(for: .rightOf(Fixture.c), dragged: dragged, in: on27, currentSection: .visible)
        #expect(intent == .macOSOrders(item: Fixture.b))
        let unknown = MenuBarDrop.intent(for: .rightOf(Fixture.c), dragged: dragged, in: on27, currentSection: nil)
        #expect(unknown == .macOSOrders(item: Fixture.b))
    }

    @Test("On macOS 27 a hidden or always hidden item dropped elsewhere becomes visible")
    func intentHiddenItemOn27() {
        for saved in [MenuBarDrop.Section.hidden, .alwaysHidden] {
            let intent = MenuBarDrop.intent(for: .leftOf(Fixture.c), dragged: dragged, in: on27, currentSection: saved)
            #expect(intent == .setSection(item: Fixture.b, section: .visible))
        }
    }

    // MARK: Placement

    @Test("An item between the hidden divider and its neighbour is placed left of that neighbour")
    func placementLeftOfRightNeighbour() {
        // b sits between the hidden divider and c.
        #expect(MenuBarDrop.placement(of: Fixture.b, in: before27) == .leftOf(Fixture.c))
    }

    @Test("The rightmost counted item is placed right of its left neighbour")
    func placementRightOfLeftNeighbour() {
        let bar = Fixture.bar(bX: 1450)
        #expect(MenuBarDrop.placement(of: Fixture.b, in: bar) == .rightOf(Fixture.controlCenter))
    }

    @Test("An item alone on the bar has no placement")
    func placementWithoutNeighbours() {
        let alone = MenuBarDrop.Bar(
            generation: .before27,
            displayBounds: Fixture.bounds,
            barMaxY: Fixture.barMaxY,
            items: [Fixture.item(Fixture.b, .app, x: 420)]
        )
        #expect(MenuBarDrop.placement(of: Fixture.b, in: alone) == nil)
    }

    @Test("A missing or narrow item has no placement and narrow items are never neighbours")
    func placementOfUncountedItems() {
        #expect(MenuBarDrop.placement(of: 4242, in: before27) == nil)
        let narrowDragged = MenuBarDrop.Bar(
            generation: .before27,
            displayBounds: Fixture.bounds,
            barMaxY: Fixture.barMaxY,
            items: [
                Fixture.item(Fixture.a, .app, x: 280),
                Fixture.item(Fixture.b, .app, x: 420, width: 4),
                Fixture.item(Fixture.c, .app, x: 460),
            ]
        )
        #expect(MenuBarDrop.placement(of: Fixture.b, in: narrowDragged) == nil)
        let narrowNeighbour = MenuBarDrop.Bar(
            generation: .before27,
            displayBounds: Fixture.bounds,
            barMaxY: Fixture.barMaxY,
            items: [
                Fixture.item(Fixture.b, .app, x: 420),
                Fixture.item(Fixture.c, .app, x: 460, width: 4),
            ]
        )
        #expect(MenuBarDrop.placement(of: Fixture.b, in: narrowNeighbour) == nil)
    }
}
