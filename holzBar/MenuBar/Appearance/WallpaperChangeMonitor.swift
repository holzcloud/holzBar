//
//  WallpaperChangeMonitor.swift
//  holzBar
//

import Foundation
import OSLog

/// Reports changes of the desktop picture as events.
///
/// macOS posts no public notification when the wallpaper changes, so this watches the file
/// the system rewrites when a wallpaper is set: `com.apple.wallpaper`'s store index. It
/// replaced a 30 s timer for the wallpaper beside a menu bar shape.
///
/// Adapted from Thaw's `WallpaperChangeMonitor` (GPL-3.0, see NOTICE).
@MainActor
final class WallpaperChangeMonitor {
    /// The wallpaper store's index.
    static let indexURL = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")

    /// The watch on the file. The system replaces the file rather than writing into it, so
    /// the watch is opened anew after every event.
    private nonisolated final class Watch {
        private let source: any DispatchSourceFileSystemObject

        /// Starts watching the file, or returns `nil` when it cannot be opened (a fresh
        /// account has no index until a wallpaper is set).
        init?(url: URL, onEvent: @escaping @MainActor @Sendable () -> Void) {
            let descriptor = open(url.path, O_EVTONLY)
            guard descriptor >= 0 else {
                return nil
            }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .extend],
                queue: .main
            )
            source.setEventHandler {
                // The source reports on the main queue.
                MainActor.assumeIsolated {
                    onEvent()
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

    /// Called on the main actor once a burst of writes has passed.
    var onChange: (() -> Void)?

    private let url: URL
    private var watch: Watch?
    private var debounceTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private let logger = Logger(category: "WallpaperChangeMonitor")

    /// How long a burst of writes is coalesced: setting a wallpaper rewrites the index
    /// several times.
    private static let debounce = Duration.milliseconds(500)

    /// How long to wait before opening the file again when it was not there yet.
    private static let retryDelay = Duration.milliseconds(500)

    init(url: URL = WallpaperChangeMonitor.indexURL) {
        self.url = url
    }

    /// Starts watching. Does nothing while already watching.
    func start() {
        guard watch == nil else {
            return
        }
        watch = Watch(url: url) { [weak self] in
            self?.fileDidChange()
        }
        if watch == nil {
            logger.debug("The wallpaper index cannot be opened; wallpaper changes are noticed on space and screen changes")
        }
    }

    /// Stops watching.
    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        retryTask?.cancel()
        retryTask = nil
        watch = nil
    }

    /// Opens the file anew (it may have been replaced) and reports the change once the
    /// writes stop.
    private func fileDidChange() {
        watch = nil
        start()
        if watch == nil {
            // The new file may not be linked yet: one more try a moment later.
            retryTask?.cancel()
            retryTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: Self.retryDelay)
                } catch {
                    return
                }
                self?.start()
            }
        }
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounce)
            } catch {
                return
            }
            self?.onChange?()
        }
    }
}
