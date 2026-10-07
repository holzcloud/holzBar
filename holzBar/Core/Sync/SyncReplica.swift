//
//  SyncReplica.swift
//  holzBar
//

import Foundation

/// The name of one synced unit: a setting, or one item of a family of items.
///
/// Whole units (`ShowOnHover`) are one value. Split units (`Hotkeys`, item `ShowHidden`)
/// are a family of items that change independently. The item key is kept apart from the
/// family because identity keys contain `/` and `:`.
nonisolated enum SyncUnitKey: Hashable, Comparable, Sendable {
    case whole(String)
    case split(family: String, item: String)

    /// Whole units sort before split units, then by name, by UTF-8 bytes.
    static func < (lhs: SyncUnitKey, rhs: SyncUnitKey) -> Bool {
        switch (lhs, rhs) {
        case (.whole(let left), .whole(let right)):
            left.utf8.lexicographicallyPrecedes(right.utf8)
        case (.whole, .split):
            true
        case (.split, .whole):
            false
        case (.split(let leftFamily, let leftItem), .split(let rightFamily, let rightItem)):
            leftFamily == rightFamily
                ? leftItem.utf8.lexicographicallyPrecedes(rightItem.utf8)
                : leftFamily.utf8.lexicographicallyPrecedes(rightFamily.utf8)
        }
    }
}

/// What joining two replicas gives.
nonisolated struct SyncJoinResult: Hashable, Sendable {
    /// The joined replica.
    let replica: SyncReplica
    /// The dots that two replicas hold with different values. A Mac's own dots among them
    /// mean that the Mac's identity is used twice; the join never picks one value.
    let collisions: [SyncDot]
}

/// Everything one Mac knows about the synced settings: which changes it has seen
/// (``context``), the changes that are still current (``registers``) and the sets.
///
/// A unit's register holds every entry that no later change has overwritten. Normally that
/// is one entry; after two Macs changed a unit without seeing each other it is both, and
/// the engine shows both until someone chooses. ``join(_:_:)`` is commutative, associative
/// and idempotent, so the order in which replicas arrive, duplicates and skipped
/// intermediate states change nothing.
///
/// The initializer normalizes: entries are sorted by dot and deduplicated by identity,
/// empty registers are absent and sets are sorted, unique and capped.
nonisolated struct SyncReplica: Hashable, Sendable {
    /// Every dot this replica has seen.
    let context: SyncContext
    /// The current entries per unit, sorted by dot; never empty.
    let registers: [SyncUnitKey: [SyncEntry]]
    /// Named sets of strings, sorted and unique.
    let sets: [String: [String]]

    /// A replica that has seen nothing.
    static let empty = SyncReplica()

    init(context: SyncContext = .empty, registers: [SyncUnitKey: [SyncEntry]] = [:], sets: [String: [String]] = [:]) {
        self.context = context
        var normalized: [SyncUnitKey: [SyncEntry]] = [:]
        for (key, entries) in registers {
            let sorted = Self.normalize(entries)
            if !sorted.isEmpty {
                normalized[key] = sorted
            }
        }
        self.registers = normalized
        self.sets = sets.mapValues(Self.normalize(set:))
    }

    /// The units that hold at least one entry, sorted.
    var keys: [SyncUnitKey] {
        registers.keys.sorted()
    }

    /// The current entries of the unit, sorted by dot: one normally, several when changes
    /// were made without seeing each other. Deletions are entries too.
    func live(_ key: SyncUnitKey) -> [SyncEntry] {
        registers[key] ?? []
    }

    /// The different payloads among the current entries of the unit, in the order of their
    /// first entry.
    func distinctValues(_ key: SyncUnitKey) -> [SyncPayload] {
        var seen: Set<SyncDigest> = []
        var payloads: [SyncPayload] = []
        for entry in live(key) where seen.insert(entry.payload.digest).inserted {
            payloads.append(entry.payload)
        }
        return payloads
    }

    /// This replica with `entry` as the only current entry of `key`: a local change that
    /// has seen every current entry of the unit. The entry's dot joins the context.
    func setting(_ key: SyncUnitKey, to entry: SyncEntry) -> SyncReplica {
        var registers = registers
        registers[key] = [entry]
        return SyncReplica(context: context.adding(entry.dot), registers: registers, sets: sets)
    }

    // MARK: Join

    /// Joins two replicas.
    ///
    /// The context is the pointwise maximum. An entry of one replica stays unless the other
    /// replica has seen its dot and no longer holds it: then the other replica replaced or
    /// removed it. The same dot with two different payloads keeps both entries and is
    /// reported as a collision. Sets join by union, capped at
    /// ``SyncDeviceFile/maximumSetElements`` elements by the smallest SHA-256.
    static func join(_ lhs: SyncReplica, _ rhs: SyncReplica) -> SyncJoinResult {
        var registers: [SyncUnitKey: [SyncEntry]] = [:]
        var collisions: Set<SyncDot> = []
        let keys = Set(lhs.registers.keys).union(rhs.registers.keys).sorted()
        for key in keys {
            let left = lhs.registers[key] ?? []
            let right = rhs.registers[key] ?? []
            let leftDots = Set(left.map(\.dot))
            let rightDots = Set(right.map(\.dot))
            var kept: [SyncEntry] = []
            kept += left.filter { rightDots.contains($0.dot) || !rhs.context.covers($0.dot) }
            kept += right.filter { leftDots.contains($0.dot) || !lhs.context.covers($0.dot) }
            let entries = normalize(kept)
            guard !entries.isEmpty else {
                continue
            }
            registers[key] = entries
            for (earlier, later) in zip(entries, entries.dropFirst()) where earlier.dot == later.dot {
                collisions.insert(earlier.dot)
            }
        }
        var sets: [String: [String]] = [:]
        for name in Set(lhs.sets.keys).union(rhs.sets.keys).sorted() {
            sets[name] = normalize(set: (lhs.sets[name] ?? []) + (rhs.sets[name] ?? []))
        }
        let replica = SyncReplica(context: lhs.context.merging(rhs.context), registers: registers, sets: sets)
        return SyncJoinResult(replica: replica, collisions: collisions.sorted())
    }

    /// Sorts entries by identity and keeps one entry per identity.
    private static func normalize(_ entries: [SyncEntry]) -> [SyncEntry] {
        var byIdentity: [SyncEntry.Identity: SyncEntry] = [:]
        for entry in entries {
            let identity = entry.identity
            byIdentity[identity] = byIdentity[identity].map { SyncEntry.preferred($0, entry) } ?? entry
        }
        return byIdentity.keys.sorted().compactMap { byIdentity[$0] }
    }

    /// Sorts a set, removes duplicates and, above the cap, keeps the elements with the
    /// smallest SHA-256 of their UTF-8 bytes. Keeping the smallest hashes is itself a join:
    /// the cap of a union equals the cap of the union of the caps.
    private static func normalize(set: [String]) -> [String] {
        var elements = Array(Set(set))
        if elements.count > SyncDeviceFile.maximumSetElements {
            let hashed = elements.map { (hash: SyncDigest.hash(Array($0.utf8)), element: $0) }
            elements = hashed
                .sorted { $0.hash == $1.hash ? $0.element.utf8.lexicographicallyPrecedes($1.element.utf8) : $0.hash < $1.hash }
                .prefix(SyncDeviceFile.maximumSetElements)
                .map(\.element)
        }
        return elements.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    // MARK: Digest

    /// The canonical digest of the whole replica: equal replicas digest equal.
    var digest: SyncDigest {
        let contextValues = context.macs.map { mac in
            SyncValue.array([.string(mac.rawValue), .integer(Int64(clamping: context[mac]))])
        }
        let registerValues = keys.map { key in
            let name: [SyncValue] = switch key {
            case .whole(let name):
                [.string("whole"), .string(name)]
            case .split(let family, let item):
                [.string("split"), .string(family), .string(item)]
            }
            return SyncValue.array(name + [.array(live(key).map { .dictionary($0.canonicalFields) })])
        }
        let setValues = sets.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { name in
            SyncValue.array([.string(name), .array((sets[name] ?? []).map { .string($0) })])
        }
        var bytes: [UInt8] = []
        SyncValue.array([.array(contextValues), .array(registerValues), .array(setValues)]).appendCanonicalEncoding(to: &bytes)
        return SyncDigest.hash(bytes)
    }
}
