import Testing
@testable import HolzBarCore

@Suite("HubTabStrip")
struct HubTabStripTests {
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
        #expect(row.moreWing == nil)
    }

    @Test("The left group is the first tabs in catalog order, the right group the rest, each tab once")
    func eachTabOnce() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "c",
            leftWingWidth: 100, rightWingWidth: 160, rightReservedWidth: 60
        )
        #expect(row.left == ["overview", "a", "b"])
        #expect(row.right == ["c", "d"])
        #expect(row.overflow == ["e", "f", "g", "h"])
        #expect(Set(row.left + row.right + row.overflow) == Set(allNine))
        #expect((row.left + row.right + row.overflow).count == allNine.count)
        // Nothing fits at any width: the smallest is used and the right group ends in More.
        #expect(row.tabWidth == 26)
        #expect(row.moreWing == .right)
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

    @Test("Without a right wing only the left wing is used and More takes its last place")
    func noRightWing() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 0, rightReservedWidth: 90
        )
        #expect(row.left == ["overview", "a", "b", "c", "d", "e"])
        #expect(row.right.isEmpty)
        #expect(row.overflow == ["f", "g", "h"])
        #expect(row.tabWidth == 26)
        #expect(row.moreWing == .left)
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
        #expect(row.moreWing == .left)
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

    @Test("A row that is a little too wide steps down to 28 points and shows no menu")
    func shrinksToTwentyEight() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 194, rightReservedWidth: 100
        )
        #expect(row.tabWidth == 28)
        #expect(row.overflow.isEmpty)
        #expect(row.moreWing == nil)
        #expect(row.left == ["overview", "a", "b", "c", "d", "e"])
        #expect(row.right == ["f", "g", "h"])
    }

    @Test("When 26 points are not enough either, one place of the right group is kept for More")
    func moreAtTheEndOfTheRightGroup() {
        let row = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 150, rightReservedWidth: 100
        )
        #expect(row.tabWidth == 26)
        #expect(row.moreWing == .right)
        #expect(row.right.isEmpty)
        #expect(row.left == ["overview", "a", "b", "c", "d", "e", "f"])
        #expect(row.overflow == ["g", "h"])
        // The selected tab is visible even though it was in the overflow.
        let chosen = HubTabStrip.row(
            moduleTabs: eight, selected: "h",
            leftWingWidth: 194, rightWingWidth: 150, rightReservedWidth: 100
        )
        #expect(chosen.left.last == "h")
        #expect(!chosen.overflow.contains("h"))
    }

    @Test("The widths tried are 30, 28 and 26 in that order, and the first that holds every tab wins")
    func stepsInOrder() {
        #expect(DesignTokens.Hub.tabWidthSteps == [30, 28, 26])
        // Nine tabs and eight gaps of 2 points need 286, 268 and 250 points at the three widths;
        // give the left wing the whole room and the right one nothing.
        for (width, left) in [(30.0, 286.0), (28.0, 268.0), (26.0, 250.0)] {
            let row = HubTabStrip.row(
                moduleTabs: eight, selected: "overview",
                leftWingWidth: left, rightWingWidth: 0, rightReservedWidth: 0
            )
            #expect(row.tabWidth == width)
            #expect(row.overflow.isEmpty)
        }
        // One point less than the 26-point row needs: More appears.
        let tight = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 249, rightWingWidth: 0, rightReservedWidth: 0
        )
        #expect(tight.tabWidth == 26)
        #expect(tight.moreWing == .left)
    }

    @Test("The Overview alone never overflows, whatever the widths")
    func overviewAlone() {
        for (left, right) in [(0.0, 0.0), (10.0, 0.0), (194.0, 194.0), (.nan, .nan)] {
            let row = HubTabStrip.row(
                moduleTabs: [], selected: "a",
                leftWingWidth: left, rightWingWidth: right, rightReservedWidth: 90
            )
            #expect(row.left + row.right == ["overview"])
            #expect(row.overflow.isEmpty)
            #expect(row.selected == "overview")
        }
    }

    @Test("Selection falls back to the Overview for a tab that does not exist")
    func selectionFallback() {
        #expect(HubTabStrip.selection("b", moduleTabs: ["a", "b"]) == "b")
        #expect(HubTabStrip.selection("zzz", moduleTabs: ["a", "b"]) == "overview")
        #expect(HubTabStrip.selection("a", moduleTabs: []) == "overview")
    }

    @Test("Wide pills take room from the tabs of the right group")
    func widePillsTakeRoom() {
        let plain = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 194,
            rightReservedWidth: HubTabStrip.rightReservedWidth(pills: [])
        )
        let crowded = HubTabStrip.row(
            moduleTabs: eight, selected: "overview",
            leftWingWidth: 194, rightWingWidth: 194,
            rightReservedWidth: HubTabStrip.rightReservedWidth(pills: [
                .init(textLength: 5, hasSymbol: false),
                .init(textLength: 6, hasSymbol: true),
                .init(textLength: 12, hasSymbol: true),
            ])
        )
        #expect(plain.right.count > crowded.right.count)
        #expect(plain.overflow.isEmpty)
        #expect(crowded.moreWing != nil)
    }
}
