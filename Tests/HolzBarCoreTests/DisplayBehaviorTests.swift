import Foundation
import Testing

@testable import HolzBarCore

@Suite("DisplayBehavior")
struct DisplayBehaviorTests {
    @Test("The raw values stay as stored")
    func rawValues() {
        #expect(DisplayBehavior.allCases.map(\.rawValue) == [0, 1, 2])
    }

    @Test("A stored number that names no behaviour means the standard one")
    func stored() {
        #expect(DisplayBehavior.stored(1) == .showEverything)
        #expect(DisplayBehavior.stored(2) == .collapse)
        #expect(DisplayBehavior.stored(3) == .standard)
        #expect(DisplayBehavior.stored(-1) == .standard)
    }

    @Test("Only showing everything refuses to hide")
    func hiding() {
        #expect(DisplayBehavior.standard.allowsHiding)
        #expect(DisplayBehavior.collapse.allowsHiding)
        #expect(!DisplayBehavior.showEverything.allowsHiding)
    }

    @Test("Collapsing refuses what reveals by itself, as Zen mode does, and keeps the user's own requests")
    func triggers() {
        for trigger in ZenMode.Trigger.allCases {
            #expect(DisplayBehavior.standard.allows(trigger))
            #expect(DisplayBehavior.showEverything.allows(trigger))
            #expect(DisplayBehavior.collapse.allows(trigger) == ZenMode(isManual: true).allows(trigger))
        }
        #expect(!DisplayBehavior.collapse.allows(.hover))
        #expect(!DisplayBehavior.collapse.allows(.clickOnEmptyBar))
        #expect(!DisplayBehavior.collapse.allows(.scroll))
        #expect(DisplayBehavior.collapse.allows(.holzBarIcon))
        #expect(DisplayBehavior.collapse.allows(.sectionHotkey))
    }

    @Test("Moving the pointer between displays shows, hides or leaves the sections")
    func actions() {
        typealias Behavior = DisplayBehavior
        #expect(Behavior.action(from: .standard, to: .showEverything) == .showAll)
        #expect(Behavior.action(from: .collapse, to: .showEverything) == .showAll)
        #expect(Behavior.action(from: .standard, to: .collapse) == .hideAll)
        #expect(Behavior.action(from: .showEverything, to: .collapse) == .hideAll)
        #expect(Behavior.action(from: .showEverything, to: .standard) == .hideAll)
        #expect(Behavior.action(from: .collapse, to: .standard) == .none)
        for behavior in Behavior.allCases {
            #expect(Behavior.action(from: behavior, to: behavior) == .none)
        }
    }
}

@Suite("DisplayBehaviors")
struct DisplayBehaviorsTests {
    private let first = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
    private let second = "5A8C1B34-92E0-4F55-A1D7-0C6B9E3F7A21"

    @Test("A display without a choice behaves as usual")
    func standard() {
        let behaviors = DisplayBehaviors()
        #expect(behaviors.isEmpty)
        #expect(behaviors.behavior(of: first) == .standard)
        #expect(behaviors.behavior(of: nil) == .standard)
    }

    @Test("A choice is kept for its display only, and the standard one forgets it")
    func setAndForget() {
        var behaviors = DisplayBehaviors()
        behaviors.set(.showEverything, for: first)
        behaviors.set(.collapse, for: second)
        #expect(behaviors.behavior(of: first) == .showEverything)
        #expect(behaviors.behavior(of: second) == .collapse)
        #expect(!behaviors.isEmpty)
        behaviors.set(.standard, for: first)
        #expect(behaviors.behavior(of: first) == .standard)
        #expect(behaviors.stored == [second: 2])
        behaviors.set(.standard, for: second)
        #expect(behaviors.isEmpty)
    }

    @Test("The stored form round-trips")
    func roundTrip() {
        var behaviors = DisplayBehaviors()
        behaviors.set(.showEverything, for: first)
        behaviors.set(.collapse, for: second)
        let restored = DisplayBehaviors(stored: behaviors.stored)
        #expect(restored == behaviors)
    }

    @Test("A stored form from outside is cleaned: wrong types, unknown numbers and the standard one are dropped")
    func cleaning() {
        let restored = DisplayBehaviors(stored: [
            first: 1,
            second: "2",
            "a": 7,
            "b": 1.5,
            "c": 0,
            "d": -1,
            "": 1,
            String(repeating: "x", count: 65): 1,
            "e": 2,
        ])
        #expect(restored.stored == [first: 1, "e": 2])
    }

    @Test("A non-finite number is not a behaviour")
    func odd() {
        let restored = DisplayBehaviors(stored: ["a": Double.nan, "b": Double.infinity])
        #expect(restored.isEmpty)
    }

    @Test("The list is bounded, and an existing display can still change")
    func bounded() {
        var behaviors = DisplayBehaviors()
        for index in 0..<(DisplayBehaviors.maximumCount + 5) {
            behaviors.set(.collapse, for: "display-\(index)")
        }
        #expect(behaviors.choices.count == DisplayBehaviors.maximumCount)
        behaviors.set(.showEverything, for: "display-0")
        #expect(behaviors.behavior(of: "display-0") == .showEverything)
        #expect(behaviors.choices.count == DisplayBehaviors.maximumCount)
        let stored = Dictionary(uniqueKeysWithValues: (0..<100).map { ("display-\($0)", 1) })
        #expect(DisplayBehaviors(stored: stored).choices.count == DisplayBehaviors.maximumCount)
    }

    @Test("An identifier that is empty or too long is refused")
    func identifiers() {
        var behaviors = DisplayBehaviors()
        behaviors.set(.collapse, for: "")
        behaviors.set(.collapse, for: String(repeating: "x", count: 65))
        #expect(behaviors.isEmpty)
    }
}
