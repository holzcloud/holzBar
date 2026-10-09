//
//  AppState.swift
//  holzBar
//

import Observation
import OSLog
import SwiftUI

/// The model for app-wide state.
@MainActor
@Observable
final class AppState {
    /// The app's state, for code macOS runs outside holzBar's views and delegate, such as
    /// the Shortcuts actions (`HolzBarIntents.swift`).
    ///
    /// SwiftUI's application delegate adaptor puts its own object in `NSApp.delegate`, so
    /// the app delegate cannot be reached from there.
    static weak var current: AppState?

    /// Information for the active space.
    private(set) var activeSpace = SpaceInfo.activeSpace()

    /// A Boolean value that indicates whether the user is dragging a menu bar item.
    var isDraggingMenuBarItem: Bool {
        hidEventManager.isDraggingMenuBarItem
    }

    /// Model for the app's settings.
    let settings = AppSettings()

    /// Model for the app's permissions.
    let permissions = AppPermissions()

    /// Model for app-wide navigation.
    let navigationState = AppNavigationState()

    /// Manager for the state of the menu bar.
    let menuBarManager = MenuBarManager()

    /// Manager for the menu bar's appearance.
    let appearanceManager = MenuBarAppearanceManager()

    /// Manager for menu bar item spacing.
    let spacingManager = MenuBarItemSpacingManager()

    /// Manager for menu bar items.
    let itemManager = MenuBarItemManager()

    /// Global cache for menu bar item images.
    let imageCache = MenuBarItemImageCache()

    /// Images of the user's choice for items, and app icons where there is no picture.
    let itemIconStore = ItemIconStore()

    /// Manager for input events received by the app.
    let hidEventManager = HIDEventManager()

    /// The frame of the application menu on each display, read off the main thread.
    let applicationMenuFrames = ApplicationMenuFrames()

    /// Whether the Mac is in use (screen lock, sleep, session) and when the bar has settled.
    let systemActivityMonitor = SystemActivityMonitor()

    /// Saved layout profiles.
    let profiles = LayoutProfiles()

    /// Keeps the settings in step with other Macs through a folder they sync; the launch built it.
    let settingsSync = SettingsSync.forAppState()

    /// Groups of menu bar items behind icons of their own.
    let itemGroups = MenuBarItemGroups()

    /// Empty menu bar items that add space between others.
    let spacers = MenuBarSpacers()

    /// Rules that show hidden items when something happens.
    let revealRules = RevealRules()

    /// Turns Zen mode on while the screen is mirrored or shared.
    let presentationMonitor = PresentationMonitor()

    /// Shows the items marked "Show When It Changes" for a moment when they change.
    let itemChangeWatcher = ItemChangeWatcher()

    /// The action that opens holzBar's windows, handed over by its scenes.
    @ObservationIgnored private var openWindowAction: OpenWindowAction?

    /// The action that dismisses holzBar's windows, handed over by its scenes.
    @ObservationIgnored private var dismissWindowAction: DismissWindowAction?

    /// Window requests made before the scenes handed over their actions, in order.
    @ObservationIgnored private var pendingWindowRequests: [(id: HolzBarWindowIdentifier, opens: Bool)] = []

    /// Storage for ``concealer27``, typed loosely so the property exists on every macOS.
    @ObservationIgnored private var concealer27Storage: AnyObject?

    /// Hides menu bar items on macOS 27.
    @available(macOS 27.0, *)
    var concealer27: Concealer27 {
        if let concealer = concealer27Storage as? Concealer27 {
            return concealer
        }
        let concealer = Concealer27()
        concealer27Storage = concealer
        return concealer
    }

    /// Storage for ``captureActivityMonitor27``, typed loosely so the property exists on every macOS.
    @ObservationIgnored private var captureActivityMonitor27Storage: AnyObject?

    /// Follows whether another app uses the microphone or a camera on macOS 27.
    @available(macOS 27.0, *)
    var captureActivityMonitor27: CaptureActivityMonitor27 {
        if let monitor = captureActivityMonitor27Storage as? CaptureActivityMonitor27 {
            return monitor
        }
        let monitor = CaptureActivityMonitor27()
        captureActivityMonitor27Storage = monitor
        return monitor
    }

    /// What holzBar's icon shows while another app records on macOS 27, where Control Centre's
    /// indicator is not drawn while holzBar hides items.
    ///
    /// Reads only observed state and has no early return, so an observation started before the
    /// monitor's setup still follows every input. Follows concealment through the suspensions
    /// of a bridged click, so the badge and the icon carrying it stay while a system item opens.
    @available(macOS 27.0, *)
    var captureBadge27: CaptureBadge? {
        let activity = captureActivityMonitor27.activity
        return CaptureIndicator.badge(
            isEnabled: settings.general.holzBarIconShowsCaptureDot,
            isConcealing: concealer27.concealsThroughSuspensions,
            isMicrophoneInUse: activity.isMicrophoneInUse,
            isCameraInUse: activity.isCameraInUse
        )
    }

    /// Storage for ``itemImageStore27``, typed loosely so the property exists on every macOS.
    @ObservationIgnored private var itemImageStore27Storage: AnyObject?

    /// Images of menu bar items on macOS 27.
    @available(macOS 27.0, *)
    var itemImageStore27: ItemImageStore27 {
        if let store = itemImageStore27Storage as? ItemImageStore27 {
            return store
        }
        let store = ItemImageStore27()
        itemImageStore27Storage = store
        return store
    }

    /// Observers of other models, kept for the app's lifetime.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// Tasks that observe notifications, kept for the app's lifetime.
    @ObservationIgnored private var observerTasks = [Task<Void, Never>]()

    /// Key-value observers, kept for the app's lifetime.
    @ObservationIgnored private var keyValueObservations = [NSKeyValueObservation]()

    /// The click monitor for the active space, while it is needed.
    @ObservationIgnored private var spaceClickMonitor: EventMonitor?

    /// Logger for the app state.
    @ObservationIgnored private let logger = Logger(category: "AppState")

    /// Whether the setup finished: before, the settings and items are not loaded yet.
    @ObservationIgnored private(set) var isSetUp = false

    /// Whether the setup was started: before, also after the permissions were granted
    /// until the user continues, the stored settings are not loaded.
    @ObservationIgnored private var hasStartedSetup = false

    /// Async setup actions, run once on first access.
    @ObservationIgnored private lazy var setupTask = Task { @MainActor in
        permissions.stopAllChecks()

        settings.performSetup(with: self)
        systemActivityMonitor.performSetup()
        applicationMenuFrames.performSetup()
        menuBarManager.performSetup(with: self)

        // The source-PID cache on macOS 26, the synthetic bounds on macOS 27.
        await MenuBarBackends.current.performSetup()

        appearanceManager.performSetup(with: self)
        hidEventManager.performSetup(with: self)
        if #available(macOS 27.0, *) {
            // Hiding does not need the item cache, and the first read of the items can
            // take seconds (measured 9 s), so it starts before the item manager's setup.
            concealer27.performSetup(with: self)
        }
        await itemManager.performSetup(with: self)
        imageCache.performSetup(with: self)
        itemIconStore.performSetup(with: self)
        profiles.performSetup(with: self)
        settingsSync.performSetup(with: self)
        itemGroups.performSetup(with: self)
        spacers.performSetup()
        revealRules.performSetup(with: self)
        presentationMonitor.performSetup(with: self)
        if #available(macOS 27.0, *) {
            // The dot on holzBar's icon while another app records.
            captureActivityMonitor27.performSetup(with: self)
        }
        itemChangeWatcher.performSetup(with: self)

        configureObservers()
        isSetUp = true
    }

    /// Brings holzBar up to date once the bar has settled after the screen was locked, the
    /// Mac slept, the session was away or the displays changed: the input monitors are
    /// checked, the items read again, the images refreshed where a view shows them, the
    /// concealment of macOS 27 applied and the menu bar appearance restored.
    private func systemActivityDidSettle() {
        hidEventManager.healthCheck()
        if #available(macOS 27.0, *) {
            concealer27.update()
        }
        appearanceManager.systemActivityDidSettle()
        Task {
            await itemManager.cacheItemsRegardless()
            // Items that macOS put elsewhere while the displays changed go back.
            await itemManager.reconcileSections(trigger: .settle)
            await itemManager.retryPausedRehide()
            await imageCache.updateCache()
        }
    }

    /// Performs app state setup.
    ///
    /// - Parameter hasPermissions: If `true`, continues with setup normally.
    ///   If `false`, prompts the user to grant permissions.
    func performSetup(hasPermissions: Bool) {
        if hasPermissions {
            hasStartedSetup = true
            Task {
                logger.debug("Setting up app state")
                await setupTask.value
                logger.debug("Finished setting up app state")
            }
        } else {
            Task {
                // Delay to prevent conflicts with the app delegate.
                try? await Task.sleep(for: .milliseconds(100))
                activate(for: .permissions)
                dismissWindow(.settings) // Shouldn't be open anyway.
                openWindow(.permissions)
            }
        }
    }

    /// Opens the permissions window instead of Settings until the setup starts, while
    /// permissions are missing or granted but the user has not continued yet: the setup,
    /// which loads the stored settings and registers the hotkeys, has not run then, so
    /// Settings would show the defaults and write them.
    ///
    /// - Returns: Whether the permissions window opens instead.
    func openPermissionsWindowIfNeeded() -> Bool {
        guard !hasStartedSetup else {
            return false
        }
        activate(for: .permissions)
        openWindow(.permissions)
        return true
    }

    /// Configures the internal observers for the app state.
    private func configureObservers() {
        // Brings holzBar up to date once the bar has settled after the Mac was not in use.
        systemActivityMonitor.onSettled { [weak self] in
            self?.systemActivityDidSettle()
        }

        // Listen for changes to the active space. We need handle some special
        // cases that NSWorkspace.shared.notificationCenter seems to miss.
        //
        // Special cases:
        //
        // * Changes to the frontmost application -- may indicate that a space
        //   on another display was made active.
        // * Left mouse down -- user may have clicked into a fullscreen space.
        //   To account for variations in system timing, the space is read
        //   immediately upon receipt of the event, then again after a delay.
        //
        // The click monitor wakes holzBar on every click in the system and reads
        // the active space twice, so it runs only where a click can change the
        // space without a notification: in a fullscreen space or with more than
        // one display (`InputMonitors.needsSpaceClickMonitor`). It is re-evaluated
        // when the active space or the screens change.
        observerTasks.append(Task { [weak self] in
            let center = NSWorkspace.shared.notificationCenter
            for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                self?.updateActiveSpace()
            }
        })
        observerTasks.append(Task { [weak self] in
            let center = NotificationCenter.default
            for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                self?.updateSpaceClickMonitor()
            }
        })
        keyValueObservations.append(
            NSWorkspace.shared.observe(\.frontmostApplication, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.frontmostApplicationDidChange()
                }
            }
        )
        updateSpaceClickMonitor()

        // No capture of every section at launch: images are taken when a view that
        // shows them opens (Settings here; the Shelf, search and groups on their own).
        // Combine throttled this by 0.1 s; the loop already reports a burst of changes
        // once, with the last value.
        observers.append(
            ObservationLoop.observe { [navigationState] in
                navigationState.isAppFrontmost && navigationState.isSettingsPresented
            } onChange: { [weak self] shouldUpdate in
                guard let self, shouldUpdate else {
                    return
                }
                Task {
                    await self.imageCache.updateCacheWithoutChecks(sections: MenuBarSection.Name.allCases)
                }
            }
        )
    }

    /// Reads the active space and stores it if it changed.
    private func updateActiveSpace() {
        let spaceID = Bridging.getActiveSpaceID()
        guard spaceID != activeSpace.spaceID else {
            return
        }
        activeSpace = SpaceInfo(spaceID: spaceID)
        updateSpaceClickMonitor()
    }

    /// Records whether holzBar is frontmost and reads the active space again.
    private func frontmostApplicationDidChange() {
        let isFrontmost = NSWorkspace.shared.frontmostApplication == .current
        if navigationState.isAppFrontmost != isFrontmost {
            navigationState.isAppFrontmost = isFrontmost
        }
        updateActiveSpace()
    }

    /// Runs the click monitor for the active space only while it is needed.
    private func updateSpaceClickMonitor() {
        let isNeeded = InputMonitors.needsSpaceClickMonitor(
            isFullscreenSpace: activeSpace.isFullscreen,
            screenCount: NSScreen.screens.count
        )
        if isNeeded, spaceClickMonitor == nil {
            let monitor = EventMonitor.passive(for: .leftMouseDown, scope: .universal) { [weak self] _ in
                self?.updateActiveSpace()
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(100))
                    self?.updateActiveSpace()
                }
            }
            monitor.start()
            spaceClickMonitor = monitor
        } else if !isNeeded, let monitor = spaceClickMonitor {
            monitor.stop()
            spaceClickMonitor = nil
        }
    }

    /// Returns a Boolean value indicating whether the app has been
    /// granted the permission associated with the given key.
    func hasPermission(_ key: AppPermissions.PermissionKey) -> Bool {
        switch key {
        case .accessibility:
            permissions.accessibility.hasPermission
        case .screenRecording:
            permissions.screenRecording.hasPermission
        }
    }

    /// Stores the window actions of holzBar's scenes.
    ///
    /// Every scene hands over its environment's actions when it first appears. The first
    /// call also performs, in order, the window requests made before any scene existed;
    /// later calls only refresh the actions.
    func setWindowActions(open: OpenWindowAction, dismiss: DismissWindowAction) {
        openWindowAction = open
        dismissWindowAction = dismiss
        let requests = pendingWindowRequests
        pendingWindowRequests.removeAll()
        for request in requests {
            if request.opens {
                openWindow(request.id)
            } else {
                dismissWindow(request.id)
            }
        }
    }

    /// Opens the window with the given identifier.
    func openWindow(_ id: HolzBarWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        Task {
            guard let action = self.openWindowAction else {
                self.pendingWindowRequests.append((id: id, opens: true))
                return
            }
            self.logger.debug("Opening window with id: \(id, privacy: .public)")
            action(id: id)
        }
    }

    /// Dismisses the window with the given identifier.
    func dismissWindow(_ id: HolzBarWindowIdentifier) {
        // Async prevents conflicts with SwiftUI.
        Task {
            guard let action = self.dismissWindowAction else {
                self.pendingWindowRequests.append((id: id, opens: false))
                return
            }
            self.logger.debug("Dismissing window with id: \(id, privacy: .public)")
            action(id: id)
        }
    }

    /// Activates the app for the given reason, with or without a Dock icon as
    /// `DockIconPolicy` decides.
    ///
    /// - Returns: `false` when the app does not come to the front for this reason (hiding
    ///   application menus while "Keep the Dock icon hidden" is on).
    @discardableResult
    func activate(for reason: DockIconPolicy.ActivationReason) -> Bool {
        guard let choice = DockIconPolicy.policy(for: reason, keepsDockIconHidden: settings.advanced.keepsDockIconHidden) else {
            return false
        }
        switch choice {
        case .regular:
            activate(withPolicy: .regular)
        case .accessory:
            activate(withPolicy: .accessory)
            // Without the regular policy, macOS shows the other app's menus again.
            menuBarManager.applicationMenusDidReappear()
        }
        return true
    }

    /// Activates the app and sets its activation policy.
    private func activate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        // NSApplication.activate(ignoringOtherApps:) is deprecated, with
        // no suitable alternative for explicit activation, so we activate
        // through NSRunningApplication.current for now.
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            NSRunningApplication.current.activate()
            return
        }
        NSRunningApplication.current.activate(from: frontmost)
    }

    /// Takes the Dock icon away again when nothing needs it: the permissions window, which
    /// shows one so that a fresh install can be found, can close without "Continue" (its
    /// close button, or after System Settings came to the front), and holzBar then kept the
    /// icon until it quit. Hiding the application menus needs the icon, so it stays then.
    func hideDockIconIfUnneeded() {
        guard NSApp.activationPolicy() != .accessory, !menuBarManager.isHidingApplicationMenus else {
            return
        }
        logger.debug("Hiding the Dock icon")
        NSApp.setActivationPolicy(.accessory)
    }

    /// Deactivates the app and sets its activation policy.
    func deactivate(withPolicy policy: NSApplication.ActivationPolicy? = nil) {
        if let policy {
            NSApp.setActivationPolicy(policy)
        }
        NSApp.deactivate()
    }
}
