//
//  SimGateSupport.swift
//  holzBar
//

import Foundation
import Testing
@testable import HolzBarCore

/// What the gate runner collects from the suites: one line per part, appended to the file named by `SYNC_GATE_REPORT`
/// (nothing is written without it). `Scripts/sync-gate.sh` reads the lines to record gate G1.
enum SimGateReport {
    private static let lock = NSLock()

    static func record(_ line: String) {
        guard let path = ProcessInfo.processInfo.environment["SYNC_GATE_REPORT"], !path.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.seekToEndOfFile()
        handle.write(Data((line + "\n").utf8))
        try? handle.close()
    }
}

/// The two kinds of world of the seeded runs. A clean world draws every event except the ones that destroy what a Mac's sync state
/// knows (a clone, a copied account, a restore of the preferences, of Sigma or of the home folder, a lost Sigma, a reinstall) and is
/// judged by every invariant. A disturbed world draws those too, and is judged by every invariant but the ones that need that
/// knowledge to exist (``SimExploration/evidenceLossExclusions``, each with its reason): the ground truth models what it can of the
/// loss (what the state forgot, what the settings still hold), and the invariants below the line stay on.
enum SimWorldFamily: String, Sendable, CaseIterable {
    case clean
    case disturbed

    var drawsEvidenceLoss: Bool { self == .disturbed }
}

/// Consecutive seeds of one provider preset and one family of worlds: the unit the seeded tests run in parallel.
/// `SYNC_SIM_FIRST_SEED` (default 1) moves the first seed, so several processes can share a large run.
struct SimSeedBlock: Sendable, CustomTestStringConvertible {
    var preset: SimProviderPreset
    var seeds: ClosedRange<UInt64>
    var family = SimWorldFamily.clean

    var testDescription: String { "\(family.rawValue) \(preset.rawValue) seeds \(seeds.lowerBound) to \(seeds.upperBound)" }

    static let size: UInt64 = 50

    static var firstSeed: UInt64 {
        ProcessInfo.processInfo.environment["SYNC_SIM_FIRST_SEED"].flatMap { UInt64($0) } ?? 1
    }

    /// The blocks that cover `count` seeds of every preset, in every family of worlds.
    static func blocks(
        count: Int,
        presets: [SimProviderPreset] = SimProviderPreset.allCases,
        families: [SimWorldFamily] = SimWorldFamily.allCases
    ) -> [SimSeedBlock] {
        guard count > 0 else { return [] }
        var blocks: [SimSeedBlock] = []
        for family in families {
            for preset in presets {
                var start = firstSeed
                let end = firstSeed + UInt64(count) - 1
                while start <= end {
                    let last = min(start + size - 1, end)
                    blocks.append(SimSeedBlock(preset: preset, seeds: start...last, family: family))
                    start = last + 1
                }
            }
        }
        return blocks
    }
}
