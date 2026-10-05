//
//  MenuBarItemManager.swift
//  holzBar
//

import Cocoa
import Observation
import os
import OSLog

/// Manager for menu bar items.
@MainActor
@Observable
final class MenuBarItemManager {
    /// The current cache of menu bar items.
    private(set) var itemCache = ItemCache(displayID: nil)

    /// Logger for the menu bar item manager.
    @ObservationIgnored private nonisolated let logger = Logger.menuBarItemManager

    /// Reads, moves and clicks the items the way the running macOS needs.
    @ObservationIgnored let backend: any MenuBarBackend = MenuBarBackends.current

    /// Actor for managing menu bar item cache operations.
    @ObservationIgnored private let cacheActor = CacheActor()

    /// Contexts for temporarily shown menu bar items.
    @ObservationIgnored private var temporarilyShownItemContexts = [TemporarilyShownItemContext]()

    /// A timer for rehiding temporarily shown menu bar items.
    @ObservationIgnored private var rehideTimer: Timer?

    /// Whether the "Hide opened items again after" delay runs: it starts when no shown
    /// item's menu is open any more (THAW-13).
    @ObservationIgnored private var isRehideDelayRunning = false

    /// Pauses automatic moves after repeated failures or a repeatedly moved item.
    @ObservationIgnored private var moveBackoff = MoveBackoff()

    /// The end of the pause of automatic moves that was last logged, so it is logged once.
    @ObservationIgnored private var loggedPauseEnd: ContinuousClock.Instant?

    /// Whether temporarily shown items wait to be rehidden until automatic moves may run
    /// again (on the next settle or user move) instead of retrying every 3 seconds.
    @ObservationIgnored private var isRehideWaitingForMoves = false

    /// The namespaces whose item titles change beyond their numbers (`ItemIdentity`).
    @ObservationIgnored private(set) var titleChangingOwners = Set<String>()

    /// The bar as last read, for learning which apps change their item titles.
    @ObservationIgnored private var previousIdentityItems: [ItemIdentity.Item]?

    /// The identity key of each cached item, by window.
    @ObservationIgnored private var identityKeysByWindow = [CGWindowID: String]()

    /// Whether the sections are saved after the next item cache, because the user arranged
    /// items (see `SectionRestore.swift`).
    @ObservationIgnored var needsSectionSave = false

    /// Whether the sections are being reconciled.
    @ObservationIgnored var isReconcilingSections = false

    /// A reconciliation asked for while one was running; it runs once that one ends.
    @ObservationIgnored var pendingReconciliation: (wanted: [String: MenuBarSection.Name]?, trigger: SectionRestoreTrigger)?

    /// The restore after an application launched, with its one re-check.
    @ObservationIgnored var applicationLaunchRestoreTask: Task<Void, Never>?

    /// The cache that records the sections the user just arranged.
    @ObservationIgnored var sectionSaveTask: Task<Void, Never>?

    /// Tasks that observe the events that may change the item list.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Observes the running applications.
    @ObservationIgnored private var runningApplicationsObservation: NSKeyValueObservation?

    /// Observes the Settings pane that is shown.
    @ObservationIgnored private var settingsPaneObserver: ObservationLoop?

    /// Reads the item list again 1 s after the last event that may have changed it.
    @ObservationIgnored private let itemListDebouncer = Debouncer(delay: .seconds(1))

    /// When the first event that still waits for ``itemListDebouncer`` came.
    @ObservationIgnored private var itemListChangePendingSince: ContinuousClock.Instant?

    /// Reads the item list again 1.5 s after the last application activation, where the
    /// backend asks for it.
    @ObservationIgnored private let activationDebouncer = Debouncer(delay: .milliseconds(1500))

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        self.appState = appState
        titleChangingOwners = Set(Defaults.array(forKey: .titleChangingItemOwners) as? [String] ?? [])
        await cacheItemsRegardless()
        await reconcileSections(trigger: .launch)
        configureObservers(with: appState)
    }

    /// Configures the internal observers for the manager.
    private func configureObservers(with appState: AppState) {
        // The item list is read again on events: an application launches or quits, the
        // active space or the screens change, or (on macOS 27) a process that owns items
        // creates or destroys an Accessibility element. A slow, tolerant fallback catches
        // an item that appears without any of these; it replaced a 5 s timer that read
        // the window list (on macOS 27, every process through Accessibility) at idle.
        // The events are debounced by 1 s, as the Combine pipeline was, but wait 5 s at
        // most; the fallback reads at once, so events that never pause cannot hold it up.
        runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                // A launched application needs a moment to add its items.
                try? await Task.sleep(for: .milliseconds(250))
                self?.itemListMayHaveChanged()
            }
        }
        let notifications: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ] + backend.itemChangeNotifications
        observerTasks = notifications.map { center, name in
            Task { [weak self] in
                for await notification in center.notifications(named: name) {
                    if name == .menuBarItemsMayHaveChanged27 {
                        let pid = notification.userInfo?["pid"] as? pid_t
                        self?.logItemChangeNotification(pid: pid)
                    }
                    self?.itemListMayHaveChanged()
                }
            }
        }
        observerTasks.append(Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(60), tolerance: .seconds(10))
                } catch {
                    return
                }
                guard let self else {
                    return
                }
                if self.appState?.systemActivityMonitor.isPaused != true {
                    await cacheItemsIfNeeded()
                }
            }
        })

        let navigationState = appState.navigationState
        settingsPaneObserver = ObservationLoop.observe { navigationState.settingsNavigationIdentifier } onChange: { [weak self] identifier in
            guard let self, identifier == .menuBarLayout else {
                return
            }
            Task {
                await self.cacheItemsRegardless()
            }
        }

        if backend.canMoveItems {
            // An application that launches may put its items anywhere; they go back to their
            // sections (see `SectionRestore.swift`).
            observerTasks.append(Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.didLaunchApplicationNotification) {
                    self?.applicationDidLaunch()
                }
            })
        }

        if backend.refreshesAfterApplicationActivation {
            // Accessibility reports frames only for the active menu bar, so read the
            // items again soon after it moves to another display.
            observerTasks.append(Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.didActivateApplicationNotification) {
                    // The menu bar takes about a second to move (measured).
                    self?.activationDebouncer.schedule { [weak self] in
                        guard let self else {
                            return
                        }
                        Task {
                            await self.cacheItemsIfNeeded()
                        }
                    }
                }
            })
        }
    }

    /// Reads the item list again once the events that may have changed it pause for 1 s,
    /// or 5 s after the first of them while they keep coming (on macOS 27, an item owner
    /// whose elements change every moment).
    ///
    /// Nothing is read while the screen is locked, the Mac sleeps or the session is away;
    /// the list is read once the bar has settled afterwards.
    private func itemListMayHaveChanged() {
        if appState?.systemActivityMonitor.isPaused == true {
            return
        }
        let now = ContinuousClock.now
        let pendingSince = itemListChangePendingSince ?? now
        if pendingSince.duration(to: now) >= .seconds(5) {
            itemListChangePendingSince = nil
            itemListDebouncer.cancel()
            Task {
                await cacheItemsIfNeeded()
            }
            return
        }
        itemListChangePendingSince = pendingSince
        itemListDebouncer.schedule { [weak self] in
            guard let self else {
                return
            }
            itemListChangePendingSince = nil
            Task {
                await self.cacheItemsIfNeeded()
            }
        }
    }

    /// Logs that an Accessibility notification of an item owner asks for a refresh.
    private func logItemChangeNotification(pid: pid_t?) {
        guard let pid else {
            return
        }
        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown"
        logger.debug("Item owner \(bundleID, privacy: .private(mask: .hash)) changed its elements, refreshing the item list")
    }

    /// Returns a Boolean value that indicates whether the most recent
    /// menu bar item move operation occurred within the given duration.
    func lastMoveOperationOccurred(within duration: Duration) -> Bool {
        guard let timestamp = backend.lastMoveOperationTimestamp else {
            return false
        }
        return timestamp.duration(to: .now) <= duration
    }
}

// MARK: - Item Cache

extension MenuBarItemManager {
    /// An actor that manages menu bar item cache operations.
    private final actor CacheActor {
        /// Stored task for the current cache operation.
        private var cacheTask: Task<Void, Never>?

        /// A list of the menu bar item window identifiers at the time
        /// of the previous cache.
        private(set) var cachedItemWindowIDs = [CGWindowID]()

        /// Runs the given async closure as a task and waits for it to
        /// complete before returning.
        ///
        /// If a task from a previous call to this method is currently
        /// running, that task is cancelled and replaced.
        func runCacheTask(_ operation: @escaping @MainActor @Sendable () async -> Void) async {
            cacheTask.take()?.cancel()
            let task = Task(operation: operation)
            cacheTask = task
            await task.value
        }

        /// Updates the list of cached menu bar item window identifiers.
        func updateCachedItemWindowIDs(_ itemWindowIDs: [CGWindowID]) {
            cachedItemWindowIDs = itemWindowIDs
        }

        /// Clears the list of cached menu bar item window identifiers.
        func clearCachedItemWindowIDs() {
            cachedItemWindowIDs.removeAll()
        }
    }

    /// Cache for menu bar items.
    struct ItemCache: Hashable {
        /// Storage for cached menu bar items, keyed by section.
        private var storage = [MenuBarSection.Name: [MenuBarItem]]()

        /// The identifier of the display with the active menu bar at
        /// the time this cache was created.
        let displayID: CGDirectDisplayID?

        /// The cached menu bar items as an array.
        var managedItems: [MenuBarItem] {
            MenuBarSection.Name.allCases.reduce(into: []) { result, section in
                guard let items = storage[section] else {
                    return
                }
                result.append(contentsOf: items)
            }
        }

        /// Creates a cache with the given display identifier.
        init(displayID: CGDirectDisplayID?) {
            self.displayID = displayID
        }

        /// Returns the address for the menu bar item with the given tag,
        /// if it exists in the cache.
        func address(for tag: MenuBarItemTag) -> (section: MenuBarSection.Name, index: Int)? {
            for (section, items) in storage {
                guard let index = items.firstIndex(matching: tag) else {
                    continue
                }
                return (section, index)
            }
            return nil
        }

        /// Inserts the given menu bar item into the cache at the specified
        /// destination, or at the edge of `fallbackSection` next to holzBar's divider when
        /// the destination's target item is gone.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination, orIn fallbackSection: MenuBarSection.Name) {
            let targetTag = destination.targetItem.tag

            if targetTag == .hiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.hidden].append(item)
                case .rightOfItem:
                    self[.visible].insert(item, at: 0)
                }
                return
            }

            if targetTag == .alwaysHiddenControlItem {
                switch destination {
                case .leftOfItem:
                    self[.alwaysHidden].append(item)
                case .rightOfItem:
                    self[.hidden].insert(item, at: 0)
                }
                return
            }

            guard case (let section, var index)? = address(for: targetTag) else {
                if fallbackSection == .visible {
                    self[.visible].insert(item, at: 0)
                } else {
                    self[fallbackSection].append(item)
                }
                return
            }

            if case .rightOfItem = destination {
                let range = self[section].startIndex...self[section].endIndex
                index = (index + 1).clamped(to: range)
            }

            self[section].insert(item, at: index)
        }

        /// Accesses the items in the given section.
        subscript(section: MenuBarSection.Name) -> [MenuBarItem] {
            get { storage[section, default: []] }
            set { storage[section] = newValue }
        }
    }

    /// A pair of control items, taken from a list of menu bar items
    /// during a menu bar item cache operation.
    struct ControlItemPair {
        let hidden: MenuBarItem
        let alwaysHidden: MenuBarItem?

        init?(items: inout [MenuBarItem]) {
            guard let hidden = items.removeFirst(matching: .hiddenControlItem) else {
                return nil
            }
            self.hidden = hidden
            self.alwaysHidden = items.removeFirst(matching: .alwaysHiddenControlItem)
        }
    }

    /// Context maintained during a menu bar item cache operation.
    private struct CacheContext {
        let controlItems: ControlItemPair

        var cache: ItemCache
        var temporarilyShownItems = [(MenuBarItem, MoveDestination, MenuBarSection.Name)]()
        var shouldClearCachedItemWindowIDs = false

        private(set) lazy var hiddenControlItemBounds = bestBounds(for: controlItems.hidden)
        private(set) lazy var alwaysHiddenControlItemBounds = controlItems.alwaysHidden.map { bestBounds(for: $0) }

        init(controlItems: ControlItemPair, displayID: CGDirectDisplayID?) {
            self.controlItems = controlItems
            self.cache = ItemCache(displayID: displayID)
        }

        func bestBounds(for item: MenuBarItem) -> CGRect {
            Bridging.getWindowBounds(for: item.windowID) ?? item.bounds
        }

        func isValidForCaching(_ item: MenuBarItem) -> Bool {
            if !item.canBeHidden {
                return false
            }
            if item.isSystemClone {
                return false
            }
            if item.isControlItem, item.tag != .visibleControlItem {
                return false
            }
            return true
        }

        mutating func findSection(for item: MenuBarItem) -> MenuBarSection.Name? {
            lazy var itemBounds = bestBounds(for: item)
            return MenuBarSection.Name.allCases.first { section in
                switch section {
                case .visible:
                    return itemBounds.minX >= hiddenControlItemBounds.maxX
                case .hidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX &&
                        itemBounds.minX >= alwaysHiddenControlItemBounds.maxX
                    } else {
                        return itemBounds.maxX <= hiddenControlItemBounds.minX
                    }
                case .alwaysHidden:
                    if let alwaysHiddenControlItemBounds {
                        return itemBounds.maxX <= alwaysHiddenControlItemBounds.minX
                    } else {
                        return false
                    }
                }
            }
        }
    }

    /// Caches the given menu bar items, without ensuring that the provided
    /// control items are correctly ordered.
    private func uncheckedCacheItems(
        items: [MenuBarItem],
        controlItems: ControlItemPair,
        displayID: CGDirectDisplayID?
    ) async {
        var context = CacheContext(controlItems: controlItems, displayID: displayID)

        for item in items where context.isValidForCaching(item) {
            if item.sourcePID == nil {
                logger.warning("Missing sourcePID for \(item.logString, privacy: .private(mask: .hash))")
                context.shouldClearCachedItemWindowIDs = true
            }

            if let temp = temporarilyShownItemContexts.first(where: { $0.matches(item) }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, temp.returnDestination, temp.returnSection))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            logger.warning("Couldn't find section for caching \(item.logString, privacy: .private(mask: .hash))")
            context.shouldClearCachedItemWindowIDs = true
        }

        for (item, destination, section) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination, orIn: section)
        }

        if context.shouldClearCachedItemWindowIDs {
            logger.info("Clearing cached menu bar item windowIDs")
            await cacheActor.clearCachedItemWindowIDs() // Ensure next cache isn't skipped.
        }

        // A newer cache replaced this one; its items are the current ones.
        guard !Task.isCancelled else {
            return
        }

        guard itemCache != context.cache else {
            logger.debug("Not updating menu bar item cache, as items haven't changed")
            return
        }

        itemCache = context.cache
        logger.debug("Updated menu bar item cache")
    }

    /// Caches the current menu bar items, regardless of whether the
    /// items have changed since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsRegardless(_ currentItemWindowIDs: [CGWindowID]? = nil) async {
        await cacheActor.runCacheTask { [weak self] in
            guard let self else {
                return
            }

            guard appState?.systemActivityMonitor.isPaused != true else {
                logger.debug("Skipping menu bar item cache while the Mac is not in use")
                return
            }

            guard !lastMoveOperationOccurred(within: .seconds(1)) else {
                logger.debug("Skipping menu bar item cache due to recent item movement")
                return
            }

            let displayID = Bridging.getActiveMenuBarDisplayID()
            var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            // A newer cache replaced this one while it waited (`runCacheTask`); a stale
            // read must not overwrite its result, so every wait is followed by a check.
            guard !Task.isCancelled else {
                return
            }

            let itemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }
            await cacheActor.updateCachedItemWindowIDs(itemWindowIDs)

            guard !Task.isCancelled else {
                return
            }

            if let appState, let cache = backend.cacheFromLayout(items: items, displayID: displayID, appState: appState) {
                // On macOS 27 the saved layout, not the order on the bar, places items in sections
                // (see `AccessibilityBackend27`). The items are keyed together, so several
                // items of one app keep apart (`ItemIdentity`); titles are not learned here.
                identityKeysByWindow = identityKeys(for: items)
                if itemCache != cache {
                    itemCache = cache
                    logger.info(
                        """
                        macOS 27 cache: \
                        visible=\(cache[.visible].map(\.tag.namespace.description).joined(separator: ","), privacy: .private(mask: .hash)) \
                        hidden=\(cache[.hidden].map(\.tag.namespace.description).joined(separator: ","), privacy: .private(mask: .hash)) \
                        alwaysHidden=\(cache[.alwaysHidden].map(\.tag.namespace.description).joined(separator: ","), privacy: .private(mask: .hash))
                        """
                    )
                }
                return
            }

            guard let controlItems = ControlItemPair(items: &items) else {
                // ???: Is clearing the cache the best thing to do here?
                logger.error(
                    """
                    Missing control item for hidden section, clearing menu bar item cache \
                    (\(items.count, privacy: .public) items: \
                    \(items.prefix(12).map(\.tag.description).joined(separator: ", "), privacy: .private(mask: .hash)))
                    """
                )
                itemCache = ItemCache(displayID: nil)
                // The window list may have been read while Control Center was still updating
                // the dividers' windows (macOS 26), so the next read of an unchanged list must
                // not be skipped. It comes with the next event, timer or Shelf, not from here.
                await cacheActor.clearCachedItemWindowIDs()
                return
            }

            // Where items cannot be moved, the dividers stay where macOS placed them.
            if backend.canMoveItems {
                await enforceControlItemOrder(controlItems: controlItems)
                guard !Task.isCancelled else {
                    return
                }
                // Forget the UUIDs of item windows that are gone (on every space).
                pruneUUIDCache(keeping: Bridging.getMenuBarWindowList(option: .itemsOnly))
                updateIdentities(with: items)
            }
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)

            guard !Task.isCancelled else {
                return
            }

            if backend.canMoveItems {
                // The sections the user arranged, or of the first run, are recorded.
                if needsSectionSave || Defaults.dictionary(forKey: .itemSections) == nil {
                    needsSectionSave = false
                    saveSections()
                }
                // Moving runs outside the cache task, which it would otherwise hold up.
                Task {
                    await self.reconcileSections(trigger: .itemListChange, items: items, controlItems: controlItems)
                }
            }
        }
    }

    /// Caches the current menu bar items, if the items have changed
    /// since the previous cache.
    ///
    /// Before caching, this method ensures that the control items for
    /// the hidden and always-hidden sections are correctly ordered,
    /// arranging them into valid positions if needed.
    func cacheItemsIfNeeded() async {
        let signature = await backend.itemListSignature()
        if await cacheActor.cachedItemWindowIDs != signature {
            await cacheItemsRegardless(signature)
        }
    }
}

// MARK: - Event Helpers

extension MenuBarItemManager {
    /// An error that can occur during menu bar item event operations.
    nonisolated enum EventError: CustomStringConvertible, LocalizedError {
        /// A generic indication of a failure.
        case cannotComplete
        /// An event source cannot be created or is otherwise invalid.
        case invalidEventSource
        /// The location of the mouse cannot be found.
        case missingMouseLocation
        /// A failure during the creation of an event.
        case eventCreationFailure(MenuBarItem)
        /// A timeout during an event operation.
        case eventOperationTimeout(MenuBarItem)
        /// A menu bar item is not movable.
        case itemNotMovable(MenuBarItem)
        /// A timeout waiting for a menu bar item to respond to an event.
        case itemResponseTimeout(MenuBarItem)
        /// A menu bar item's bounds cannot be found.
        case missingItemBounds(MenuBarItem)
        /// Automatic moves are paused (see `MoveBackoff` and `SystemActivityMonitor`).
        case automaticMovesPaused

        var description: String {
            switch self {
            case .cannotComplete:
                "\(Self.self).cannotComplete"
            case .invalidEventSource:
                "\(Self.self).invalidEventSource"
            case .missingMouseLocation:
                "\(Self.self).missingMouseLocation"
            case .eventCreationFailure(let item):
                "\(Self.self).eventCreationFailure(item: \(item.tag))"
            case .eventOperationTimeout(let item):
                "\(Self.self).eventOperationTimeout(item: \(item.tag))"
            case .itemNotMovable(let item):
                "\(Self.self).itemNotMovable(item: \(item.tag))"
            case .itemResponseTimeout(let item):
                "\(Self.self).itemResponseTimeout(item: \(item.tag))"
            case .missingItemBounds(let item):
                "\(Self.self).missingItemBounds(item: \(item.tag))"
            case .automaticMovesPaused:
                "\(Self.self).automaticMovesPaused"
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                String(localized: "Operation could not be completed")
            case .invalidEventSource:
                String(localized: "Invalid event source")
            case .missingMouseLocation:
                String(localized: "Missing mouse location")
            case .eventCreationFailure(let item):
                String(localized: "Could not create event for \u{201C}\(item.displayName)\u{201D}")
            case .eventOperationTimeout(let item):
                String(localized: "Event operation timed out for \u{201C}\(item.displayName)\u{201D}")
            case .itemNotMovable(let item):
                String(localized: "\u{201C}\(item.displayName)\u{201D} is not movable")
            case .itemResponseTimeout(let item):
                String(localized: "\u{201C}\(item.displayName)\u{201D} took too long to respond")
            case .missingItemBounds(let item):
                String(localized: "Missing bounds rectangle for \u{201C}\(item.displayName)\u{201D}")
            case .automaticMovesPaused:
                String(localized: "Automatic moves are paused")
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .itemNotMovable, .automaticMovesPaused:
                return nil
            default:
                return String(localized: "Please try again. If the error persists, please file a bug report.")
            }
        }
    }
}

// MARK: - Moving Items

extension MenuBarItemManager {
    /// Destinations for menu bar item move operations.
    nonisolated enum MoveDestination {
        /// The destination to the left of the given target item.
        case leftOfItem(MenuBarItem)
        /// The destination to the right of the given target item.
        case rightOfItem(MenuBarItem)

        /// The destination's target item.
        var targetItem: MenuBarItem {
            switch self {
            case .leftOfItem(let item), .rightOfItem(let item): item
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .leftOfItem(let item): "left of \(item.logString)"
            case .rightOfItem(let item): "right of \(item.logString)"
            }
        }
    }

    /// Who asked for a move.
    nonisolated enum MoveOrigin {
        /// The user, by dragging an item in the Layout pane or opening one from the Shelf,
        /// search or a group. Always allowed; it ends a pause of automatic moves.
        case user
        /// holzBar itself: placing new items, keeping Live Activities visible, rehiding,
        /// ordering the dividers or applying a profile. Paused by `MoveBackoff` and while
        /// the Mac is not in use.
        case automatic
    }

    /// Moves a menu bar item to the given destination.
    ///
    /// An automatic move throws ``EventError/automaticMovesPaused`` while automatic moves
    /// are paused: after repeated failures or a repeatedly moved item (`MoveBackoff`), and
    /// while the screen is locked, the Mac sleeps or the session is away.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    ///   - origin: Who asked for the move.
    func move(item: MenuBarItem, to destination: MoveDestination, origin: MoveOrigin = .automatic) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            throw EventError.cannotComplete
        }
        switch origin {
        case .user:
            moveBackoff.recordUserMove()
            loggedPauseEnd = nil
        case .automatic:
            try checkAutomaticMove(of: item, appState: appState)
        }
        do {
            try await backend.move(item: item, to: destination, appState: appState)
        } catch {
            if origin == .automatic, moveBackoff.recordFailure(at: .now) {
                logPausedMoves()
            }
            throw error
        }
        if origin == .user, isRehideWaitingForMoves {
            // The user's move ended the pause; the waiting items are rehidden after the
            // usual interval (not at once: this may be an item the user is opening).
            isRehideWaitingForMoves = false
            runRehideTimer()
        }
    }

    /// Throws when an automatic move of the given item may not run now, and counts it
    /// otherwise.
    private func checkAutomaticMove(of item: MenuBarItem, appState: AppState) throws {
        guard !appState.systemActivityMonitor.isPaused else {
            throw EventError.automaticMovesPaused
        }
        let now = ContinuousClock.now
        guard moveBackoff.allowsAutomaticMove(at: now) else {
            logPausedMoves()
            throw EventError.automaticMovesPaused
        }
        if moveBackoff.recordAutomaticMove(identifier: item.tag.description, at: now) {
            logPausedMoves()
            throw EventError.automaticMovesPaused
        }
    }

    /// Logs the current pause of automatic moves, once per pause.
    private func logPausedMoves() {
        guard let pausedUntil = moveBackoff.pausedUntil, pausedUntil != loggedPauseEnd else {
            return
        }
        loggedPauseEnd = pausedUntil
        let seconds = Int(ContinuousClock.now.duration(to: pausedUntil).components.seconds)
        logger.warning("Automatic moves paused until \(seconds, privacy: .public) s from now")
    }

    /// Clicks a menu bar item with the given mouse button.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to click.
    ///   - mouseButton: The mouse button to click the item with.
    func click(item: MenuBarItem, with mouseButton: CGMouseButton) async throws {
        guard let appState else {
            throw EventError.cannotComplete
        }
        try await backend.click(item: item, with: mouseButton, appState: appState)
    }
}

// MARK: - Temporarily Showing Items

extension MenuBarItemManager {
    /// Context for a temporarily shown menu bar item.
    private final class TemporarilyShownItemContext {
        /// The tag associated with the item.
        let tag: MenuBarItemTag

        /// The item's window.
        let windowID: CGWindowID

        /// The item's identity key (`ItemIdentity`).
        let identityKey: String

        /// The destination to return the item to, as it was when the item was shown.
        let returnDestination: MoveDestination

        /// The identity key of the destination's target item (`ItemIdentity`).
        let returnTargetIdentityKey: String

        /// The section the item was shown from, which it returns to when the destination's
        /// target item is gone.
        let returnSection: MenuBarSection.Name

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        ///
        /// Only a menu counts (`InterfaceWindowRule`): another window of the app, such as a
        /// small floating one, never kept the item from being hidden again (Thaw #1158).
        var isShowingInterface: Bool {
            guard
                let window = shownInterfaceWindow,
                let current = WindowInfo(windowID: window.windowID)
            else {
                // Window no longer exists, so assume closed.
                return false
            }
            // The window was recorded as a new window of the item's app after the click.
            return current.isOnScreen && InterfaceWindowRule.counts(
                layer: current.layer,
                isOwnersWindow: true,
                appearedAfterClick: true
            )
        }

        init(
            tag: MenuBarItemTag,
            windowID: CGWindowID,
            identityKey: String,
            returnDestination: MoveDestination,
            returnTargetIdentityKey: String,
            returnSection: MenuBarSection.Name
        ) {
            self.tag = tag
            self.windowID = windowID
            self.identityKey = identityKey
            self.returnDestination = returnDestination
            self.returnTargetIdentityKey = returnTargetIdentityKey
            self.returnSection = returnSection
        }

        /// Whether the context belongs to the given item: the same window, or the same tag.
        func matches(_ item: MenuBarItem) -> Bool {
            item.windowID == windowID || item.tag == tag
        }
    }

    /// Gets the destination to return the given item to after it is
    /// temporarily shown.
    private func getReturnDestination(for item: MenuBarItem, in items: [MenuBarItem]) -> MoveDestination? {
        guard let index = items.firstIndex(matching: item.tag) else {
            return nil
        }
        if items.indices.contains(index + 1) {
            return .leftOfItem(items[index + 1])
        }
        if items.indices.contains(index - 1) {
            return .rightOfItem(items[index - 1])
        }
        return nil
    }

    /// Resolves the destination to return the item of the given context to from the
    /// current items.
    ///
    /// The target item is found again by its window, its tag or its identity key, as it
    /// may have been re-created while the item was shown. When it is gone, the item returns
    /// to the edge of its section next to holzBar's divider; the stored target's window no
    /// longer has bounds, so moving to it failed on every attempt.
    private func resolveReturnDestination(
        for context: TemporarilyShownItemContext,
        in items: [MenuBarItem],
        keys: [CGWindowID: String]
    ) -> MoveDestination? {
        let target = context.returnDestination.targetItem
        let resolved = items.first { $0.windowID == target.windowID }
            ?? items.first { $0.tag == target.tag }
            ?? items.first { keys[$0.windowID] == context.returnTargetIdentityKey }
        if let resolved {
            switch context.returnDestination {
            case .leftOfItem:
                return .leftOfItem(resolved)
            case .rightOfItem:
                return .rightOfItem(resolved)
            }
        }
        guard let hiddenControlItem = items.first(matching: .hiddenControlItem) else {
            return nil
        }
        switch context.returnSection {
        case .visible:
            return .rightOfItem(hiddenControlItem)
        case .hidden:
            return .leftOfItem(hiddenControlItem)
        case .alwaysHidden:
            return .leftOfItem(items.first(matching: .alwaysHiddenControlItem) ?? hiddenControlItem)
        }
    }

    /// Schedules a timer for the given interval that rehides the
    /// temporarily shown items when fired.
    private func runRehideTimer(for interval: TimeInterval? = nil) {
        guard let appState else {
            return
        }
        let interval = interval ?? appState.settings.advanced.tempShowInterval
        logger.debug("Running rehide timer for interval: \(interval, format: .fixed, privacy: .public)")
        rehideTimer?.invalidate()
        rehideTimer = .scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            logger.debug("Rehide timer fired")
            Task {
                await self.rehideTemporarilyShownItems()
            }
        }
    }

    /// Temporarily shows the given item.
    ///
    /// The item is cached and returned to its original location after the
    /// time interval specified by ``AdvancedSettings/tempShowInterval``.
    ///
    /// - Parameters:
    ///   - item: The item to temporarily show.
    ///   - mouseButton: The mouse button to click the item with.
    func temporarilyShow(item: MenuBarItem, clickingWith mouseButton: CGMouseButton) async {
        guard let appState else {
            logger.error("Missing AppState, so not showing \(item.logString, privacy: .private(mask: .hash))")
            return
        }
        guard let screen = NSScreen.screenWithActiveMenuBar else {
            logger.error("No active menu bar screen, so not showing \(item.logString, privacy: .private(mask: .hash))")
            return
        }

        guard let applicationMenuFrame = appState.applicationMenuFrames.frame(for: screen) else {
            logger.error("No application menu frame, so not showing \(item.logString, privacy: .private(mask: .hash))")
            return
        }

        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

        guard let destination = getReturnDestination(for: item, in: items) else {
            logger.error("No return destination for \(item.logString, privacy: .private(mask: .hash))")
            return
        }

        // Remove all items up to and including the hidden control item.
        if let index = items.firstIndex(matching: .hiddenControlItem) {
            items.removeSubrange(...index)
        }

        let maxX: CGFloat = {
            var maxX = applicationMenuFrame.maxX
            if let frameOfNotch = screen.frameOfNotch {
                maxX = max(maxX, frameOfNotch.maxX + 30)
            }
            return maxX + item.bounds.width
        }()

        // Remove items until we have enough room to show this item.
        items.trimPrefix { item in
            if item.isOnScreen && item.canBeHidden {
                return item.bounds.minX <= maxX
            }
            return true
        }

        guard let targetItem = items.first else {
            logger.warning("Not enough room to show \(item.logString, privacy: .private(mask: .hash))")
            let alert = NSAlert()
            alert.messageText = String(localized: "Not enough room to show \u{201C}\(item.displayName)\u{201D}")
            alert.runModal()
            return
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        logger.debug("Temporarily showing \(item.logString, privacy: .private(mask: .hash))")

        do {
            try await move(item: item, to: .leftOfItem(targetItem), origin: .user)
        } catch {
            logger.error("Error showing item: \(error, privacy: .private)")
            return
        }

        let context = TemporarilyShownItemContext(
            tag: item.tag,
            windowID: item.windowID,
            identityKey: identityKey(for: item),
            returnDestination: destination,
            returnTargetIdentityKey: identityKey(for: destination.targetItem),
            returnSection: itemCache.address(for: item.tag)?.section ?? .hidden
        )
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        isRehideDelayRunning = false
        defer {
            // The first check comes soon; the delay counts from when the menu closes.
            runRehideTimer(for: 1)
        }

        await MenuBarItemEventPoster.eventSleep(for: .milliseconds(100))
        let idsBeforeClick = Set(Bridging.getWindowList(option: .onScreen))

        do {
            try await click(item: item, with: mouseButton)
        } catch {
            logger.error("Error clicking item: \(error, privacy: .private)")
            return
        }

        await MenuBarItemEventPoster.eventSleep(for: .milliseconds(250))
        let windowsAfterClick = WindowInfo.createWindows(option: .onScreen)

        context.shownInterfaceWindow = windowsAfterClick.first { window in
            InterfaceWindowRule.counts(
                layer: window.layer,
                isOwnersWindow: window.ownerPID == item.sourcePID,
                appearedAfterClick: !idsBeforeClick.contains(window.windowID)
            )
        }
    }

    /// Rehides all temporarily shown items.
    ///
    /// If an item is currently showing its interface, this method waits
    /// for the interface to close before hiding the items.
    func rehideTemporarilyShownItems() async {
        guard let appState else {
            logger.error("Missing AppState, so not rehiding")
            return
        }
        guard !temporarilyShownItemContexts.isEmpty else {
            return
        }
        // While automatic moves are paused, the items wait for the next settle or user
        // move instead of retrying every few seconds.
        guard
            !appState.systemActivityMonitor.isPaused,
            moveBackoff.allowsAutomaticMove(at: .now)
        else {
            waitToRehide(appState: appState)
            return
        }
        isRehideWaitingForMoves = false
        guard !temporarilyShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            isRehideDelayRunning = false
            runRehideTimer(for: 3)
            return
        }
        // "Hide opened items again after" counts from when the menu was seen closed.
        if !isRehideDelayRunning {
            let delay = min(max(appState.settings.advanced.tempShowInterval, 0), 30)
            if delay > 0 {
                isRehideDelayRunning = true
                runRehideTimer(for: delay)
                return
            }
        }
        guard MenuBarItemEventPoster.hasUserPausedInput(for: .milliseconds(250)) else {
            logger.debug("Found recent user input, so waiting to rehide")
            runRehideTimer(for: 1)
            return
        }
        isRehideDelayRunning = false

        var currentContexts = temporarilyShownItemContexts
        temporarilyShownItemContexts.removeAll()

        let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        var failedContexts = [TemporarilyShownItemContext]()

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        await MenuBarItemEventPoster.eventSleep(for: .milliseconds(250))

        logger.debug("Rehiding temporarily shown items")

        MouseHelpers.hideCursor()
        defer {
            MouseHelpers.showCursor()
        }

        let keys = identityKeys(for: items)
        while let context = currentContexts.popLast() {
            // The window first (it lasts while the app runs), then the identity, which
            // survives a title that changed while the item was shown.
            let item = items.first { $0.windowID == context.windowID }
                ?? items.first { keys[$0.windowID] == context.identityKey }
            guard let item else {
                continue
            }
            guard let destination = resolveReturnDestination(for: context, in: items, keys: keys) else {
                // The dividers were not read; the next attempt reads the items again.
                logger.warning("No return destination for \(item.logString, privacy: .private(mask: .hash))")
                failedContexts.append(context)
                continue
            }
            do {
                try await move(item: item, to: destination)
            } catch EventError.automaticMovesPaused {
                // Paused during the rehide: the rest waits for the next settle or user move.
                failedContexts.append(context)
                failedContexts.append(contentsOf: currentContexts.reversed())
                currentContexts.removeAll()
            } catch {
                context.rehideAttempts += 1
                logger.warning(
                    """
                    Attempt \(context.rehideAttempts, privacy: .public) to rehide \
                    \(item.logString, privacy: .private(mask: .hash)) failed with error: \
                    \(error, privacy: .private)
                    """
                )
                if context.rehideAttempts < 3 {
                    currentContexts.append(context) // Try again.
                } else {
                    // Failed contexts are ultimately added back to the array
                    // and rehidden after a longer delay, so reset the count.
                    context.rehideAttempts = 0
                    failedContexts.append(context)
                }
            }
        }

        if failedContexts.isEmpty {
            logger.debug("All items were successfully rehidden")
        } else {
            logger.error(
                """
                Some items failed to rehide: \
                \(failedContexts.map { $0.tag }, privacy: .private(mask: .hash))
                """
            )
            temporarilyShownItemContexts.append(contentsOf: failedContexts.reversed())
            if appState.systemActivityMonitor.isPaused || !moveBackoff.allowsAutomaticMove(at: .now) {
                waitToRehide(appState: appState)
            } else {
                runRehideTimer(for: 3)
            }
        }
    }

    /// Lets the temporarily shown items wait while automatic moves are paused: they are
    /// rehidden on the next settle or user move, or once when the back-off's pause ends.
    private func waitToRehide(appState: AppState) {
        logger.debug("Automatic moves are paused, so waiting to rehide")
        isRehideWaitingForMoves = true
        rehideTimer?.invalidate()
        rehideTimer = nil
        // While the Mac is not in use the settle brings them back; otherwise one timer
        // fires as the pause ends.
        guard !appState.systemActivityMonitor.isPaused, let pausedUntil = moveBackoff.pausedUntil else {
            return
        }
        let remaining = ContinuousClock.now.duration(to: pausedUntil)
        let seconds = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
        runRehideTimer(for: max(seconds, 0) + 1)
    }

    /// Rehides the temporarily shown items once, if they wait for automatic moves to be
    /// allowed again (after a settle or a user move).
    func retryPausedRehide() async {
        guard isRehideWaitingForMoves else {
            return
        }
        isRehideWaitingForMoves = false
        await rehideTemporarilyShownItems()
    }

    /// Whether the given item is shown for a moment and waits to be rehidden.
    func isTemporarilyShown(_ item: MenuBarItem) -> Bool {
        temporarilyShownItemContexts.contains { $0.matches(item) }
    }

    /// Removes a temporarily shown item from the cache, ensuring that
    /// the item is _not_ returned to its original location.
    func removeTemporarilyShownItemFromCache(with tag: MenuBarItemTag) {
        while let index = temporarilyShownItemContexts.firstIndex(where: { $0.tag == tag }) {
            logger.debug(
                """
                Removing temporarily shown item from cache: \
                \(tag, privacy: .private(mask: .hash))
                """
            )
            temporarilyShownItemContexts.remove(at: index)
        }
    }
}

// MARK: - Control Item Order

extension MenuBarItemManager {
    /// Enforces the order of the given control items, ensuring that the
    /// control item for the always-hidden section is positioned to the
    /// left of control item for the hidden section.
    private func enforceControlItemOrder(controlItems: ControlItemPair) async {
        let hidden = controlItems.hidden

        guard
            let alwaysHidden = controlItems.alwaysHidden,
            hidden.bounds.maxX <= alwaysHidden.bounds.minX
        else {
            return
        }

        do {
            logger.debug("Control items have incorrect order")
            try await move(item: alwaysHidden, to: .leftOfItem(hidden))
        } catch {
            logger.error("Error enforcing control item order: \(error, privacy: .private)")
        }
    }
}

// MARK: - Item Identity

extension MenuBarItemManager {
    /// The identity keys of the given items, by window, keyed in the bar's order (left to
    /// right) (`ItemIdentity`).
    func identityKeys(for items: [MenuBarItem]) -> [CGWindowID: String] {
        let ordered = items.sorted { $0.bounds.minX < $1.bounds.minX }
        let keys = ItemIdentity.keys(
            for: ordered.map { (namespace: $0.tag.namespace.description, title: $0.tag.title) },
            titleChangingOwners: titleChangingOwners
        )
        return Dictionary(zip(ordered.map(\.windowID), keys)) { first, _ in first }
    }

    /// The key under which the given item is stored in profiles, groups, the known items and
    /// the saved sections. It is the only way an item becomes a stored key.
    func identityKey(for item: MenuBarItem) -> String {
        if let key = identityKeysByWindow[item.windowID] {
            return key
        }
        let keys = ItemIdentity.keys(
            for: [(namespace: item.tag.namespace.description, title: item.tag.title)],
            titleChangingOwners: titleChangingOwners
        )
        return keys.first ?? item.tag.description
    }

    /// The key a stored key (of this or an earlier version) matches today.
    func storedIdentityKey(_ stored: String) -> String {
        ItemIdentity.storedKey(stored, titleChangingOwners: titleChangingOwners)
    }

    /// Learns which apps change their item titles from this and the previous read of the bar,
    /// and keys the items anew.
    private func updateIdentities(with items: [MenuBarItem]) {
        let current = items
            .sorted { $0.bounds.minX < $1.bounds.minX }
            .map { (namespace: $0.tag.namespace.description, title: $0.tag.title) }
        if let previousIdentityItems {
            let learned = ItemIdentity.learnTitleChangingOwners(
                previous: previousIdentityItems,
                current: current,
                excluding: [Constants.bundleIdentifier]
            )
            let newlyLearned = learned.subtracting(titleChangingOwners)
            if !newlyLearned.isEmpty {
                titleChangingOwners.formUnion(newlyLearned)
                Defaults.set(titleChangingOwners.sorted(), forKey: .titleChangingItemOwners)
                logger.info("Learned \(newlyLearned.count, privacy: .public) apps whose item titles change")
            }
        }
        previousIdentityItems = current
        identityKeysByWindow = identityKeys(for: items)
    }
}

// MARK: - Logger Helpers

nonisolated private extension Logger {
    /// Logger for the menu bar item manager.
    static let menuBarItemManager = Logger(category: "MenuBarItemManager")
}
