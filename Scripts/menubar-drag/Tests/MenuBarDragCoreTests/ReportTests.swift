//
//  ReportTests.swift
//  holzBar
//

import CoreGraphics
import Testing

@testable import MenuBarDragCore

@Suite("Report")
struct ReportTests {
    private func result(
        moved: Bool = true,
        scope: SettleResult.Scope = .reorder,
        settleMs: Int? = 100,
        bounces: Int = 0,
        vanished: Bool = false,
        persisted: Bool? = true
    ) -> SettleResult {
        SettleResult(
            moved: moved,
            scope: scope,
            settleMs: settleMs,
            bounces: bounces,
            vanished: vanished,
            persisted: persisted,
            fromIndex: 3,
            toIndex: 4,
            fromSection: nil,
            toSection: nil
        )
    }

    /// The value of `key` in a report line, or nil.
    private func value(_ key: String, in line: ReportLine) -> String? {
        line.text.split(separator: " ").first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    @Test("a disabled Redactor changes nothing, an enabled one numbers non-Apple apps and keeps Apple and holzBar")
    func redactor() {
        var off = Redactor(enabled: false)
        #expect(off.shownID("com.example.one#0") == "com.example.one#0")

        var on = Redactor(enabled: true)
        #expect(on.shownID("com.example.one#0") == "app1#0")
        #expect(on.shownID("com.example.two#1") == "app2#1")
        #expect(on.shownID("com.example.one#2") == "app1#2")
        #expect(on.shownID("com.apple.controlcenter#0") == "com.apple.controlcenter#0")
        #expect(on.shownID("com.holzcloud.holzBar#2") == "com.holzcloud.holzBar#2")
        #expect(on.shownOwner("com.example.two") == "app2")
    }

    @Test("three drags with settle 100, 300 and none give the median, the maximum and the counts")
    func drags() {
        var summary = RunSummary()
        summary.add(result(settleMs: 100), landed: nil, refused: false)
        summary.add(
            result(scope: .section, settleMs: 300, bounces: 2, vanished: true, persisted: false),
            landed: nil,
            refused: false
        )
        summary.add(result(moved: false, scope: .none, settleMs: nil), landed: nil, refused: false)
        let line = summary.line(mechanism: "a1", generation: .before27)
        #expect(value("mech", in: line) == "a1")
        #expect(value("generation", in: line) == "before27")
        #expect(value("drags", in: line) == "3")
        #expect(value("moved", in: line) == "2")
        #expect(value("reorder", in: line) == "1")
        #expect(value("section", in: line) == "1")
        #expect(value("medianSettleMs", in: line) == "100")
        #expect(value("maxSettleMs", in: line) == "300")
        #expect(value("bouncy", in: line) == "1")
        #expect(value("vanished", in: line) == "1")
        #expect(value("notPersisted", in: line) == "1")
    }

    @Test("click delays of 80, 120 and 200 give a median of 120, and landed counts yes over checked")
    func clicksAndLanded() {
        var summary = RunSummary()
        for delay in [200, 80, 120] {
            summary.addClick(delayMs: delay)
        }
        #expect(value("landed", in: summary.line(mechanism: "a2", generation: .macOS27)) == "-")
        summary.add(result(), landed: true, refused: false)
        summary.add(result(), landed: false, refused: true)
        summary.add(result(), landed: nil, refused: false)
        let line = summary.line(mechanism: "a2", generation: .macOS27)
        #expect(value("clicks", in: line) == "3")
        #expect(value("medianClickDelayMs", in: line) == "120")
        #expect(value("landed", in: line) == "1/2")
        #expect(value("refused", in: line) == "1")
    }

    @Test("an empty summary writes a dash for every median and maximum")
    func emptySummary() {
        let line = RunSummary().line(mechanism: "a1", generation: .before27)
        for key in ["medianSettleMs", "maxSettleMs", "medianClickDelayMs", "tapMaxUs", "maxShiftPt"] {
            #expect(value(key, in: line) == "-")
        }
        #expect(value("drags", in: line) == "0")
        #expect(value("tracks", in: line) == "0")
    }

    @Test("tracks and their largest shift are counted")
    func tracks() {
        var summary = RunSummary()
        summary.addTrack(shifted: 1, maxShift: 2.5)
        summary.addTrack(shifted: 3, maxShift: 7)
        summary.tapMaxUs = 420
        let line = summary.line(mechanism: "b", generation: .macOS27)
        #expect(value("tracks", in: line) == "2")
        #expect(value("maxShiftPt", in: line) == "7.0")
        #expect(value("tapMaxUs", in: line) == "420")
    }

    @Test("the SUMMARY line's keys come exactly in the contract's order")
    func summaryKeyOrder() {
        let line = RunSummary().line(mechanism: "a1", generation: .before27)
        let keys = line.text.split(separator: " ").dropFirst().map { $0.split(separator: "=")[0] }
        #expect(line.text.hasPrefix("SUMMARY "))
        #expect(keys.map(String.init) == [
            "mech", "generation", "drags", "moved", "reorder", "section", "medianSettleMs", "maxSettleMs",
            "bouncy", "vanished", "notPersisted", "landed", "refused", "clicks", "medianClickDelayMs", "tapMaxUs",
            "tracks", "maxShiftPt",
        ])
    }

    @Test("a2 asks about clicks but not about the overlay, and the ANSWER line maps answers to y, n and skip")
    func questions() {
        let asked = Question.questions(for: "a2")
        #expect(asked.contains(.clicksFine))
        #expect(!asked.contains(.overlayAligned))
        #expect(Question.questions(for: "a1") == [.flicker, .natural, .holzBarFine])
        #expect(Question.questions(for: "b").contains(.overlayAligned))

        let line = Question.answerLine(asked: asked, answers: [.flicker: "yes", .natural: "No", .clicksFine: "maybe"])
        #expect(line.text == "ANSWER flicker=y natural=n clicksFine=skip overlayAligned=n/a holzBarFine=skip")
    }
}
