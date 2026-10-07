//
//  SimFolderIO.swift
//  holzBar
//

import Foundation
@testable import HolzBarCore

/// What the simulator's I/O performer found: the folder read the engine gets, and the provider
/// version of every device file it decoded, so the adapter can report what it ingested.
struct SimFolderReadResult {
    var read: SyncFolderRead
    var versions: [SyncMacID: Int]
}

/// The simulator's I/O performer for the redesigned engine. It does what the app's file actor
/// does, on the simulated folder: list `holzBar/Macs/`, apply the name filter and the file
/// limit, read each file with the bound, tell dataless, partial and stalled reads apart, decode
/// with ``SyncDeviceFile/decode(_:fileName:)`` and hand the engine a ``SyncFolderRead``; and
/// write the own file, read it back and report. It reads the legacy file only when the request
/// asks for it.
///
/// The simulated provider carries no modification dates, so the file limit keeps the first
/// files by name instead of the most recently modified ones.
enum SimFolderIO {
    static let directory = "holzBar/Macs"
    static let legacyPath = "holzBar/Settings.plist"

    static func path(of mac: SyncMacID) -> String {
        "\(directory)/\(mac.rawValue).plist"
    }

    // MARK: Read

    static func read(_ request: SyncReadRequest, _ context: inout SimMacContext) -> SimFolderReadResult {
        let names: [String]
        switch context.list(directory) {
        case .names(let listed):
            names = listed
        case .notMounted, .timedOut:
            return SimFolderReadResult(read: SyncFolderRead(availability: .unavailable), versions: [:])
        }
        var candidates: [String] = []
        var files: [SyncFileOutcome] = []
        for name in names.sorted() {
            if SyncDeviceFile.isDeviceFileName(name) {
                candidates.append(name)
            } else if let owner = SyncDeviceFile.conflictCopyOwner(fileName: name, knownMacs: request.knownMacs) {
                files.append(SyncFileOutcome(macID: nil, state: .conflictCopy(owner: owner)))
            }
        }
        let skipped = max(0, candidates.count - request.maximumFiles)
        var versions: [SyncMacID: Int] = [:]
        for name in candidates.prefix(request.maximumFiles) {
            guard let outcome = readFile(named: name, &context) else {
                continue
            }
            files.append(outcome.file)
            if let version = outcome.version, let mac = outcome.file.macID {
                versions[mac] = version
            }
        }
        let legacy = request.legacy == .none ? nil : readLegacy(request.legacy, &context)
        return SimFolderReadResult(read: SyncFolderRead(availability: .available, files: files, legacy: legacy, skipped: skipped), versions: versions)
    }

    private static func readFile(named name: String, _ context: inout SimMacContext) -> (file: SyncFileOutcome, version: Int?)? {
        guard let mac = SyncDeviceFile.macID(fromFileName: name) else {
            return nil
        }
        let result = context.read("\(directory)/\(name)", maximumBytes: SyncDeviceFile.maximumReadSize)
        let wasPartial = context.readLog.last?.wasPartial ?? false
        switch result {
        case .absent:
            return nil
        case .notLocal:
            return (SyncFileOutcome(macID: mac, state: .dataless), nil)
        case .timedOut, .notMounted:
            return (SyncFileOutcome(macID: mac, state: .pending), nil)
        case .tooLarge(let size):
            return (SyncFileOutcome(macID: mac, size: size, state: .refused(.tooLarge(size))), nil)
        case .symbolicLink:
            return (SyncFileOutcome(macID: mac, state: .refused(.symbolicLink)), nil)
        case .data(let data, let version):
            if wasPartial {
                return (SyncFileOutcome(macID: mac, size: data.count, state: .pending), nil)
            }
            switch SyncDeviceFile.decode(data, fileName: name) {
            case .success(let contents):
                return (SyncFileOutcome(macID: mac, size: data.count, state: .contents(contents)), version > 0 ? version : nil)
            case .failure(let refusal):
                return (SyncFileOutcome(macID: mac, size: data.count, state: .refused(refusal)), nil)
            }
        }
    }

    private static func readLegacy(_ request: SyncLegacyRequest, _ context: inout SimMacContext) -> SyncLegacyOutcome {
        switch context.read(legacyPath, maximumBytes: SettingsSyncFile.maximumFileSize) {
        case .data(let data, _):
            switch SyncLegacyInput.read(data) {
            case .success(let file):
                if request == .metadata {
                    return .file(SyncLegacyFile(modified: file.modified, deviceID: file.deviceID, settings: [:], identityDigest: file.identityDigest))
                }
                return .file(file)
            case .failure(let refusal):
                return .refused(refusal)
            }
        case .tooLarge(let size):
            return .refused(.tooLarge(size))
        case .symbolicLink:
            return .refused(.symbolicLink)
        case .absent, .notLocal, .notMounted, .timedOut:
            return .absent
        }
    }

    // MARK: Write

    static func write(_ request: SyncWriteRequest, _ context: inout SimMacContext) -> SyncWriteResult {
        let data: Data
        do throws(SyncRefusal) {
            data = try SyncDeviceFile.encode(request.contents)
        } catch {
            return .failed(.tooLarge)
        }
        let mac = request.contents.mac
        let path = path(of: mac)
        let fileName = "\(mac.rawValue).plist"
        // The own file must still be what the session read.
        let current = context.read(path, maximumBytes: SyncDeviceFile.maximumReadSize)
        switch (request.expectation, current) {
        case (.unchecked, _):
            break
        case (.absent, .absent):
            break
        case (.readThisSession(let digest), .data(let bytes, _)):
            guard case .success(let contents) = SyncDeviceFile.decode(bytes, fileName: fileName), contents.replica.digest == digest else {
                return .failed(.ownFileChanged)
            }
        case (_, .notMounted), (_, .timedOut):
            return .failed(.unavailable)
        default:
            return .failed(.ownFileChanged)
        }
        guard context.write(path, data) == .written else {
            return .failed(.unavailable)
        }
        guard
            case .data(let back, _) = context.read(path, maximumBytes: SyncDeviceFile.maximumReadSize),
            case .success(let contents) = SyncDeviceFile.decode(back, fileName: fileName),
            contents.replica.digest == request.replicaDigest
        else {
            return .unverified
        }
        return .verified(SyncWriteReceipt(counter: request.counter, replicaDigest: request.replicaDigest, fileDigest: contents.replica.digest))
    }
}
