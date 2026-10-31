//
//  ProbeLineTests.swift
//  display-controls
//

import Testing
@testable import DisplayProbeCore

@Test("A line is the tag and key=value pairs in the given order")
func lineOrder() {
    let line = ProbeLine.line("DISPLAY", [("id", "1"), ("builtIn", "yes"), ("main", "yes")])
    #expect(line == "DISPLAY id=1 builtIn=yes main=yes")
}

@Test("An unknown value is a dash and a value with a space is quoted")
func lineQuotingAndUnknown() {
    let line = ProbeLine.line("PROBE", [("mode", nil), ("label", "my run"), ("redact", "yes"), ("empty", "")])
    #expect(line == "PROBE mode=- label=\"my run\" redact=yes empty=-")
}

@Test("A quote inside a value is escaped")
func lineEscapesQuotes() {
    #expect(ProbeLine.line("STEP", [("text", "say \"hi\"")]) == "STEP text=\"say \\\"hi\\\"\"")
}

@Test("The summary line has the contract's keys in the contract's order")
func summaryOrder() {
    let line = ProbeLine.summary(brightness: "GO", volume: nil, listener: "fired", external: "2,3")
    #expect(line == "SUMMARY brightness=GO volume=- listener=fired external=2,3")
}

@Test("The verdict text names the reason unless the result is GO")
func verdictText() {
    #expect(Verdict.text((.go, reason: "all criteria met")) == "GO")
    #expect(Verdict.text((.reducedGo, reason: "read only")) == "REDUCED-GO (read only)")
}
