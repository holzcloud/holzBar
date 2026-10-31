//
//  DownloadsSource.swift
//  holzBar
//

import Foundation
import OSLog

/// Reports the downloads in progress in the user's Downloads folder, for the Live activities module.
///
/// A browser leaves a mark in the folder while it downloads (see ``DownloadScan``), so the source
/// watches the folder's entries: nothing polls, no file is read and nothing but the names is
/// listed. The folder is opened for events only in ``start()``, which is when macOS asks the
/// user once for the folder; a refusal sets ``access`` to ``Access/denied`` and nothing asks
/// again by itself. Events are coalesced to one listing per 300 ms, and the listing runs off
/// the main actor. ``stop()`` closes the folder, cancels what is pending and forgets every name,
/// so a source that is off holds nothing.
///
/// File names stay in the ``DownloadTracker`` in memory: they are not stored, and the log
/// says only how many downloads there are.
@MainActor
final class DownloadsSource {
    /// Whether the user lets holzBar read the Downloads folder.
    enum Access: Sendable {
        /// Not asked yet, or not started.
        case unknown
        case granted
        /// The user refused, or macOS does not allow it.
        case denied
    }

    /// What opening the folder gave.
    private enum Opening: Sendable {
        case opened(Int32)
        case denied
        case unavailable
    }

    /// What a listing of the folder gave.
    private enum Listing: Sendable {
        case names([String])
        case denied
        case failed
    }

    /// The watch on the folder. It reports what happened to the folder, and closes the
    /// descriptor when it goes.
    private nonisolated final class Watch {
        private let source: any DispatchSourceFileSystemObject

        init(descriptor: Int32, onEvent: @escaping @MainActor @Sendable (DispatchSource.FileSystemEvent) -> Void) {
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak source] in
                let event = source?.data ?? []
                // The source reports on the main queue.
                MainActor.assumeIsolated {
                    onEvent(event)
                }
            }
            source.setCancelHandler {
                close(descriptor)
            }
            self.source = source
            source.resume()
        }

        deinit {
            source.cancel()
        }
    }

    /// How events are coalesced: at most one listing in this time.
    private static let coalescing = Duration.milliseconds(300)

    /// The downloads, as the last listing left them.
    private(set) var tracker = DownloadTracker()

    /// Whether the folder may be read.
    private(set) var access = Access.unknown

    /// Called on the main actor after the tracker or the access changed.
    var onChange: (() -> Void)?

    private var folder: URL?
    private var watch: Watch?
    private var startTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private let debouncer = Debouncer(delay: coalescing)
    private let logger = Logger(category: "DownloadsSource")

    /// Opens the Downloads folder, which is when macOS asks the user, and lists it. Does
    /// nothing while already started.
    func start() {
        guard watch == nil, startTask == nil,
              let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        else {
            return
        }
        self.folder = folder
        // The open call waits for the user's answer to the question, so it must not block the
        // main actor: the Settings window would stand still until it is answered.
        startTask = Task { [weak self] in
            let opening = await Self.openFolder(folder)
            guard !Task.isCancelled, let self else {
                if case .opened(let descriptor) = opening {
                    close(descriptor)
                }
                return
            }
            startTask = nil
            didOpen(opening)
        }
    }

    /// Closes the folder, cancels what is pending and forgets every download.
    func stop() {
        startTask?.cancel()
        startTask = nil
        scanTask?.cancel()
        scanTask = nil
        debouncer.cancel()
        watch = nil
        folder = nil
        tracker.removeAll()
        access = .unknown
        onChange = nil
    }

    // MARK: Watching

    private func didOpen(_ opening: Opening) {
        switch opening {
        case .opened(let descriptor):
            access = .granted
            watch = Watch(descriptor: descriptor) { [weak self] event in
                self?.folderDidChange(event)
            }
            scan()
        case .denied:
            logger.debug("The Downloads folder is not allowed; downloads are not followed")
            access = .denied
            onChange?()
        case .unavailable:
            // No folder to watch (it may be gone for now): not a refusal.
            access = .granted
            onChange?()
        }
    }

    private func folderDidChange(_ event: DispatchSource.FileSystemEvent) {
        if !event.isDisjoint(with: [.rename, .delete]) {
            // The folder itself moved or went: the descriptor follows the old one. Open it again
            // once; when that fails there is nothing to watch.
            watch = nil
            start()
            return
        }
        debouncer.throttle(latest: true) { [weak self] in
            self?.scan()
        }
    }

    // MARK: Listing

    private func scan() {
        guard let folder else {
            return
        }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let listing = await Self.entryNames(in: folder)
            guard !Task.isCancelled, let self else {
                return
            }
            apply(listing)
        }
    }

    private func apply(_ listing: Listing) {
        switch listing {
        case .names(let names):
            var changed = false
            if access != .granted {
                access = .granted
                changed = true
            }
            var updated = tracker
            updated.update(names: names, now: .now)
            if updated != tracker {
                tracker = updated
                changed = true
                logger.debug(
                    "Downloads changed: \(updated.running.count, privacy: .public) running, \(updated.finished.count, privacy: .public) finished"
                )
            }
            if changed {
                onChange?()
            }
        case .denied:
            if access != .denied {
                access = .denied
                tracker.removeAll()
                onChange?()
            }
        case .failed:
            break
        }
    }

    // MARK: Off the main actor

    /// Opens the folder to receive events only, which does not read it. `@concurrent` keeps the
    /// main actor free while macOS asks.
    @concurrent
    private nonisolated static func openFolder(_ folder: URL) async -> Opening {
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        if descriptor >= 0 {
            return .opened(descriptor)
        }
        return errno == EPERM || errno == EACCES ? .denied : .unavailable
    }

    /// The names of the folder's entries, its top level only. `@concurrent` runs the listing
    /// off the main actor, however big the folder is.
    @concurrent
    private nonisolated static func entryNames(in folder: URL) async -> Listing {
        do {
            return .names(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)))
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            return .denied
        } catch {
            let error = error as NSError
            let underlying = (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            let isPOSIXRefusal = underlying == Int(EPERM) || underlying == Int(EACCES)
            return isPOSIXRefusal ? .denied : .failed
        }
    }
}
