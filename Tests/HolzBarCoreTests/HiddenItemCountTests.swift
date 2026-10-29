import Testing
@testable import HolzBarCore

@Suite("HiddenItemCount")
struct HiddenItemCountTests {
    @Test("The hidden section is counted alone, or with the always-hidden section when asked")
    func countsTheChosenSections() {
        let hiddenOnly = HiddenItemCount.badge(hidden: 5, alwaysHidden: 2, includesAlwaysHidden: false, isHiding: true, isEnabled: true)
        #expect(hiddenOnly == HiddenItemCount.Badge(count: 5, text: "5"))
        let both = HiddenItemCount.badge(hidden: 5, alwaysHidden: 2, includesAlwaysHidden: true, isHiding: true, isEnabled: true)
        #expect(both == HiddenItemCount.Badge(count: 7, text: "7"))
    }

    @Test("The text is the count up to 99 and 99+ above")
    func textCapsAtNinetyNine() {
        #expect(HiddenItemCount.maximumShown == 99)
        #expect(badge(hidden: 1)?.text == "1")
        #expect(badge(hidden: 12)?.text == "12")
        #expect(badge(hidden: 99)?.text == "99")
        #expect(badge(hidden: 100) == HiddenItemCount.Badge(count: 100, text: "99+"))
        #expect(badge(hidden: 1_000)?.text == "99+")
    }

    @Test("A huge count does not trap")
    func hugeCountsDoNotTrap() {
        #expect(badge(hidden: Int.max)?.text == "99+")
        let both = HiddenItemCount.badge(hidden: Int.max, alwaysHidden: Int.max, includesAlwaysHidden: true, isHiding: true, isEnabled: true)
        #expect(both?.text == "99+")
        #expect(both?.count == Int.max)
    }

    @Test("Zero and negative counts give no badge")
    func zeroGivesNothing() {
        #expect(badge(hidden: 0) == nil)
        #expect(badge(hidden: -3) == nil)
        let negativeOther = HiddenItemCount.badge(hidden: 4, alwaysHidden: -9, includesAlwaysHidden: true, isHiding: true, isEnabled: true)
        #expect(negativeOther == HiddenItemCount.Badge(count: 4, text: "4"))
        let allNegative = HiddenItemCount.badge(hidden: -1, alwaysHidden: -1, includesAlwaysHidden: true, isHiding: true, isEnabled: true)
        #expect(allNegative == nil)
    }

    @Test("Nothing shows while the setting is off")
    func offGivesNothing() {
        #expect(HiddenItemCount.badge(hidden: 5, alwaysHidden: 2, includesAlwaysHidden: true, isHiding: true, isEnabled: false) == nil)
        #expect(HiddenItemCount.badge(hidden: 5, alwaysHidden: 0, includesAlwaysHidden: false, isHiding: true, isEnabled: false) == nil)
    }

    @Test("Nothing shows while the items are shown")
    func shownGivesNothing() {
        #expect(HiddenItemCount.badge(hidden: 5, alwaysHidden: 2, includesAlwaysHidden: true, isHiding: false, isEnabled: true) == nil)
        #expect(HiddenItemCount.badge(hidden: 5, alwaysHidden: 0, includesAlwaysHidden: false, isHiding: false, isEnabled: true) == nil)
    }

    private func badge(hidden: Int) -> HiddenItemCount.Badge? {
        HiddenItemCount.badge(hidden: hidden, alwaysHidden: 0, includesAlwaysHidden: false, isHiding: true, isEnabled: true)
    }
}
