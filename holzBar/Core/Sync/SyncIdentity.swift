//
//  SyncIdentity.swift
//  holzBar
//

import Foundation

/// What the identity check decides for this launch.
nonisolated enum SyncIdentityDecision: Equatable, Sendable {
    /// The stored identity is this Mac's: keep it.
    case same(SyncMacID)
    /// The defaults were copied from another Mac or account, or the hash predates the uid
    /// binding: use `new`. `legacyID` is the identity that was stored, kept so this Mac still
    /// recognizes its own writes under the old identity (`SettingsSyncLegacyDeviceID`).
    case rotated(new: SyncMacID, legacyID: String?)
    /// There is no identity yet: use this one.
    case firstRun(SyncMacID)
    /// The hardware UUID cannot be read, so the stored identity cannot be checked: keep it.
    /// `nil` when none of the stored identities is usable; the caller makes one.
    case noHardwareID(SyncMacID?)
}

/// A sign that this Mac's identity is used twice (analysis section 4.5).
nonisolated enum SyncCollisionSignal: Hashable, Sendable {
    /// A file holds an own dot with a payload other than the one this Mac's state holds.
    case ownDotWithOtherPayload(SyncDot)
    /// The own file carries another installation nonce.
    case otherInstallation
    /// A conflict copy of the own file.
    case conflictCopy
}

/// The identity, counter and collision rules of this Mac (analysis section 4.5).
///
/// Every function is pure: the caller reads the hardware, the preferences and the files and
/// persists what these functions decide.
nonisolated enum SyncIdentity {
    /// How long the same refusal must last, with the file unchanged, to be lasting.
    static let lastingRefusalInterval: TimeInterval = 10 * 60

    // MARK: Identity

    /// Decides which identity this Mac uses.
    ///
    /// The identity is bound to the hardware UUID and the user ID by a salted hash
    /// (``SettingsSyncDevice/hardwareHash(of:uid:salt:)``), so a clone, a restore on other
    /// hardware or a copied account gets its own identity. A hash computed without the uid
    /// (0.0.6, 0.0.7-beta1 and beta2) or a missing hash does not match once; the identity
    /// then rotates and the old one is kept as the legacy ID, and the next launch finds the
    /// new hash.
    static func check(
        storedID: String?,
        storedHash: String?,
        salt: Data?,
        hardwareID: String?,
        uid: UInt32,
        makeID: () -> SyncMacID
    ) -> SyncIdentityDecision {
        guard let storedID else {
            return .firstRun(makeID())
        }
        let stored = SyncMacID(storedID)
        guard let hardwareID else {
            return .noHardwareID(stored)
        }
        guard let stored else {
            return .rotated(new: makeID(), legacyID: storedID)
        }
        switch SettingsSyncDevice.identity(storedHash: storedHash, salt: salt, hardwareID: hardwareID, uid: uid) {
        case .same:
            return .same(stored)
        case .firstSeen, .otherMac, .unknown:
            return .rotated(new: makeID(), legacyID: storedID)
        }
    }

    // MARK: Counters

    /// The next counter: above the state's counter, the mirror in the defaults, the high-water
    /// mark in the caches and the highest own counter seen in any file, and at least the unix
    /// seconds, so a restored state or a clock that steps back never repeats a counter.
    ///
    /// - Returns: The counter, or `nil` above 2^34 (``SyncDeviceFile/maximumCounter``): the
    ///   Mac then has to re-identify.
    static func nextCounter(stateCounter: UInt64, mirror: UInt64, highWater: UInt64, unixSeconds: UInt64, maxSeenSelf: UInt64) -> UInt64? {
        var next = unixSeconds
        for floor in [stateCounter, mirror, highWater, maxSeenSelf] {
            let (above, overflow) = floor.addingReportingOverflow(1)
            guard !overflow else {
                return nil
            }
            next = max(next, above)
        }
        return next <= SyncDeviceFile.maximumCounter ? next : nil
    }

    /// The own live dots above the published counter that `context` covers.
    ///
    /// Nobody can legitimately have seen a dot this Mac never published, so such a dot was
    /// minted twice: the identity is used by two installations.
    static func suspectReusedDots(in state: SyncState, coveredBy context: SyncContext) -> [SyncDot] {
        var dots = Set<SyncDot>()
        for entries in state.replica.registers.values {
            for entry in entries where entry.dot.mac == state.mac && entry.dot.n > state.publishedCounter && context.covers(entry.dot) {
                dots.insert(entry.dot)
            }
        }
        return dots.sorted()
    }

    /// The own live dots that a file's replica covers although it cannot have seen them.
    ///
    /// Two signs say that this identity is used by two installations. A dot above the published counter
    /// that the replica covers was never published, so nobody saw it. And a dot that the replica covers
    /// while it holds no entry at all for the unit never reached it either: a replica that has seen an entry
    /// holds some entry for its unit, because a later entry replaces the one before and a deletion is an
    /// entry too. The first sign is no sign when this installation's own file explains the dot.
    ///
    /// - Parameters:
    ///   - publishedCounter: What this state had published before it read the folder; the state's own by default.
    ///     Reading the own file raises the state's counter, and a dot that the file explains is no reuse, but a dot
    ///     below the file's counter that the file does not explain is the very case of a restore with a clock set back.
    ///   - ownFile: The replica of this installation's own file, if it was read. A dot it holds, or one that it
    ///     supersedes with a later entry of this Mac's for the same unit, is published.
    static func suspectCollidingDots(
        in state: SyncState,
        coveredBy file: SyncReplica,
        publishedCounter: UInt64? = nil,
        ownFile: SyncReplica? = nil
    ) -> [SyncDot] {
        let published = publishedCounter ?? state.publishedCounter
        var dots = Set<SyncDot>()
        for (key, entries) in state.replica.registers {
            for entry in entries where entry.dot.mac == state.mac && file.context.covers(entry.dot) {
                let neverSeen = file.live(key).isEmpty
                guard entry.dot.n > published || neverSeen else {
                    continue
                }
                if !neverSeen, let ownFile, ownFile.live(key).contains(where: { $0.dot.mac == state.mac && $0.dot.n >= entry.dot.n }) {
                    continue
                }
                dots.insert(entry.dot)
            }
        }
        return dots.sorted()
    }

    // MARK: Collisions

    /// The signs in a device file that this Mac's identity is used twice.
    ///
    /// - Parameters:
    ///   - ownMac: This Mac's identity.
    ///   - ownNonce: The nonce of this installation.
    ///   - file: The decoded device file.
    ///   - fileName: The file's name, with its extension.
    ///   - state: This Mac's state.
    static func collisionSignals(
        ownMac: SyncMacID,
        ownNonce: String,
        file: SyncDeviceFile.Contents,
        fileName: String,
        state: SyncState
    ) -> [SyncCollisionSignal] {
        var signals: [SyncCollisionSignal] = []
        let ownName = ownMac.rawValue + ".plist"
        if file.mac == ownMac, file.installation != ownNonce {
            signals.append(.otherInstallation)
        }
        // A copy named after this Mac, such as "<ID> 2.plist" or "<ID> (conflicted copy).plist",
        // or an own file under another name.
        if fileName != ownName, fileName.hasPrefix(ownMac.rawValue) || file.mac == ownMac {
            signals.append(.conflictCopy)
        }
        // An own dot that this Mac's state holds, with another payload in the file.
        var known: [SyncDot: Set<SyncEntry.Identity>] = [:]
        for entries in state.replica.registers.values {
            for entry in entries where entry.dot.mac == ownMac {
                known[entry.dot, default: []].insert(entry.identity)
            }
        }
        var mismatched = Set<SyncDot>()
        for entries in file.replica.registers.values {
            for entry in entries where entry.dot.mac == ownMac {
                if let held = known[entry.dot], !held.contains(entry.identity) {
                    mismatched.insert(entry.dot)
                }
            }
        }
        signals.append(contentsOf: mismatched.sorted().map { .ownDotWithOtherPayload($0) })
        return signals
    }

    // MARK: Refusals

    /// Whether a refusal lasts: the same refusal for at least ten minutes while the file's
    /// size and modification date stay unchanged. A file that is empty, still downloading or
    /// dataless (unreadable) is never lasting.
    static func isLastingRefusal(_ record: SyncRefusalRecord, now: Date, size: Int, modified: Date?) -> Bool {
        guard record.reason != SyncRefusal.unreadable.code, size > 0 else {
            return false
        }
        guard record.size == size, record.modified == modified else {
            return false
        }
        return now.timeIntervalSince(record.firstSeen) >= lastingRefusalInterval
    }

    // MARK: Re-identification

    /// The state of this Mac under a new identity.
    ///
    /// The replica, `applied` and `baseline` stay: a copied state is a valid causal state and
    /// dots are globally unique, so nothing is lost. The old identity is remembered, and every
    /// unit that holds a suspect dot becomes `preexisting`, so it is asked about where the
    /// group differs and published where the group has nothing, never dropped. The own file
    /// is a new file, so what was last published is forgotten.
    static func reidentified(_ state: SyncState, newMac: SyncMacID, newNonce: String, suspect: [SyncDot]) -> SyncState {
        var result = state
        let suspectDots = Set(suspect)
        if state.mac != newMac {
            if !result.previousMacIDs.contains(state.mac) {
                result.previousMacIDs.append(state.mac)
            }
            result.mac = newMac
        }
        result.nonce = newNonce
        result.published = SyncPublishedRecord()
        for (key, entries) in state.replica.registers where entries.contains(where: { suspectDots.contains($0.dot) }) {
            result.localOrigin[key] = .preexisting
        }
        return result
    }
}
