//
//  ProbeLineTests.swift
//  notifications
//

import Testing
@testable import NotificationProbeCore

@Test("A line is the tag and key=value pairs in the given order")
func lineOrder() {
    let line = ProbeLine.line("EVENT", [("n", "1"), ("name", "AXWindowCreated"), ("tMs", "412.0")])
    #expect(line == "EVENT n=1 name=AXWindowCreated tMs=412.0")
}

@Test("An unknown value is a dash and a value with a space is quoted")
func lineQuotingAndUnknown() {
    let line = ProbeLine.line("PROBE", [("mode", nil), ("label", "my run"), ("redact", "yes"), ("empty", "")])
    #expect(line == "PROBE mode=- label=\"my run\" redact=yes empty=-")
}

@Test("A quote and a backslash inside a value are escaped")
func lineEscapes() {
    #expect(ProbeLine.line("STEP", [("text", "say \"hi\"")]) == "STEP text=\"say \\\"hi\\\"\"")
    #expect(ProbeLine.line("STEP", [("text", "a b\\c")]) == "STEP text=\"a b\\\\c\"")
}

@Test("The summary line has the contract's keys in the contract's order")
func summaryOrder() {
    let line = ProbeLine.summary(routeA: "GO", routeB: "not run", decision: "go")
    #expect(line == "SUMMARY routeA=GO routeB=\"not run\" decision=go")
    #expect(ProbeLine.summary(routeA: nil, routeB: "NO-GO", decision: nil) == "SUMMARY routeA=- routeB=NO-GO decision=-")
}

@Test("The line that ends every report is fixed")
func endLine() {
    #expect(ProbeLine.endOfReport == "=== end of report ===")
}
