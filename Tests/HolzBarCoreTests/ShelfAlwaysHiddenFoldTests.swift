//
//  ShelfAlwaysHiddenFoldTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("The holzBar Shelf's fold setting")
struct ShelfAlwaysHiddenFoldTests {
    @Test("Folded each time opens closed whatever was left")
    func foldedEachTime() {
        #expect(!ShelfAlwaysHiddenFold.foldedEachTime.opensFold(wasLeftOpen: true))
        #expect(!ShelfAlwaysHiddenFold.foldedEachTime.opensFold(wasLeftOpen: false))
    }

    @Test("Remembered opens as the user left it")
    func remembered() {
        #expect(ShelfAlwaysHiddenFold.remembered.opensFold(wasLeftOpen: true))
        #expect(!ShelfAlwaysHiddenFold.remembered.opensFold(wasLeftOpen: false))
    }

    @Test("A stored number that names no choice means folded each time")
    func stored() {
        #expect(ShelfAlwaysHiddenFold.stored(0) == .foldedEachTime)
        #expect(ShelfAlwaysHiddenFold.stored(1) == .remembered)
        #expect(ShelfAlwaysHiddenFold.stored(2) == .foldedEachTime)
        #expect(ShelfAlwaysHiddenFold.stored(-1) == .foldedEachTime)
    }

    @Test("The raw values stay as stored")
    func rawValues() {
        #expect(ShelfAlwaysHiddenFold.allCases.map(\.rawValue) == [0, 1])
    }
}
