import CoreGraphics
import Testing
@testable import HolzBarCore

@Suite("Item capture policy")
struct ItemCapturePolicyTests {
    // MARK: Watchdog

    @Test("Two timeouts replace the queue, the third stops capture")
    func stopsAfterThree() {
        var watchdog = ItemCapturePolicy.Watchdog()
        var actions = [ItemCapturePolicy.Watchdog.Action]()
        var stopped = [Bool]()
        var counts = [Int]()
        for windowID in [CGWindowID(1), 2, 3] {
            actions.append(watchdog.recordTimeout(windowID: windowID))
            stopped.append(watchdog.isStopped)
            counts.append(watchdog.abandonedQueues)
        }
        #expect(actions == [.replaceQueue, .replaceQueue, .stop])
        #expect(stopped == [false, false, true])
        #expect(counts == [1, 2, 3])
    }

    @Test("A timed-out single capture skips its window")
    func skipsHungWindow() {
        var watchdog = ItemCapturePolicy.Watchdog()
        #expect(!watchdog.skips(42))
        _ = watchdog.recordTimeout(windowID: 42)
        #expect(watchdog.skips(42))
        #expect(!watchdog.skips(43))
    }

    @Test("A timed-out composite capture counts but skips no window")
    func compositeTimeoutSkipsNothing() {
        var watchdog = ItemCapturePolicy.Watchdog()
        #expect(watchdog.recordTimeout(windowID: nil) == .replaceQueue)
        #expect(watchdog.abandonedQueues == 1)
        #expect(watchdog.hungWindowIDs.isEmpty)
    }

    @Test("Windows that are gone are forgotten")
    func forgetsGoneWindows() {
        var watchdog = ItemCapturePolicy.Watchdog()
        _ = watchdog.recordTimeout(windowID: 42)
        _ = watchdog.recordTimeout(windowID: 43)
        watchdog.forgetWindows(notIn: [43, 99])
        #expect(watchdog.hungWindowIDs == [43])
        // Forgetting a window does not give back an abandoned queue.
        #expect(watchdog.abandonedQueues == 2)
    }

    // MARK: On Screen

    /// A built-in display and an external one to its right, in the window list's global
    /// coordinates.
    private static let displays = [
        CGRect(x: 0, y: 0, width: 1512, height: 982),
        CGRect(x: 1512, y: 0, width: 2560, height: 1440),
    ]

    @Test(
        "An item is on screen only when it lies entirely on one display",
        arguments: [
            (CGRect(x: 1400, y: 0, width: 24, height: 24), true),
            // Overshoots display 1 by 12 pt into display 2: it straddles two displays.
            (CGRect(x: 1500, y: 0, width: 24, height: 24), false),
            // Overshoots display 1 by 0.5 pt: within the tolerance, as at the outer edge.
            (CGRect(x: 1488.5, y: 0, width: 24, height: 24), true),
            // Overshoots the outer left edge by 0.5 pt: within the tolerance.
            (CGRect(x: -0.5, y: 0, width: 24, height: 24), true),
            (CGRect(x: -10, y: 0, width: 24, height: 24), false),
            // A hidden item, pushed off screen by the expanded section divider.
            (CGRect(x: -9000, y: 0, width: 24, height: 24), false),
            (CGRect(x: 1400, y: 0, width: 0, height: 24), false),
            (CGRect(x: 3000, y: 0, width: 24, height: 24), true),
        ]
    )
    func isOnScreen(bounds: CGRect, expected: Bool) {
        #expect(ItemCapturePolicy.isOnScreen(bounds, displays: Self.displays) == expected)
    }

    @Test("Without displays nothing is on screen")
    func noDisplays() {
        #expect(!ItemCapturePolicy.isOnScreen(CGRect(x: 0, y: 0, width: 24, height: 24), displays: []))
    }
}
