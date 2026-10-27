//
//  HolzBarShelfStyleTests.swift
//  holzBar
//

import Testing

@testable import HolzBarCore

@Suite("HolzBarShelfStyle")
struct HolzBarShelfStyleTests {
    @Test("The raw values are the stored ones: attached 0 and floating 1")
    func rawValues() {
        #expect(HolzBarShelfStyle.attached.rawValue == 0)
        #expect(HolzBarShelfStyle.floating.rawValue == 1)
        #expect(HolzBarShelfStyle.allCases == [.attached, .floating])
    }

    @Test("A stored number reads as its style, and any other number as attached")
    func storedNumbers() {
        #expect(HolzBarShelfStyle.stored(0) == .attached)
        #expect(HolzBarShelfStyle.stored(1) == .floating)
        #expect(HolzBarShelfStyle.stored(7) == .attached)
        #expect(HolzBarShelfStyle.stored(-1) == .attached)
        #expect(HolzBarShelfStyle.stored(Int.max) == .attached)
    }
}
