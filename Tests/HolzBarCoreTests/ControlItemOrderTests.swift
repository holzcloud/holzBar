#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import HolzBarCore

@Suite("ControlItemOrder")
struct ControlItemOrderTests {
    /// A bar item of the usual size at the given left edge.
    private func item(_ minX: CGFloat, width: CGFloat = 22) -> CGRect {
        CGRect(x: minX, y: 0, width: width, height: 24)
    }

    private let hidden = CGRect(x: 1000, y: 0, width: 22, height: 24)

    @Test("The right order needs nothing")
    func rightOrder() {
        #expect(ControlItemOrder.corrections(icon: item(1100), hidden: hidden, alwaysHidden: item(800)).isEmpty)
    }

    @Test("An icon left of the hidden divider goes back right of it")
    func iconLeftOfHidden() {
        #expect(ControlItemOrder.corrections(icon: item(900), hidden: hidden, alwaysHidden: item(800)) == [.iconRightOfHidden])
    }

    @Test("An icon touching the divider from the left counts as left of it")
    func iconTouching() {
        #expect(ControlItemOrder.corrections(icon: item(978), hidden: hidden, alwaysHidden: nil) == [.iconRightOfHidden])
    }

    @Test("An always-hidden divider right of the hidden one goes back left of it")
    func alwaysHiddenRightOfHidden() {
        #expect(ControlItemOrder.corrections(icon: item(1100), hidden: hidden, alwaysHidden: item(1050)) == [.alwaysHiddenLeftOfHidden])
    }

    @Test("Both wrong: the icon first, then the always-hidden divider")
    func bothWrong() {
        #expect(
            ControlItemOrder.corrections(icon: item(900), hidden: hidden, alwaysHidden: item(1050))
                == [.iconRightOfHidden, .alwaysHiddenLeftOfHidden]
        )
    }

    @Test("Without the icon only the divider rule applies")
    func noIcon() {
        #expect(ControlItemOrder.corrections(icon: nil, hidden: hidden, alwaysHidden: item(1050)) == [.alwaysHiddenLeftOfHidden])
        #expect(ControlItemOrder.corrections(icon: nil, hidden: hidden, alwaysHidden: item(800)).isEmpty)
    }

    @Test("Without the always-hidden divider only the icon rule applies")
    func noAlwaysHidden() {
        #expect(ControlItemOrder.corrections(icon: item(900), hidden: hidden, alwaysHidden: nil) == [.iconRightOfHidden])
        #expect(ControlItemOrder.corrections(icon: item(1100), hidden: hidden, alwaysHidden: nil).isEmpty)
    }

    @Test("A collapsed divider 10,000 pt wide with the icon pushed far left")
    func collapsedDivider() {
        let collapsed = CGRect(x: -8500, y: 0, width: 10_000, height: 24)
        #expect(ControlItemOrder.corrections(icon: item(-8600), hidden: collapsed, alwaysHidden: nil) == [.iconRightOfHidden])
        #expect(ControlItemOrder.corrections(icon: item(1520), hidden: collapsed, alwaysHidden: nil).isEmpty)
    }
}
