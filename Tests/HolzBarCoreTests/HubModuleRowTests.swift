import Foundation
import Testing
@testable import HolzBarCore

@Suite("HubModuleRow")
struct HubModuleRowTests {
    private let base = DesignTokens.Island.baseWidth
    private let maximum = DesignTokens.Island.maximumWidth

    @Test("The row is the buttons and the gaps between them, and nothing without buttons")
    func rowWidth() {
        #expect(HubModuleRow.rowWidth(count: 9, buttonSize: 30) == 318)
        #expect(HubModuleRow.rowWidth(count: 0, buttonSize: 30) == 0)
        #expect(HubModuleRow.rowWidth(count: -3, buttonSize: 30) == 0)
        #expect(HubModuleRow.rowWidth(count: 1, buttonSize: 26) == 26)
    }

    @Test("The room for buttons is the hub's width less both sides' radius and padding")
    func room() {
        let inset = 2 * (DesignTokens.Island.openTopRadius + DesignTokens.Island.sidePadding)
        #expect(inset == 60)
        // 16 buttons at 30 points need exactly 630 - 60 points: the hub is 630 wide.
        #expect(HubModuleRow.fit(count: 16, baseWidth: base, maxWidth: maximum).hubWidth == 630)
    }

    @Test("Today's nine buttons fit at 30 points in the base width")
    func nineButtons() {
        let fit = HubModuleRow.fit(count: 9, baseWidth: base, maxWidth: maximum)
        #expect(fit == HubModuleRow.Fit(buttonSize: 30, hubWidth: 560, scrolls: false))
    }

    @Test("The same holds for the largest hub of the 14 inch, the 16 inch and the Air display")
    func displays() {
        // The largest island on a display is min(640, width - 24).
        for width in [1512.0, 1728.0, 1470.0] {
            let limit = min(maximum, width - 2 * 12)
            let fit = HubModuleRow.fit(count: 9, baseWidth: base, maxWidth: limit)
            #expect(fit.buttonSize == 30)
            #expect(fit.hubWidth == 560)
            #expect(!fit.scrolls)
        }
    }

    @Test("The hub widens before the buttons shrink, then they step down, then the row scrolls")
    func widenThenShrinkThenScroll() {
        let sixteen = HubModuleRow.fit(count: 16, baseWidth: base, maxWidth: maximum)
        #expect(sixteen == HubModuleRow.Fit(buttonSize: 30, hubWidth: 630, scrolls: false))
        let seventeen = HubModuleRow.fit(count: 17, baseWidth: base, maxWidth: maximum)
        #expect(seventeen == HubModuleRow.Fit(buttonSize: 26, hubWidth: 640, scrolls: false))
        let eighteen = HubModuleRow.fit(count: 18, baseWidth: base, maxWidth: maximum)
        #expect(eighteen == HubModuleRow.Fit(buttonSize: 26, hubWidth: 640, scrolls: false))
        let nineteen = HubModuleRow.fit(count: 19, baseWidth: base, maxWidth: maximum)
        #expect(nineteen == HubModuleRow.Fit(buttonSize: 26, hubWidth: 640, scrolls: true))
    }

    @Test("A narrow display shrinks the base width and the row still fits at 30 points")
    func narrowDisplay() {
        let fit = HubModuleRow.fit(count: 9, baseWidth: base, maxWidth: 400)
        #expect(fit == HubModuleRow.Fit(buttonSize: 30, hubWidth: 400, scrolls: false))
    }

    @Test("No buttons give 30 points at the base width, and a maximum that is no number is the base")
    func edges() {
        #expect(HubModuleRow.fit(count: 0, baseWidth: base, maxWidth: maximum)
            == HubModuleRow.Fit(buttonSize: 30, hubWidth: 560, scrolls: false))
        #expect(HubModuleRow.fit(count: -4, baseWidth: base, maxWidth: maximum)
            == HubModuleRow.Fit(buttonSize: 30, hubWidth: 560, scrolls: false))
        // With the maximum counted as the base width, 17 buttons cannot widen: they scroll at 26.
        let notANumber = HubModuleRow.fit(count: 17, baseWidth: base, maxWidth: .nan)
        #expect(notANumber == HubModuleRow.Fit(buttonSize: 26, hubWidth: 560, scrolls: true))
        let nine = HubModuleRow.fit(count: 9, baseWidth: base, maxWidth: .nan)
        #expect(nine == HubModuleRow.Fit(buttonSize: 30, hubWidth: 560, scrolls: false))
    }
}
