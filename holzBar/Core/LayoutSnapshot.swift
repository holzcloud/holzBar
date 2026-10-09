//
//  LayoutSnapshot.swift
//  holzBar
//

import Foundation

/// Why a snapshot of the arrangement was taken.
nonisolated enum SnapshotReason: String, Codable, Sendable {
    /// The arrangement settled after the screen woke or the displays changed.
    case settled
    /// The first check of a day, when the arrangement changed.
    case daily
    /// Before a profile rearranged many items.
    case beforeProfile
    /// Before a snapshot was restored, so the restore can be undone.
    case beforeRestore
    /// The user asked for it.
    case manual
}

/// The arrangement of the menu bar items at one moment, kept so it can be brought back.
///
/// It holds only what is needed to rebuild the sections: the section of each item (macOS 26
/// and earlier) or application (macOS 27). No images, hotkeys, other settings or usage data.
nonisolated struct LayoutSnapshot: Codable, Equatable, Identifiable, Sendable {
    /// The file format. A snapshot with a format this version does not know is skipped.
    static let currentFormat = 1

    var format = LayoutSnapshot.currentFormat
    var date: Date
    var reason: SnapshotReason
    /// Whether the user starred it, which keeps it from being pruned.
    var isStarred = false
    /// The section of each item by identity key (0 visible, 1 hidden, 2 always hidden).
    var itemSections: [String: Int]
    /// The section of each application by bundle identifier (macOS 27).
    var applicationSections: [String: Int]
    /// The applications known on macOS 27, so a known one missing from `applicationSections`
    /// is visible.
    var knownApplications: [String]?

    var id: Date { date }

    /// The number of items and applications the snapshot places.
    var count: Int {
        itemSections.count + applicationSections.count
    }

    /// Whether the snapshot places nothing.
    var isEmpty: Bool {
        itemSections.isEmpty && applicationSections.isEmpty
    }

    /// Whether another snapshot arranges everything in the same way.
    func hasSameArrangement(as other: LayoutSnapshot) -> Bool {
        itemSections == other.itemSections
            && applicationSections == other.applicationSections
            && Set(knownApplications ?? []) == Set(other.knownApplications ?? [])
    }
}

/// Decides whether a new snapshot is worth keeping.
nonisolated enum SnapshotPolicy {
    /// A snapshot is not kept when it arranges everything as the newest one does: an
    /// unchanged layout never makes a new file.
    static func shouldKeep(_ candidate: LayoutSnapshot, latest: LayoutSnapshot?) -> Bool {
        guard let latest else {
            return !candidate.isEmpty
        }
        return !candidate.hasSameArrangement(as: latest)
    }
}

/// Decides which snapshots stay.
nonisolated enum SnapshotRetention {
    /// The newest snapshots always kept.
    static let newestCount = 10
    /// How many earlier days keep their newest snapshot.
    static let dayCount = 20
    /// The most snapshots kept, not counting starred ones.
    static let maximumCount = 30

    /// The snapshots to keep, newest first: the newest ten, then the newest of each of the
    /// 20 days before them, at most 30, plus every starred one.
    static func kept(from snapshots: [LayoutSnapshot], calendar: Calendar = .current) -> [LayoutSnapshot] {
        let sorted = snapshots.sorted { $0.date > $1.date }
        var keptIDs = Set<Date>()
        var result: [LayoutSnapshot] = []

        func keep(_ snapshot: LayoutSnapshot) {
            if keptIDs.insert(snapshot.id).inserted {
                result.append(snapshot)
            }
        }

        var unstarredCount = 0
        for snapshot in sorted.prefix(newestCount) {
            keep(snapshot)
            if !snapshot.isStarred {
                unstarredCount += 1
            }
        }
        // The days of the newest snapshots are covered; each earlier day keeps its newest one.
        var coveredDays = Set(sorted.prefix(newestCount).map { calendar.startOfDay(for: $0.date) })
        var earlierDays = 0
        for snapshot in sorted.dropFirst(newestCount) where !snapshot.isStarred {
            let day = calendar.startOfDay(for: snapshot.date)
            guard !coveredDays.contains(day), earlierDays < dayCount, unstarredCount < maximumCount else {
                continue
            }
            coveredDays.insert(day)
            earlierDays += 1
            keep(snapshot)
            unstarredCount += 1
        }
        for snapshot in sorted where snapshot.isStarred {
            keep(snapshot)
        }
        return result.sorted { $0.date > $1.date }
    }
}

/// What restoring a snapshot would change.
nonisolated struct SnapshotDiff: Equatable, Sendable {
    /// Items or applications that move to another section, by target section.
    private(set) var toVisible = 0
    private(set) var toHidden = 0
    private(set) var toAlwaysHidden = 0
    /// Items or applications the snapshot places that are not in the arrangement now. They
    /// are placed when they appear.
    private(set) var notPresent = 0

    /// The number of items and applications that move.
    var moves: Int {
        toVisible + toHidden + toAlwaysHidden
    }

    /// What it takes to go from `current` to `target`.
    init(from current: LayoutSnapshot, to target: LayoutSnapshot) {
        func count(_ now: [String: Int], _ wanted: [String: Int]) {
            for (key, section) in wanted {
                guard let existing = now[key] else {
                    notPresent += 1
                    continue
                }
                guard existing != section else {
                    continue
                }
                switch section {
                case 0: toVisible += 1
                case 1: toHidden += 1
                default: toAlwaysHidden += 1
                }
            }
        }
        count(current.itemSections, target.itemSections)
        count(current.applicationSections, target.applicationSections)
    }
}

/// Tells when the arrangement looks reset, for example after an update or a crash.
nonisolated enum LayoutLossDetector {
    /// How many items must differ, at least.
    static let minimumChanges = 5

    /// Whether at least half of the items the snapshot knows are somewhere else now, and at
    /// least ``minimumChanges`` of them.
    static func looksReset(current: LayoutSnapshot, comparedWith snapshot: LayoutSnapshot) -> Bool {
        let known = snapshot.count
        guard known >= minimumChanges else {
            return false
        }
        let diff = SnapshotDiff(from: current, to: snapshot)
        return diff.moves >= minimumChanges && diff.moves * 2 >= known
    }
}
