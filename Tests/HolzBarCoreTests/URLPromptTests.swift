import Foundation
import Testing
@testable import HolzBarCore

@Suite("URLPrompt")
struct URLPromptTests {
    @Test("A plain name is shown as it is")
    func plainName() {
        #expect(URLPrompt.displayName("Work") == "Work")
        #expect(URLPrompt.displayName("Büro – Montag") == "Büro – Montag")
    }

    @Test("Line breaks and runs of white space become one space")
    func lineBreaksBecomeOneSpace() {
        #expect(URLPrompt.displayName("x\u{201D}?\n\nholzBar must verify") == "x\u{201D}? holzBar must verify")
        #expect(URLPrompt.displayName("  a\t\tb\r\nc  ") == "a b c")
        #expect(URLPrompt.displayName("a\u{2028}b") == "a b")
    }

    @Test("Control and formatting characters are removed")
    func controlAndFormattingCharactersAreRemoved() {
        // A right-to-left override would turn the rest of the question around.
        #expect(URLPrompt.displayName("Work\u{202E}gnp.exe") == "Workgnp.exe")
        #expect(URLPrompt.displayName("a\u{0007}b\u{200B}c") == "abc")
    }

    @Test("Long names are cut with an ellipsis")
    func longNamesAreCut() {
        let long = String(repeating: "a", count: 200)
        let shown = URLPrompt.displayName(long)
        #expect(shown.count == URLPrompt.maximumNameLength)
        #expect(shown.hasSuffix("\u{2026}"))
        let exact = String(repeating: "b", count: URLPrompt.maximumNameLength)
        #expect(URLPrompt.displayName(exact) == exact)
    }

    @Test("One question at a time")
    func oneQuestionAtATime() {
        var gate = URLPrompt.Gate()
        let now = ContinuousClock.Instant.now
        let began1 = gate.begin(at: now)
        #expect(began1)
        #expect(gate.isAsking)
        let began2 = gate.begin(at: now)
        #expect(!began2)
        gate.end(approved: true, at: now)
        #expect(!gate.isAsking)
        let began3 = gate.begin(at: now)
        #expect(began3)
    }

    @Test("Nothing is asked for a while after a declined question")
    func quietAfterDeclining() {
        var gate = URLPrompt.Gate()
        let start = ContinuousClock.Instant.now
        let began4 = gate.begin(at: start)
        #expect(began4)
        gate.end(approved: false, at: start)
        let began5 = gate.begin(at: start.advanced(by: .seconds(1)))
        #expect(!began5)
        let began6 = gate.begin(at: start.advanced(by: URLPrompt.Gate.quietPeriod - .seconds(1)))
        #expect(!began6)
        let began7 = gate.begin(at: start.advanced(by: URLPrompt.Gate.quietPeriod))
        #expect(began7)
    }
}
