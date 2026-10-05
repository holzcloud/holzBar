import CoreGraphics
import Foundation
import Testing
@testable import HolzBarMacOS27Core

/// Windows as measured on macOS 27.0: Notification Center's panel stands at layer 21 and the
/// size of the display, Control Centre's at layer 101 and 964 pt tall. A banner shows in a
/// window of Notification Center's process, at the same level and size.
private enum Windows {
    static let notificationCenter: ItemClick27.PanelWindow = (number: 45, layer: 21, height: 1080.0, ownerPID: 300)
    static let controlCentre: ItemClick27.PanelWindow = (number: 46, layer: 101, height: 964.0, ownerPID: 400)
    static let banner: ItemClick27.PanelWindow = (number: 47, layer: 21, height: 1080.0, ownerPID: 300)
    static let clock = "com.apple.menuextra.clock"
    static let controlCentreItem = "com.apple.menuextra.controlcenter"
    static let notificationCenterPanel = ItemClick27.OpenPanel(item: clock, window: 45, ownerPID: 300)
}

@Suite("Click bridge steps")
struct ClickBridgeStep27Tests {
    @Test("A click on the item whose panel is still up dismisses it")
    func dismissesTheRememberedPanel() {
        let step = ItemClick27.firstStep(
            remembered: Windows.notificationCenterPanel,
            windows: [Windows.notificationCenter],
            mayOpenFromPress: false
        )
        #expect(step == .dismiss(Windows.notificationCenterPanel))
    }

    @Test("A remembered panel whose window went is not dismissed, even with a banner up")
    func staleMemoryIsReplayed() {
        let step = ItemClick27.firstStep(
            remembered: Windows.notificationCenterPanel,
            windows: [Windows.banner],
            mayOpenFromPress: false
        )
        #expect(step == .liftAndReplay)
    }

    @Test("Without a remembered panel a banner never leads to Escape")
    func bannerWithoutMemoryIsReplayed() {
        let step = ItemClick27.firstStep(remembered: nil, windows: [Windows.banner], mayOpenFromPress: false)
        #expect(step == .liftAndReplay)
    }

    @Test("An item that opens from a press is pressed when no panel is up")
    func pressWhenNothingIsUp() {
        let step = ItemClick27.firstStep(remembered: nil, windows: [], mayOpenFromPress: true)
        #expect(step == .press)
    }

    @Test("A panel holzBar did not see open is closed by the replayed click, not the press")
    func unknownPanelIsReplayed() {
        let step = ItemClick27.firstStep(remembered: nil, windows: [Windows.controlCentre], mayOpenFromPress: true)
        #expect(step == .liftAndReplay)
    }

    @Test("Once the panel went, a click on its own item is done")
    func sameItemDoneAfterDismissal() {
        let step = ItemClick27.stepAfterDismissal(
            of: Windows.notificationCenterPanel,
            clickedItem: Windows.clock,
            windowWent: true,
            windows: [],
            mayOpenFromPress: false
        )
        #expect(step == nil)
    }

    @Test("Once the panel went, another item still opens its own")
    func otherItemOpensAfterDismissal() {
        let pressed = ItemClick27.stepAfterDismissal(
            of: Windows.notificationCenterPanel,
            clickedItem: Windows.controlCentreItem,
            windowWent: true,
            windows: [],
            mayOpenFromPress: true
        )
        let replayed = ItemClick27.stepAfterDismissal(
            of: Windows.notificationCenterPanel,
            clickedItem: Windows.controlCentreItem,
            windowWent: true,
            windows: [],
            mayOpenFromPress: false
        )
        #expect(pressed == .press)
        #expect(replayed == .liftAndReplay)
    }

    @Test("A panel that stays after Escape has the click replayed, never dropped or pressed")
    func panelThatStaysIsReplayed() {
        for (item, mayOpenFromPress) in [(Windows.clock, false), (Windows.controlCentreItem, false), (Windows.controlCentreItem, true)] {
            let step = ItemClick27.stepAfterDismissal(
                of: Windows.notificationCenterPanel,
                clickedItem: item,
                windowWent: false,
                windows: [Windows.notificationCenter],
                mayOpenFromPress: mayOpenFromPress
            )
            #expect(step == .liftAndReplay)
        }
    }

    @Test("A click on the panel's own item waits longer for Escape than a click elsewhere")
    func ownItemWaitsLongerForEscape() {
        let panel = Windows.notificationCenterPanel
        let ownItem = ItemClick27.escapeAnswerPolls(for: panel, clickedItem: Windows.clock)
        let otherItem = ItemClick27.escapeAnswerPolls(for: panel, clickedItem: Windows.controlCentreItem)
        let overflowButton = ItemClick27.escapeAnswerPolls(for: panel, clickedItem: nil)
        // A replay onto a panel still sliding out would open it again.
        #expect(ownItem * 50 >= 600)
        #expect(otherItem * 50 == 200)
        #expect(overflowButton == otherItem)
    }

    @Test("A click on the overflow button still opens after the panel went")
    func overflowButtonAfterDismissal() {
        let step = ItemClick27.stepAfterDismissal(
            of: Windows.notificationCenterPanel,
            clickedItem: nil,
            windowWent: true,
            windows: [],
            mayOpenFromPress: false
        )
        #expect(step != nil)
    }

    @Test("A new panel window after the click is the panel that opened")
    func newWindowIsTheOpenedPanel() {
        let opened = ItemClick27.openedPanel(item: Windows.clock, before: [10, 11], windows: [Windows.notificationCenter])
        #expect(opened == ItemClick27.OpenPanel(item: Windows.clock, window: 45, ownerPID: 300))
    }

    @Test("A window that was there before the click is no panel that opened")
    func reusedWindowIsNotOpened() {
        let opened = ItemClick27.openedPanel(item: Windows.clock, before: [10, 45], windows: [Windows.notificationCenter])
        #expect(opened == nil)
    }

    @Test("No panel without an item, or for a window too small or too low")
    func notAPanel() {
        let withoutItem = ItemClick27.openedPanel(item: nil, before: [], windows: [Windows.notificationCenter])
        let small = ItemClick27.openedPanel(
            item: Windows.clock,
            before: [],
            windows: [(number: 48, layer: 101, height: 28.0, ownerPID: 400)]
        )
        let low = ItemClick27.openedPanel(
            item: Windows.clock,
            before: [],
            windows: [(number: 49, layer: 0, height: 700.0, ownerPID: 300)]
        )
        #expect(withoutItem == nil)
        #expect(small == nil)
        #expect(low == nil)
    }
}

@Suite("Panel memory")
struct PanelMemory27Tests {
    // The memory is changed outside `#expect`, whose expansion cannot call a mutating method.

    @Test("A panel opened by the latest click is handed to the next bridged click once")
    func handedToTheNextClick() {
        var memory = ItemClick27.PanelMemory()
        let opening = memory.takeForBridgedClick()
        memory.remember(Windows.notificationCenterPanel, openedBy: opening.click)
        #expect(memory.panel == Windows.notificationCenterPanel)
        let next = memory.takeForBridgedClick()
        #expect(next.remembered == Windows.notificationCenterPanel)
        #expect(memory.panel == nil)
    }

    @Test("A click let through forgets the panel")
    func forgetDropsThePanel() {
        var memory = ItemClick27.PanelMemory()
        let opening = memory.takeForBridgedClick()
        memory.remember(Windows.notificationCenterPanel, openedBy: opening.click)
        memory.forget()
        #expect(memory.panel == nil)
    }

    @Test("A panel found for a click that a later click overtook is not remembered")
    func rapidDoubleClick() {
        var memory = ItemClick27.PanelMemory()
        let first = memory.takeForBridgedClick()
        _ = memory.takeForBridgedClick()
        memory.remember(Windows.notificationCenterPanel, openedBy: first.click)
        #expect(memory.panel == nil)
    }

    @Test("A panel found after a click was let through meanwhile is not remembered")
    func clickLetThroughMeanwhile() {
        var memory = ItemClick27.PanelMemory()
        let opening = memory.takeForBridgedClick()
        memory.forget()
        memory.remember(Windows.notificationCenterPanel, openedBy: opening.click)
        #expect(memory.panel == nil)
    }

    @Test("The latest click finding no panel clears the memory")
    func noPanelClears() {
        var memory = ItemClick27.PanelMemory()
        let opening = memory.takeForBridgedClick()
        memory.remember(Windows.notificationCenterPanel, openedBy: opening.click)
        memory.remember(nil, openedBy: opening.click)
        #expect(memory.panel == nil)
    }
}
