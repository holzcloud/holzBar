import Testing
@testable import HolzBarCore

@Suite("DDCDisplayMatch")
struct DDCDisplayMatchTests {
    typealias Match = DDCDisplayMatch

    private func display(_ id: UInt32, _ vendor: UInt32, _ model: UInt32, _ serial: UInt32, builtIn: Bool = false) -> Match.Display {
        Match.Display(id: id, vendor: vendor, model: model, serial: serial, isBuiltIn: builtIn)
    }

    private func framebuffer(_ vendor: UInt32, _ product: UInt32, _ serial: UInt32) -> Match.Framebuffer {
        Match.Framebuffer(vendor: vendor, product: product, serial: serial)
    }

    @Test("A display whose numbers equal one framebuffer's is paired with it")
    func unique() {
        let result = Match.match(
            displays: [display(5, 19501, 29689, 810_635_844)],
            framebuffers: [framebuffer(19501, 29689, 810_635_844)]
        )
        #expect(result.pairs == [5: 0])
        #expect(result.indistinguishable.isEmpty)
    }

    @Test("Two different monitors are each paired with their own framebuffer")
    func twoDifferent() {
        let result = Match.match(
            displays: [display(5, 1, 2, 3), display(6, 4, 5, 6)],
            framebuffers: [framebuffer(4, 5, 6), framebuffer(1, 2, 3)]
        )
        #expect(result.pairs == [5: 1, 6: 0])
        #expect(result.indistinguishable.isEmpty)
    }

    @Test("Identical monitors with serial 0 are indistinguishable and never paired")
    func identical() {
        let result = Match.match(
            displays: [display(5, 1, 2, 0), display(6, 1, 2, 0)],
            framebuffers: [framebuffer(1, 2, 0), framebuffer(1, 2, 0)]
        )
        #expect(result.pairs.isEmpty)
        #expect(result.indistinguishable == [5, 6])
    }

    @Test("Two identical displays with one framebuffer are indistinguishable")
    func twoDisplaysOneFramebuffer() {
        let result = Match.match(
            displays: [display(5, 1, 2, 0), display(6, 1, 2, 0)],
            framebuffers: [framebuffer(1, 2, 0)]
        )
        #expect(result.pairs.isEmpty)
        #expect(result.indistinguishable == [5, 6])
    }

    @Test("One display that two framebuffers fit is indistinguishable")
    func oneDisplayTwoFramebuffers() {
        let result = Match.match(
            displays: [display(5, 1, 2, 0)],
            framebuffers: [framebuffer(1, 2, 0), framebuffer(1, 2, 0)]
        )
        #expect(result.pairs.isEmpty)
        #expect(result.indistinguishable == [5])
    }

    @Test("A tie leaves a different monitor beside it paired")
    func tieBesideOther() {
        let result = Match.match(
            displays: [display(5, 1, 2, 0), display(6, 1, 2, 0), display(7, 9, 9, 9)],
            framebuffers: [framebuffer(9, 9, 9), framebuffer(1, 2, 0), framebuffer(1, 2, 0)]
        )
        #expect(result.pairs == [7: 0])
        #expect(result.indistinguishable == [5, 6])
    }

    @Test("A display with another vendor, model or serial is neither paired nor indistinguishable")
    func mismatch() {
        let framebuffers = [framebuffer(1, 2, 3)]
        for other in [display(5, 9, 2, 3), display(5, 1, 9, 3), display(5, 1, 2, 9)] {
            let result = Match.match(displays: [other], framebuffers: framebuffers)
            #expect(result.pairs.isEmpty)
            #expect(result.indistinguishable.isEmpty)
        }
    }

    @Test("A built-in display is never paired, even with equal numbers")
    func builtIn() {
        let result = Match.match(
            displays: [display(1, 1, 2, 3, builtIn: true)],
            framebuffers: [framebuffer(1, 2, 3)]
        )
        #expect(result.pairs.isEmpty)
        #expect(result.indistinguishable.isEmpty)
    }

    @Test("A built-in display does not make an external one with the same numbers a tie")
    func builtInBesideExternal() {
        let result = Match.match(
            displays: [display(1, 1, 2, 3, builtIn: true), display(5, 1, 2, 3)],
            framebuffers: [framebuffer(1, 2, 3)]
        )
        #expect(result.pairs == [5: 0])
        #expect(result.indistinguishable.isEmpty)
    }

    @Test("Without displays or framebuffers nothing is paired")
    func empty() {
        #expect(Match.match(displays: [], framebuffers: [framebuffer(1, 2, 3)]).pairs.isEmpty)
        #expect(Match.match(displays: [display(5, 1, 2, 3)], framebuffers: []).pairs.isEmpty)
    }
}
