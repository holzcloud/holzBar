import Testing
@testable import HolzBarCore

@Suite("WhatsNewGrouping")
struct WhatsNewGroupingTests {
    private let versions = ["1.1.0", "1.0.2", "1.0.1", "1.0.0", "0.0.13", "0.0.5"]

    @Test("Majors and minors are listed oldest first, with short labels")
    func tabs() {
        let majors = WhatsNewGrouping.majors(of: versions)
        #expect(majors.map(\.label) == ["0.x", "1.x"])
        #expect(majors.last?.minors.map(\.label) == ["1.0", "1.1"])
        #expect(majors.first?.minors.map(\.label) == ["0.0"])
    }

    @Test("The patch versions of a minor stay together, newest first")
    func patches() {
        let majors = WhatsNewGrouping.majors(of: versions)
        #expect(majors.last?.minors.first?.versions == ["1.0.2", "1.0.1", "1.0.0"])
        #expect(majors.first?.minors.first?.versions == ["0.0.13", "0.0.5"])
    }

    @Test("The order of the input does not matter, and numbers compare as numbers")
    func order() {
        let majors = WhatsNewGrouping.majors(of: ["0.0.5", "0.0.13", "0.0.9"])
        #expect(majors.first?.minors.first?.versions == ["0.0.13", "0.0.9", "0.0.5"])
    }

    @Test("Something that is not a version is left out")
    func garbage() {
        #expect(WhatsNewGrouping.majors(of: ["garbage", "", "1.0.0"]).map(\.label) == ["1.x"])
        #expect(WhatsNewGrouping.majors(of: []).isEmpty)
    }

    @Test("A version is found in its main tab and sub tab")
    func location() {
        let majors = WhatsNewGrouping.majors(of: versions)
        let found = WhatsNewGrouping.location(of: "1.0.1", in: majors)
        #expect(found?.major == "1")
        #expect(found?.minor == "1.0")
        #expect(WhatsNewGrouping.location(of: "1.1.0-beta1", in: majors)?.minor == "1.1")
        #expect(WhatsNewGrouping.location(of: "2.0.0", in: majors) == nil)
        #expect(WhatsNewGrouping.location(of: nil, in: majors) == nil)
    }
}
