import Foundation
import Testing
@testable import HolzBarCore

@Suite("NotchHubGeometry")
struct NotchHubGeometryTests {
    typealias Geometry = NotchHubGeometry

    // The fixtures are representative values chosen to differ from one another, not
    // measurements of real Macs: the layout never hard-codes a notch.
    private let notchedA = Geometry.Display(
        width: 1512, height: 982, menuBarHeight: 32,
        notch: Geometry.Notch(minX: 663, maxX: 849, height: 32)
    )
    private let notchedB = Geometry.Display(
        width: 1728, height: 1117, menuBarHeight: 32,
        notch: Geometry.Notch(minX: 770, maxX: 958, height: 32)
    )
    private let notchedC = Geometry.Display(
        width: 1470, height: 956, menuBarHeight: 37,
        notch: Geometry.Notch(minX: 642, maxX: 828, height: 37)
    )
    private let notchless = Geometry.Display(width: 2560, height: 1440, menuBarHeight: 24, notch: nil)
    @Test("A menu bar height that makes no sense falls back to a usable top row")
    func menuBarHeightFallback() throws {
        let display = Geometry.Display(width: 1512, height: 982, menuBarHeight: .nan, notch: nil)
        #expect(try island(display).topRowHeight == Geometry.fallbackMenuBarHeight)
        let negative = Geometry.Display(width: 1512, height: 982, menuBarHeight: -3, notch: nil)
        #expect(try island(negative).topRowHeight == Geometry.fallbackMenuBarHeight)
    }

    @Test("The notch comes from the widths of the areas beside it, and only when both are known")
    func notchFromAreaWidths() {
        let notch = Geometry.notch(displayWidth: 1512, leftAreaWidth: 663, rightAreaWidth: 663, height: 32)
        #expect(notch == Geometry.Notch(minX: 663, maxX: 849, height: 32))
        #expect(Geometry.notch(displayWidth: 1512, leftAreaWidth: nil, rightAreaWidth: 663, height: 32) == nil)
        #expect(Geometry.notch(displayWidth: 1512, leftAreaWidth: 663, rightAreaWidth: nil, height: 32) == nil)
        #expect(Geometry.notch(displayWidth: 1512, leftAreaWidth: 900, rightAreaWidth: 900, height: 32) == nil)
        #expect(Geometry.notch(displayWidth: 1512, leftAreaWidth: 663, rightAreaWidth: 663, height: 0) == nil)
    }

    @Test("The flip to AppKit coordinates maps y to the display height minus y minus height")
    func flipToAppKit() {
        let rect = Geometry.Rect(x: 436, y: 10, width: 640, height: 180)
        let flipped = Geometry.flipped(rect, displayHeight: 982)
        #expect(flipped == Geometry.Rect(x: 436, y: 792, width: 640, height: 180))
        #expect(Geometry.flipped(flipped, displayHeight: 982) == rect)
    }

    @Test("A rectangle contains its edges, and touching rectangles do not intersect")
    func rectangleRules() {
        let rect = Geometry.Rect(x: 10, y: 0, width: 20, height: 5)
        #expect(rect.contains(x: 10, y: 0))
        #expect(rect.contains(x: 30, y: 5))
        #expect(!rect.contains(x: 9.9, y: 0))
        #expect(!rect.contains(x: 20, y: 5.1))
        let touching = Geometry.Rect(x: 30, y: 0, width: 5, height: 5)
        #expect(!rect.intersects(touching))
        #expect(rect.intersects(Geometry.Rect(x: 29, y: 4, width: 5, height: 5)))
    }

    @Test("The constants equal the design's numbers")
    func constants() {
        #expect(Geometry.clearance == 8)
        #expect(Geometry.screenMargin == 12)
        #expect(Geometry.hoverZoneWidth == 200)
        #expect(Geometry.hoverZoneHeight == 3)
        #expect(Geometry.fallbackMenuBarHeight == 24)
        #expect(Geometry.bodyHeight == 200)
    }

    // MARK: Compact capsule

    @Test("Compact, notched fixture A: begins at the notch's lower edge, centred on it, at least the notch plus 24")
    func compactNotched() throws {
        let result = try #require(Geometry.compactLayout(display: notchedA, contentWidth: 240))
        #expect(result.silhouette == Geometry.Rect(x: 636, y: 32, width: 240, height: 30))
        #expect(result.hoverZone == result.silhouette)
        // Centred on the notch's centre, 756.
        #expect(result.silhouette.x + result.silhouette.width / 2 == 756)
        let narrow = try #require(Geometry.compactLayout(display: notchedA, contentWidth: 100))
        #expect(narrow.silhouette.width == 210)
        #expect(narrow.silhouette.x == 651)
        let wide = try #require(Geometry.compactLayout(display: notchedA, contentWidth: 400))
        #expect(wide.silhouette.width == 280)
        #expect(wide.silhouette.x == 616)
        #expect(wide.silhouette.y == 32)
        #expect(wide.silhouette.height == 30)
    }

    @Test("Compact, a display without a notch: 200 wide at the narrowest, centred, below the menu bar")
    func compactNotchless() throws {
        let result = try #require(Geometry.compactLayout(display: notchless, contentWidth: 150))
        #expect(result.silhouette == Geometry.Rect(x: 1180, y: 24, width: 200, height: 30))
    }

    @Test("Compact: the capsule lies below the top row, so it never overlaps the notch or a menu bar item")
    func compactNeverOverTheBar() throws {
        for display in [notchedA, notchedB, notchedC, notchless] {
            let result = try #require(Geometry.compactLayout(display: display, contentWidth: 240))
            let full = try island(display)
            #expect(result.silhouette.minY == full.topRowHeight)
            if let notch = full.notch {
                #expect(!result.silhouette.intersects(notch))
                #expect(result.silhouette.minX <= notch.minX - Geometry.compactNotchMargin / 2)
                #expect(result.silhouette.maxX >= notch.maxX + Geometry.compactNotchMargin / 2)
            }
            #expect(result.silhouette.minX >= Geometry.screenMargin)
            #expect(result.silhouette.maxX <= display.width - Geometry.screenMargin)
        }
    }

    @Test("Compact: the top row is the notch when it is taller than the menu bar")
    func compactBelowATallNotch() throws {
        let tall = Geometry.Display(
            width: 1512, height: 982, menuBarHeight: 30,
            notch: Geometry.Notch(minX: 663, maxX: 849, height: 38)
        )
        #expect(try #require(Geometry.compactLayout(display: tall, contentWidth: 240)).silhouette.y == 38)
    }

    @Test("Compact: a malformed notch counts as none, and a display without a usable size has no capsule")
    func compactMalformed() throws {
        let reference = try #require(
            Geometry.compactLayout(
                display: Geometry.Display(width: 1512, height: 982, menuBarHeight: 32, notch: nil),
                contentWidth: 240
            )
        )
        let malformed: [Geometry.Notch] = [
            Geometry.Notch(minX: 300, maxX: 300, height: 32),
            Geometry.Notch(minX: 663, maxX: 2000, height: 32),
            Geometry.Notch(minX: 663, maxX: 849, height: 0),
            Geometry.Notch(minX: .nan, maxX: 849, height: 32),
        ]
        for notch in malformed {
            let display = Geometry.Display(width: 1512, height: 982, menuBarHeight: 32, notch: notch)
            #expect(Geometry.compactLayout(display: display, contentWidth: 240) == reference)
        }
        let unusable = [
            Geometry.Display(width: 0, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: .nan, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: 0, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: .infinity, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 20, height: 982, menuBarHeight: 32, notch: nil),
        ]
        for display in unusable {
            #expect(Geometry.compactLayout(display: display, contentWidth: 240) == nil)
        }
    }

    @Test("Compact: a narrow display clamps the width into the margins, and a width that is no number is the narrowest")
    func compactNarrowDisplayAndOddWidths() throws {
        let narrow = Geometry.Display(width: 300, height: 800, menuBarHeight: 24, notch: nil)
        let clamped = try #require(Geometry.compactLayout(display: narrow, contentWidth: 280))
        #expect(clamped.silhouette.width == 276)
        #expect(clamped.silhouette.x == 12)
        let nan = try #require(Geometry.compactLayout(display: notchedA, contentWidth: .nan))
        #expect(nan.silhouette.width == 210)
        let infinite = try #require(Geometry.compactLayout(display: notchedA, contentWidth: .infinity))
        #expect(infinite.silhouette.width == 280)
        let negative = try #require(Geometry.compactLayout(display: notchedA, contentWidth: -50))
        #expect(negative.silhouette.width == 210)
    }

    @Test("Compact: a notch near an edge moves the capsule into the display")
    func compactNearAnEdge() throws {
        let display = Geometry.Display(
            width: 900, height: 600, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 20, maxX: 120, height: 32)
        )
        let result = try #require(Geometry.compactLayout(display: display, contentWidth: 240))
        #expect(result.silhouette.x == 12)
        #expect(result.silhouette.maxX <= 900 - 12)
    }

    @Test("The compact constants equal the design's numbers")
    func compactConstants() {
        #expect(Geometry.compactHeight == 30)
        #expect(Geometry.compactMinimumWidth == 200)
        #expect(Geometry.compactMaximumWidth == 280)
        #expect(Geometry.compactNotchMargin == 24)
        #expect(Geometry.compactTopRadius == 12)
        #expect(Geometry.compactBottomRadius == 18)
    }

    // MARK: Island

    private func island(
        _ display: Geometry.Display,
        contentHeight: Double = DesignTokens.Island.contentHeight,
        width: Double = DesignTokens.Island.baseWidth,
        buttonSize: Double = 30
    ) throws -> Geometry.IslandLayout {
        try #require(
            Geometry.island(display: display, contentHeight: contentHeight, width: width, buttonSize: buttonSize)
        )
    }

    @Test("Island, notched fixture A: 560 by 226 at the top, centred on the notch, the hover zone is the notch")
    func islandNotchedFixtureA() throws {
        let result = try island(notchedA)
        #expect(result.shape == Geometry.Rect(x: 476, y: 0, width: 560, height: 226))
        #expect(result.shape.x + result.shape.width / 2 == 756)
        #expect(result.topRowHeight == 32)
        #expect(result.notch == Geometry.Rect(x: 663, y: 0, width: 186, height: 32))
        #expect(result.hoverZone == result.notch)
    }

    @Test("Island: the width grows to the notch plus the two flares, is capped at 640 and the margins, and NaN is 560")
    func islandWidthRules() throws {
        let tiny = try island(notchedA, width: 100)
        #expect(tiny.shape.width == 186 + 2 * 14)
        #expect(tiny.shape.x == 649)
        #expect(try island(notchedA, width: -5).shape.width == 214)
        #expect(try island(notchedA, width: 900).shape.width == 640)
        #expect(try island(notchedA, width: .infinity).shape.width == 640)
        #expect(try island(notchedA, width: .nan).shape.width == 560)
        // A narrow display keeps 12 points to both edges.
        let narrow = Geometry.Display(
            width: 440, height: 800, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 127, maxX: 313, height: 32)
        )
        let clamped = try island(narrow, width: 640)
        #expect(clamped.shape.width == 416)
        #expect(clamped.shape.x == 12)
        // A notch near an edge moves the island into the display.
        let edge = Geometry.Display(
            width: 900, height: 600, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 20, maxX: 120, height: 32)
        )
        let moved = try island(edge)
        #expect(moved.shape.x == 12)
        #expect(moved.shape.maxX <= 900 - 12)
    }

    @Test("Island: the context row, the content and the module row stack inside the black body")
    func islandRowsInsideTheBody() throws {
        for display in [notchedA, notchedB, notchedC, notchless] {
            let result = try island(display)
            let inset = DesignTokens.Island.openTopRadius + DesignTokens.Island.sidePadding
            let bodyX = result.shape.x + inset
            let bodyWidth = result.shape.width - 2 * inset
            #expect(result.contextRow.y == result.topRowHeight + 8)
            #expect(result.contextRow.height == 22)
            #expect(result.content.y == result.contextRow.maxY)
            #expect(result.content.height == 110)
            #expect(result.moduleRow.height == 30)
            #expect(result.moduleRow.maxY == result.shape.maxY - 12)
            #expect(result.moduleRow.minY == result.content.maxY + 12)
            for row in [result.contextRow, result.content, result.moduleRow] {
                #expect(row.x == bodyX)
                #expect(row.width == bodyWidth)
            }
            if let notch = result.notch {
                #expect(!result.contextRow.intersects(notch))
            }
        }
    }

    @Test("Island, a display without a notch: centred on the display, the top row is the menu bar, a thin hover zone")
    func islandNotchless() throws {
        let result = try island(notchless)
        #expect(result.shape == Geometry.Rect(x: 1000, y: 0, width: 560, height: 24 + 8 + 22 + 110 + 12 + 30 + 12))
        #expect(result.notch == nil)
        #expect(result.topRowHeight == 24)
        #expect(result.hoverZone == Geometry.Rect(x: 1180, y: 0, width: 200, height: 3))
    }

    @Test("Island: the height follows the content's height and the module row's button size")
    func islandHeightFollowsTheContent() throws {
        #expect(try island(notchedA, contentHeight: 190).shape.height == 306)
        #expect(try island(notchedA, buttonSize: 26).shape.height == 222)
        let tall = Geometry.Display(
            width: 1512, height: 982, menuBarHeight: 30,
            notch: Geometry.Notch(minX: 663, maxX: 849, height: 38)
        )
        #expect(try island(tall).topRowHeight == 38)
        #expect(try island(tall).shape.height == 232)
    }

    @Test("Island: a malformed notch counts as none, and a display or a content height that makes no sense has no island")
    func islandMalformed() throws {
        let reference = try island(Geometry.Display(width: 1512, height: 982, menuBarHeight: 32, notch: nil))
        let malformed = [
            Geometry.Notch(minX: 300, maxX: 300, height: 32),
            Geometry.Notch(minX: 663, maxX: 2000, height: 32),
            Geometry.Notch(minX: 663, maxX: 849, height: 0),
            Geometry.Notch(minX: .nan, maxX: 849, height: 32),
        ]
        for notch in malformed {
            let display = Geometry.Display(width: 1512, height: 982, menuBarHeight: 32, notch: notch)
            #expect(try island(display) == reference)
        }
        let unusable = [
            Geometry.Display(width: 0, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: .nan, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: 0, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: .infinity, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 20, height: 982, menuBarHeight: 32, notch: nil),
        ]
        for display in unusable {
            #expect(Geometry.island(display: display, contentHeight: 110, width: 560) == nil)
        }
        #expect(Geometry.island(display: notchedA, contentHeight: .nan, width: 560) == nil)
        #expect(Geometry.island(display: notchedA, contentHeight: -1, width: 560) == nil)
    }

    @Test("The content height: 110 for a module, 110 to 190 by preference, the Overview by its rows of cards")
    func contentHeightRules() {
        #expect(Geometry.contentHeight(overviewTileCount: nil) == 110)
        #expect(Geometry.contentHeight(overviewTileCount: nil, preferred: 160) == 160)
        #expect(Geometry.contentHeight(overviewTileCount: nil, preferred: 300) == 190)
        #expect(Geometry.contentHeight(overviewTileCount: nil, preferred: 50) == 110)
        #expect(Geometry.contentHeight(overviewTileCount: nil, preferred: .nan) == 110)
        #expect(Geometry.contentHeight(overviewTileCount: 0) == 190)
        #expect(Geometry.contentHeight(overviewTileCount: -3) == 190)
        for count in 1...4 {
            #expect(Geometry.contentHeight(overviewTileCount: count) == 110)
        }
        for count in 5...8 {
            #expect(Geometry.contentHeight(overviewTileCount: count) == 190)
        }
        #expect(Geometry.contentHeight(overviewTileCount: 40) == 190)
    }

    @Test("The seed is the notch's rectangle, or a flat strip at the top centre without a notch")
    func seedRules() {
        #expect(Geometry.seed(display: notchedA) == Geometry.Rect(x: 663, y: 0, width: 186, height: 32))
        #expect(Geometry.seed(display: notchedC) == Geometry.Rect(x: 642, y: 0, width: 186, height: 37))
        #expect(Geometry.seed(display: notchless) == Geometry.Rect(x: 1180, y: 0, width: 200, height: 0))
        #expect(Geometry.seed(display: Geometry.Display(width: 0, height: 982, menuBarHeight: 32, notch: nil)) == nil)
    }

    @Test("The transition frame is both shapes plus the margin on the sides and the bottom, kept inside the display")
    func transitionFrameRules() throws {
        let margin = DesignTokens.Island.transitionMargin
        #expect(margin == 12)
        // From the seed of display A to its open island.
        let seed = try #require(Geometry.seed(display: notchedA))
        let open = try island(notchedA).shape
        let frame = Geometry.transitionFrame(from: seed, to: open, displayWidth: notchedA.width)
        #expect(frame == Geometry.Rect(x: open.x - margin, y: 0, width: open.width + 2 * margin, height: open.height + margin))
        // Closing is the same union the other way round.
        #expect(Geometry.transitionFrame(from: open, to: seed, displayWidth: notchedA.width) == frame)
        // Equal rectangles give that rectangle plus the margin.
        let same = Geometry.Rect(x: 100, y: 0, width: 200, height: 50)
        #expect(
            Geometry.transitionFrame(from: same, to: same, displayWidth: 1000)
                == Geometry.Rect(x: 88, y: 0, width: 224, height: 62)
        )
        // Never beyond the display's sides.
        let atEdges = Geometry.Rect(x: 5, y: 0, width: 100, height: 40)
        #expect(
            Geometry.transitionFrame(from: atEdges, to: atEdges, displayWidth: 110)
                == Geometry.Rect(x: 0, y: 0, width: 110, height: 52)
        )
        // Never above the top of the display.
        let above = Geometry.Rect(x: 100, y: -3, width: 50, height: 20)
        #expect(Geometry.transitionFrame(from: above, to: above, displayWidth: 1000).y == 0)
    }

    // MARK: Live state

    @Test("Live, notched fixture A: at the top edge, the top row high, the notch plus 90 on each side, centred on the notch")
    func liveNotched() throws {
        let result = try #require(Geometry.live(display: notchedA))
        let side = DesignTokens.Island.liveSideWidth
        let radius = DesignTokens.Island.liveTopRadius
        #expect(side == 90)
        #expect(radius == 6)
        // The black part is 663 - 90 ... 849 + 90, the bounds add the 6 point flare on each side.
        #expect(result.shape == Geometry.Rect(x: 567, y: 0, width: 378, height: 32))
        #expect(result.shape.x + result.shape.width / 2 == 756)
        #expect(result.shape.minX + radius == 663 - side)
        #expect(result.shape.maxX - radius == 849 + side)
        #expect(result.hoverZone == result.shape)
        // The areas keep the clearance to the notch and never touch it.
        #expect(result.leading == Geometry.Rect(x: 573, y: 0, width: 82, height: 32))
        #expect(result.trailing == Geometry.Rect(x: 857, y: 0, width: 82, height: 32))
        #expect(result.leading.maxX == 663 - Geometry.clearance)
        #expect(result.trailing.minX == 849 + Geometry.clearance)
        let notch = Geometry.Rect(x: 663, y: 0, width: 186, height: 32)
        #expect(!result.leading.intersects(notch))
        #expect(!result.trailing.intersects(notch))
    }

    @Test("Live: never taller than the top row, on every notched fixture")
    func liveNeverGrowsDownward() throws {
        for display in [notchedA, notchedB, notchedC, notchless] {
            let result = try #require(Geometry.live(display: display))
            let full = try island(display)
            #expect(result.shape.minY == 0)
            #expect(result.shape.height == full.topRowHeight)
            #expect(result.leading.height == full.topRowHeight)
            #expect(result.trailing.height == full.topRowHeight)
            #expect(result.shape.minX >= Geometry.screenMargin)
            #expect(result.shape.maxX <= display.width - Geometry.screenMargin)
            if let notch = full.notch {
                #expect(!result.leading.intersects(notch))
                #expect(!result.trailing.intersects(notch))
                #expect(result.shape.width == notch.width + 2 * DesignTokens.Island.liveSideWidth + 2 * DesignTokens.Island.liveTopRadius)
            }
        }
        #expect(try #require(Geometry.live(display: notchedC)).shape.height == 37)
    }

    @Test("Live, a display without a notch: centred at menu bar height, the areas half the clearance from the centre")
    func liveNotchless() throws {
        let result = try #require(Geometry.live(display: notchless))
        // 90 on each side of the centre 1280, plus the flare.
        #expect(result.shape == Geometry.Rect(x: 1184, y: 0, width: 192, height: 24))
        #expect(result.leading == Geometry.Rect(x: 1190, y: 0, width: 86, height: 24))
        #expect(result.trailing == Geometry.Rect(x: 1284, y: 0, width: 86, height: 24))
        #expect(result.leading.maxX == 1280 - Geometry.clearance / 2)
        #expect(result.trailing.minX == 1280 + Geometry.clearance / 2)
        #expect(result.hoverZone == result.shape)
    }

    @Test("Live: a notch near an edge moves the shape into the margins, and a display that makes no sense has none")
    func liveEdgesAndMalformed() throws {
        let nearLeft = Geometry.Display(
            width: 1512, height: 982, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 20, maxX: 206, height: 32)
        )
        let left = try #require(Geometry.live(display: nearLeft))
        #expect(left.shape.minX == Geometry.screenMargin)
        #expect(left.shape.width == 378)
        #expect(left.leading.width == 0)
        #expect(!left.leading.intersects(Geometry.Rect(x: 20, y: 0, width: 186, height: 32)))
        let nearRight = Geometry.Display(
            width: 1512, height: 982, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 1306, maxX: 1492, height: 32)
        )
        let right = try #require(Geometry.live(display: nearRight))
        #expect(right.shape.maxX == 1512 - Geometry.screenMargin)
        #expect(right.trailing.width == 0)
        let unusable = [
            Geometry.Display(width: 0, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: .nan, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: 0, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 20, height: 982, menuBarHeight: 32, notch: nil),
        ]
        for display in unusable {
            #expect(Geometry.live(display: display) == nil)
        }
        let malformed = Geometry.Display(
            width: 1512, height: 982, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 663, maxX: 849, height: 0)
        )
        #expect(try #require(Geometry.live(display: malformed)).shape.width == 192)
    }
}
