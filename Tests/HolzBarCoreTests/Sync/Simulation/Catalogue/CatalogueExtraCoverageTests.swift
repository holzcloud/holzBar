//
//  CatalogueExtraCoverageTests.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// Which scenario asserts each scenario of A2 section 7 (SC-01 to SC-71). The A1 catalogue (S-01 to S-70, whose coverage
/// `CatalogueCoverage` in `CatalogueCoverageTests.swift` proves) holds most of them under another name; the D3, judge and A2
/// residual files of plan 28-12 hold the rest. A scenario that an earlier one already asserts is mapped there and not written
/// twice.
nonisolated enum A2Mapping {
    /// Each A2 id to the id of the scenario that asserts it. A comment says where the two meet.
    static let covers: [String: String] = [
        // Joining and identity
        "SC-01": "S-07", // joining a folder with no file publishes and asks nothing
        "SC-02": "S-07", // a file whose settings equal this Mac's is adopted silently, with no hint on the other Mac
        "SC-03": "S-01", // a configured group and a fresh Mac: Use, Keep and Cancel
        "SC-04": "SC-33", // a fresh Mac's automatic arrangement gives way to the group's silently: the upgrade form, SC-33
        "SC-05": "S-06", // a clone gets its own identity and joins with its replica
        "SC-06": "D3-S09", // preferences restored from an old backup, Σ intact: a join without a dot
        "SC-07": "D3-S11", // two accounts on one Mac: distinct IDs, both sync
        "SC-08": "SC-08", // Change… to a folder with another group; Cancel keeps the old folder
        // Steady state
        "SC-10": "D3-S01", // a change on one Mac is a restart hint on the other and applies there with no question
        "SC-11": "D3-S02", // concurrent changes of one setting: one question each, one answer settles both
        "SC-12": "J-14", // equal values collapse and ask nothing
        "SC-13": "S-02", // a hundred relaunches write nothing and show no hint
        "SC-14": "S-04", // Later, then a push: the waiting version survives
        "SC-15": "D3-S03", // a value that arrives while a sheet is open is asked about anew, never superseded
        "SC-16": "SC-16", // a deleted hotkey reaches the other Mac as an explicit deletion of that hotkey only
        "SC-17": "SC-17", // an Import without Hotkeys deletes exactly the hotkeys the importing Mac had
        // Automatic versus user
        "SC-20": "S-55", // a new item or application placed automatically creates no dot and no hint
        "SC-21": "S-60", // an automatic store never overwrites an entry with applied intent
        "SC-22": "S-59", // displacement creates nothing; only the application the user moved counts
        "SC-23": "S-67", // automatic events inside the settle window mint nothing
        "SC-24": "SC-24", // known applications of macOS 27 union silently; every other learned key stays local
        "SC-25": "S-56", // a Command-click without a move, and a profile that changes nothing, create no intent
        // Generations (SC-30 to SC-36 in their macOS 27 form)
        "SC-30": "SC-30",
        "SC-31": "SC-31",
        "SC-32": "SC-32",
        "SC-33": "SC-33",
        "SC-34": "SC-34",
        "SC-35": "SC-35",
        "SC-36": "SC-36",
        // L1, P and N+ peers
        "SC-40": "S-27", // a beta1 Mac that rewrites its file is a status line and nothing else
        "SC-41": "S-27", // fifty relaunches of a beta1 Mac: no question
        "SC-42": "S-20", // a beta1 arrangement survives a redesigned Mac's write
        "SC-43": "S-23", // a kept answer is not undone by a beta1 write
        "SC-44": "S-62", // an arrangement made during the beta2 pause is asked about at the first run
        "SC-45": "D3-S08", // the return from a beta1 run is a join
        "SC-46": "SC-46", // a file of a newer format is never rewritten or pruned
        "SC-47": "SC-47", // a legacy file with only a device field gives no lineage
        // File-provider realities
        "SC-50": "S-09", // a dataless file at login never blocks the launch
        "SC-51": "S-09", // a hung provider never blocks the launch, and nothing is written over the unread file
        "SC-52": "S-43", // a truncated file is unreadable, never missing, and never written over
        "SC-53": "J-10", // concurrent writes of one file: the loser's content is not globally lost
        "SC-54": "J-10", // an unresolved version of iCloud instead of a sibling file
        "SC-55": "S-42", // an older version of the own file comes back: no apply, no prompt, the writer publishes again
        "SC-56": "S-34", // a deleted file or folder reverts nothing and the next publications are honest
        "SC-57": "S-03", // a Mac away for two weeks: one question pair, nothing lost
        "SC-58": "S-32", // the older of two writes delivered last never reverts the newer
        "SC-59": "S-30", // clocks far apart and stepped back decide nothing
        "SC-60": "S-10", // an unmounted share: nothing mounted, nothing written, a status line
        "SC-61": "S-11", // a state over 1 MiB: no write, a warning, the previous publication intact
        "SC-62": "S-12", // one bad entry is skipped, the rest applied, nothing written back
        "SC-63": "S-43", // a symbolic link as the file or the folder is refused
        "SC-64": "SC-64", // a lost write on a last-writer-wins share is noticed and published again
        "SC-65": "SC-65", // a rollback of the own file to an older own state is recognised
        // Convergence
        "SC-70": "SC-70",
        "SC-71": "SC-71",
    ]

    /// Every id of A2 section 7, in order.
    static let ids: [String] = {
        let ranges: [ClosedRange<Int>] = [1...8, 10...17, 20...25, 30...36, 40...47, 50...65, 70...71]
        return ranges.flatMap { $0 }.map { String(format: "SC-%02d", $0) }
    }()

    /// The ids of the A1 catalogue, whose coverage `CatalogueCoverage` proves: S-01 to S-70.
    static let a1Ids: Set<String> = Set((1...70).map { String(format: "S-%02d", $0) })

    /// The scenarios of the catalogue files this plan can see. Plan 28-11's files (G6 to G10) add S-34 to S-70, which
    /// `CatalogueCoverage.scenarios` unites with these; their ids are checked against `a1Ids` here.
    static var registered: [CatalogueScenario] {
        CatalogueCoverage.scenarios
            + CatalogueD3.scenarios + CatalogueJudges.scenarios + CatalogueA2Residual.scenarios
    }

    /// An id without the suffix of a form: `S-15/27` is `S-15`.
    static func base(_ id: String) -> String {
        id.split(separator: "/").first.map(String.init) ?? id
    }
}

@Suite("CatalogueExtraCoverage")
struct CatalogueExtraCoverageTests {
    @Test("Every scenario of A2 section 7 is mapped, and nothing else is")
    func everyA2IdIsMapped() {
        for id in A2Mapping.ids {
            #expect(A2Mapping.covers[id] != nil, "\(id) is mapped to no scenario")
        }
        let unknown = Set(A2Mapping.covers.keys).subtracting(A2Mapping.ids)
        #expect(unknown.isEmpty, "the mapping names scenarios that A2 does not have: \(unknown.sorted())")
        #expect(A2Mapping.ids.count == 55)
    }

    @Test("Every mapping points at a registered scenario")
    func everyTargetIsRegistered() {
        let registered = Set(A2Mapping.registered.map { A2Mapping.base($0.id) })
        for id in A2Mapping.ids {
            guard let target = A2Mapping.covers[id] else { continue }
            if target.hasPrefix("S-") {
                // The A1 ids that plan 28-10 registered must exist; the rest are in the files of plan 28-11.
                #expect(A2Mapping.a1Ids.contains(target), "\(id) is mapped to \(target), which is no id of the A1 catalogue")
                #expect(registered.contains(target), "\(id) is mapped to \(target), which no catalogue file registers")
            } else {
                #expect(registered.contains(target), "\(id) is mapped to \(target), which no catalogue file registers")
            }
        }
    }

    @Test("A scenario of the A2 residual file asserts the A2 id it carries, and no other")
    func residualScenariosMapToThemselves() {
        for scenario in CatalogueA2Residual.scenarios {
            #expect(A2Mapping.covers[scenario.id] == scenario.id, "\(scenario.id) is not mapped to itself")
            #expect(scenario.source == .a2)
        }
        let own = Set(A2Mapping.covers.filter { $0.key == $0.value }.keys)
        #expect(own == Set(CatalogueA2Residual.scenarios.map(\.id)), "a self-mapping has no scenario or the other way round")
    }

    @Test("No scenario id appears twice across the catalogue files")
    func noDuplicateIds() {
        var seen = Set<String>()
        for scenario in A2Mapping.registered {
            #expect(seen.insert(scenario.id).inserted, "\(scenario.id) is registered twice")
        }
    }

    @Test("The D3 ids are D3-S01 to D3-S20 and the judges' ids J-01 to J-16, each once")
    func d3AndJudgeIds() {
        #expect(CatalogueD3.scenarios.map(\.id) == (1...20).map { String(format: "D3-S%02d", $0) })
        #expect(CatalogueJudges.scenarios.map(\.id) == (1...16).map { String(format: "J-%02d", $0) })
        #expect(CatalogueD3.scenarios.allSatisfy { $0.source == .d3 })
        #expect(CatalogueJudges.scenarios.allSatisfy { $0.source == .judge })
    }
}
