//
//  OverlayGeometryTests.swift
//  holzBar
//

import CoreGraphics
import Testing

@testable import MenuBarDragCore

@Suite("OverlayGeometry")
struct OverlayGeometryTests {
    private let primary = Fixture.bar()

    /// A display left of and above the primary one (1512 by 982), as System Settings can arrange it.
    private func secondary(extra: [BarItem] = []) -> BarSnapshot {
        BarSnapshot(
            generation: .before27,
            displayID: 2,
            displayBounds: CGRect(x: -1920, y: -1080, width: 1920, height: 1080),
            barMaxY: -1056,
            items: [
                BarItem(
                    id: "com.example.b#0",
                    owner: "com.example.b",
                    kind: .app,
                    frame: CGRect(x: -500, y: -1080, width: 30, height: 24)
                ),
            ] + extra
        )
    }

    private func handle(_ id: String, in layout: OverlayLayout) -> OverlayLayout.Handle? {
        layout.handles.first { $0.id == id }
    }

    @Test("on the primary display the panel covers the bar and handles keep their rects")
    func primaryDisplay() {
        let layout = OverlayLayout.make(snapshot: primary, primaryDisplayHeight: 982, notchSpan: nil)
        #expect(layout.panelFrame == CGRect(x: 0, y: 958, width: 1512, height: 24))
        #expect(handle("com.example.b#0", in: layout)?.rect == CGRect(x: 420, y: 0, width: 30, height: 24))
    }

    @Test("on a display left of and above the primary one the conversion follows the arrangement")
    func secondaryDisplay() {
        let layout = OverlayLayout.make(snapshot: secondary(), primaryDisplayHeight: 982, notchSpan: nil)
        #expect(layout.panelFrame == CGRect(x: -1920, y: 2038, width: 1920, height: 24))
        #expect(handle("com.example.b#0", in: layout)?.rect == CGRect(x: 1420, y: 0, width: 30, height: 24))
    }

    @Test("handles exist only for counted items and keep their kinds")
    func handlesForCountedItems() {
        let thin = Fixture.item("com.example.thin", 0, .app, x: 600, width: 4)
        let layout = OverlayLayout.make(
            snapshot: Fixture.bar(extra: [thin]),
            primaryDisplayHeight: 982,
            notchSpan: nil
        )
        #expect(layout.handles.count == 7)
        #expect(handle("com.example.thin#0", in: layout) == nil)
        #expect(handle("com.example.b#0", in: layout)?.kind == .app)
        #expect(handle("com.holzcloud.holzBar#0", in: layout)?.kind == .holzBarIcon)
        #expect(handle("com.apple.controlcenter#0", in: layout)?.kind == .system)
    }

    @Test("the Hidden zone ends 8 points left of the leftmost item, the Always Hidden zone sits left of it")
    func zonePlacement() {
        let layout = OverlayLayout.make(snapshot: primary, primaryDisplayHeight: 982, notchSpan: nil)
        #expect(layout.zones.map(\.section) == [.hidden, .alwaysHidden])
        #expect(layout.zones[0].dropZone == DropZone(section: .hidden, frame: CGRect(x: 196, y: 2, width: 76, height: 20)))
        #expect(
            layout.zones[1].dropZone == DropZone(section: .alwaysHidden, frame: CGRect(x: 112, y: 2, width: 76, height: 20))
        )
        #expect(layout.zones[0].rect == CGRect(x: 196, y: 2, width: 76, height: 20))
    }

    @Test("a zone that would start left of the display is left out")
    func zoneLeftOfTheDisplay() {
        let near = Fixture.bar(extra: [Fixture.item("com.example.far", 0, .app, x: 100)])
        // The Hidden zone is 16...92, the Always Hidden zone would start at -68.
        let some = OverlayLayout.make(snapshot: near, primaryDisplayHeight: 982, notchSpan: nil)
        #expect(some.zones.map(\.section) == [.hidden])
        let nearer = Fixture.bar(extra: [Fixture.item("com.example.far", 0, .app, x: 50)])
        let none = OverlayLayout.make(snapshot: nearer, primaryDisplayHeight: 982, notchSpan: nil)
        #expect(none.zones.isEmpty)
    }

    @Test("both zones move left of the notch")
    func notch() {
        let bar = BarSnapshot(
            generation: .macOS27,
            displayID: 1,
            displayBounds: Fixture.bounds,
            barMaxY: 24,
            items: [Fixture.item("com.example.a", 0, .app, x: 830)]
        )
        let layout = OverlayLayout.make(snapshot: bar, primaryDisplayHeight: 982, notchSpan: 690...822)
        #expect(layout.zones.map(\.section) == [.hidden, .alwaysHidden])
        #expect(layout.zones[0].dropZone.frame.maxX == 682)
        #expect(layout.zones[1].dropZone.frame.maxX == 598)
        for zone in layout.zones {
            #expect(zone.dropZone.frame.maxX <= 690 || zone.dropZone.frame.minX >= 822)
        }
    }

    @Test("cgPoint(fromPanel:) undoes the panel conversion")
    func pointConversion() {
        let layout = OverlayLayout.make(snapshot: secondary(), primaryDisplayHeight: 982, notchSpan: nil)
        let rect = layout.panelRect(fromCG: CGRect(x: -500, y: -1080, width: 30, height: 24))
        #expect(rect == CGRect(x: 1420, y: 0, width: 30, height: 24))
        #expect(layout.cgPoint(fromPanel: CGPoint(x: 1435, y: 12)) == CGPoint(x: -485, y: -1068))
        #expect(layout.cgPoint(fromPanel: CGPoint(x: 1420, y: 24)) == CGPoint(x: -500, y: -1080))
    }

    @Test("equal snapshots show no shift")
    func equalSnapshots() {
        let diff = TrackDiff.compare(shown: Fixture.before, fresh: Fixture.before)
        #expect(diff.shifted == 0)
        #expect(diff.maxShift == 0)
    }

    @Test("an item that moved by more than 2 points is shifted and feeds the largest shift")
    func movedItem() {
        let moved = Fixture.bar(bX: 432.5)
        let diff = TrackDiff.compare(shown: Fixture.before, fresh: moved)
        #expect(diff.shifted == 1)
        #expect(diff.maxShift == 12.5)
        let nudged = Fixture.bar(bX: 421.5)
        #expect(TrackDiff.compare(shown: Fixture.before, fresh: nudged).shifted == 0)
    }

    @Test("an item in only one snapshot is shifted and leaves the largest shift alone")
    func appearedItem() {
        let more = Fixture.bar(extra: [Fixture.item("com.example.new", 0, .app, x: 700)])
        let diff = TrackDiff.compare(shown: Fixture.before, fresh: more)
        #expect(diff.shifted == 1)
        #expect(diff.maxShift == 0)
        let reverse = TrackDiff.compare(shown: more, fresh: Fixture.before)
        #expect(reverse.shifted == 1)
        #expect(reverse.maxShift == 0)
    }
}
