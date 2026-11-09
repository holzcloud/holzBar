import Foundation
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

    private static let owner: Int32 = 501
    private static let shownOwners: Set<Int32> = [owner, 777]

    private func isOpenMenu(layer: Int, height: CGFloat, ownerPID: Int32 = owner, barHeight: CGFloat = 24) -> Bool {
        InterfaceWindowRule.isOpenMenu(
            layer: layer,
            height: height,
            ownerPID: ownerPID,
            shownOwners: Self.shownOwners,
            barHeight: barHeight
        )
    }

    @Test("A pop-up menu of a shown item's app is open at any height")
    func popUpMenusCount() {
        for layer in [100, 101] {
            #expect(isOpenMenu(layer: layer, height: 300))
            #expect(isOpenMenu(layer: layer, height: 20))
        }
    }

    @Test("A status-bar window counts only when it is taller than the bar")
    func statusBarWindowsNeedHeight() {
        // Every status item's own window sits at layer 25 in the bar.
        #expect(!isOpenMenu(layer: 25, height: 24, barHeight: 24))
        #expect(!isOpenMenu(layer: 25, height: 37, barHeight: 37))
        #expect(!isOpenMenu(layer: 25, height: 26, barHeight: 24))
        // A popover or panel reaches below the bar.
        #expect(isOpenMenu(layer: 25, height: 300, barHeight: 24))
        #expect(isOpenMenu(layer: 25, height: 300, barHeight: 37))
    }

    @Test("Application menus and normal windows never count")
    func otherLayersNeverCount() {
        #expect(!isOpenMenu(layer: 24, height: 300))
        #expect(!isOpenMenu(layer: 0, height: 300))
        #expect(!isOpenMenu(layer: 3, height: 300))
    }

    @Test("A menu of an app without a shown item never counts")
    func otherOwnersNeverCount() {
        #expect(!isOpenMenu(layer: 101, height: 300, ownerPID: 42))
        #expect(!isOpenMenu(layer: 25, height: 300, ownerPID: 42))
        #expect(InterfaceWindowRule.isOpenMenu(layer: 101, height: 300, ownerPID: 777, shownOwners: [777], barHeight: 24))
        #expect(!InterfaceWindowRule.isOpenMenu(layer: 101, height: 300, ownerPID: 777, shownOwners: [], barHeight: 24))
    }
}
