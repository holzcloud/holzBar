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
}
