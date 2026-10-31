//
//  Verdict.swift
//  notifications
//
//  ROUTE-A and ROUTE-B and the mechanical decision, as pure functions of what the probe
//  observed, by the criteria of 44-CONTEXT.md that were fixed before any run. Foundation
//  only.
//

import Foundation

public enum Verdict {
    public enum Result: String, Sendable {
        case go = "GO"
        case reducedGo = "REDUCED-GO"
        case noGo = "NO-GO"
    }

    /// The limits of the criteria, in milliseconds.
    public static let goLatencyMs = 1500.0
    public static let reducedLatencyMs = 5000.0

    // MARK: ROUTE-A

    /// Judges one trigger on its own: a single run of the probe is one trigger.
    public static func single(_ observation: TriggerObservation) -> (result: Result, reason: String) {
        if observation.blocked {
            return (.noGo, "blocked by the target for more than 2 seconds")
        }
        guard observation.eventSeen else {
            return (.noGo, "no event arrived")
        }
        let title = observation.titleMatched ?? false
        let body = observation.bodyMatched ?? false
        if !title, !body, observation.textNodes == 0 {
            return (.noGo, "event but no text readable")
        }
        if !(title && body) {
            if title {
                return (.reducedGo, "only the title was read")
            }
            return (.reducedGo, body ? "only the body was read" : "only text that does not match was read")
        }
        guard let latency = observation.latencyMs, latency.isFinite else {
            return (.reducedGo, "latency not measured")
        }
        if latency <= goLatencyMs {
            return (.go, "all criteria met")
        }
        if latency <= reducedLatencyMs {
            return (.reducedGo, "latency between 1.5 and 5 seconds")
        }
        return (.noGo, "latency above 5 seconds")
    }

    /// ROUTE-A over the two triggers; `nil` is a trigger that was not run.
    public static func routeA(
        t1: TriggerObservation?,
        t2: TriggerObservation?
    ) -> (Result, reason: String) {
        var items = [(name: String, observation: TriggerObservation)]()
        if let t1 {
            items.append(("T1", t1))
        }
        if let t2 {
            items.append(("T2", t2))
        }
        guard !items.isEmpty else {
            return (.noGo, "not run")
        }
        if let blocked = items.first(where: { $0.observation.blocked }) {
            return (.noGo, "\(blocked.name): \(single(blocked.observation).reason)")
        }
        let judged = items.map { (name: $0.name, judgement: single($0.observation)) }
        if judged.allSatisfy({ $0.judgement.result == .noGo }) {
            return (.noGo, "\(judged[0].name): \(judged[0].judgement.reason)")
        }
        if judged.count == 1 {
            let only = judged[0]
            if only.judgement.result == .go {
                return (.reducedGo, "\(only.name == "T1" ? "T2" : "T1") not run")
            }
            return (only.judgement.result, "\(only.name): \(only.judgement.reason)")
        }
        if judged.allSatisfy({ $0.judgement.result == .go }) {
            return (.go, "all criteria met")
        }
        let reasons = judged.filter { $0.judgement.result != .go }
            .map { "\($0.name): \($0.judgement.reason)" }
        return (.reducedGo, reasons.joined(separator: "; "))
    }

    /// The mechanical recommendation: `go`, `reduced-go` or `no-go`, from ROUTE-A alone.
    public static func decision(routeA: Result) -> String {
        switch routeA {
        case .go: "go"
        case .reducedGo: "reduced-go"
        case .noGo: "no-go"
        }
    }

    /// ROUTE-B never changes the decision: it is recorded and goes to the maintainer.
    public static func decision(routeA: Result, routeB: RouteBResult) -> String {
        _ = routeB
        return decision(routeA: routeA)
    }

    // MARK: Latency and observation

    /// The time that counts for the criteria: for the trigger the probe posts, the time from
    /// the start of the post to the event; for the other trigger, which the probe cannot time
    /// from the sender, the time the read took after the event.
    public static func latencyCounts(posted: Bool, eventMs: Double?, readMs: Double?) -> Double? {
        posted ? eventMs : readMs
    }

    /// The observation of a run from its reads: the read that delivered the most matching
    /// text counts, and the earliest of equals.
    public static func observe(posted: Bool, eventCount: Int, samples: [ReadSample]) -> TriggerObservation {
        let blocked = samples.contains { $0.blocked }
        let best = samples.filter { !$0.blocked }.min { first, second in
            let (a, b) = (first.score, second.score)
            if a != b { return a > b }
            return first.eventMs < second.eventMs
        }
        guard let best else {
            return TriggerObservation(eventSeen: eventCount > 0, textNodes: 0, blocked: blocked)
        }
        return TriggerObservation(
            eventSeen: eventCount > 0,
            latencyMs: latencyCounts(posted: posted, eventMs: best.eventMs, readMs: best.readMs),
            titleMatched: best.titleMatched,
            bodyMatched: best.bodyMatched,
            textNodes: best.textNodes,
            blocked: blocked
        )
    }

    // MARK: ROUTE-B

    /// ROUTE-B: `readable` when any database candidate could be opened without Full Disk
    /// Access. Nothing is read, so it is never a go.
    public static func routeB(_ outcomes: [DatabaseOutcome]) -> (RouteBResult, reason: String) {
        guard !outcomes.isEmpty else {
            return (.noGo, "not run")
        }
        if outcomes.contains(.ok) {
            return (.readable, "readable without Full Disk Access, nothing read")
        }
        return (.noGo, "needs Full Disk Access or absent")
    }

    // MARK: Text

    /// The text of a result for the SUMMARY line: the word, and the reason unless it is GO.
    public static func text(_ judgement: (Result, reason: String)) -> String {
        judgement.0 == .go ? judgement.0.rawValue : "\(judgement.0.rawValue) (\(judgement.reason))"
    }
}

/// What one trigger showed in a run.
public struct TriggerObservation: Equatable, Sendable {
    public var eventSeen: Bool
    public var latencyMs: Double?
    public var titleMatched: Bool?
    public var bodyMatched: Bool?
    public var textNodes: Int
    public var blocked: Bool

    public init(
        eventSeen: Bool,
        latencyMs: Double? = nil,
        titleMatched: Bool? = nil,
        bodyMatched: Bool? = nil,
        textNodes: Int = 0,
        blocked: Bool = false
    ) {
        self.eventSeen = eventSeen
        self.latencyMs = latencyMs
        self.titleMatched = titleMatched
        self.bodyMatched = bodyMatched
        self.textNodes = textNodes
        self.blocked = blocked
    }
}

/// One read of a banner's subtree after an event.
public struct ReadSample: Equatable, Sendable {
    public var eventMs: Double
    public var readMs: Double
    public var textNodes: Int
    public var titleMatched: Bool?
    public var bodyMatched: Bool?
    public var blocked: Bool

    public init(
        eventMs: Double,
        readMs: Double,
        textNodes: Int,
        titleMatched: Bool?,
        bodyMatched: Bool?,
        blocked: Bool = false
    ) {
        self.eventMs = eventMs
        self.readMs = readMs
        self.textNodes = textNodes
        self.titleMatched = titleMatched
        self.bodyMatched = bodyMatched
        self.blocked = blocked
    }

    /// How much of the known text this read delivered; unmatched text counts a little.
    var score: Int {
        (titleMatched == true ? 4 : 0) + (bodyMatched == true ? 4 : 0) + (textNodes > 0 ? 1 : 0)
    }
}

/// What opening a database candidate read-only gave.
public enum DatabaseOutcome: Equatable, Sendable {
    case ok
    case denied(Int32)
    case absent

    public var word: String {
        switch self {
        case .ok: "ok"
        case .denied(let code): "denied:\(code)"
        case .absent: "absent"
        }
    }

    /// `absent` for a path that does not exist (ENOENT, ENOTDIR), `denied` for any other error.
    public static func fromErrno(_ code: Int32) -> DatabaseOutcome {
        (code == 2 || code == 20) ? .absent : .denied(code)
    }
}

public enum RouteBResult: Equatable, Sendable {
    case noGo
    case readable
    case notRun

    public var word: String {
        switch self {
        case .noGo: "NO-GO"
        case .readable: "READABLE"
        case .notRun: "not run"
        }
    }
}
