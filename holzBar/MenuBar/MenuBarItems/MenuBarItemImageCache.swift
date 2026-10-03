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
    private nonisolated static let captureQueue = DispatchQueue(
        label: "com.holzcloud.holzBar.ImageCapture",
        qos: .userInitiated
    )

    /// Runs a blocking capture off the Swift concurrency pool.
    private nonisolated func onCaptureQueue(
        _ work: @escaping @Sendable () -> CaptureResult
    ) async -> CaptureResult {
        await withCheckedContinuation { continuation in
            Self.captureQueue.async {
                continuation.resume(returning: work())
            }
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
        guard isNeeded else {
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

    /// Captures an image of each of the given items individually, then
    /// returns the result.
    private nonisolated func individualCapture(_ items: [MenuBarItem], scale: CGFloat) -> CaptureResult {
        var result = CaptureResult()

        for item in items {
            // Live bounds, not `item.bounds`: the cached ones can name the display
            // the item was on a moment ago.
            guard
                let bounds = Bridging.getWindowBounds(for: item.windowID),
                bounds.width > 0,
                let image = ScreenCapture.captureWindow(with: item.windowID, option: captureOption),
                !image.isTransparent()
            else {
                result.excluded.append(item)
                continue
            }
            // Derived, for the same reason as in the composite path above.
            let actualScale = CGFloat(image.width) / bounds.width
            result.images[item.tag] = CapturedImage(
                cgImage: image,
                scale: (actualScale >= 0.5 && actualScale <= 4) ? actualScale : scale
            )
        }

        return result
    }

    /// Captures the images of the given menu bar items and returns the result.
    private func captureImages(of items: [MenuBarItem], scale: CGFloat, appState: AppState) async -> CaptureResult {
        // Use individual capture after a move operation, since composite capture
        // doesn't account for overlapping items.
        if appState.itemManager.lastMoveOperationOccurred(within: .seconds(2)) {
            logger.debug("Capturing individually due to recent item movement")
            return await onCaptureQueue { [self] in individualCapture(items, scale: scale) }
        }

        let compositeResult = await onCaptureQueue { [self] in compositeCapture(items, scale: scale) }

        if compositeResult.excluded.isEmpty {
            return compositeResult // All items captured successfully.
        }

        logger.notice(
            """
            Some items were excluded from composite capture. Attempting to capture \
            excluded items individually: \(compositeResult.excluded, privacy: .private(mask: .hash))
            """
        )

        let excluded = compositeResult.excluded
        var individualResult = await onCaptureQueue { [self] in individualCapture(excluded, scale: scale) }

        // Merge the successfully captured images from each result. Keep excluded
        // items as part of the result, so they can be logged elsewhere.
        individualResult.images.merge(compositeResult.images) { (_, new) in new }

        return individualResult
    }

    /// Captures the images of the menu bar items in the given section and returns
    /// a dictionary containing the images, keyed by their menu bar item tags.
    private func captureImages(for section: MenuBarSection.Name, scale: CGFloat, appState: AppState) async -> [MenuBarItemTag: CapturedImage] {
        let items = appState.itemManager.itemCache[section]
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

        guard
            let displayID = appState.itemManager.itemCache.displayID,
            let screen = NSScreen.screens.first(where: { $0.displayID == displayID })
        else {
            return
        }

        let scale = screen.backingScaleFactor
        var newImages = [MenuBarItemTag: CapturedImage]()

        for section in sections {
            guard !appState.itemManager.itemCache[section].isEmpty else {
                continue
            }

            let sectionImages = await captureImages(for: section, scale: scale, appState: appState)

            guard !sectionImages.isEmpty else {
                logger.warning("Failed item image cache for \(section.logString, privacy: .public)")
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
        guard !images.isEmpty else {
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
