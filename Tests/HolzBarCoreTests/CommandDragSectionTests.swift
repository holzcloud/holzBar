#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import HolzBarCore

@Suite("CommandDragSection")
struct CommandDragSectionTests {
    private enum Fixture {
        static let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)
        static let barMaxY: CGFloat = 24

        static let icon: UInt32 = 1
        static let hiddenDivider: UInt32 = 2
        static let leftA: UInt32 = 10
        static let leftB: UInt32 = 11
        static let rightA: UInt32 = 12
        static let rightB: UInt32 = 13
        static let extraApp: UInt32 = 14
        static let controlCenter: UInt32 = 20
        static let widget: UInt32 = 30

        static func kind(of id: UInt32) -> MenuBarDrop.Item.Kind {
            switch id {
            case icon: .holzBarIcon
            case hiddenDivider: .hiddenDivider
            case controlCenter: .system
            case widget: .holzBarOther
            default: .app
            }
        }

        static func width(of id: UInt32) -> CGFloat {
            switch id {
            case icon: 26
            case hiddenDivider: 18
            case controlCenter: 80
            default: 30
            }
        }

        /// A bar with the items in the given order, laid out from the left with 4 points between.
        static func bar(_ order: [UInt32], widths: [UInt32: CGFloat] = [:]) -> MenuBarDrop.Bar {
            var x: CGFloat = 400
            var items: [MenuBarDrop.Item] = []
            for id in order {
                let width = widths[id] ?? Fixture.width(of: id)
                items.append(MenuBarDrop.Item(id: id, kind: kind(of: id), frame: CGRect(x: x, y: 0, width: width, height: 24)))
                x += width + 4
            }
            return MenuBarDrop.Bar(generation: .macOS27, displayBounds: bounds, barMaxY: barMaxY, items: items)
        }

        static func frame(of id: UInt32, in bar: MenuBarDrop.Bar) -> CGRect {
            bar.items.first { $0.id == id }?.frame ?? .zero
        }

        /// The centre of an item in a bar, as a pointer position inside the bar strip.
        static func point(on id: UInt32, in bar: MenuBarDrop.Bar) -> CGPoint {
            CGPoint(x: frame(of: id, in: bar).midX, y: 12)
        }

        static func point(x: CGFloat) -> CGPoint {
            CGPoint(x: x, y: 12)
        }
    }

    /// Two apps left of the icon, two right of it: A B | icon | C D.
    private let press = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.icon, Fixture.rightA, Fixture.rightB])

    // MARK: Crossing

    @Test("An app dragged from right of the icon to its left is set hidden")
    func rightToLeftIsHidden() {
        let settled = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.rightA, Fixture.icon, Fixture.rightB])
        let decision = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: press,
            pressPoint: Fixture.point(on: Fixture.rightA, in: press),
            release: Fixture.point(x: 440),
            settled: settled
        )
        #expect(decision == .set(.hidden))
    }

    @Test("An app dragged from left of the icon to its right is set visible")
    func leftToRightIsVisible() {
        let settled = Fixture.bar([Fixture.leftB, Fixture.icon, Fixture.rightA, Fixture.leftA, Fixture.rightB])
        let decision = CommandDragSection.decide(
            draggedID: Fixture.leftA,
            press: press,
            pressPoint: Fixture.point(on: Fixture.leftA, in: press),
            release: Fixture.point(x: 560),
            settled: settled
        )
        #expect(decision == .set(.visible))
    }

    @Test("A reorder on the left of the icon crosses nothing")
    func reorderLeftCrossesNothing() {
        let settled = Fixture.bar([Fixture.leftB, Fixture.leftA, Fixture.icon, Fixture.rightA, Fixture.rightB])
        let decision = CommandDragSection.decide(
            draggedID: Fixture.leftA,
            press: press,
            pressPoint: Fixture.point(on: Fixture.leftA, in: press),
            release: Fixture.point(x: 420),
            settled: settled
        )
        #expect(decision == .ignore(.crossedNothing))
    }

    @Test("A reorder on the right of the icon crosses nothing")
    func reorderRightCrossesNothing() {
        let settled = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.icon, Fixture.rightB, Fixture.rightA])
        let decision = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: press,
            pressPoint: Fixture.point(on: Fixture.rightA, in: press),
            release: Fixture.point(x: 560),
            settled: settled
        )
        #expect(decision == .ignore(.crossedNothing))
    }

    @Test("An Escape that restores the order crosses nothing")
    func escapeRestoresTheOrder() {
        let decision = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: press,
            pressPoint: Fixture.point(on: Fixture.rightA, in: press),
            release: Fixture.point(x: 570),
            settled: press
        )
        #expect(decision == .ignore(.crossedNothing))
    }

    // MARK: On the icon

    /// The settled bar after `rightA` crossed to the left of the icon.
    private func crossedLeft(_ order: [UInt32]? = nil) -> MenuBarDrop.Bar {
        Fixture.bar(order ?? [Fixture.leftA, Fixture.leftB, Fixture.rightA, Fixture.icon, Fixture.rightB])
    }

    private func decideRelease(x: CGFloat, settled: MenuBarDrop.Bar?) -> CommandDragSection.Decision {
        CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: press,
            pressPoint: Fixture.point(on: Fixture.rightA, in: press),
            release: Fixture.point(x: x),
            settled: settled
        )
    }

    @Test("A release inside the icon's frame sets nothing, even with a crossing")
    func releaseOnTheIcon() {
        #expect(decideRelease(x: Fixture.frame(of: Fixture.icon, in: press).midX, settled: crossedLeft()) == .ignore(.onIcon))
    }

    @Test("A release in the 6 point margin around the icon sets nothing")
    func releaseInTheIconMargin() {
        let icon = Fixture.frame(of: Fixture.icon, in: press)
        #expect(decideRelease(x: icon.minX - 4, settled: crossedLeft()) == .ignore(.onIcon))
        #expect(decideRelease(x: icon.maxX + 4, settled: crossedLeft()) == .ignore(.onIcon))
    }

    @Test("A release on the icon where it slides to sets nothing")
    func releaseOnTheShiftedIcon() {
        let icon = Fixture.frame(of: Fixture.icon, in: press)
        let dragged = Fixture.frame(of: Fixture.rightA, in: press)
        // The dragged item is right of the icon, so the icon slides right by its width and a gap.
        // A point near the shifted icon's right edge, so the pointer has moved from the press.
        let shifted = icon.midX + dragged.width + MenuBarDrop.gapEstimate + 10
        #expect(decideRelease(x: shifted, settled: crossedLeft()) == .ignore(.onIcon))
    }

    @Test("A release on the icon where the settled bar has it sets nothing")
    func releaseOnTheSettledIcon() {
        let settled = crossedLeft([Fixture.leftA, Fixture.leftB, Fixture.rightA, Fixture.extraApp, Fixture.icon, Fixture.rightB])
        let settledIcon = Fixture.frame(of: Fixture.icon, in: settled)
        #expect(decideRelease(x: settledIcon.midX, settled: settled) == .ignore(.onIcon))
    }

    @Test("A release just outside the icon's margin still decides")
    func releaseNextToTheMargin() {
        let icon = Fixture.frame(of: Fixture.icon, in: press)
        #expect(decideRelease(x: icon.minX - 12, settled: crossedLeft()) == .set(.hidden))
    }

    // MARK: Refusals

    @Test("A movement under 4 points is a click, even with a crossing in the settled bar")
    func clickSetsNothing() {
        let pressPoint = Fixture.point(on: Fixture.rightA, in: press)
        let decision = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: press,
            pressPoint: pressPoint,
            release: Fixture.point(x: pressPoint.x + 3),
            settled: crossedLeft()
        )
        #expect(decision == .ignore(.noMovement))
        let moved = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: press,
            pressPoint: pressPoint,
            release: Fixture.point(x: pressPoint.x + 4),
            settled: crossedLeft()
        )
        #expect(moved != .ignore(.noMovement))
    }

    @Test("A dragged item that is not in the settled bar is gone")
    func itemGone() {
        let without = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.icon, Fixture.rightB])
        #expect(decideRelease(x: 440, settled: without) == .ignore(.itemGone))
        #expect(decideRelease(x: 440, settled: nil) == .ignore(.itemGone))
        let folded = Fixture.bar(
            [Fixture.leftA, Fixture.leftB, Fixture.rightA, Fixture.icon, Fixture.rightB],
            widths: [Fixture.rightA: 3]
        )
        #expect(decideRelease(x: 440, settled: folded) == .ignore(.itemGone))
    }

    @Test("Without a usable icon there is no boundary")
    func noIcon() {
        let pressWithout = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.rightA, Fixture.rightB])
        let settled = Fixture.bar([Fixture.leftA, Fixture.rightA, Fixture.leftB, Fixture.rightB])
        let missing = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: pressWithout,
            pressPoint: Fixture.point(on: Fixture.rightA, in: pressWithout),
            release: Fixture.point(x: 440),
            settled: settled
        )
        #expect(missing == .ignore(.noIcon))

        let narrowIcon = Fixture.bar(
            [Fixture.leftA, Fixture.leftB, Fixture.icon, Fixture.rightA, Fixture.rightB],
            widths: [Fixture.icon: 4]
        )
        let narrow = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: narrowIcon,
            pressPoint: Fixture.point(on: Fixture.rightA, in: narrowIcon),
            release: Fixture.point(x: 440),
            settled: crossedLeft()
        )
        #expect(narrow == .ignore(.noIcon))

        let onlyInSettled = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.rightA, Fixture.rightB])
        #expect(decideRelease(x: 440, settled: onlyInSettled) == .ignore(.noIcon))
    }

    @Test("Only an app's item is decided: system, icon, divider and other holzBar items are not")
    func notAnAppItem() {
        let bar = Fixture.bar([
            Fixture.leftA, Fixture.hiddenDivider, Fixture.icon, Fixture.rightA, Fixture.widget, Fixture.controlCenter,
        ])
        for id in [Fixture.controlCenter, Fixture.icon, Fixture.hiddenDivider, Fixture.widget] {
            let decision = CommandDragSection.decide(
                draggedID: id,
                press: bar,
                pressPoint: Fixture.point(on: id, in: bar),
                release: Fixture.point(x: 300),
                settled: bar
            )
            #expect(decision == .ignore(.notAnAppItem))
        }
    }

    // MARK: Which item decides

    @Test("Two apps swapped across the icon: only the dragged one decides")
    func swappedAcrossTheIcon() {
        let before = Fixture.bar([Fixture.leftA, Fixture.icon, Fixture.rightA])
        let after = Fixture.bar([Fixture.rightA, Fixture.icon, Fixture.leftA])
        let right = CommandDragSection.decide(
            draggedID: Fixture.rightA,
            press: before,
            pressPoint: Fixture.point(on: Fixture.rightA, in: before),
            release: Fixture.point(x: 410),
            settled: after
        )
        #expect(right == .set(.hidden))
        let left = CommandDragSection.decide(
            draggedID: Fixture.leftA,
            press: before,
            pressPoint: Fixture.point(on: Fixture.leftA, in: before),
            release: Fixture.point(x: 540),
            settled: after
        )
        #expect(left == .set(.visible))
    }

    @Test("An icon that slid aside by the dragged item's width still gives the right sides")
    func iconSlidAside() {
        let settled = crossedLeft()
        let pressIcon = Fixture.frame(of: Fixture.icon, in: press)
        let settledIcon = Fixture.frame(of: Fixture.icon, in: settled)
        #expect(settledIcon.minX > pressIcon.minX)
        #expect(CommandDragSection.side(of: Fixture.rightA, in: press) == .right)
        #expect(CommandDragSection.side(of: Fixture.rightA, in: settled) == .left)
        #expect(CommandDragSection.side(of: Fixture.rightB, in: settled) == .right)
    }

    @Test("Items 4 points wide or narrower never count and never anchor")
    func narrowItemsNeverCount() {
        let narrowApp = Fixture.bar(
            [Fixture.leftA, Fixture.icon, Fixture.rightA],
            widths: [Fixture.leftA: 4]
        )
        #expect(CommandDragSection.side(of: Fixture.leftA, in: narrowApp) == nil)
        #expect(CommandDragSection.side(of: Fixture.rightA, in: narrowApp) == .right)
        let narrowIcon = Fixture.bar(
            [Fixture.leftA, Fixture.icon, Fixture.rightA],
            widths: [Fixture.icon: 4]
        )
        #expect(CommandDragSection.side(of: Fixture.leftA, in: narrowIcon) == nil)
        let divider = Fixture.bar(
            [Fixture.leftA, Fixture.hiddenDivider, Fixture.rightA],
            widths: [Fixture.hiddenDivider: 3]
        )
        #expect(CommandDragSection.side(of: Fixture.leftA, in: divider) == nil)
        #expect(CommandDragSection.side(of: 999, in: press) == nil)
    }

    @Test("The first and the last item of a long bar decide like any other")
    func firstAndLastItem() {
        let apps: [UInt32] = Array(40...47)
        let before = Fixture.bar(Array(apps[0..<4]) + [Fixture.icon] + Array(apps[4...]))
        #expect(CommandDragSection.side(of: apps[0], in: before) == .left)
        #expect(CommandDragSection.side(of: apps[7], in: before) == .right)
        // The first item goes to the far right, the last to the far left.
        let first = Fixture.bar(Array(apps[1..<4]) + [Fixture.icon] + Array(apps[4...]) + [apps[0]])
        let firstDecision = CommandDragSection.decide(
            draggedID: apps[0],
            press: before,
            pressPoint: Fixture.point(on: apps[0], in: before),
            release: Fixture.point(x: 900),
            settled: first
        )
        #expect(firstDecision == .set(.visible))
        let last = Fixture.bar([apps[7]] + Array(apps[0..<4]) + [Fixture.icon] + Array(apps[4..<7]))
        let lastDecision = CommandDragSection.decide(
            draggedID: apps[7],
            press: before,
            pressPoint: Fixture.point(on: apps[7], in: before),
            release: Fixture.point(x: 380),
            settled: last
        )
        #expect(lastDecision == .set(.hidden))
    }

    // MARK: Outcome

    @Test("Hidden on a visible app applies")
    func hiddenOnVisible() {
        #expect(CommandDragSection.outcome(for: .set(.hidden), current: .visible, lock: nil) == .apply(from: .visible, to: .hidden))
    }

    @Test("Visible on a hidden or always-hidden app applies")
    func visibleOnHidden() {
        #expect(CommandDragSection.outcome(for: .set(.visible), current: .hidden, lock: nil) == .apply(from: .hidden, to: .visible))
        #expect(CommandDragSection.outcome(for: .set(.visible), current: .alwaysHidden, lock: nil) == .apply(from: .alwaysHidden, to: .visible))
    }

    @Test("A section the app already has is nothing to do")
    func sameSectionIsNothing() {
        #expect(CommandDragSection.outcome(for: .set(.hidden), current: .hidden, lock: nil) == .nothing)
        #expect(CommandDragSection.outcome(for: .set(.visible), current: .visible, lock: nil) == .nothing)
    }

    @Test("An always-hidden app is never moved to hidden")
    func alwaysHiddenStays() {
        #expect(CommandDragSection.outcome(for: .set(.hidden), current: .alwaysHidden, lock: nil) == .nothing)
    }

    @Test("A lock wins over every set")
    func lockWins() {
        for lock in [CommandDragSection.Lock.rule, .pinned, .system] {
            #expect(CommandDragSection.outcome(for: .set(.hidden), current: .visible, lock: lock) == .keep(lock))
            #expect(CommandDragSection.outcome(for: .set(.visible), current: .visible, lock: lock) == .keep(lock))
        }
    }

    @Test("An ignored decision is nothing, locked or not")
    func ignoreIsNothing() {
        #expect(CommandDragSection.outcome(for: .ignore(.noMovement), current: .visible, lock: nil) == .nothing)
        #expect(CommandDragSection.outcome(for: .ignore(.crossedNothing), current: .hidden, lock: .rule) == .nothing)
    }

    // MARK: Fixed items

    private let fixed = Fixture.bar([Fixture.leftA, Fixture.leftB, Fixture.icon, Fixture.rightA, Fixture.controlCenter])

    private func decideFixed(dragged: UInt32, release: CGFloat, in bar: MenuBarDrop.Bar? = nil) -> CommandDragSection.Decision {
        let bar = bar ?? fixed
        return CommandDragSection.decideFixed(
            draggedFrame: Fixture.frame(of: dragged, in: bar),
            press: bar,
            pressPoint: Fixture.point(on: dragged, in: bar),
            release: Fixture.point(x: release)
        )
    }

    @Test("A fixed item's pointer crossing right to left is hidden, left to right visible")
    func fixedCrossings() {
        #expect(decideFixed(dragged: Fixture.rightA, release: 420) == .set(.hidden))
        #expect(decideFixed(dragged: Fixture.leftA, release: 600) == .set(.visible))
    }

    @Test("A fixed item released on its own side crosses nothing")
    func fixedSameSide() {
        #expect(decideFixed(dragged: Fixture.rightA, release: 700) == .ignore(.crossedNothing))
        #expect(decideFixed(dragged: Fixture.leftA, release: 410) == .ignore(.crossedNothing))
    }

    @Test("A fixed item released in the icon's margin is left to macOS")
    func fixedOnTheIcon() {
        let icon = Fixture.frame(of: Fixture.icon, in: fixed)
        #expect(decideFixed(dragged: Fixture.rightA, release: icon.midX) == .ignore(.onIcon))
        #expect(decideFixed(dragged: Fixture.rightA, release: icon.minX - 5) == .ignore(.onIcon))
        #expect(decideFixed(dragged: Fixture.rightA, release: icon.maxX + 5) == .ignore(.onIcon))
    }

    @Test("A fixed item moved under 4 points is a click")
    func fixedClick() {
        let pressPoint = Fixture.point(on: Fixture.rightA, in: fixed)
        #expect(decideFixed(dragged: Fixture.rightA, release: pressPoint.x - 3) == .ignore(.noMovement))
    }

    @Test("A fixed item without a usable icon has no boundary")
    func fixedNoIcon() {
        let bar = Fixture.bar([Fixture.leftA, Fixture.rightA, Fixture.controlCenter])
        #expect(decideFixed(dragged: Fixture.rightA, release: 420, in: bar) == .ignore(.noIcon))
        let narrow = Fixture.bar([Fixture.leftA, Fixture.icon, Fixture.rightA], widths: [Fixture.icon: 4])
        #expect(decideFixed(dragged: Fixture.rightA, release: 420, in: narrow) == .ignore(.noIcon))
    }
}
