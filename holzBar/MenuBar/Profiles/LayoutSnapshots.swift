//
//  LayoutSnapshots.swift
//  holzBar
//

import Foundation
import Observation
import OSLog

/// Keeps the history of the arrangement, so a layout never gets lost.
///
/// A snapshot is taken when the bar has settled after the Mac woke or the displays changed,
/// at the first check of a day, before a profile rearranges the items, before a restore and
/// when the user asks. An unchanged arrangement never makes a new file
/// (``SnapshotPolicy``), and old ones are pruned (``SnapshotRetention``). The files are in
/// `~/Library/Application Support/holzBar/Snapshots`, readable only by the user, and are not
/// synced or exported: item identities belong to the apps of one Mac.
///
/// Logs hold counts and reasons only, never item or profile names.
@MainActor
@Observable
final class LayoutSnapshots {
    /// The snapshots, newest first.
    private(set) var snapshots = [LayoutSnapshot]()

    /// Whether the history is kept. On by default.
    var isEnabled = true {
        didSet {
            guard !isLoading else {
                return
            }
            Defaults.set(!isEnabled, forKey: .layoutSnapshotsDisabled)
        }
    }

    /// When holzBar last rearranged the items itself, by a profile or a restore.
    @ObservationIgnored private(set) var lastRearrangement: Date?

    @ObservationIgnored private let logger = Logger(category: "LayoutSnapshots")
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var isLoading = false

    private static let directory: URL = {
        let base = URL.applicationSupportDirectory
        return base.appending(path: "holzBar", directoryHint: .isDirectory)
            .appending(path: "Snapshots", directoryHint: .isDirectory)
    }()

    func performSetup(with appState: AppState) {
        self.appState = appState
        isLoading = true
        isEnabled = !Defaults.bool(forKey: .layoutSnapshotsDisabled)
        isLoading = false
        load()
        appState.systemActivityMonitor.onSettled { [weak self] in
            self?.take(.settled)
        }
        // The items are read some seconds after launch; the first snapshot of a day waits for them.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            self?.takeDailyIfDue()
        }
    }

    // MARK: Taking

    /// The arrangement now, as a snapshot.
    func currentSnapshot(reason: SnapshotReason) -> LayoutSnapshot {
        let layout = appState?.profiles.currentLayout()
        // Whole milliseconds, so the date is the same after it was stored and read again.
        let milliseconds = (Date.now.timeIntervalSince1970 * 1000).rounded(.down)
        return LayoutSnapshot(
            date: Date(timeIntervalSince1970: milliseconds / 1000),
            reason: reason,
            itemSections: layout?.itemSections ?? [:],
            applicationSections: layout?.applicationSections ?? [:],
            knownApplications: layout?.knownApplications
        )
    }

    /// Takes a snapshot of the arrangement now, unless it is turned off or nothing changed
    /// since the newest one.
    func take(_ reason: SnapshotReason) {
        guard isEnabled else {
            return
        }
        let candidate = currentSnapshot(reason: reason)
        guard SnapshotPolicy.shouldKeep(candidate, latest: snapshots.first) else {
            return
        }
        write(candidate)
        snapshots.insert(candidate, at: 0)
        prune()
        logger.notice("Took a snapshot of \(candidate.count, privacy: .public) items (\(reason.rawValue, privacy: .public))")
    }

    private func takeDailyIfDue() {
        let calendar = Calendar.current
        if let latest = snapshots.first, calendar.isDateInToday(latest.date) {
            return
        }
        take(.daily)
    }

    /// Called before a profile rearranges the items: keeps the arrangement as it is now.
    func willApplyProfile() {
        take(.beforeProfile)
        lastRearrangement = .now
    }

    /// Called before the clean-up assistant hides items: keeps the arrangement as it is now.
    func willTidyUp() {
        take(.beforeAssistant)
        lastRearrangement = .now
    }

    /// Called before rules move items: keeps the arrangement as it is now.
    func willApplyRules() {
        take(.beforeRule)
        lastRearrangement = .now
    }

    // MARK: Restoring

    /// What restoring the snapshot would change now.
    func diff(to snapshot: LayoutSnapshot) -> SnapshotDiff {
        SnapshotDiff(from: currentSnapshot(reason: .manual), to: snapshot)
    }

    /// Brings the arrangement of the snapshot back. The arrangement now is kept first, so
    /// the restore can be undone.
    func restore(_ snapshot: LayoutSnapshot) {
        guard let appState else {
            return
        }
        take(.beforeRestore)
        lastRearrangement = .now
        logger.notice("Restoring a snapshot of \(snapshot.count, privacy: .public) items")
        appState.profiles.applyLayout(of: LayoutProfile(
            name: "",
            itemSections: snapshot.itemSections,
            applicationSections: snapshot.applicationSections,
            knownApplications: snapshot.knownApplications
        ))
    }

    /// The newest snapshot the arrangement now looks reset against, or `nil`. Not for a
    /// while after holzBar rearranged the items itself.
    var snapshotToSuggest: LayoutSnapshot? {
        guard
            isEnabled,
            lastRearrangement.map({ Date.now.timeIntervalSince($0) > 120 }) ?? true,
            let reference = snapshots.first(where: { [.settled, .daily, .manual].contains($0.reason) })
        else {
            return nil
        }
        let current = currentSnapshot(reason: .manual)
        return LayoutLossDetector.looksReset(current: current, comparedWith: reference) ? reference : nil
    }

    // MARK: Editing

    func toggleStar(_ snapshot: LayoutSnapshot) {
        guard let index = snapshots.firstIndex(where: { $0.id == snapshot.id }) else {
            return
        }
        snapshots[index].isStarred.toggle()
        write(snapshots[index])
    }

    func delete(_ snapshot: LayoutSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        try? FileManager.default.removeItem(at: Self.url(for: snapshot))
    }

    func deleteAll() {
        for snapshot in snapshots {
            try? FileManager.default.removeItem(at: Self.url(for: snapshot))
        }
        snapshots = []
    }

    // MARK: Files

    private static func url(for snapshot: LayoutSnapshot) -> URL {
        let milliseconds = Int((snapshot.date.timeIntervalSince1970 * 1000).rounded())
        return directory.appending(path: "\(milliseconds).json", directoryHint: .notDirectory)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func write(_ snapshot: LayoutSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: Self.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let url = Self.url(for: snapshot)
            try Self.encoder.encode(snapshot).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path(percentEncoded: false))
        } catch {
            logger.error("Could not write a snapshot: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Reads the files. One that cannot be read or has a format this version does not know
    /// is skipped.
    private func load() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var loaded = [LayoutSnapshot]()
        for url in urls where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let snapshot = try? decoder.decode(LayoutSnapshot.self, from: data),
                snapshot.format == LayoutSnapshot.currentFormat
            else {
                logger.notice("Skipped a snapshot file that cannot be read")
                continue
            }
            loaded.append(snapshot)
        }
        snapshots = loaded.sorted { $0.date > $1.date }
        prune()
    }

    /// Deletes the files of the snapshots that are no longer kept.
    private func prune() {
        let kept = SnapshotRetention.kept(from: snapshots)
        guard kept.count != snapshots.count else {
            return
        }
        let keptIDs = Set(kept.map(\.id))
        for snapshot in snapshots where !keptIDs.contains(snapshot.id) {
            try? FileManager.default.removeItem(at: Self.url(for: snapshot))
        }
        snapshots = kept
    }
}
