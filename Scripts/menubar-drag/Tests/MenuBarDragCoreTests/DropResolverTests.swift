//
//  DropResolverTests.swift
//  holzBar
//

import CoreGraphics
import Foundation
import Testing

@testable import MenuBarDragCore

@Suite("DropResolver")
struct DropResolverTests {
    private let before27 = Fixture.bar()
    private let on27 = Fixture.bar(generation: .macOS27)
    private let dragged = Fixture.item("com.example.b", 0, .app, x: 420)

    private func point(_ x: CGFloat, y: CGFloat = 12) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    private func target(_ x: CGFloat, y: CGFloat = 12, in bar: BarSnapshot? = nil, zones: [DropZone] = []) -> DropTarget? {
        DropResolver.target(forDropAt: point(x, y: y), draggedID: Fixture.b, in: bar ?? before27, zones: zones)
    }

    private func rendered(_ intent: DropIntent, generation: Generation = .before27) -> String {
        intent.rendered(generation: generation, shownID: { $0 }, shownOwner: { $0 })
    }

    @Test("the right half of an item gives rightOf, the left half leftOf")
    func halves() {
        #expect(target(480) == .rightOf("com.example.c#0"))
        #expect(target(465) == .leftOf("com.example.c#0"))
    }

    @Test("a gap gives the item on its right, past the last item the last one")
    func gaps() {
        #expect(target(455) == .leftOf("com.example.c#0"))
        #expect(target(1450) == .rightOf("com.apple.controlcenter#0"))
        #expect(target(10) == .leftOf("com.holzcloud.holzBar#2"))
    }

    @Test("the dragged item is never its own target")
    func notItself() {
        #expect(target(435) == .leftOf("com.example.c#0"))
    }

    @Test("a release below the bar has no target and is refused")
    func belowTheBar() {
        let none = target(480, y: 30)
        #expect(none == nil)
        let intent = DropResolver.intent(for: none, dragged: dragged, in: before27, currentSection: nil)
        #expect(intent == .refused(reason: "dropped outside the bar"))
        #expect(intent.isRefused)
        #expect(rendered(intent) == "refused: dropped outside the bar")
    }

    @Test("a zone that contains the release point wins over any item")
    func zoneWins() {
        let zone = DropZone(section: .alwaysHidden, frame: CGRect(x: 270, y: 1, width: 76, height: 22))
        #expect(target(290, zones: [zone]) == .section(.alwaysHidden))
        #expect(target(290) == .leftOf("com.example.a#0") || target(290) == .rightOf("com.example.a#0"))
    }

    @Test("holzBar's icon is the hidden section on macOS 27 only")
    func iconOn27() {
        #expect(target(510, in: on27) == .section(.hidden))
        #expect(target(520, in: before27) == .rightOf("com.holzcloud.holzBar#0"))
        #expect(target(505, in: before27) == .leftOf("com.holzcloud.holzBar#0"))
    }

    @Test("before macOS 27 a neighbour renders LayoutBarMoves.move, a zone LayoutBarMoves.setSection")
    func rendersBefore27() {
        let right = DropResolver.intent(
            for: .rightOf("com.example.c#0"), dragged: dragged, in: before27, currentSection: .visible
        )
        #expect(rendered(right) == "LayoutBarMoves.move(com.example.b#0, to: .rightOfItem(com.example.c#0))")
        let left = DropResolver.intent(
            for: .leftOf("com.example.c#0"), dragged: dragged, in: before27, currentSection: .visible
        )
        #expect(rendered(left) == "LayoutBarMoves.move(com.example.b#0, to: .leftOfItem(com.example.c#0))")
        let zone = DropResolver.intent(for: .section(.hidden), dragged: dragged, in: before27, currentSection: .visible)
        #expect(rendered(zone) == "LayoutBarMoves.setSection(of: com.example.b#0, to: .hidden)")
    }

    @Test("on macOS 27 a section target renders setSection and the Concealer27 call")
    func rendersSectionOn27() {
        let intent = DropResolver.intent(for: .section(.hidden), dragged: dragged, in: on27, currentSection: nil)
        #expect(
            rendered(intent, generation: .macOS27)
                == "LayoutBarMoves.setSection(of: com.example.b#0, to: .hidden) -> Concealer27.setSection(.hidden, for: com.example.b)"
        )
        let always = DropResolver.intent(for: .section(.alwaysHidden), dragged: dragged, in: on27, currentSection: nil)
        #expect(rendered(always, generation: .macOS27).hasSuffix("Concealer27.setSection(.alwaysHidden, for: com.example.b)"))
    }

    @Test("on macOS 27 a neighbour target changes nothing, as in the Layout pane")
    func neighbourOn27() {
        let intent = DropResolver.intent(
            for: .rightOf("com.example.c#0"), dragged: dragged, in: on27, currentSection: nil
        )
        #expect(intent == .macOSOrders(item: "com.example.b#0"))
        #expect(rendered(intent, generation: .macOS27) == "none: macOS 27 orders items within a section")
    }

    @Test("on macOS 27 a neighbour target of an item saved as hidden sets the visible section")
    func neighbourOfHiddenOn27() {
        for saved in [BarSection.hidden, .alwaysHidden] {
            let intent = DropResolver.intent(
                for: .leftOf("com.example.c#0"), dragged: dragged, in: on27, currentSection: saved
            )
            #expect(intent == .setSection(item: "com.example.b#0", owner: "com.example.b", section: .visible))
        }
        let visible = DropResolver.intent(
            for: .leftOf("com.example.c#0"), dragged: dragged, in: on27, currentSection: .visible
        )
        #expect(visible == .macOSOrders(item: "com.example.b#0"))
    }

    @Test("a system item and holzBar's own item are refused")
    func onlyAppItems() {
        let system = Fixture.item("com.apple.controlcenter", 0, .system, x: 1300, width: 80)
        let own = Fixture.item("com.holzcloud.holzBar", 0, .holzBarIcon, x: 500, width: 26)
        for item in [system, own] {
            let intent = DropResolver.intent(for: .leftOf("com.example.c#0"), dragged: item, in: before27, currentSection: nil)
            #expect(intent == .refused(reason: "only app items are moved"))
            #expect(rendered(intent) == "refused: only app items are moved")
        }
    }

    @Test("landed compares the final order for leftOf and rightOf")
    func landedNeighbour() {
        #expect(DropResolver.landed(.rightOf("com.example.c#0"), draggedID: Fixture.b, in: Fixture.swapped) == true)
        #expect(DropResolver.landed(.leftOf("com.example.c#0"), draggedID: Fixture.b, in: Fixture.swapped) == false)
        #expect(DropResolver.landed(.leftOf("com.example.c#0"), draggedID: Fixture.b, in: Fixture.before) == true)
        #expect(DropResolver.landed(.rightOf("com.example.c#0"), draggedID: Fixture.b, in: Fixture.before) == false)
        #expect(DropResolver.landed(.leftOf("com.example.c#0"), draggedID: "com.example.gone#0", in: Fixture.before) == false)
        #expect(DropResolver.landed(.leftOf("com.example.gone#0"), draggedID: Fixture.b, in: Fixture.before) == false)
    }

    @Test("landed compares the positional section for a section target and is nil on macOS 27")
    func landedSection() {
        #expect(DropResolver.landed(.section(.hidden), draggedID: Fixture.b, in: Fixture.bInHidden) == true)
        #expect(DropResolver.landed(.section(.visible), draggedID: Fixture.b, in: Fixture.bInHidden) == false)
        #expect(DropResolver.landed(.section(.visible), draggedID: Fixture.b, in: Fixture.before) == true)
        #expect(DropResolver.landed(.section(.hidden), draggedID: Fixture.b, in: on27) == nil)
        #expect(DropResolver.landed(.section(.hidden), draggedID: "com.example.gone#0", in: Fixture.before) == false)
    }

    @Test("rendering applies the redaction closures to every id and to the owner")
    func redaction() {
        let intent = DropResolver.intent(for: .section(.hidden), dragged: dragged, in: on27, currentSection: nil)
        let text = intent.rendered(
            generation: .macOS27,
            shownID: { $0.replacingOccurrences(of: "com.example.b", with: "app1") },
            shownOwner: { $0 == "com.example.b" ? "app1" : $0 }
        )
        #expect(text == "LayoutBarMoves.setSection(of: app1#0, to: .hidden) -> Concealer27.setSection(.hidden, for: app1)")
        let move = DropResolver.intent(for: .leftOf("com.example.c#0"), dragged: dragged, in: before27, currentSection: nil)
        let shown = move.rendered(
            generation: .before27,
            shownID: { $0.replacingOccurrences(of: "com.example.", with: "app-") },
            shownOwner: { $0 }
        )
        #expect(shown == "LayoutBarMoves.move(app-b#0, to: .leftOfItem(app-c#0))")
    }
}
