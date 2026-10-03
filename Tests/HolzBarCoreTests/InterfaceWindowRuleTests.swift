import Testing
@testable import HolzBarCore

@Suite("InterfaceWindowRule")
struct InterfaceWindowRuleTests {
    @Test("Only menus count")
    func onlyMenusCount() {
        for layer in [24, 25, 100, 101] {
            #expect(InterfaceWindowRule.counts(layer: layer, isOwnersWindow: true, appearedAfterClick: true))
        }
        // A floating window and a normal window never count.
        #expect(!InterfaceWindowRule.counts(layer: 3, isOwnersWindow: true, appearedAfterClick: true))
        #expect(!InterfaceWindowRule.counts(layer: 0, isOwnersWindow: true, appearedAfterClick: true))
    }

    @Test("A menu counts only for the item's app and only when it is new")
    func onlyTheOwnersNewMenuCounts() {
        #expect(!InterfaceWindowRule.counts(layer: 101, isOwnersWindow: false, appearedAfterClick: true))
        #expect(!InterfaceWindowRule.counts(layer: 101, isOwnersWindow: true, appearedAfterClick: false))
    }
}
