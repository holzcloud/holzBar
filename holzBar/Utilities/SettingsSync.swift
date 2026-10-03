//
//  SettingsSync.swift
//  holzBar
//

import AppKit
import Combine
import OSLog
import SystemConfiguration

/// Keeps holzBar's settings in step across Macs through a file in iCloud Drive
/// (jordanbaird/Ice#95).
///
/// iCloud's key-value store needs an iCloud entitlement, which an ad hoc signed
/// app cannot have, so the settings travel as `holzBar/Settings.plist` in
/// iCloud Drive instead. Each change is written there; newer settings from
/// another Mac are applied at launch, or after a restart the user agrees to.
@MainActor
final class SettingsSync: ObservableObject {
    private static let logger = Logger(category: "SettingsSync")

    /// Keys that stay on this Mac.
    private static let localKeys: Set<String> = [
        Defaults.Key.syncsSettingsWithICloud.rawValue,
        lastSyncedKey,
    ]

    private static let lastSyncedKey = "SettingsSyncLastSynced"

    /// The key of this Mac's sync id. Keys starting with "SettingsSync" are never exported,
    /// imported or synced (`SettingsBackup.excludedKeyPrefixes`).
    private static let deviceIDKey = "SettingsSyncDeviceID"

    /// The id this Mac writes into the sync file, created once and kept in this Mac's
    /// defaults.
    static var deviceID: String {
        if let deviceID = UserDefaults.standard.string(forKey: deviceIDKey) {
            return deviceID
        }
        let deviceID = UUID().uuidString
        UserDefaults.standard.set(deviceID, forKey: deviceIDKey)
        return deviceID
    }

    /// This Mac's computer name, read from the system configuration without a network
    /// lookup.
    static var computerName: String? {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
    }

    /// iCloud Drive's folder, if iCloud Drive is turned on.
    static var iCloudDriveURL: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The file the settings are synced through.
    static var fileURL: URL? {
        iCloudDriveURL?.appending(path: "holzBar/Settings.plist")
    }

    /// A Boolean value that indicates whether syncing is turned on.
    @Published var isEnabled = false {
        didSet {
            Defaults.set(isEnabled, forKey: .syncsSettingsWithICloud)
            if isEnabled, !oldValue {
                push()
            }
        }
    }

    private weak var appState: AppState?
    private var cancellables = Set<AnyCancellable>()
    private var lastPushedData: Data?
    private var isAskingToRestart = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        isEnabled = Defaults.bool(forKey: .syncsSettingsWithICloud)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: 5, scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsDidChange()
            }
            .store(in: &cancellables)

        Timer.publish(every: 300, tolerance: 30, on: .main, in: .default)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkForNewerSettings()
            }
            .store(in: &cancellables)
    }

    /// Writes the settings to iCloud Drive, if syncing is on.
    func settingsDidChange() {
        guard isEnabled else {
            return
        }
        push()
    }

    private func push() {
        guard let fileURL = Self.fileURL else {
            Self.logger.warning("iCloud Drive is off, not syncing settings")
            return
        }
        let settings = SettingsBackup.currentSettings().filter { !Self.localKeys.contains($0.key) }
        guard
            let settingsData = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0),
            settingsData != lastPushedData
        else {
            return
        }
        let modified = Date.now
        let file: [String: Any] = [
            "modified": modified,
            SettingsSyncDevice.deviceIDKey: Self.deviceID,
            SettingsSyncDevice.deviceNameKey: Self.computerName ?? "",
            "settings": settings,
        ]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
            try data.write(to: fileURL, options: .atomic)
            lastPushedData = settingsData
            UserDefaults.standard.set(modified, forKey: Self.lastSyncedKey)
            Self.logger.info("Wrote settings to iCloud Drive")
        } catch {
            Self.logger.error("Error writing settings to iCloud Drive: \(error, privacy: .private)")
        }
    }

    /// Reads the synced settings if they are newer than the ones this Mac has.
    private static func newerSettings() -> (settings: [String: Any], modified: Date)? {
        guard
            let fileURL,
            let data = try? Data(contentsOf: fileURL),
            let file = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let modified = file["modified"] as? Date,
            let settings = file["settings"] as? [String: Any],
            !SettingsSyncDevice.isFromThisMac(file: file, deviceID: deviceID, computerName: computerName)
        else {
            return nil
        }
        let lastSynced = UserDefaults.standard.object(forKey: lastSyncedKey) as? Date ?? .distantPast
        return modified > lastSynced ? (settings, modified) : nil
    }

    /// Applies newer settings from another Mac before anything reads the
    /// settings. The app delegate calls this before it creates the app state.
    static func pullIfNeeded() {
        guard
            Defaults.bool(forKey: .syncsSettingsWithICloud),
            let newer = newerSettings()
        else {
            return
        }
        SettingsBackup.apply(newer.settings.filter { !localKeys.contains($0.key) })
        Defaults.set(true, forKey: .syncsSettingsWithICloud)
        UserDefaults.standard.set(newer.modified, forKey: lastSyncedKey)
        logger.notice("Applied settings from iCloud Drive")
    }

    /// Offers to restart when another Mac has changed the settings.
    private func checkForNewerSettings() {
        guard isEnabled, !isAskingToRestart, Self.newerSettings() != nil else {
            return
        }
        isAskingToRestart = true
        defer {
            isAskingToRestart = false
        }
        let alert = NSAlert()
        alert.messageText = "Settings changed on another Mac"
        alert.informativeText = "holzBar can restart now to use the settings from iCloud Drive."
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            SettingsSync.pullIfNeeded()
            SettingsBackup.relaunch()
        }
    }
}
