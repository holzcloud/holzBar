import Testing
@testable import HolzBarCore

@Suite("NotchHubDisplays")
struct NotchHubDisplaysTests {
    @Test("The stored raw values are 0 to 3, and an unknown one gives nothing")
    func rawValues() {
        #expect(NotchHubDisplays.allCases.map(\.rawValue) == [0, 1, 2, 3])
        #expect(NotchHubDisplays.followPointer.rawValue == 3)
        #expect(NotchHubDisplays(rawValue: 4) == nil)
        #expect(NotchHubDisplays(rawValue: -1) == nil)
    }

    @Test("All includes every display")
    func all() {
        for builtIn in [true, false] {
            for notch in [true, false] {
                #expect(NotchHubDisplays.all.includes(isBuiltIn: builtIn, hasNotch: notch))
            }
        }
    }

    @Test("Built-in includes only built-in displays")
    func builtIn() {
        #expect(NotchHubDisplays.builtIn.includes(isBuiltIn: true, hasNotch: false))
        #expect(NotchHubDisplays.builtIn.includes(isBuiltIn: true, hasNotch: true))
        #expect(!NotchHubDisplays.builtIn.includes(isBuiltIn: false, hasNotch: true))
    }

    @Test("Notched includes only displays with a notch")
    func notched() {
        #expect(NotchHubDisplays.notched.includes(isBuiltIn: true, hasNotch: true))
        #expect(NotchHubDisplays.notched.includes(isBuiltIn: false, hasNotch: true))
        #expect(!NotchHubDisplays.notched.includes(isBuiltIn: true, hasNotch: false))
    }

    @Test("D-17: Displays with a notch includes a built-in Dynamic Island display, which has a camera cutout")
    func notchedIncludesDynamicIsland() {
        // Callers pass `safeAreaInsets.top != 0`, which is true for the island as well as the notch.
        #expect(NotchHubDisplays.notched.includes(isBuiltIn: true, hasNotch: true))
        // A display with no cutout at all stays out.
        #expect(!NotchHubDisplays.notched.includes(isBuiltIn: false, hasNotch: false))
        #expect(!NotchHubDisplays.notched.includes(isBuiltIn: true, hasNotch: false))
    }

    @Test("Follow the pointer includes every display")
    func followPointerIncludesAll() {
        for builtIn in [true, false] {
            for notch in [true, false] {
                #expect(NotchHubDisplays.followPointer.includes(isBuiltIn: builtIn, hasNotch: notch))
            }
        }
    }

    @Test("Only Follow the pointer falls back to the key window")
    func fallsBack() {
        #expect(NotchHubDisplays.followPointer.fallsBackToKeyWindow)
        for rule in [NotchHubDisplays.all, .builtIn, .notched] {
            #expect(!rule.fallsBackToKeyWindow)
        }
    }

    @Test("The pointer's display wins when it is included")
    func pointerWins() {
        #expect(NotchHubDisplays.followPointer.preferred(pointer: "B", keyWindow: "A", included: ["A", "B"]) == "B")
        #expect(NotchHubDisplays.all.preferred(pointer: "B", keyWindow: "A", included: ["A", "B"]) == "B")
    }

    @Test("Without a pointer, Follow the pointer takes the key window's display")
    func keyWindowFallback() {
        #expect(NotchHubDisplays.followPointer.preferred(pointer: String?.none, keyWindow: "B", included: ["A", "B"]) == "B")
        // A key window on a display that is not included is no choice.
        #expect(NotchHubDisplays.followPointer.preferred(pointer: String?.none, keyWindow: "C", included: ["A", "B"]) == "A")
    }

    @Test("The other rules never use the key window")
    func keyWindowIgnored() {
        #expect(NotchHubDisplays.builtIn.preferred(pointer: String?.none, keyWindow: "B", included: ["A", "B"]) == "A")
        #expect(NotchHubDisplays.all.preferred(pointer: String?.none, keyWindow: "B", included: ["A", "B"]) == "A")
    }

    @Test("A pointer on an excluded display gives the first included one")
    func pointerExcluded() {
        #expect(NotchHubDisplays.builtIn.preferred(pointer: "C", keyWindow: "A", included: ["A"]) == "A")
        #expect(NotchHubDisplays.notched.preferred(pointer: "C", keyWindow: String?.none, included: ["B"]) == "B")
    }

    @Test("Zero, one and many included displays")
    func countsOfDisplays() {
        for rule in NotchHubDisplays.allCases {
            #expect(rule.preferred(pointer: "A", keyWindow: "A", included: [String]()) == nil)
            #expect(rule.preferred(pointer: String?.none, keyWindow: String?.none, included: ["A"]) == "A")
            #expect(rule.preferred(pointer: String?.none, keyWindow: String?.none, included: ["A", "B", "C"]) == "A")
        }
    }
}
