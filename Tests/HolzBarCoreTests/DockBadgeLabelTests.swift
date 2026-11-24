import Foundation
import Testing
@testable import HolzBarCore

@Suite("DockBadgeLabel")
struct DockBadgeLabelTests {
    private func label(_ text: String) -> DockBadgeLabel {
        DockBadgeLabel(.text(text))
    }

    private func pass(readable: Bool = true, listed: Bool = false, _ answers: [DockLabelAnswer] = []) -> DockLabelGate.Pass {
        DockLabelGate.Pass(dockReadable: readable, listed: listed, answers: answers)
    }

    // MARK: Parse

    @Test("An empty or blank label is no badge")
    func blankIsNone() {
        #expect(label("") == .none)
        #expect(label("  ") == .none)
        #expect(label("\n\u{202F}") == .none)
    }

    @Test("A whole number is a count, and zero is the zero state")
    func numbers() {
        #expect(label("1") == .count(1))
        #expect(label("0") == .count(0))
        #expect(label("0").isZero)
        #expect(label(" 7 ") == .count(7))
        #expect(!label("1").isZero)
    }

    @Test("Grouping separators and a trailing plus are part of a count")
    func grouping() {
        #expect(label("1,234") == .count(1234))
        #expect(label("1.234") == .count(1234))
        #expect(label("1 234") == .count(1234))
        #expect(label("1\u{202F}234") == .count(1234))
        #expect(label("1\u{00A0}234") == .count(1234))
        #expect(label("12,345,678") == .count(12_345_678))
        #expect(label("99+") == .count(99))
        #expect(label("1,000+") == .count(1000))
    }

    @Test("A number that is not a grouped count stays a mark, never a guessed number")
    func notACount() {
        #expect(label("1.5") == .mark("1.5"))
        #expect(label("12,34") == .mark("12,34"))
        #expect(label("1,,234") == .mark("1,,234"))
        #expect(label("+") == .mark("+"))
        #expect(label("99999999999999999999999") == .mark("99999999999999999999999"))
    }

    @Test("A mark is kept as the trimmed text")
    func marks() {
        #expect(label("•") == .mark("•"))
        #expect(label("!") == .mark("!"))
        #expect(label(" New ") == .mark("New"))
        #expect(!label("•").isZero)
    }

    @Test("An answer that is no text is no badge")
    func noTextIsNone() {
        #expect(DockBadgeLabel(.none) == .none)
        #expect(DockBadgeLabel(.unsupported) == .none)
        #expect(DockBadgeLabel(.failed) == .none)
        #expect(DockBadgeLabel.none.isZero)
    }

    // MARK: Bubble and full text

    @Test("The bubble shows nothing for no badge and zero, the number to 99 and 99+ above")
    func bubbleCounts() {
        #expect(DockBadgeLabel.none.bubbleText == nil)
        #expect(DockBadgeLabel.count(0).bubbleText == nil)
        #expect(DockBadgeLabel.count(1).bubbleText == "1")
        #expect(DockBadgeLabel.count(99).bubbleText == "99")
        #expect(DockBadgeLabel.count(100).bubbleText == "99+")
        #expect(DockBadgeLabel.count(142).bubbleText == "99+")
        #expect(DockBadgeLabel.count(Int.max).bubbleText == "99+")
    }

    @Test("A mark shows as it is up to three characters, longer as two characters and an ellipsis")
    func bubbleMarks() {
        #expect(DockBadgeLabel.mark("•").bubbleText == "•")
        #expect(DockBadgeLabel.mark("!").bubbleText == "!")
        #expect(DockBadgeLabel.mark("New").bubbleText == "New")
        #expect(DockBadgeLabel.mark("Hello").bubbleText == "He…")
        #expect(DockBadgeLabel.mark("Neu!").bubbleText == "Ne…")
        // Characters are whole letters: an accent or an emoji is never cut apart.
        #expect(DockBadgeLabel.mark("e\u{0301}e\u{0301}e\u{0301}e\u{0301}").bubbleText == "e\u{0301}e\u{0301}…")
        #expect(DockBadgeLabel.mark("👍🏽👍🏽👍🏽👍🏽").bubbleText == "👍🏽👍🏽…")
    }

    @Test("The full text is the real count or the whole label, and nothing without a badge")
    func fullTexts() {
        #expect(DockBadgeLabel.none.fullText == nil)
        #expect(DockBadgeLabel.count(0).fullText == nil)
        #expect(DockBadgeLabel.count(1).fullText == "1")
        #expect(DockBadgeLabel.count(142).fullText == "142")
        #expect(DockBadgeLabel.mark("Hello").fullText == "Hello")
        #expect(DockBadgeLabel.mark("•").fullText == "•")
    }

    @Test("A bubble shows exactly when the label is not zero")
    func bubbleFollowsIsZero() {
        let labels: [DockBadgeLabel] = [.none, .count(0), .count(5), .count(500), .mark("•"), .mark("Hello")]
        for label in labels {
            #expect((label.bubbleText == nil) == label.isZero)
            #expect((label.fullText == nil) == label.isZero)
        }
    }

    // MARK: Start check

    @Test("An attribute the Dock lists means the interface is there")
    func listedIsLoaded() {
        var check = DockLabelGate.StartCheck()
        #expect(check.record(pass(listed: true, [.unsupported])) == .loaded)
    }

    @Test("Any answer with text or no value means the interface is there")
    func textOrNoValueIsLoaded() {
        var first = DockLabelGate.StartCheck()
        #expect(first.record(pass([.failed, .text("3")])) == .loaded)
        var second = DockLabelGate.StartCheck()
        #expect(second.record(pass([.unsupported, .none])) == .loaded)
    }

    @Test("A Dock where no app has a badge never switches the read off")
    func noBadgeAnywhereStaysLoaded() {
        var check = DockLabelGate.StartCheck()
        for _ in 0..<20 {
            #expect(check.record(pass([.none, .none])) == .loaded)
        }
    }

    @Test("Three passes in a row that say the attribute is unsupported mean the interface is missing")
    func unsupportedThreeTimes() {
        var check = DockLabelGate.StartCheck()
        #expect(check.record(pass([.unsupported, .unsupported])) == nil)
        #expect(check.record(pass([.unsupported])) == nil)
        #expect(check.record(pass([.unsupported])) == .symbolMissing)
    }

    @Test("Three passes in a row that cannot read the Dock, or whose reads all error, mean it is failing")
    func failingThreeTimes() {
        var unreadable = DockLabelGate.StartCheck()
        #expect(unreadable.record(pass(readable: false)) == nil)
        #expect(unreadable.record(pass(readable: false)) == nil)
        #expect(unreadable.record(pass(readable: false)) == .frameworkMissing)
        var errors = DockLabelGate.StartCheck()
        #expect(errors.record(pass([.failed])) == nil)
        #expect(errors.record(pass([.failed, .failed])) == nil)
        #expect(errors.record(pass([.failed])) == .frameworkMissing)
    }

    @Test("A pass with no answer and nothing listed decides nothing and resets nothing")
    func nothingReadDecidesNothing() {
        var check = DockLabelGate.StartCheck()
        #expect(check.record(pass([.unsupported])) == nil)
        #expect(check.record(pass([.unsupported])) == nil)
        #expect(check.record(pass()) == nil)
        #expect(check.record(pass([.unsupported])) == .symbolMissing)
    }

    @Test("A pass with evidence between two failing ones starts the count again")
    func evidenceResets() {
        var check = DockLabelGate.StartCheck()
        #expect(check.record(pass([.unsupported])) == nil)
        #expect(check.record(pass([.unsupported])) == nil)
        #expect(check.record(pass([.none])) == .loaded)
        var again = DockLabelGate.StartCheck()
        #expect(again.record(pass([.unsupported])) == nil)
        #expect(again.record(pass([.unsupported])) == nil)
        #expect(again.record(pass(readable: false)) == nil)
        #expect(again.record(pass([.unsupported])) == nil)
        #expect(again.record(pass([.unsupported])) == nil)
        #expect(again.record(pass([.unsupported])) == .symbolMissing)
    }

    // MARK: Outcome

    @Test("A readable pass with no answer reads nothing")
    func nothingRead() {
        #expect(DockLabelGate.outcome(pass()) == .nothingRead)
        #expect(DockLabelGate.outcome(pass(listed: true)) == .nothingRead)
    }

    @Test("A pass that cannot read the Dock, or whose answers all fail or are unsupported, is a failure")
    func failures() {
        #expect(DockLabelGate.outcome(pass(readable: false)) == .failure)
        #expect(DockLabelGate.outcome(pass(readable: false, [.text("1")])) == .failure)
        #expect(DockLabelGate.outcome(pass([.failed, .failed])) == .failure)
        #expect(DockLabelGate.outcome(pass([.unsupported])) == .failure)
        #expect(DockLabelGate.outcome(pass([.unsupported, .failed])) == .failure)
    }

    @Test("Any answer with text or no value is a success, so a Dock without badges succeeds every time")
    func successes() {
        #expect(DockLabelGate.outcome(pass([.none])) == .success)
        #expect(DockLabelGate.outcome(pass([.text("2")])) == .success)
        #expect(DockLabelGate.outcome(pass([.failed, .none])) == .success)
    }

    // MARK: Gate

    @Test("Three real failures in a row switch the read off for the session")
    func threeFailuresSwitchOff() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        record(pass(readable: false), in: &gate)
        record(pass([.failed]), in: &gate)
        #expect(gate.isAvailable)
        record(pass(readable: false), in: &gate)
        #expect(gate.state == .unavailable(.failedRepeatedly))
    }

    @Test("A pass that read nothing between failures does not reset the count")
    func nothingReadKeepsTheCount() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        record(pass([.failed]), in: &gate)
        record(pass(), in: &gate)
        record(pass([.failed]), in: &gate)
        record(pass(), in: &gate)
        record(pass([.unsupported]), in: &gate)
        #expect(gate.state == .unavailable(.failedRepeatedly))
    }

    @Test("A success resets the count")
    func successResets() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        record(pass([.failed]), in: &gate)
        record(pass([.failed]), in: &gate)
        record(pass([.text("1")]), in: &gate)
        record(pass([.failed]), in: &gate)
        record(pass([.failed]), in: &gate)
        #expect(gate.isAvailable)
    }

    @Test("Twenty passes where no chosen app has a badge leave the gate available")
    func noBadgeLeavesGateAvailable() {
        var gate = PrivateFeatureGate(isEnabled: true, load: .loaded)
        for _ in 0..<20 {
            record(pass([.none, .none]), in: &gate)
        }
        #expect(gate.state == .available)
    }

    private func record(_ pass: DockLabelGate.Pass, in gate: inout PrivateFeatureGate) {
        switch DockLabelGate.outcome(pass) {
        case .success: gate.recordSuccess()
        case .failure: gate.recordFailure()
        case .nothingRead: break
        }
    }

    // MARK: Sum

    @Test("The sum of counts is a count, and marks do not change it")
    func sumOfCounts() {
        #expect(DockBadgeSum.of([.count(3), .count(9)]) == .count(12))
        #expect(DockBadgeSum.of([.count(3), .mark("\u{2022}"), .count(9), .none]) == .count(12))
        #expect(DockBadgeSum.of([.count(142)]).fullText == "142")
        #expect(DockBadgeSum.of([.count(60), .count(60)]).bubbleText == "99+")
    }

    @Test("With no number but a label the sum is the dot")
    func sumOfMarksIsTheDot() {
        #expect(DockBadgeSum.of([.mark("!"), .none]) == .mark("\u{2022}"))
        #expect(DockBadgeSum.of([.mark("new"), .mark("!")]) == .mark("\u{2022}"))
        #expect(DockBadgeSum.of([.count(0), .mark("!")]) == .mark("\u{2022}"))
        #expect(DockBadgeSum.of([.mark("!")]).bubbleText == "\u{2022}")
    }

    @Test("Nothing to show is zero")
    func sumOfNothingIsZero() {
        #expect(DockBadgeSum.of([.none, .count(0)]).isZero)
        #expect(DockBadgeSum.of([.none]).isZero)
        #expect(DockBadgeSum.of([]).isZero)
        #expect(DockBadgeSum.of([.count(0), .count(0)]).bubbleText == nil)
    }

    @Test("A huge sum does not overflow")
    func sumDoesNotOverflow() {
        #expect(DockBadgeSum.of([.count(Int.max), .count(Int.max)]) == .count(Int.max))
    }

    @Test("The menu lists the apps with a badge first, each part in list order")
    func menuOrderPutsBadgesFirst() {
        let labels: [String: DockBadgeLabel] = [
            "com.a.one": .none, "com.a.two": .count(3), "com.a.three": .count(0), "com.a.four": .mark("!"), "com.a.five": .count(1),
        ]
        let members = ["com.a.one", "com.a.two", "com.a.three", "com.a.four", "com.a.five", "com.a.unknown"]
        #expect(
            DockBadgeSum.menuOrder(members, labels: labels)
                == ["com.a.two", "com.a.four", "com.a.five", "com.a.one", "com.a.three", "com.a.unknown"]
        )
        #expect(DockBadgeSum.menuOrder([], labels: labels).isEmpty)
    }
}
