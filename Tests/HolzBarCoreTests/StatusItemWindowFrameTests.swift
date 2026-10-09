import CoreGraphics
import Testing
@testable import HolzBarCore

/// The frames are measured on macOS 26.7.1 with a 3440 × 1440 primary display and a
/// second display to its left: an NSStatusItem's window frame in AppKit, and the bounds of
/// the Control Center window that draws the item, from the window list.
@Suite("StatusItemWindowFrame")
struct StatusItemWindowFrameTests {
    /// The primary display's height in the measurements.
    private let primaryScreenHeight: CGFloat = 1440

    @Test("AppKit frames become window bounds with the origin at the top left")
    func convertsToWindowBounds() {
        let bounds = StatusItemWindowFrame.windowBounds(
            fromAppKitFrame: CGRect(x: 2510, y: 1410, width: 46, height: 30),
            primaryScreenHeight: primaryScreenHeight
        )
        #expect(bounds == CGRect(x: 2510, y: 0, width: 46, height: 30))
    }

    @Test(
        "The Control Center window of a status item matches the item's frame",
        arguments: [
            // A standard item.
            (CGRect(x: -2517, y: 1410, width: 24, height: 30), CGRect(x: -2517, y: 0, width: 24, height: 30)),
            // A divider expanded to 10 000 points, which the window server clamps to 5016.
            (CGRect(x: -7533, y: 1410, width: 5016, height: 30), CGRect(x: -7533, y: 0, width: 5016, height: 30)),
            // A divider of length 0 (holzBar turns its width constraint off: 1 point wide).
            (CGRect(x: -2533, y: 1410, width: 1, height: 30), CGRect(x: -2533, y: 0, width: 1, height: 30)),
            // Edges one point apart.
            (CGRect(x: -2517, y: 1410, width: 24, height: 30), CGRect(x: -2516, y: 1, width: 24, height: 30)),
        ]
    )
    func matchesItsWindow(appKitFrame: CGRect, windowBounds: CGRect) {
        #expect(StatusItemWindowFrame.matches(windowBounds, appKitFrame: appKitFrame, primaryScreenHeight: primaryScreenHeight))
    }

    @Test(
        "Other windows do not match",
        arguments: [
            // The item's copy on the second display.
            (CGRect(x: -2547, y: 1410, width: 30, height: 30), CGRect(x: -5985, y: 458, width: 30, height: 33)),
            // The neighbouring item.
            (CGRect(x: -2547, y: 1410, width: 30, height: 30), CGRect(x: -2517, y: 0, width: 24, height: 30)),
            // Edges two points apart.
            (CGRect(x: -2517, y: 1410, width: 24, height: 30), CGRect(x: -2515, y: 0, width: 24, height: 30)),
            // One edge two points apart: the same place, another width.
            (CGRect(x: -2517, y: 1410, width: 24, height: 30), CGRect(x: -2517, y: 0, width: 26, height: 30)),
            // An item in the same place on a bar of another height.
            (CGRect(x: -2517, y: 1410, width: 24, height: 30), CGRect(x: -2517, y: 0, width: 24, height: 24)),
        ]
    )
    func doesNotMatchOtherWindows(appKitFrame: CGRect, windowBounds: CGRect) {
        #expect(!StatusItemWindowFrame.matches(windowBounds, appKitFrame: appKitFrame, primaryScreenHeight: primaryScreenHeight))
    }

    /// Two collapsed dividers next to each other, measured on macOS 26.7.1 with the default
    /// divider style: the hidden section's divider at 2531 and the always-hidden section's
    /// at 2530, each 1 point wide. Each window lies within the tolerance of both frames.
    private let adjacentDividerFrames = [
        CGRect(x: 2531, y: 1410, width: 1, height: 30),
        CGRect(x: 2530, y: 1410, width: 1, height: 30),
    ]
    private let adjacentDividerWindows = [
        CGRect(x: 2531, y: 0, width: 1, height: 30),
        CGRect(x: 2530, y: 0, width: 1, height: 30),
    ]

    @Test("Adjacent collapsed dividers each get their own window")
    func assignsAdjacentDividersToTheirOwnWindows() {
        #expect(StatusItemWindowFrame.assign(
            windowBounds: adjacentDividerWindows,
            toAppKitFrames: adjacentDividerFrames,
            primaryScreenHeight: primaryScreenHeight
        ) == [0, 1])
        // The order of the frames does not decide which window a frame gets.
        #expect(StatusItemWindowFrame.assign(
            windowBounds: adjacentDividerWindows,
            toAppKitFrames: adjacentDividerFrames.reversed(),
            primaryScreenHeight: primaryScreenHeight
        ) == [1, 0])
        #expect(StatusItemWindowFrame.assign(
            windowBounds: adjacentDividerWindows.reversed(),
            toAppKitFrames: adjacentDividerFrames,
            primaryScreenHeight: primaryScreenHeight
        ) == [1, 0])
    }

    @Test("A frame goes to one window only, the closest")
    func assignsEachFrameOnce() {
        let frame = CGRect(x: -2517, y: 1410, width: 24, height: 30)
        let windows = [
            // One point off: within the tolerance, but not the closest.
            CGRect(x: -2516, y: 0, width: 24, height: 30),
            // The item's own window.
            CGRect(x: -2517, y: 0, width: 24, height: 30),
            // The item's copy on the second display.
            CGRect(x: -5985, y: 458, width: 30, height: 33),
        ]
        #expect(StatusItemWindowFrame.assign(
            windowBounds: windows,
            toAppKitFrames: [frame],
            primaryScreenHeight: primaryScreenHeight
        ) == [nil, 0, nil])
    }

    @Test("A tie goes to the earlier frame")
    func breaksTiesByFrameOrder() {
        let window = CGRect(x: 2530, y: 0, width: 2, height: 30)
        let frames = [
            CGRect(x: 2531, y: 1410, width: 1, height: 30),
            CGRect(x: 2530, y: 1410, width: 1, height: 30),
        ]
        #expect(StatusItemWindowFrame.assign(
            windowBounds: [window],
            toAppKitFrames: frames,
            primaryScreenHeight: primaryScreenHeight
        ) == [0])
    }

    @Test("A window without a size matches nothing")
    func emptyFrameMatchesNothing() {
        let empty = CGRect(x: 0, y: 0, width: 0, height: 0)
        #expect(!StatusItemWindowFrame.matches(
            StatusItemWindowFrame.windowBounds(fromAppKitFrame: empty, primaryScreenHeight: primaryScreenHeight),
            appKitFrame: empty,
            primaryScreenHeight: primaryScreenHeight
        ))
    }
}
