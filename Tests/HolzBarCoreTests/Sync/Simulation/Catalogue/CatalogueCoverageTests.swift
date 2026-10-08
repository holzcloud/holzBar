//
//  CatalogueCoverageTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// Every scenario of the A1 catalogue S-01 to S-70, in the order of its groups. Plan 28-12's coverage test and plan 28-13's
/// gate script use it too.
nonisolated enum CatalogueCoverage {
    static let scenarios: [CatalogueScenario] = {
        var all: [CatalogueScenario] = []
        all += CatalogueG1Joining.scenarios
        all += CatalogueG2Infrastructure.scenarios
        all += CatalogueG3Generations.scenarios
        all += CatalogueG4BetaPeers.scenarios
        all += CatalogueG5Clocks.scenarios
        all += CatalogueG6FileFaults.scenarios
        all += CatalogueG7Answers.scenarios
        all += CatalogueG8Automatic.scenarios
        all += CatalogueG9Races.scenarios
        all += CatalogueG10Convergence.scenarios
        return all
    }()

    /// The ids S-01 to S-70.
    static let expectedIDs: [String] = (1...70).map { "S-" + String(format: "%02d", $0) }

    /// The SCOPE scenarios of analysis Appendix B: layout propagation, run in a generation-26 and a generation-27 form.
    static let scopeIDs: Set<String> = [
        "S-08", "S-15", "S-16", "S-17", "S-29", "S-31", "S-37", "S-38", "S-40", "S-41", "S-42", "S-45", "S-47", "S-48",
        "S-49", "S-51", "S-52", "S-56", "S-57", "S-58", "S-59", "S-60", "S-61", "S-62", "S-64", "S-67", "S-69",
    ]

    /// The BOUNDARY scenarios of Appendix B: a real 0.0.7-beta1 peer takes part.
    static let boundaryIDs: Set<String> = Set((18...27).map { "S-" + String(format: "%02d", $0) })

    /// The id of a scenario without its form suffix (`S-15/27` is `S-15`).
    static func baseID(_ scenario: CatalogueScenario) -> String {
        scenario.id.split(separator: "/").first.map(String.init) ?? scenario.id
    }

    /// What Appendix B calls a scenario.
    static func expectedKind(of id: String) -> CatalogueKind {
        if scopeIDs.contains(id) { return .scope }
        if boundaryIDs.contains(id) { return .boundary }
        return .pass
    }

    /// Everything that is wrong with the catalogue: a missing, duplicate or misclassed id, a scope scenario without both
    /// forms, a form on a scenario that has none, a scenario without its A1 text. Empty when the catalogue is complete.
    static func problems(in scenarios: [CatalogueScenario] = CatalogueCoverage.scenarios) -> [String] {
        var problems: [String] = []
        var seen = Set<String>()
        for scenario in scenarios where !seen.insert(scenario.id).inserted {
            problems.append("\(scenario.id) appears more than once")
        }
        let grouped = Dictionary(grouping: scenarios, by: baseID)
        let known = Set(expectedIDs)
        for id in expectedIDs where grouped[id] == nil {
            problems.append("\(id) is missing")
        }
        for id in grouped.keys.sorted() where !known.contains(id) {
            problems.append("\(id) is no id of S-01 to S-70")
        }
        for id in expectedIDs {
            guard let entries = grouped[id] else { continue }
            let expected = expectedKind(of: id)
            for entry in entries where entry.kind != expected {
                problems.append("\(entry.id) is classed \(entry.kind.rawValue), Appendix B classes \(id) as \(expected.rawValue)")
            }
            let suffixes = entries.map { $0.id == id ? "" : String($0.id.dropFirst(id.count)) }.sorted()
            if expected == .scope, suffixes != ["/26", "/27"] {
                problems.append("\(id) is a scope scenario and needs the forms /26 and /27, it has \(suffixes)")
            }
            if expected != .scope, suffixes != [""] {
                problems.append("\(id) is no scope scenario and must have one entry without a form, it has \(suffixes)")
            }
            if Catalogue.a1Text(id: id) == nil {
                problems.append("\(id) has no A1 text for its failure message")
            }
        }
        return problems
    }

    /// The numbers of Appendix B: how many ids are PASS, SCOPE and BOUNDARY.
    static func counts(in scenarios: [CatalogueScenario] = CatalogueCoverage.scenarios) -> (pass: Int, scope: Int, boundary: Int) {
        let kinds = Dictionary(grouping: scenarios, by: baseID).mapValues { $0.first?.kind }
        return (
            kinds.values.filter { $0 == .pass }.count,
            kinds.values.filter { $0 == .scope }.count,
            kinds.values.filter { $0 == .boundary }.count
        )
    }
}

@Suite("CatalogueCoverage")
struct CatalogueCoverageTests {
    @Test("The union of the catalogue files is exactly S-01 to S-70, each id once, classed as in Appendix B")
    func everyScenarioOnce() {
        let problems = CatalogueCoverage.problems()
        if !problems.isEmpty {
            Issue.record(Comment(rawValue: "The catalogue is not complete:\n" + problems.map { "  - \($0)" }.joined(separator: "\n")))
        }
    }

    @Test("Appendix B counts 33 PASS, 27 SCOPE and 10 BOUNDARY scenarios")
    func appendixBCounts() {
        let counts = CatalogueCoverage.counts()
        #expect(counts.pass == 33, "PASS scenarios: \(counts.pass)")
        #expect(counts.scope == 27, "SCOPE scenarios: \(counts.scope)")
        #expect(counts.boundary == 10, "BOUNDARY scenarios: \(counts.boundary)")
        #expect(counts.pass + counts.scope + counts.boundary == 70)
    }

    @Test("The check finds a missing id, a duplicate, a misclassed id and a scope scenario with one form")
    func theCheckCatchesGaps() {
        let all = CatalogueCoverage.scenarios
        let missing = all.filter { CatalogueCoverage.baseID($0) != "S-34" }
        #expect(CatalogueCoverage.problems(in: missing).contains { $0.contains("S-34 is missing") })
        #expect(CatalogueCoverage.problems(in: all + [all[0]]).contains { $0.contains("appears more than once") })
        let oneForm = all.filter { $0.id != "S-40/27" }
        #expect(CatalogueCoverage.problems(in: oneForm).contains { $0.contains("S-40") && $0.contains("forms") })
        let misclassed = all.map { scenario in
            scenario.id == "S-34" ? CatalogueScenario(id: scenario.id, title: scenario.title, source: scenario.source, kind: .scope, run: scenario.run) : scenario
        }
        #expect(CatalogueCoverage.problems(in: misclassed).contains { $0.contains("S-34 is classed scope") })
    }
}
