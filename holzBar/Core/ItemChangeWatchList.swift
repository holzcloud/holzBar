//
//  ItemChangeWatchList.swift
//  holzBar
//

import Foundation

/// The bookkeeping of `ItemChangeWatcher`: which marked items it watches, which it tries
/// to observe next, and whether a registration that finished still counts.
///
/// The observers are registered off the main thread, so the list may change while a
/// registration is under way. Each registration carries the generation it started in, and
/// a result from an older one is dropped. Only items whose observer was added count as
/// watched, so an item whose element was not found or not observed is tried again
/// (``maximumRetries`` times for one list).
///
/// An item counts as changed when its window or its process changes: on macOS 27 a
/// relaunched app's item keeps its window identifier, and its observers would otherwise stay
/// on the process that quit.
nonisolated struct ItemChangeWatchList: Equatable, Sendable {
    /// The retries for one list.
    static let maximumRetries = 3

    /// Where a marked item is: its window and the process that owns it.
    struct Location: Equatable, Sendable {
        let windowID: UInt32
        let pid: pid_t
    }

    /// A registration to run: the generation it belongs to and the keys of the items to
    /// observe.
    struct Registration: Equatable, Sendable {
        let generation: Int
        let keys: Set<String>
    }

    /// The marked items in the menu bar and their locations, from the last change of the list.
    private(set) var windows = [String: Location]()

    /// The observed items and their locations.
    private(set) var watchedWindows = [String: Location]()

    /// The generation of the latest registration.
    private(set) var generation = 0

    /// The retries made for the current list.
    private(set) var retryCount = 0

    /// Takes the marked items in the menu bar now.
    ///
    /// - Parameters:
    ///   - windows: The marked items' locations, by item key.
    ///   - retrying: Whether this is a retry for an unchanged list.
    /// - Returns: Whether the observers must be removed (the list changed), and the
    ///   registration to run, if any.
    mutating func update(
        windows: [String: Location],
        retrying: Bool
    ) -> (removesObservers: Bool, registration: Registration?) {
        let changed = windows != self.windows
        if changed {
            self.windows = windows
            watchedWindows.removeAll()
            retryCount = 0
        } else if !retrying {
            // A pending retry or registration stays.
            return (false, nil)
        }
        generation += 1
        let keys = Set(windows.keys).subtracting(watchedWindows.keys)
        return (changed, keys.isEmpty ? nil : Registration(generation: generation, keys: keys))
    }

    /// Records a finished registration.
    ///
    /// - Returns: Whether it is still current; an outdated one must be discarded.
    mutating func finish(_ registration: Registration, observed keys: Set<String>) -> Bool {
        guard registration.generation == generation else {
            return false
        }
        for key in keys.intersection(registration.keys) {
            watchedWindows[key] = windows[key]
        }
        return true
    }

    /// Whether the items not observed are tried again once more; counts the retry.
    mutating func takeRetry() -> Bool {
        guard watchedWindows.count < windows.count, retryCount < Self.maximumRetries else {
            return false
        }
        retryCount += 1
        return true
    }
}
