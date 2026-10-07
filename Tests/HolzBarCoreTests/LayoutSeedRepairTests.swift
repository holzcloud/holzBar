import Testing
@testable import HolzBarCore

@Suite("LayoutSeedRepair")
struct LayoutSeedRepairTests {
    @Test("A seeded flag over an empty layout on macOS before 27 is cleared")
    func clearsTheBeta1Artifact() {
        #expect(LayoutSeedRepair.shouldClearSeededFlag(isMacOS27: false, seeded: true, layoutIsEmpty: true))
    }

    @Test("Nothing is cleared on macOS 27")
    func keepsTheFlagOnMacOS27() {
        #expect(!LayoutSeedRepair.shouldClearSeededFlag(isMacOS27: true, seeded: true, layoutIsEmpty: true))
    }

    @Test("Nothing is cleared when the flag is not set")
    func keepsAnUnsetFlag() {
        #expect(!LayoutSeedRepair.shouldClearSeededFlag(isMacOS27: false, seeded: false, layoutIsEmpty: true))
    }

    @Test("Nothing is cleared when the layout holds an entry")
    func keepsTheFlagOverARealLayout() {
        #expect(!LayoutSeedRepair.shouldClearSeededFlag(isMacOS27: false, seeded: true, layoutIsEmpty: false))
    }
}
