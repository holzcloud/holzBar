//
//  LayoutEditor.swift
//  holzBar
//

import CoreGraphics
import Observation
import OSLog

/// The drawing behind the Menu Bar Layout pane.
///
/// With "Apply changes immediately" off (the default), a drop or a key press in the pane changes
/// only the drawing, a ``LayoutDraft``. The bar stays as it is until the user chooses Apply,
/// which lays it out in one pass, or Discard. The rows of the pane show the draft while one
/// exists and the item cache otherwise. The draft follows the bar while the pane is open
/// (`LayoutDraft.rebase(onto:newItems:)`).
///
/// The Shelf, the menu bar drag and everything else outside the pane move items at once, as
/// before; they change the cache, and the draft follows.
@MainActor
@Observable
final class LayoutEditor {
    /// What an Apply did.
    struct Outcome: Equatable {
        /// Changes laid out: items in another section, items in another place, the tile.
        var applied = 0
        /// Items a rule decides about, which Apply leaves to their rules.
        var leftToRules = 0
        /// Moves that macOS or the item refused.
        var failed = 0
    }

    /// The drawing, or `nil` while the rows show the bar.
    private(set) var draft: LayoutDraft?

    /// Whether an Apply is under way.
    private(set) var isApplying = false

    /// The result of the last Apply, until the next change.
    private(set) var outcome: Outcome?

    /// Changes whenever the rows have to be read again.
    private(set) var revision = 0

    @ObservationIgnored private weak var appState: AppState?
    @ObservationIgnored private var itemsByKey = [String: MenuBarItem]()
    @ObservationIgnored private var keysByWindow = [CGWindowID: String]()
    @ObservationIgnored private var observers = [ObservationLoop]()
    @ObservationIgnored private let logger = Logger(category: "LayoutEditor")

    /// Starts following the item cache.
    func performSetup(with appState: AppState) {
        self.appState = appState
        let itemManager = appState.itemManager
        observers = [
            ObservationLoop.observe { itemManager.itemCache } onChange: { [weak self] _ in
                self?.cacheDidChange()
            },
        ]
    }

    // MARK: Reading

    /// Whether changes in the pane wait for Apply.
    var recordsChanges: Bool {
        appState.map { !$0.settings.general.appliesLayoutChangesImmediately } ?? false
    }

    /// Whether the drawing differs from the bar.
    var isChanged: Bool {
        draft?.isChanged ?? false
    }

    /// How many changes the drawing holds.
    var changeCount: Int {
        draft?.changeCount ?? 0
    }

    /// The items a row shows: the drawing's while there is one, the bar's otherwise.
    func items(in section: MenuBarSection.Name) -> [MenuBarItem] {
        guard let draft else {
            return appState?.itemManager.itemCache[section] ?? []
        }
        return draft.entries(in: LayoutDraft.Section(section)).compactMap { itemsByKey[$0.key] }
    }

    /// The section the tile "New items" is in.
    var newItemsSection: MenuBarSection.Name {
        (draft?.newItems ?? landing).name
    }

    /// The sections the pane shows, which new items can land in.
    var availableSections: [MenuBarSection.Name] {
        let hasAlwaysHidden = appState?.settings.advanced.enableAlwaysHiddenSection ?? false
        return MenuBarSection.Name.allCases.filter { $0 != .alwaysHidden || hasAlwaysHidden }
    }

    // MARK: Recording

    /// Moves an item to the end of a section in the drawing.
    ///
    /// - Returns: `false` if the drawing cannot take the move (the item is not on the bar).
    @discardableResult
    func recordSection(of item: MenuBarItem, to section: MenuBarSection.Name) -> Bool {
        guard prepareDraft(), let key = key(of: item) else {
            return false
        }
        draft?.moveToEnd(key, of: LayoutDraft.Section(section))
        didChange()
        return true
    }

    /// Whether the drawing takes a move of the item: not a pinned item and not one a rule controls.
    private func canRecord(_ key: String) -> Bool {
        guard let entry = draft?.entry(for: key), !entry.isLocked else {
            return false
        }
        guard let appState else {
            return true
        }
        let manager = appState.itemManager
        return !appState.automation.controlledItemKeys.map(manager.storedIdentityKey).contains(key)
    }

    /// Puts an item in a section of the drawing, before another item or at the end.
    @discardableResult
    func recordMove(_ item: MenuBarItem, to section: MenuBarSection.Name, before next: MenuBarItem?) -> Bool {
        guard prepareDraft(), let key = key(of: item), canRecord(key) else {
            return false
        }
        draft?.move(key, to: LayoutDraft.Section(section), before: next.flatMap { self.key(of: $0) })
        didChange()
        return true
    }

    /// Puts an item next to another one, in the other item's section.
    @discardableResult
    func recordMove(_ item: MenuBarItem, relativeTo neighbour: MenuBarItem, isRight: Bool) -> Bool {
        guard prepareDraft(), let key = key(of: item), canRecord(key), let neighbourKey = self.key(of: neighbour) else {
            return false
        }
        if isRight {
            draft?.move(key, rightOf: neighbourKey)
        } else if let section = draft?.section(of: neighbourKey) {
            draft?.move(key, to: section, before: neighbourKey)
        }
        didChange()
        return true
    }

    /// Sets the section new items land in: in the drawing, or at once with "Apply changes
    /// immediately".
    func setNewItemsSection(_ section: MenuBarSection.Name) {
        guard let appState else {
            return
        }
        guard recordsChanges else {
            appState.settings.advanced.newItemsPlacement = Self.placement(for: LayoutDraft.Section(section))
            return
        }
        guard prepareDraft() else {
            return
        }
        draft?.setNewItems(LayoutDraft.Section(section))
        didChange()
    }

    /// Makes the rows show the bar again.
    func discard() {
        guard !isApplying else {
            return
        }
        draft = nil
        outcome = nil
        revision += 1
    }

    // MARK: Apply

    /// Lays the bar out as the drawing says, in one pass.
    func apply() {
        guard let appState, let pending = draft, !isApplying, pending.isChanged else {
            return
        }
        isApplying = true
        outcome = nil
        Task { [weak self] in
            guard let self else {
                return
            }
            let result = await perform(pending, appState: appState)
            draft = nil
            isApplying = false
            outcome = result
            revision += 1
            let message = String(localized: "Changes applied: \(result.applied)")
            LayoutBarItemView.announce(message)
        }
    }

    private func perform(_ pending: LayoutDraft, appState: AppState) async -> Outcome {
        // The arrangement as it is now stays in the history.
        appState.snapshots.willApplyProfile()
        let manager = appState.itemManager
        let controlled = Set(appState.automation.controlledItemKeys.map(manager.storedIdentityKey))
        var outcome = Outcome()
        var sectionChanges = [String: LayoutDraft.Section]()
        for (key, section) in pending.changedKeys {
            if controlled.contains(key) {
                outcome.leftToRules += 1
            } else {
                sectionChanges[key] = section
            }
        }
        outcome.applied = sectionChanges.count
        if #available(macOS 27.0, *) {
            // The sections of the applications are written once and applied once; then each
            // section is sorted on the bar, where the backend can.
            var applications = [String: MacOS27Section]()
            for (key, section) in sectionChanges {
                if let application = itemsByKey[key]?.layoutKey27 {
                    applications[application] = MacOS27Section(section.name)
                }
            }
            appState.concealer27.setSections(applications)
            appState.automation.itemsWereArrangedByHand()
            if pending.ordersWithinSection {
                await sortSections(of: pending, controlled: controlled, outcome: &outcome, appState: appState)
            }
            // The rows show the bar again once the draft goes: read it now, not at the next change.
            await manager.cacheItemsRegardless()
        } else {
            await layOutBeforeMacOS27(pending, sectionChanges: sectionChanges, controlled: controlled, manager: manager, outcome: &outcome)
        }
        if pending.newItems != pending.baselineNewItems {
            appState.settings.advanced.newItemsPlacement = Self.placement(for: pending.newItems)
            outcome.applied += 1
        }
        return outcome
    }

    /// Sorts each section on the bar in the drawing's order (macOS 27): the items that are not
    /// pinned and that no rule controls, by the executor. A stopped run or a blocker counts as one
    /// failure and ends the sorting of the remaining sections.
    @available(macOS 27.0, *)
    private func sortSections(
        of pending: LayoutDraft,
        controlled: Set<String>,
        outcome: inout Outcome,
        appState: AppState
    ) async {
        for section in LayoutDraft.Section.allCases {
            let windowIDs = pending.entries(in: section)
                .filter { !$0.isLocked && !controlled.contains($0.key) }
                .compactMap { itemsByKey[$0.key]?.windowID }
            guard windowIDs.count > 1 else {
                continue
            }
            let result = await ItemReorderer27.sort(desired: windowIDs, appState: appState)
            outcome.applied += result.moved
            if result.stop != nil || result.blocker != nil {
                outcome.failed += 1
                let word = result.stop.map { $0.rawValue } ?? result.blocker.map { String(describing: $0) } ?? "unknown"
                logger.debug("Sorting a section stopped: \(word, privacy: .public)")
                return
            }
        }
    }

    /// The pass before macOS 27: the items change section (the machinery of a profile), then
    /// each section is put in the drawing's order with as few moves as it takes.
    private func layOutBeforeMacOS27(
        _ pending: LayoutDraft,
        sectionChanges: [String: LayoutDraft.Section],
        controlled: Set<String>,
        manager: MenuBarItemManager,
        outcome: inout Outcome
    ) async {
        if !sectionChanges.isEmpty {
            await manager.reconcileSections(wanted: sectionChanges.mapValues(\.name), trigger: .profile)
        }
        if pending.ordersWithinSection {
            var failed = false
            for section in LayoutDraft.Section.allCases where !failed {
                let desired = pending.entries(in: section).map(\.key).filter { !controlled.contains($0) }
                guard desired.count > 1 else {
                    continue
                }
                let plan = await livePlan(for: section, desired: desired, manager: manager)
                for move in plan {
                    do {
                        try await place(move, in: section, manager: manager)
                        outcome.applied += 1
                    } catch {
                        logger.error("Error moving an item into place: \(error, privacy: .private)")
                        outcome.failed += 1
                        failed = true
                        break
                    }
                }
            }
        }
        // The move machinery refuses to read the bar within a second of a move.
        try? await Task.sleep(for: .milliseconds(1100))
        await manager.cacheItemsRegardless()
        manager.saveSectionsSoon()
    }

    /// The moves that put a section's items, as the bar holds them now, into the drawing's order.
    private func livePlan(for section: LayoutDraft.Section, desired: [String], manager: MenuBarItemManager) async -> [ReorderPlan.Move] {
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let pair = MenuBarItemManager.ControlItemPair(items: &items) else {
            return []
        }
        let actual = items
            .filter { manager.section(of: $0, controlItems: pair) == section.name }
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .map { manager.identityKey(for: $0) }
        let movable = Set(items.filter(\.isMovable).map { manager.identityKey(for: $0) })
        // An item macOS pins is not moved; the others are put in order around it.
        return ReorderPlan.moves(actual: actual, desired: desired).filter { movable.contains($0.key) }
    }

    /// Makes one move of a plan on the bar as it is now.
    private func place(_ move: ReorderPlan.Move, in section: LayoutDraft.Section, manager: MenuBarItemManager) async throws {
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let pair = MenuBarItemManager.ControlItemPair(items: &items) else {
            throw ApplyError.barUnreadable
        }
        let keys = Dictionary(items.map { (manager.identityKey(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        guard let item = keys[move.key] else {
            // The item left the bar meanwhile.
            return
        }
        let destination: MenuBarItemManager.MoveDestination
        if let before = move.before, let target = keys[before] {
            destination = .leftOfItem(target)
        } else {
            let row = items
                .filter { $0.windowID != item.windowID && $0.isMovable && manager.section(of: $0, controlItems: pair) == section.name }
                .sorted { $0.bounds.minX < $1.bounds.minX }
            if let last = row.last {
                destination = .rightOfItem(last)
            } else {
                destination = switch section {
                case .visible: .rightOfItem(pair.hidden)
                case .hidden: .leftOfItem(pair.hidden)
                case .alwaysHidden: .leftOfItem(pair.alwaysHidden ?? pair.hidden)
                }
            }
        }
        try await manager.move(item: item, to: destination, origin: .user)
    }

    private enum ApplyError: Error {
        case barUnreadable
    }

    // MARK: Draft

    /// Starts a draft from the bar if there is none.
    private func prepareDraft() -> Bool {
        if draft != nil {
            return !isApplying
        }
        guard !isApplying, let snapshot = snapshot() else {
            return false
        }
        outcome = nil
        itemsByKey = snapshot.items
        keysByWindow = snapshot.keys
        draft = LayoutDraft(sections: snapshot.sections, newItems: landing, ordersWithinSection: ordersWithinSection)
        return true
    }

    /// Tells the rows that the drawing changed. A drawing equal to the bar is dropped.
    private func didChange() {
        if draft?.isChanged == false {
            draft = nil
        }
        revision += 1
    }

    /// Follows the bar: the draft keeps what the user drew over what the bar holds now.
    private func cacheDidChange() {
        defer {
            revision += 1
        }
        guard !isApplying, var current = draft, let snapshot = snapshot() else {
            return
        }
        current.rebase(onto: snapshot.sections, newItems: landing)
        itemsByKey = snapshot.items
        keysByWindow = snapshot.keys
        draft = current.isChanged ? current : nil
    }

    /// The key of an item in the drawing.
    private func key(of item: MenuBarItem) -> String? {
        if let key = keysByWindow[item.windowID], itemsByKey[key] != nil {
            return key
        }
        return itemsByKey.first { $0.value.tag == item.tag }?.key
    }

    private struct Snapshot {
        var sections = [LayoutDraft.Section: [LayoutDraft.Entry]]()
        var items = [String: MenuBarItem]()
        var keys = [CGWindowID: String]()
    }

    /// Reads the item cache into entries.
    private func snapshot() -> Snapshot? {
        guard let appState else {
            return nil
        }
        let manager = appState.itemManager
        let cache = manager.itemCache
        var result = Snapshot()
        for name in MenuBarSection.Name.allCases {
            var entries = [LayoutDraft.Entry]()
            for item in cache[name] {
                var key = manager.identityKey(for: item)
                if result.items[key] != nil {
                    key += "#\(item.windowID)"
                }
                result.items[key] = item
                result.keys[item.windowID] = key
                entries.append(entry(for: item, key: key))
            }
            result.sections[LayoutDraft.Section(name)] = entries
        }
        return result
    }

    private func entry(for item: MenuBarItem, key: String) -> LayoutDraft.Entry {
        var isLocked = item.isControlItem || !item.isMovable
        var group = key
        if #available(macOS 27.0, *) {
            // macOS 27 hides whole applications; an item without one cannot be placed.
            if let layoutKey = item.layoutKey27 {
                group = layoutKey
            } else {
                isLocked = true
            }
        }
        return LayoutDraft.Entry(key: key, group: group, isLocked: isLocked)
    }

    /// Whether a drop within a row changes the order: the drawing's, or the backend's when there
    /// is no drawing yet.
    var ordersItems: Bool {
        draft?.ordersWithinSection ?? ordersWithinSection
    }

    /// Whether the order within a section is part of the drawing: always before macOS 27; on
    /// macOS 27 while the backend can put items in order and sorting has not turned itself off
    /// for the session.
    private var ordersWithinSection: Bool {
        if #available(macOS 27.0, *) {
            return appState?.itemManager.backend.reordersItems == true && !ItemReorderer27.isBlockedThisSession
        }
        return true
    }

    private var isMacOS27: Bool {
        if #available(macOS 27.0, *) {
            return true
        }
        return false
    }

    /// The section new items land in on the bar as it is.
    private var landing: LayoutDraft.Section {
        guard let appState else {
            return .visible
        }
        return NewItemsLanding.section(
            placement: appState.settings.advanced.newItemsPlacement.rawValue,
            isMacOS27: isMacOS27,
            alwaysHiddenIsOn: appState.settings.advanced.enableAlwaysHiddenSection
        )
    }

    private static func placement(for section: LayoutDraft.Section) -> NewItemsPlacement {
        NewItemsPlacement(rawValue: NewItemsLanding.placement(for: section)) ?? .systemDefault
    }
}

// MARK: - LayoutDraft.Section

nonisolated extension LayoutDraft.Section {
    /// The section of the same name on the bar.
    init(_ name: MenuBarSection.Name) {
        switch name {
        case .visible: self = .visible
        case .hidden: self = .hidden
        case .alwaysHidden: self = .alwaysHidden
        }
    }

    /// The section of the same name on the bar.
    var name: MenuBarSection.Name {
        switch self {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }
}
