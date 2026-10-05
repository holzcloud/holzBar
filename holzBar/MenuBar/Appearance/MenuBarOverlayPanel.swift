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

    /// The dominant colors of the wallpaper under the menu bar, for the "Follow Wallpaper"
    /// tint; read only while a configuration uses it.
    private(set) var wallpaperPalette: WallpaperPalette? {
        didSet {
            contentView?.needsDisplay = true
        }
    }

    /// The read of the wallpaper's palette that is under way.
    private var paletteTask: Task<Void, Never>?

    /// Observes whether a tint follows the wallpaper.
    private var wallpaperTintObserver: ObservationLoop?

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

    /// Observes the shape, which decides whether the wallpaper is needed.
    private var shapeKindObserver: ObservationLoop?

    /// Notices a new wallpaper without a timer.
    private let wallpaperChangeMonitor = WallpaperChangeMonitor()

    /// The read of the desktop picture under the bar that is under way.
    private var wallpaperTask: Task<Void, Never>?

    /// Captures the wallpaper again every 30 s while the capture fallback is in use (a
    /// moving wallpaper before macOS 27, which changes without an event).
    private var captureFallbackTask: Task<Void, Never>?

    /// Whether the wallpaper comes from a capture (a moving wallpaper before macOS 27).
    private var usesCaptureFallback = false {
        didSet {
            guard usesCaptureFallback != oldValue else {
                return
            }
            captureFallbackTask?.cancel()
            captureFallbackTask = nil
            guard usesCaptureFallback else {
                return
            }
            captureFallbackTask = Task { [weak self] in
                while true {
                    do {
                        try await Task.sleep(for: .seconds(30), tolerance: .seconds(5))
                    } catch {
                        return
                    }
                    self?.insertUpdateFlag(.desktopWallpaper)
                }
            }
        }
    }

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
        wallpaperTask?.cancel()
        paletteTask?.cancel()
        captureFallbackTask?.cancel()
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

        // Update the desktop wallpaper when the space or the screens change, on the
        // distributed notification "com.apple.desktop" (posted for some wallpaper changes)
        // and when the wallpaper store's index changes (`WallpaperChangeMonitor`). Only the
        // capture fallback for a moving wallpaper before macOS 27 needs a slow, tolerant
        // timer (`captureFallbackTask`). The application menu frame needs no timer:
        // `ApplicationMenuFrames` follows it.
        observeNotifications(named: NSWorkspace.activeSpaceDidChangeNotification, in: NSWorkspace.shared.notificationCenter) { panel in
            panel.insertUpdateFlag(.desktopWallpaper)
        }
        observeNotifications(named: NSApplication.didChangeScreenParametersNotification, in: NotificationCenter.default) { panel in
            panel.insertUpdateFlag(.desktopWallpaper)
        }
        observeNotifications(named: Notification.Name("com.apple.desktop"), in: DistributedNotificationCenter.default()) { panel in
            DesktopPicture.invalidate()
            panel.insertUpdateFlag(.desktopWallpaper)
        }
        wallpaperChangeMonitor.onChange = { [weak self] in
            DesktopPicture.invalidate()
            self?.insertUpdateFlag(.desktopWallpaper)
        }
        wallpaperChangeMonitor.start()
        if let appearanceManager = appState?.appearanceManager {
            // Only a shape draws the wallpaper, so it is read when one is chosen.
            shapeKindObserver = ObservationLoop.observe {
                appearanceManager.configuration.shapeKind
            } onChange: { [weak self] _ in
                self?.insertUpdateFlag(.desktopWallpaper)
            }
            // Only the "Follow Wallpaper" tint needs the palette.
            wallpaperTintObserver = ObservationLoop.observe {
                appearanceManager.configuration.usesWallpaperTint
            } onChange: { [weak self] _ in
                self?.insertUpdateFlag(.desktopWallpaper)
            }
        }

        // A tint that follows the accent color changes with it at once.
        observeNotifications(named: NSColor.systemColorsDidChangeNotification, in: NotificationCenter.default) { panel in
            panel.contentView?.needsDisplay = true
        }

        // On macOS 27 the split shape starts its trailing half where the run of items starts,
        // and a read can move that edge without changing the item cache: a concealed item
        // keeps its old frame, and the items right of it stay where they are. No other shape
        // depends on that edge.
        observeNotifications(named: .menuBarItemsAreaDidChange27, in: NotificationCenter.default) { panel in
            guard panel.appState?.appearanceManager.configuration.shapeKind == .split else {
                return
            }
            panel.contentView?.needsDisplay = true
        }

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
    ///
    /// The picture is read from its file (`DesktopPicture`), with no capture and no Screen
    /// Recording. Only a moving wallpaper has no file: before macOS 27 it is captured when
    /// Screen Recording is already granted; on macOS 27 nothing is captured (a capture lights
    /// the recording indicator) and the shape stands on the flat colour of the bar.
    private func updateDesktopWallpaper(for display: CGDirectDisplayID, with windows: [WindowInfo]) {
        guard
            let appState,
            appState.appearanceManager.configuration.shapeKind != .noShape,
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: display)
        else {
            usesCaptureFallback = false
            if desktopWallpaper != nil {
                desktopWallpaper = nil
            }
            return
        }
        let menuBarBounds = menuBarWindow.bounds
        let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: display)
        wallpaperTask?.cancel()
        wallpaperTask = Task { [weak self] in
            guard let self else {
                return
            }
            let strip = await DesktopPicture.strip(for: owningScreen, height: menuBarBounds.height)
            guard !Task.isCancelled else {
                return
            }
            if let strip {
                usesCaptureFallback = false
                if desktopWallpaper !== strip {
                    desktopWallpaper = strip
                }
                return
            }
            if #available(macOS 27.0, *) {
                usesCaptureFallback = false
                desktopWallpaper = Self.solidImage(color: HolzBarShelfColorManager.flatColor27())
                return
            }
            // Nothing captures the screen before Screen Recording is granted; the shape is
            // then drawn without the wallpaper beside it.
            guard ScreenCapture.cachedCheckPermissions(), let wallpaperWindow else {
                usesCaptureFallback = false
                if desktopWallpaper != nil {
                    desktopWallpaper = nil
                }
                return
            }
            usesCaptureFallback = true
            let wallpaper = ScreenCapture.captureWindow(with: wallpaperWindow.windowID, screenBounds: menuBarBounds)
            if desktopWallpaper?.dataProvider?.data != wallpaper?.dataProvider?.data {
                desktopWallpaper = wallpaper
            }
        }
    }

    /// Reads the palette of the wallpaper under the menu bar, while a tint follows it.
    private func updateWallpaperPalette(for screen: NSScreen) {
        paletteTask?.cancel()
        guard
            let appState,
            appState.appearanceManager.configuration.usesWallpaperTint,
            let height = screen.getMenuBarHeight()
        else {
            if wallpaperPalette != nil {
                wallpaperPalette = nil
            }
            return
        }
        paletteTask = Task { [weak self] in
            guard let self else {
                return
            }
            let palette = await DesktopPicture.palette(for: owningScreen, height: height)
            guard !Task.isCancelled, palette != wallpaperPalette else {
                return
            }
            wallpaperPalette = palette
        }
    }

    /// A one-pixel image of the given colour, drawn stretched over the bar.
    private static func solidImage(color: CGColor) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }
        context.setFillColor(color)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()
    }

    /// Updates the panel to prepare for display.
    private func performUpdates(for flags: Set<UpdateFlag>, windows: [WindowInfo], screen: NSScreen) {
        if flags.contains(.applicationMenuFrame) {
            updateApplicationMenuFrame(for: screen)
        }
        if flags.contains(.desktopWallpaper) {
            updateDesktopWallpaper(for: screen.displayID, with: windows)
            updateWallpaperPalette(for: screen)
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
            updateGlassView()
        }
    }

    private var previewConfiguration: MenuBarAppearancePartialConfiguration? {
        didSet {
            needsDisplay = true
            updateGlassView()
        }
    }

    /// The system glass of the "System Glass" tint (macOS 26 and later), masked to the
    /// shape; the way Thaw masks its glass tint (see NOTICE).
    private var glassView: NSView?

    /// The shape the glass is masked to, set while drawing.
    private let glassMask = CAShapeLayer()

    /// Adds or removes the system glass with the tint kind.
    private func updateGlassView() {
        if #available(macOS 26.0, *), configuration.tintKind == .systemGlass {
            guard glassView == nil else {
                return
            }
            let view = NSGlassEffectView(frame: bounds)
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.layer?.mask = glassMask
            addSubview(view)
            glassView = view
        } else if let glassView {
            glassView.removeFromSuperview()
            self.glassView = nil
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

    /// A dynamic appearance switches its configuration with light/dark mode, which
    /// changes neither stored configuration: add or remove the glass and redraw here.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        updateGlassView()
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

        // The application menu frame, the wallpaper and, on macOS 27, the edge of the items
        // area redraw the view from the panel.
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
        guard let appState = overlayPanel?.appState else {
            return NSBezierPath()
        }
        let appearanceManager = appState.appearanceManager
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
            // On macOS 27 there are no item windows: the backend knows where the run of
            // items starts, from values it already read.
            if let leftEdge = appState.itemManager.backend.itemsAreaLeftEdge(on: screen, appState: appState) {
                // x is the same in CoreGraphics and Cocoa coordinates.
                return SplitShape27.trailingBounds(
                    edge: leftEdge - screen.frame.minX,
                    in: rect,
                    isInset: shouldInset,
                    insetAmount: appearanceManager.menuBarInsetAmount
                )
            }
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
        case .noTint, .systemGlass:
            // The system glass is a view of its own (`updateGlassView()`).
            break
        case .solid:
            let baseColor: NSColor? = configuration.tintFollowsAccentColor
                ? NSColor.controlAccentColor
                : NSColor(cgColor: configuration.tintColor)
            if let tintColor = baseColor?.withAlphaComponent(0.2) {
                tintColor.setFill()
                rect.fill()
            }
        case .gradient:
            if let tintGradient = configuration.tintGradient.withAlpha(0.2).nsGradient(using: .displayP3) {
                tintGradient.draw(in: rect, angle: 0)
            }
        case .adaptive:
            // A gradient from the wallpaper's two dominant colors; one color is solid.
            guard
                let palette = overlayPanel?.wallpaperPalette,
                let primary = palette.primary,
                let secondary = palette.secondary
            else {
                return
            }
            let colors = [primary, secondary].map { swatch in
                NSColor(srgbRed: swatch.red, green: swatch.green, blue: swatch.blue, alpha: 0.2)
            }
            NSGradient(colors: colors)?.draw(in: rect, angle: 0)
        }
    }

    /// Strokes a border path with the configured style: solid, dashed or dotted.
    ///
    /// - Parameter drawnWidth: The width the path is stroked with.
    private func strokeBorder(_ path: NSBezierPath, color: NSColor, drawnWidth: CGFloat) {
        path.lineWidth = drawnWidth
        if let dashes = BorderPattern.dashes(for: configuration.borderStyle, width: drawnWidth) {
            let pattern = dashes.map { CGFloat($0) }
            path.setLineDash(pattern, count: pattern.count, phase: 0)
        }
        if BorderPattern.usesRoundCaps(configuration.borderStyle) {
            path.lineCapStyle = .round
        }
        color.setStroke()
        path.stroke()
    }

    override func layout() {
        super.layout()
        glassMask.frame = bounds
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
            glassMask.path = nil
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

        if glassView != nil {
            glassMask.frame = bounds
            glassMask.path = shapePath.cgPath
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

            if configuration.hasBorder, let borderColor = NSColor(cgColor: configuration.borderColor) {
                if configuration.borderStyle == .solid {
                    let borderBounds = CGRect(
                        x: bounds.minX,
                        y: bounds.minY + 5,
                        width: bounds.width,
                        height: configuration.borderWidth
                    )
                    borderColor.setFill()
                    NSBezierPath(rect: borderBounds).fill()
                } else {
                    // A line along the bottom of the bar, dashed or dotted.
                    let lineY = bounds.minY + 5 + configuration.borderWidth / 2
                    let line = NSBezierPath()
                    line.move(to: CGPoint(x: bounds.minX, y: lineY))
                    line.line(to: CGPoint(x: bounds.maxX, y: lineY))
                    strokeBorder(line, color: borderColor, drawnWidth: configuration.borderWidth)
                }
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
                borderPath.setClip()
                strokeBorder(borderPath, color: borderColor, drawnWidth: configuration.borderWidth * 2)
            }
        }
    }
}
