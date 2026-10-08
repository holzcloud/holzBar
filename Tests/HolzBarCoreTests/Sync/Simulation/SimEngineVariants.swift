//
//  SimEngineVariants.swift
//  holzBar
//

import Foundation
@testable import HolzBarCore

// Control engines of the redesigned engine (analysis section 5.6, decision D-11): each one is the real
// engine with exactly one of its defenses removed (`SyncGuards`). The oracles must catch every one of them
// within a bounded number of seeds on the scenarios that expose it; if one survives, the generator or the
// oracles are too weak and the gate fails. The unmodified engine runs the same seeds with no violation.

extension SimMacRedesign {
    /// The real engine with `removed` taken out of its defenses.
    static func variant(_ removed: SyncGuards) -> SimMacRedesign {
        SimMacRedesign(guards: SyncGuards.all.subtracting(removed))
    }
}

/// A scenario that exposes the removal of one defense: the random events of one seed, the provider preset,
/// and the oracles that must fire.
protocol SimEngineVariant {
    /// The defense that is removed.
    static var removed: SyncGuards { get }
    /// The provider preset the scenario runs on (`nil`: an ideal provider).
    static var preset: SimProviderPreset? { get }
    /// The oracles of which at least one must fire.
    static var caughtBy: Set<String> { get }
    /// The random events of one seed. `ownFile` is the path of Mac A's own device file.
    static func events(seed: UInt64, ownFile: String) -> [SimEvent]
}

extension SimEngineVariant {
    static func macs() -> [SimMacSpec] {
        [SimMacSpec(.A, .redesign, running: true), SimMacSpec(.B, .redesign, running: true)]
    }

    static func world(seed: UInt64, events: [SimEvent], removed: SyncGuards? = nil) -> SimWorld {
        let removed = removed ?? Self.removed
        let world = SimWorld(
            seed: seed,
            macs: macs(),
            preset: preset,
            brainFactory: { _, _ in SimMacRedesign.variant(removed) },
            oracles: .safety
        )
        world.run(events)
        return world
    }

    /// The path of Mac A's own file in the world of `seed`: the identity is drawn at the first launch,
    /// so it does not depend on the events.
    static func ownFile(seed: UInt64) -> String {
        let probe = SimWorld(seed: seed, macs: macs(), preset: preset, brainFactory: { _, _ in SimMacRedesign() }, oracles: .none)
        return SimFolderIO.directory + "/\(SimMacRedesignProbe.id(of: probe, .A) ?? "").plist"
    }

    static func events(seed: UInt64) -> [SimEvent] {
        events(seed: seed, ownFile: ownFile(seed: seed))
    }

    /// The violations of the oracles this variant must trip.
    static func found(_ world: SimWorld) -> Bool {
        world.oracleViolations.contains { caughtBy.contains($0.id.rawValue) }
    }
}

/// Two Macs change one unit at about the same time, so the other's entry arrives between the change and
/// its capture. Without the applied-context rule the capture supersedes every live entry, including the
/// one this Mac's user never saw (INV-S1 or INV-S7, then INV-S1g).
enum NoAppliedContext: SimEngineVariant {
    static let removed = SyncGuards.appliedContext
    static let preset: SimProviderPreset? = .iCloud
    static let caughtBy: Set<String> = ["INV-S1", "INV-S7", "INV-S1g"]

    static func events(seed: UInt64, ownFile: String) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("variant-applied-context")
        var events: [SimEvent] = []
        for _ in 0..<4 {
            events.append(.userEdit(mac: .B, unit: "S1"))
            events.append(.advance(milliseconds: Int64(random.int(in: 6...24)) * 500))
            events.append(.userEdit(mac: .A, unit: "S1"))
            events.append(.advance(milliseconds: Int64(random.int(in: 4...30)) * 500))
            switch random.int(in: 0...3) {
            case 0: events.append(.restartApp(mac: .A))
            case 1: events.append(.answer(mac: .A, random.chance(0.5) ? .use : .keep))
            case 2: events.append(.answer(mac: .B, random.chance(0.5) ? .use : .keep))
            default: events.append(.restartApp(mac: .B))
            }
        }
        return events
    }
}

/// A Mac writes over its own file without having read it in this session: someone restored an older
/// version of it. Without the own-file-first rule the write goes through unchecked (INV-S6, INV-Z6, or
/// INV-S1g when the entries of the older file are lost).
enum UnreadOwnFileOverwrite: SimEngineVariant {
    static let removed = SyncGuards.ownFileReadFirst
    static let preset: SimProviderPreset? = nil
    static let caughtBy: Set<String> = ["INV-S6", "INV-Z6", "INV-S1g"]

    static func events(seed: UInt64, ownFile: String) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("variant-own-file")
        var events: [SimEvent] = []
        for _ in 0..<5 {
            events.append(.userEdit(mac: .A, unit: random.pick(["S1", "S2", "S3"])))
            events.append(.advance(milliseconds: Int64(random.int(in: 3...8)) * 1000))
            switch random.int(in: 0...3) {
            case 0: events.append(.provider(.restore(path: ownFile, version: random.int(in: 1...4))))
            case 1: events.append(.provider(.evict(path: ownFile, mac: .A)))
            case 2: events.append(.provider(.exposePartial(path: ownFile, mac: .A, forMilliseconds: 6_000)))
            default: events.append(.userEdit(mac: .B, unit: random.pick(["S1", "S2"])))
            }
        }
        return events
    }
}

/// Preferences are restored from a backup while Sigma is not, so Sigma is not evidence of what this Mac
/// holds. An engine that mints for it at launch publishes the old values as new changes and reverts the
/// group (INV-S2, INV-S1, INV-B5).
enum MintAtLaunchUntrusted: SimEngineVariant {
    static let removed = SyncGuards.trustedState
    static let preset: SimProviderPreset? = nil
    static let caughtBy: Set<String> = ["INV-S1", "INV-S2", "INV-S1g", "INV-B5"]

    static func events(seed: UInt64, ownFile: String) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("variant-untrusted")
        var events: [SimEvent] = []
        for _ in 0..<4 {
            events.append(.userEdit(mac: .A, unit: random.pick(["S1", "S2"])))
            events.append(.advance(milliseconds: Int64(random.int(in: 3...9)) * 1000))
            events.append(.restartApp(mac: .B))
            events.append(.userEdit(mac: .B, unit: random.pick(["S1", "S2"])))
            events.append(.advance(milliseconds: Int64(random.int(in: 3...9)) * 1000))
            events.append(.restartApp(mac: .A))
            if random.chance(0.6) {
                events.append(.restorePrefs(mac: .A))
                events.append(.launch(mac: .A))
                events.append(.advance(milliseconds: Int64(random.int(in: 3...9)) * 1000))
            }
            if random.chance(0.4) {
                events.append(.answer(mac: .A, random.chance(0.5) ? .use : .keep))
            }
        }
        return events
    }
}

/// "No user value" is the key's absence, never "equal to the default" (D-10). An engine for which absence is
/// a value publishes a deletion for every setting nobody has set, and a Mac that never had a setting deletes
/// it for everyone (INV-A6, INV-S1, INV-S2).
enum EqualToDefaultAsUnset: SimEngineVariant {
    static let removed = SyncGuards.absentMeansNoValue
    static let preset: SimProviderPreset? = .iCloud
    static let caughtBy: Set<String> = ["INV-A6", "INV-S1", "INV-S2", "INV-S1g", "INV-P1"]

    static func events(seed: UInt64, ownFile: String) -> [SimEvent] {
        var random = SimRandom(seed: seed).fork("variant-default")
        var events: [SimEvent] = []
        for _ in 0..<4 {
            let mac: SimMacName = random.chance(0.5) ? .A : .B
            let unit = random.pick(["S1", "S2", "S3", "S4"])
            events.append(.userEdit(mac: mac, unit: unit))
            events.append(.advance(milliseconds: Int64(random.int(in: 2...20)) * 1000))
            if random.chance(0.3) {
                // A setting that was set is reset to its default: the key is removed.
                events.append(.userDelete(mac: mac, unit: unit))
                events.append(.advance(milliseconds: Int64(random.int(in: 2...10)) * 1000))
            }
            events.append(.restartApp(mac: random.chance(0.5) ? .A : .B))
        }
        return events
    }
}
