//
//  SettingsSyncLocation.swift
//  holzBar
//

import Foundation

/// Where holzBar syncs its settings: iCloud Drive or any folder the user's Macs keep in
/// step, such as a Nextcloud, Dropbox, OneDrive or Syncthing folder or a network share
/// (SYNC-01).
///
/// The folder is stored as a bookmark, so it is found again after it was moved or renamed.
/// The settings travel as `holzBar/Settings.plist` inside it; the folder's own app syncs
/// the file, holzBar never connects to the network.
nonisolated enum SettingsSyncLocation {
    /// The sync file inside the chosen folder.
    static let fileComponents = ["holzBar", "Settings.plist"]

    /// What the stored bookmark gave.
    nonisolated enum Resolution: Equatable, Sendable {
        /// No folder was chosen yet.
        case none
        /// The bookmark gave this folder; a stale bookmark is to be stored again.
        case resolved(path: String, isStale: Bool)
        /// The bookmark could not be resolved: the folder is gone or its volume is not
        /// mounted.
        case failed
    }

    /// Where to sync and what to store.
    nonisolated struct Decision: Equatable, Sendable {
        /// The folder to sync through, or `nil` when there is none now.
        let folderPath: String?
        /// Whether to store a new bookmark of ``folderPath``: it was stale, or it is
        /// iCloud Drive, used before folders could be chosen.
        let storesBookmark: Bool
    }

    /// Decides the folder.
    ///
    /// Without a chosen folder, iCloud Drive is used, as it was before folders could be
    /// chosen, and stored as the choice, so existing users keep syncing without a question.
    /// A folder that cannot be found is not replaced by iCloud Drive: that would mix the
    /// settings of two places.
    ///
    /// - Parameters:
    ///   - resolution: What the stored bookmark gave.
    ///   - iCloudDrivePath: iCloud Drive's folder, if iCloud Drive is turned on.
    static func decide(resolution: Resolution, iCloudDrivePath: String?) -> Decision {
        switch resolution {
        case .none:
            Decision(folderPath: iCloudDrivePath, storesBookmark: iCloudDrivePath != nil)
        case .resolved(let path, let isStale):
            Decision(folderPath: path, storesBookmark: isStale)
        case .failed:
            Decision(folderPath: nil, storesBookmark: false)
        }
    }

    /// The path of the sync file in the given folder.
    static func syncFilePath(inFolder folderPath: String) -> String {
        fileComponents.reduce(URL(fileURLWithPath: folderPath, isDirectory: true)) { url, component in
            url.appendingPathComponent(component)
        }.path
    }

    /// The name of the folder to show: "iCloud Drive" for iCloud Drive, a path starting
    /// with "~" inside the home folder, the full path otherwise.
    static func displayName(forFolder folderPath: String, homePath: String, iCloudDrivePath: String?) -> String {
        let folder = normalized(folderPath)
        if let iCloudDrivePath, folder == normalized(iCloudDrivePath) {
            return "iCloud Drive"
        }
        let home = normalized(homePath)
        if folder == home {
            return "~"
        }
        if folder.hasPrefix(home + "/") {
            return "~" + folder.dropFirst(home.count)
        }
        return folder
    }

    /// The path without a trailing slash.
    private static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
