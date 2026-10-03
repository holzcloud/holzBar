//
//  MenuBarOverlayPanel.swift
//  holzBar
//

import Cocoa
import OSLog

// MARK: - Overlay Panel

/// A subclass of `NSPanel` that sits atop the menu bar to alter its appearance.
final class MenuBarOverlayPanel: NSPanel {
    /// Flags representing the updatable components of a panel.
    enum UpdateFlag: String, CustomStringConvertible {
        case applicationMenuFrame
        case desktopWallpaper

        var description: String { rawValue }
    }

    /// The kind of validation that occurs before an update.
    private enum ValidationKind {
        case showing
        case updates
    }

    /// A context that manages panel update tasks.
    private final class UpdateTaskContext {
        private var tasks = [UpdateFlag: Task<Void, any Error>]()

        /// Sets the task for the given update flag.
        ///
        /// Setting the task cancels the previous task for the flag, if there is one.
        ///
        /// - Parameters:
        ///   - flag: The update flag to set the task for.
        ///   - timeout: The timeout of the task.
        ///   - operation: The operation for the task to perform.
        func setTask(for flag: UpdateFlag, timeout: Duration, operation: @escaping @MainActor @Sendable () async throws -> Void) {
            cancelTask(for: flag)
            tasks[flag] = Task.detached(timeout: timeout) {
                try await operation()
            }
        }

        /// Cancels the task for the given update flag.
        ///
        /// - Parameter flag: The update flag to cancel the task for.
        func cancelTask(for flag: UpdateFlag) {
            tasks.removeValue(forKey: flag)?.cancel()
        }
    }

    /// Shared logger for overlay panels.
    private static let logger = Logger(category: "MenuBarOverlayPanel")

    /// A Boolean value that indicates whether the panel needs to be shown.
    ///
    /// The panel is shown 0.05 s after the last change, if the value is then `true`
    /// (as Combine's `debounce` delivered the latest value).
    var needsShow = false {
        didSet {
            needsShowDebouncer.schedule { [weak self] in
                guard let self, needsShow else {
                    return
                }
                defer {
                    self.needsShow = false
                }
                show()
            }
        }
    }

    /// Flags representing the components of the panel currently in need of an update.
    ///
    /// Inserting a flag performs the updates at once; the flags are cleared on the next
    /// turn of the main actor, so several inserts in one turn update together.
    private(set) var updateFlags = Set<UpdateFlag>() {
        didSet {
            guard !updateFlags.isEmpty else {
                return
            }
            let flags = updateFlags
            Task {
                // Must be run async, or this will not remove the flags.
                self.updateFlags.removeAll()
            }
            let windows = WindowInfo.createWindows(option: .onScreen)
            if validate(for: .updates, with: windows) {
                performUpdates(for: flags, windows: windows, screen: owningScreen)
            }
        }
    }

    /// Whether the panel found no menu bar to draw on (at login, before the bar exists), so
    /// it needs another try (see `MenuBarAppearanceManager`).
    private(set) var needsRetry = false

    /// The frame of the application menu.
    private(set) var applicationMenuFrame: CGRect? {
        didSet {
            contentView?.needsDisplay = true
        }
    }

    /// The current desktop wallpaper, clipped to the bounds of the menu bar.
    private(set) var desktopWallpaper: CGImage? {
        didSet {
            contentView?.needsDisplay = true
        }
    }

    /// Shows the panel once ``needsShow`` stops changing.
    private let needsShowDebouncer = Debouncer(delay: .milliseconds(50))

    /// Updates the wallpaper 0.1 s after the appearance stops changing.
    private let themeDebouncer = Debouncer(delay: .milliseconds(100))

    /// Reads the application menu frame again 0.05 s after a click settles.
    private let applicationMenuDebouncer = Debouncer(delay: .milliseconds(50))

    /// Tasks that observe notifications and the wallpaper fallback.
    private var observerTasks = [Task<Void, Never>]()

    /// Key-value observers of the workspace and the panel.
    private var keyValueObservations = [NSKeyValueObservation]()

    /// The mouse-up monitor for clicks into another space.
    private var mouseUpMonitor: EventMonitor?

    /// Observes whether the system hides the menu bar.
    private var menuBarHiddenObserver: ObservationLoop?

    /// Observes the application menu frames read by `ApplicationMenuFrames`.
    private var applicationMenuFrameObserver: ObservationLoop?

    /// Observes whether the owning screen's menu bar is valid (see `ApplicationMenuFrames`).
    private var menuBarValidityObserver: ObservationLoop?

    /// The context that manages panel update tasks.
    private let updateTaskContext = UpdateTaskContext()

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// The screen that owns the panel.
    let owningScreen: NSScreen

    /// Creates an overlay panel with the given app state and owning screen.
    init(appState: AppState, owningScreen: NSScreen) {
        self.appState = appState
        self.owningScreen = owningScreen
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .statusBar
        self.title = "Menu Bar Overlay"
        self.backgroundColor = .clear
        self.hasShadow = false
        self.animationBehavior = .none
        self.hidesOnDeactivate = false
        self.canHide = false
        self.isMovable = false
        self.ignoresMouseEvents = true
        self.isExcludedFromWindowsMenu = true
        // One panel stands on every desktop at once, so the look is there the moment a
        // desktop slides in instead of following it after the switch (Thaw #1139).
        self.collectionBehavior = [.fullScreenNone, .ignoresCycle, .canJoinAllSpaces, .stationary]
        self.contentView = MenuBarOverlayPanelContentView()
        configureObservers()
    }

    deinit {
        for task in observerTasks {
            task.cancel()
        }
    }

    private func configureObservers() {
        // Update when light/dark mode changes.
        observeNotifications(
            named: DistributedNotificationCenter.interfaceThemeChangedNotification,
            in: DistributedNotificationCenter.default()
        ) { panel in
            panel.themeDebouncer.schedule { [weak panel] in
                panel?.startWallpaperUpdates()
            }
        }

        // Redraw with the application menu frame. `ApplicationMenuFrames` reads it off the
        // main thread when the frontmost application, the menu bar's owner, the space or
        // the screens change; the panel used to read it itself, on the main thread, every
        // millisecond until it changed and then every second for ten seconds.
        if let applicationMenuFrames = appState?.applicationMenuFrames {
            applicationMenuFrameObserver = ObservationLoop.observe {
                applicationMenuFrames.frames
            } onChange: { [weak self] _ in
                self?.insertUpdateFlag(.applicationMenuFrame)
            }
            // The first read can finish after the panel first tried to update, and a menu bar
            // can appear later (at login): update the panel once its menu bar is valid.
            let displayID = owningScreen.displayID
            menuBarValidityObserver = ObservationLoop.observe {
                applicationMenuFrames.hasValidMenuBar(on: displayID)
            } onChange: { [weak self] isValid in
                if isValid {
                    self?.updateFlags = [.applicationMenuFrame, .desktopWallpaper]
                }
            }
        }

        // Special cases for when the user drags an app onto or clicks into another space.
        keyValueObservations.append(
            observe(\.isOnActiveSpace, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.insertUpdateFlag(.applicationMenuFrame)
                }
            }
        )
        let mouseUpMonitor = EventMonitor.passive(for: .leftMouseUp, scope: .universal) { [weak self] _ in
            guard let self, isOnActiveSpace else {
                return
            }
            scheduleApplicationMenuFrameRefresh()
        }
        mouseUpMonitor.start()
        self.mouseUpMonitor = mouseUpMonitor

        // Update the desktop wallpaper when the space or the screens change, and on the
        // distributed notification "com.apple.desktop" (posted for some wallpaper changes).
        // macOS posts no reliable wallpaper notification, so a slow, tolerant fallback
        // catches the rest; it replaced a 5 s timer per screen. The application menu frame
        // needs no timer: the frontmost-application and mouse-up observers above update it.
        observeNotifications(named: NSWorkspace.activeSpaceDidChangeNotification, in: NSWorkspace.shared.notificationCenter) { panel in
            panel.insertUpdateFlag(.desktopWallpaper)
        }
        observeNotifications(named: NSApplication.didChangeScreenParametersNotification, in: NotificationCenter.default) { panel in
            panel.insertUpdateFlag(.desktopWallpaper)
        }
        observeNotifications(named: Notification.Name("com.apple.desktop"), in: DistributedNotificationCenter.default()) { panel in
            panel.insertUpdateFlag(.desktopWallpaper)
        }
        observerTasks.append(Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(30), tolerance: .seconds(5))
                } catch {
                    return
                }
                self?.insertUpdateFlag(.desktopWallpaper)
            }
        })

        // The panel steps aside while the system hides the menu bar and on a fullscreen
        // space, and comes back when that ends.
        if let appState {
            alphaValue = Self.stepsAside(appState) ? 0 : 1
            menuBarHiddenObserver = ObservationLoop.observe { [weak appState] in
                appState.map(Self.stepsAside) ?? false
            } onChange: { [weak self] stepsAside in
                self?.animator().alphaValue = stepsAside ? 0 : 1
            }
        }
    }

    /// Whether the panel is invisible: the system hides the menu bar, or the active space is
    /// fullscreen.
    private static func stepsAside(_ appState: AppState) -> Bool {
        appState.menuBarManager.isMenuBarHiddenBySystem || appState.activeSpace.isFullscreen
    }

    /// Calls the handler for each notification with the given name, while the panel exists.
    private func observeNotifications(
        named name: Notification.Name,
        in center: NotificationCenter,
        handler: @escaping @MainActor @Sendable (MenuBarOverlayPanel) -> Void
    ) {
        observerTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: name) {
                guard let self else {
                    return
                }
                handler(self)
            }
        })
    }

    /// Updates the wallpaper every second for five seconds, while the appearance switches.
    private func startWallpaperUpdates() {
        updateTaskContext.setTask(for: .desktopWallpaper, timeout: .seconds(5)) { [weak self] in
            while true {
                try Task.checkCancellation()
                self?.insertUpdateFlag(.desktopWallpaper)
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Reads the application menu frame again once a click settles, off the main thread.
    private func scheduleApplicationMenuFrameRefresh() {
        applicationMenuDebouncer.schedule { [weak self] in
            self?.appState?.applicationMenuFrames.refresh(reason: "click", settling: false)
        }
    }

    /// Inserts the given update flag into the panel's current list of update flags.
    private func insertUpdateFlag(_ flag: UpdateFlag) {
        updateFlags.insert(flag)
    }

    /// Performs validation for the given validation kind. Returns the panel's
    /// owning display if successful. Returns `nil` on failure.
    private func validate(for kind: ValidationKind, with windows: [WindowInfo]) -> Bool {
        lazy var actionMessage = switch kind {
        case .showing: "Preventing overlay panel from showing."
        case .updates: "Preventing overlay panel from updating."
        }
        guard let appState else {
            MenuBarOverlayPanel.logger.debug("No app state. \(actionMessage, privacy: .public)")
            return false
        }
        guard !appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults else {
            MenuBarOverlayPanel.logger.debug("Menu bar is hidden by system. \(actionMessage, privacy: .public)")
            return false
        }
        guard !appState.activeSpace.isFullscreen else {
            MenuBarOverlayPanel.logger.debug("Active space is fullscreen. \(actionMessage, privacy: .public)")
            return false
        }
        guard appState.menuBarManager.hasValidMenuBar(in: windows, for: owningScreen.displayID) else {
            MenuBarOverlayPanel.logger.debug("No valid menu bar found. \(actionMessage, privacy: .public)")
            needsRetry = true
            return false
        }
        needsRetry = false
        return true
    }

    /// Draws the panel again and updates the application menu frame and the wallpaper.
    func refresh() {
        updateFlags = [.applicationMenuFrame, .desktopWallpaper]
        contentView?.needsDisplay = true
    }

    /// Stores the frame of the menu bar's application menu.
    private func updateApplicationMenuFrame(for screen: NSScreen) {
        guard
            let menuBarManager = appState?.menuBarManager,
            !menuBarManager.isMenuBarHiddenBySystem
        else {
            return
        }
        applicationMenuFrame = appState?.applicationMenuFrames.frame(for: screen)
    }

    /// Stores the area of the desktop wallpaper that is under the menu bar
    /// of the given display.
    private func updateDesktopWallpaper(for display: CGDirectDisplayID, with windows: [WindowInfo]) {
        // Nothing captures the screen before Screen Recording is granted; the shape is
        // then drawn without the wallpaper beside it.
        guard ScreenCapture.cachedCheckPermissions() else {
            if desktopWallpaper != nil {
                desktopWallpaper = nil
            }
            return
        }
        guard
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: display),
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: display)
        else {
            return
        }
        let wallpaper = ScreenCapture.captureWindow(with: wallpaperWindow.windowID, screenBounds: menuBarWindow.bounds)
        if desktopWallpaper?.dataProvider?.data != wallpaper?.dataProvider?.data {
            desktopWallpaper = wallpaper
        }
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(for flags: Set<UpdateFlag>, windows: [WindowInfo], screen: NSScreen) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: screen)
        }
        if flags.contains(.desktopWallpaper) {
            updateDesktopWallpaper(for: screen.displayID, with: windows)
        }
    }

    /// Shows the panel.
    private func show() {
        guard let appState else {
            return
        }

        guard appState.appearanceManager.overlayPanels.contains(self) else {
            MenuBarOverlayPanel.logger.warning("Overlay panel \(self, privacy: .public) not retained")
            return
        }

        guard let menuBarHeight = owningScreen.getMenuBarHeight() else {
            MenuBarOverlayPanel.logger.debug("No menu bar window found. Preventing overlay panel from showing.")
            needsRetry = true
            return
        }

        let newFrame = CGRect(
            x: owningScreen.frame.minX,
            y: (owningScreen.frame.maxY - menuBarHeight) - 5,
            width: owningScreen.frame.width,
            height: menuBarHeight + 5
        )

        alphaValue = 0
        setFrame(newFrame, display: false)
        orderFrontRegardless()

        updateFlags = [.applicationMenuFrame, .desktopWallpaper]

        if !Self.stepsAside(appState) {
            animator().alphaValue = 1
        }
    }

    override func isAccessibilityElement() -> Bool {
        return false
    }
}

// MARK: - Content View

private final class MenuBarOverlayPanelContentView: NSView {
    private var fullConfiguration: MenuBarAppearanceConfigurationV2 = .defaultConfiguration {
        didSet {
            needsDisplay = true
        }
    }

    private var previewConfiguration: MenuBarAppearancePartialConfiguration? {
        didSet {
            needsDisplay = true
        }
    }

    /// Observers of the appearance, the drag state and the control items.
    private var observers = [ObservationLoop]()

    /// The overlay panel that contains the content view.
    private var overlayPanel: MenuBarOverlayPanel? {
        window as? MenuBarOverlayPanel
    }

    /// The currently displayed configuration.
    private var configuration: MenuBarAppearancePartialConfiguration {
        previewConfiguration ?? fullConfiguration.current
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureObservers()
    }

    private func configureObservers() {
        observers.removeAll()

        guard let appState = overlayPanel?.appState else {
            return
        }
        let appearanceManager = appState.appearanceManager

        fullConfiguration = appearanceManager.configuration
        previewConfiguration = appearanceManager.previewConfiguration
        observers.append(
            ObservationLoop.observe { appearanceManager.configuration } onChange: { [weak self] configuration in
                self?.fullConfiguration = configuration
            }
        )
        observers.append(
            ObservationLoop.observe { appearanceManager.previewConfiguration } onChange: { [weak self] configuration in
                self?.previewConfiguration = configuration
            }
        )

        // Fade out whenever a menu bar item is being dragged.
        observers.append(
            ObservationLoop.observe { appState.isDraggingMenuBarItem } onChange: { [weak self] isDragging in
                if isDragging {
                    self?.animator().alphaValue = 0
                } else {
                    self?.animator().alphaValue = 1
                }
            }
        )

        // Redraw whenever the window frame of a control item changes: it changes only
        // after the items moved on screen, so the drawing that depends on their positions
        // is right then.
        let sections = appState.menuBarManager.sections
        observers.append(
            ObservationLoop.observe {
                sections.map(\.controlItem.onScreenFrame)
            } onChange: { [weak self] _ in
                self?.needsDisplay = true
            }
        )

        // Redraw too when a section is shown or hidden, so the shape appears with the
        // icons during a reveal rather than after the next frame change, and when the
        // item list changes: an application adding an item moves no control item, and on
        // macOS 27 the control items' frames never change at all.
        observers.append(
            ObservationLoop.observe {
                sections.map(\.isHidden)
            } onChange: { [weak self] _ in
                self?.needsDisplay = true
            }
        )
        let itemManager = appState.itemManager
        observers.append(
            ObservationLoop.observe {
                itemManager.itemCache
            } onChange: { [weak self] _ in
                self?.needsDisplay = true
            }
        )
        if #available(macOS 27.0, *) {
            let concealer = appState.concealer27
            observers.append(
                ObservationLoop.observe {
                    concealer.concealedPIDs
                } onChange: { [weak self] _ in
                    self?.needsDisplay = true
                }
            )
        }

        // The application menu frame and the wallpaper redraw the view from the panel.
    }

    /// Returns a path in the given rectangle, with the given end caps,
    /// and inset by the given amounts.
    private func shapePath(in rect: CGRect, leadingEndCap: MenuBarEndCap, trailingEndCap: MenuBarEndCap, screen: NSScreen) -> NSBezierPath {
        let insetRect: CGRect = if !screen.hasNotch {
            switch (leadingEndCap, trailingEndCap) {
            case (.square, .square):
                CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width, height: rect.height - 2)
            case (.square, .round):
                CGRect(x: rect.origin.x, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .square):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 1, height: rect.height - 2)
            case (.round, .round):
                CGRect(x: rect.origin.x + 1, y: rect.origin.y + 1, width: rect.width - 2, height: rect.height - 2)
            }
        } else {
            rect
        }

        let shapeBounds = CGRect(
            x: insetRect.minX + insetRect.height / 2,
            y: insetRect.minY,
            width: insetRect.width - insetRect.height,
            height: insetRect.height
        )
        let leadingEndCapBounds = CGRect(
            x: insetRect.minX,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )
        let trailingEndCapBounds = CGRect(
            x: insetRect.maxX - insetRect.height,
            y: insetRect.minY,
            width: insetRect.height,
            height: insetRect.height
        )

        var path = NSBezierPath(rect: shapeBounds)

        path = switch leadingEndCap {
        case .square: path.union(NSBezierPath(rect: leadingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: leadingEndCapBounds))
        }

        path = switch trailingEndCap {
        case .square: path.union(NSBezierPath(rect: trailingEndCapBounds))
        case .round: path.union(NSBezierPath(ovalIn: trailingEndCapBounds))
        }

        return path
    }

    /// Returns a path for the ``MenuBarShapeKind/full`` shape kind.
    private func pathForFullShape(in rect: CGRect, info: MenuBarFullShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        return shapePath(
            in: rect,
            leadingEndCap: info.leadingEndCap,
            trailingEndCap: info.trailingEndCap,
            screen: screen
        )
    }

    /// Returns a path for the ``MenuBarShapeKind/split`` shape kind.
    private func pathForSplitShape(in rect: CGRect, info: MenuBarSplitShapeInfo, isInset: Bool, screen: NSScreen) -> NSBezierPath {
        guard let appearanceManager = overlayPanel?.appState?.appearanceManager else {
            return NSBezierPath()
        }
        var rect = rect
        let shouldInset = isInset && screen.hasNotch
        if shouldInset {
            rect = rect.insetBy(dx: 0, dy: appearanceManager.menuBarInsetAmount)
            if info.leading.leadingEndCap == .round {
                rect.origin.x += appearanceManager.menuBarInsetAmount
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
            if info.trailing.trailingEndCap == .round {
                rect.size.width -= appearanceManager.menuBarInsetAmount
            }
        }
        let leadingPathBounds: CGRect = {
            guard
                var maxX = overlayPanel?.applicationMenuFrame?.width,
                maxX > 0
            else {
                return .zero
            }
            if shouldInset {
                maxX += 10
                if info.leading.leadingEndCap == .square {
                    maxX += appearanceManager.menuBarInsetAmount
                }
            } else {
                maxX += 20
            }
            return CGRect(x: rect.minX, y: rect.minY, width: maxX, height: rect.height)
        }()
        let trailingPathBounds: CGRect = {
            let itemWindows = MenuBarItem.getMenuBarItemWindows(on: screen.displayID, option: .onScreen)
            guard !itemWindows.isEmpty else {
                return .zero
            }
            let totalWidth = itemWindows.reduce(into: 0) { width, item in
                width += item.bounds.width
            }
            var position = rect.maxX - totalWidth
            if shouldInset {
                position += 4
                if info.trailing.trailingEndCap == .square {
                    position -= appearanceManager.menuBarInsetAmount
                }
            } else {
                position -= 7
            }
            return CGRect(x: position, y: rect.minY, width: rect.maxX - position, height: rect.height)
        }()

        if leadingPathBounds == .zero || trailingPathBounds == .zero || leadingPathBounds.intersects(trailingPathBounds) {
            return shapePath(
                in: rect,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
        } else {
            let leadingPath = shapePath(
                in: leadingPathBounds,
                leadingEndCap: info.leading.leadingEndCap,
                trailingEndCap: info.leading.trailingEndCap,
                screen: screen
            )
            let trailingPath = shapePath(
                in: trailingPathBounds,
                leadingEndCap: info.trailing.leadingEndCap,
                trailingEndCap: info.trailing.trailingEndCap,
                screen: screen
            )
            let path = NSBezierPath()
            path.append(leadingPath)
            path.append(trailingPath)
            return path
        }
    }

    /// Returns the bounds that the view's drawn content can occupy.
    private func getDrawableBounds() -> CGRect {
        return CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y + 5,
            width: bounds.width,
            height: bounds.height - 5
        )
    }

    /// Draws the tint defined by the given configuration in the given rectangle.
    private func drawTint(in rect: CGRect) {
        switch configuration.tintKind {
        case .noTint:
            break
        case .solid:
            if let tintColor = NSColor(cgColor: configuration.tintColor)?.withAlphaComponent(0.2) {
                tintColor.setFill()
                rect.fill()
            }
        case .gradient:
            if let tintGradient = configuration.tintGradient.withAlpha(0.2).nsGradient(using: .displayP3) {
                tintGradient.draw(in: rect, angle: 0)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard
            let overlayPanel,
            let context = NSGraphicsContext.current
        else {
            return
        }

        let drawableBounds = getDrawableBounds()

        // A black menu bar replaces every other style: the notch disappears into it.
        if fullConfiguration.blackBackground.applies(to: overlayPanel.owningScreen) {
            NSColor.black.setFill()
            drawableBounds.fill()
            return
        }

        let shapePath = switch fullConfiguration.shapeKind {
        case .noShape:
            NSBezierPath(rect: drawableBounds)
        case .full:
            pathForFullShape(
                in: drawableBounds,
                info: fullConfiguration.fullShapeInfo,
                isInset: fullConfiguration.isInset,
                screen: overlayPanel.owningScreen
            )
        case .split:
            pathForSplitShape(
                in: drawableBounds,
                info: fullConfiguration.splitShapeInfo,
                isInset: fullConfiguration.isInset,
                screen: overlayPanel.owningScreen
            )
        }

        var hasBorder = false

        switch fullConfiguration.shapeKind {
        case .noShape:
            if configuration.hasShadow {
                let gradient = NSGradient(
                    colors: [
                        NSColor(white: 0.0, alpha: 0.0),
                        NSColor(white: 0.0, alpha: 0.2),
                    ]
                )
                let shadowBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY,
                    width: bounds.width,
                    height: 5
                )
                gradient?.draw(in: shadowBounds, angle: 90)
            }

            drawTint(in: drawableBounds)

            if configuration.hasBorder {
                let borderBounds = CGRect(
                    x: bounds.minX,
                    y: bounds.minY + 5,
                    width: bounds.width,
                    height: configuration.borderWidth
                )
                NSColor(cgColor: configuration.borderColor)?.setFill()
                NSBezierPath(rect: borderBounds).fill()
            }
        case .full, .split:
            if let desktopWallpaper = overlayPanel.desktopWallpaper {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let invertedClipPath = NSBezierPath(rect: drawableBounds)
                invertedClipPath.append(shapePath.reversed)
                invertedClipPath.setClip()

                context.cgContext.draw(desktopWallpaper, in: drawableBounds)
            }

            if configuration.hasShadow {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let shadowClipPath = NSBezierPath(rect: bounds)
                shadowClipPath.append(shapePath.reversed)
                shadowClipPath.setClip()

                shapePath.drawShadow(color: .black.withAlphaComponent(0.5), radius: 5)
            }

            if configuration.hasBorder {
                hasBorder = true
            }

            do {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                shapePath.setClip()

                drawTint(in: drawableBounds)
            }

            if
                hasBorder,
                let borderColor = NSColor(cgColor: configuration.borderColor)
            {
                context.saveGraphicsState()
                defer {
                    context.restoreGraphicsState()
                }

                let borderPath = switch fullConfiguration.shapeKind {
                case .noShape:
                    NSBezierPath(rect: drawableBounds)
                case .full:
                    pathForFullShape(
                        in: drawableBounds,
                        info: fullConfiguration.fullShapeInfo,
                        isInset: fullConfiguration.isInset,
                        screen: overlayPanel.owningScreen
                    )
                case .split:
                    pathForSplitShape(
                        in: drawableBounds,
                        info: fullConfiguration.splitShapeInfo,
                        isInset: fullConfiguration.isInset,
                        screen: overlayPanel.owningScreen
                    )
                }

                // HACK: Insetting a path to get an "inside" stroke is surprisingly
                // difficult. We can fake the correct line width by doubling it, as
                // anything outside the shape path will be clipped.
                borderPath.lineWidth = configuration.borderWidth * 2
                borderPath.setClip()

                borderColor.setStroke()
                borderPath.stroke()
            }
        }
    }
}
