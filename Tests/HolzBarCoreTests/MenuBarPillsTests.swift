import Testing
@testable import HolzBarCore

@Suite("MenuBarPills")
struct MenuBarPillsTests {
    private let itemsArea: ClosedRange<Double> = 1000...1500
    private let minimumWidth: Double = 24

    private func spans(
        itemsArea: ClosedRange<Double>? = nil,
        hidden: MenuBarPills.Divider?,
        alwaysHidden: MenuBarPills.Divider? = nil
    ) -> [ClosedRange<Double>]? {
        MenuBarPills.sectionSpans(
            itemsArea: itemsArea ?? self.itemsArea,
            hiddenDivider: hidden,
            alwaysHiddenDivider: alwaysHidden,
            minimumWidth: minimumWidth
        )
    }

    @Test("Without a hidden divider on the display there is no answer, and the caller draws Paired")
    func noHiddenDividerGivesNil() {
        #expect(spans(hidden: nil) == nil)
        #expect(spans(hidden: nil, alwaysHidden: .init(span: 1080...1100, showsSection: true)) == nil)
    }

    @Test("A collapsed hidden section leaves the items area as one shape")
    func collapsedHiddenSectionIsOneShape() {
        let hidden = MenuBarPills.Divider(span: -8880...1120, showsSection: false)
        #expect(spans(hidden: hidden) == [1000...1500])
    }

    @Test("An items area narrower than the minimum width gives no answer")
    func narrowItemsAreaGivesNil() {
        let hidden = MenuBarPills.Divider(span: -8880...1120, showsSection: false)
        #expect(spans(itemsArea: 1000...1020, hidden: hidden) == nil)
    }

    @Test("A shown hidden section splits the items area at the middle of its divider")
    func shownHiddenSectionSplitsTheItemsArea() {
        let hidden = MenuBarPills.Divider(span: 1200...1220, showsSection: true)
        #expect(spans(hidden: hidden) == [1000...1208, 1212...1500])
    }

    @Test("Shown hidden and always-hidden sections give three shapes")
    func bothSectionsShownGiveThreeShapes() {
        let hidden = MenuBarPills.Divider(span: 1200...1220, showsSection: true)
        let alwaysHidden = MenuBarPills.Divider(span: 1080...1100, showsSection: true)
        #expect(spans(hidden: hidden, alwaysHidden: alwaysHidden) == [1000...1088, 1092...1208, 1212...1500])
    }

    @Test("A collapsed always-hidden section adds no boundary")
    func collapsedAlwaysHiddenSectionAddsNoBoundary() {
        let hidden = MenuBarPills.Divider(span: 1200...1220, showsSection: true)
        let alwaysHidden = MenuBarPills.Divider(span: -8920...1100, showsSection: false)
        #expect(spans(hidden: hidden, alwaysHidden: alwaysHidden) == [1000...1208, 1212...1500])
    }

    @Test("An always-hidden section that shows while the hidden one does not adds no boundary")
    func alwaysHiddenAloneAddsNoBoundary() {
        let hidden = MenuBarPills.Divider(span: -8880...1120, showsSection: false)
        let alwaysHidden = MenuBarPills.Divider(span: 1080...1100, showsSection: true)
        #expect(spans(hidden: hidden, alwaysHidden: alwaysHidden) == [1000...1500])
    }

    @Test("A span narrower than the minimum width is left out")
    func narrowSpanIsLeftOut() {
        let hidden = MenuBarPills.Divider(span: 1010...1030, showsSection: true)
        #expect(spans(hidden: hidden) == [1022...1500])
    }

    @Test("A divider left of the items area is clamped and leaves the whole items area")
    func dividerOutsideTheItemsAreaIsClamped() {
        let hidden = MenuBarPills.Divider(span: 960...980, showsSection: true)
        #expect(spans(hidden: hidden) == [1000...1500])
    }

    @Test("The shapes are ordered left to right and never overlap, with at least the gap between them")
    func shapesAreOrderedAndNeverOverlap() throws {
        let hidden = MenuBarPills.Divider(span: 1200...1220, showsSection: true)
        let alwaysHidden = MenuBarPills.Divider(span: 1080...1100, showsSection: true)
        let results = [
            try #require(spans(hidden: hidden)),
            try #require(spans(hidden: hidden, alwaysHidden: alwaysHidden)),
        ]
        for result in results {
            for (left, right) in zip(result, result.dropFirst()) {
                #expect(right.lowerBound - left.upperBound >= MenuBarPills.gap)
            }
        }
    }

    @Test("The gap between two shapes is four points")
    func gapIsFourPoints() {
        #expect(MenuBarPills.gap == 4)
    }

    private func appleLogo(
        _ appleMenu: ClosedRange<Double>,
        height: Double = 24,
        within bounds: ClosedRange<Double> = 0...1500
    ) -> ClosedRange<Double>? {
        MenuBarPills.appleLogoSpan(appleMenu: appleMenu, height: height, within: bounds)
    }

    @Test("An Apple menu wider than the bar is high keeps its own span")
    func wideAppleMenuKeepsItsSpan() {
        #expect(appleLogo(10...44) == 10...44)
    }

    @Test("An Apple menu narrower than the bar is high becomes a circle centred on it")
    func narrowAppleMenuBecomesACircle() {
        #expect(appleLogo(10...26) == 6...30)
    }

    @Test("A capsule that would start left of the bounds is shifted right")
    func capsuleLeftOfTheBoundsIsShifted() {
        #expect(appleLogo(0...16, within: 8...1000) == 8...32)
    }

    @Test("An Apple menu without a width gives no capsule")
    func emptyAppleMenuGivesNil() {
        #expect(appleLogo(20...20) == nil)
    }

    @Test("A capsule that does not fit into the bounds gives no capsule")
    func capsuleBeyondTheBoundsGivesNil() {
        #expect(appleLogo(10...44, within: 0...20) == nil)
    }

    @Test("The shapes start one gap right of the capsule")
    func shapesStartOneGapRightOfTheCapsule() {
        #expect(MenuBarPills.leadingStart(after: 10...44) == 48)
    }
}
