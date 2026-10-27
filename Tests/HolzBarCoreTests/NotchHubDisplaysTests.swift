import Testing
@testable import HolzBarCore

@Suite("NotchHubDisplays")
struct NotchHubDisplaysTests {
    @Test("The stored raw values are 0, 1 and 2, and an unknown one gives nothing")
    func rawValues() {
        #expect(NotchHubDisplays.allCases.map(\.rawValue) == [0, 1, 2])
        #expect(NotchHubDisplays(rawValue: 3) == nil)
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
}
