//
//  SyncLegacyInput.swift
//  holzBar
//

import Foundation

/// What the legacy sync file `holzBar/Settings.plist` of 0.0.6 and 0.0.7-beta1 holds.
nonisolated struct SyncLegacyFile: Hashable, Sendable {
    /// When the file was written, if it says so.
    let modified: Date?
    /// The sync ID of the Mac that wrote it; files of the earliest builds carry only a
    /// computer name, which is never read here, so they have none.
    let deviceID: String?
    /// The settings, the values that convert to ``SyncValue`` only. The founding join
    /// validates every unit later.
    let settings: [String: SyncValue]
    /// A digest of `(modified, deviceID)` and nothing else: it changes only when the legacy
    /// writer or the date changes, which is what the status line shows.
    let identityDigest: SyncDigest

    /// Whether the file was written by the Mac that had the sync ID `id`, which holzBar
    /// keeps after a Mac re-identifies.
    func isWritten(byLegacyDeviceID id: String?) -> Bool {
        guard let id, let deviceID else {
            return false
        }
        return id == deviceID
    }
}

/// Reads the legacy sync file of 0.0.6 and 0.0.7-beta1.
///
/// holzBar never writes or deletes `holzBar/Settings.plist` (decision D-02): other Macs on
/// the old versions keep syncing through it. It reads the file only to found a group from
/// it and to show the status line when an old Mac changes it. So this type has a reader and
/// no encoder.
nonisolated enum SyncLegacyInput {
    /// Reads the file's bytes, which the caller has read safely (a regular file, no
    /// symbolic link; see ``SettingsSyncFile/readContents(atPath:maximumSize:)``).
    ///
    /// - Returns: The file, or why it was refused: larger than
    ///   ``SettingsSyncFile/maximumFileSize``, not a property list, or without a
    ///   settings dictionary.
    static func read(_ data: Data) -> Result<SyncLegacyFile, SyncRefusal> {
        guard data.count <= SettingsSyncFile.maximumFileSize else {
            return .failure(.tooLarge(data.count))
        }
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            return .failure(.notPropertyList)
        }
        guard let root = object as? [String: Any] else {
            return .failure(.wrongStructure("root"))
        }
        guard let settingFields = root[SettingsSyncFile.settingsKey] as? [String: Any] else {
            return .failure(.wrongStructure("settings"))
        }
        let modified = root[SettingsSyncFile.modifiedKey] as? Date
        let deviceID = root[SettingsSyncDevice.deviceIDKey] as? String
        var settings: [String: SyncValue] = [:]
        for key in settingFields.keys.sorted() {
            if let value = settingFields[key].flatMap({ SyncValue(propertyList: $0) }) {
                settings[key] = value
            }
        }
        var identity: [String: SyncValue] = [:]
        identity[SettingsSyncFile.modifiedKey] = modified.map { .date($0) }
        identity[SettingsSyncDevice.deviceIDKey] = deviceID.map { .string($0) }
        let file = SyncLegacyFile(
            modified: modified,
            deviceID: deviceID,
            settings: settings,
            identityDigest: SyncValue.dictionary(identity).digest
        )
        return .success(file)
    }
}
