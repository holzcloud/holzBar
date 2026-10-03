import CoreGraphics
import Testing
@testable import HolzBarCore

@Suite("ColorComponents")
struct ColorComponentsTests {
    @Test("The count must match the colour space")
    func countMatchesColorSpace() {
        #expect(ColorComponents.isValid([0.1, 0.2, 0.3, 1], colorSpaceComponents: 3))
        #expect(ColorComponents.isValid([0.5, 1], colorSpaceComponents: 1))
        #expect(!ColorComponents.isValid([0.1, 0.2, 0.3], colorSpaceComponents: 3))
        #expect(!ColorComponents.isValid([0.1, 0.2, 0.3, 0.4, 1], colorSpaceComponents: 3))
        #expect(!ColorComponents.isValid([], colorSpaceComponents: 3))
        #expect(!ColorComponents.isValid([1], colorSpaceComponents: 0))
    }

    @Test("Components are finite and within 0 to 1")
    func componentsAreFiniteAndInRange() {
        #expect(!ColorComponents.isValid([.nan, 0.2, 0.3, 1], colorSpaceComponents: 3))
        #expect(!ColorComponents.isValid([0.1, .infinity, 0.3, 1], colorSpaceComponents: 3))
        #expect(!ColorComponents.isValid([0.1, 0.2, -0.1, 1], colorSpaceComponents: 3))
        #expect(!ColorComponents.isValid([0.1, 0.2, 0.3, 1.5], colorSpaceComponents: 3))
        #expect(ColorComponents.isValid([0, 0, 0, 0], colorSpaceComponents: 3))
        #expect(ColorComponents.isValid([1, 1, 1, 1], colorSpaceComponents: 3))
    }

    @Test("A stored colour slightly out of range is clamped, not lost")
    func outOfRangeValuesAreClamped() {
        let clamped = ColorComponents.clamped([-0.02, 1.05, 0.5, 1])
        #expect(clamped == [0, 1, 0.5, 1])
        #expect(ColorComponents.isValid(clamped, colorSpaceComponents: 3))
        let notANumber = ColorComponents.clamped([.nan, 0.5, 0.5, 1])
        #expect(!ColorComponents.isValid(notANumber, colorSpaceComponents: 3))
    }
}
