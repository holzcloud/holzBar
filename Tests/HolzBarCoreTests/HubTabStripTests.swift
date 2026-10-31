import Testing
@testable import HolzBarCore

@Suite("HubTabStrip")
struct HubTabStripTests {
    private let seven = ["a", "b", "c", "d", "e", "f"]

    @Test("With no module tab the strip is the Overview alone")
    func overviewAlone() {
        let layout = HubTabStrip.layout(moduleTabs: [], selected: "a")
        #expect(layout.visible == ["overview"])
        #expect(layout.overflow.isEmpty)
        #expect(layout.selected == "overview")
    }

    @Test("Five or fewer tabs are all visible; seven put two in the menu")
    func overflow() {
        let few = HubTabStrip.layout(moduleTabs: ["a", "b", "c", "d"], selected: "overview")
        #expect(few.visible == ["overview", "a", "b", "c", "d"])
        #expect(few.overflow.isEmpty)
        let many = HubTabStrip.layout(moduleTabs: seven, selected: "overview")
        #expect(many.visible == ["overview", "a", "b", "c", "d"])
        #expect(many.overflow == ["e", "f"])
    }

    @Test("A selection in the menu takes the last visible place, and the displaced tab joins the menu")
    func selectionInOverflow() {
        let layout = HubTabStrip.layout(moduleTabs: seven, selected: "f")
        #expect(layout.visible == ["overview", "a", "b", "c", "f"])
        #expect(layout.overflow == ["d", "e"])
        #expect(layout.selected == "f")
        let middle = HubTabStrip.layout(moduleTabs: seven, selected: "e")
        #expect(middle.visible == ["overview", "a", "b", "c", "e"])
        #expect(middle.overflow == ["d", "f"])
        // A selection that is already visible changes nothing.
        let visible = HubTabStrip.layout(moduleTabs: seven, selected: "b")
        #expect(visible.visible == ["overview", "a", "b", "c", "d"])
        #expect(visible.overflow == ["e", "f"])
    }

    @Test("An unknown selection becomes the Overview, and duplicates and a stray overview are dropped")
    func cleaning() {
        let layout = HubTabStrip.layout(moduleTabs: ["a", "overview", "b", "a"], selected: "zzz")
        #expect(layout.visible == ["overview", "a", "b"])
        #expect(layout.selected == "overview")
    }

    @Test("A maximum below one counts as one")
    func minimumOfOne() {
        let layout = HubTabStrip.layout(moduleTabs: ["a", "b"], selected: "b", maximumVisible: 0)
        #expect(layout.visible == ["b"])
        #expect(layout.overflow == ["overview", "a"])
        let negative = HubTabStrip.layout(moduleTabs: ["a"], selected: "overview", maximumVisible: -4)
        #expect(negative.visible == ["overview"])
        #expect(negative.overflow == ["a"])
    }

    @Test("Stepping moves through the whole list and wraps at both ends")
    func stepping() {
        let tabs = ["overview", "a", "b"]
        #expect(HubTabStrip.step(from: "overview", by: 1, in: tabs) == "a")
        #expect(HubTabStrip.step(from: "b", by: 1, in: tabs) == "overview")
        #expect(HubTabStrip.step(from: "overview", by: -1, in: tabs) == "b")
        #expect(HubTabStrip.step(from: "a", by: -1, in: tabs) == "overview")
        #expect(HubTabStrip.step(from: "overview", by: 7, in: tabs) == "a")
        // An unknown start steps from the Overview.
        #expect(HubTabStrip.step(from: "gone", by: 1, in: tabs) == "a")
        #expect(HubTabStrip.step(from: "gone", by: 1, in: []) == "overview")
    }

    @Test("The strip never reaches past its wing: the More button takes a slot where tabs overflow")
    func capacityInAWing() {
        // 30-point tabs with a gap of 2: six slots fit in 190 points.
        #expect(HubTabStrip.visibleCapacity(tabCount: 4, wingWidth: 191, tabWidth: 30, gap: 2) == 5)
        #expect(HubTabStrip.visibleCapacity(tabCount: 7, wingWidth: 191, tabWidth: 30, gap: 2) == 5)
        #expect(HubTabStrip.visibleCapacity(tabCount: 7, wingWidth: 100, tabWidth: 30, gap: 2) == 2)
        #expect(HubTabStrip.visibleCapacity(tabCount: 2, wingWidth: 100, tabWidth: 30, gap: 2) == 3)
        #expect(HubTabStrip.visibleCapacity(tabCount: 7, wingWidth: 20, tabWidth: 30, gap: 2) == 1)
        #expect(HubTabStrip.visibleCapacity(tabCount: 7, wingWidth: .nan, tabWidth: 30, gap: 2) == 1)
        #expect(HubTabStrip.visibleCapacity(tabCount: 7, wingWidth: 500, tabWidth: 30, gap: 2) == 5)
    }

    @Test("The remembered tab is used when it is available, else the Overview")
    func remembered() {
        #expect(HubTabStrip.remembered(lastTab: "a", available: ["a", "b"]) == "a")
        #expect(HubTabStrip.remembered(lastTab: "gone", available: ["a", "b"]) == "overview")
        #expect(HubTabStrip.remembered(lastTab: nil, available: ["a"]) == "overview")
        #expect(HubTabStrip.remembered(lastTab: "overview", available: []) == "overview")
    }

    // MARK: The row across both wings

    private let eight = ["a", "b", "c", "d", "e", "f", "g", "h"]
    private let allNine = ["overview", "a", "b", "c", "d", "e", "f", "g", "h"]

    @Test("Nine tabs across two wings of 194 points: six on the left, three on the right, no overflow")
    func nineTabsAcrossBothWings() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 194, rightReservedWidth: 90
        )
        #expect(row.left == ["overview", "a", "b", "c", "d", "e"])
        #expect(row.right == ["f", "g", "h"])
        #expect(row.overflow.isEmpty)
        #expect(row.tabWidth == 30)
        #expect(row.selected == "overview")
    }

    @Test("The left group is the first tabs in catalog order, the right group the rest, each tab once")
    func eachTabOnce() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "c",
            leftWingWidth: 100, rightWingWidth: 160, rightReservedWidth: 60
        )
        #expect(Set(row.left + row.right + row.overflow) == Set(allNine))
        #expect((row.left + row.right + row.overflow).count == allNine.count)
        #expect(row.left == ["overview", "a", "b"])
        #expect(row.right == ["c", "d", "e"])
        #expect(row.overflow == ["f", "g", "h"])
    }

    @Test("Six tabs fit in a left wing of 194 points and the right group stays empty")
    func leftWingOnly() {
        let row = HubTabStrip.row(
            moduleTabs: ["a", "b", "c", "d", "e"], selected: "overview",
            leftWingWidth: 194, rightWingWidth: 194, rightReservedWidth: 90
        )
        #expect(row.left == ["overview", "a", "b", "c", "d", "e"])
        #expect(row.right.isEmpty)
        #expect(row.overflow.isEmpty)
    }

    @Test("Without a right wing only the left wing is used and the tabs that do not fit overflow")
    func noRightWing() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 0, rightReservedWidth: 90
        )
        #expect(row.left == ["overview", "a", "b", "c", "d", "e"])
        #expect(row.right.isEmpty)
        #expect(row.overflow == ["f", "g", "h"])
    }

    @Test("The selected tab never ends in the overflow: it takes the last visible place")
    func selectionStaysVisible() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "h",
            leftWingWidth: 194, rightWingWidth: 0, rightReservedWidth: 90
        )
        #expect(row.left == ["overview", "a", "b", "c", "d", "h"])
        #expect(row.overflow == ["e", "f", "g"])
        #expect(row.selected == "h")
        let wide = HubTabStrip.row(
            moduleTabs: eight, selected: "g",
            leftWingWidth: 194, rightWingWidth: 194, rightReservedWidth: 90
        )
        #expect(wide.right == ["f", "g", "h"])
        #expect(wide.overflow.isEmpty)
    }

    @Test("An unknown selection becomes the Overview; duplicates and a stray overview are dropped")
    func rowCleaning() {
        let row = HubTabStrip.row(
            moduleTabs: ["a", "overview", "b", "a"], selected: "zzz",
            leftWingWidth: 194, rightWingWidth: 0, rightReservedWidth: 0
        )
        #expect(row.left == ["overview", "a", "b"])
        #expect(row.selected == "overview")
    }

    @Test("Widths that are not numbers or are negative count as no room")
    func unusableWidths() {
        let none = HubTabStrip.row(
            moduleTabs: ["a"], selected: "overview",
            leftWingWidth: .nan, rightWingWidth: -50, rightReservedWidth: .infinity
        )
        #expect(none.left.isEmpty && none.right.isEmpty)
        #expect(none.overflow == ["overview", "a"])
        let crowded = HubTabStrip.row(
            moduleTabs: ["a"], selected: "overview",
            leftWingWidth: 0, rightWingWidth: 100, rightReservedWidth: 400
        )
        #expect(crowded.right.isEmpty)
    }

    @Test("The pills and the settings button reserve their estimated width; no pills reserve the button alone")
    func reservedWidth() {
        #expect(HubTabStrip.rightReservedWidth(pills: []) == 24)
        // "Muted": five characters at 7 points, and 8 points of padding on both sides.
        #expect(HubTabStrip.pillWidth(textLength: 5, hasSymbol: false) == 51)
        // A symbol adds 14 points and the 4 points between it and the text.
        #expect(HubTabStrip.pillWidth(textLength: 5, hasSymbol: true) == 69)
        #expect(HubTabStrip.pillWidth(textLength: -3, hasSymbol: false) == 16)
        // One pill, the button and 8 points between them.
        let one = HubTabStrip.rightReservedWidth(pills: [.init(textLength: 5, hasSymbol: false)])
        #expect(one == 51 + 24 + 8)
        let two = HubTabStrip.rightReservedWidth(pills: [
            .init(textLength: 5, hasSymbol: false), .init(textLength: 4, hasSymbol: true),
        ])
        #expect(two == 51 + 62 + 24 + 16)
    }
}
