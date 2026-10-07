//
//  SyncMerge.swift
//  holzBar
//

import Foundation

/// What merging one read of the folder into the state gave.
nonisolated struct SyncMergeResult: Sendable {
    /// The state after the merge.
    var state: SyncState
    /// Whether the replica changed, so the new entries have to be relayed.
    var replicaChanged: Bool
    /// Whether this Mac took a new identity because its old one was used twice.
    var reidentified: Bool
    /// The Macs whose files are still dataless and have to be downloaded.
    var downloads: [SyncMacID]
    /// Whether the own file is missing or is not what this Mac last wrote.
    var needsHealing: Bool
}

/// Joins what a read of the folder found into the state (analysis sections 4.5 and 4.6.1).
///
/// A join only adds: nothing is removed because a file lacks it, only because another file's
/// context has seen it and no longer holds it. A file that is unreadable, too large, partial,
/// dataless or refused is left out whole and is never read as missing. Conflict names can hold
/// a computer name, so the engine never sees a file name and the refusals are recorded by Mac
/// identity only; nothing here may log a name.
nonisolated enum SyncMerge {
    static func merge(_ read: SyncFolderRead, into state: SyncState, environment: SyncEnvironment) -> SyncMergeResult {
        var state = state
        state.session.availability = read.availability
        guard read.availability == .available else {
            // The folder is away: only the status changes, nothing is read as missing.
            return SyncMergeResult(state: state, replicaChanged: false, reidentified: false, downloads: [], needsHealing: false)
        }
        state.session.skippedFiles = read.skipped
        let original = state.replica.digest
        let files = classify(read, state: state)
        let ownRefusalLasting = recordRefusals(files, state: &state, environment: environment)
        state.session.waitingFiles = files.waiting

        // The identity checks run before any file is joined, over every file, so that one
        // re-identification covers every suspect dot.
        // What this installation's own file holds is published, so it is no evidence that a dot
        // was minted twice, even when another Mac has read it already (Sigma restored alone).
        if let ownFile = files.contents.first(where: { $0.mac == state.mac && $0.installation == state.nonce }) {
            let signals = SyncIdentity.collisionSignals(
                ownMac: state.mac,
                ownNonce: state.nonce,
                file: ownFile,
                fileName: ownFile.mac.rawValue + ".plist",
                state: state
            )
            if signals.isEmpty {
                state.publishedCounter = max(state.publishedCounter, ownFile.replica.context[state.mac])
            }
        }
        var reidentified = false
        var blocked = Set<SyncMacID>()
        var suspects = Set<SyncDot>()
        var signalled = files.ownConflictCopy || ownRefusalLasting
        for file in files.contents {
            let ownSameInstallation = file.mac == state.mac && file.installation == state.nonce
            let signals = SyncIdentity.collisionSignals(
                ownMac: state.mac,
                ownNonce: state.nonce,
                file: file,
                fileName: file.mac.rawValue + ".plist",
                state: state
            )
            for signal in signals {
                if case .ownDotWithOtherPayload(let dot) = signal {
                    suspects.insert(dot)
                }
            }
            if !signals.isEmpty {
                signalled = true
                blocked.insert(file.mac)
            }
            if !ownSameInstallation {
                let reused = SyncIdentity.suspectReusedDots(in: state, coveredBy: file.replica.context)
                if !reused.isEmpty {
                    signalled = true
                    suspects.formUnion(reused)
                    blocked.insert(file.mac)
                }
            }
        }
        var own = ownStatusBeforeJoin(files)
        if signalled, let fresh = environment.freshIdentity {
            state = SyncIdentity.reidentified(state, newMac: fresh.mac, newNonce: fresh.nonce, suspect: suspects.sorted())
            reidentified = true
            blocked = []
            own = .absent
        }

        // The join.
        var joinedOwn: SyncDeviceFile.Contents?
        for file in files.contents.sorted(by: { $0.mac < $1.mac }) where !blocked.contains(file.mac) {
            state.replica = SyncReplica.join(state.replica, file.replica).replica
            if file.mac == state.mac {
                joinedOwn = file
            }
        }
        // The own file is the Mac's own history: its dots are published, and the counter floor
        // rises above the highest own counter seen.
        let seen = state.replica.context[state.mac]
        state.counter = max(state.counter, seen)
        if let joinedOwn {
            state.publishedCounter = max(state.publishedCounter, joinedOwn.replica.context[state.mac])
            let dominated = SyncReplica.join(state.replica, joinedOwn.replica).replica == state.replica
            own = .read(digest: joinedOwn.replica.digest, isDominated: dominated)
        }
        state.session.ownFile = own
        updateLegacy(read.legacy, state: &state, environment: environment)

        let healing = needsHealing(own, state: state)
        return SyncMergeResult(
            state: state,
            replicaChanged: state.replica.digest != original,
            reidentified: reidentified,
            downloads: files.downloads,
            needsHealing: healing
        )
    }

    // MARK: Classification

    private struct Classified {
        var contents: [SyncDeviceFile.Contents] = []
        var refused: [(mac: SyncMacID, outcome: SyncFileOutcome, refusal: SyncRefusal)] = []
        var downloads: [SyncMacID] = []
        var waiting = 0
        var ownConflictCopy = false
        /// How the own file showed in the read: nothing, or what the host found.
        var ownOutcome: SyncFileState?
    }

    private static func classify(_ read: SyncFolderRead, state: SyncState) -> Classified {
        var result = Classified()
        let ordered = read.files.sorted { left, right in
            switch (left.macID, right.macID) {
            case (let leftMac?, let rightMac?):
                leftMac < rightMac
            case (_?, nil):
                true
            default:
                false
            }
        }
        for file in ordered {
            if file.macID == state.mac {
                result.ownOutcome = file.state
            }
            switch file.state {
            case .contents(let contents):
                result.contents.append(contents)
            case .refused(let refusal):
                if let mac = file.macID {
                    result.refused.append((mac, file, refusal))
                }
            case .dataless:
                result.waiting += 1
                if let mac = file.macID {
                    result.downloads.append(mac)
                }
            case .pending:
                result.waiting += 1
            case .conflictCopy(let owner):
                if owner == state.mac {
                    result.ownConflictCopy = true
                }
            }
        }
        return result
    }

    /// Keeps the refusals of this read, keyed by Mac identity: a refusal that continues keeps
    /// the date it was first seen, one that is gone is forgotten.
    ///
    /// - Returns: Whether the own file stays unreadable for a lasting reason.
    private static func recordRefusals(_ files: Classified, state: inout SyncState, environment: SyncEnvironment) -> Bool {
        var refusals: [String: SyncRefusalRecord] = [:]
        var ownLasting = false
        for item in files.refused {
            let key = item.mac.rawValue
            var record = SyncRefusalRecord(reason: item.refusal.code, size: item.outcome.size, modified: item.outcome.modified, firstSeen: environment.now)
            if let known = state.refusals[key], known.reason == record.reason, known.size == record.size, known.modified == record.modified {
                record.firstSeen = known.firstSeen
            }
            refusals[key] = record
            if item.mac == state.mac, SyncIdentity.isLastingRefusal(record, now: environment.now, size: item.outcome.size, modified: item.outcome.modified) {
                ownLasting = true
            }
        }
        state.refusals = refusals
        // An own file that stays unreadable for a lasting reason is never overwritten: this Mac
        // publishes under a new identity instead.
        return ownLasting
    }

    /// What the read says about the own file before the join: absent when the folder lists
    /// none, otherwise unread until the join has read it.
    private static func ownStatusBeforeJoin(_ files: Classified) -> SyncOwnFileStatus {
        files.ownOutcome == nil ? .absent : .unread
    }

    /// Whether the own file is missing or no longer what this Mac last wrote.
    private static func needsHealing(_ own: SyncOwnFileStatus, state: SyncState) -> Bool {
        switch own {
        case .absent:
            return state.published.replicaDigest != nil
        case .read(let digest, _):
            guard let written = state.published.ownFileDigest else {
                return false
            }
            return digest != written
        case .unread:
            return false
        }
    }

    // MARK: Legacy

    /// Keeps what this Mac knows about the legacy file up to date: when its identity digest
    /// differs from the one recorded at founding or joining and its writer is not this Mac's
    /// legacy ID, an older holzBar still uses the folder. Only a display horizon, never a
    /// decision.
    private static func updateLegacy(_ outcome: SyncLegacyOutcome?, state: inout SyncState, environment: SyncEnvironment) {
        guard case .file(let file)? = outcome, let founding = state.legacy.foundingDigest else {
            return
        }
        if file.identityDigest != founding, !file.isWritten(byLegacyDeviceID: state.legacy.legacyDeviceID) {
            state.legacy.lastLegacyChange = file.modified ?? environment.now
        }
    }
}
