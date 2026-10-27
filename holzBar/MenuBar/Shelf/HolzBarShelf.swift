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

    override var canBecomeKey: Bool { acceptsKeyboard }

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
        style = appState.settings.general.shelfStyle
        anchor = getAnchor(for: appState.settings.general.shelfLocation, screen: screen)
        contentView = HolzBarShelfHostingView(
            appState: appState,
            colorManager: colorManager,
            transparency: transparency,
            screen: screen,
            section: section,
            style: style
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

    /// Orders the panel front, fading it in when the setting is on and Reduce Motion is off.
    /// Closing is never delayed: the panel is gone at once.
    private func fadeIn(appState: AppState) {
        let duration = ShelfAnimation.fadeDuration(
            isEnabled: appState.settings.general.animatesShelf,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        guard duration > 0 else {
            alphaValue = 1
            orderFrontRegardless()
            return
        }
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().alphaValue = 1
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
        style: HolzBarShelfStyle
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
            style: style
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
    /// The item the arrows highlight, while the Shelf takes keys.
    @State private var highlightedWindowID: CGWindowID?
    @FocusState private var hasKeyboardFocus: Bool

    let screen: NSScreen
    let section: MenuBarSection.Name
    /// How the Shelf sits relative to the menu bar, as it was when the Shelf opened.
    let style: HolzBarShelfStyle

    private var items: [MenuBarItem] {
        let sectionItems = itemManager.itemCache[section]
        guard
            section == .hidden,
            appState.settings.general.showsNotchOverflowInShelf,
            let notch = screen.frameOfNotch
        else {
            return sectionItems
        }
        // Visible items under the notch cannot be seen or clicked, so the bar
        // offers them too (jordanbaird/Ice#227, jordanbaird/Ice#570). The
        // horizontal coordinates of item bounds and screen frames agree.
        let covered = itemManager.itemCache[.visible].filter { item in
            !item.isControlItem &&
            item.bounds.maxX > notch.minX &&
            item.bounds.minX < notch.maxX &&
            !isShownByNativeOverflow(item)
        }
        return covered + sectionItems
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

    private var clipShape: some InsettableShape {
        if configuration.hasRoundedShape {
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
                .shadow(color: .black.opacity(shadowOpacity), radius: 2.5)

            if let border {
                clipShape
                    .inset(by: border.width / 2)
                    .stroke(lineWidth: border.width)
                    .foregroundStyle(border.style)
            }
        }
        .padding(panelInsets)
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
        .focusable(menuBarManager.shelfPanel.acceptsKeyboard)
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            moveHighlight(.left)
        }
        .onKeyPress(.rightArrow) {
            moveHighlight(.right)
        }
        .onKeyPress(.upArrow) {
            moveHighlight(.up)
        }
        .onKeyPress(.downArrow) {
            moveHighlight(.down)
        }
        .onKeyPress(.return) {
            openHighlightedItem()
        }
        .onKeyPress(.space) {
            openHighlightedItem()
        }
        .onKeyPress(.escape) {
            menuBarManager.section(withName: section)?.hide()
            return .handled
        }
        .onAppear {
            guard menuBarManager.shelfPanel.acceptsKeyboard else {
                return
            }
            hasKeyboardFocus = true
            highlightedWindowID = (layout == .row ? items.last : items.first)?.windowID
        }
    }

    /// Moves the highlight one item to the left or right, or one row up or down.
    private func moveHighlight(_ step: ShelfLayoutPlan.Step) -> KeyPress.Result {
        let items = items
        guard !items.isEmpty else {
            return .ignored
        }
        guard let current = items.firstIndex(where: { $0.windowID == highlightedWindowID }) else {
            // Nothing is highlighted yet: the first key lands on the end the Shelf starts from.
            highlightedWindowID = (layout == .row ? items.last : items.first)?.windowID
            return .handled
        }
        if let index = ShelfLayoutPlan.target(from: current, step: step, count: items.count, layout: layout) {
            highlightedWindowID = items[index].windowID
        }
        return .handled
    }

    /// Opens the highlighted item through the same path as a click.
    private func openHighlightedItem() -> KeyPress.Result {
        guard let item = items.first(where: { $0.windowID == highlightedWindowID }) else {
            return .ignored
        }
        let shelfDisplayID = menuBarManager.shelfPanel.screen?.displayID
        menuBarManager.section(withName: section)?.hide()
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: shelfDisplayID, origin: .click)
        }
        return .handled
    }

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
            itemsScrollView
        }
    }

    @ViewBuilder
    private var itemsScrollView: some View {
        switch layout {
        case .row:
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(items, id: \.windowID) { item in
                        itemView(item)
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
            let rows = ShelfLayoutPlan.rows(of: items, layout: layout)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows, id: \.first?.windowID) { row in
                        HStack(spacing: 0) {
                            ForEach(row, id: \.windowID) { item in
                                itemView(item)
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

    private func itemView(_ item: MenuBarItem) -> some View {
        HolzBarShelfItemView(
            imageCache: imageCache,
            itemManager: itemManager,
            menuBarManager: menuBarManager,
            item: item,
            section: section,
            isHighlighted: item.windowID == highlightedWindowID
        )
    }
}

// MARK: - HolzBarShelfItemView

private struct HolzBarShelfItemView: View {
    var imageCache: MenuBarItemImageCache
    var itemManager: MenuBarItemManager
    var menuBarManager: MenuBarManager

    let item: MenuBarItem
    let section: MenuBarSection.Name
    /// Whether the arrows of the keyboard highlight the item.
    var isHighlighted = false

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let shelfDisplayID = menuBarManager.shelfPanel.screen?.displayID
            menuBarManager.section(withName: section)?.hide()
            Task {
                try? await Task.sleep(for: .milliseconds(25))
                await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: shelfDisplayID, origin: .click)
            }
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager] in
            guard let itemManager, let menuBarManager else {
                return
            }
            let shelfDisplayID = menuBarManager.shelfPanel.screen?.displayID
            menuBarManager.section(withName: section)?.hide()
            Task {
                try? await Task.sleep(for: .milliseconds(25))
                await itemManager.openItem(item, mouseButton: .right, shelfDisplayID: shelfDisplayID, origin: .click)
            }
        }
    }

    /// The item's chosen image, its picture or its app's icon (`ItemIconStore`).
    private var image: NSImage? {
        let captured = imageCache.images[item.tag]?.nsImage
        guard let iconStore = itemManager.appState?.itemIconStore else {
            return captured
        }
        return iconStore.image(for: item, captured: captured)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
            } else if item.displayName == MenuBarItem.fallbackDisplayName {
                // An item of an unknown app: a quiet symbol instead of the same words many times.
                Image(systemName: "app.dashed")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            } else {
                Text(item.displayName)
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }
        }
        .contentShape(Rectangle())
        .overlay {
            HolzBarShelfItemClickView(
                item: item,
                leftClickAction: leftClickAction,
                rightClickAction: rightClickAction
            )
        }
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    }
            }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityLabel(item.displayName)
        .accessibilityAction(.default, leftClickAction)
        .accessibilityAction(named: "Open", leftClickAction)
        .accessibilityAction(named: "Open Menu", rightClickAction)
    }
}

// MARK: - HolzBarShelfItemClickView

private struct HolzBarShelfItemClickView: NSViewRepresentable {
    private final class Represented: NSView {
        let item: MenuBarItem

        let leftClickAction: () -> Void
        let rightClickAction: () -> Void

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        init(
            item: MenuBarItem,
            leftClickAction: @escaping () -> Void,
            rightClickAction: @escaping () -> Void
        ) {
            self.item = item
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            super.init(frame: .zero)
            self.toolTip = item.displayName
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
        }

        override func rightMouseDown(with event: NSEvent) {
            super.rightMouseDown(with: event)
            lastRightMouseDownDate = .now
            lastRightMouseDownLocation = NSEvent.mouseLocation
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            leftClickAction()
        }

        override func rightMouseUp(with event: NSEvent) {
            super.rightMouseUp(with: event)
            guard
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }
    }

    let item: MenuBarItem

    let leftClickAction: () -> Void
    let rightClickAction: () -> Void

    func makeNSView(context: Context) -> NSView {
        Represented(
            item: item,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) { }
}

// MARK: - Placement conversions

private extension HolzBarShelfPlacement.Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}
