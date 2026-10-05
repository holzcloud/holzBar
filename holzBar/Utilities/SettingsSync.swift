//
//  SettingsSync.swift
//  holzBar
//

import AppKit
import IOKit
import Observation
import os
import OSLog
import SystemConfiguration

/// Keeps holzBar's settings in step across Macs through a file in a folder the Macs sync:
/// iCloud Drive or any folder the user chooses, such as a Nextcloud, Dropbox, OneDrive or
/// Syncthing folder or a network share (jordanbaird/Ice#95, SYNC-01).
///
/// iCloud's key-value store needs an iCloud entitlement, which an ad hoc signed
/// app cannot have, so the settings travel as `holzBar/Settings.plist` in the folder
/// instead. Each change of the user's settings is written there; newer settings from
/// another Mac are applied at launch, or when the user chooses Restart in a quiet hint in
/// the sync settings and the holzBar menu. When both Macs changed their settings, or a Mac
/// joins a folder that holds another Mac's different settings, holzBar asks which settings
/// to use, in a sheet on the Settings window, and overwrites neither unasked
/// (``SettingsSyncPolicy``, F-02). holzBar never opens a dialog by itself for sync: a modal
/// dialog would pause holzBar until it closed, and another Mac could open one at any time
/// (F-14). The folder's own app syncs the file; holzBar never connects to the network.
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
///
/// The file may be online-only, on a stalled network volume or held by a file provider
/// that hangs, so every access to it runs on one serial background queue (``fileQueue``),
/// never on the main thread; only the read at launch waits for it, at most a second, and
/// skips a file that is not on this Mac (F-15).
@MainActor
@Observable
final class SettingsSync {
    private static let logger = Logger(category: "SettingsSync")

    /// Keys that stay on this Mac.
    private nonisolated static let localKeys: Set<String> = [
        Defaults.Key.syncsSettingsWithICloud.rawValue,
        lastSyncedKey,
    ]

    private nonisolated static let lastSyncedKey = "SettingsSyncLastSynced"

    /// The key of the digest of the user settings this Mac last wrote or applied
    /// (``SettingsSyncPolicy/Local/base``). Without one, this Mac joins the folder.
    private static let baseKey = "SettingsSyncBaseDigest"

    /// The key of the date of a newer version from another Mac that waits for the user;
    /// while it waits, this Mac's changes are not written.
    private static let pendingKey = "SettingsSyncPendingModified"

    /// The key of this Mac's sync id. Keys starting with "SettingsSync" are never exported,
    /// imported or synced (`SettingsBackup.excludedKeyPrefixes`).
    private static let deviceIDKey = "SettingsSyncDeviceID"

    /// The queue of every access to the sync file and its folder, one at a time.
    private nonisolated static let fileQueue = DispatchQueue(label: "com.holzcloud.holzBar.SettingsSync", qos: .utility)

    /// How long the launch waits for the sync file.
    private nonisolated static let launchReadTimeout = DispatchTimeInterval.seconds(1)

    /// The key of the salt of the hardware hash (``deviceHashKey``).
    private static let deviceSaltKey = "SettingsSyncDeviceSalt"

    /// The key of the salted hash of the hardware UUID of the Mac the sync id belongs to
    /// (`SettingsSyncDevice.hardwareHash(of:salt:)`). Like the id, it is never exported,
    /// imported, synced or logged.
    private static let deviceHashKey = "SettingsSyncDeviceHash"

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

    /// Gives this Mac a new sync id when its defaults were copied from another Mac, by
    /// Migration Assistant, a restore or a clone (F-38).
    ///
    /// Two Macs with the same id take each other's files for their own and ignore each
    /// other's changes. A Mac with another Mac's defaults also forgets when it last synced,
    /// and joins the sync folder again. The first time, the id is replaced once as well, as
    /// it may already be shared, but the date of the last sync is kept.
    static func verifyDeviceIdentity() {
        let defaults = UserDefaults.standard
        let hardwareID = hardwareUUID()
        let identity = SettingsSyncDevice.identity(
            storedHash: defaults.string(forKey: deviceHashKey),
            salt: defaults.data(forKey: deviceSaltKey),
            hardwareID: hardwareID
        )
        switch identity {
        case .same, .unknown:
            return
        case .firstSeen:
            logger.notice("Gave this Mac a new sync id")
        case .otherMac:
            defaults.removeObject(forKey: lastSyncedKey)
            defaults.removeObject(forKey: baseKey)
            defaults.removeObject(forKey: pendingKey)
            logger.notice("This Mac's settings come from another Mac; it joins the sync folder again")
        }
        if let hardwareID {
            let salt = SettingsSyncDevice.makeSalt()
            defaults.set(salt, forKey: deviceSaltKey)
            defaults.set(SettingsSyncDevice.hardwareHash(of: hardwareID, salt: salt), forKey: deviceHashKey)
        }
        defaults.set(UUID().uuidString, forKey: deviceIDKey)
    }

    /// This Mac's hardware UUID, read from the I/O Registry. It never leaves this Mac and
    /// is never stored; only its salted hash is.
    private static func hardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != IO_OBJECT_NULL else {
            return nil
        }
        defer {
            IOObjectRelease(service)
        }
        return IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
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

    /// The sync file in the given synced folder.
    private static func fileURL(inFolder syncFolderURL: URL) -> URL {
        syncFolderURL
            .appending(path: SettingsSyncLocation.fileComponents[0], directoryHint: .isDirectory)
            .appending(path: SettingsSyncLocation.fileComponents[1])
    }

    /// The name of the synced folder to show, or `nil` when there is none. Updated while
    /// sync is on, when the folder is chosen, when a volume is mounted or unmounted, when the
    /// folder changes and when the settings show it (``refreshFolder()``), never in a view
    /// body.
    private(set) var folderDisplayName: String?

    /// Updates the name of the synced folder to show while sync is on, as the folder may
    /// have been moved, renamed or deleted since.
    func refreshFolder() {
        guard isEnabled else {
            return
        }
        updateFolderDisplayName()
    }

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
    ///
    /// Turning it on writes nothing: this Mac's settings are written when the user changes
    /// them, or when the folder is chosen (``chooseFolder()``).
    var isEnabled = false {
        didSet {
            Defaults.set(isEnabled, forKey: .syncsSettingsWithICloud)
            updateObservers()
            if oldValue, !isEnabled {
                forgetSyncState()
            }
        }
    }

    @ObservationIgnored private weak var appState: AppState?

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

    /// Whether the folder is being prepared on the file queue for the presenter.
    @ObservationIgnored private var isPreparingFolder = false

    /// The pending check after the sync file changed.
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    /// A push waited for the pending check, and is made once the check is done.
    @ObservationIgnored private var pushesAfterCheck = false

    /// The exchange with the sync file that runs now; one at a time.
    @ObservationIgnored private var exchangeTask: Task<Void, Never>?

    /// The exchanges requested while another one ran, each made once afterwards.
    @ObservationIgnored private var queuedExchanges: Set<ExchangeKind> = []

    /// The date of the version the user answered "Later" for in this session.
    @ObservationIgnored private var postponed: Date?

    /// Whether a sync question is open.
    @ObservationIgnored private var isAsking = false

    /// A check waited for the open question, and is made once it is answered.
    @ObservationIgnored private var checksAfterPrompt = false

    /// Whether the folder chosen by the user is being joined.
    @ObservationIgnored private var isChoosingFolder = false

    /// What holzBar offers for a newer version from another Mac that waits for the user,
    /// shown in the sync settings and the holzBar menu; `nil` when none waits.
    private(set) var hint: SettingsSyncPolicy.Hint?

    /// The version from another Mac the hint is about.
    @ObservationIgnored private var waitingVersion: RemoteVersion?

    /// A question that waits for the Settings window to be on screen, to show as a sheet
    /// on it.
    @ObservationIgnored private var settingsWindowWait: SettingsWindowWait?

    func performSetup(with appState: AppState) {
        self.appState = appState
        isEnabled = Defaults.bool(forKey: .syncsSettingsWithICloud)
        if isEnabled {
            // The launch skipped a file that was not on this Mac and never asks; check
            // the file once now.
            syncFileDidChange()
        }
    }

    /// Starts or stops observing the settings and the sync file, as sync is on or off.
    ///
    /// - Parameter checksNewFolder: Whether to check the sync file once a folder is
    ///   watched that was not before.
    private func updateObservers(checksNewFolder: Bool = false) {
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

        if presenter == nil, !isPreparingFolder, let folderURL = Self.folderURL {
            prepareFolder(folderURL, checksAfterwards: checksNewFolder)
        }
    }

    /// The closure the presenter and the folder watcher call when the folder changes.
    private func makeChangeHandler() -> @Sendable () -> Void {
        { [weak self] in
            guard let self else {
                return
            }
            Task { @MainActor in
                self.syncFileDidChange()
            }
        }
    }

    /// Creates the holzBar folder and its watcher on the file queue, then watches it with a
    /// presenter if sync is still on with the same folder.
    private func prepareFolder(_ folderURL: URL, checksAfterwards: Bool) {
        isPreparingFolder = true
        let onChange = makeChangeHandler()
        Task { [weak self] in
            let preparation = await Self.prepare(folderURL, onChange: onChange)
            guard let self else {
                preparation.watcher?.cancel()
                return
            }
            isPreparingFolder = false
            guard isEnabled, presenter == nil, Self.folderURL == folderURL else {
                preparation.watcher?.cancel()
                if isEnabled, presenter == nil, Self.folderURL != folderURL {
                    // The folder changed meanwhile.
                    updateObservers(checksNewFolder: checksAfterwards)
                }
                return
            }
            switch preparation {
            case .unusable:
                // Anyone who can write the synced folder could make the holzBar folder a
                // link to another folder of the user's; holzBar then neither watches nor
                // writes it.
                Self.logger.error("The holzBar folder in the sync folder is a link or a file, not syncing")
            case .ready(let watcher, let creationError):
                if let creationError {
                    Self.logger.error("Error creating the holzBar folder in the sync folder: \(creationError, privacy: .private)")
                }
                let presenter = SettingsSyncPresenter(folderURL: folderURL, onChange: onChange)
                NSFileCoordinator.addFilePresenter(presenter)
                self.presenter = presenter
                folderWatcher = watcher
                Self.logger.info("Watching the sync file")
                if checksAfterwards {
                    syncFileDidChange()
                }
            }
        }
    }

    /// What preparing the holzBar folder gave.
    private nonisolated enum FolderPreparation: Sendable {
        /// The holzBar folder is a link or a file.
        case unusable
        /// The folder exists, or creating it failed with the given error; the watcher is
        /// `nil` when the folder could not be opened.
        case ready(SettingsSyncFolderWatcher?, creationError: String?)

        var watcher: SettingsSyncFolderWatcher? {
            if case .ready(let watcher, _) = self {
                return watcher
            }
            return nil
        }
    }

    /// Checks and creates the holzBar folder and opens its watcher, on the file queue.
    @concurrent
    private nonisolated static func prepare(_ folderURL: URL, onChange: @escaping @Sendable () -> Void) async -> FolderPreparation {
        await BlockingWork.run(on: fileQueue) {
            guard SettingsSyncFile.isUsableFolder(atPath: folderURL.path(percentEncoded: false)) else {
                return .unusable
            }
            var creationError: String?
            do {
                try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            } catch {
                creationError = String(describing: error)
            }
            return .ready(SettingsSyncFolderWatcher(folderURL: folderURL, onChange: onChange), creationError: creationError)
        }
    }

    /// Watches the sync folder again when a volume was mounted or unmounted and the folder
    /// became available, moved or gone.
    ///
    /// A folder that has just become available, such as a network share mounted after
    /// launch, may hold newer settings from another Mac, so it is checked once it is
    /// watched.
    private func volumesDidChange() {
        if presenter?.presentedItemURL != Self.folderURL {
            stopWatchingFolder()
        }
        updateObservers(checksNewFolder: true)
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

    /// Forgets the state of the folder when sync is turned off, so turning it on joins
    /// the folder again.
    private func forgetSyncState() {
        UserDefaults.standard.removeObject(forKey: Self.baseKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)
        postponed = nil
        exchangeTask?.cancel()
        exchangeTask = nil
        queuedExchanges = []
        withdrawHint()
    }

    // MARK: Folder

    /// A folder the user chose, until it is joined.
    private struct JoinRequest {
        /// The chosen folder.
        let folderURL: URL
    }

    /// Lets the user choose the folder the Macs sync, and turns sync on with it.
    ///
    /// Nothing is stored before the sync file in the folder has been read off the main
    /// thread. When it holds another Mac's different settings, holzBar asks which settings
    /// to use, as a sheet on the Settings window, which opens again if it was closed
    /// meanwhile; until the answer, sync stays off or keeps the previous folder. Otherwise
    /// the folder is stored and this Mac's settings are written there, unless the file
    /// already holds them.
    ///
    /// - Returns: Whether a folder was chosen; joining it goes on afterwards.
    @discardableResult
    func chooseFolder() -> Bool {
        guard !isChoosingFolder else {
            return false
        }
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
        Self.verifyDeviceIdentity()
        let join = JoinRequest(folderURL: url)
        // A join ignores the previous folder's state: this Mac has not synced with the
        // chosen folder yet.
        guard
            let request = makeRequest(
                .push,
                fileURL: Self.fileURL(inFolder: url),
                base: nil,
                pending: nil,
                lastSynced: nil,
                postponed: nil,
                presenter: nil
            )
        else {
            return false
        }
        isChoosingFolder = true
        Task { [weak self] in
            let result = await Self.exchange(request)
            self?.finishJoin(join, request: request, result: result)
        }
        return true
    }

    /// Stores the chosen folder, or asks which settings to use first.
    private func finishJoin(_ join: JoinRequest, request: ExchangeRequest, result: ExchangeResult) {
        Self.log(result.problem)
        guard result.action == .ask, let remote = result.remote else {
            commitJoin(join)
            switch result.action {
            case .write:
                Self.markSynced(base: request.local.userDigest, modified: result.written)
                Self.logger.info("Wrote settings to the sync folder")
            case .adopt:
                Self.markSynced(base: request.local.userDigest, modified: result.remote?.modified)
            default:
                // The file could not be read; the folder is joined once it can.
                break
            }
            isChoosingFolder = false
            return
        }
        guard !isAsking else {
            // Another question is open; the folder is not joined.
            isChoosingFolder = false
            return
        }
        showSettings(
            forHint: false,
            onCancel: { [weak self] in
                self?.isChoosingFolder = false
            },
            then: { [weak self] window in
                guard let self, !isAsking else {
                    self?.isChoosingFolder = false
                    return
                }
                ask(about: remote, isJoining: true, on: window, join: join)
            }
        )
    }

    /// Stores the chosen folder and turns sync on with it, as a join: without the
    /// previous folder's state.
    private func commitJoin(_ join: JoinRequest) {
        stopWatchingFolder()
        Self.storeBookmark(of: join.folderURL)
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.lastSyncedKey)
        defaults.removeObject(forKey: Self.baseKey)
        defaults.removeObject(forKey: Self.pendingKey)
        postponed = nil
        withdrawHint()
        if isEnabled {
            updateObservers()
        } else {
            isEnabled = true
        }
    }

    // MARK: Checks and Pushes

    /// Checks the sync file shortly after it changed, once for a burst of changes.
    private func syncFileDidChange() {
        updateFolderDisplayName()
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            // A cancelled check was replaced by a newer one, or sync was turned off.
            guard !Task.isCancelled, let self else {
                return
            }
            checkTask = nil
            checkNow()
        }
    }

    /// Checks the sync file, and then makes the push that waited for the check.
    private func checkNow() {
        // An open question is about a version of the file; check once it is answered.
        guard !isAsking else {
            checksAfterPrompt = true
            return
        }
        requestExchange(.check)
        if pushesAfterCheck {
            pushesAfterCheck = false
            requestExchange(.push)
        }
    }

    /// Writes the settings to the sync folder, if syncing is on and the user's settings
    /// changed since this Mac last synced.
    func settingsDidChange() {
        guard isEnabled else {
            return
        }
        // While a version from another Mac waits, nothing is pushed, so Restart would
        // overwrite this change: the hint becomes the question instead.
        refreshHint()
        // A pending check may find newer settings from another Mac; push once the check
        // is done.
        guard checkTask == nil else {
            pushesAfterCheck = true
            return
        }
        requestExchange(.push)
    }

    /// The settings that are synced: holzBar's own, without the keys that stay on this Mac.
    private static func syncedSettings() -> [String: Any] {
        SettingsBackup.currentSettings().filter { !localKeys.contains($0.key) }
    }

    /// Remembers that this Mac has synced the given user settings with the file of the
    /// given date, and that no version waits for the user.
    private static func markSynced(base: String, modified: Date?) {
        let defaults = UserDefaults.standard
        defaults.set(base, forKey: baseKey)
        if let modified {
            let lastSynced = defaults.object(forKey: lastSyncedKey) as? Date ?? .distantPast
            defaults.set(max(lastSynced, modified), forKey: lastSyncedKey)
        }
        defaults.removeObject(forKey: pendingKey)
    }

    /// Remembers the date of the version that waits for the user, or that none waits.
    private static func setPending(_ modified: Date?) {
        if let modified {
            UserDefaults.standard.set(modified, forKey: pendingKey)
        } else {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
    }

    // MARK: Exchanges

    /// What an exchange with the sync file is for.
    private nonisolated enum ExchangeKind: Int, Comparable, Sendable {
        /// This Mac's settings changed.
        case push
        /// The file changed.
        case check
        /// The user chose to keep this Mac's settings.
        case keepThisMac

        /// The trigger of the decision.
        var trigger: SettingsSyncPolicy.Trigger {
            self == .check ? .check : .localChange
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// A version of the sync file from another Mac, kept until the user decides.
    private nonisolated struct RemoteVersion: Sendable {
        /// When the version was written.
        let modified: Date
        /// Its settings, as a binary property list.
        let settingsData: Data

        /// Its settings.
        var settings: [String: Any]? {
            (try? PropertyListSerialization.propertyList(from: settingsData, format: nil)) as? [String: Any]
        }
    }

    /// Everything an exchange needs, gathered on the main actor.
    private nonisolated struct ExchangeRequest: Sendable {
        let kind: ExchangeKind
        let local: SettingsSyncPolicy.Local
        let fileURL: URL
        /// This Mac's synced settings, as a binary property list.
        let settingsData: Data
        let lastSynced: Date?
        let deviceID: String
        let computerName: String?
        /// This Mac's presenter, so it is not told about its own write.
        let presenter: SettingsSyncPresenter?
    }

    /// Why an exchange did not go as planned, for the log.
    private nonisolated enum ExchangeProblem: Sendable {
        /// The holzBar folder is a link or a file.
        case unusableFolder
        /// The file was not used, for the given reason.
        case ignoredFile(String)
        /// Reading or writing failed with the given error.
        case failed(String)
    }

    /// What an exchange did.
    private nonisolated struct ExchangeResult: Sendable {
        /// The decision; `.write` only when the settings were written.
        var action: SettingsSyncPolicy.Action
        /// The version in the file, if it holds one.
        var remote: RemoteVersion?
        /// The date written into the file.
        var written: Date?
        var problem: ExchangeProblem?
    }

    /// What reading the sync file gave, as the decision sees it.
    private nonisolated struct Inspection {
        var file: SettingsSyncPolicy.File
        /// The file's settings, without the keys that stay on each Mac.
        var settings: [String: Any]?
        var remote: RemoteVersion?
        var problem: ExchangeProblem?
    }

    /// Gathers what an exchange needs.
    ///
    /// - Returns: The request, or `nil` when the exchange is not needed: a push of
    ///   settings that did not change since the last sync, or while a version from another
    ///   Mac waits for the user (``SettingsSyncPolicy/needsExchange(_:local:)``).
    private func makeRequest(
        _ kind: ExchangeKind,
        fileURL: URL,
        base: String?,
        pending: Date?,
        lastSynced: Date?,
        postponed: Date?,
        presenter: SettingsSyncPresenter?
    ) -> ExchangeRequest? {
        let settings = Self.syncedSettings()
        let local = SettingsSyncPolicy.Local(
            userDigest: SettingsSyncPolicy.userDigest(of: settings),
            base: base,
            pending: pending,
            postponed: postponed,
            forcesWrite: kind == .keepThisMac
        )
        guard SettingsSyncPolicy.needsExchange(kind.trigger, local: local) else {
            return nil
        }
        guard let settingsData = try? PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0) else {
            Self.logger.error("Could not encode the settings for the sync folder")
            return nil
        }
        return ExchangeRequest(
            kind: kind,
            local: local,
            fileURL: fileURL,
            settingsData: settingsData,
            lastSynced: lastSynced,
            deviceID: Self.deviceID,
            computerName: Self.computerName,
            presenter: presenter
        )
    }

    /// Makes an exchange with the sync file of the current folder, or makes it after the
    /// one that runs now.
    private func requestExchange(_ kind: ExchangeKind) {
        guard isEnabled else {
            return
        }
        guard exchangeTask == nil else {
            queuedExchanges.insert(kind)
            return
        }
        guard let fileURL = Self.fileURL else {
            Self.logger.warning("No sync folder, not syncing settings")
            updateFolderDisplayName()
            return
        }
        let defaults = UserDefaults.standard
        guard
            let request = makeRequest(
                kind,
                fileURL: fileURL,
                base: defaults.string(forKey: Self.baseKey),
                pending: defaults.object(forKey: Self.pendingKey) as? Date,
                lastSynced: defaults.object(forKey: Self.lastSyncedKey) as? Date,
                postponed: postponed,
                presenter: presenter
            )
        else {
            runQueuedExchange()
            return
        }
        exchangeTask = Task { [weak self] in
            let result = await Self.exchange(request)
            // A cancelled exchange belongs to sync that was turned off.
            guard !Task.isCancelled, let self else {
                return
            }
            exchangeTask = nil
            handle(result, of: request)
            runQueuedExchange()
        }
    }

    /// Makes the most important exchange that waited, if no exchange runs.
    private func runQueuedExchange() {
        guard exchangeTask == nil, let next = queuedExchanges.max() else {
            return
        }
        queuedExchanges.remove(next)
        requestExchange(next)
    }

    /// Acts on the result of an exchange while holzBar runs.
    private func handle(_ result: ExchangeResult, of request: ExchangeRequest) {
        // Sync was turned off or the folder changed while the exchange ran.
        guard isEnabled, request.fileURL == Self.fileURL else {
            return
        }
        Self.log(result.problem)
        switch result.action {
        case .none:
            Self.setPending(nil)
            withdrawHint()
        case .wait, .retry:
            break
        case .adopt:
            Self.markSynced(base: request.local.userDigest, modified: result.remote?.modified)
            withdrawHint()
        case .write:
            if request.kind == .check {
                // A check never writes; this Mac's changes are pushed with a read of their
                // own.
                Self.setPending(nil)
                withdrawHint()
                requestExchange(.push)
            } else {
                Self.markSynced(base: request.local.userDigest, modified: result.written)
                withdrawHint()
                Self.logger.info("Wrote settings to the sync folder")
            }
        case .apply, .ask:
            guard let remote = result.remote else {
                return
            }
            // Pending first, so no push overwrites the version while the hint is shown.
            Self.setPending(remote.modified)
            offer(remote, local: request.local)
        }
    }

    /// Logs why an exchange did not go as planned.
    private static func log(_ problem: ExchangeProblem?) {
        switch problem {
        case .unusableFolder:
            logger.error("The holzBar folder in the sync folder is a link or a file, not syncing")
        case .ignoredFile(let reason):
            logger.error("Ignoring the sync file: \(reason, privacy: .public)")
        case .failed(let error):
            logger.error("Error syncing settings with the sync folder: \(error, privacy: .private)")
        case nil:
            break
        }
    }

    /// Makes an exchange with the sync file on the file queue, off the main thread.
    @concurrent
    private nonisolated static func exchange(_ request: ExchangeRequest) async -> ExchangeResult {
        await BlockingWork.run(on: fileQueue) {
            performExchange(request)
        }
    }

    /// Reads the sync file, decides, and writes this Mac's settings when the decision
    /// says so.
    ///
    /// A push reads and writes in one coordinated access, so no other coordinated writer,
    /// such as iCloud Drive, can replace the file between the read and the write. A check
    /// only reads.
    private nonisolated static func performExchange(_ request: ExchangeRequest) -> ExchangeResult {
        // Anyone who can write the synced folder could make the holzBar folder a link to
        // another folder of the user's; holzBar then neither reads nor writes it.
        let folderPath = request.fileURL.deletingLastPathComponent().path(percentEncoded: false)
        guard SettingsSyncFile.isUsableFolder(atPath: folderPath) else {
            return ExchangeResult(action: .retry, problem: .unusableFolder)
        }
        let trigger = request.kind.trigger
        guard request.kind != .check else {
            let read = readFileContents(at: request.fileURL, coordinator: NSFileCoordinator(filePresenter: nil))
            let inspection = inspect(read, lastSynced: request.lastSynced, deviceID: request.deviceID, computerName: request.computerName)
            return ExchangeResult(
                action: SettingsSyncPolicy.decide(trigger, local: request.local, file: inspection.file),
                remote: inspection.remote,
                problem: inspection.problem
            )
        }
        var result = ExchangeResult(action: .retry)
        var coordinationError: NSError?
        // This Mac's presenter is not told about its own write (its folder watcher is, and
        // finds the file its own).
        NSFileCoordinator(filePresenter: request.presenter).coordinate(
            readingItemAt: request.fileURL,
            options: [],
            writingItemAt: request.fileURL,
            options: .forReplacing,
            error: &coordinationError
        ) { readingURL, writingURL in
            let read = SettingsSyncFile.readContents(atPath: readingURL.path(percentEncoded: false))
            let inspection = inspect(read, lastSynced: request.lastSynced, deviceID: request.deviceID, computerName: request.computerName)
            let action = SettingsSyncPolicy.decide(trigger, local: request.local, file: inspection.file)
            guard action == .write else {
                result = ExchangeResult(action: action, remote: inspection.remote, problem: inspection.problem)
                return
            }
            result = write(request, fileSettings: inspection.settings, to: writingURL)
        }
        if let coordinationError {
            return ExchangeResult(action: .retry, problem: .failed(String(describing: coordinationError)))
        }
        return result
    }

    /// Writes this Mac's settings into the sync file, with the learned settings merged
    /// with the file's.
    private nonisolated static func write(_ request: ExchangeRequest, fileSettings: [String: Any]?, to fileURL: URL) -> ExchangeResult {
        guard let settings = (try? PropertyListSerialization.propertyList(from: request.settingsData, format: nil)) as? [String: Any] else {
            return ExchangeResult(action: .retry, problem: .failed("The settings could not be decoded"))
        }
        let modified = Date.now
        // The id alone tells the Macs apart; the computer name, which usually holds the
        // owner's name, stays on this Mac.
        let file: [String: Any] = [
            SettingsSyncFile.modifiedKey: modified,
            SettingsSyncDevice.deviceIDKey: request.deviceID,
            SettingsSyncFile.settingsKey: SettingsSyncPolicy.settingsToWrite(settings, file: fileSettings),
        ]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: file, format: .xml, options: 0)
            try data.write(to: fileURL, options: .atomic)
            return ExchangeResult(action: .write, written: modified)
        } catch {
            return ExchangeResult(action: .retry, problem: .failed(String(describing: error)))
        }
    }

    /// Turns what reading the sync file gave into what the decision needs.
    private nonisolated static func inspect(
        _ read: SettingsSyncFile.ReadResult,
        lastSynced: Date?,
        deviceID: String,
        computerName: String?
    ) -> Inspection {
        let data: Data
        switch read {
        case .contents(let contents):
            data = contents
        case .missing:
            return Inspection(file: .missing)
        case .refused(let refusal):
            let reason = String(describing: refusal)
            return Inspection(file: refusal == .unreadable ? .unreadable : .unusable, problem: .ignoredFile(reason))
        }
        guard
            let file = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
            let contents = SettingsSyncFile.contents(
                of: file,
                lastSynced: lastSynced,
                deviceID: deviceID,
                computerName: computerName,
                localKeys: localKeys
            ),
            let settingsData = try? PropertyListSerialization.data(fromPropertyList: contents.settings, format: .binary, options: 0)
        else {
            return Inspection(file: .unusable, problem: .ignoredFile("it holds no settings"))
        }
        let version = SettingsSyncPolicy.Version(
            isFromThisMac: contents.isFromThisMac,
            modified: contents.modified,
            isNewer: contents.isNewer,
            userDigest: SettingsSyncPolicy.userDigest(of: contents.settings)
        )
        return Inspection(
            file: .version(version),
            settings: contents.settings,
            remote: RemoteVersion(modified: contents.modified, settingsData: settingsData)
        )
    }

    /// Reads the sync file with a coordinated read, so a version iCloud Drive is still
    /// writing is never read half.
    ///
    /// Anyone who can write the synced folder can write the file, so it is read only from a
    /// real `holzBar` folder, only when it is a regular file reached without a symbolic link,
    /// and only up to `SettingsSyncFile.maximumFileSize` bytes. Runs on the file queue.
    /// No presenter is passed: holzBar's presenter does nothing for a read.
    private nonisolated static func readFileContents(at fileURL: URL, coordinator: NSFileCoordinator) -> SettingsSyncFile.ReadResult {
        let folderPath = fileURL.deletingLastPathComponent().path(percentEncoded: false)
        guard SettingsSyncFile.isUsableFolder(atPath: folderPath) else {
            return .refused(.notRegularFile)
        }
        var coordinationError: NSError?
        var result = SettingsSyncFile.ReadResult.missing
        coordinator.coordinate(
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

    // MARK: Launch

    /// Reads the sync file for the launch, waiting at most ``launchReadTimeout``.
    ///
    /// The read runs on the file queue. A file whose contents are not on this Mac (an
    /// online-only file) is not read at all, so the launch never waits for a download;
    /// a read that takes longer, as on a stalled network volume or with a file provider
    /// that hangs, is cancelled.
    ///
    /// - Returns: What reading gave, or `nil` when the file was not read.
    private nonisolated static func readForLaunch(at fileURL: URL) -> SettingsSyncFile.ReadResult? {
        let coordinator = LaunchCoordinator()
        let result = OSAllocatedUnfairLock<SettingsSyncFile.ReadResult?>(initialState: nil)
        let done = DispatchSemaphore(value: 0)
        fileQueue.async {
            defer {
                done.signal()
            }
            guard isLocal(fileURL) else {
                return
            }
            let read = readFileContents(at: fileURL, coordinator: coordinator.coordinator)
            result.withLock { $0 = read }
        }
        guard done.wait(timeout: .now() + launchReadTimeout) == .success else {
            coordinator.coordinator.cancel()
            return nil
        }
        return result.withLock { $0 }
    }

    /// Whether the contents of the file are on this Mac, or there is no file
    /// (`SettingsSyncFile.isLocal(flags:isUbiquitous:downloadingStatus:)`).
    private nonisolated static func isLocal(_ fileURL: URL) -> Bool {
        var status = stat()
        guard lstat(fileURL.path(percentEncoded: false), &status) == 0 else {
            // A missing file, or one the read reports as unreadable.
            return true
        }
        let values = try? fileURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return SettingsSyncFile.isLocal(
            flags: status.st_flags,
            isUbiquitous: values?.isUbiquitousItem,
            downloadingStatus: values?.ubiquitousItemDownloadingStatus
        )
    }

    /// Applies newer settings from another Mac before anything reads the settings, when
    /// this Mac's settings did not change since it last synced. The app delegate calls
    /// this before it creates the app state.
    ///
    /// It waits for the file on the main thread, because nothing may read the settings
    /// before they are applied, but at most a second, and not at all for a file that is
    /// not on this Mac; the check after setup reads it then (``readForLaunch(at:)``). It
    /// never writes the file and never asks: when both Macs changed their settings, the
    /// version is remembered and the check after setup asks.
    static func pullIfNeeded() {
        guard Defaults.bool(forKey: .syncsSettingsWithICloud) else {
            return
        }
        verifyDeviceIdentity()
        guard let fileURL else {
            return
        }
        guard let read = readForLaunch(at: fileURL) else {
            logger.info("The sync file is not on this Mac yet; checking it after launch")
            return
        }
        let defaults = UserDefaults.standard
        let settings = syncedSettings()
        let inspection = inspect(
            read,
            lastSynced: defaults.object(forKey: lastSyncedKey) as? Date,
            deviceID: deviceID,
            computerName: computerName
        )
        log(inspection.problem)
        let local = SettingsSyncPolicy.Local(
            userDigest: SettingsSyncPolicy.userDigest(of: settings),
            base: defaults.string(forKey: baseKey),
            pending: defaults.object(forKey: pendingKey) as? Date,
            postponed: nil,
            forcesWrite: false
        )
        switch SettingsSyncPolicy.decide(.launch, local: local, file: inspection.file) {
        case .apply:
            guard let remote = inspection.settings, let modified = inspection.remote?.modified else {
                return
            }
            SettingsBackup.apply(SettingsSyncPolicy.settingsToApply(remote, over: settings), removesMissingKeys: false)
            Defaults.set(true, forKey: .syncsSettingsWithICloud)
            markSynced(base: SettingsSyncPolicy.userDigest(of: syncedSettings()), modified: modified)
            logger.notice("Applied settings from the sync folder")
            return
        case .adopt:
            markSynced(base: local.userDigest, modified: inspection.remote?.modified)
        case .ask:
            setPending(inspection.remote?.modified)
        case .none:
            setPending(nil)
        case .write, .wait, .retry:
            break
        }
        // What the other Macs have learned (``SettingsSyncPolicy/learnedKeys``) never asks;
        // a Mac that has synced takes it in silently.
        if defaults.string(forKey: baseKey) != nil, let remote = inspection.settings {
            let learned = SettingsSyncPolicy.learnedSettings(merging: remote, into: settings)
            if !learned.isEmpty {
                SettingsBackup.apply(learned, removesMissingKeys: false)
            }
        }
    }

    // MARK: Hints and Questions

    /// A question that waits for the Settings window to be on screen.
    private struct SettingsWindowWait {
        /// Observes whether the Settings window is on screen.
        let loop: ObservationLoop
        /// Whether the question is about the waiting version, rather than a chosen folder.
        let isForHint: Bool
        /// Called when a newer question or the end of the hint replaces this one.
        let onCancel: @MainActor () -> Void
    }

    /// Offers a newer version from another Mac through the hint. holzBar never asks about
    /// it by itself.
    private func offer(_ remote: RemoteVersion, local: SettingsSyncPolicy.Local) {
        waitingVersion = remote
        let offered = SettingsSyncPolicy.hint(for: local)
        if hint != offered {
            hint = offered
            Self.logger.info("Settings from another Mac wait for the user")
        }
    }

    /// Takes the hint away: no version from another Mac waits any more.
    private func withdrawHint() {
        waitingVersion = nil
        if hint != nil {
            hint = nil
        }
        if settingsWindowWait?.isForHint == true {
            cancelSettingsWindowWait()
        }
    }

    /// Decides the hint again from this Mac's current settings, as a change made since the
    /// version arrived turns a restart into a question.
    private func refreshHint() {
        guard waitingVersion != nil else {
            return
        }
        let defaults = UserDefaults.standard
        let local = SettingsSyncPolicy.Local(
            userDigest: SettingsSyncPolicy.userDigest(of: Self.syncedSettings()),
            base: defaults.string(forKey: Self.baseKey),
            pending: defaults.object(forKey: Self.pendingKey) as? Date,
            postponed: postponed,
            forcesWrite: false
        )
        let refreshed = SettingsSyncPolicy.hint(for: local)
        if hint != refreshed {
            hint = refreshed
        }
    }

    /// Applies the waiting version from another Mac and restarts, as the hint's Restart
    /// offers; asks instead when this Mac's settings changed since the version arrived.
    func restartWithWaitingSettings() {
        guard let remote = waitingVersion, !isAsking else {
            return
        }
        refreshHint()
        guard hint == .restart else {
            chooseSettings()
            return
        }
        use(remote, join: nil)
    }

    /// Asks which settings to use for the waiting version from another Mac, in a sheet on
    /// the Settings window, which opens for it.
    func chooseSettings() {
        guard waitingVersion != nil else {
            return
        }
        showSettings(forHint: true) { [weak self] window in
            self?.askAboutWaitingVersion(on: window)
        }
    }

    /// Asks about the waiting version from another Mac in a sheet on the given window.
    private func askAboutWaitingVersion(on window: NSWindow) {
        guard isEnabled, !isAsking, let remote = waitingVersion else {
            return
        }
        refreshHint()
        let isJoining = if case .choice(let isJoining) = hint { isJoining } else { false }
        ask(about: remote, isJoining: isJoining, on: window, join: nil)
    }

    /// Shows the Settings window on the Advanced pane, and then calls `present` with it
    /// once it is on screen, without polling. A newer request replaces one that still waits.
    private func showSettings(
        forHint isForHint: Bool,
        onCancel: @escaping @MainActor () -> Void = {},
        then present: @escaping @MainActor (NSWindow) -> Void
    ) {
        cancelSettingsWindowWait()
        guard let appState else {
            onCancel()
            return
        }
        let navigationState = appState.navigationState
        navigationState.settingsNavigationIdentifier = .advanced
        if navigationState.isSettingsPresented, let window = navigationState.settingsWindow {
            appState.activate(for: .settings)
            window.makeKeyAndOrderFront(nil)
            present(window)
            return
        }
        let loop = ObservationLoop.observe { navigationState.isSettingsPresented } onChange: { [weak self] isPresented in
            guard isPresented, let self, let window = navigationState.settingsWindow else {
                return
            }
            settingsWindowWait?.loop.cancel()
            settingsWindowWait = nil
            present(window)
        }
        settingsWindowWait = SettingsWindowWait(loop: loop, isForHint: isForHint, onCancel: onCancel)
        // While permissions are missing, their window opens instead; the question waits.
        guard !appState.openPermissionsWindowIfNeeded() else {
            return
        }
        appState.activate(for: .settings)
        appState.openWindow(.settings)
    }

    /// Drops the question that waits for the Settings window.
    private func cancelSettingsWindowWait() {
        guard let wait = settingsWindowWait else {
            return
        }
        settingsWindowWait = nil
        wait.loop.cancel()
        wait.onCancel()
    }

    /// Asks which settings to use, in a sheet on the given window. A sheet starts no nested
    /// run loop, so holzBar goes on running while it is open (F-14).
    private func ask(about remote: RemoteVersion, isJoining: Bool, on window: NSWindow, join: JoinRequest?) {
        isAsking = true
        let alert = makeAlert(isJoining: isJoining)
        Task {
            let response = await alert.beginSheetModal(for: window)
            answer(remote, isJoining: isJoining, response: response, join: join)
        }
    }

    /// The alert that asks which settings to use.
    private func makeAlert(isJoining: Bool) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Which settings should holzBar use?")
        alert.informativeText = String(localized: "The sync folder holds settings from another Mac that differ from this Mac's. Using them restarts holzBar; keeping this Mac's settings replaces them in the sync folder.")
        alert.addButton(withTitle: String(localized: "Use Settings from Sync Folder"))
        alert.addButton(withTitle: String(localized: "Keep This Mac's Settings"))
        let third = alert.addButton(withTitle: isJoining ? String(localized: "Cancel") : String(localized: "Later"))
        // Escape in every language, not only for the English title.
        third.keyEquivalent = "\u{1B}"
        return alert
    }

    /// Acts on the answer to the question.
    private func answer(_ remote: RemoteVersion, isJoining: Bool, response: NSApplication.ModalResponse, join: JoinRequest?) {
        if join != nil {
            isChoosingFolder = false
        }
        switch response {
        case .alertFirstButtonReturn:
            isAsking = false
            use(remote, join: join)
            return
        case .alertSecondButtonReturn:
            keepThisMac(join: join)
        default:
            if join != nil {
                // Sync stays off, or keeps the previous folder.
                break
            } else if isJoining {
                isEnabled = false
            } else {
                // The hint stays; asked again after the next launch. Until then, pushes
                // stay paused.
                postponed = remote.modified
            }
        }
        promptDidClose()
    }

    /// Makes the check that waited for the question.
    private func promptDidClose() {
        isAsking = false
        if checksAfterPrompt {
            checksAfterPrompt = false
            checkNow()
        }
    }

    /// Applies the version from another Mac, without removing the settings it lacks, and
    /// restarts, as every model reads its settings once at launch.
    private func use(_ remote: RemoteVersion, join: JoinRequest?) {
        guard let remoteSettings = remote.settings else {
            return
        }
        if let join {
            commitJoin(join)
        }
        SettingsBackup.apply(SettingsSyncPolicy.settingsToApply(remoteSettings, over: Self.syncedSettings()), removesMissingKeys: false)
        Self.markSynced(base: SettingsSyncPolicy.userDigest(of: Self.syncedSettings()), modified: remote.modified)
        postponed = nil
        withdrawHint()
        Defaults.set(true, forKey: .syncsSettingsWithICloud)
        Self.logger.notice("Applied settings from the sync folder")
        SettingsBackup.relaunch()
    }

    /// Writes this Mac's settings over the version from another Mac.
    private func keepThisMac(join: JoinRequest?) {
        if let join {
            commitJoin(join)
        }
        postponed = nil
        requestExchange(.keepThisMac)
    }
}

// MARK: - LaunchCoordinator

/// The file coordinator of the read at launch, which the launch cancels when the read
/// takes too long. `NSFileCoordinator.cancel()` may be called from any thread.
private nonisolated final class LaunchCoordinator: @unchecked Sendable {
    let coordinator = NSFileCoordinator(filePresenter: nil)
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
