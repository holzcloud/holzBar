import Testing
@testable import HolzBarCore

@Suite("BorderPattern")
struct BorderPatternTests {
    @Test("Solid has no dashes; dashed and dotted scale with the width")
    func patternsScaleWithWidth() {
        #expect(BorderPattern.dashes(for: .solid, width: 2) == nil)
        #expect(BorderPattern.dashes(for: .dashed, width: 1) == [6, 3])
        #expect(BorderPattern.dashes(for: .dashed, width: 3) == [18, 9])
        #expect(BorderPattern.dashes(for: .dotted, width: 2) == [0, 4])
        #expect(BorderPattern.usesRoundCaps(.dotted))
        #expect(!BorderPattern.usesRoundCaps(.dashed))
        #expect(!BorderPattern.usesRoundCaps(.solid))
    }

    @Test("Stored styles never change")
    func storedStylesNeverChange() {
        #expect(BorderStyle.allCases.map(\.rawValue) == [0, 1, 2])
    }
}
