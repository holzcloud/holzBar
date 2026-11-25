import Testing
@testable import HolzBarCore

@Suite("InputSourceLabel")
struct InputSourceLabelTests {
    @Test("The first language, upper case, two letters")
    func languageCode() {
        #expect(InputSourceLabel.shortCode(languages: ["de"], localizedName: "German") == "DE")
        #expect(InputSourceLabel.shortCode(languages: ["en-US"], localizedName: "U.S.") == "EN")
        #expect(InputSourceLabel.shortCode(languages: ["zh_Hans", "en"], localizedName: "Pinyin") == "ZH")
        #expect(InputSourceLabel.shortCode(languages: ["fr", "de"], localizedName: "French") == "FR")
    }

    @Test("Without a language the first two characters of the name")
    func nameFallback() {
        #expect(InputSourceLabel.shortCode(languages: [], localizedName: "ABC") == "AB")
        #expect(InputSourceLabel.shortCode(languages: [""], localizedName: "Emoji") == "Em")
        #expect(InputSourceLabel.shortCode(languages: [], localizedName: "") == "")
        let long = String(repeating: "x", count: 40)
        #expect(InputSourceLabel.shortCode(languages: [], localizedName: long).count == 2)
    }

    @Test("The code is capped")
    func cap() {
        #expect(InputSourceLabel.maximumCodeLength == 16)
        #expect(InputSourceLabel.shortCode(languages: ["x"], localizedName: "").count <= InputSourceLabel.maximumCodeLength)
    }

    @Test("The source shows only with two or more enabled input sources")
    func minimum() {
        #expect(InputSourceLabel.minimumSources == 2)
        #expect(!InputSourceLabel.shows(enabledCount: 0))
        #expect(!InputSourceLabel.shows(enabledCount: 1))
        #expect(InputSourceLabel.shows(enabledCount: 2))
        #expect(InputSourceLabel.shows(enabledCount: 5))
    }
}
