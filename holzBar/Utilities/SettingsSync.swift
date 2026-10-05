//
//  SettingsSync.swift
//  holzBar
//

import AppKit
import Observation
import OSLog
import SystemConfiguration

/// Keeps holzBar's settings in step across Macs through a file in a folder the Macs sync:
/// iCloud Drive or any folder the user chooses, such as a Nextcloud, Dropbox, OneDrive or
/// Syncthing folder or a network share (jordanbaird/Ice#95, SYNC-01).
///
/// iCloud's key-value store needs an iCloud entitlement, which an ad hoc signed
/// app cannot have, so the settings travel as `holzBar/Settings.plist` in the folder
/// instead. Each change is written there; newer settings from another Mac are applied at
/// launch, or after a restart the user agrees to. The folder's own app syncs the file;
/// holzBar never connects to the network.
///
/// The folder is stored as a bookmark (`SettingsSyncLocation`). Without one, iCloud Drive
/// is used, as before folders could be chosen, and stored as the choice.
///
/// Without an iCloud entitlement, `NSMetadataQuery`'s ubiquitous scopes are out of reach
/// too. File coordination is what iCloud Drive itself uses to update the file, so a file
/// presenter on the `holzBar` folder hears about every version that arrives from another
/// Mac, with no polling, and coordinated reads and writes never see half a file. Other
/// sync apps replace the file without coordination; a file system event source on the
/// folder hears about those. The presenter, the event source and the observer of this
/// Mac's settings exist only while sync is on.
@MainActor
@Observable
final class SettingsSync {
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
    /// lookup. It is never written into the sync file (it usually holds the owner's name);
    /// it is only compared with files of older holzBar builds, which carry no id.
    static var computerName: String? {
        SCDynamicStoreCopyComputerName(nil, nil) as String?
    }

    /// iCloud Drive's folder, if iCloud Drive is turned on.
    static var iCloudDriveURL: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The key of the bookmark of the chosen folder. It starts with "SettingsSync", so it
    /// stays on this Mac (`SettingsBackup.excludedKeyPrefixes`).
    private static let folderBookmarkKey = "SettingsSyncFolderBookmark"

    /// The folder the Macs sync, chosen by the user or iCloud Drive (see
    /// `SettingsSyncLocation`). A stale bookmark, or iCloud Drive used without a choice, is
    /// stored as the choice.
    ///
    /// The bookmark is resolved without mounting: holzBar never mounts a network share
    /// itself (and never waits for one on the main thread). A folder on a volume that is
    /// not mounted is not available until the user mounts it.
    static var syncFolderURL: URL? {
        let resolution: SettingsSyncLocation.Resolution
        var resolvedURL: URL?
        if let bookmark = UserDefaults.standard.data(forKey: folderBookmarkKey) {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                resolvedURL = url
                resolution = .resolved(path: url.path(percentEncoded: false), isStale: isStale)
            } else {
                resolution = .failed
            }
        } else {
            resolution = .none
        }
        let iCloudDriveURL = iCloudDriveURL
        let decision = SettingsSyncLocation.decide(
            resolution: resolution,
            iCloudDrivePath: iCloudDriveURL?.path(percentEncoded: false)
        )
        guard let folderPath = decision.folderPath else {
            return nil
        }
        let url = resolvedURL ?? iCloudDriveURL ?? URL(filePath: folderPath, directoryHint: .isDirectory)
        if decision.storesBookmark {
            storeBookmark(of: url)
        }
        return url
    }

    /// Stores the bookmark of the folder the Macs sync.
    private static func storeBookmark(of folderURL: URL) {
        do {
            let bookmark = try folderURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: folderBookmarkKey)
        } catch {
            logger.error("Could not store the sync folder: \(error, privacy: .private)")
        }
    }

    /// The folder in the synced folder that holds the sync file.
    static var folderURL: URL? {
        syncFolderURL?.appending(path: SettingsSyncLocation.fileComponents[0], directoryHint: .isDirectory)
    }

    /// The file the settings are synced through.
    static var fileURL: URL? {
        folderURL?.appending(path: SettingsSyncLocation.fileComponents[1])
    }

    /// The name of the synced folder to show, or `nil` when there is none. Updated while
    /// sync is on, when the folder is chosen and when a volume is mounted or unmounted, never
    /// in a view body.
    private(set) var folderDisplayName: String?

    /// Updates the name of the synced folder to show.
    private func updateFolderDisplayName() {
        folderDisplayName = Self.syncFolderURL.map { url in
            SettingsSyncLocation.displayName(
                forFolder: url.path(percentEncoded: false),
                homePath: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
                iCloudDrivePath: Self.iCloudDriveURL?.path(percentEncoded: false)
            )
        }
    }

    /// A Boolean value that indicates whether syncing is turned on.
    var isEnabled = false {
        didSet {
            Defaults.set(isEnabled, forKey: .syncsSettingsWithICloud)
            updateObservers()
            if isEnabled, !oldValue {
                push()
            }
        }
    }

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var lastPushedData: Data?
    @ObservationIgnored private var isAskingToRestart = false

    /// Observes this Mac's settings while sync is on.
    @ObservationIgnored private var defaultsObserver: Task<Void, Never>?

    /// Observes volumes being mounted and unmounted while sync is on, as the folder may be
    /// on one.
    @ObservationIgnored private var volumeObservers: [Task<Void, Never>] = []

    /// Pushes the settings 5 s after they stop changing.
    @ObservationIgnored private let defaultsDebouncer = Debouncer(delay: .seconds(5))

    /// Hears about new versions of the sync file while sync is on.
    @ObservationIgnored private var presenter: SettingsSyncPresenter?

    /// Hears about files other sync apps replace in the folder while sync is on.
    @ObservationIgnored private var folderWatcher: SettingsSyncFolderWatcher?

    /// The pending check after the sync file changed.
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    /// A push waited for the pending check, and is made once the check is done.
    @ObservationIgnored private var pushesAfterCheck = false

    func performSetup(with appState: AppState) {
        self.appState = appState
        isEnabled = Defaults.bool(forKey: .syncsSettingsWithICloud)
    }

    /// Starts or stops observing the settings and the sync file, as sync is on or off.
    private func updateObservers() {
        guard isEnabled, appState != nil else {
            defaultsObserver?.cancel()
            defaultsObserver = nil
            volumeObservers.forEach { $0.cancel() }
            volumeObservers = []
            defaultsDebouncer.cancel()
            checkTask?.cancel()
            checkTask = nil
            pushesAfterCheck = false
            stopWatchingFolder()
            return
        }

        if defaultsObserver == nil {
            defaultsObserver = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                    self?.defaultsDebouncer.schedule { [weak self] in
                        self?.settingsDidChange()
                    }
                }
            }
        }

        if volumeObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            volumeObservers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification].map { name in
                Task { [weak self] in
                    for await _ in center.notifications(named: name) {
                        self?.volumesDidChange()
                    }
                }
            }
        }

        updateFolderDisplayName()

        if presenter == nil, let folderURL = Self.folderURL {
            // Anyone who can write the synced folder could make the holzBar folder a link
            // to another folder of the user's; holzBar then neither watches nor writes it.
            guard SettingsSyncFile.isUsableFolder(atPath: folderURL.path(percentEncoded: false)) else {
                Self.logger.error("The holzBar folder in the sync folder is a link or a file, not syncing")
                return
            }
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                Self.logger.error("Error creating the holzBar folder in the sync folder: \(error, privacy: .private)")
            }
            let onChange: @Sendable () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                Task { @MainActor in
                    self.syncFileDidChange()
                }
            }
            let presenter = SettingsSyncPresenter(folderURL: folderURL, onChange: onChange)
            NSFileCoordinator.addFilePresenter(presenter)
            self.presenter = presenter
            folderWatcher = SettingsSyncFolderWatcher(folderURL: folderURL, onChange: onChange)
            Self.logger.info("Watching the sync file")
        }
    }

    /// Watches the sync folder again when a volume was mounted or unmounted and the folder
    /// became available, moved or gone.
    ///
    /// A folder that has just become available, such as a network share mounted after
    /// launch, may hold newer settings from another Mac, so it is checked before this Mac's
    /// settings are written there (``push()`` waits for the check).
    private func volumesDidChange() {
        let watchedURL = presenter?.presentedItemURL
        if watchedURL != Self.folderURL {
            stopWatchingFolder()
        }
        updateObservers()
        if let presenter, presenter.presentedItemURL != watchedURL {
            syncFileDidChange()
        }
    }

    /// Stops listening to the sync folder.
    private func stopWatchingFolder() {
        folderWatcher?.cancel()
        folderWatcher = nil
        if let presenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            self.presenter = nil
            Self.logger.info("Stopped watching the sync file")
        }
    }

    // MARK: Folder

    /// Lets the user choose the folder the Macs sync, and turns sync on with it.
    ///
    /// - Returns: Whether a folder was chosen.
    @discardableResult
    func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Sync Here")
        panel.message = String(localized: "Choose a folder your Macs keep in sync, such as iCloud Drive or a Nextcloud, Dropbox, OneDrive or Syncthing folder. holzBar keeps its settings in a holzBar folder inside it.")
        panel.directoryURL = Self.syncFolderURL ?? Self.iCloudDriveURL
        guard panel.runModal() == .OK, let url = panel.url else {
            return false
        }
        stopWatchingFolder()
        Self.storeBookmark(of: url)
        lastPushedData = nil
        if isEnabled {
            updateObservers()
            push()
        } else {
            isEnabled = true
        }
        return true
    }

    /// Checks the sync file shortly after it changed, once for a burst of changes.
    private func syncFileDidChange() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            let restarts = await self?.checkForNewerSettings() ?? false
            // A cancelled check was replaced by a newer one, or sync was turned off.
            if !Task.isCancelled {
                self?.checkTask = nil
            }
            if !restarts {
                self?.pushAfterCheck()
            }
        }
    }

    /// Makes the push that waited for a check of the sync file, once no check is pending.
    private func pushAfterCheck() {
        guard pushesAfterCheck, checkTask == nil, !isAskingToRestart else {
            return
        }
        pushesAfterCheck = false
        settingsDidChange()
    }

    /// Writes the settings to iCloud Drive, if syncing is on.
    func settingsDidChange() {
        guard isEnabled else {
            return
        }
        push()
    }

    private func push() {
        // A pending check may find newer settings from another Mac, which this push would
        // overwrite; push once the check is done (``pushAfterCheck()``).
        guard checkTask == nil, !isAskingToRestart else {
            pushesAfterCheck = true
            return
        }
        guard let fileURL = Self.fileURL else {
            Self.logger.warning("No sync folder, not syncing settings")
            return
        }
        let settings = SettingsBackup.currentSettings().filter { !Self.localKeys.contains($0.key) }
        guard
            let settingsData = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0),
            settingsData != lastPushedData
        else {
            return
        }
        let folderURL = fileURL.deletingLastPathComponent()
        guard SettingsSyncFile.isUsableFolder(atPath: folderURL.path(percentEncoded: false)) else {
            Self.logger.error("The holzBar folder in the sync folder is a link or a file, not syncing")
            return
        }
        let modified = Date.now
        // The id alone tells the Macs apart; the computer name, which usually holds the
        // owner's name, stays on this Mac.
        let file: [String: Any] = [
            SettingsSyncFile.modifiedKey: modified,
            SettingsSyncDevice.deviceIDKey: Self.deviceID,
            SettingsSyncFile.settingsKey: settings,
        ]
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
            // Coordinated, so iCloud Drive never uploads half a file; this Mac's presenter
            // is not told about its own write (its folder watcher is, and finds the file
            // its own).
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
            Self.logger.info("Wrote settings to the sync folder")
        } catch {
            Self.logger.error("Error writing settings to the sync folder: \(error, privacy: .private)")
        }
    }

    /// The settings in the sync file, if another Mac wrote them after this Mac last synced.
    ///
    /// - Parameter read: What reading the sync file gave (``readFileContents(at:)``).
    private static func newerSettings(from read: SettingsSyncFile.ReadResult) -> (settings: [String: Any], modified: Date)? {
        let data: Data
        switch read {
        case .contents(let contents):
            data = contents
        case .missing:
            return nil
        case .refused(let refusal):
            let reason = String(describing: refusal)
            logger.error("Ignoring the sync file: \(reason, privacy: .public)")
            return nil
        }
        guard let file = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else {
            logger.error("Ignoring the sync file: it holds no settings")
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
    ///
    /// Anyone who can write the synced folder can write the file, so it is read only from a
    /// real `holzBar` folder, only when it is a regular file reached without a symbolic link,
    /// and only up to `SettingsSyncFile.maximumFileSize` bytes. Nonisolated, so the checks
    /// after launch read it off the main actor (``readFileContentsInBackground(at:)``).
    /// No presenter is passed: holzBar's presenter does nothing for a read.
    private nonisolated static func readFileContents(at fileURL: URL) -> SettingsSyncFile.ReadResult {
        let folderPath = fileURL.deletingLastPathComponent().path(percentEncoded: false)
        guard SettingsSyncFile.isUsableFolder(atPath: folderPath) else {
            return .refused(.notRegularFile)
        }
        var coordinationError: NSError?
        var result = SettingsSyncFile.ReadResult.missing
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: fileURL,
            options: [],
            error: &coordinationError
        ) { url in
            result = SettingsSyncFile.readContents(atPath: url.path(percentEncoded: false))
        }
        if coordinationError != nil {
            return .refused(.unreadable)
        }
        return result
    }

    /// Reads the sync file on the concurrent pool, off the main actor.
    @concurrent
    private nonisolated static func readFileContentsInBackground(at fileURL: URL) async -> SettingsSyncFile.ReadResult {
        readFileContents(at: fileURL)
    }

    /// Applies newer settings from another Mac before anything reads the
    /// settings. The app delegate calls this before it creates the app state.
    ///
    /// It reads on the main thread, because nothing may read the settings before they are
    /// applied; the size limit keeps the read short.
    static func pullIfNeeded() {
        guard
            Defaults.bool(forKey: .syncsSettingsWithICloud),
            let fileURL,
            let newer = newerSettings(from: readFileContents(at: fileURL))
        else {
            return
        }
        SettingsBackup.apply(newer.settings)
        Defaults.set(true, forKey: .syncsSettingsWithICloud)
        UserDefaults.standard.set(newer.modified, forKey: lastSyncedKey)
        logger.notice("Applied settings from the sync folder")
    }

    /// Offers to restart when another Mac has changed the settings.
    ///
    /// The file is read off the main actor; only the small, checked result is decoded here.
    ///
    /// - Returns: Whether holzBar restarts with the newer settings.
    private func checkForNewerSettings() async -> Bool {
        guard isEnabled, !isAskingToRestart, let fileURL = Self.fileURL else {
            return false
        }
        let read = await Self.readFileContentsInBackground(at: fileURL)
        guard isEnabled, !isAskingToRestart, Self.newerSettings(from: read) != nil else {
            return false
        }
        isAskingToRestart = true
        defer {
            isAskingToRestart = false
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Settings changed on another Mac")
        alert.informativeText = String(localized: "holzBar can restart now to use the settings from the sync folder.")
        alert.addButton(withTitle: String(localized: "Restart"))
        alert.addButton(withTitle: String(localized: "Later"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            return false
        }
        SettingsSync.pullIfNeeded()
        SettingsBackup.relaunch()
        return true
    }
}

// MARK: - SettingsSyncFolderWatcher

/// Tells settings sync when a file in the sync folder is added, replaced or removed, as
/// sync apps other than iCloud Drive do without file coordination.
///
/// A file system event source on the folder: an event, never a poll. Its state never
/// changes after it is created.
private nonisolated final class SettingsSyncFolderWatcher: @unchecked Sendable {
    private let source: any DispatchSourceFileSystemObject

    init?(folderURL: URL, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(folderURL.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .link],
            queue: .global(qos: .utility)
        )
        source.setEventHandler {
            onChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
    }

    func cancel() {
        source.cancel()
    }
}

// MARK: - SettingsSyncPresenter

/// Tells settings sync when a new version of the sync file arrives in iCloud Drive.
///
/// File presenters are called on their own queue; the presenter only hands the change on.
/// Its state never changes after it is created. It must be `nonisolated`: with the
/// project's main actor default isolation, its `NSFilePresenter` members would be main
/// actor isolated, and the file coordinator, which reads `presentedItemURL` and calls the
/// change methods on the presenter's queue, would trip Swift's isolation check and crash
/// holzBar as soon as sync was turned on.
private nonisolated final class SettingsSyncPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
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
