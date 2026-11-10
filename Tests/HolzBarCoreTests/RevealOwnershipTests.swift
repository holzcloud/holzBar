import Testing
@testable import HolzBarCore

@Suite("RevealOwnership")
struct RevealOwnershipTests {
    @Test("Hover owns what hover showed, until another show")
    func hoverOwnsItsOwnShow() {
        var ownership = RevealOwnership()
        let hover = ownership.didShow(.hover, expanded: [.hidden])
        #expect(ownership.hoverOwns)
        #expect(ownership.isCurrent(hover))
        #expect(ownership.mayHide(hover) == [.hidden])

        let hotkey = ownership.didShow(.hotkey, expanded: [.alwaysHidden])
        #expect(!ownership.hoverOwns)
        #expect(!ownership.isCurrent(hover))
        #expect(ownership.mayHide(hover).isEmpty)
        #expect(ownership.mayHide(hotkey) == [.alwaysHidden])
    }

    @Test("A click takes a hover reveal over and keeps what it expanded")
    func clickTakesOver() throws {
        var ownership = RevealOwnership()
        let hover = ownership.didShow(.hover, expanded: [.hidden])
        let takeover = ownership.takeOver(by: .click)
        let click = try #require(takeover)
        #expect(!ownership.hoverOwns)
        #expect(ownership.expanded == [.hidden])
        #expect(ownership.mayHide(hover).isEmpty)
        #expect(ownership.mayHide(click) == [.hidden])
        #expect(click.origin == .click)
    }

    @Test("A click in the bar takes over only a hover reveal")
    func clickTakesOverOnlyHover() throws {
        var ownership = RevealOwnership()
        let hover = ownership.didShow(.hover, expanded: [.hidden])
        let takeover = ownership.takeOverFromHover(by: .click)
        let click = try #require(takeover)
        #expect(!ownership.isCurrent(hover))
        #expect(ownership.isCurrent(click))
        #expect(ownership.mayHide(click) == [.hidden])

        for origin in [RevealOwnership.Origin.peek, .rule, .changeReveal, .hotkey, .displayBehavior] {
            var ownership = RevealOwnership()
            let token = ownership.didShow(origin, expanded: [.hidden])
            #expect(ownership.takeOverFromHover(by: .click) == nil)
            #expect(ownership.isCurrent(token))
            #expect(ownership.mayHide(token) == [.hidden])
        }

        var empty = RevealOwnership()
        #expect(empty.takeOverFromHover(by: .click) == nil)
        #expect(empty.current == nil)
    }

    @Test("Taking over with nothing shown does nothing")
    func takeOverWithNothingShown() {
        var ownership = RevealOwnership()
        #expect(ownership.takeOver(by: .click) == nil)
        #expect(ownership == RevealOwnership())
        #expect(ownership.current == nil)
    }

    @Test("Hiding every section clears the reveal")
    func hidingAllClears() {
        var ownership = RevealOwnership()
        let token = ownership.didShow(.hover, expanded: [.hidden])
        ownership.didHide([.visible, .hidden, .alwaysHidden])
        #expect(ownership.current == nil)
        #expect(ownership.expanded.isEmpty)
        #expect(!ownership.hoverOwns)
        #expect(ownership.mayHide(token).isEmpty)
    }

    @Test("Hiding the always-hidden section alone leaves the hidden section expanded")
    func hidingAlwaysHiddenAlone() {
        var ownership = RevealOwnership()
        let token = ownership.didShow(.click, expanded: [.alwaysHidden, .hidden])
        ownership.didHide([.alwaysHidden])
        #expect(ownership.expanded == [.hidden])
        #expect(ownership.isCurrent(token))
        #expect(ownership.mayHide(token) == [.hidden])
    }

    @Test("The always-hidden rehide collapses the hidden section its show opened")
    func rehideCollapsesWhatTheShowOpened() {
        var ownership = RevealOwnership()
        _ = ownership.didShow(.click, expanded: [.alwaysHidden, .hidden])
        #expect(ownership.sectionsToHide(rehiding: .alwaysHidden) == [.alwaysHidden, .hidden])
    }

    @Test("A hidden section shown before keeps its own rehide")
    func hiddenShownBeforeKeepsItsRehide() {
        var ownership = RevealOwnership()
        _ = ownership.didShow(.hotkey, expanded: [.hidden])
        _ = ownership.didShow(.click, expanded: [.alwaysHidden])
        #expect(ownership.sectionsToHide(rehiding: .alwaysHidden) == [.alwaysHidden])
        #expect(ownership.sectionsToHide(rehiding: .hidden) == [.hidden])
    }

    @Test("A section outside the current reveal hides only itself")
    func sectionOutsideTheReveal() {
        var ownership = RevealOwnership()
        #expect(ownership.sectionsToHide(rehiding: .hidden) == [.hidden])
        _ = ownership.didShow(.hover, expanded: [.hidden])
        #expect(ownership.sectionsToHide(rehiding: .visible) == [.visible])
        #expect(ownership.sectionsToHide(rehiding: .alwaysHidden) == [.alwaysHidden])
    }

    @Test("Only reveals holzBar made by itself are automatic")
    func automaticOrigins() {
        let automatic: [RevealOwnership.Origin] = [.hover, .changeReveal, .drag, .rule, .displayBehavior]
        let user: [RevealOwnership.Origin] = [.click, .hotkey, .shelf, .peek, .other]
        for origin in automatic {
            #expect(origin.isAutomatic)
        }
        for origin in user {
            #expect(!origin.isAutomatic)
        }
        #expect(Set(automatic + user).count == RevealOwnership.Origin.allCases.count)
    }

    @Test("A drop with nothing revealed does nothing")
    func dropWithNothingRevealed() {
        for autoRehide in [false, true] {
            for collapsesAtDrop in [false, true] {
                let action = RevealOwnership.afterDrop(revealed: [], autoRehide: autoRehide, collapsesAtDrop: collapsesAtDrop)
                #expect(action == .nothing)
            }
        }
    }

    @Test("On macOS 27 what the drag revealed collapses at the drop")
    func dropCollapsesOn27() {
        let revealed: Set<RevealOwnership.Section> = [.visible, .hidden, .alwaysHidden]
        for autoRehide in [false, true] {
            let action = RevealOwnership.afterDrop(revealed: revealed, autoRehide: autoRehide, collapsesAtDrop: true)
            #expect(action == .collapse(revealed))
        }
    }

    @Test("Without automatic rehide what the drag revealed collapses at the drop")
    func dropCollapsesWithoutAutoRehide() {
        let action = RevealOwnership.afterDrop(revealed: [.hidden], autoRehide: false, collapsesAtDrop: false)
        #expect(action == .collapse([.hidden]))
    }

    @Test("With automatic rehide what the drag revealed goes to the rehide")
    func dropHandsOverToTheRehide() {
        let revealed: Set<RevealOwnership.Section> = [.visible, .hidden]
        let action = RevealOwnership.afterDrop(revealed: revealed, autoRehide: true, collapsesAtDrop: false)
        #expect(action == .rehide(revealed))
    }

    @Test("A peek token stays current until another origin shows or takes over")
    func peekStaysCurrent() throws {
        var ownership = RevealOwnership()
        let peek = ownership.didShow(.peek, expanded: [.hidden])
        #expect(ownership.isCurrent(peek))
        #expect(ownership.mayHide(peek) == [.hidden])

        ownership.takeOver(by: .click)
        #expect(!ownership.isCurrent(peek))
        #expect(ownership.mayHide(peek).isEmpty)

        let second = ownership.didShow(.peek, expanded: [.hidden])
        ownership.didShow(.hover, expanded: [.alwaysHidden])
        #expect(!ownership.isCurrent(second))
    }

    @Test("A peek on a section already shown takes it over and keeps what it expanded")
    func peekTakesOverAShownSection() throws {
        var ownership = RevealOwnership()
        _ = ownership.didShow(.hover, expanded: [.alwaysHidden, .hidden])
        let takeover = ownership.takeOver(by: .peek)
        let peek = try #require(takeover)
        #expect(ownership.isCurrent(peek))
        #expect(!ownership.hoverOwns)
        #expect(ownership.mayHide(peek) == [.alwaysHidden, .hidden])
    }

    @Test("A change reveal hides nothing once the user took it over or another show happened")
    func changeRevealBecomesStale() {
        for userOrigin in [RevealOwnership.Origin.click, .hotkey] {
            var ownership = RevealOwnership()
            let change = ownership.didShow(.changeReveal, expanded: [.alwaysHidden, .hidden])
            #expect(ownership.mayHide(change) == [.alwaysHidden, .hidden])
            ownership.takeOver(by: userOrigin)
            #expect(ownership.mayHide(change).isEmpty)
        }
        var ownership = RevealOwnership()
        let change = ownership.didShow(.changeReveal, expanded: [.hidden])
        ownership.didHide([.visible, .hidden, .alwaysHidden])
        ownership.didShow(.hover, expanded: [.hidden])
        #expect(ownership.mayHide(change).isEmpty)
    }

    @Test("Every show starts a new token")
    func everyShowIsNew() {
        var ownership = RevealOwnership()
        let first = ownership.didShow(.hover, expanded: [.hidden])
        ownership.didHide([.hidden])
        let second = ownership.didShow(.hover, expanded: [.hidden])
        #expect(first != second)
        #expect(ownership.mayHide(first).isEmpty)
        #expect(ownership.mayHide(second) == [.hidden])
    }
}
