import Testing

@testable import HolzBarCore

@Suite("SecondaryMenuOwnership")
struct SecondaryMenuOwnershipTests {
    @Test("Before macOS 27.2 a plain right-click opens holzBar's menu")
    func beforeTwentySevenTwo() {
        for (major, minor) in [(14, 7), (15, 6), (26, 4), (27, 0), (27, 1)] {
            #expect(!SecondaryMenuOwnership.systemOpensOwnMenu(major: major, minor: minor))
            #expect(SecondaryMenuOwnership.opensHolzBarMenu(optionHeld: false, major: major, minor: minor))
            #expect(SecondaryMenuOwnership.opensHolzBarMenu(optionHeld: true, major: major, minor: minor))
        }
    }

    @Test("From macOS 27.2 a plain right-click stays Apple's")
    func fromTwentySevenTwo() {
        for (major, minor) in [(27, 2), (27, 3), (28, 0), (29, 1)] {
            #expect(SecondaryMenuOwnership.systemOpensOwnMenu(major: major, minor: minor))
            #expect(!SecondaryMenuOwnership.opensHolzBarMenu(optionHeld: false, major: major, minor: minor))
        }
    }

    @Test("From macOS 27.2 ⌥ Option opens holzBar's menu")
    func optionClaimsTheClick() {
        for (major, minor) in [(27, 2), (27, 3), (28, 0)] {
            #expect(SecondaryMenuOwnership.opensHolzBarMenu(optionHeld: true, major: major, minor: minor))
        }
    }

    @Test("The live check answers without crashing")
    func liveCheck() {
        #expect(SecondaryMenuOwnership.opensHolzBarMenu(optionHeld: true))
    }
}
