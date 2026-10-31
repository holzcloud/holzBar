//
//  VerdictTests.swift
//  notifications
//

import Testing
@testable import NotificationProbeCore

private func good(latency: Double = 400) -> TriggerObservation {
    TriggerObservation(eventSeen: true, latencyMs: latency, titleMatched: true, bodyMatched: true, textNodes: 3)
}

private let titleOnly = TriggerObservation(
    eventSeen: true, latencyMs: 300, titleMatched: true, bodyMatched: false, textNodes: 2
)

private let eventOnly = TriggerObservation(
    eventSeen: true, latencyMs: 300, titleMatched: false, bodyMatched: false, textNodes: 0
)

private let silent = TriggerObservation(eventSeen: false, textNodes: 0)

private let blocked = TriggerObservation(eventSeen: true, textNodes: 0, blocked: true)

@Test("Two good triggers within 1.5 seconds give GO")
func routeAGo() {
    let result = Verdict.routeA(t1: good(), t2: good(latency: 1500))
    #expect(result.0 == .go)
    #expect(Verdict.decision(routeA: result.0) == "go")
}

@Test("One good trigger and the other with only a title, or only the event, gives REDUCED-GO")
func routeAReducedOneGood() {
    #expect(Verdict.routeA(t1: good(), t2: titleOnly).0 == .reducedGo)
    #expect(Verdict.routeA(t1: eventOnly, t2: good()).0 == .reducedGo)
    #expect(Verdict.routeA(t1: good(), t2: silent).0 == .reducedGo)
    #expect(Verdict.decision(routeA: .reducedGo) == "reduced-go")
}

@Test("A latency between 1.5 and 5 seconds gives REDUCED-GO and above 5 seconds NO-GO")
func routeALatencyBands() {
    #expect(Verdict.single(good(latency: 1500.5)).result == .reducedGo)
    #expect(Verdict.single(good(latency: 5000)).result == .reducedGo)
    #expect(Verdict.single(good(latency: 5001)).result == .noGo)
    #expect(Verdict.routeA(t1: good(latency: 3000), t2: good()).0 == .reducedGo)
}

@Test("An event with no text in either trigger gives NO-GO with the reason")
func routeAEventWithoutText() {
    let result = Verdict.routeA(t1: eventOnly, t2: eventOnly)
    #expect(result.0 == .noGo)
    #expect(result.reason == "T1: event but no text readable")
    #expect(Verdict.decision(routeA: result.0) == "no-go")
}

@Test("No event at all gives NO-GO")
func routeANoEvent() {
    let result = Verdict.routeA(t1: silent, t2: silent)
    #expect(result.0 == .noGo)
    #expect(result.reason == "T1: no event arrived")
}

@Test("A probe blocked by the target for more than two seconds gives NO-GO even when the other trigger is good")
func routeABlocked() {
    let result = Verdict.routeA(t1: good(), t2: blocked)
    #expect(result.0 == .noGo)
    #expect(result.reason == "T2: blocked by the target for more than 2 seconds")
}

@Test("A trigger that was not run caps the result at REDUCED-GO and none at all is NO-GO")
func routeANotRun() {
    #expect(Verdict.routeA(t1: good(), t2: nil).0 == .reducedGo)
    #expect(Verdict.routeA(t1: nil, t2: titleOnly).0 == .reducedGo)
    #expect(Verdict.routeA(t1: nil, t2: nil).0 == .noGo)
    #expect(Verdict.routeA(t1: silent, t2: nil).0 == .noGo)
}

@Test("A single run is judged on its own trigger, so a perfect T1 run is GO")
func singleRun() {
    #expect(Verdict.single(good()).result == .go)
    #expect(Verdict.single(titleOnly).reason == "only the title was read")
    #expect(Verdict.single(TriggerObservation(
        eventSeen: true, latencyMs: 100, titleMatched: false, bodyMatched: true, textNodes: 1
    )).reason == "only the body was read")
    #expect(Verdict.single(TriggerObservation(
        eventSeen: true, latencyMs: 100, titleMatched: false, bodyMatched: false, textNodes: 2
    )).reason == "only text that does not match was read")
    #expect(Verdict.single(TriggerObservation(
        eventSeen: true, latencyMs: nil, titleMatched: true, bodyMatched: true, textNodes: 2
    )).reason == "latency not measured")
}

@Test("The text of a result names the reason unless it is GO")
func resultText() {
    #expect(Verdict.text((.go, reason: "all criteria met")) == "GO")
    #expect(Verdict.text((.reducedGo, reason: "only the title was read")) == "REDUCED-GO (only the title was read)")
}

@Test("ROUTE-B is NO-GO when every candidate is denied or absent")
func routeBNoGo() {
    let result = Verdict.routeB([.denied(1), .absent])
    #expect(result.0 == .noGo)
    #expect(result.reason == "needs Full Disk Access or absent")
    #expect(result.0.word == "NO-GO")
}

@Test("ROUTE-B is READABLE when any candidate opens, and nothing was read")
func routeBReadable() {
    let result = Verdict.routeB([.absent, .ok])
    #expect(result.0 == .readable)
    #expect(result.reason == "readable without Full Disk Access, nothing read")
    #expect(result.0.word == "READABLE")
}

@Test("ROUTE-B with no candidate is NO-GO and not run")
func routeBEmpty() {
    let result = Verdict.routeB([])
    #expect(result.0 == .noGo)
    #expect(result.reason == "not run")
    #expect(RouteBResult.notRun.word == "not run")
}

@Test("ROUTE-B never turns the decision into a go")
func decisionIgnoresRouteB() {
    #expect(Verdict.decision(routeA: .noGo, routeB: .readable) == "no-go")
    #expect(Verdict.decision(routeA: .reducedGo, routeB: .readable) == "reduced-go")
    #expect(Verdict.decision(routeA: .go, routeB: .noGo) == "go")
}

@Test("A database outcome is written as ok, denied with the error number, or absent")
func databaseOutcomeWords() {
    #expect(DatabaseOutcome.ok.word == "ok")
    #expect(DatabaseOutcome.denied(1).word == "denied:1")
    #expect(DatabaseOutcome.absent.word == "absent")
    #expect(DatabaseOutcome.fromErrno(2) == .absent)
    #expect(DatabaseOutcome.fromErrno(1) == .denied(1))
}

@Test("The latency of the posted trigger runs from the start of the post, the other counts the read after the event")
func latencyRule() {
    #expect(Verdict.latencyCounts(posted: true, eventMs: 420, readMs: 15) == 420)
    #expect(Verdict.latencyCounts(posted: false, eventMs: 9000, readMs: 15) == 15)
    #expect(Verdict.latencyCounts(posted: true, eventMs: nil, readMs: 15) == nil)
}

@Test("A run's observation takes the read that delivered the most text, earliest first")
func observationFromReads() {
    let empty = ReadSample(eventMs: 40, readMs: 8, textNodes: 0, titleMatched: false, bodyMatched: false)
    let partial = ReadSample(eventMs: 120, readMs: 9, textNodes: 2, titleMatched: true, bodyMatched: false)
    let full = ReadSample(eventMs: 300, readMs: 11, textNodes: 3, titleMatched: true, bodyMatched: true)
    let later = ReadSample(eventMs: 900, readMs: 7, textNodes: 3, titleMatched: true, bodyMatched: true)

    let posted = Verdict.observe(posted: true, eventCount: 4, samples: [empty, partial, later, full])
    #expect(posted.eventSeen)
    #expect(posted.latencyMs == 300)
    #expect(posted.titleMatched == true && posted.bodyMatched == true)

    let other = Verdict.observe(posted: false, eventCount: 4, samples: [empty, partial, later, full])
    #expect(other.latencyMs == 11)

    let none = Verdict.observe(posted: true, eventCount: 0, samples: [])
    #expect(!none.eventSeen)
    #expect(Verdict.single(none).reason == "no event arrived")

    let blockedRun = Verdict.observe(
        posted: false, eventCount: 1,
        samples: [ReadSample(eventMs: 10, readMs: 2100, textNodes: 0, titleMatched: nil, bodyMatched: nil, blocked: true)]
    )
    #expect(blockedRun.blocked)
}
