//
//  SettingsSyncDevice.swift
//  holzBar
//

import Foundation

/// Decides which Mac wrote a settings sync file.
///
/// Each Mac identifies itself by a UUID that it creates once and keeps in its own defaults;
/// the id is never exported, imported or synced. The file also carries the computer name,
/// for display and for older holzBar builds, which wrote only the name.
enum SettingsSyncDevice {
    /// The key of the writing Mac's id in the sync file.
    static let deviceIDKey = "deviceID"

    /// The key of the writing Mac's computer name in the sync file.
    static let deviceNameKey = "device"

    /// Whether the sync file was written by this Mac.
    ///
    /// An id in the file decides alone, so two Macs with the same name are told apart. Only a
    /// file without an id, written by an older holzBar, falls back to the name, and only
    /// when this Mac has a non-empty computer name.
    ///
    /// - Parameters:
    ///   - file: The contents of the sync file.
    ///   - deviceID: This Mac's id.
    ///   - computerName: This Mac's computer name, if it has one.
    static func isFromThisMac(file: [String: Any], deviceID: String, computerName: String?) -> Bool {
        if let fileDeviceID = file[deviceIDKey] as? String {
            return fileDeviceID == deviceID
        }
        guard let computerName, !computerName.isEmpty else {
            return false
        }
        return (file[deviceNameKey] as? String) == computerName
    }
}
