import Testing
@testable import HolzBarMacOS27Core

@Suite("ConcealmentPlanner27")
struct ConcealmentPlanner27Tests {
    let layout: [String: MacOS27Section] = ["visible.app": .visible, "hidden.app": .hidden, "always.app": .alwaysHidden]

    @Test("Everything hidden conceals hidden and always-hidden apps")
    func allHidden() {
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .allHidden) == [["hidden.app", "always.app"]])
    }

    @Test("Revealing the hidden section conceals only always-hidden apps")
    func hiddenRevealed() {
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .hiddenRevealed) == [["always.app"]])
    }

    @Test("Revealing everything needs no assertion")
    func allRevealed() {
        #expect(ConcealmentPlanner27.concealedSets(layout: layout, state: .allRevealed).isEmpty)
    }

    @Test("Nothing to conceal needs no assertion")
    func nothingToConceal() {
        #expect(ConcealmentPlanner27.concealedSets(layout: ["a": .visible], state: .allHidden).isEmpty)
        #expect(ConcealmentPlanner27.concealedSets(layout: ["a": .hidden], state: .hiddenRevealed).isEmpty)
    }

    @Test("The allowlist is every running app except the concealed ones, sorted")
    func allowlist() {
        #expect(ConcealmentPlanner27.allowlist(concealing: ["b"], running: ["z", "a", "b"]) == ["a", "z"])
    }

    @Test("Live assertions conceal only what all of them conceal")
    func effectivelyConcealed() {
        #expect(ConcealmentPlanner27.effectivelyConcealed(sets: [["b", "c"], ["c"]]) == ["c"])
        #expect(ConcealmentPlanner27.effectivelyConcealed(sets: []).isEmpty)
    }

    @Test("A hidden system item is concealed while everything is hidden, and only then")
    func systemItemInTheStates() {
        let withClock = layout.merging(SystemItems27.layoutEntries(for: [.clock])) { _, system in system }
        #expect(ConcealmentPlanner27.concealedSets(layout: withClock, state: .allHidden) == [["hidden.app", "always.app", "system-item:2"]])
        #expect(ConcealmentPlanner27.concealedSets(layout: withClock, state: .hiddenRevealed) == [["always.app"]])
        #expect(ConcealmentPlanner27.concealedSets(layout: withClock, state: .allRevealed).isEmpty)
    }

    @Test("A layout with only a system item still makes one assertion")
    func onlyASystemItem() {
        let only = SystemItems27.layoutEntries(for: [.battery])
        #expect(ConcealmentPlanner27.concealedSets(layout: only, state: .allHidden) == [["system-item:0"]])
    }

    @Test("The system items an assertion keeps are every number except the hidden ones")
    func allowedSystemItems() {
        let concealed: Set<String> = ["system-item:2", "other.app"]
        #expect(ConcealmentPlanner27.allowedSystemItems(concealing: concealed) == SystemItems27.allowedNumbers(concealing: concealed))
        #expect(!ConcealmentPlanner27.allowedSystemItems(concealing: concealed).contains(2))
        #expect(ConcealmentPlanner27.allowedSystemItems(concealing: []).count == 128)
    }

    /// One combination of the inputs of ``RevealState27/decide``.
    struct RevealCase: CustomTestStringConvertible, Sendable {
        let layoutPaneOpen: Bool
        let hiddenShownOnBar: Bool
        let alwaysHiddenShownOnBar: Bool
        let alwaysHiddenEnabled: Bool
        let expected: RevealState27

        var testDescription: String {
            "pane \(layoutPaneOpen) hidden \(hiddenShownOnBar) always \(alwaysHiddenShownOnBar) enabled \(alwaysHiddenEnabled)"
        }
    }

    /// Every combination of the four inputs, with the state each one must give.
    static let revealCases: [RevealCase] = [false, true].flatMap { pane in
        [false, true].flatMap { hidden in
            [false, true].flatMap { always in
                [false, true].map { enabled in
                    let expected: RevealState27 = if pane {
                        .allRevealed
                    } else if always && enabled {
                        .allRevealed
                    } else if hidden {
                        .hiddenRevealed
                    } else {
                        .allHidden
                    }
                    return RevealCase(
                        layoutPaneOpen: pane,
                        hiddenShownOnBar: hidden,
                        alwaysHiddenShownOnBar: always,
                        alwaysHiddenEnabled: enabled,
                        expected: expected
                    )
                }
            }
        }
    }

    @Test("The reveal state follows the sections' states on the bar", arguments: revealCases)
    func revealStateDecides(_ revealCase: RevealCase) {
        let state = RevealState27.decide(
            layoutPaneOpen: revealCase.layoutPaneOpen,
            hiddenShownOnBar: revealCase.hiddenShownOnBar,
            alwaysHiddenShownOnBar: revealCase.alwaysHiddenShownOnBar,
            alwaysHiddenEnabled: revealCase.alwaysHiddenEnabled
        )
        #expect(state == revealCase.expected)
    }

    @Test("The table covers all 16 combinations")
    func revealCasesCoverEveryCombination() {
        #expect(Self.revealCases.count == 16)
        let distinct = Set(Self.revealCases.map { [$0.layoutPaneOpen, $0.hiddenShownOnBar, $0.alwaysHiddenShownOnBar, $0.alwaysHiddenEnabled] })
        #expect(distinct.count == 16)
    }

    @Test("Menu Bar Layout reveals everything, whatever the sections say")
    func layoutPaneRevealsEverything() {
        #expect(RevealState27.decide(layoutPaneOpen: true, hiddenShownOnBar: false, alwaysHiddenShownOnBar: false, alwaysHiddenEnabled: false) == .allRevealed)
    }

    @Test("While the Shelf shows the items their control items hide the sections, so the bar stays concealed")
    func shelfKeepsTheBarConcealed() {
        #expect(RevealState27.decide(layoutPaneOpen: false, hiddenShownOnBar: false, alwaysHiddenShownOnBar: false, alwaysHiddenEnabled: true) == .allHidden)
    }

    @Test("An always-hidden section shown but switched off falls through to the hidden rule")
    func disabledAlwaysHiddenFallsThrough() {
        #expect(RevealState27.decide(layoutPaneOpen: false, hiddenShownOnBar: true, alwaysHiddenShownOnBar: true, alwaysHiddenEnabled: false) == .hiddenRevealed)
        #expect(RevealState27.decide(layoutPaneOpen: false, hiddenShownOnBar: false, alwaysHiddenShownOnBar: true, alwaysHiddenEnabled: false) == .allHidden)
    }
}
