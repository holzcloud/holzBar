#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import HolzBarCore

@Suite("MenuBarAnchor")
struct MenuBarAnchorTests {
    /// The built-in display, in AppKit coordinates (origin at the bottom left).
    private let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// An external display right of it, whose top edge is lower.
    private let external = CGRect(x: 1512, y: 0, width: 1920, height: 900)

    /// An item frame in the bar of the given display, at the given left edge.
    private func inBar(of screen: CGRect, minX: CGFloat, width: CGFloat = 22) -> CGRect {
        CGRect(x: minX, y: screen.maxY - 24, width: width, height: 24)
    }

    /// An item frame pushed above the given display, as in a fullscreen Space.
    private func aboveBar(of screen: CGRect, minX: CGFloat) -> CGRect {
        CGRect(x: minX, y: screen.maxY, width: 22, height: 24)
    }

    @Test("The icon in the bar of the display decides: shown")
    func iconShown() {
        let result = MenuBarAnchor.evaluate(
            iconFrame: inBar(of: builtIn, minX: 1200),
            dividerFrame: inBar(of: builtIn, minX: 1100),
            screenFrame: builtIn,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(result.anchor == .icon)
        #expect(result.barIsShown)
    }

    @Test("The icon above the display decides: not shown, whatever the divider says")
    func iconAbove() {
        let result = MenuBarAnchor.evaluate(
            iconFrame: aboveBar(of: builtIn, minX: 1200),
            dividerFrame: inBar(of: builtIn, minX: 1100),
            screenFrame: builtIn,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(result.anchor == .icon)
        #expect(!result.barIsShown)
    }

    @Test("Without the icon the hidden divider decides, with the same rule")
    func noIcon() {
        let shown = MenuBarAnchor.evaluate(
            iconFrame: nil,
            dividerFrame: inBar(of: builtIn, minX: 1100),
            screenFrame: builtIn,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(shown.anchor == .divider)
        #expect(shown.barIsShown)
        let hidden = MenuBarAnchor.evaluate(
            iconFrame: nil,
            dividerFrame: aboveBar(of: builtIn, minX: 1100),
            screenFrame: builtIn,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(hidden.anchor == .divider)
        #expect(!hidden.barIsShown)
    }

    @Test("An icon on another display leaves the decision to the divider")
    func iconElsewhere() {
        let result = MenuBarAnchor.evaluate(
            iconFrame: inBar(of: builtIn, minX: 1200),
            dividerFrame: inBar(of: external, minX: 3000),
            screenFrame: external,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(result.anchor == .divider)
        #expect(result.barIsShown)
    }

    @Test("A collapsed divider 10,000 pt wide is on the display of its right end")
    func collapsedDivider() {
        let collapsed = CGRect(x: 1100 - 10_000, y: builtIn.maxY - 24, width: 10_000, height: 24)
        let result = MenuBarAnchor.evaluate(
            iconFrame: nil,
            dividerFrame: collapsed,
            screenFrame: builtIn,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(result.anchor == .divider)
        #expect(result.barIsShown)
    }

    @Test("A display with neither: shown unless the system hides the bar or a fullscreen Space is active")
    func neither() {
        let icon = inBar(of: builtIn, minX: 1200)
        let divider = inBar(of: builtIn, minX: 1100)
        let plain = MenuBarAnchor.evaluate(
            iconFrame: icon,
            dividerFrame: divider,
            screenFrame: external,
            systemHidesBar: false,
            isFullscreen: false
        )
        #expect(plain.anchor == .none)
        #expect(plain.barIsShown)
        let systemHides = MenuBarAnchor.evaluate(
            iconFrame: icon,
            dividerFrame: divider,
            screenFrame: external,
            systemHidesBar: true,
            isFullscreen: false
        )
        #expect(systemHides.anchor == .none)
        #expect(!systemHides.barIsShown)
        let fullscreen = MenuBarAnchor.evaluate(
            iconFrame: nil,
            dividerFrame: nil,
            screenFrame: external,
            systemHidesBar: false,
            isFullscreen: true
        )
        #expect(fullscreen.anchor == .none)
        #expect(!fullscreen.barIsShown)
    }

    @Test("With an anchor the system state is never asked")
    func lazyFallback() {
        var asked = 0
        let result = MenuBarAnchor.evaluate(
            iconFrame: inBar(of: builtIn, minX: 1200),
            dividerFrame: nil,
            screenFrame: builtIn,
            systemHidesBar: { asked += 1; return true }(),
            isFullscreen: { asked += 1; return true }()
        )
        #expect(result.barIsShown)
        #expect(asked == 0)
    }

    @Test("The anchor words")
    func words() {
        #expect(MenuBarAnchor.Kind.icon.rawValue == "icon")
        #expect(MenuBarAnchor.Kind.divider.rawValue == "divider")
        #expect(MenuBarAnchor.Kind.none.rawValue == "none")
    }
}
