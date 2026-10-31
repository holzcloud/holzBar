//
//  VerdictTests.swift
//  calendar-access
//

import Testing
@testable import CalendarAccessCore

private func observed(_ variant: Variant, _ outcome: Outcome) -> Observation {
    switch outcome {
    case .readable:
        Observation(variant: variant, statusAfter: .fullAccess, granted: true, storeReadable: true)
    case .denied:
        Observation(variant: variant, statusAfter: .denied, granted: false, storeReadable: false)
    case .unreadable:
        Observation(variant: variant, statusAfter: .fullAccess, granted: true, storeReadable: false)
    }
}

@Test("V1 readable means the entitlement is not needed")
func v1Readable() {
    let result = Verdict.evaluate([observed(.v1, .readable)])
    #expect(result.result == .entitlementNotNeeded)
}

@Test("V3 readable with V1 denied also means not needed")
func v3ReadableV1Denied() {
    let result = Verdict.evaluate([observed(.v1, .denied), observed(.v3, .readable)])
    #expect(result.result == .entitlementNotNeeded)
}

@Test("V1 and V3 not readable and V2 readable means required")
func v2Readable() {
    let result = Verdict.evaluate([
        observed(.v1, .denied), observed(.v2, .readable), observed(.v3, .unreadable),
    ])
    #expect(result.result == .entitlementRequired)
}

@Test("V4 readable alone means required")
func v4Alone() {
    #expect(Verdict.evaluate([observed(.v4, .readable)]).result == .entitlementRequired)
}

@Test("No variant readable means no-go")
func noneReadable() {
    let result = Verdict.evaluate(Variant.allCases.map { observed($0, .denied) })
    #expect(result.result == .noGo)
    #expect(Verdict.evaluate(Variant.allCases.map { observed($0, .unreadable) }).result == .noGo)
}

@Test("An empty list is no-go with the reason no run")
func emptyList() {
    let result = Verdict.evaluate([])
    #expect(result.result == .noGo)
    #expect(result.reason == "no run")
}

@Test("An observation is readable only with full access, a grant and a readable store")
func outcomes() {
    #expect(Observation(variant: .v1, statusAfter: .fullAccess, granted: true, storeReadable: true).outcome == .readable)
    #expect(Observation(variant: .v1, statusAfter: .fullAccess, granted: true, storeReadable: false).outcome == .unreadable)
    #expect(Observation(variant: .v1, statusAfter: .fullAccess, granted: false, storeReadable: true).outcome == .denied)
    #expect(Observation(variant: .v1, statusAfter: .writeOnly, granted: true, storeReadable: true).outcome == .denied)
    #expect(Observation(variant: .v1, statusAfter: .notDetermined, granted: false, storeReadable: false).outcome == .denied)
}

@Test("Variants know their signature, entitlement and identifier")
func variants() {
    #expect(Variant.v1.hasCalendarsEntitlement == false)
    #expect(Variant.v2.hasCalendarsEntitlement)
    #expect(Variant.v3.usesReleaseCertificate)
    #expect(Variant.v4.usesReleaseCertificate && Variant.v4.hasCalendarsEntitlement)
    #expect(Variant.v2.bundleIdentifier == "ch.holzcloud.holzbar.calendarprobe.v2")
}

@Test("ReportLine writes the keys in order, quotes spaces and writes a dash for nil")
func reportLine() {
    let line = ReportLine.format(tag: "ANSWER", [("promptShown", "yes"), ("promptText", "Allow access to calendars")])
    #expect(line == "ANSWER promptShown=yes promptText=\"Allow access to calendars\"")
    #expect(ReportLine.format(tag: "REQUEST", [("granted", "false"), ("error", nil)]) == "REQUEST granted=false error=-")
    #expect(ReportLine.format(tag: "X", [("a", "")]) == "X a=-")
    #expect(ReportLine.format(tag: "X", [("a", "say \"hi\"")]) == "X a=\"say \\\"hi\\\"\"")
}
