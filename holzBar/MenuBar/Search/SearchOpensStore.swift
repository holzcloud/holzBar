//
//  SearchOpensStore.swift
//  holzBar
//

import Foundation
import Observation
import OSLog

/// Remembers which items the user opens from the search, so the ones used most and most lately
/// come first (`SearchFrecency`).
///
/// What is kept is the same as for the usage suggestions (`UsageCounters`): a count per item and
/// calendar day for the last 30 days, in one small file on this Mac with mode 0600, excluded from
/// backups, and in no export, no snapshot, no diagnostics and no log. Only an open from the search
/// is counted, never a click in the menu bar. Nothing runs in the background: the file is read
/// when the search opens or the setting is shown, and written when an item is opened. "Forget"
/// deletes the file.
@MainActor
@Observable
final class SearchOpensStore {
    /// What is held now.
    private(set) var counters = UsageCounters()

    @ObservationIgnored private let logger = Logger(category: "SearchOpensStore")
    @ObservationIgnored private var isLoaded = false

    private static var today: Int {
        UsageCounters.dayNumber(for: .now)
    }

    private static let fileURL = CounterFile.url(named: "SearchOpens.json")

    /// Whether nothing is held.
    var isEmpty: Bool {
        counters.summary.items == 0
    }

    /// Reads the file, once.
    func loadIfNeeded() {
        guard !isLoaded else {
            return
        }
        isLoaded = true
        counters = CounterFile.read(at: Self.fileURL, today: Self.today) ?? UsageCounters()
    }

    /// Counts one open of an item from the search.
    func recordOpen(ofItemWithKey key: String) {
        loadIfNeeded()
        counters.record(key: key, day: Self.today)
        counters.prune(today: Self.today)
        do {
            try CounterFile.write(counters, to: Self.fileURL)
        } catch {
            logger.error("Could not write what the search remembers: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// The frecency of an item, 0 when it was never opened from the search.
    func frecency(ofItemWithKey key: String) -> Double {
        counters.frecency(of: key, today: Self.today)
    }

    /// Deletes everything and the file.
    func forget() {
        counters = UsageCounters()
        isLoaded = true
        CounterFile.delete(at: Self.fileURL)
    }
}
