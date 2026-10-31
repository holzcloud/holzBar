//
//  DownloadTracker.swift
//  holzBar
//

import Foundation

/// The life of the downloads in a folder, as a pure state machine over its listings.
///
/// Each listing of the folder's entry names goes through ``update(names:now:)``. A download is
/// tracked by its final name (see ``DownloadScan``) and is running while its mark is in the
/// listing:
///
/// - A mark that appears starts a running item at `now`; while it stays, the item stays and
///   `startedAt` does not change.
/// - A mark that is gone while the final name is listed finishes the item at `now`.
/// - A mark that is gone without the final name, or the mark of a download whose name the
///   browser did not know, drops the item: a cancelled download shows nothing.
/// - A finished item whose mark appears again is replaced by a new running item.
/// - A finished item older than ``finishedRetention`` is dropped (the board hides it sooner).
/// - At most ``maximumRunning`` items run: the newest are kept. One that was left out stays
///   out while its mark is listed, so a crowded folder does not make the others flicker.
///
/// The tracker holds file names, so it lives in memory only and its owner clears it when it
/// stops. It reads no clock.
nonisolated struct DownloadTracker: Equatable, Sendable {
    /// The most downloads tracked as running.
    static let maximumRunning = 20

    /// How long a finished download is kept, in seconds.
    static let finishedRetention: TimeInterval = 60

    /// One download.
    nonisolated struct Item: Equatable, Sendable {
        /// The final name, or `nil` when the browser does not know it yet.
        let name: String?
        let startedAt: Date
        /// When the download finished, or `nil` while it runs.
        var finishedAt: Date?
        /// What identifies the item among the others: the final name, or the placeholder
        /// name of an unnamed download.
        let key: String

        /// A short identifier that does not contain the name, for places that must not hold
        /// it (an activity's id, an announcement): the FNV-1a hash of the key in hex.
        var id: String {
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100_0000_01b3
            }
            return String(hash, radix: 16)
        }
    }

    private var items = [String: Item]()

    /// The final names of marks that were left out because of ``maximumRunning`` and are still
    /// listed.
    private var leftOut = Set<String>()

    /// The downloads in progress, the newest first.
    var running: [Item] {
        items.values
            .filter { $0.finishedAt == nil }
            .sorted(by: Self.isNewer)
    }

    /// The finished downloads, the latest to finish first.
    var finished: [Item] {
        items.values
            .filter { $0.finishedAt != nil }
            .sorted { lhs, rhs in
                if lhs.finishedAt != rhs.finishedAt {
                    return (lhs.finishedAt ?? .distantPast) > (rhs.finishedAt ?? .distantPast)
                }
                return lhs.key < rhs.key
            }
    }

    /// Whether nothing is tracked.
    var isEmpty: Bool {
        items.isEmpty
    }

    /// Takes the entry names of a folder listing at a moment.
    mutating func update(names: [String], now: Date) {
        let partials = DownloadScan.partials(in: names)
        let present = Set(partials.map(\.finalName))
        let listed = Set(names)

        // Running items whose mark went: finished when the final name is there, else dropped.
        for (key, item) in items where item.finishedAt == nil && !present.contains(key) {
            if item.name != nil, listed.contains(key) {
                items[key]?.finishedAt = now
            } else {
                items[key] = nil
            }
        }

        // Finished items are kept for a while only.
        for (key, item) in items {
            if let finishedAt = item.finishedAt, now.timeIntervalSince(finishedAt) > Self.finishedRetention {
                items[key] = nil
            }
        }

        // Marks that appeared, or appeared again after the download finished.
        leftOut.formIntersection(present)
        for partial in partials {
            let key = partial.finalName
            if let existing = items[key], existing.finishedAt == nil {
                continue
            }
            if leftOut.contains(key) {
                continue
            }
            items[key] = Item(
                name: partial.isUnnamed ? nil : key,
                startedAt: now,
                finishedAt: nil,
                key: key
            )
        }

        // Only the newest downloads run.
        let all = running
        if all.count > Self.maximumRunning {
            for item in all.dropFirst(Self.maximumRunning) {
                items[item.key] = nil
                leftOut.insert(item.key)
            }
        }
    }

    /// Forgets everything.
    mutating func removeAll() {
        items.removeAll()
        leftOut.removeAll()
    }

    private static func isNewer(_ lhs: Item, _ rhs: Item) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.key < rhs.key
    }
}
