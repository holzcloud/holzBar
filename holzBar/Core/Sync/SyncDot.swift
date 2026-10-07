//
//  SyncDot.swift
//  holzBar
//

import Foundation

/// The identity of one Mac in the sync folder: an upper-case UUID, such as the existing
/// `SettingsSyncDeviceID`. It is also the name of the Mac's device file.
nonisolated struct SyncMacID: Hashable, Comparable, Sendable {
    /// The identity as 36 characters, upper-case hexadecimal in the groups 8-4-4-4-12.
    let rawValue: String

    /// The length of an identity in characters.
    static let length = 36

    /// Returns the identity named by `string`, or `nil` unless it is exactly an upper-case
    /// UUID.
    init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == Self.length else {
            return nil
        }
        for (index, byte) in bytes.enumerated() {
            if [8, 13, 18, 23].contains(index) {
                guard byte == UInt8(ascii: "-") else {
                    return nil
                }
            } else {
                let isDigit = (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                let isUpperHex = (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte)
                guard isDigit || isUpperHex else {
                    return nil
                }
            }
        }
        rawValue = string
    }

    /// The identity of `uuid`.
    init(_ uuid: UUID) {
        rawValue = uuid.uuidString
    }

    static func < (lhs: SyncMacID, rhs: SyncMacID) -> Bool {
        lhs.rawValue.utf8.lexicographicallyPrecedes(rhs.rawValue.utf8)
    }
}

/// The identity of one change: the Mac that made it and that Mac's counter. Dots are
/// globally unique, because each Mac only mints its own and counts up.
nonisolated struct SyncDot: Hashable, Comparable, Sendable {
    let mac: SyncMacID
    let n: UInt64

    static func < (lhs: SyncDot, rhs: SyncDot) -> Bool {
        lhs.mac == rhs.mac ? lhs.n < rhs.n : lhs.mac < rhs.mac
    }
}

/// Every dot a replica has seen, as the highest counter per Mac.
///
/// A Mac mints its counters in order and a replica adopts a Mac's changes only whole, so
/// the highest counter stands for all the lower ones.
nonisolated struct SyncContext: Hashable, Sendable {
    /// The highest counter per Mac. A Mac with counter zero is absent, so equal contexts
    /// are equal values.
    private let counters: [SyncMacID: UInt64]

    /// A context that has seen nothing.
    static let empty = SyncContext(counters: [:])

    init(counters: [SyncMacID: UInt64]) {
        self.counters = counters.filter { $0.value > 0 }
    }

    /// The highest counter seen from `mac`, zero if none.
    subscript(_ mac: SyncMacID) -> UInt64 {
        counters[mac] ?? 0
    }

    /// Whether this context has seen `dot`.
    func covers(_ dot: SyncDot) -> Bool {
        self[dot.mac] >= dot.n
    }

    /// The context that has seen everything either context has seen.
    func merging(_ other: SyncContext) -> SyncContext {
        SyncContext(counters: counters.merging(other.counters) { max($0, $1) })
    }

    /// The context that has also seen `dot`.
    func adding(_ dot: SyncDot) -> SyncContext {
        guard !covers(dot) else {
            return self
        }
        var counters = counters
        counters[dot.mac] = dot.n
        return SyncContext(counters: counters)
    }

    /// The Macs this context has seen, sorted.
    var macs: [SyncMacID] {
        counters.keys.sorted()
    }

    /// Whether the context has seen nothing.
    var isEmpty: Bool {
        counters.isEmpty
    }
}

/// What a change set a unit to.
nonisolated enum SyncPayload: Hashable, Sendable {
    /// The unit was set to a value.
    case value(SyncValue)
    /// The unit was removed.
    case deleted

    /// The digest of the payload; a deletion digests differently from every value.
    var digest: SyncDigest {
        switch self {
        case .value(let value):
            value.digest
        case .deleted:
            Self.deletedDigest
        }
    }

    private static let deletedDigest = SyncDigest.hash(Array("deleted".utf8) + [0xFF])
}

/// One change of one unit.
///
/// Entries are equal for the join when their dot and the digest of their payload are equal
/// (``identity``); the date is for display only and never decides anything. Fields of an
/// entry this build does not know are kept in ``extra`` and written back unchanged.
nonisolated struct SyncEntry: Hashable, Sendable {
    let dot: SyncDot
    /// When the change was made, for display only.
    let at: Date
    let payload: SyncPayload
    /// The fields of the entry this build does not know.
    let extra: [String: SyncValue]

    init(dot: SyncDot, at: Date, payload: SyncPayload, extra: [String: SyncValue] = [:]) {
        self.dot = dot
        self.at = at
        self.payload = payload
        self.extra = extra
    }

    /// What makes two entries the same for the join.
    nonisolated struct Identity: Hashable, Comparable, Sendable {
        let dot: SyncDot
        let payload: SyncDigest

        static func < (lhs: Identity, rhs: Identity) -> Bool {
            lhs.dot == rhs.dot ? lhs.payload < rhs.payload : lhs.dot < rhs.dot
        }
    }

    var identity: Identity {
        Identity(dot: dot, payload: payload.digest)
    }

    /// The value, or `nil` for a deletion.
    var value: SyncValue? {
        if case .value(let value) = payload {
            return value
        }
        return nil
    }

    /// The digest of the whole entry, display fields included.
    var digest: SyncDigest {
        var bytes: [UInt8] = []
        SyncValue.dictionary(canonicalFields).appendCanonicalEncoding(to: &bytes)
        return SyncDigest.hash(bytes)
    }

    /// The entry as a value tree, in a fixed shape for digests.
    var canonicalFields: [String: SyncValue] {
        [
            "mac": .string(dot.mac.rawValue),
            "n": .integer(Int64(clamping: dot.n)),
            "at": .date(at),
            "payload": .string(payload.digest.hex),
            "extra": .dictionary(extra),
        ]
    }

    /// Of two entries with the same identity, the one every replica keeps: the later date,
    /// then the larger digest of the extra fields. The choice does not depend on the order
    /// of the arguments, so the join stays commutative.
    static func preferred(_ lhs: SyncEntry, _ rhs: SyncEntry) -> SyncEntry {
        if lhs.at != rhs.at {
            return lhs.at > rhs.at ? lhs : rhs
        }
        return SyncValue.dictionary(lhs.extra).digest >= SyncValue.dictionary(rhs.extra).digest ? lhs : rhs
    }
}
