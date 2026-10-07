import CoreGraphics
import Testing
@testable import HolzBarCore

@Suite("RehideClickTarget")
struct RehideClickTargetTests {
    private let dockPID: pid_t = 100
    private let cursorLayer = 2_147_483_630
    private let point = CGPoint(x: 50, y: 50)
    private let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func window(layer: Int, ownerPID: pid_t = 200, bounds: CGRect? = nil) -> RehideClickTarget.Window {
        RehideClickTarget.Window(layer: layer, ownerPID: ownerPID, bounds: bounds ?? self.bounds)
    }

    private func index(of windows: [RehideClickTarget.Window]) -> Int? {
        RehideClickTarget.clickedWindowIndex(in: windows, at: point, cursorLayer: cursorLayer, dockPID: dockPID)
    }

    @Test("The topmost app window under the point wins, title or not")
    func appWindowWins() {
        // Only layer, owner and bounds are known: no title is needed.
        #expect(index(of: [window(layer: 0), window(layer: 0, ownerPID: 300)]) == 0)
    }

    @Test("Windows away from the point are passed over")
    func windowsAwayFromThePointArePassedOver() {
        let away = CGRect(x: 200, y: 200, width: 100, height: 100)
        #expect(index(of: [window(layer: 0, bounds: away), window(layer: 0, ownerPID: 300)]) == 1)
    }

    @Test("Floating and desktop-level windows of other apps are skipped")
    func otherLevelsOfOtherAppsAreSkipped() {
        // A floating panel, the Finder's desktop and a Notification Center widget.
        let windows = [
            window(layer: 3),
            window(layer: -2_147_483_603, ownerPID: 300),
            window(layer: -2_147_483_624, ownerPID: 400),
        ]
        #expect(index(of: windows) == nil)
        #expect(index(of: windows + [window(layer: 0, ownerPID: 500)]) == 3)
    }

    @Test("A Dock window counts at any level")
    func dockWindowCountsAtAnyLevel() {
        for layer in [-2_147_483_624, -2_147_483_603, 0, 20] {
            #expect(index(of: [window(layer: 3), window(layer: layer, ownerPID: dockPID)]) == 1)
        }
        // Without a Dock, only app windows count.
        #expect(RehideClickTarget.clickedWindowIndex(in: [window(layer: 20)], at: point, cursorLayer: cursorLayer, dockPID: nil) == nil)
    }

    @Test("Windows at or above the cursor's level are ignored")
    func cursorLevelIsIgnored() {
        let windows = [
            window(layer: cursorLayer, ownerPID: dockPID),
            window(layer: cursorLayer + 1, ownerPID: dockPID),
            window(layer: 0),
        ]
        #expect(index(of: windows) == 2)
        #expect(RehideClickTarget.clickedWindowIndex(in: [window(layer: 0)], at: point, cursorLayer: 0, dockPID: dockPID) == nil)
    }
}
