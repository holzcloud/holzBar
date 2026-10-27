//
//  UsageStore.swift
//  holzBar
//

import AppKit
import Observation
import OSLog

/// Counts how often the user opens each menu bar item, so holzBar can suggest hiding what is
/// never used.
///
/// The feature is off until the user turns it on. While it is off nothing is counted, no file
/// exists and the mouse-down monitor is not kept running for it. What is kept is a count per
/// item and calendar day for the last 30 days (``UsageCounters``), in one file on this Mac with
/// mode 0600, excluded from backups, and in no export, no snapshot, no diagnostics and no log.
/// Turning the feature off, or "Forget Everything", deletes the file.
@MainActor
@Observable
final class UsageStore {
    /// Whether the counters run. Setting it on starts them today; setting it off deletes them.
    var isEnabled = false {
        didSet {
            guard !isLoading, oldValue != isEnabled else {
                return
            }
            Defaults.set(isEnabled, forKey: .usageSuggestionsEnabled)
            if isEnabled {
                counters = UsageCounters(startDay: Self.today)
                save()
            } else {
                forgetEverything()
            }
            appState?.hidEventManager.usageSettingChanged()
        }
    }

    /// What is held now.
    private(set) var counters = UsageCounters()

    @ObservationIgnored private let logger = Logger(category: "UsageStore")
    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var terminationTask: Task<Void, Never>?

    private static var today: Int {
        UsageCounters.dayNumber(for: .now)
    }

    private static let fileURL = CounterFile.url(named: "Usage.json")

    func performSetup(with appState: AppState) {
        self.appState = appState
        isLoading = true
        isEnabled = Defaults.bool(forKey: .usageSuggestionsEnabled)
        isLoading = false
        if isEnabled {
            load()
            terminationTask = Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSApplication.willTerminateNotification) {
                    self?.saveNow()
                }
            }
        }
    }

    // MARK: Counting

    /// Counts one open of an item. Nothing happens while the feature is off.
    func recordOpen(ofItemWithKey key: String) {
        guard isEnabled else {
            return
        }
        counters.record(key: key, day: Self.today)
        scheduleSave()
    }

    /// Counts a click in the menu bar at a point in Core Graphics coordinates, when it is on an
    /// item of the visible section. A click that hits nothing, or more than one item, counts
    /// nothing.
    func recordMenuBarClick(atCoreGraphicsPoint point: CGPoint) {
        guard isEnabled, let appState else {
            return
        }
        let itemManager = appState.itemManager
        let hits = itemManager.itemCache[.visible].filter { !$0.isControlItem && $0.bounds.contains(point) }
        guard hits.count == 1, let item = hits.first else {
            return
        }
        recordOpen(ofItemWithKey: itemManager.identityKey(for: item))
    }

    // MARK: Suggestions

    /// The visible items that were not opened lately. Empty while the feature is off or has not
    /// run long enough.
    var suggestions: [MenuBarItem] {
        guard isEnabled, let appState else {
            return []
        }
        let itemManager = appState.itemManager
        let controlled = appState.automation.controlledItemKeys
        var byKey = [String: MenuBarItem]()
        var excluded = controlled
        var keys = [String]()
        for item in itemManager.itemCache[.visible] where !item.isControlItem {
            let key = itemManager.identityKey(for: item)
            byKey[key] = item
            keys.append(key)
            let item = ClassifiableItem(
                key: key,
                namespace: item.tag.namespace.description,
                title: item.tag.title,
                applicationCategory: nil,
                section: 0,
                isOwnItem: item.tag.namespace == .holzBar
            )
            switch ItemClassifier.classify(item) {
            case .essential, .information, .communication:
                excluded.insert(key)
            case .setAndForget, .unknown:
                break
            }
            if item.isOwnItem {
                excluded.insert(key)
            }
        }
        return UsageSuggester
            .suggestions(from: counters, visibleKeys: keys, excluded: excluded, today: Self.today)
            .compactMap { byKey[$0] }
    }

    /// Moves a suggested item to the hidden section, after a snapshot of the layout.
    func hide(_ item: MenuBarItem) {
        guard let appState else {
            return
        }
        let key = appState.itemManager.identityKey(for: item)
        appState.snapshots.willTidyUp()
        let layout = appState.profiles.currentLayout()
        var itemSections = layout.itemSections
        var applicationSections = layout.applicationSections
        itemSections[key] = 1
        if let layoutKey = OwnBundle.layoutKey(forItemKey: key, bundleIdentifier: Constants.bundleIdentifier) {
            applicationSections[layoutKey] = 1
        }
        appState.profiles.applyLayout(of: LayoutProfile(
            name: "",
            itemSections: itemSections,
            applicationSections: applicationSections,
            knownApplications: layout.knownApplications
        ))
    }

    /// Keeps an item where it is and never suggests it again.
    func keep(_ item: MenuBarItem) {
        guard let appState else {
            return
        }
        counters.dismissed.insert(appState.itemManager.identityKey(for: item))
        scheduleSave()
    }

    // MARK: What is held

    /// The rows of the list of what is stored: the item key's readable name and its daily counts.
    func storedRows() -> [(name: String, days: [Int])] {
        counters.keys.map { key in
            let name = appState?.itemManager.item(withIdentityKey: key)?.displayName ?? key.split(separator: ":").last.map(String.init) ?? key
            return (name, counters.dailyCounts(of: key, today: Self.today))
        }
    }

    /// Deletes every count, the dismissed suggestions and the file.
    func forgetEverything() {
        saveTask?.cancel()
        saveTask = nil
        counters.forgetEverything()
        if isEnabled {
            counters = UsageCounters(startDay: Self.today)
        }
        CounterFile.delete(at: Self.fileURL)
        if isEnabled {
            save()
        }
    }

    // MARK: File

    /// Writes at most once a minute.
    private func scheduleSave() {
        guard saveTask == nil else {
            return
        }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else {
                return
            }
            self?.saveTask = nil
            self?.save()
        }
    }

    private func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func save() {
        guard isEnabled else {
            return
        }
        counters.prune(today: Self.today)
        do {
            try CounterFile.write(counters, to: Self.fileURL)
        } catch {
            logger.error("Could not write the usage counters: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func load() {
        counters = CounterFile.read(at: Self.fileURL, today: Self.today) ?? UsageCounters(startDay: Self.today)
    }
}
