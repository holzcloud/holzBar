import Testing
@testable import HolzBarCore

@Suite("AppVersion")
struct AppVersionTests {
    private func version(_ string: String) throws -> AppVersion {
        try #require(AppVersion(string))
    }

    @Test("Well-formed versions parse")
    func wellFormedVersionsParse() {
        for string in ["1.0.1", "1.0.0", "1.2", "1", "1.0.1.2", "1.0.1-beta1", "1.0.0-alpha.2", "0.0.5"] {
            #expect(AppVersion(string) != nil, "\(string) should parse")
        }
    }

    @Test("Garbage and overflowing input returns nil")
    func garbageReturnsNil() {
        let garbage = [
            "", " ", "abc", "1.", ".1", "1..0", "-1", "1.0.0-", "v1.0.1", "1.0.1 ", " 1.0.1",
            "1.0.0-beta 1", "1.0.0.0.0", "1.0.0-beta..1", "1.0.0-beta-1", "1,0", "1.0.1\n",
            "99999999999999999999.0.0", "1.0.0-99999999999999999999", "1.0.0-beta99999999999999999999",
            "\u{0661}.0.0",
        ]
        for string in garbage {
            #expect(AppVersion(string) == nil, "\(string.debugDescription) should not parse")
        }
    }

    @Test("Components compare numerically, not textually")
    func componentsCompareNumerically() throws {
        #expect(try version("1.0.9") < version("1.0.10"))
        #expect(try version("1.9.0") < version("1.10.0"))
        #expect(try version("0.9.9") < version("1.0.0"))
        #expect(try version("1.0.1") < version("1.0.2"))
    }

    @Test("A missing component equals zero")
    func missingComponentEqualsZero() throws {
        let short = try version("1.0")
        let long = try version("1.0.0")
        #expect(short == long)
        #expect(short.hashValue == long.hashValue)
        #expect(Set([short, long]).count == 1)
        #expect(try version("1") == version("1.0.0.0"))
        #expect(try version("1.0.0.1") > version("1.0.0"))
    }

    @Test("A prerelease sorts before the same core")
    func prereleaseSortsBeforeCore() throws {
        #expect(try version("1.0.1-beta1") < version("1.0.1"))
        #expect(try version("1.0.1-alpha1") < version("1.0.1-beta1"))
        #expect(try version("1.0.1-beta2") < version("1.0.1-beta10"))
        #expect(try version("1.0.1-beta1") < version("1.0.1-beta2"))
        #expect(try version("1.0.0") < version("1.0.1-beta1"))
        #expect(try version("1.0.1") < version("1.0.2-alpha1"))
        #expect(try version("1.0.1-beta") < version("1.0.1-beta1"))
        #expect(try version("1.0.1-1") < version("1.0.1-alpha"))
        #expect(try version("1.0.1-beta.1") < version("1.0.1-beta.2"))
    }

    @Test("The core drops the prerelease")
    func coreDropsPrerelease() throws {
        let beta = try version("1.0.1-beta3")
        #expect(beta.core == (try version("1.0.1")))
        #expect(beta.isPrerelease)
        #expect(!beta.core.isPrerelease)
        #expect(!(try version("1.0.1")).isPrerelease)
    }

    @Test("The display string keeps the input spelling")
    func displayStringKeepsSpelling() throws {
        let beta = try version("1.0.1-beta1")
        #expect(beta.displayString == "1.0.1-beta1")
        #expect(beta.core.displayString == "1.0.1")
        #expect(try version("1.0").displayString == "1.0")
    }
}
