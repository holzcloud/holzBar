import CoreGraphics
import Testing
@testable import HolzBarCore

@Suite("MenuBarOcclusion")
struct MenuBarOcclusionTests {
    private let ownPID: pid_t = 100
    private let click = CGPoint(x: 760, y: 12)
    private let notchFrame = CGRect(x: 640, y: 0, width: 240, height: 38)

    private func window(
        layer: Int,
        ownerPID: pid_t = 200,
        bundleID: String? = "theboringteam.boringnotch",
        alpha: Double = 1
    ) -> MenuBarOcclusion.Window {
        (layer: layer, bounds: notchFrame, ownerPID: ownerPID, ownerBundleID: bundleID, alpha: alpha)
    }

    @Test("A notch app above the bar covers it")
    func notchAppCoversTheBar() {
        #expect(MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 27)], ownPID: ownPID))
    }

    @Test("holzBar's own windows and windows at the bar's level or lower do not cover it")
    func ownAndLowWindowsDoNotCover() {
        #expect(!MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 27, ownerPID: ownPID)], ownPID: ownPID))
        #expect(!MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 25)], ownPID: ownPID))
        #expect(!MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 0)], ownPID: ownPID))
    }

    @Test("Transparent windows and the system's own processes do not cover it")
    func transparentAndSystemWindowsDoNotCover() {
        #expect(!MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 27, alpha: 0)], ownPID: ownPID))
        #expect(!MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 27, bundleID: "com.apple.controlcenter")], ownPID: ownPID))
        #expect(!MenuBarOcclusion.isCovered(point: click, windows: [window(layer: 27, bundleID: "com.apple.WindowServer")], ownPID: ownPID))
    }

    @Test("A window elsewhere does not cover the point")
    func windowElsewhereDoesNotCover() {
        let away = CGPoint(x: 200, y: 12)
        #expect(!MenuBarOcclusion.isCovered(point: away, windows: [window(layer: 27)], ownPID: ownPID))
    }
}
