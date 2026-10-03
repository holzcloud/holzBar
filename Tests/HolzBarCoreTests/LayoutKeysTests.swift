import Testing
@testable import HolzBarCore

@Suite("LayoutKeys")
struct LayoutKeysTests {
    private typealias Key = LayoutKeys.Key
    private typealias Position = LayoutKeys.Position

    @Test("Arrows move the focus")
    func arrowsMoveTheFocus() {
        let right = LayoutKeys.command(keyCode: Key.rightArrow, modifiers: [])
        let down = LayoutKeys.command(keyCode: Key.downArrow, modifiers: [])
        let up = LayoutKeys.command(keyCode: Key.upArrow, modifiers: [])
        #expect(right == .focus(dx: 1, dy: 0))
        let counts = [4, 2, 3]
        #expect(LayoutKeys.focusTarget(from: Position(row: 0, index: 2), command: .focus(dx: 1, dy: 0), rowCounts: counts) == Position(row: 0, index: 3))
        #expect(LayoutKeys.focusTarget(from: Position(row: 0, index: 3), command: .focus(dx: 1, dy: 0), rowCounts: counts) == Position(row: 0, index: 3))
        #expect(LayoutKeys.focusTarget(from: Position(row: 0, index: 0), command: .focus(dx: -1, dy: 0), rowCounts: counts) == Position(row: 0, index: 0))
        // Down from the first section lands on the nearest item of the next one.
        #expect(down == .focus(dx: 0, dy: 1))
        #expect(LayoutKeys.focusTarget(from: Position(row: 0, index: 3), command: .focus(dx: 0, dy: 1), rowCounts: counts) == Position(row: 1, index: 1))
        #expect(up == .focus(dx: 0, dy: -1))
        #expect(LayoutKeys.focusTarget(from: Position(row: 0, index: 1), command: .focus(dx: 0, dy: -1), rowCounts: counts) == Position(row: 0, index: 1))
        // Empty sections are skipped.
        #expect(LayoutKeys.focusTarget(from: Position(row: 0, index: 1), command: .focus(dx: 0, dy: 1), rowCounts: [2, 0, 5]) == Position(row: 2, index: 1))
    }

    @Test("Option-arrows and Command-digits move the item")
    func optionArrowsAndCommandDigitsMoveTheItem() {
        #expect(LayoutKeys.command(keyCode: Key.leftArrow, modifiers: .option) == .moveWithinSection(-1))
        #expect(LayoutKeys.command(keyCode: Key.rightArrow, modifiers: .option) == .moveWithinSection(1))
        #expect(LayoutKeys.command(keyCode: Key.downArrow, modifiers: .option) == .moveToSection(.next))
        #expect(LayoutKeys.command(keyCode: Key.upArrow, modifiers: .option) == .moveToSection(.previous))
        #expect(LayoutKeys.command(keyCode: Key.one, modifiers: .command) == .moveToSection(.visible))
        #expect(LayoutKeys.command(keyCode: Key.two, modifiers: .command) == .moveToSection(.hidden))
        #expect(LayoutKeys.command(keyCode: Key.three, modifiers: .command) == .moveToSection(.alwaysHidden))
        #expect(LayoutKeys.command(keyCode: Key.two, modifiers: []) == nil)
        #expect(LayoutKeys.sectionIndex(for: .next, from: 0, sectionCount: 3) == 1)
        #expect(LayoutKeys.sectionIndex(for: .previous, from: 0, sectionCount: 3) == nil)
        #expect(LayoutKeys.sectionIndex(for: .alwaysHidden, from: 0, sectionCount: 2) == nil)
        #expect(LayoutKeys.sectionIndex(for: .hidden, from: 1, sectionCount: 3) == nil)
    }

    @Test("Moving within a section is refused where macOS orders items")
    func movingWithinASectionIsRefused() {
        #expect(LayoutKeys.command(keyCode: Key.leftArrow, modifiers: .option, itemsKeepOrder: false) == .refused(LayoutKeys.macOSOrdersItems))
        #expect(LayoutKeys.command(keyCode: Key.downArrow, modifiers: .option, itemsKeepOrder: false) == .moveToSection(.next))
    }

    @Test("Return and Space open the item's menu")
    func returnAndSpaceOpenTheMenu() {
        #expect(LayoutKeys.command(keyCode: Key.returnKey, modifiers: []) == .openMenu)
        #expect(LayoutKeys.command(keyCode: Key.space, modifiers: []) == .openMenu)
        #expect(LayoutKeys.command(keyCode: Key.keypadEnter, modifiers: []) == .openMenu)
        #expect(LayoutKeys.command(keyCode: Key.returnKey, modifiers: .command) == nil)
    }
}
