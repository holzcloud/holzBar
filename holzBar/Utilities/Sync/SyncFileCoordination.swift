//
//  SyncFileCoordination.swift
//  holzBar
//

import Foundation
import os.lock

/// The file coordination, the change watching and the downloads of the sync folder.
///
/// iCloud Drive replaces a file through file coordination, and a coordinated read never sees half
/// of a file. Without an iCloud entitlement, the metadata query of the ubiquitous scopes is out of
/// reach, so a file presenter on the folder hears about every version that arrives from another
/// Mac, with no polling. Other sync apps replace files without coordination; a file system event
/// source on the folder hears about those.
///
/// Everything here blocks or runs off the main thread, and every type is `nonisolated`: the host
/// (`SettingsSync`) calls it only from its file queue, with a time limit, because a file provider
/// that hangs would otherwise stall whoever waits for it. A coordination that is not granted in
/// time is cancelled.
nonisolated enum SyncFileCoordination {
    // MARK: Places

    /// The user's home folder.
    static var homeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// iCloud Drive's folder, if iCloud Drive is turned on. It looks at the file system, so it belongs on the file queue.
    static func iCloudDriveURL() -> URL? {
        let url = homeDirectory.appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The state store over the Application Support and Caches folders of the user. It only builds the paths.
    static func makeStateStore() -> SyncStateStore {
        let manager = FileManager.default
        return SyncStateStore(
            supportDirectory: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory,
            cachesDirectory: manager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? manager.temporaryDirectory
        )
    }

    // MARK: Presenters

    /// Registers the presenter that hears the versions iCloud Drive brings.
    static func add(_ presenter: SyncFolderPresenter) {
        NSFileCoordinator.addFilePresenter(presenter)
    }

    static func remove(_ presenter: SyncFolderPresenter) {
        NSFileCoordinator.removeFilePresenter(presenter)
    }

    // MARK: Folder kinds

    /// Whether the folder is in iCloud Drive, whose files are coordinated.
    static func isICloudDrive(_ url: URL) -> Bool {
        url.path(percentEncoded: false).contains("/Library/Mobile Documents/")
    }

    /// Whether the volume of the folder is on this Mac. File events do not see what another computer writes
    /// to a network volume, so the host polls those more often.
    static func isLocalVolume(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal ?? true
    }

    /// The folder to watch: `holzBar/Macs` when it exists, else `holzBar`, else the sync folder, so that
    /// the watcher hears the folders appear that the first write creates.
    static func watchTarget(for syncFolder: URL) -> URL {
        let macs = syncFolder.appending(path: SyncFolderLayout.folderName, directoryHint: .notDirectory)
            .appending(path: SyncFolderLayout.devicesName, directoryHint: .notDirectory)
        if SyncFolderLayout.kind(atPath: SyncFolderLayout.path(of: macs), followingLinks: false) == .folder {
            return macs
        }
        let holzBar = syncFolder.appending(path: SyncFolderLayout.folderName, directoryHint: .notDirectory)
        if SyncFolderLayout.kind(atPath: SyncFolderLayout.path(of: holzBar), followingLinks: false) == .folder {
            return holzBar
        }
        return syncFolder
    }

    // MARK: Coordination

    /// Runs `body` inside a coordinated read of `url`, or gives up after `timeout` seconds.
    ///
    /// - Returns: The result of `body`, or `nil` when the coordination was not granted in time.
    static func coordinatedRead<Value>(at url: URL, timeout: TimeInterval, _ body: () -> Value) -> Value? {
        let cancellation = Cancellation(timeout: timeout)
        var result: Value?
        var coordinationError: NSError?
        cancellation.coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { _ in
            result = body()
        }
        cancellation.finish()
        return coordinationError == nil ? result : nil
    }

    /// Runs `body` inside a coordinated write that replaces `url`, or gives up after `timeout` seconds.
    ///
    /// - Parameter presenter: This Mac's presenter, so it is not told about its own write; its folder watcher
    ///   is, and finds the file its own.
    /// - Returns: The result of `body`, or `nil` when the coordination was not granted in time.
    static func coordinatedWrite<Value>(at url: URL, presenter: (any NSFilePresenter)?, timeout: TimeInterval, _ body: () -> Value) -> Value? {
        let cancellation = Cancellation(timeout: timeout, presenter: presenter)
        var result: Value?
        var coordinationError: NSError?
        cancellation.coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { _ in
            result = body()
        }
        cancellation.finish()
        return coordinationError == nil ? result : nil
    }

    /// A coordinator that is cancelled when it has not been granted access after a time limit.
    /// `NSFileCoordinator.cancel()` may be called from any thread.
    private nonisolated final class Cancellation: @unchecked Sendable {
        let coordinator: NSFileCoordinator
        private let isFinished = OSAllocatedUnfairLock(initialState: false)

        init(timeout: TimeInterval, presenter: (any NSFilePresenter)? = nil) {
            coordinator = NSFileCoordinator(filePresenter: presenter)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) { [self] in
                if !isFinished.withLock({ $0 }) {
                    coordinator.cancel()
                }
            }
        }

        func finish() {
            isFinished.withLock { $0 = true }
        }
    }

    // MARK: Downloads

    /// Asks the provider to download the files, without waiting for them. A file that is not in iCloud Drive
    /// fails quietly: the folder's own app brings the files of the other providers.
    static func startDownloads(of urls: [URL]) {
        for url in urls {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }
}

// MARK: - SyncFolderWatcher

/// Tells the host when a file in the watched folder is added, replaced or removed, as sync apps other
/// than iCloud Drive do without file coordination.
///
/// A file system event source on the folder: an event, never a poll. Its state never changes after it is
/// created.
nonisolated final class SyncFolderWatcher: @unchecked Sendable {
    /// The folder that is watched.
    let folderURL: URL

    private let source: any DispatchSourceFileSystemObject

    init?(folderURL: URL, onChange: @escaping @Sendable () -> Void) {
        let descriptor = open(SyncFolderLayout.path(of: folderURL), O_EVTONLY)
        guard descriptor >= 0 else {
            return nil
        }
        self.folderURL = folderURL
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

// MARK: - SyncFolderPresenter

/// Tells the host when a new version of a file in the folder arrives in iCloud Drive.
///
/// File presenters are called on their own queue; the presenter only hands the change on. Its state never
/// changes after it is created. It must be `nonisolated`: with the project's main actor default isolation,
/// its `NSFilePresenter` members would be main actor isolated, and the file coordinator, which reads
/// `presentedItemURL` and calls the change methods on the presenter's queue, would trip Swift's isolation
/// check and crash holzBar as soon as sync was turned on.
nonisolated final class SyncFolderPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
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
        presentedItemURL = folderURL
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
