//
//  SyncStateStore.swift
//  holzBar
//

import Foundation

/// Why ``SyncStateStore/persist(_:)`` wrote nothing.
nonisolated enum SyncStateStoreError: Error, Equatable, Sendable {
    /// The file on disk was written by a newer format. This build reads it as no state, and it
    /// must not replace it: the newer holzBar needs it after the user comes back to it.
    case newerFormatOnDisk
    /// The state could not be encoded.
    case cannotEncode
    /// The file or its folder could not be written; the old file is as it was.
    case cannotWrite
}

/// Sigma, this Mac's sync state, on disk: `holzBar/Sync/State.plist` under the support folder,
/// and the counter floor `holzBar/Sync/CounterHighWater` under the caches folder (analysis
/// section 4.4).
///
/// The state file is replaced atomically: the new bytes go to a temporary file in the same folder, are
/// flushed to disk, and are renamed over the old file, so a crash leaves the old file or the new one,
/// never half of one. The host persists the generation key and the counter mirror before this file, and
/// this file before it writes any device file.
///
/// The high-water file holds one decimal counter. It is raised and never lowered: a Sigma that was
/// restored from a backup alone is behind the counter this Mac already published, and the floor keeps
/// the next counter above it. It lives in the caches folder because the system may remove it; the
/// counter mirror in the preferences is the other floor.
///
/// Every call blocks; the host runs them on its file queue or at launch.
nonisolated struct SyncStateStore: Sendable {
    /// What reading Sigma found.
    enum Loaded: Hashable, Sendable {
        /// There is no state file.
        case missing
        /// The file was read.
        case read(SyncStateDecodeResult)

        /// What the engine's launch gets: a missing file is no state at all, as an unreadable one is, since a
        /// missing state also means joining.
        var forEngine: SyncStateDecodeResult {
            switch self {
            case .missing:
                .unreadable
            case .read(let result):
                result
            }
        }
    }

    private let stateFile: URL
    private let highWaterFile: URL

    /// - Parameters:
    ///   - supportDirectory: The Application Support folder of the user.
    ///   - cachesDirectory: The Caches folder of the user.
    init(supportDirectory: URL, cachesDirectory: URL) {
        stateFile = supportDirectory
            .appending(path: "holzBar", directoryHint: .isDirectory)
            .appending(path: "Sync", directoryHint: .isDirectory)
            .appending(path: "State.plist")
        highWaterFile = cachesDirectory
            .appending(path: "holzBar", directoryHint: .isDirectory)
            .appending(path: "Sync", directoryHint: .isDirectory)
            .appending(path: "CounterHighWater")
    }

    /// Whether a state file is on disk, whatever it holds.
    var hasFile: Bool {
        FileManager.default.fileExists(atPath: SyncFolderLayout.path(of: stateFile))
    }

    // MARK: State

    func load() -> Loaded {
        switch SettingsSyncFile.readContents(atPath: SyncFolderLayout.path(of: stateFile), maximumSize: SyncStateCodec.maximumSize) {
        case .missing:
            return .missing
        case .refused:
            return .read(.unreadable)
        case .contents(let data):
            return .read(SyncStateCodec.decode(data))
        }
    }

    /// Replaces the state file atomically.
    ///
    /// - Throws: ``SyncStateStoreError``; nothing was replaced then.
    func persist(_ state: SyncState) throws {
        let data: Data
        do {
            data = try SyncStateCodec.encode(state)
        } catch {
            throw SyncStateStoreError.cannotEncode
        }
        if Self.format(ofFileAt: stateFile) ?? 0 > SyncState.currentFormat {
            throw SyncStateStoreError.newerFormatOnDisk
        }
        let folder = stateFile.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw SyncStateStoreError.cannotWrite
        }
        let temporary = folder.appending(path: "State.plist.tmp")
        guard SyncFolderLayout.writeAtomically(data, temporary: SyncFolderLayout.path(of: temporary), destination: SyncFolderLayout.path(of: stateFile)) else {
            throw SyncStateStoreError.cannotWrite
        }
    }

    /// The major format number of the file at `url`, or `nil` when it holds none.
    private static func format(ofFileAt url: URL) -> Int? {
        guard
            case .contents(let data) = SettingsSyncFile.readContents(atPath: SyncFolderLayout.path(of: url), maximumSize: SyncStateCodec.maximumSize),
            let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let root = object as? [String: Any]
        else {
            return nil
        }
        return (root["format"] as? NSNumber)?.intValue
    }

    // MARK: Counter floor

    /// The largest counter this installation has minted, as far as the floor file knows; `0` when there is none.
    var highWater: UInt64 {
        guard
            case .contents(let data) = SettingsSyncFile.readContents(atPath: SyncFolderLayout.path(of: highWaterFile), maximumSize: 64),
            let text = String(data: data, encoding: .utf8)
        else {
            return 0
        }
        return UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Raises the floor to `value`; a lower value changes nothing, so the floor never decreases.
    ///
    /// - Returns: Whether the floor is at least `value` afterwards.
    @discardableResult
    func raiseHighWater(to value: UInt64) -> Bool {
        guard value > highWater else {
            return true
        }
        let folder = highWaterFile.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return false
        }
        let temporary = folder.appending(path: "CounterHighWater.tmp")
        return SyncFolderLayout.writeAtomically(
            Data(String(value).utf8),
            temporary: SyncFolderLayout.path(of: temporary),
            destination: SyncFolderLayout.path(of: highWaterFile)
        )
    }
}
