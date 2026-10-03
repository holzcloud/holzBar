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

    /// Tasks that observe the events that may change the item list.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Observes the running applications.
    @ObservationIgnored private var runningApplicationsObservation: NSKeyValueObservation?

    /// Observes the Settings pane that is shown.
    @ObservationIgnored private var settingsPaneObserver: ObservationLoop?

    /// Reads the item list again 1 s after the last event that may have changed it.
    @ObservationIgnored private let itemListDebouncer = Debouncer(delay: .seconds(1))

    /// Reads the item list again 1.5 s after the last application activation, where the
    /// backend asks for it.
    @ObservationIgnored private let activationDebouncer = Debouncer(delay: .milliseconds(1500))

    /// The shared app state.
    @ObservationIgnored private(set) weak var appState: AppState?

    /// Sets up the manager.
    func performSetup(with appState: AppState) async {
        self.appState = appState
        await cacheItemsRegardless()
        configureObservers(with: appState)
    }

    /// Configures the internal observers for the manager.
    private func configureObservers(with appState: AppState) {
        // The item list is read again on events: an application launches or quits, the
        // active space or the screens change, or (on macOS 27) a process that owns items
        // creates or destroys an Accessibility element. A slow, tolerant fallback catches
        // an item that appears without any of these; it replaced a 5 s timer that read
        // the window list (on macOS 27, every process through Accessibility) at idle.
        // All of them are debounced by 1 s, as the Combine pipeline was.
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
                self?.itemListMayHaveChanged()
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

    /// Reads the item list again once the events that may have changed it pause for 1 s.
    private func itemListMayHaveChanged() {
        itemListDebouncer.schedule { [weak self] in
            guard let self else {
                return
            }
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
        /// destination.
        mutating func insert(_ item: MenuBarItem, at destination: MoveDestination) {
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
    private struct ControlItemPair {
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
        var temporarilyShownItems = [(MenuBarItem, MoveDestination)]()
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

            if let temp = temporarilyShownItemContexts.first(where: { $0.tag == item.tag }) {
                // Cache temporarily shown items as if they were in their original locations.
                // Keep track of them separately and use their return destinations to insert
                // them into the cache once all other items have been handled.
                context.temporarilyShownItems.append((item, temp.returnDestination))
                continue
            }

            if let section = context.findSection(for: item) {
                context.cache[section].append(item)
                continue
            }

            logger.warning("Couldn't find section for caching \(item.logString, privacy: .private(mask: .hash))")
            context.shouldClearCachedItemWindowIDs = true
        }

        for (item, destination) in context.temporarilyShownItems {
            context.cache.insert(item, at: destination)
        }

        if context.shouldClearCachedItemWindowIDs {
            logger.info("Clearing cached menu bar item windowIDs")
            await cacheActor.clearCachedItemWindowIDs() // Ensure next cache isn't skipped.
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

            guard !lastMoveOperationOccurred(within: .seconds(1)) else {
                logger.debug("Skipping menu bar item cache due to recent item movement")
                return
            }

            let displayID = Bridging.getActiveMenuBarDisplayID()
            var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)

            let itemWindowIDs = currentItemWindowIDs ?? items.reversed().map { $0.windowID }
            await cacheActor.updateCachedItemWindowIDs(itemWindowIDs)

            if let appState, let cache = backend.cacheFromLayout(items: items, displayID: displayID, appState: appState) {
                // On macOS 27 the saved layout, not the order on the bar, places items in sections
                // (see `AccessibilityBackend27`).
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
                return
            }

            // Where items cannot be moved, the dividers stay where macOS placed them.
            if backend.canMoveItems {
                await enforceControlItemOrder(controlItems: controlItems)
                // Forget the UUIDs of item windows that are gone (on every space).
                pruneUUIDCache(keeping: Bridging.getMenuBarWindowList(option: .itemsOnly))
            }
            await uncheckedCacheItems(items: items, controlItems: controlItems, displayID: displayID)

            if backend.canMoveItems {
                // Moving runs outside the cache task, which it would otherwise hold up.
                Task {
                    await self.placeNewItems(items, controlItems: controlItems)
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

// MARK: - Moving Items Into Sections

extension MenuBarItemManager {
    /// Moves items into the sections given by their tags' descriptions, for
    /// example to apply a layout profile. Items already in their section, and
    /// items that are not on the bar, are left alone.
    func move(itemsTo sections: [String: MenuBarSection.Name]) async {
        var items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
        guard let controlItems = ControlItemPair(items: &items) else {
            logger.warning("Missing control item for hidden section, cannot move items into sections")
            return
        }
        for item in items where item.isMovable && !item.isControlItem {
            guard
                var section = sections[item.tag.description],
                itemCache.address(for: item.tag)?.section != section
            else {
                continue
            }
            if section == .alwaysHidden && controlItems.alwaysHidden == nil {
                section = .hidden
            }
            let destination: MoveDestination = switch section {
            case .visible: .rightOfItem(controlItems.hidden)
            case .hidden: .leftOfItem(controlItems.hidden)
            case .alwaysHidden: .leftOfItem(controlItems.alwaysHidden ?? controlItems.hidden)
            }
            do {
                try await move(item: item, to: destination)
            } catch {
                logger.error("Error moving \(item.logString, privacy: .private(mask: .hash)) into \(section.logString, privacy: .public): \(error, privacy: .private)")
            }
        }
        await cacheItemsRegardless()
    }
}

// MARK: - Placing New Items

extension MenuBarItemManager {
    /// Moves menu bar items that holzBar has not seen before into the section
    /// chosen in the settings (jordanbaird/Ice#6, jordanbaird/Ice#767,
    /// jordanbaird/Ice#378).
    ///
    /// macOS puts a new item at the far left of the bar, which is wherever the
    /// leftmost section happens to be. holzBar remembers every item it has seen,
    /// so only items that are new to it are moved, and the first run only records
    /// what is there. Items whose identity changes on every launch are left alone,
    /// as they would be new every time.
    private func placeNewItems(_ items: [MenuBarItem], controlItems: ControlItemPair) async {
        guard let appState else {
            return
        }

        if appState.settings.advanced.keepLiveActivitiesVisible {
            await keepLiveActivitiesVisible(items, controlItems: controlItems)
        }

        let candidates = items.filter { item in
            item.isMovable &&
            item.canBeHidden &&
            !item.isControlItem &&
            !item.isSystemClone &&
            !item.tag.namespace.isUUID
        }
        let stored = Defaults.array(forKey: .knownItemTags) as? [String]
        var known = Set(stored ?? [])
        let newItems = candidates.filter { !known.contains($0.tag.description) }

        guard stored == nil || !newItems.isEmpty else {
            return
        }
        known.formUnion(candidates.map(\.tag.description))
        Defaults.set(known.sorted(), forKey: .knownItemTags)

        guard
            stored != nil,
            var section = appState.settings.advanced.newItemsPlacement.section
        else {
            return
        }
        if section == .alwaysHidden && controlItems.alwaysHidden == nil {
            section = .hidden
        }

        for item in newItems where itemCache.address(for: item.tag)?.section != section {
            let destination: MoveDestination = switch section {
            case .visible: .rightOfItem(controlItems.hidden)
            case .hidden: .leftOfItem(controlItems.hidden)
            case .alwaysHidden: .leftOfItem(controlItems.alwaysHidden ?? controlItems.hidden)
            }
            do {
                logger.info("Placing new item \(item.logString, privacy: .private(mask: .hash)) in \(section.logString, privacy: .public)")
                try await move(item: item, to: destination)
            } catch {
                logger.error("Error placing new item \(item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
            }
        }
    }
}

extension MenuBarItemManager {
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
                    logger.info("Keeping Live Activity \(item.logString, privacy: .private(mask: .hash)) visible")
                    try await move(item: item, to: .rightOfItem(controlItems.hidden))
                } catch {
                    logger.error("Error moving Live Activity \(item.logString, privacy: .private(mask: .hash)): \(error, privacy: .private)")
                }
            } else if item.tag.namespace.isUUID || item.tag.namespace.description.hasPrefix("com.apple.") {
                // Helps find the process that draws Live Activities.
                logger.debug("Hidden system item: \(item.tag.description, privacy: .private(mask: .hash))")
            }
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
            }
        }

        var errorDescription: String? {
            switch self {
            case .cannotComplete:
                "Operation could not be completed"
            case .invalidEventSource:
                "Invalid event source"
            case .missingMouseLocation:
                "Missing mouse location"
            case .eventCreationFailure(let item):
                "Could not create event for \"\(item.displayName)\""
            case .eventOperationTimeout(let item):
                "Event operation timed out for \"\(item.displayName)\""
            case .itemNotMovable(let item):
                "\"\(item.displayName)\" is not movable"
            case .itemResponseTimeout(let item):
                "\"\(item.displayName)\" took too long to respond"
            case .missingItemBounds(let item):
                "Missing bounds rectangle for \"\(item.displayName)\""
            }
        }

        var recoverySuggestion: String? {
            if case .itemNotMovable = self { return nil }
            return "Please try again. If the error persists, please file a bug report."
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

    /// Moves a menu bar item to the given destination.
    ///
    /// - Parameters:
    ///   - item: The menu bar item to move.
    ///   - destination: The destination to move the item to.
    func move(item: MenuBarItem, to destination: MoveDestination) async throws {
        guard item.isMovable else {
            throw EventError.itemNotMovable(item)
        }
        guard let appState else {
            throw EventError.cannotComplete
        }
        try await backend.move(item: item, to: destination, appState: appState)
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

        /// The destination to return the item to.
        let returnDestination: MoveDestination

        /// The window of the item's shown interface.
        var shownInterfaceWindow: WindowInfo?

        /// The number of attempts that have been made to rehide the item.
        var rehideAttempts = 0

        /// A Boolean value that indicates whether the menu bar item's
        /// interface is showing.
        var isShowingInterface: Bool {
            guard
                let window = shownInterfaceWindow,
                let current = WindowInfo(windowID: window.windowID)
            else {
                // Window no longer exists, so assume closed.
                return false
            }
            if
                current.layer != CGWindowLevelForKey(.popUpMenuWindow),
                current.layer != CGWindowLevelForKey(.popUpMenuWindow) - 1,
                current.layer != CGWindowLevelForKey(.statusWindow),
                current.layer != CGWindowLevelForKey(.mainMenuWindow),
                let app = current.owningApplication
            {
                return app.isActive && current.isOnScreen
            }
            return current.isOnScreen
        }

        init(tag: MenuBarItemTag, returnDestination: MoveDestination) {
            self.tag = tag
            self.returnDestination = returnDestination
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
            alert.messageText = "Not enough room to show \"\(item.displayName)\""
            alert.runModal()
            return
        }

        appState.hidEventManager.stopAll()
        defer {
            appState.hidEventManager.startAll()
        }

        logger.debug("Temporarily showing \(item.logString, privacy: .private(mask: .hash))")

        do {
            try await move(item: item, to: .leftOfItem(targetItem))
        } catch {
            logger.error("Error showing item: \(error, privacy: .private)")
            return
        }

        let context = TemporarilyShownItemContext(tag: item.tag, returnDestination: destination)
        temporarilyShownItemContexts.append(context)

        rehideTimer?.invalidate()
        defer {
            runRehideTimer()
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
            window.ownerPID == item.sourcePID && !idsBeforeClick.contains(window.windowID)
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
        guard !temporarilyShownItemContexts.contains(where: { $0.isShowingInterface }) else {
            logger.debug("Menu bar item interface is shown, so waiting to rehide")
            runRehideTimer(for: 3)
            return
        }
        guard MenuBarItemEventPoster.hasUserPausedInput(for: .milliseconds(250)) else {
            logger.debug("Found recent user input, so waiting to rehide")
            runRehideTimer(for: 1)
            return
        }

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

        while let context = currentContexts.popLast() {
            guard let item = items.first(matching: context.tag) else {
                continue
            }
            do {
                try await move(item: item, to: context.returnDestination)
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
            runRehideTimer(for: 3)
        }
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

// MARK: - Logger Helpers

nonisolated private extension Logger {
    /// Logger for the menu bar item manager.
    static let menuBarItemManager = Logger(category: "MenuBarItemManager")
}
