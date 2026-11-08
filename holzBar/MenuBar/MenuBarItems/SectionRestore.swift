//
//  SectionRestore.swift
//  holzBar
//

import Cocoa
import OSLog

/// The one path that saves and restores the section of each item before macOS 27.
///
/// Before macOS 27 the bar itself was the only record of an item's section, so an item that
/// macOS put elsewhere — after the app relaunched or updated, after holzBar restarted, after
/// a display was connected — stayed there. Now the section of every item is saved under its
/// identity (`ItemIdentity`) once the user arranged the items (a drop in the Layout pane, a
/// Command-drag on the bar, a profile) and on the first run, and ``reconcileSections(wanted:trigger:)``
/// puts items back. It also places new items (the new-items setting) and keeps Live
/// Activities visible. macOS 27 keeps its sections per app (`Concealer27`) and does not use it.
extension MenuBarItemManager {
    /// Logger for saving and restoring sections.
    private static let restoreLogger = Logger(category: "SectionRestore")

    /// What asks for the sections to be reconciled.
    nonisolated enum SectionRestoreTrigger: String {
        /// holzBar has set up.
        case launch
        /// An application has launched (and its re-checks: 2 s later, then the bounded ones while
        /// an item still has a launch placeholder title).
        case applicationLaunch
        /// The bar has settled after a display change, wake or unlock.
        case settle
        /// A profile is applied.
        case profile
        /// The item list changed: only new items are placed.
        case itemListChange
        /// A move by holzBar pushed other items out of place; restores the saved sections and
        /// order.
        case moveRepair

        /// Whether items go back to their saved sections, not only new ones to theirs.
        var restoresSavedSections: Bool {
            self != .itemListChange
        }

        /// The kind of pass, for the neighbour check after each move.
        var pass: MoveNeighbourCheck.Pass {
            switch self {
            case .profile: .arrangement
            case .moveRepair: .repair
            case .launch, .applicationLaunch, .settle, .itemListChange: .restore
            }
        }
    }

    /// The pass of the reconciliation the current task runs, `nil` outside one. Bound to the
    /// task, so a move another task makes meanwhile (rehiding, the dividers) is not taken for one
    /// of the pass.
    nonisolated enum ReconciliationPass {
        @TaskLocal static var current: MoveNeighbourCheck.Pass?
    }

    // MARK: Saving

    /// Saves the section of every cached item under its identity key. Sections of items that
    /// are not on the bar now (their apps are not running) are kept. An item that still carries a
    /// launch placeholder title (`ItemPlaceholder`) is not saved: its key is not its own yet.
    func saveSections() {
        guard backend.canMoveItems else {
            return
        }
        var stored = storedSectionIndexes()
        for section in MenuBarSection.Name.allCases {
            for item in itemCache[section]
            where !item.isControlItem && !item.tag.namespace.isUUID && !isProvisionalPlaceholder(item) {
                stored[identityKey(for: item)] = section.profileIndex
            }
        }
        Defaults.set(stored, forKey: .itemSections)
        Self.restoreLogger.debug("Saved the sections of \(stored.count, privacy: .public) items")
        saveOrder(of: itemCache.managedItems)
    }

    /// Saves the order of the given items, left to right, merged with the stored order, so an
    /// item that is not on the bar now keeps its place (`ItemOrder`). Control items, items of a UUID
    /// namespace, temporarily shown items and items with a launch placeholder title are not part
    /// of the order. It runs at the moments the sections are saved, and once to seed the order of
    /// an existing install.
    private func saveOrder(of items: [MenuBarItem], keys: [CGWindowID: String]? = nil) {
        let ordered = items
            .filter {
                !$0.isControlItem && !$0.tag.namespace.isUUID && !isTemporarilyShown($0) && !isProvisionalPlaceholder($0)
            }
            .sorted { orderPosition(of: $0) < orderPosition(of: $1) }
        guard !ordered.isEmpty else {
            return
        }
        let merged = ItemOrder.merge(
            saved: storedOrder() ?? [],
            current: ordered.map { keys?[$0.windowID] ?? identityKey(for: $0) }
        )
        Defaults.set(merged, forKey: .itemOrder)
        Self.restoreLogger.debug("Saved the order of \(merged.count, privacy: .public) items")
    }

    /// The horizontal position of an item on the bar now.
    private func orderPosition(of item: MenuBarItem) -> CGFloat {
        (Bridging.getWindowBounds(for: item.windowID) ?? item.bounds).minX
    }

    /// The stored order under the keys they match today, or `nil` when none is stored yet. The
    /// value can be written by any process of the user, so it is capped before its keys are
    /// matched (several regular expressions each) and sanitized again after.
    private func storedOrder() -> [String]? {
        Defaults.stringArray(forKey: .itemOrder).map { raw in
            ItemOrder.sanitized(ItemOrder.sanitized(raw).map(storedIdentityKey))
        }
    }

    /// The identity keys that have a saved section (`ItemOrder.reappeared`).
    func savedSectionKeys() -> Set<String> {
        Set(storedSectionIndexes().keys)
    }

    /// Saves the sections of the given items (by identity key), keeping the others.
    func storeSections(_ sections: [String: MenuBarSection.Name]) {
        guard !sections.isEmpty else {
            return
        }
        var stored = storedSectionIndexes()
        for (key, section) in sections {
            stored[key] = section.profileIndex
        }
        Defaults.set(stored, forKey: .itemSections)
    }

    /// Saves the sections once the bar has taken the arrangement the user just made: a drop
    /// in the Layout pane or a Command-drag on the bar. Until then nothing is restored, so
    /// the old sections never undo the user's move.
    func saveSectionsSoon() {
        guard backend.canMoveItems else {
            return
        }
        // A rule that controls the item has to look at it again (never a timer: the move is the event).
        appState?.automation.itemsWereArrangedByHand()
        needsSectionSave = true
        sectionSaveTask?.cancel()
        // One read after holzBar's own recent-move pause (1 s) has passed; the read saves.
        sectionSaveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(1500))
            } catch {
                return
            }
            await self?.cacheItemsRegardless()
        }
    }

    /// The saved section of each identity key.
    private func savedSections() -> [String: MenuBarSection.Name] {
        storedSectionIndexes().compactMapValues(MenuBarSection.Name.init(profileIndex:))
    }

    /// The saved section indexes under the keys they match today. A key of an earlier read
    /// or version never outranks the current key it matches, and saving writes only these
    /// keys, so a stale section cannot come back.
    private func storedSectionIndexes() -> [String: Int] {
        let stored = Defaults.dictionary(forKey: .itemSections) as? [String: Int] ?? [:]
        return ItemIdentity.storedValues(stored, titleChangingOwners: titleChangingOwners)
    }

    // MARK: Restoring

    /// Restores an application's items a moment after it launched, and checks once more 2 s
    /// later (the app may add its items late). While items with a launch placeholder title
    /// remain (`ItemPlaceholder`), at most four more reads follow, 5 s, 15 s, 30 s and 12 s
    /// later, each only if such an item is still on the bar, so the last one falls after the
    /// 60 s period in which such an item counts as provisional.
    ///
    /// The re-checks are triggered by the launch and bounded (at most four extra reads within
    /// about 66 s), not polling: no event exists for a title change of a status item window. A
    /// later launch replaces the schedule: it cancels the waiting, never a pass that runs (see
    /// ``runLaunchPass(readsRegardless:)``).
    func applicationDidLaunch() {
        applicationLaunchRestoreTask?.cancel()
        applicationLaunchRestoreTask = Task { [weak self] in
            for delay in ItemPlaceholder.launchRecheckDelays {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                await runLaunchPass(readsRegardless: false)
            }
            await self?.recheckProvisionalItems()
        }
    }

    /// One read and reconciliation of the launch schedule, in a task of its own: cancelling the
    /// schedule (a later launch) then stops only its waiting. A pass cut off in the middle of a
    /// move would count as a failed automatic move and could mark a new item as known before it
    /// was placed.
    private func runLaunchPass(readsRegardless: Bool) async {
        await Task { [weak self] in
            guard let self else {
                return
            }
            if readsRegardless {
                await cacheItemsRegardless()
            } else {
                await cacheItemsIfNeeded()
            }
            await reconcileSections(trigger: .applicationLaunch)
        }.value
    }

    /// The bounded re-checks for items with a launch placeholder title: for each of
    /// `ItemPlaceholder.provisionalRecheckDelays`, stops as soon as no cached item is
    /// provisional, otherwise waits, reads the bar anew (a title change does not change the
    /// window list, so the read is never skipped) and reconciles.
    private func recheckProvisionalItems() async {
        for delay in ItemPlaceholder.provisionalRecheckDelays {
            guard itemCache.managedItems.contains(where: isProvisionalPlaceholder) else {
                return
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            await runLaunchPass(readsRegardless: true)
        }
    }

    /// Starts the provisional re-checks alone, after holzBar's own launch restore skipped an item
    /// with a launch placeholder title (holzBar started together with a slow app, at login). They
    /// run through ``applicationLaunchRestoreTask``, so a later app launch replaces them.
    private func startProvisionalRechecks() {
        applicationLaunchRestoreTask?.cancel()
        applicationLaunchRestoreTask = Task { [weak self] in
            await self?.recheckProvisionalItems()
        }
    }

    /// Moves every item into its section: the one in `wanted` (a profile), else the saved
    /// one, and new items into the section the new-items setting chooses. It is the one
    /// path that restores sections.
    ///
    /// Nothing happens while the user drags an item, while the Mac is not in use, while a
    /// save of the user's arrangement is pending, or while the items wait to be rehidden,
    /// and a running restore stops once the user drags an item or such a save is pending;
    /// a call during another reconciliation runs once that one ends. The moves are
    /// automatic, so `MoveBackoff` can pause them.
    ///
    /// A read with a divider right of the Clock (`DividerPlausibility`) is not believed: a
    /// restore, a launch or a settle moves nothing and places no new item from it, and the next
    /// read tries again. A profile applied on such a read runs its moves and stores its own
    /// sections, which do not depend on the read, but nothing from the read: no placed new items,
    /// no known items.
    ///
    /// - Parameters:
    ///   - wanted: The section of each identity key, when a profile is applied.
    ///   - trigger: What asks for the reconciliation.
    func reconcileSections(wanted: [String: MenuBarSection.Name]? = nil, trigger: SectionRestoreTrigger) async {
        await reconcileSections(wanted: wanted, trigger: trigger, items: nil, controlItems: nil)
    }

    /// Reconciles the sections of the given items (read anew when `nil`).
    func reconcileSections(
        wanted: [String: MenuBarSection.Name]? = nil,
        trigger: SectionRestoreTrigger,
        items givenItems: [MenuBarItem]?,
        controlItems givenControlItems: ControlItemPair?
    ) async {
        guard backend.canMoveItems, let appState else {
            return
        }
        guard !isReconcilingSections else {
            // A profile outranks a restore, and a restore outranks placing new items. Only a
            // later profile replaces a pending one, which is otherwise never applied.
            let pendingProfile = pendingReconciliation?.wanted != nil
            if wanted != nil || (!pendingProfile && (trigger.restoresSavedSections || pendingReconciliation == nil)) {
                pendingReconciliation = (wanted, trigger)
            }
            return
        }
        guard
            !appState.isDraggingMenuBarItem,
            !appState.systemActivityMonitor.isPaused,
            wanted != nil || !needsSectionSave
        else {
            Self.restoreLogger.debug("Not reconciling sections now (\(trigger.rawValue, privacy: .public))")
            return
        }

        isReconcilingSections = true
        await ReconciliationPass.$current.withValue(trigger.pass) {
            await performReconciliation(
                wanted: wanted,
                trigger: trigger,
                items: givenItems,
                controlItems: givenControlItems,
                appState: appState
            )
        }
        isReconcilingSections = false

        if let pending = pendingReconciliation {
            pendingReconciliation = nil
            await reconcileSections(wanted: pending.wanted, trigger: pending.trigger)
        }
    }

    /// Restores the saved sections and order once, after an automatic move pushed other items
    /// out of their places. Nothing happens while a repair is scheduled or running; a call while
    /// another reconciliation runs becomes its pending restore (see
    /// ``reconcileSections(wanted:trigger:items:controlItems:)``).
    ///
    /// The repair's own moves are automatic, so `MoveBackoff` bounds them (the same item at most
    /// 4 times in 60 s, 8 failures) and pauses repeated ones, and a move of a repair never
    /// schedules another repair.
    func scheduleMoveRepair() {
        guard !isMoveRepairScheduled else {
            return
        }
        isMoveRepairScheduled = true
        Task { [weak self] in
            guard let self else {
                return
            }
            await reconcileSections(trigger: .moveRepair)
            isMoveRepairScheduled = false
        }
    }

    /// The work of ``reconcileSections(wanted:trigger:)``.
    private func performReconciliation(
        wanted: [String: MenuBarSection.Name]?,
        trigger: SectionRestoreTrigger,
        items givenItems: [MenuBarItem]?,
        controlItems givenControlItems: ControlItemPair?,
        appState: AppState
    ) async {
        var items: [MenuBarItem]
        let controlItems: ControlItemPair
        if let givenItems, let givenControlItems {
            items = givenItems
            controlItems = givenControlItems
        } else {
            items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard let pair = ControlItemPair(items: &items) else {
                Self.restoreLogger.warning("Missing control item for hidden section, not reconciling sections")
                return
            }
            controlItems = pair
        }

        // A divider read right of the Clock is a bad read (`DividerPlausibility`). A restore from
        // it would move items into Hidden, so it moves nothing and places no new item; the next
        // read and the next settle, launch or app launch reach this point again. A profile the
        // user applies still runs its moves and stores its sections, but nothing from the bad read.
        let isPlausibleRead = dividersArePlausible(items: items, controlItems: controlItems)
        if !isPlausibleRead {
            if wanted == nil {
                Self.restoreLogger.notice(
                    "Not reconciling sections (\(trigger.rawValue, privacy: .public)): a divider reads right of the Clock"
                )
                return
            }
            Self.restoreLogger.notice("Applying a profile on a read with a divider right of the Clock: storing only its sections")
        }

        let keepsLiveActivitiesVisible = appState.settings.advanced.keepLiveActivitiesVisible
        if keepsLiveActivitiesVisible {
            await keepLiveActivitiesVisible(items, controlItems: controlItems, wanted: wanted, appState: appState)
        }

        let keys = identityKeys(for: items)
        // Live Activities kept visible are never moved back by a saved or new-items section.
        // A profile or the Layout pane is the user's arrangement and may move a Wine tray icon.
        let candidates = reconcilableItems(
            items,
            keepsLiveActivitiesVisible: keepsLiveActivitiesVisible,
            arrangedByUser: wanted != nil
        )

        let storedKnown = Defaults.array(forKey: .knownItemTags) as? [String]
        var known = Set((storedKnown ?? []).map(storedIdentityKey))
        let saved = savedSections()
        let newItemsSection = appState.settings.advanced.newItemsPlacement.section
        // Known items that came back (`ItemOrder.reappeared`) go to their saved section for every
        // trigger. A profile does not use them.
        let reappearedKeys = wanted == nil ? pendingReappearedKeys : []

        // Items that still carry a launch placeholder title (`ItemPlaceholder`): a profile and the
        // saved sections still apply to them, but they are neither placed as new nor remembered.
        var provisionalKeys = Set<String>()
        var skippedProvisionalNewItem = false

        var moves = [(item: MenuBarItem, key: String, section: MenuBarSection.Name, isNew: Bool)]()
        for item in candidates {
            guard let key = keys[item.windowID] else {
                continue
            }
            let isProvisional = isProvisionalPlaceholder(item)
            if isProvisional {
                provisionalKeys.insert(key)
            }
            let isNew = storedKnown != nil && saved[key] == nil && !known.contains(key)
            var target: MenuBarSection.Name?
            if let wanted {
                target = wanted[key]
            } else if trigger.restoresSavedSections || reappearedKeys.contains(key), let section = saved[key] {
                target = section
            } else if isNew {
                if isProvisional {
                    skippedProvisionalNewItem = true
                } else {
                    // A widget the user just added starts where they can see it (D-24).
                    let isWidget = item.tag.namespace == .holzBar && WidgetDefinition.isAutosaveName(item.tag.title)
                    target = isWidget ? .visible : newItemsSection
                }
            }
            guard var target else {
                continue
            }
            if target == .alwaysHidden && controlItems.alwaysHidden == nil {
                target = .hidden
            }
            if target != section(of: item, controlItems: controlItems) {
                moves.append((item, key, target, isNew))
            }
        }

        var placedSections = [String: MenuBarSection.Name]()
        // New items whose move was not tried: the loop stopped before them, or automatic
        // moves were paused. A move that failed otherwise is not retried on every read.
        var untriedNewKeys = Set(moves.filter(\.isNew).map(\.key))
        // Reappeared items whose move was not tried stay pending for the next read.
        var untriedReappearedKeys = Set(moves.map(\.key)).intersection(reappearedKeys)
        var stoppedEarly = false
        for move in moves {
            if await yieldsToUserAfterInputPause(wanted: wanted, appState: appState) {
                Self.restoreLogger.debug("The user arranges the items, so not moving the remaining items into their sections")
                stoppedEarly = true
                break
            }
            let destination: MoveDestination = switch move.section {
            case .visible: .rightOfItem(controlItems.hidden)
            case .hidden: .leftOfItem(controlItems.hidden)
            case .alwaysHidden: .leftOfItem(controlItems.alwaysHidden ?? controlItems.hidden)
            }
            do {
                Self.restoreLogger.info(
                    """
                    Moving \(move.item.logString, privacy: .private(mask: .hash)) into \
                    \(move.section.logString, privacy: .public) (\(trigger.rawValue, privacy: .public))
                    """
                )
                try await self.move(item: move.item, to: destination)
                untriedNewKeys.remove(move.key)
                untriedReappearedKeys.remove(move.key)
                if move.isNew {
                    placedSections[move.key] = move.section
                }
            } catch EventError.automaticMovesPaused {
                Self.restoreLogger.warning("Automatic moves are paused, so not moving the remaining items into their sections")
                stoppedEarly = true
                break
            } catch EventError.userInputNotPaused {
                Self.restoreLogger.notice("The user did not pause input, so not moving the remaining items into their sections")
                stoppedEarly = true
                break
            } catch where Task.isCancelled {
                // A cancelled pass did not try the move: the item stays new or pending.
                Self.restoreLogger.notice("The pass was cancelled, so not moving the remaining items into their sections")
                stoppedEarly = true
                break
            } catch {
                untriedNewKeys.remove(move.key)
                untriedReappearedKeys.remove(move.key)
                Self.restoreLogger.error("Error moving \(move.item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
            }
        }

        // A reappeared item that was moved, was in its section already or is not on this read is
        // done; only the ones whose move was not tried stay pending (keys that arrived while the
        // moves ran are not in the snapshot, so they stay too).
        let reappearedHere = reappearedKeys.intersection(candidates.compactMap { keys[$0.windowID] })
        if !reappearedKeys.isEmpty {
            pendingReappearedKeys.subtract(reappearedKeys.subtracting(untriedReappearedKeys))
            Self.restoreLogger.debug("Reappeared items: \(reappearedHere.count, privacy: .public)")
        }

        // A profile's sections do not come from the read, so they are stored on any read: the next
        // restore then keeps the profile instead of undoing it.
        if let wanted {
            storeSections(wanted)
        }

        // Nothing that comes from the read is stored from one that failed the divider check.
        guard isPlausibleRead else {
            return
        }

        // A new item whose move was not tried stays unknown, so a later pass places it. So does
        // an item with a launch placeholder title, until its title is final or its app has run
        // for a minute.
        if !provisionalKeys.isEmpty {
            Self.restoreLogger.debug("Not remembering \(provisionalKeys.count, privacy: .public) items with a launch placeholder title")
        }
        let candidateKeys = Set(candidates.compactMap { keys[$0.windowID] })
            .subtracting(untriedNewKeys)
            .subtracting(provisionalKeys)
        if storedKnown == nil || !candidateKeys.isSubset(of: known) {
            known.formUnion(candidateKeys)
            Defaults.set(known.sorted(), forKey: .knownItemTags)
        }

        // Where new items were placed is a section to restore too.
        storeSections(placedSections)

        // Only the launch restore starts the re-checks, so a re-check never starts another.
        if trigger == .launch && skippedProvisionalNewItem {
            startProvisionalRechecks()
        }

        // The order inside the sections, after the section moves. A profile does not reorder, and
        // a pass that stopped because the user arranges the items does not start another.
        // An item-list change reorders only the sections that hold a reappeared item.
        if wanted == nil, !stoppedEarly, trigger.restoresSavedSections || !reappearedHere.isEmpty {
            let sections = trigger.restoresSavedSections ? nil : Set(reappearedHere.compactMap { saved[$0] })
            await restoreOrder(trigger: trigger, sections: sections, appState: appState)
        }
    }

    /// The items a restore may move: movable, hideable, not a control item, a system clone or an
    /// item of a UUID namespace, not a Live Activity that is kept visible, not temporarily shown,
    /// and not a Windows app's tray icon (`UngovernedItemOwners`) unless the pass applies the
    /// user's own arrangement.
    private func reconcilableItems(
        _ items: [MenuBarItem],
        keepsLiveActivitiesVisible: Bool,
        arrangedByUser: Bool
    ) -> [MenuBarItem] {
        items.filter { item in
            item.isMovable &&
            item.canBeHidden &&
            !item.isControlItem &&
            !item.isSystemClone &&
            !item.tag.namespace.isUUID &&
            !(keepsLiveActivitiesVisible && item.tag.isLiveActivity) &&
            UngovernedItemOwners.allowsReconciling(isUngoverned: item.tag.isUngoverned, arrangedByUser: arrangedByUser) &&
            !isTemporarilyShown(item)
        }
    }

    /// The order pass: puts the items of each section back into the saved order (`ItemOrder`)
    /// with as few moves as possible, at most `ItemOrder.maximumMovesPerPass` in all.
    ///
    /// With no stored order, holzBar's own launch restore seeds it from the bar as it is then
    /// (an existing install has sections but no order) and moves nothing; any other trigger does
    /// nothing. The bar is read anew because the section moves changed the positions, and a read
    /// with a divider right of the Clock is not believed. The moves are automatic, so
    /// `MoveBackoff` bounds them, and each waits for the user to pause input.
    ///
    /// - Parameters:
    ///   - trigger: What asks for the reconciliation.
    ///   - sections: The only sections to reorder, or `nil` for all.
    ///   - appState: The app state.
    private func restoreOrder(trigger: SectionRestoreTrigger, sections: Set<MenuBarSection.Name>?, appState: AppState) async {
        let stored = storedOrder()
        guard stored != nil || trigger == .launch else {
            return
        }
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let controlItems = ControlItemPair(items: &items) else {
            Self.restoreLogger.warning("Missing control item for hidden section, not ordering items")
            return
        }
        guard dividersArePlausible(items: items, controlItems: controlItems) else {
            Self.restoreLogger.notice("Not ordering items (\(trigger.rawValue, privacy: .public)): a divider reads right of the Clock")
            return
        }
        let keys = identityKeys(for: items)
        guard let stored else {
            guard !appState.isDraggingMenuBarItem, !needsSectionSave else {
                return
            }
            saveOrder(of: items, keys: keys)
            return
        }

        let keepsLiveActivitiesVisible = appState.settings.advanced.keepLiveActivitiesVisible
        var entriesBySection = [MenuBarSection.Name: [(key: String, item: MenuBarItem)]]()
        for item in reconcilableItems(items, keepsLiveActivitiesVisible: keepsLiveActivitiesVisible, arrangedByUser: false)
            .sorted(by: { orderPosition(of: $0) < orderPosition(of: $1) }) {
            if let key = keys[item.windowID] {
                entriesBySection[section(of: item, controlItems: controlItems), default: []].append((key, item))
            }
        }

        var planned = [(item: MenuBarItem, destination: MoveDestination)]()
        for name in MenuBarSection.Name.allCases where sections?.contains(name) ?? true {
            guard let entries = entriesBySection[name] else {
                continue
            }
            let itemsByKey = Dictionary(entries.map { ($0.key, $0.item) }) { first, _ in first }
            for step in ItemOrder.plan(current: entries.map(\.key), wanted: stored) {
                guard let item = itemsByKey[step.key] else {
                    continue
                }
                switch step.anchor {
                case .after(let anchorKey):
                    if let anchor = itemsByKey[anchorKey] {
                        planned.append((item, .rightOfItem(anchor)))
                    }
                case .before(let anchorKey):
                    if let anchor = itemsByKey[anchorKey] {
                        planned.append((item, .leftOfItem(anchor)))
                    }
                }
            }
        }
        guard !planned.isEmpty else {
            return
        }
        Self.restoreLogger.info(
            "Ordering items: \(planned.count, privacy: .public) moves planned (\(trigger.rawValue, privacy: .public))"
        )

        for move in planned.prefix(ItemOrder.maximumMovesPerPass) {
            if await yieldsToUserAfterInputPause(wanted: nil, appState: appState) {
                Self.restoreLogger.debug("The user arranges the items, so not ordering the remaining items")
                return
            }
            do {
                Self.restoreLogger.info("Ordering \(move.item.logString, privacy: .private(mask: .hash)) (\(trigger.rawValue, privacy: .public))")
                try await self.move(item: move.item, to: move.destination)
            } catch EventError.automaticMovesPaused {
                Self.restoreLogger.warning("Automatic moves are paused, so not ordering the remaining items")
                return
            } catch EventError.userInputNotPaused {
                Self.restoreLogger.notice("The user did not pause input, so not ordering the remaining items")
                return
            } catch where Task.isCancelled {
                Self.restoreLogger.notice("The pass was cancelled, so not ordering the remaining items")
                return
            } catch {
                Self.restoreLogger.error("Error ordering \(move.item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
            }
        }
    }

    /// How long the application of an item has run, for the rule of ``ItemPlaceholder``: since
    /// the later of its launch and holzBar's own (an item that holzBar finds at its own start is
    /// as young as holzBar), ignoring a missing date. With no date it is not young.
    private func runningDuration(of item: MenuBarItem) -> Duration {
        let launchDates = [
            (item.sourceApplication ?? item.owningApplication)?.launchDate,
            NSRunningApplication.current.launchDate,
        ].compactMap(\.self)
        guard let launchDate = launchDates.max() else {
            return ItemPlaceholder.provisionalPeriod
        }
        return .seconds(max(0, Date.now.timeIntervalSince(launchDate)))
    }

    /// Whether the item still carries a launch placeholder title while its app is young
    /// (`ItemPlaceholder.isProvisional`). Only items with a placeholder title look up their
    /// application.
    private func isProvisionalPlaceholder(_ item: MenuBarItem) -> Bool {
        guard ItemIdentity.isPlaceholderTitle(item.tag.title) else {
            return false
        }
        return ItemPlaceholder.isProvisional(title: item.tag.title, runningFor: runningDuration(of: item))
    }

    /// Whether a restore stops moving items because the user arranges them: an item is being
    /// dragged, or a save of the user's arrangement is pending. A profile is applied regardless.
    private func yieldsToUser(wanted: [String: MenuBarSection.Name]?, appState: AppState) -> Bool {
        wanted == nil && (appState.isDraggingMenuBarItem || needsSectionSave)
    }

    /// Waits for the user to pause input, then returns whether a restore stops moving items
    /// because the user arranges them. A move waits for that pause itself, and a Command-drag
    /// of the item about to be moved lasts through it, so the check comes after the wait; the
    /// move's own wait then returns at once.
    private func yieldsToUserAfterInputPause(wanted: [String: MenuBarSection.Name]?, appState: AppState) async -> Bool {
        guard wanted == nil else {
            return false
        }
        do {
            try await MenuBarItemEventPoster.waitForUserToPauseInput()
        } catch {
            return true
        }
        return yieldsToUser(wanted: wanted, appState: appState)
    }

    /// The section an item is in, from its position relative to the control items.
    func section(of item: MenuBarItem, controlItems: ControlItemPair) -> MenuBarSection.Name {
        let bounds = Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        let hiddenBounds = Bridging.getWindowBounds(for: controlItems.hidden.windowID) ?? controlItems.hidden.bounds
        if bounds.minX >= hiddenBounds.maxX {
            return .visible
        }
        if let alwaysHidden = controlItems.alwaysHidden {
            let alwaysHiddenBounds = Bridging.getWindowBounds(for: alwaysHidden.windowID) ?? alwaysHidden.bounds
            if bounds.maxX <= alwaysHiddenBounds.minX {
                return .alwaysHidden
            }
        }
        return .hidden
    }

    /// Moves Live Activities that macOS put in a hidden section to the visible
    /// one (jordanbaird/Ice#731).
    ///
    /// A Live Activity appears as a new item at the far left of the bar, which
    /// is a hidden section, so without this it is only seen by showing that section.
    private func keepLiveActivitiesVisible(
        _ items: [MenuBarItem],
        controlItems: ControlItemPair,
        wanted: [String: MenuBarSection.Name]?,
        appState: AppState
    ) async {
        for item in items where item.isMovable && !item.isControlItem {
            if yieldsToUser(wanted: wanted, appState: appState) {
                return
            }
            let isHidden = item.bounds.maxX <= controlItems.hidden.bounds.minX
            guard isHidden else {
                continue
            }
            if item.tag.isLiveActivity {
                if await yieldsToUserAfterInputPause(wanted: wanted, appState: appState) {
                    return
                }
                do {
                    Self.restoreLogger.info("Keeping Live Activity \(item.logString, privacy: .private(mask: .hash)) visible")
                    try await move(item: item, to: .rightOfItem(controlItems.hidden))
                } catch EventError.automaticMovesPaused, EventError.userInputNotPaused {
                    return
                } catch {
                    Self.restoreLogger.error("Error moving Live Activity \(item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
                }
            } else if item.tag.namespace.isUUID || item.tag.namespace.description.hasPrefix("com.apple.") {
                // Helps find the process that draws Live Activities.
                Self.restoreLogger.debug("Hidden system item: \(item.tag.description, privacy: .private(mask: .hash))")
            }
        }
    }
}
