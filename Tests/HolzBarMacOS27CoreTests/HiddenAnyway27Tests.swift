import CoreGraphics
import Testing
@testable import HolzBarMacOS27Core

@Suite("HiddenAnyway27")
struct HiddenAnyway27Tests {
    typealias Item = HiddenAnyway27.DrawnItem

    /// An item of the bar at the given place; measured on macOS 27.0, items are 24 points high
    /// and neighbours overlap by 2 points.
    func frame(_ x: CGFloat, width: CGFloat = 34) -> CGRect {
        CGRect(x: x, y: 7.5, width: width, height: 24)
    }

    func app(_ bundleID: String, _ x: CGFloat, width: CGFloat = 34) -> Item {
        Item(bundleID: bundleID, frame: frame(x, width: width))
    }

    func live(_ x: CGFloat, width: CGFloat = 34) -> Item {
        Item(bundleID: nil, frame: frame(x, width: width))
    }

    @Test("Items laid out side by side hide nothing")
    func laidOut() {
        let items = [
            app("com.example.history", 1242),
            live(1274),
            live(1306),
            live(1338, width: 38),
            live(1374, width: 120),
        ]
        #expect(HiddenAnyway27.suspects(among: items).isEmpty)
    }

    @Test("A visible app MenuBarAgent hides anyway is named (macOS 27.2)")
    func agentHiddenAnyway() {
        // The bar of the report: the clock-history item, holzBar's icon, Bluetooth, Wi-Fi,
        // battery, Control Centre and the clock are drawn. A device management agent is visible
        // in the layout, but MenuBarAgent hides it; Accessibility still reports it where it was
        // last drawn, which is where holzBar's icon stands now.
        let items = [
            app("com.example.history", 1242),
            app("com.example.agent", 1278, width: 30),
            live(1274),
            live(1306),
            live(1338),
            live(1370, width: 38),
            live(1406),
            live(1438, width: 120),
        ]
        #expect(HiddenAnyway27.suspects(among: items) == ["com.example.agent"])
    }

    @Test("Two apps' items on top of each other are both named")
    func twoApps() {
        let items = [app("a", 1242), app("b", 1250), live(1306)]
        #expect(HiddenAnyway27.suspects(among: items) == ["a", "b"])
    }

    @Test("Two items of one app, or two live items, on top of each other name nothing")
    func sameOwner() {
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242), app("a", 1250)]).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [live(1242), live(1250)]).isEmpty)
    }

    @Test("An overlap of up to 6 points is a neighbour, more is an item on top")
    func tolerance() {
        // 2 points (measured), and the margin itself.
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242), live(1274)]).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242), live(1270)]).isEmpty)
        // Just past the margin, and one item fully on top of another.
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242), live(1269.5)]) == ["a"])
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242), live(1242)]) == ["a"])
        // The margin holds on either side.
        #expect(HiddenAnyway27.suspects(among: [live(1242), app("a", 1270)]).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [live(1242), app("a", 1269.5)]) == ["a"])
    }

    @Test("Collapsed and squashed items are ignored")
    func narrowItems() {
        // holzBar's collapsed items are 2 points wide; a launching app's item can be 3.
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242, width: 3), live(1242)]).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242), live(1250, width: 2)]).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242, width: 4), live(1242)]).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242, width: 8), live(1242)]) == ["a"])
    }

    @Test("Items that do not share a bar never overlap")
    func otherBar() {
        let below = Item(bundleID: "a", frame: CGRect(x: 1242, y: 1200, width: 34, height: 24))
        #expect(HiddenAnyway27.suspects(among: [below, live(1242)]).isEmpty)
    }

    @Test("No item, one item: nothing to name")
    func emptyAndSingle() {
        #expect(HiddenAnyway27.suspects(among: []).isEmpty)
        #expect(HiddenAnyway27.suspects(among: [app("a", 1242)]).isEmpty)
    }

    @Test("One read alone names none; two in a row name what both saw")
    func confirmation() {
        #expect(HiddenAnyway27.confirmed(current: ["a"], previous: []).isEmpty)
        #expect(HiddenAnyway27.confirmed(current: ["a", "b"], previous: ["a"]) == ["a"])
        #expect(HiddenAnyway27.confirmed(current: [], previous: ["a"]).isEmpty)
    }

    // MARK: Confirmed

    @Test("A confirmed application is kept while a read shows its overlap")
    func confirmedKeptWhileOverlapping() {
        var confirmed = HiddenAnyway27.Confirmed()
        confirmed.update(confirmed: ["a"], suspects: ["a"], drawn: ["a", "b"])
        for _ in 0 ..< 10 {
            #expect(confirmed.update(confirmed: ["a"], suspects: ["a"], drawn: ["a", "b"]).isEmpty)
        }
        #expect(confirmed.bundleIDs == ["a"])
    }

    @Test("A false positive is dropped after clean settled reads in a row")
    func confirmedDroppedWhenClean() {
        var confirmed = HiddenAnyway27.Confirmed()
        confirmed.update(confirmed: ["a"], suspects: ["a"], drawn: ["a"])
        for _ in 1 ..< HiddenAnyway27.Confirmed.dropAfterCleanReads {
            #expect(confirmed.update(confirmed: [], suspects: [], drawn: ["a"]).isEmpty)
            #expect(confirmed.bundleIDs == ["a"])
        }
        #expect(confirmed.update(confirmed: [], suspects: [], drawn: ["a"]) == ["a"])
        #expect(confirmed.bundleIDs.isEmpty)
    }

    @Test("A suspect read in between restarts the count")
    func confirmedCountRestarts() {
        var confirmed = HiddenAnyway27.Confirmed()
        confirmed.update(confirmed: ["a"], suspects: ["a"], drawn: ["a"])
        for _ in 1 ..< HiddenAnyway27.Confirmed.dropAfterCleanReads {
            confirmed.update(confirmed: [], suspects: [], drawn: ["a"])
        }
        // One read finds the overlap again (not yet confirmed twice): the count starts over.
        confirmed.update(confirmed: [], suspects: ["a"], drawn: ["a"])
        for _ in 1 ..< HiddenAnyway27.Confirmed.dropAfterCleanReads {
            confirmed.update(confirmed: [], suspects: [], drawn: ["a"])
        }
        #expect(confirmed.bundleIDs == ["a"])
    }

    @Test("A read that does not draw the application leaves its count alone")
    func confirmedKeptWhenNotDrawn() {
        var confirmed = HiddenAnyway27.Confirmed()
        confirmed.update(confirmed: ["a"], suspects: ["a"], drawn: ["a"])
        for _ in 0 ..< 20 {
            #expect(confirmed.update(confirmed: [], suspects: [], drawn: ["b"]).isEmpty)
        }
        #expect(confirmed.bundleIDs == ["a"])
    }

    @Test("An application that quit is forgotten, and one dropped can be confirmed again")
    func confirmedQuitAndAgain() {
        var confirmed = HiddenAnyway27.Confirmed()
        confirmed.update(confirmed: ["a", "b"], suspects: ["a", "b"], drawn: ["a", "b"])
        confirmed.keepOnly(running: ["b"])
        #expect(confirmed.bundleIDs == ["b"])
        for _ in 0 ..< HiddenAnyway27.Confirmed.dropAfterCleanReads {
            confirmed.update(confirmed: [], suspects: [], drawn: ["b"])
        }
        #expect(confirmed.bundleIDs.isEmpty)
        confirmed.update(confirmed: ["b"], suspects: ["b"], drawn: ["b"])
        #expect(confirmed.bundleIDs == ["b"])
    }
}
