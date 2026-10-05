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
        /// An application has launched (and its one re-check 2 s later).
        case applicationLaunch
        /// The bar has settled after a display change, wake or unlock.
        case settle
        /// A profile is applied.
        case profile
        /// The item list changed: only new items are placed.
        case itemListChange

        /// Whether items go back to their saved sections, not only new ones to theirs.
        var restoresSavedSections: Bool {
            self != .itemListChange
        }
    }

    // MARK: Saving

    /// Saves the section of every cached item under its identity key. Sections of items that
    /// are not on the bar now (their apps are not running) are kept.
    func saveSections() {
        guard backend.canMoveItems else {
            return
        }
        var stored = storedSectionIndexes()
        for section in MenuBarSection.Name.allCases {
            for item in itemCache[section] where !item.isControlItem && !item.tag.namespace.isUUID {
                stored[identityKey(for: item)] = section.profileIndex
            }
        }
        Defaults.set(stored, forKey: .itemSections)
        Self.restoreLogger.debug("Saved the sections of \(stored.count, privacy: .public) items")
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
    /// later (a single bounded re-check; the app may add its items late).
    func applicationDidLaunch() {
        applicationLaunchRestoreTask?.cancel()
        applicationLaunchRestoreTask = Task { [weak self] in
            for delay in [Duration.milliseconds(1500), .seconds(2)] {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                await cacheItemsIfNeeded()
                await reconcileSections(trigger: .applicationLaunch)
            }
        }
    }

    /// Moves every item into its section: the one in `wanted` (a profile), else the saved
    /// one, and new items into the section the new-items setting chooses. It is the one
    /// path that restores sections.
    ///
    /// Nothing happens while the user drags an item, while the Mac is not in use, while a
    /// save of the user's arrangement is pending, or while the items wait to be rehidden;
    /// a call during another reconciliation runs once that one ends. The moves are
    /// automatic, so `MoveBackoff` can pause them.
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
        await performReconciliation(
            wanted: wanted,
            trigger: trigger,
            items: givenItems,
            controlItems: givenControlItems,
            appState: appState
        )
        isReconcilingSections = false

        if let pending = pendingReconciliation {
            pendingReconciliation = nil
            await reconcileSections(wanted: pending.wanted, trigger: pending.trigger)
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

        let keepsLiveActivitiesVisible = appState.settings.advanced.keepLiveActivitiesVisible
        if keepsLiveActivitiesVisible {
            await keepLiveActivitiesVisible(items, controlItems: controlItems)
        }

        let keys = identityKeys(for: items)
        // Live Activities kept visible are never moved back by a saved or new-items section.
        let candidates = items.filter { item in
            item.isMovable &&
            item.canBeHidden &&
            !item.isControlItem &&
            !item.isSystemClone &&
            !item.tag.namespace.isUUID &&
            !(keepsLiveActivitiesVisible && item.tag.isLiveActivity) &&
            !isTemporarilyShown(item)
        }

        let storedKnown = Defaults.array(forKey: .knownItemTags) as? [String]
        var known = Set((storedKnown ?? []).map(storedIdentityKey))
        let saved = savedSections()
        let newItemsSection = appState.settings.advanced.newItemsPlacement.section

        var moves = [(item: MenuBarItem, key: String, section: MenuBarSection.Name, isNew: Bool)]()
        for item in candidates {
            guard let key = keys[item.windowID] else {
                continue
            }
            let isNew = storedKnown != nil && saved[key] == nil && !known.contains(key)
            var target: MenuBarSection.Name?
            if let wanted {
                target = wanted[key]
            } else if trigger.restoresSavedSections, let section = saved[key] {
                target = section
            } else if isNew {
                target = newItemsSection
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
        for move in moves {
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
                if move.isNew {
                    placedSections[move.key] = move.section
                }
            } catch EventError.automaticMovesPaused {
                Self.restoreLogger.warning("Automatic moves are paused, so not moving the remaining items into their sections")
                break
            } catch {
                Self.restoreLogger.error("Error moving \(move.item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
            }
        }

        // A new item that was not placed stays unknown, so a later pass places it.
        let unplacedKeys = Set(moves.filter { $0.isNew && placedSections[$0.key] == nil }.map(\.key))
        let candidateKeys = Set(candidates.compactMap { keys[$0.windowID] }).subtracting(unplacedKeys)
        if storedKnown == nil || !candidateKeys.isSubset(of: known) {
            known.formUnion(candidateKeys)
            Defaults.set(known.sorted(), forKey: .knownItemTags)
        }

        // A profile's sections, and where new items were placed, are the sections to restore.
        if let wanted {
            storeSections(wanted)
        }
        storeSections(placedSections)
    }

    /// The section an item is in, from its position relative to the control items.
    private func section(of item: MenuBarItem, controlItems: ControlItemPair) -> MenuBarSection.Name {
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
    private func keepLiveActivitiesVisible(_ items: [MenuBarItem], controlItems: ControlItemPair) async {
        for item in items where item.isMovable && !item.isControlItem {
            let isHidden = item.bounds.maxX <= controlItems.hidden.bounds.minX
            guard isHidden else {
                continue
            }
            if item.tag.isLiveActivity {
                do {
                    Self.restoreLogger.info("Keeping Live Activity \(item.logString, privacy: .private(mask: .hash)) visible")
                    try await move(item: item, to: .rightOfItem(controlItems.hidden))
                } catch EventError.automaticMovesPaused {
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
