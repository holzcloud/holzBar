//
//  HolzBarShelfPlacementTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("HolzBarShelfPlacement")
struct HolzBarShelfPlacementTests {
    private typealias Placement = HolzBarShelfPlacement

    /// A 1512 by 982 screen with a 37 point menu bar and a Dock at the bottom.
    private let screen = Placement.Screen(
        frame: .init(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: .init(x: 0, y: 70, width: 1512, height: 875),
        menuBarHeight: 37
    )

    /// The attached panel: 400 by 40.
    private let attachedPanel = Placement.Size(width: 400, height: 40)

    /// The floating panel: the same 400 by 40 bar with the floating insets.
    private let floatingPanel = Placement.Size(width: 424, height: 56)

    private func attached(
        _ anchor: Placement.Anchor,
        panel: Placement.Size? = nil,
        screen: Placement.Screen? = nil,
        insets: Placement.Insets = .zero
    ) -> Placement.Point {
        Placement.origin(
            style: .attached,
            anchor: anchor,
            panel: panel ?? attachedPanel,
            screen: screen ?? self.screen,
            insets: insets
        )
    }

    private func floating(
        _ anchor: Placement.Anchor,
        panel: Placement.Size? = nil,
        screen: Placement.Screen? = nil
    ) -> Placement.Point {
        Placement.origin(
            style: .floating,
            anchor: anchor,
            panel: panel ?? floatingPanel,
            screen: screen ?? self.screen,
            insets: Placement.floatingInsets
        )
    }

    private func point(_ x: Double, _ y: Double) -> Placement.Point {
        Placement.Point(x: x, y: y)
    }

    // MARK: Attached: today's numbers

    @Test("Attached: centred on the icon and flush below the menu bar")
    func attachedCentred() {
        #expect(attached(.horizontal(800)) == point(600, 904))
        #expect(attached(.horizontal(1300)) == point(1100, 904))
    }

    @Test("Attached: clamped into the screen on both sides")
    func attachedClamped() {
        #expect(attached(.horizontal(1500)) == point(1112, 904))
        #expect(attached(.horizontal(100)) == point(0, 904))
    }

    @Test("Attached: the screen edge puts the panel flush right")
    func attachedScreenEdge() {
        #expect(attached(.screenEdge) == point(1112, 904))
    }

    @Test("Attached: the pointer's height is ignored")
    func attachedIgnoresPointerHeight() {
        #expect(attached(.pointer(x: 800, y: 500)) == point(600, 904))
        #expect(attached(.pointer(x: 800, y: 10)) == point(600, 904))
    }

    @Test("Attached: a panel wider than the screen sits at the right, as it always did")
    func attachedWiderThanScreen() {
        let wide = Placement.Size(width: 1600, height: 40)
        #expect(attached(.horizontal(800), panel: wide) == point(-88, 904))
    }

    @Test("Attached: with no menu bar the panel hangs from the top of the screen")
    func attachedWithoutMenuBar() {
        var bare = screen
        bare.menuBarHeight = 0
        #expect(attached(.horizontal(800), screen: bare) == point(600, 941))
    }

    @Test("Attached: the insets change nothing")
    func attachedIgnoresInsets() {
        let withInsets = attached(.horizontal(800), insets: Placement.floatingInsets)
        #expect(withInsets == attached(.horizontal(800)))
    }

    // MARK: Floating

    @Test("Floating: the bar's top is 8 points below the menu bar, centred on the icon")
    func floatingCentred() {
        #expect(floating(.horizontal(800)) == point(588, 881))
        #expect(floating(.horizontal(1300)) == point(1088, 881))
    }

    @Test("Floating: clamped into the visible frame less the margin")
    func floatingClamped() {
        #expect(floating(.horizontal(1500)) == point(1092, 881))
        #expect(floating(.horizontal(50)) == point(-4, 881))
    }

    @Test("Floating: the screen edge puts the bar's right side at the margin")
    func floatingScreenEdge() {
        #expect(floating(.screenEdge) == point(1092, 881))
    }

    @Test("Floating: with no menu bar the bar hangs 8 points from the top of the screen")
    func floatingWithoutMenuBar() {
        var bare = screen
        bare.menuBarHeight = 0
        #expect(floating(.horizontal(800), screen: bare) == point(588, 918))
    }

    @Test("Floating: a Dock at the left moves the left limit")
    func floatingWithDockAtLeft() {
        var docked = screen
        docked.visibleFrame = .init(x: 60, y: 0, width: 1452, height: 945)
        #expect(floating(.horizontal(50), screen: docked) == point(56, 881))
    }

    @Test("Floating: a bar wider than the room sits at the right limit")
    func floatingWiderThanRoom() {
        var docked = screen
        docked.visibleFrame = .init(x: 60, y: 0, width: 1452, height: 945)
        let wide = Placement.Size(width: 1624, height: 56)
        #expect(floating(.horizontal(800), panel: wide, screen: docked) == point(-108, 881))
    }

    // MARK: Floating under the pointer

    @Test("Floating: under the pointer the bar's top is 12 points below it")
    func floatingUnderPointer() {
        #expect(floating(.pointer(x: 800, y: 500)) == point(588, 432))
        #expect(floating(.pointer(x: 1500, y: 500)) == point(1092, 432))
    }

    @Test("Floating: near the bottom the bar flips above the pointer")
    func floatingFlipsAbove() {
        #expect(floating(.pointer(x: 800, y: 100)) == point(588, 96))
    }

    @Test("Floating: a pointer in the menu bar leaves the bar below the menu bar")
    func floatingPointerInMenuBar() {
        #expect(floating(.pointer(x: 800, y: 970)) == point(588, 881))
    }

    @Test("Floating: a bar that fits neither below nor above the pointer is kept in the room")
    func floatingPointerWithNoRoomEitherSide() {
        // 400 wide, 700 high: below the pointer at 400 it reaches 48, above it passes the ceiling.
        let tall = Placement.Size(width: 424, height: 716)
        // The bar's bottom is the area's minimum, 78, and its top 778.
        #expect(floating(.pointer(x: 800, y: 400), panel: tall) == point(588, 62))
    }

    // MARK: Floating, tall

    @Test("Floating: a bar taller than the room hangs from the ceiling and is clipped below")
    func floatingTallerThanRoom() {
        let tall = Placement.Size(width: 424, height: 1016)
        #expect(floating(.horizontal(800), panel: tall) == point(588, -79))
        #expect(floating(.pointer(x: 800, y: 500), panel: tall) == point(588, -79))
    }

    @Test("Floating: a bar that exactly fills the room fits")
    func floatingFillingTheRoom() {
        // The room is 937 - 78 = 859 high; the bar is 851.
        let capped = Placement.Size(width: 424, height: 867)
        #expect(floating(.horizontal(800), panel: capped) == point(588, 70))
    }

    // MARK: Odd numbers

    @Test("An anchor that is not a number counts as the screen edge")
    func anchorNotANumber() {
        for bad in [Double.nan, .infinity, -.infinity] {
            #expect(attached(.horizontal(bad)) == attached(.screenEdge))
            #expect(floating(.horizontal(bad)) == floating(.screenEdge))
            #expect(floating(.pointer(x: bad, y: 500)) == floating(.screenEdge))
        }
    }

    @Test("A pointer height that is not a number leaves the bar under the menu bar")
    func pointerHeightNotANumber() {
        #expect(floating(.pointer(x: 800, y: .nan)) == floating(.horizontal(800)))
    }

    @Test("A panel size that is not usable gives the screen's bottom left corner")
    func unusablePanel() {
        let corner = point(0, 0)
        for size in [
            Placement.Size(width: 0, height: 40),
            Placement.Size(width: 400, height: 0),
            Placement.Size(width: -5, height: 40),
            Placement.Size(width: .nan, height: 40),
            Placement.Size(width: 400, height: .infinity),
        ] {
            #expect(attached(.horizontal(800), panel: size) == corner)
            #expect(floating(.horizontal(800), panel: size) == corner)
        }
    }

    @Test("A menu bar height that is not a number counts as no menu bar")
    func menuBarHeightNotANumber() {
        var odd = screen
        odd.menuBarHeight = .nan
        var bare = screen
        bare.menuBarHeight = 0
        #expect(attached(.horizontal(800), screen: odd) == attached(.horizontal(800), screen: bare))
        #expect(floating(.horizontal(800), screen: odd) == floating(.horizontal(800), screen: bare))
    }

    @Test("A screen with a zero-height visible frame still gives a finite origin")
    func zeroHeightVisibleFrame() {
        var flat = screen
        flat.visibleFrame = .init(x: 0, y: 500, width: 1512, height: 0)
        let origin = floating(.pointer(x: 800, y: 500), screen: flat)
        #expect(origin.x.isFinite)
        #expect(origin.y.isFinite)
    }

    @Test("A screen frame that is not finite gives the origin of the space")
    func screenNotFinite() {
        var broken = screen
        broken.frame.width = .nan
        #expect(attached(.horizontal(800), screen: broken) == point(0, 0))
        #expect(floating(.horizontal(800), screen: broken) == point(0, 0))
    }

    @Test("Numbers so large that they overflow still give a finite origin")
    func overflow() {
        let huge = Double.greatestFiniteMagnitude
        let origin = floating(.pointer(x: huge, y: huge))
        #expect(origin.x.isFinite)
        #expect(origin.y.isFinite)
    }

    // MARK: Constants

    @Test("The constants are pinned: gap 8, margin 8, pointer offset 12, insets 0, 12, 16, 12")
    func constants() {
        #expect(Placement.floatingGap == 8)
        #expect(Placement.floatingMargin == 8)
        #expect(Placement.pointerOffset == 12)
        #expect(Placement.floatingInsets == Placement.Insets(top: 0, leading: 12, bottom: 16, trailing: 12))
    }

    @Test("The gap plus the top inset stays below the 15 points the rehide checks add to the panel")
    func gapStaysWithinRehidePadding() {
        #expect(Placement.floatingGap + Placement.floatingInsets.top < 15)
    }
}
