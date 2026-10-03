//
//  SettingsSyncFile.swift
//  holzBar
//

import Foundation

/// Decides which settings of the sync file in iCloud Drive this Mac applies.
///
/// The file holds the date it was written (``modifiedKey``), the writing Mac (see
/// ``SettingsSyncDevice``) and the settings (``settingsKey``).
enum SettingsSyncFile {
    /// The key of the date the file was written.
    static let modifiedKey = "modified"

    /// The key of the synced settings.
    static let settingsKey = "settings"

    /// Returns the settings to apply from the sync file, if another Mac wrote them after
    /// this Mac last synced.
    ///
    /// - Parameters:
    ///   - file: The contents of the sync file.
    ///   - lastSynced: When this Mac last wrote or applied the file, if ever.
    ///   - deviceID: This Mac's sync id.
    ///   - computerName: This Mac's computer name, if it has one.
    ///   - localKeys: The keys that stay on this Mac; they are removed from the settings.
    /// - Returns: The settings and the date the file was written, or `nil` when the file
    ///   is this Mac's own, is not newer, or lacks its date or settings.
    static func newerSettings(
        in file: [String: Any],
        lastSynced: Date?,
        deviceID: String,
        computerName: String?,
        localKeys: Set<String>
    ) -> (settings: [String: Any], modified: Date)? {
        guard
            let modified = file[modifiedKey] as? Date,
            let settings = file[settingsKey] as? [String: Any],
            !SettingsSyncDevice.isFromThisMac(file: file, deviceID: deviceID, computerName: computerName),
            modified > lastSynced ?? .distantPast
        else {
            return nil
        }
        return (settings.filter { !localKeys.contains($0.key) }, modified)
    }
}
