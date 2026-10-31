//
//  HolzBarShelf.swift
//  holzBar
//

import OSLog
import SwiftUI

// MARK: - HolzBarShelfPanel

final class HolzBarShelfPanel: NSPanel {
    /// The shared app state.
    private weak var appState: AppState?

    /// Manager for the holzBar Shelf's color, created when the Shelf is first shown.
    private var colorManager: HolzBarShelfColorManager?

    /// Follows Reduce Transparency and Increase Contrast while the Shelf is open.
    private let transparency = TransparencyObserver()

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// What the panel is placed by, chosen once when it opens, so a resize while it is open
    /// does not move it to the mouse pointer or the holzBar icon.
    private var anchor: HolzBarShelfPlacement.Anchor?

    /// Whether the panel hangs from the menu bar or floats below it, as the setting was when
    /// it opened: a change made while it is open takes effect the next time it opens.
    private var style = HolzBarShelfStyle.attached

    /// Counts the calls to `show(section:on:)` and `close()`, so a show that waited for the
    /// caches knows whether the panel was closed or shown again meanwhile.
    private var showGeneration = 0

    /// Tasks that hide the panel when the space or the screens change.
    private var observerTasks = [Task<Void, Never>]()

    /// Observes the hidden section's control item.
    private var controlItemObserver: ObservationLoop?

    /// Follows the control item at most every 0.1 s, with its latest frame.
    private let controlItemThrottle = Debouncer(delay: .milliseconds(100))

    /// Whether the Shelf takes keys: it was opened with a hotkey, so the arrows, Return and
    /// Escape work in it. Opened with the mouse, it stays non-key as before.
    var acceptsKeyboard = false

    /// Whether the Shelf of the hidden section lists the always-hidden items now (the fold is
    /// open, or something is typed), so their pictures are captured too.
    var listsAlwaysHidden = false

    override var canBecomeKey: Bool { acceptsKeyboard }

    /// What the Shelf shows while a tile or a dragged menu bar item is over it.
    let dragModel = HolzBarShelfDragModel()

    /// Outlines the Shelf while a dragged menu bar item is over it and will be hidden by the drop.
    func setDropTargeted(_ isTargeted: Bool) {
        if dragModel.isDropTargeted != isTargeted {
            dragModel.isDropTargeted = isTargeted
        }
    }

    /// Creates a new holzBar Shelf panel.
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.title = "holzBar Shelf"
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = true
        self.allowsToolTipsWhenApplicationIsInactive = true
        self.isFloatingPanel = true
        self.animationBehavior = .none
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .mainMenu + 1
        self.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
    }

    /// Sets up the panel.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
    }

    /// Returns the manager for the Shelf's color, creating and setting it up the first
    /// time the Shelf is shown.
    private func colorManagerForShowing() -> HolzBarShelfColorManager {
        if let colorManager {
            return colorManager
        }
        let colorManager = HolzBarShelfColorManager()
        colorManager.performSetup(with: self)
        self.colorManager = colorManager
        return colorManager
    }

    /// Configures the internal observers.
    private func configureObservers() {
        // Hide the panel when the active space or screen parameters change.
        observerTasks = [
            Task { [weak self] in
                let center = NSWorkspace.shared.notificationCenter
                for await _ in center.notifications(named: NSWorkspace.activeSpaceDidChangeNotification) {
                    self?.hide()
                }
            },
            Task { [weak self] in
                let center = NotificationCenter.default
                for await _ in center.notifications(named: NSApplication.didChangeScreenParametersNotification) {
                    self?.hide()
                }
            },
        ]

        if let controlItem = appState?.menuBarManager.controlItem(withName: .hidden) {
            // Use the hidden control item's frame to determine if the menu bar
            // is hidden. Hide the panel if so.
            controlItemObserver = ObservationLoop.observe {
                (controlItem.frame, controlItem.screen)
            } onChange: { [weak self, weak controlItem] _ in
                self?.controlItemThrottle.throttle(latest: true) { [weak self, weak controlItem] in
                    guard let self, let controlItem else {
                        return
                    }

                    guard let frame = controlItem.frame, let screen = controlItem.screen else {
                        hide()
                        return
                    }

                    // Icon is not vertically visible. We can infer that the
                    // menu bar is hidden.
                    if frame.maxY > screen.frame.maxY {
                        hide()
                    }
                }
            }
        }
    }

    /// Updates the panel's origin whenever its size changes.
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        let oldSize = frame.size
        super.setFrame(frameRect, display: flag)
        if frame.size != oldSize, let screen {
            updateOrigin(for: screen)
        }
    }

    /// Returns what to place the panel by for the given location setting, read from the
    /// mouse pointer and the holzBar icon as they are now.
    private func getAnchor(for shelfLocation: HolzBarShelfLocation, screen: NSScreen) -> HolzBarShelfPlacement.Anchor {
        guard let appState else {
            return .screenEdge
        }

        switch shelfLocation {
        case .dynamic:
            if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                return getAnchor(for: .mousePointer, screen: screen)
            }
            return getAnchor(for: .holzBarIcon, screen: screen)
        case .mousePointer:
            guard let location = MouseHelpers.locationAppKit else {
                return getAnchor(for: .holzBarIcon, screen: screen)
            }
            // The attached Shelf uses only the pointer's x; the floating bar hangs below it.
            return .pointer(x: location.x, y: location.y)
        case .screenEdge:
            return .screenEdge
        case .holzBarIcon:
            guard
                let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem),
                // Bridging API is more reliable than controlItem.frame in some
                // cases (like if the item is offscreen).
                let itemBounds = Bridging.getWindowBounds(for: controlItem.windowID)
            else {
                // Without the icon's position the panel goes to the right of the screen.
                return .screenEdge
            }
            return .horizontal(itemBounds.midX)
        }
    }

    /// Updates the panel's frame origin for display on the given screen, placed by the
    /// anchor chosen when it opened.
    private func updateOrigin(for screen: NSScreen) {
        let origin = HolzBarShelfPlacement.origin(
            style: style,
            anchor: anchor ?? .screenEdge,
            panel: .init(width: frame.width, height: frame.height),
            screen: .init(
                frame: .init(screen.frame),
                visibleFrame: .init(screen.visibleFrame),
                menuBarHeight: screen.getMenuBarHeight() ?? 0
            ),
            insets: style == .floating ? HolzBarShelfPlacement.floatingInsets : .zero
        )
        setFrameOrigin(CGPoint(x: origin.x, y: origin.y))
    }

    /// Shows the panel on the given screen, displaying the given
    /// menu bar section.
    ///
    /// - Returns: Whether the panel was shown, which it is not when it was closed
    ///   or shown again while the caches updated.
    @discardableResult
    func show(section: MenuBarSection.Name, on screen: NSScreen) async -> Bool {
        let requestedAt = ContinuousClock.now
        guard let appState else {
            return false
        }

        showGeneration += 1
        let generation = showGeneration

        // IMPORTANT: We must set the navigation state and current section
        // before updating the caches.
        appState.navigationState.isShelfPresented = true
        currentSection = section
        // Set before the pictures are captured: an open fold needs those of its items too.
        let general = appState.settings.general
        listsAlwaysHidden = section == .hidden
            && appState.settings.advanced.enableAlwaysHiddenSection
            && general.shelfAlwaysHiddenFold.opensFold(wasLeftOpen: general.shelfAlwaysHiddenFoldOpen)

        if #available(macOS 27.0, *), !Defaults.bool(forKey: .macOS27ShelfWaitsForRefresh) {
            // Waiting for this refresh cannot help the bar that is about to open on macOS 27:
            // the hidden items are concealed, so they can be neither read nor photographed,
            // and the bar shows the images stored while they were drawn. The wait only held
            // the bar back by a scan of every process and a capture of the display. The
            // refresh runs alongside instead, for the visible items and any still missing.
            // The `Defaults.Key.macOS27ShelfWaitsForRefresh` default brings the wait back, for measuring.
            Task {
                await appState.itemManager.cacheItemsIfNeeded()
                // Derived again whether or not the item cache rebuilt, so the Shelf never
                // decides on a state older than its opening (Phase 22).
                await appState.concealer27.refreshNativeOverflow()
                await appState.imageCache.updateCache()
            }
        } else {
            // The refresh is its own task, so a timeout ends only the wait: the refresh still
            // lands in the observable caches. Awaiting `.value` does not pass the cancellation on.
            let refresh = Task {
                await appState.itemManager.cacheItemsIfNeeded()
                if #available(macOS 27.0, *) {
                    await appState.concealer27.refreshNativeOverflow()
                }
                await appState.imageCache.updateCache()
            }
            let cacheTask = Task(timeout: .seconds(1)) {
                await refresh.value
            }

            do {
                try await cacheTask.value
            } catch is TaskTimeoutError {
                Logger.default.notice("holzBar Shelf shown with the cached images: the refresh took longer than 1 s")
            } catch {
                Logger.default.error("Cache update failed when showing HolzBarShelfPanel - \(error, privacy: .private)")
            }
        }

        // A close (or another show) while the caches updated wins: ordering the panel
        // front now would leave it on screen with no section, which nothing can dismiss.
        guard generation == showGeneration, currentSection == section else {
            return false
        }

        let colorManager = colorManagerForShowing()
        transparency.start()
        // The style and the anchor come first: the panel is placed as soon as it has a size.
        style = general.shelfStyle
        anchor = getAnchor(for: general.shelfLocation, screen: screen)
        // The closed applications are read only with the setting on, and only now, as the
        // Shelf opens. The fold belongs to the Shelf of the hidden section.
        let closedApps = general.shelfShowsClosedApps ? HolzBarShelfClosedAppList.read() : .none
        let opensFold = section == .hidden
            && general.shelfAlwaysHiddenFold.opensFold(wasLeftOpen: general.shelfAlwaysHiddenFoldOpen)
        contentView = HolzBarShelfHostingView(
            appState: appState,
            colorManager: colorManager,
            transparency: transparency,
            screen: screen,
            section: section,
            style: style,
            closedApps: closedApps,
            opensFold: opensFold
        )

        updateOrigin(for: screen)

        // Color manager must be updated after updating the panel's origin,
        // but before it is shown.
        //
        // Color manager handles frame changes automatically, but does so on
        // the main queue, so we need to update manually once before showing
        // the panel to prevent the color from flashing.
        if #available(macOS 27.0, *) {
            colorManager.setColor27()
        } else {
            colorManager.updateAllProperties(with: frame, screen: screen)
        }

        fadeIn(appState: appState)
        if acceptsKeyboard {
            makeKey()
        }
        if ScreenRecordingAccess.shouldOfferOnce(appState) {
            // The first time the Shelf opens, a window offers Screen Recording. The Shelf closes
            // first: it would cover the window, and a click on its icon opens it again.
            Task {
                hide()
                ScreenRecordingAccess.offerOnce(for: .shelf, appState: appState)
            }
        }
        if #available(macOS 27.0, *) {
            let elapsed = (ContinuousClock.now - requestedAt).components
            let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
            Logger.default.notice("holzBar Shelf shown \(milliseconds, privacy: .public) ms after it was requested")
        }
        return true
    }

    /// Orders the panel front, playing the animation of the chosen style: a fade, and for the
    /// smooth style also a slide of the content out from under the menu bar. Reduce Motion
    /// plays none. Closing is never delayed: the panel is gone at once.
    private func fadeIn(appState: AppState) {
        let plan = ShelfAnimation.plan(
            style: appState.settings.general.revealAnimationStyle,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        guard !plan.isInstant else {
            alphaValue = 1
            orderFrontRegardless()
            return
        }
        alphaValue = plan.fadeDuration > 0 ? 0 : 1
        orderFrontRegardless()
        if plan.fadeDuration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = plan.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        }
        if plan.slideDistance > 0, let layer = contentView?.layer {
            // The content starts above its place, where the panel clips it, and slides down:
            // it comes out from under the menu bar. The animation moves the layer's picture
            // only, so the panel's frame, which holds the placement, is never touched.
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = plan.slideDistance
            slide.toValue = 0
            slide.duration = max(plan.fadeDuration, 0.05)
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(slide, forKey: "holzBarShelfSlide")
        }
    }

    /// Hides the panel.
    func hide() {
        if
            let name = currentSection,
            let section = appState?.menuBarManager.section(withName: name)
        {
            section.hide()
        }
        close()
    }

    override func close() {
        super.close()
        transparency.stop()
        showGeneration += 1
        contentView = nil
        currentSection = nil
        anchor = nil
        acceptsKeyboard = false
        listsAlwaysHidden = false
        appState?.navigationState.isShelfPresented = false
    }
}

// MARK: - HolzBarShelfHostingView

private final class HolzBarShelfHostingView: NSHostingView<HolzBarShelfContentView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }

    init(
        appState: AppState,
        colorManager: HolzBarShelfColorManager,
        transparency: TransparencyObserver,
        screen: NSScreen,
        section: MenuBarSection.Name,
        style: HolzBarShelfStyle,
        closedApps: HolzBarShelfClosedAppList,
        opensFold: Bool
    ) {
        let rootView = HolzBarShelfContentView(
            appState: appState,
            colorManager: colorManager,
            transparency: transparency,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section,
            style: style,
            closedApps: closedApps,
            opensFold: opensFold
        )
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: HolzBarShelfContentView) {
        fatalError("init(rootView:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - HolzBarShelfContentView

private struct HolzBarShelfContentView: View {
    var appState: AppState
    var colorManager: HolzBarShelfColorManager
    var transparency: TransparencyObserver
    var itemManager: MenuBarItemManager
    var imageCache: MenuBarItemImageCache
    var menuBarManager: MenuBarManager
    @State private var frame = CGRect.zero
    @State private var scrollIndicatorsFlashTrigger = 0
    /// The tile the arrows highlight, while the Shelf takes keys.
    @State private var highlightedID: String?
    /// What was typed to find an item.
    @State private var find = ShelfFind()
    /// Whether the fold of the always-hidden items is open.
    @State private var isFoldOpen: Bool
    /// Where the tiles are on the screen, read while a tile is dragged.
    @State private var registry = HolzBarShelfTileRegistry()
    @FocusState private var hasKeyboardFocus: Bool

    let screen: NSScreen
    let section: MenuBarSection.Name
    /// How the Shelf sits relative to the menu bar, as it was when the Shelf opened.
    let style: HolzBarShelfStyle
    /// The applications that are not running, read as the Shelf opened.
    let closedApps: HolzBarShelfClosedAppList

    init(
        appState: AppState,
        colorManager: HolzBarShelfColorManager,
        transparency: TransparencyObserver,
        itemManager: MenuBarItemManager,
        imageCache: MenuBarItemImageCache,
        menuBarManager: MenuBarManager,
        screen: NSScreen,
        section: MenuBarSection.Name,
        style: HolzBarShelfStyle,
        closedApps: HolzBarShelfClosedAppList,
        opensFold: Bool
    ) {
        self.appState = appState
        self.colorManager = colorManager
        self.transparency = transparency
        self.itemManager = itemManager
        self.imageCache = imageCache
        self.menuBarManager = menuBarManager
        self.screen = screen
        self.section = section
        self.style = style
        self.closedApps = closedApps
        _isFoldOpen = State(initialValue: opensFold)
    }

    /// The visible items that the notch covers, which the Shelf of the hidden section lists too.
    private var coveredItems: [MenuBarItem] {
        guard
            section == .hidden,
            appState.settings.general.showsNotchOverflowInShelf,
            let notch = screen.frameOfNotch
        else {
            return []
        }
        // Visible items under the notch cannot be seen or clicked, so the bar
        // offers them too (jordanbaird/Ice#227, jordanbaird/Ice#570). The
        // horizontal coordinates of item bounds and screen frames agree.
        return itemManager.itemCache[.visible].filter { item in
            !item.isControlItem &&
            item.bounds.maxX > notch.minX &&
            item.bounds.minX < notch.maxX &&
            !isShownByNativeOverflow(item)
        }
    }

    /// What the Shelf shows now: its tiles, and the items and applications they stand for.
    private struct Contents {
        var tiles = [ShelfTile]()
        var items = [UInt32: MenuBarItem]()
    }

    /// The Shelf of the hidden section lists the covered items, the hidden ones and, behind a
    /// fold, the always-hidden ones; the Shelf of the always-hidden section lists only those.
    /// While something is typed the fold counts as open, so a search reaches every item.
    private var contents: Contents {
        var contents = Contents()
        var input = ShelfContents.Input()
        func shelfItems(_ items: [MenuBarItem]) -> [ShelfContents.Item] {
            items.map { item in
                contents.items[item.windowID] = item
                return ShelfContents.Item(windowID: item.windowID, name: item.displayName)
            }
        }
        input.covered = shelfItems(coveredItems)
        switch section {
        case .hidden:
            input.hidden = shelfItems(itemManager.itemCache[.hidden])
            if appState.settings.advanced.enableAlwaysHiddenSection {
                input.alwaysHidden = shelfItems(itemManager.itemCache[.alwaysHidden])
                input.closedAlwaysHidden = closedApps.alwaysHidden.map(\.app)
            }
            input.closedHidden = closedApps.hidden.map(\.app)
            input.hiddenSystemItems = hiddenSystemItems
            input.foldsAlwaysHidden = true
            input.isFoldOpen = isFoldOpen || find.isActive
        case .alwaysHidden:
            input.alwaysHidden = shelfItems(itemManager.itemCache[.alwaysHidden])
            input.closedAlwaysHidden = closedApps.alwaysHidden.map(\.app)
        case .visible:
            break
        }
        input.showsDividers = layout == .row
        input.closedFirst = layout == .row
        contents.tiles = ShelfContents.tiles(input)
        return contents
    }

    /// The system items the user hid with Apple Items (macOS 27), in the bar's order. macOS
    /// draws no picture of a concealed item, so the Shelf lists a symbol tile for each.
    private var hiddenSystemItems: [ShelfContents.SystemItem] {
        guard AppleItems.isSupported else {
            return []
        }
        return SystemItems27.inBarOrder(appState.appleItems.concealedSystemItems(in: appState)).map { item in
            ShelfContents.SystemItem(key: SystemItems27.concealedKey(for: item), name: Self.name(of: item))
        }
    }

    /// The name of a system item, for its tile's tooltip, VoiceOver label and search.
    private static func name(of item: SystemItem27) -> String {
        switch item {
        case .battery: String(localized: "Battery")
        case .clock: String(localized: "Clock")
        case .wifi: String(localized: "Wi-Fi")
        case .controlCentre: String(localized: "Control Center")
        }
    }

    /// Whether macOS 27 shows the item itself, in its own expanded overflow, so the Shelf would
    /// list it twice (Phase 22); never on earlier macOS and never in doubt.
    private func isShownByNativeOverflow(_ item: MenuBarItem) -> Bool {
        guard #available(macOS 27.0, *) else {
            return false
        }
        return appState.concealer27.nativeOverflow.shelfOmits(
            itemFrame: item.bounds, isDrawn: item.isOnScreen, onDisplay: screen.displayID
        )
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
    }

    private var layout: ShelfLayout {
        appState.settings.general.shelfLayout
    }

    private var horizontalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return 3
        }
        return configuration.hasRoundedShape ? 7 : 5
    }

    private var verticalPadding: CGFloat {
        if #available(macOS 26.0, *) {
            return screen.hasNotch && configuration.hasRoundedShape ? 2 : 0
        }
        return screen.hasNotch ? 0 : 2
    }

    private var contentHeight: CGFloat? {
        guard let menuBarHeight = screen.getMenuBarHeight() else {
            return nil
        }
        if configuration.shapeKind != .noShape && configuration.isInset && screen.hasNotch {
            return menuBarHeight - appState.appearanceManager.menuBarInsetAmount * 2
        }
        return menuBarHeight
    }

    /// The height of the bar itself: the content less the transparent insets that hold the
    /// shadow of the floating style.
    private var barHeight: CGFloat {
        let insets = HolzBarShelfPlacement.floatingInsets
        return style == .floating ? max(frame.height - insets.top - insets.bottom, 0) : frame.height
    }

    /// The Shelf's drag state, which the panel owns so the drag tap can set it.
    private var dragModel: HolzBarShelfDragModel {
        menuBarManager.shelfPanel.dragModel
    }

    private var clipShape: some InsettableShape {
        if style == .floating {
            // A capsule for one row, a rounded panel for a grid or a column.
            RoundedRectangle(
                cornerRadius: HolzBarShelfPlacement.floatingCornerRadius(forHeight: barHeight),
                style: .continuous
            )
        } else if configuration.hasRoundedShape {
            RoundedRectangle(cornerRadius: frame.height / 2, style: .circular)
        } else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: frame.height / 4, style: .continuous)
        } else {
            RoundedRectangle(cornerRadius: frame.height / 5, style: .continuous)
        }
    }

    /// How the Shelf is drawn under the system's Reduce Transparency and Increase Contrast.
    private var treatment: TransparencyTreatment {
        .shelf(options: transparency.options, hasConfiguredBorder: configuration.current.hasBorder)
    }

    /// The colour of the Shelf's background.
    ///
    /// While Reduce Transparency or Increase Contrast is on, the same colour with its alpha
    /// forced to 1. The Shelf's background is opaque today (a flat window background colour
    /// on macOS 27, the average of a capture before), so this makes the guarantee explicit
    /// and changes no look.
    private var backgroundColorInfo: MenuBarAverageColorInfo? {
        guard
            treatment.fill == .opaque,
            var info = colorManager.colorInfo,
            let opaque = info.color.copy(alpha: 1)
        else {
            return colorManager.colorInfo
        }
        info.color = opaque
        return info
    }

    /// The line drawn around the Shelf: the visible one the treatment asks for, else the
    /// one the user configured, else none.
    ///
    /// A configured border follows the fill the appearance chose (`borderFill`): its colour,
    /// the accent colour or a gradient, from leading to trailing or from top to bottom.
    private var border: (width: CGFloat, style: AnyShapeStyle)? {
        if treatment.border == .visible {
            return (TransparencyTreatment.visibleBorderWidth, AnyShapeStyle(Color.primary.opacity(treatment.borderOpacity)))
        }
        guard configuration.current.hasBorder else {
            return nil
        }
        let width = configuration.current.borderWidth
        let borderColor = Color(cgColor: configuration.current.borderColor)
        switch configuration.current.style.borderFill {
        case .color:
            return (width, AnyShapeStyle(borderColor))
        case .accentColor:
            return (width, AnyShapeStyle(Color.accentColor))
        case .gradient:
            let gradient = configuration.current.borderGradient
            guard !gradient.stops.isEmpty else {
                return (width, AnyShapeStyle(borderColor))
            }
            let isVertical = configuration.current.style.gradientDirection == .vertical
            return (
                width,
                AnyShapeStyle(
                    LinearGradient(
                        gradient: gradient.swiftUIGradient,
                        startPoint: isVertical ? .top : .leading,
                        endPoint: isVertical ? .bottom : .trailing
                    )
                )
            )
        }
    }

    /// The space around the bar inside the panel: it holds the shadow. The floating bar's top
    /// has none, so the panel never reaches over the menu bar.
    private var panelInsets: EdgeInsets {
        switch style {
        case .attached:
            return EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
        case .floating:
            let insets = HolzBarShelfPlacement.floatingInsets
            return EdgeInsets(top: insets.top, leading: insets.leading, bottom: insets.bottom, trailing: insets.trailing)
        }
    }

    private var shadowOpacity: CGFloat {
        configuration.current.hasShadow ? 0.5 : 0.33
    }

    /// The Shelf's shadow: the one it always had when attached, the tight shadow of the
    /// design for the floating bar.
    private var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        switch style {
        case .attached:
            return (.black.opacity(shadowOpacity), 2.5, 0)
        case .floating:
            return (.black.opacity(HolzBarTheme.Shadow.barOpacity), HolzBarTheme.Shadow.barRadius, HolzBarTheme.Shadow.barOffsetY)
        }
    }

    var body: some View {
        ZStack {
            content
                .frame(height: layout == .row ? contentHeight : nil)
                .frame(minHeight: layout == .row ? nil : contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .menuBarItemContainer(appState: appState, colorInfo: backgroundColorInfo)
                .foregroundStyle(colorManager.colorInfo?.color.brightness ?? 0 > 0.67 ? .black : .white)
                .clipShape(clipShape)
                .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)

            if dragModel.isDropTargeted {
                // A dragged menu bar item is over the Shelf: the drop will hide its app.
                clipShape
                    .inset(by: HolzBarTheme.Spacing.dropOutline / 2)
                    .stroke(lineWidth: HolzBarTheme.Spacing.dropOutline)
                    .foregroundStyle(HolzBarTheme.Palette.accent)
                    .transition(.opacity)
            }

            if let border {
                clipShape
                    .inset(by: border.width / 2)
                    .stroke(lineWidth: border.width)
                    .foregroundStyle(border.style)
            } else if style == .floating {
                // A hairline, so a bar of nearly the colour of the window behind it still reads
                // as a bar. A visible or configured border replaces it.
                clipShape
                    .inset(by: HolzBarTheme.Spacing.hairline / 2)
                    .stroke(HolzBarTheme.Palette.stroke, lineWidth: HolzBarTheme.Spacing.hairline)
            }
        }
        .animation(
            HolzBarTheme.Motion.resolved(
                HolzBarTheme.Motion.snappy,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ),
            value: dragModel.isDropTargeted
        )
        .padding(panelInsets)
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
        .focusable(menuBarManager.shelfPanel.acceptsKeyboard)
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(phases: [.down, .repeat]) { press in
            handleKey(press)
        }
        .onChange(of: isFoldOpen || find.isActive) { _, isListed in
            // The pictures of the always-hidden items are captured once they are listed.
            guard section == .hidden, appState.settings.advanced.enableAlwaysHiddenSection else {
                return
            }
            menuBarManager.shelfPanel.listsAlwaysHidden = isListed
            if isListed {
                Task {
                    await imageCache.updateCache()
                }
            }
        }
        .onAppear {
            guard menuBarManager.shelfPanel.acceptsKeyboard else {
                return
            }
            hasKeyboardFocus = true
            let navigable = contents.tiles.filter(\.isNavigable)
            highlightedID = (layout == .row ? navigable.last : navigable.first)?.id
        }
    }

    // MARK: Keyboard

    /// Whether typing finds an item: the setting is on and the Shelf takes the keyboard.
    private var findsByTyping: Bool {
        appState.settings.general.shelfFindsByTyping && menuBarManager.shelfPanel.acceptsKeyboard
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .leftArrow:
            return moveHighlight(.left)
        case .rightArrow:
            return moveHighlight(.right)
        case .upArrow:
            return moveHighlight(.up)
        case .downArrow:
            return moveHighlight(.down)
        case .return, .space:
            return openHighlightedTile()
        case .escape:
            menuBarManager.section(withName: section)?.hide()
            return .handled
        case .delete:
            return deleteLastCharacter()
        default:
            return typeCharacters(press)
        }
    }

    /// Adds the typed characters to the query and highlights the best match.
    private func typeCharacters(_ press: KeyPress) -> KeyPress.Result {
        guard
            findsByTyping,
            press.modifiers.isDisjoint(with: [.command, .control]),
            find.type(press.characters)
        else {
            return .ignored
        }
        highlightBestMatch()
        return .handled
    }

    private func deleteLastCharacter() -> KeyPress.Result {
        guard findsByTyping, find.deleteLast() else {
            return .ignored
        }
        highlightBestMatch()
        return .handled
    }

    private func highlightBestMatch() {
        highlightedID = find.matches(in: contents.tiles).first
    }

    /// Moves the highlight one tile to the left or right, or one row up or down. While
    /// something is typed it steps through the matches instead: left and up go back toward the
    /// best one, right and down on.
    private func moveHighlight(_ step: ShelfLayoutPlan.Step) -> KeyPress.Result {
        let tiles = contents.tiles
        let navigable = tiles.filter(\.isNavigable)
        guard !navigable.isEmpty else {
            return .ignored
        }
        if find.isActive {
            let offset = (step == .left || step == .up) ? -1 : 1
            highlightedID = ShelfFind.step(from: highlightedID, by: offset, in: find.matches(in: tiles))
            return .handled
        }
        guard let current = navigable.firstIndex(where: { $0.id == highlightedID }) else {
            // Nothing is highlighted yet: the first key lands on the end the Shelf starts from.
            highlightedID = (layout == .row ? navigable.last : navigable.first)?.id
            return .handled
        }
        if let index = ShelfLayoutPlan.target(from: current, step: step, count: navigable.count, layout: layout) {
            highlightedID = navigable[index].id
        }
        return .handled
    }

    /// Opens the highlighted tile through the same path as a click.
    private func openHighlightedTile() -> KeyPress.Result {
        let contents = contents
        guard let tile = contents.tiles.first(where: { $0.id == highlightedID }) else {
            return .ignored
        }
        activate(tile, in: contents)
        return .handled
    }

    /// What a click on a tile does: an item opens its menu, a closed application launches and
    /// the fold opens or closes.
    private func activate(_ tile: ShelfTile, in contents: Contents) {
        switch tile.kind {
        case .item(let windowID):
            guard let item = contents.items[windowID] else {
                return
            }
            HolzBarShelfActions.open(item, mouseButton: .left, section: section, itemManager: itemManager, menuBarManager: menuBarManager)
        case .closedApp(let bundleID):
            guard let entry = closedApps.entry(forBundleIdentifier: bundleID) else {
                return
            }
            HolzBarShelfActions.launch(entry, section: section, menuBarManager: menuBarManager)
        case .systemItem(let key):
            openSystemItem(forKey: key)
        case .fold:
            toggleFold()
        case .divider:
            break
        }
    }

    /// Closes the Shelf and opens the system item a tile stands for.
    private func openSystemItem(forKey key: String) {
        guard let item = SystemItems27.item(forConcealedKey: key) else {
            return
        }
        HolzBarShelfActions.openSystemItem(item, section: section, appState: appState, menuBarManager: menuBarManager)
    }

    private func toggleFold() {
        isFoldOpen.toggle()
        // The setting decides whether the next Shelf starts this way.
        appState.settings.general.shelfAlwaysHiddenFoldOpen = isFoldOpen
    }

    // MARK: Drag

    /// The axis along which the tiles follow each other.
    private var dropAxis: ShelfDrop.Axis {
        layout == .column ? .vertical : .horizontal
    }

    /// The steps of a drag for a tile, or `nil` when it cannot be dragged: only an item of the
    /// hidden or always-hidden section that holzBar can move is dragged.
    private func dragActions(for tile: ShelfTile, item: MenuBarItem, image: NSImage?) -> HolzBarShelfDragActions? {
        guard appState.settings.general.shelfDragsTiles, tile.group != .visible, item.isMovable else {
            return nil
        }
        return HolzBarShelfDragActions(
            image: image,
            canBegin: {
                // An application that does not answer cannot be moved, as in the Layout pane.
                guard !Bridging.isProcessUnresponsive(item.sourcePID ?? item.ownerPID) else {
                    NSSound.beep()
                    return false
                }
                return true
            },
            began: {
                dragModel.draggedID = tile.id
                dragModel.outcome = .none
                // A profile bound to a display or a Space waits until the drop.
                appState.profiles.isLayoutDragInProgress = true
            },
            moved: {
                let outcome = dropOutcome(dragging: tile)
                if outcome != dragModel.outcome {
                    dragModel.outcome = outcome
                }
            },
            ended: {
                let outcome = dropOutcome(dragging: tile)
                dragModel.draggedID = nil
                dragModel.outcome = .none
                appState.profiles.isLayoutDragInProgress = false
                perform(outcome, dragging: tile)
            }
        )
    }

    /// What releasing the dragged tile at the pointer would do now.
    private func dropOutcome(dragging dragged: ShelfTile) -> ShelfDrop.Outcome {
        let panel = menuBarManager.shelfPanel
        guard let screen = panel.screen else {
            return .none
        }
        func role(_ tile: ShelfTile) -> ShelfDrop.Role {
            switch tile.kind {
            case .item: .item
            case .fold: .fold
            case .closedApp, .systemItem, .divider: .other
            }
        }
        let dropTiles: [ShelfDrop.Tile] = contents.tiles.compactMap { tile in
            registry.screenFrame(of: tile.id).map {
                ShelfDrop.Tile(id: tile.id, group: tile.group, role: role(tile), frame: .init($0))
            }
        }
        guard let draggedTile = dropTiles.first(where: { $0.id == dragged.id }) else {
            return .none
        }
        let pointer = NSEvent.mouseLocation
        return ShelfDrop.outcome(
            pointer: .init(x: pointer.x, y: pointer.y),
            dragged: draggedTile,
            tiles: dropTiles,
            panel: .init(panel.frame),
            screen: .init(screen.frame),
            axis: dropAxis,
            // macOS 27 puts the items of a section in order itself.
            ordersItems: itemManager.backend.canMoveItems
        )
    }

    /// Makes the move a drop asks for, through the same calls as the Menu Bar Layout pane.
    private func perform(_ outcome: ShelfDrop.Outcome, dragging dragged: ShelfTile) {
        let contents = contents
        guard case .item(let windowID) = dragged.kind, let item = contents.items[windowID] else {
            return
        }
        switch outcome {
        case .none:
            break
        case .menuBar:
            LayoutBarMoves.setSection(of: item, to: .visible, appState: appState)
        case .section(let group):
            guard let name = MenuBarSection.Name(group) else {
                return
            }
            LayoutBarMoves.setSection(of: item, to: name, appState: appState)
        case .beside(let id, let side):
            guard
                let target = contents.tiles.first(where: { $0.id == id }),
                case .item(let targetID) = target.kind,
                let targetItem = contents.items[targetID]
            else {
                return
            }
            LayoutBarMoves.move(
                item,
                to: side == .before ? .leftOfItem(targetItem) : .rightOfItem(targetItem),
                appState: appState,
                actionName: String(localized: "Move \(item.displayName)")
            )
        }
    }

    /// How a drag in progress shows its drop on a tile.
    private func dropIndication(for tile: ShelfTile) -> HolzBarShelfDropIndication? {
        guard dragModel.draggedID != nil, tile.id != dragModel.draggedID else {
            return nil
        }
        switch dragModel.outcome {
        case .beside(let id, let side):
            guard id == tile.id else {
                return nil
            }
            return side == .before ? .before : .after
        case .section(let group):
            return tile.group == group && tile.isNavigable ? .onto : nil
        case .none, .menuBar:
            return nil
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            Text("holzBar cannot display menu bar items for automatically hidden menu bars")
                .padding(.horizontal, 10)
        } else if itemManager.itemCache.managedItems.isEmpty {
            HStack {
                Text("Loading menu bar items…")
                ProgressView()
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
        } else if ScreenRecordingAccess.isGranted(appState), imageCache.cacheFailed(for: section) {
            Text("Unable to display menu bar items")
                .padding(.horizontal, 10)
        } else {
            // Without Screen Recording the items show their apps' icons (or the images chosen
            // for them); the first time the Shelf opens, a window offers their real pictures (see `show(section:on:)`).
            findAndTiles
                // Leaving for the menu bar: the Shelf steps back.
                .opacity(dragModel.outcome == .menuBar ? 0.55 : 1)
        }
    }

    /// The field that shows what was typed, if the Shelf takes the keyboard, and the tiles.
    @ViewBuilder
    private var findAndTiles: some View {
        let contents = contents
        let matches = find.matches(in: contents.tiles)
        switch layout {
        case .row:
            HStack(spacing: 0) {
                if findsByTyping {
                    HolzBarShelfFindView(query: find.query, hasMatches: !matches.isEmpty)
                }
                tilesScrollView(contents, matches: Set(matches))
            }
        case .grid, .column:
            VStack(alignment: .leading, spacing: 0) {
                if findsByTyping {
                    HolzBarShelfFindView(query: find.query, hasMatches: !matches.isEmpty)
                        .frame(minHeight: contentHeight)
                }
                tilesScrollView(contents, matches: Set(matches))
            }
        }
    }

    @ViewBuilder
    private func tilesScrollView(_ contents: Contents, matches: Set<String>) -> some View {
        switch layout {
        case .row:
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(contents.tiles) { tile in
                        tileView(tile, in: contents, matches: matches)
                    }
                }
            }
            .environment(\.isScrollEnabled, frame.width == screen.frame.width)
            .defaultScrollAnchor(.trailing)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        case .grid, .column:
            // More rows than fit scroll; the Shelf is as tall as its rows, up to a limit.
            let rows = ShelfLayoutPlan.rows(of: contents.tiles, layout: layout)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.first?.id) { row in
                        HStack(spacing: 0) {
                            ForEach(row) { tile in
                                tileView(tile, in: contents, matches: matches)
                            }
                        }
                        .frame(minHeight: contentHeight)
                    }
                }
            }
            .frame(maxHeight: (contentHeight ?? 24) * CGFloat(ShelfLayoutPlan.visibleRows))
            .fixedSize(horizontal: true, vertical: rows.count <= ShelfLayoutPlan.visibleRows)
            .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
            .task {
                scrollIndicatorsFlashTrigger += 1
            }
        }
    }

    @ViewBuilder
    private func tileView(_ tile: ShelfTile, in contents: Contents, matches: Set<String>) -> some View {
        let isHighlighted = tile.id == highlightedID
        // While something is typed, the tiles that do not match step back.
        let isDimmed = find.isActive && tile.isSearchable && !matches.contains(tile.id)
        switch tile.kind {
        case .item(let windowID):
            if let item = contents.items[windowID] {
                HolzBarShelfItemView(
                    imageCache: imageCache,
                    itemManager: itemManager,
                    menuBarManager: menuBarManager,
                    registry: registry,
                    item: item,
                    section: section,
                    tileID: tile.id,
                    isHighlighted: isHighlighted,
                    isDimmed: isDimmed,
                    dropIndication: dropIndication(for: tile),
                    axis: dropAxis,
                    drag: dragActions(for: tile, item: item, image: itemImage(item))
                )
            }
        case .fold(let count, let isOpen):
            HolzBarShelfFoldView(
                registry: registry,
                count: count,
                isOpen: isOpen,
                tileID: tile.id,
                isHighlighted: isHighlighted,
                dropIndication: dropIndication(for: tile),
                toggle: { toggleFold() }
            )
        case .closedApp(let bundleID):
            if let entry = closedApps.entry(forBundleIdentifier: bundleID) {
                HolzBarShelfClosedAppView(
                    registry: registry,
                    entry: entry,
                    tileID: tile.id,
                    isHighlighted: isHighlighted,
                    isDimmed: isDimmed,
                    dropIndication: dropIndication(for: tile),
                    launch: {
                        HolzBarShelfActions.launch(entry, section: section, menuBarManager: menuBarManager)
                    }
                )
            }
        case .systemItem(let key):
            if let item = SystemItems27.item(forConcealedKey: key) {
                HolzBarShelfSystemItemView(
                    registry: registry,
                    symbolName: item.symbolName,
                    name: tile.name,
                    tileID: tile.id,
                    isHighlighted: isHighlighted,
                    isDimmed: isDimmed,
                    dropIndication: dropIndication(for: tile),
                    open: { openSystemItem(forKey: key) }
                )
            }
        case .divider:
            HolzBarShelfDividerView()
        }
    }

    /// The picture of an item that follows the pointer while it is dragged.
    private func itemImage(_ item: MenuBarItem) -> NSImage? {
        let captured = imageCache.images[item.tag]?.nsImage
        guard let iconStore = itemManager.appState?.itemIconStore else {
            return captured
        }
        return iconStore.image(for: item, captured: captured)
    }
}

// MARK: - Placement conversions

private extension HolzBarShelfPlacement.Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

private extension MenuBarSection.Name {
    /// The section a group of tiles stands for; `nil` for the visible items the notch covers,
    /// which are no section of the Shelf.
    init?(_ group: ShelfGroup) {
        switch group {
        case .visible: return nil
        case .hidden: self = .hidden
        case .alwaysHidden: self = .alwaysHidden
        }
    }
}
