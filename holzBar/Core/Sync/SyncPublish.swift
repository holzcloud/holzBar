//
//  SyncPublish.swift
//  holzBar
//

import Foundation

/// Why the engine asks whether to write its own file.
nonisolated enum SyncWriteTrigger: Hashable, Sendable {
    /// An own change, or an answer: two seconds after the change.
    case ownChange
    /// Other Macs' values to relay: ten seconds after a merge changed the replica.
    case relay
    /// The own file was missing, older, damaged or from another installation.
    case healing
    /// The app quits.
    case quit
    /// An hour after this Mac learned an application.
    case learned
}

/// Why nothing is written.
nonisolated enum SyncWriteSkip: Hashable, Sendable {
    case disabled
    case pendingJoin
    case folderUnavailable
    /// The own file was not read in this session.
    case ownFileNotRead
    /// The own file holds something the state does not hold.
    case ownFileNotDominated
    /// There is nothing to publish yet.
    case nothingToPublish
    /// The replica is what was published and the own file is intact.
    case unchanged
    /// The encoded file would exceed one MiB; the previous file stays.
    case tooLarge
}

/// What the host must find in the own file before it replaces it.
nonisolated enum SyncOwnFileExpectation: Hashable, Sendable {
    /// There is no own file.
    case absent
    /// The own file is the one this session read; `digest` is the digest of its replica.
    case readThisSession(digest: SyncDigest)
    /// No check: only a control engine without ``SyncGuards/ownFileReadFirst`` asks for this.
    case unchecked
}

/// One write of the own device file.
nonisolated struct SyncWriteRequest: Hashable, Sendable {
    /// The whole file: the state's replica with relays and pass-through included.
    var contents: SyncDeviceFile.Contents
    var expectation: SyncOwnFileExpectation
    /// The counter this write publishes.
    var counter: UInt64
    /// The digest of the replica being written.
    var replicaDigest: SyncDigest
}

nonisolated enum SyncWriteDecision: Sendable {
    case none(SyncWriteSkip)
    case write(SyncWriteRequest)
}

/// What a write that read back intact produced.
nonisolated struct SyncWriteReceipt: Hashable, Sendable {
    var counter: UInt64
    /// The digest of the replica that was written.
    var replicaDigest: SyncDigest
    /// The digest of the replica of the file as read back.
    var fileDigest: SyncDigest
}

nonisolated enum SyncWriteFailure: Hashable, Sendable {
    /// The folder or the file could not be reached in time.
    case unavailable
    /// The own file was not what the request expected, so nothing was written.
    case ownFileChanged
    /// The encoding exceeds the limit.
    case tooLarge
}

nonisolated enum SyncWriteResult: Hashable, Sendable {
    /// The file was written and reads back intact.
    case verified(SyncWriteReceipt)
    /// The file was written but could not be read back.
    case unverified
    case failed(SyncWriteFailure)
}

/// When and what this Mac writes into its own device file (analysis section 4.6.5).
///
/// The file holds the state's whole replica. The context claims only dots this Mac has seen and
/// the file carries every live entry that context covers, so a reader that finds an entry
/// missing knows it was superseded. Entries of other Macs, unknown units and unknown families
/// are written unchanged. Dates are for display only and decide nothing.
nonisolated enum SyncPublish {
    static func decision(state: SyncState, environment: SyncEnvironment, trigger: SyncWriteTrigger) -> SyncWriteDecision {
        guard state.isEnabled else {
            return .none(.disabled)
        }
        guard state.pendingJoin == nil else {
            return .none(.pendingJoin)
        }
        guard state.session.availability == .available else {
            return .none(.folderUnavailable)
        }
        let replica = state.replica
        let digest = replica.digest
        let own = state.session.ownFile
        let expectation: SyncOwnFileExpectation
        if environment.guards.contains(.ownFileReadFirst) {
            switch own {
            case .unread:
                return .none(.ownFileNotRead)
            case .absent:
                expectation = .absent
            case .read(let fileDigest, let isDominated):
                guard isDominated else {
                    return .none(.ownFileNotDominated)
                }
                expectation = .readThisSession(digest: fileDigest)
            }
        } else {
            expectation = .unchecked
        }
        if replica.registers.isEmpty, replica.context.isEmpty, replica.sets.isEmpty, state.published.replicaDigest == nil {
            return .none(.nothingToPublish)
        }
        var needsWrite = digest != state.published.replicaDigest
        switch own {
        case .absent:
            needsWrite = true
        case .read(let fileDigest, _):
            needsWrite = needsWrite || fileDigest != digest
        case .unread:
            break
        }
        guard needsWrite else {
            return .none(.unchanged)
        }
        let contents = SyncDeviceFile.Contents(
            unitTable: environment.table.version,
            mac: state.mac,
            installation: state.nonce,
            written: environment.now,
            replica: replica
        )
        // The encoded size is checked before anything is written: above the limit the previous
        // file stays and Settings warns. Leaving a unit out is not allowed, because the file's
        // context would then cover an entry the file lacks, and readers would delete it.
        let encoded: Data
        do throws(SyncRefusal) {
            encoded = try SyncDeviceFile.encode(contents)
        } catch {
            return .none(.tooLarge)
        }
        guard encoded.count <= SyncDeviceFile.maximumWriteSize else {
            return .none(.tooLarge)
        }
        let counter = max(state.counter, replica.context[state.mac])
        return .write(SyncWriteRequest(contents: contents, expectation: expectation, counter: counter, replicaDigest: digest))
    }

    /// The state after the host reported a write. Only a write that read back intact moves what
    /// was published; a failed or unverifiable one keeps it, so the next check writes again.
    static func apply(_ result: SyncWriteResult, to state: SyncState) -> SyncState {
        var state = state
        switch result {
        case .verified(let receipt):
            state.publishedCounter = max(state.publishedCounter, receipt.counter)
            state.published = SyncPublishedRecord(replicaDigest: receipt.replicaDigest, ownFileDigest: receipt.fileDigest)
            state.session.ownFile = .read(digest: receipt.fileDigest, isDominated: true)
        case .unverified:
            state.session.ownFile = .unread
        case .failed(let failure):
            if failure == .ownFileChanged {
                state.session.ownFile = .unread
            }
        }
        return state
    }
}
