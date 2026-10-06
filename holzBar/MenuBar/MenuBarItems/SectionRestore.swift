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
///
/// Only the user's arrangements count as a settings change for sync
/// (`SettingsSync.userChangedLayout()`), and only where they change a saved section; the
/// first-run save, the placement of new items and the record of where macOS put an item
/// holzBar left there are holzBar's own and do not (SA-05).
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
    ///
    /// After an arrangement of the user's, the bar as holzBar last read it before the
    /// arrangement (``sectionsBeforeArrangement``) tells what the user moved: an item macOS
    /// displaced before it keeps its saved section, and an item's first move counts
    /// (`SettingsSyncPolicy.sectionsToSave`).
    ///
    /// - Parameter byUser: Whether the user arranged the items; holzBar's first-run save does
    ///   not count as a settings change for sync.
    func saveSections(byUser: Bool) {
        guard backend.canMoveItems else {
            return
        }
        var onBar = [String: Int]()
        for section in MenuBarSection.Name.allCases {
            for item in itemCache[section] where !item.isControlItem && !item.tag.namespace.isUUID {
                onBar[identityKey(for: item)] = section.profileIndex
            }
        }
        let save = SettingsSyncPolicy.sectionsToSave(
            byUser: byUser,
            onBar: onBar,
            saved: storedSectionIndexes(),
            beforeArrangement: sectionsBeforeArrangement?.mapValues(\.profileIndex)
        )
        if byUser {
            // The read before this arrangement is used up; the next reconciliation reads anew.
            sectionsBeforeArrangement = nil
        }
        Defaults.set(save.sections, forKey: .itemSections)
        // A Command-click on the bar that moved nothing is no change of the user's, nor is an
        // item saved for the first time where macOS put it.
        if save.countsAsEdit {
            SettingsSync.userChangedLayout()
        }
        Self.restoreLogger.debug("Saved the sections of \(save.sections.count, privacy: .public) items")
    }

    /// Saves the sections of the given items (by identity key), keeping the others.
    ///
    /// - Parameter byUser: Whether the user chose the sections, with a profile; holzBar's
    ///   placement of new items does not count as a settings change for sync.
    func storeSections(_ sections: [String: MenuBarSection.Name], byUser: Bool) {
        guard !sections.isEmpty else {
            return
        }
        let before = storedSectionIndexes()
        var stored = before
        for (key, section) in sections {
            stored[key] = section.profileIndex
        }
        Defaults.set(stored, forKey: .itemSections)
        if SettingsSyncPolicy.countsAsLayoutEdit(byUser: byUser, saved: stored, before: before) {
            SettingsSync.userChangedLayout()
        }
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
    /// save of the user's arrangement is pending, or while the items wait to be rehidden,
    /// and a running restore stops once the user drags an item or such a save is pending;
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
            await keepLiveActivitiesVisible(items, controlItems: controlItems, wanted: wanted, appState: appState)
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

        // The bar as read now is the bar before the user's next arrangement, unless the user
        // may be arranging it already.
        let recordsBar = SettingsSyncPolicy.capturesBarBeforeArrangement(
            isDragging: appState.isDraggingMenuBarItem,
            savesArrangementSoon: needsSectionSave || userMovesInProgress > 0,
            commandHeld: NSEvent.modifierFlags.contains(.command),
            mouseButtonPressed: NSEvent.pressedMouseButtons != 0
        )
        if recordsBar {
            var bar = [String: MenuBarSection.Name]()
            for item in candidates {
                if let key = keys[item.windowID] {
                    bar[key] = section(of: item, controlItems: controlItems)
                }
            }
            sectionsBeforeArrangement = bar
        }

        let storedKnown = Defaults.array(forKey: .knownItemTags) as? [String]
        var known = Set((storedKnown ?? []).map(storedIdentityKey))
        let saved = savedSections()
        let newItemsSection = appState.settings.advanced.newItemsPlacement.section

        var moves = [(item: MenuBarItem, key: String, section: MenuBarSection.Name, isNew: Bool)]()
        // Items without a saved section that stay where they are, by their section now.
        var unsavedSections = [String: MenuBarSection.Name]()
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
                if saved[key] == nil {
                    unsavedSections[key] = section(of: item, controlItems: controlItems)
                }
                continue
            }
            if target == .alwaysHidden && controlItems.alwaysHidden == nil {
                target = .hidden
            }
            let current = section(of: item, controlItems: controlItems)
            if target != current {
                moves.append((item, key, target, isNew))
            } else if saved[key] == nil {
                unsavedSections[key] = current
            }
        }

        var placedSections = [String: MenuBarSection.Name]()
        // New items whose move was not tried: the loop stopped before them, or automatic
        // moves were paused. A move that failed otherwise is not retried on every read.
        var untriedNewKeys = Set(moves.filter(\.isNew).map(\.key))
        for move in moves {
            if await yieldsToUserAfterInputPause(wanted: wanted, appState: appState) {
                Self.restoreLogger.debug("The user arranges the items, so not moving the remaining items into their sections")
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
                if recordsBar {
                    sectionsBeforeArrangement?[move.key] = move.section
                }
                if move.isNew {
                    placedSections[move.key] = move.section
                }
            } catch EventError.automaticMovesPaused {
                Self.restoreLogger.warning("Automatic moves are paused, so not moving the remaining items into their sections")
                break
            } catch EventError.userInputNotPaused {
                Self.restoreLogger.notice("The user did not pause input, so not moving the remaining items into their sections")
                break
            } catch {
                untriedNewKeys.remove(move.key)
                Self.restoreLogger.error("Error moving \(move.item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
            }
        }

        // A new item whose move was not tried stays unknown, so a later pass places it.
        let candidateKeys = Set(candidates.compactMap { keys[$0.windowID] }).subtracting(untriedNewKeys)
        if storedKnown == nil || !candidateKeys.isSubset(of: known) {
            known.formUnion(candidateKeys)
            Defaults.set(known.sorted(), forKey: .knownItemTags)
        }

        // A profile's sections, and where new items were placed, are the sections to restore.
        if let wanted {
            storeSections(wanted, byUser: true)
        }
        // holzBar's own placements never replace a section the user saved while the items
        // moved (`SettingsSyncPolicy.ownPlacementsToStore`).
        storeSections(SettingsSyncPolicy.ownPlacementsToStore(placedSections, savedNow: savedSections(), wanted: wanted), byUser: false)
        // So is where macOS put an item holzBar left there, as holzBar's own placement: a later
        // move of the user's then changes a saved section and counts for sync
        // (`SettingsSyncPolicy.sectionsToSave`). Not while the user arranges the items,
        // as the section may be one the user is choosing.
        if !yieldsToUser(wanted: nil, appState: appState) {
            storeSections(SettingsSyncPolicy.ownPlacementsToStore(unsavedSections, savedNow: savedSections(), wanted: wanted), byUser: false)
        }
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
