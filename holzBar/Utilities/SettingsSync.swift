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
///
/// Without an iCloud entitlement, `NSMetadataQuery`'s ubiquitous scopes are out of reach
/// too. File coordination is what iCloud Drive itself uses to update the file, so a file
/// presenter on the `holzBar` folder hears about every version that arrives from another
/// Mac, with no polling, and coordinated reads and writes never see half a file. The
/// presenter and the observer of this Mac's settings exist only while sync is on.
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

    /// The folder in iCloud Drive that holds the sync file.
    static var folderURL: URL? {
        iCloudDriveURL?.appending(path: "holzBar", directoryHint: .isDirectory)
    }

    /// The file the settings are synced through.
    static var fileURL: URL? {
        folderURL?.appending(path: "Settings.plist")
    }

    /// A Boolean value that indicates whether syncing is turned on.
    @Published var isEnabled = false {
        didSet {
            Defaults.set(isEnabled, forKey: .syncsSettingsWithICloud)
            updateObservers()
            if isEnabled, !oldValue {
                push()
            }
        }
    }

    private weak var appState: AppState?
    private var lastPushedData: Data?
    private var isAskingToRestart = false

    /// Observes this Mac's settings while sync is on.
    private var defaultsObserver: AnyCancellable?

    /// Hears about new versions of the sync file while sync is on.
    private var presenter: SettingsSyncPresenter?

    /// The pending check after the sync file changed.
    private var checkTask: Task<Void, Never>?

    func performSetup(with appState: AppState) {
        self.appState = appState
        isEnabled = Defaults.bool(forKey: .syncsSettingsWithICloud)
    }

    /// Starts or stops observing the settings and the sync file, as sync is on or off.
    private func updateObservers() {
        guard isEnabled, appState != nil else {
            defaultsObserver = nil
            checkTask?.cancel()
            checkTask = nil
            if let presenter {
                NSFileCoordinator.removeFilePresenter(presenter)
                self.presenter = nil
                Self.logger.info("Stopped watching the sync file")
            }
            return
        }

        if defaultsObserver == nil {
            defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .debounce(for: 5, scheduler: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.settingsDidChange()
                }
        }

        if presenter == nil, let folderURL = Self.folderURL {
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Error creating the sync folder in iCloud Drive: \(error, privacy: .private)")
            }
            let presenter = SettingsSyncPresenter(folderURL: folderURL) { [weak self] in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    self.syncFileDidChange()
                }
            }
            NSFileCoordinator.addFilePresenter(presenter)
            self.presenter = presenter
            Self.logger.info("Watching the sync file")
        }
    }

    /// Checks the sync file shortly after it changed, once for a burst of changes.
    private func syncFileDidChange() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            self?.checkForNewerSettings()
        }
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
            SettingsSyncFile.modifiedKey: modified,
            SettingsSyncDevice.deviceIDKey: Self.deviceID,
            SettingsSyncDevice.deviceNameKey: Self.computerName ?? "",
            SettingsSyncFile.settingsKey: settings,
        ]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
            // Coordinated, so iCloud Drive never uploads half a file; this Mac's presenter
            // is not told about its own write.
            var coordinationError: NSError?
            var writeError: (any Error)?
            NSFileCoordinator(filePresenter: presenter).coordinate(
                writingItemAt: fileURL,
                options: .forReplacing,
                error: &coordinationError
            ) { url in
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let coordinationError {
                throw coordinationError
            }
            if let writeError {
                throw writeError
            }
            lastPushedData = settingsData
            UserDefaults.standard.set(modified, forKey: Self.lastSyncedKey)
            Self.logger.info("Wrote settings to iCloud Drive")
        } catch {
            Self.logger.error("Error writing settings to iCloud Drive: \(error, privacy: .private)")
        }
    }

    /// Reads the synced settings if another Mac wrote them after this Mac last synced.
    ///
    /// - Parameter presenter: The presenter that reads, which is not told about the read.
    private static func newerSettings(presenter: (any NSFilePresenter)?) -> (settings: [String: Any], modified: Date)? {
        guard let fileURL, let file = readFile(at: fileURL, presenter: presenter) else {
            return nil
        }
        return SettingsSyncFile.newerSettings(
            in: file,
            lastSynced: UserDefaults.standard.object(forKey: lastSyncedKey) as? Date,
            deviceID: deviceID,
            computerName: computerName,
            localKeys: localKeys
        )
    }

    /// Reads the sync file with a coordinated read, so a version iCloud Drive is still
    /// writing is never read half.
    private static func readFile(at fileURL: URL, presenter: (any NSFilePresenter)?) -> [String: Any]? {
        var coordinationError: NSError?
        var file: [String: Any]?
        NSFileCoordinator(filePresenter: presenter).coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { url in
            guard let data = try? Data(contentsOf: url) else {
                return
            }
            file = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }
        if let coordinationError {
            logger.error("Error reading the sync file: \(coordinationError, privacy: .private)")
        }
        return file
    }

    /// Applies newer settings from another Mac before anything reads the
    /// settings. The app delegate calls this before it creates the app state.
    static func pullIfNeeded() {
        guard
            Defaults.bool(forKey: .syncsSettingsWithICloud),
            let newer = newerSettings(presenter: nil)
        else {
            return
        }
        SettingsBackup.apply(newer.settings)
        Defaults.set(true, forKey: .syncsSettingsWithICloud)
        UserDefaults.standard.set(newer.modified, forKey: lastSyncedKey)
        logger.notice("Applied settings from iCloud Drive")
    }

    /// Offers to restart when another Mac has changed the settings.
    private func checkForNewerSettings() {
        guard isEnabled, !isAskingToRestart, Self.newerSettings(presenter: presenter) != nil else {
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

// MARK: - SettingsSyncPresenter

/// Tells settings sync when a new version of the sync file arrives in iCloud Drive.
///
/// File presenters are called on their own queue; the presenter only hands the change on.
/// Its state never changes after it is created.
private final class SettingsSyncPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?

    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    /// Called when the folder or a file in it changes.
    private let onChange: @Sendable () -> Void

    init(folderURL: URL, onChange: @escaping @Sendable () -> Void) {
        self.presentedItemURL = folderURL
        self.onChange = onChange
        super.init()
    }

    func presentedItemDidChange() {
        onChange()
    }

    func presentedSubitemDidChange(at url: URL) {
        onChange()
    }

    func presentedSubitemDidAppear(at url: URL) {
        onChange()
    }
}
