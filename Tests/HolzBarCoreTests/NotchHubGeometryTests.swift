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
    private let content = Geometry.Content(bodyHeight: 120)

    private func layout(_ display: Geometry.Display) throws -> Geometry.Layout {
        try #require(Geometry.layout(display: display, content: content))
    }

    @Test("A notched display: the silhouette is centred on the notch, 640 wide, and the wings sit beside it")
    func notchedFixtureA() throws {
        let result = try layout(notchedA)
        #expect(result.silhouette.x == 436)
        #expect(result.silhouette.y == 0)
        #expect(result.silhouette.width == 640)
        #expect(result.topRowHeight == 32)
        let left = try #require(result.leftWing)
        let right = try #require(result.rightWing)
        #expect(left.maxX == 655)
        #expect(right.minX == 857)
        #expect(left.minX == 464)
        #expect(right.maxX == 1048)
        #expect(left.height == 32 && right.height == 32)
        #expect(result.notch == Geometry.Rect(x: 663, y: 0, width: 186, height: 32))
        #expect(result.hoverZone == result.notch)
    }

    @Test("The top row follows the larger of the menu bar and the notch, and the body starts 12 below it")
    func topRowAndBody() throws {
        let b = try layout(notchedB)
        #expect(b.silhouette.x == 544)
        #expect(b.topRowHeight == 32)
        #expect(b.body.y == 44)
        let c = try layout(notchedC)
        #expect(c.silhouette.x == 415)
        #expect(c.topRowHeight == 37)
        #expect(c.body.y == 49)
        let tall = Geometry.Display(
            width: 1512, height: 982, menuBarHeight: 30,
            notch: Geometry.Notch(minX: 663, maxX: 849, height: 38)
        )
        #expect(try layout(tall).topRowHeight == 38)
    }

    @Test("A display without a notch: the hub hangs from the top centre with a thin hover zone")
    func notchlessFixture() throws {
        let result = try layout(notchless)
        #expect(result.silhouette.x == 960)
        #expect(result.silhouette.width == 640)
        #expect(result.notch == nil)
        #expect(result.topRowHeight == 24)
        let left = try #require(result.leftWing)
        let right = try #require(result.rightWing)
        #expect(left.maxX == 1276)
        #expect(right.minX == 1284)
        #expect(result.hoverZone == Geometry.Rect(x: 1180, y: 0, width: 200, height: 3))
    }

    @Test("Nothing but the hover zone touches the notch: the wings keep 8 points and the body lies below")
    func clearanceOfTheNotch() throws {
        for display in [notchedA, notchedB, notchedC] {
            let result = try layout(display)
            let notch = try #require(display.notch)
            let inflated = Geometry.Rect(
                x: notch.minX - Geometry.clearance,
                y: 0,
                width: notch.maxX - notch.minX + 2 * Geometry.clearance,
                height: notch.height
            )
            #expect(result.leftWing.map { !$0.intersects(inflated) } ?? true)
            #expect(result.rightWing.map { !$0.intersects(inflated) } ?? true)
            #expect(!result.body.intersects(inflated))
            #expect(result.body.minY >= notch.height + Geometry.bodyGap)
        }
    }

    @Test("A narrow display has no wings, and the silhouette stays 12 points from both edges")
    func narrowDisplay() throws {
        let narrow = Geometry.Display(
            width: 440, height: 800, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 127, maxX: 313, height: 32)
        )
        let result = try layout(narrow)
        #expect(result.leftWing == nil)
        #expect(result.rightWing == nil)
        #expect(result.silhouette.width == 416)
        #expect(result.silhouette.x == 12)
        #expect(result.silhouette.maxX == 428)
    }

    @Test("A notch near an edge moves the silhouette into the display")
    func notchNearAnEdge() throws {
        let display = Geometry.Display(
            width: 900, height: 600, menuBarHeight: 32,
            notch: Geometry.Notch(minX: 20, maxX: 120, height: 32)
        )
        let result = try layout(display)
        #expect(result.silhouette.x == 12)
        #expect(result.silhouette.maxX <= 900 - 12)
        #expect(result.leftWing == nil)
    }

    @Test("A malformed notch counts as none, and a display without a usable size has no layout")
    func malformedValues() throws {
        let malformed: [Geometry.Notch] = [
            Geometry.Notch(minX: 300, maxX: 300, height: 32),
            Geometry.Notch(minX: 400, maxX: 300, height: 32),
            Geometry.Notch(minX: 663, maxX: 2000, height: 32),
            Geometry.Notch(minX: -5, maxX: 100, height: 32),
            Geometry.Notch(minX: 663, maxX: 849, height: 0),
            Geometry.Notch(minX: .nan, maxX: 849, height: 32),
            Geometry.Notch(minX: 663, maxX: .infinity, height: 32),
            Geometry.Notch(minX: 663, maxX: 849, height: .nan),
        ]
        let reference = try layout(Geometry.Display(width: 1512, height: 982, menuBarHeight: 32, notch: nil))
        for notch in malformed {
            let display = Geometry.Display(width: 1512, height: 982, menuBarHeight: 32, notch: notch)
            #expect(try layout(display) == reference)
        }
        let unusable = [
            Geometry.Display(width: 0, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: .nan, height: 982, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: 0, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 1512, height: .infinity, menuBarHeight: 32, notch: nil),
            Geometry.Display(width: 20, height: 982, menuBarHeight: 32, notch: nil),
        ]
        for display in unusable {
            #expect(Geometry.layout(display: display, content: content) == nil)
        }
        #expect(Geometry.layout(display: notchedA, content: Geometry.Content(bodyHeight: .nan)) == nil)
    }

    @Test("A menu bar height that makes no sense falls back to a usable top row")
    func menuBarHeightFallback() throws {
        let display = Geometry.Display(width: 1512, height: 982, menuBarHeight: .nan, notch: nil)
        #expect(try layout(display).topRowHeight == Geometry.fallbackMenuBarHeight)
        let negative = Geometry.Display(width: 1512, height: 982, menuBarHeight: -3, notch: nil)
        #expect(try layout(negative).topRowHeight == Geometry.fallbackMenuBarHeight)
    }

    @Test("The body's height is the content's, the silhouette ends 16 below it, and the width never exceeds 640")
    func bodyAndSilhouette() throws {
        for display in [notchedA, notchedB, notchedC, notchless] {
            let result = try layout(display)
            #expect(result.body.height == 120)
            // The side walls stand 28 inside the bounds (the concave corners flare over that
            // width), and the body keeps 16 from them.
            #expect(result.body.x == result.silhouette.x + 28 + 16)
            #expect(result.body.width == result.silhouette.width - 2 * (28 + 16))
            #expect(result.silhouette.maxY == result.body.maxY + 16)
            #expect(result.silhouette.width <= 640)
        }
    }

    @Test("The body area is 200 points: two rows of 92-point cards and a gap fit, and the silhouette follows")
    func fixedBodyArea() throws {
        #expect(Geometry.bodyHeight == 200)
        #expect(2 * 92 + DesignTokens.Hub.tileGap <= Geometry.bodyHeight)
        let result = try #require(
            Geometry.layout(display: notchedA, content: Geometry.Content(bodyHeight: Geometry.bodyHeight))
        )
        #expect(result.body.height == 200)
        #expect(result.silhouette.height == result.topRowHeight + 12 + 200 + 16)
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
        #expect(Geometry.maximumWidth == 640)
        #expect(Geometry.clearance == 8)
        #expect(Geometry.bodyGap == 12)
        #expect(Geometry.topCornerRadius == 28)
        #expect(Geometry.bottomCornerRadius == 30)
        #expect(Geometry.bodyInset == 16)
        #expect(Geometry.bottomPadding == 16)
        #expect(Geometry.minimumWingWidth == 96)
        #expect(Geometry.screenMargin == 12)
    }
}
