//
//  MenuBarItemImageCache.swift
//  holzBar
//

import Cocoa
import Observation
import OSLog

/// Cache for menu bar item images.
@MainActor
@Observable
final class MenuBarItemImageCache {
    /// A representation of a captured menu bar item image.
    nonisolated struct CapturedImage: Hashable {
        /// The base image.
        let cgImage: CGImage

        /// The scale factor of the image at the time of capture.
        let scale: CGFloat

        /// The image's size, applying ``scale``.
        var scaledSize: CGSize {
            CGSize(
                width: CGFloat(cgImage.width) / scale,
                height: CGFloat(cgImage.height) / scale
            )
        }

        /// The base image, converted to an `NSImage` and applying ``scale``.
        var nsImage: NSImage {
            NSImage(cgImage: cgImage, size: scaledSize)
        }
    }

    /// The result of an image capture operation.
    ///
    /// Unchecked so it can be returned from the capture queue below: `CGImage` is
    /// not marked Sendable, but the images it holds are immutable once captured.
    nonisolated private struct CaptureResult: @unchecked Sendable {
        /// The successfully captured images.
        var images = [MenuBarItemTag: CapturedImage]()

        /// The menu bar items excluded from the capture.
        var excluded = [MenuBarItem]()

        /// The items a single capture skipped because they are not entirely on one display.
        var offScreen = [MenuBarItem]()
    }

    /// The queue the blocking window-server capture calls run on.
    ///
    /// Capturing a window is a synchronous call that can block indefinitely: on
    /// macOS 26 the per-window path is proxied through ScreenCaptureKit, and a
    /// capture of an item that is off the edge of the menu bar never returns.
    ///
    /// Running those calls on the Swift concurrency pool is what froze the app.
    /// Every cooperative thread ended up parked inside one — a sample showed all
    /// ten of them in `SLSWindowListCreateImageFromArrayProxying` — so no further
    /// task could be scheduled, while the main thread sat idle in its run loop.
    /// The app looked hung but was merely unable to run any work.
    ///
    /// Wrapping the call in `Task.withTimeout` does not help, and did not: the
    /// task is abandoned, but the thread it left behind stays blocked forever.
    /// The only remedy is to keep these calls off the cooperative pool entirely.
    /// The queue is serial, so a stuck capture costs one thread rather than one
    /// per item.
    ///
    /// A stuck capture used to block every later one behind it until relaunch (F-13).
    /// Each call is now given up after ``ItemCapturePolicy/timeout``: the queue whose
    /// call did not return is abandoned with its thread, and later calls go to a fresh
    /// queue. After ``ItemCapturePolicy/maxAbandonedQueues`` calls that are still stuck,
    /// capture stops for the session; a call that returns late gives its queue back.
    @ObservationIgnored private var captureQueue = makeCaptureQueue()

    /// Tracks the capture calls that did not return in time.
    @ObservationIgnored private var watchdog = ItemCapturePolicy.Watchdog()

    /// Runs one capture pass at a time.
    @ObservationIgnored private let captureRun = CoalescedRun<MenuBarSection.Name>()

    /// Whether item image capture has stopped until holzBar is relaunched.
    private var isCaptureStopped: Bool {
        watchdog.isStopped
    }

    /// Returns a new queue for the blocking capture calls.
    private nonisolated static func makeCaptureQueue() -> DispatchQueue {
        DispatchQueue(label: "com.holzcloud.holzBar.ImageCapture", qos: .userInitiated)
    }

    /// Runs a blocking capture off the Swift concurrency pool, and gives it up after
    /// ``ItemCapturePolicy/timeout``.
    ///
    /// - Parameter windowID: The window of a single capture, or `nil` for a composite one.
    /// - Returns: The result, or `nil` when the capture was given up or capture has
    ///   stopped; then there are no new images, and the cached ones stay.
    private func onCaptureQueue(
        windowID: CGWindowID? = nil,
        _ work: @escaping @Sendable () -> CaptureResult
    ) async -> CaptureResult? {
        guard !isCaptureStopped else {
            return nil
        }
        let queue = captureQueue
        let hangs = Defaults.bool(forKey: .debugHangsItemImageCapture)
        let result = await BlockingWork.run(on: queue, timeout: ItemCapturePolicy.timeout, fallback: CaptureResult?.none) {
            if hangs {
                // Debug only: simulates a capture that never returns.
                DispatchSemaphore(value: 0).wait()
            }
            return work()
        }
        guard !result.timedOut else {
            captureDidTimeOut(on: queue, windowID: windowID)
            return nil
        }
        return result.value
    }

    /// Abandons the given queue after one of its capture calls did not return in time.
    private func captureDidTimeOut(on queue: DispatchQueue, windowID: CGWindowID?) {
        // The queue is serial, so this runs only after the stuck call, if it ever returns:
        // it shows whether a call that was given up was stuck for good or only slow. A
        // slow call blocks no thread any more, so its queue no longer counts toward the stop.
        let logger = logger
        let abandonedAt = ContinuousClock.now
        queue.async { [weak self] in
            let late = abandonedAt.duration(to: .now) + ItemCapturePolicy.timeout
            let seconds = Double(late.components.seconds) + Double(late.components.attoseconds) / 1e18
            logger.notice("An abandoned item image capture returned after \(seconds, format: .fixed(precision: 1), privacy: .public) s")
            Task { @MainActor in
                self?.watchdog.recordLateReturn()
            }
        }

        guard !isCaptureStopped else {
            return
        }
        switch watchdog.recordTimeout(windowID: windowID) {
        case .replaceQueue:
            captureQueue = Self.makeCaptureQueue()
            logger.warning(
                """
                Item image capture did not return within 2 s; later captures use a new queue \
                (\(self.watchdog.abandonedQueues, privacy: .public) of \(ItemCapturePolicy.maxAbandonedQueues, privacy: .public) abandoned)
                """
            )
        case .stop:
            // Nothing could refresh any more.
            refreshTask?.cancel()
            refreshTask = nil
            logger.error(
                """
                Item image capture stopped until holzBar is relaunched: \
                \(ItemCapturePolicy.maxAbandonedQueues, privacy: .public) captures did not return; the last images stay
                """
            )
        }
    }

    /// The cached item images, keyed by their corresponding tags.
    private(set) var images = [MenuBarItemTag: CapturedImage]()

    /// Logger for the menu bar item image cache.
    private let logger = Logger(category: "MenuBarItemImageCache")

    /// Image capture options.
    private let captureOption: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    /// Observers of the views that show images and of the item list.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// Tasks that observe the space and the screens.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Releases the images a minute after the last view showing them closed.
    @ObservationIgnored private var releaseTask: Task<Void, Never>?

    /// Refreshes the images every 3 seconds while a view in front shows them.
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Updates the cache at most every 0.5 s; the first request of a burst runs at once
    /// (Combine's `throttle(for:latest: false)`).
    @ObservationIgnored private let updateThrottle = Debouncer(delay: .milliseconds(500))

    // MARK: Setup

    /// Sets up the cache.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
    }

    /// Configures the internal observers for the cache.
    private func configureObservers() {
        guard let appState else {
            return
        }
        let navigationState = appState.navigationState
        // Whether the Shelf, the search panel or a group panel is shown.
        let isPanelShown: @MainActor @Sendable () -> Bool = {
            navigationState.isShelfPresented || navigationState.isSearchPresented || navigationState.isItemGroupPanelPresented
        }
        // Whether the Settings window shows the layout pane (frontmost or not).
        let isLayoutPaneShown: @MainActor @Sendable () -> Bool = {
            navigationState.isSettingsPresented && navigationState.settingsNavigationIdentifier == .menuBarLayout
        }

        // Releases every image a minute after the last view showing them closed;
        // opening one again cancels it (and captures the images anew).
        observers.append(
            ObservationLoop.observe { isPanelShown() || isLayoutPaneShown() } onChange: { [weak self] isShowing in
                self?.showingImagesDidChange(isShowing)
            }
        )
        showingImagesDidChange(isPanelShown() || isLayoutPaneShown())

        // The periodic refresh runs only while such a view is in front (the layout
        // pane only while holzBar is frontmost, as `updateCache()` checks), so it does
        // not wake holzBar at idle.
        let isRefreshNeeded: @MainActor @Sendable () -> Bool = {
            isPanelShown() || (isLayoutPaneShown() && navigationState.isAppFrontmost)
        }
        observers.append(
            ObservationLoop.observe(isRefreshNeeded) { [weak self] isNeeded in
                self?.refreshNeededDidChange(isNeeded)
            }
        )
        refreshNeededDidChange(isRefreshNeeded())

        // Update when the active space or screen parameters change.
        let notifications: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
        ]
        observerTasks = notifications.map { center, name in
            Task { [weak self] in
                for await _ in center.notifications(named: name) {
                    self?.requestUpdate()
                }
            }
        }

        // Update when the average menu bar color or cached items change.
        let menuBarManager = appState.menuBarManager
        let itemManager = appState.itemManager
        observers.append(
            ObservationLoop.observe { menuBarManager.averageColorInfo } onChange: { [weak self] _ in
                self?.requestUpdate()
            }
        )
        observers.append(
            ObservationLoop.observe { itemManager.itemCache } onChange: { [weak self] _ in
                self?.requestUpdate()
            }
        )
        requestUpdate()
    }

    /// Schedules or cancels the release of the images as views showing them open and close.
    private func showingImagesDidChange(_ isShowing: Bool) {
        releaseTask?.cancel()
        releaseTask = nil
        guard !isShowing else {
            return
        }
        releaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
            self?.releaseAllImages()
        }
    }

    /// Starts or stops the 3 s refresh.
    private func refreshNeededDidChange(_ isNeeded: Bool) {
        refreshTask?.cancel()
        refreshTask = nil
        // Once capture has stopped, a refresh could do nothing.
        guard isNeeded, !isCaptureStopped else {
            return
        }
        refreshTask = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(3), tolerance: .milliseconds(500))
                } catch {
                    return
                }
                self?.requestUpdate()
            }
        }
    }

    /// Updates the cache, at most every 0.5 s.
    private func requestUpdate() {
        updateThrottle.throttle { [weak self] in
            Task {
                await self?.updateCache()
            }
        }
    }

    // MARK: Capturing Images

    /// Captures a composite image of the given items, then crops out an image
    /// for each item and returns the result.
    private nonisolated func compositeCapture(_ items: [MenuBarItem], scale: CGFloat) -> CaptureResult {
        var result = CaptureResult()

        var windowIDs = [CGWindowID]()
        var storage = [CGWindowID: (MenuBarItem, CGRect)]()
        var boundsUnion = CGRect.null

        for item in items {
            let windowID = item.windowID

            // Don't use `item.bounds`, it could be out of date.
            guard let bounds = Bridging.getWindowBounds(for: windowID) else {
                result.excluded.append(item)
                continue
            }

            windowIDs.append(windowID)
            storage[windowID] = (item, bounds)
            boundsUnion = boundsUnion.union(bounds)
        }

        guard
            let compositeImage = ScreenCapture.captureWindows(with: windowIDs, option: captureOption),
            !compositeImage.isTransparent(),
            boundsUnion.width > 0
        else {
            result.excluded = items // Exclude all items.
            return result
        }

        // Derive the scale from the capture rather than trusting the one passed in.
        //
        // The caller's scale comes from whichever display the item cache last
        // recorded, and that briefly disagrees with reality when the active menu
        // bar moves between displays of different densities: the pixels are the
        // new display's, the recorded scale is still the old one's.
        //
        // This used to be an exact equality check — `compositeImage.width ==
        // boundsUnion.width * scale` — which failed on that disagreement and
        // excluded *every* item, sending them all into the individual capture path
        // that blocks. So the same mismatch produced both symptoms: items drawn at
        // twice or half their size, and the freeze. Deriving the scale removes the
        // disagreement instead of detecting it.
        let actualScale = CGFloat(compositeImage.width) / boundsUnion.width
        guard actualScale >= 0.5, actualScale <= 4 else {
            logger.warning("Implausible capture scale \(actualScale, privacy: .public); excluding items")
            result.excluded = items
            return result
        }

        // Crop out each item from the composite.
        for windowID in windowIDs {
            guard let (item, bounds) = storage[windowID] else {
                continue
            }

            let cropRect = CGRect(
                x: (bounds.origin.x - boundsUnion.origin.x) * actualScale,
                y: (bounds.origin.y - boundsUnion.origin.y) * actualScale,
                width: bounds.width * actualScale,
                height: bounds.height * actualScale
            )

            guard
                let image = compositeImage.cropping(to: cropRect),
                !image.isTransparent()
            else {
                result.excluded.append(item)
                continue
            }

            result.images[item.tag] = CapturedImage(cgImage: image, scale: actualScale)
        }

        return result
    }

    /// Captures an image of the given item on its own and returns the result.
    ///
    /// A single capture of an item that is not entirely on one display can block forever
    /// on macOS 26 (see ``captureQueue``), so such an item is skipped and returned in
    /// ``CaptureResult/offScreen``. Hidden items sit off screen, left of the menu bar,
    /// while their section is hidden.
    private nonisolated func individualCapture(_ item: MenuBarItem, displays: [CGRect], scale: CGFloat) -> CaptureResult {
        var result = CaptureResult()

        // Live bounds, not `item.bounds`: the cached ones can name the display
        // the item was on a moment ago.
        guard
            let bounds = Bridging.getWindowBounds(for: item.windowID),
            bounds.width > 0
        else {
            result.excluded.append(item)
            return result
        }
        guard ItemCapturePolicy.isOnScreen(bounds, displays: displays) else {
            result.offScreen.append(item)
            return result
        }
        guard
            let image = ScreenCapture.captureWindow(with: item.windowID, option: captureOption),
            !image.isTransparent()
        else {
            result.excluded.append(item)
            return result
        }
        // Derived, for the same reason as in the composite path above.
        let actualScale = CGFloat(image.width) / bounds.width
        result.images[item.tag] = CapturedImage(
            cgImage: image,
            scale: (actualScale >= 0.5 && actualScale <= 4) ? actualScale : scale
        )
        return result
    }

    /// Captures an image of each of the given items individually, each call bounded on its
    /// own, then returns the result.
    private func captureIndividually(_ items: [MenuBarItem], scale: CGFloat) async -> CaptureResult {
        let displays = Bridging.getActiveDisplayList().map(CGDisplayBounds)
        var result = CaptureResult()

        for item in items {
            let itemResult = await onCaptureQueue(windowID: item.windowID) { [self] in
                individualCapture(item, displays: displays, scale: scale)
            }
            guard let itemResult else {
                result.excluded.append(item)
                if isCaptureStopped {
                    break
                }
                continue
            }
            result.images.merge(itemResult.images) { (_, new) in new }
            result.excluded += itemResult.excluded
            result.offScreen += itemResult.offScreen
        }

        let keptCount = result.offScreen.filter { images[$0.tag] != nil }.count
        if keptCount > 0 {
            logger.debug("Kept the cached images of \(keptCount, privacy: .public) items off screen")
        }
        return result
    }

    /// Takes the images of the off-screen items in the given result that have no cached
    /// image from one composite capture; the others keep their cached images.
    private func captureMissingOffScreen(in result: CaptureResult, scale: CGFloat) async -> CaptureResult {
        let missing = result.offScreen.filter { images[$0.tag] == nil }
        guard !missing.isEmpty else {
            return result
        }

        // All off-screen items of the batch, shaped like the regular composite capture,
        // which captures the hidden items whenever the Shelf opens.
        let offScreen = result.offScreen
        let compositeResult = await onCaptureQueue { [self] in compositeCapture(offScreen, scale: scale) }

        var result = result
        for item in missing {
            if let image = compositeResult?.images[item.tag] {
                result.images[item.tag] = image
            } else {
                result.excluded.append(item)
            }
        }
        return result
    }

    /// Captures the images of the given menu bar items and returns the result.
    private func captureImages(of items: [MenuBarItem], scale: CGFloat, appState: AppState) async -> CaptureResult {
        // Use individual capture after a move operation, since composite capture
        // doesn't account for overlapping items.
        if appState.itemManager.lastMoveOperationOccurred(within: .seconds(2)) {
            logger.debug("Capturing individually due to recent item movement")
            let individualResult = await captureIndividually(items, scale: scale)
            return await captureMissingOffScreen(in: individualResult, scale: scale)
        }

        guard let compositeResult = await onCaptureQueue({ [self] in compositeCapture(items, scale: scale) }) else {
            return CaptureResult() // No new images; the cached ones stay.
        }

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        logger.notice(
            """
            Some items were excluded from composite capture. Attempting to capture \
            excluded items individually: \(compositeResult.excluded, privacy: .private(mask: .hash))
            """
        )

        var individualResult = await captureIndividually(compositeResult.excluded, scale: scale)

        // The composite capture just failed for the items off screen, so they are not
        // captured again. Those without a cached image count as failed, so they are logged.
        individualResult.excluded += individualResult.offScreen.filter { images[$0.tag] == nil }

        // Merge the successfully captured images from each result. Keep excluded
        // items as part of the result, so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { (_, new) in new }

        return individualResult
    }

    /// Captures the images of the menu bar items in the given section and returns
    /// a dictionary containing the images, keyed by their menu bar item tags.
    private func captureImages(for section: MenuBarSection.Name, scale: CGFloat, appState: AppState) async -> [MenuBarItemTag: CapturedImage] {
        // A window whose capture did not return is not captured again.
        let items = appState.itemManager.itemCache[section].filter { !watchdog.skips($0.windowID) }
        let captureResult = await captureImages(of: items, scale: scale, appState: appState)
        if !captureResult.excluded.isEmpty {
            logger.error("Some items failed capture: \(captureResult.excluded, privacy: .private(mask: .hash))")
        }
        return captureResult.images
    }

    // MARK: Update Cache

    /// Updates the cache for the given sections, without checking whether
    /// caching is necessary.
    func updateCacheWithoutChecks(sections: [MenuBarSection.Name]) async {
        guard
            let appState,
            appState.hasPermission(.screenRecording)
        else {
            return
        }

        // Nothing is captured while the screen is locked, the Mac sleeps or the session is
        // away; the cache is updated once the bar has settled afterwards.
        guard !appState.systemActivityMonitor.isPaused else {
            logger.debug("Skipping item image cache while the Mac is not in use")
            return
        }

        if #available(macOS 27.0, *) {
            // There are no item windows to capture on macOS 27. See `ItemImageStore27`.
            var items = [MenuBarItem]()
            for section in sections {
                items += appState.itemManager.itemCache[section]
            }
            let store = appState.itemImageStore27
            await store.captureActiveMenuBar(appState: appState)
            await store.photographMissing(items: items, appState: appState)
            var newImages = [MenuBarItemTag: CapturedImage]()
            for item in items {
                if let image = store.image(for: item) {
                    newImages[item.tag] = image
                }
            }
            let currentTags = Set(appState.itemManager.itemCache.managedItems.map(\.tag))
            images.merge(newImages) { (_, new) in new }
            prune(keeping: currentTags)
            return
        }

        guard !isCaptureStopped else {
            return
        }

        // One pass at a time: a request meanwhile joins it and adds its sections to one
        // re-run, so the capture queue never holds more than one call and no request waits
        // on a stuck one for longer than the watchdog allows (F-13).
        await captureRun.run(sections) { [weak self] batch in
            await self?.captureAndStoreImages(for: batch)
        }
    }

    /// Captures the images of the items in the given sections and stores them.
    private func captureAndStoreImages(for sections: Set<MenuBarSection.Name>) async {
        // A re-run can start after any of these changed.
        guard
            let appState,
            appState.hasPermission(.screenRecording),
            !appState.systemActivityMonitor.isPaused,
            !isCaptureStopped
        else {
            return
        }

        guard
            let displayID = appState.itemManager.itemCache.displayID,
            let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else {
            return
        }

        watchdog.forgetWindows(notIn: Set(appState.itemManager.itemCache.managedItems.map(\.windowID)))

        let scale = screen.backingScaleFactor
        var newImages = [MenuBarItemTag: CapturedImage]()

        for section in MenuBarSection.Name.allCases where sections.contains(section) {
            guard !isCaptureStopped else {
                break
            }
            guard !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }

            let sectionImages = await captureImages(for: section, scale: scale, appState: appState)

            guard !sectionImages.isEmpty else {
                // Items off screen just after a move keep their cached images; that is no failure.
                if appState.itemManager.itemCache[section].contains(where: { images[$0.tag] == nil }) {
                    logger.warning("Failed item image cache for \(section.logString, privacy: .public)")
                }
                continue
            }

            newImages.merge(sectionImages) { (_, new) in new }
        }

        let currentTags = Set(appState.itemManager.itemCache.managedItems.map(\.tag))
        images.merge(newImages) { (_, new) in new }
        prune(keeping: currentTags)
    }

    /// Drops the images of items that are no longer in the item cache.
    func prune(keeping tags: Set<MenuBarItemTag>) {
        let stale = images.keys.filter { !tags.contains($0) }
        guard !stale.isEmpty else {
            return
        }
        for tag in stale {
            images.removeValue(forKey: tag)
        }
    }

    /// Releases every cached image. Runs a minute after the last view that shows item
    /// images closed; the images are captured again when one opens.
    func releaseAllImages() {
        // Once capture has stopped, these images are all there is until relaunch.
        guard !images.isEmpty, !isCaptureStopped else {
            return
        }
        images.removeAll()
        logger.debug("Released all item images")
    }

    /// Updates the cache for the given sections, if necessary.
    func updateCache(sections: [MenuBarSection.Name]) async {
        guard let appState else {
            return
        }

        let isShelfPresented = appState.navigationState.isShelfPresented
        let isSearchPresented = appState.navigationState.isSearchPresented
        let isGroupPanelPresented = appState.navigationState.isItemGroupPanelPresented

        if !isShelfPresented && !isSearchPresented && !isGroupPanelPresented {
            guard
                appState.navigationState.isAppFrontmost,
                appState.navigationState.isSettingsPresented,
                appState.navigationState.settingsNavigationIdentifier == .menuBarLayout
            else {
                return
            }
        }

        guard !appState.itemManager.lastMoveOperationOccurred(within: .seconds(1)) else {
            logger.debug("Skipping item image cache due to recent item movement")
            return
        }

        await updateCacheWithoutChecks(sections: sections)
    }

    /// Updates the cache for all sections, if necessary.
    func updateCache() async {
        guard let appState else {
            return
        }

        let isShelfPresented = appState.navigationState.isShelfPresented
        let isSearchPresented = appState.navigationState.isSearchPresented
        let isSettingsPresented = appState.navigationState.isSettingsPresented

        var sectionsNeedingDisplay = [MenuBarSection.Name]()

        if isSettingsPresented || isSearchPresented {
            sectionsNeedingDisplay = MenuBarSection.Name.allCases
        } else if
            isShelfPresented,
            let section = appState.menuBarManager.shelfPanel.currentSection
        {
            sectionsNeedingDisplay.append(section)
            // Items covered by the notch are shown along with the hidden section.
            if section == .hidden, appState.settings.general.showsNotchOverflowInShelf {
                sectionsNeedingDisplay.append(.visible)
            }
        }

        await updateCache(sections: sectionsNeedingDisplay)
    }

    // MARK: Cache Failed

    /// Returns a Boolean value that indicates whether caching menu bar items
    /// failed for the given section.
    func cacheFailed(for section: MenuBarSection.Name) -> Bool {
        guard ScreenCapture.cachedCheckPermissions() else {
            return true
        }
        let items = appState?.itemManager.itemCache[section] ?? []
        guard !items.isEmpty else {
            return false
        }
        let keys = Set(images.keys)
        for item in items where keys.contains(item.tag) {
            return false
        }
        return true
    }
}
