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

    /// The currently displayed section.
    private(set) var currentSection: MenuBarSection.Name?

    /// The horizontal position the panel centres on, chosen once when it opens, so a resize
    /// while it is open does not move it to the mouse pointer or the holzBar icon.
    private var anchorX: CGFloat?

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

    /// Returns the horizontal position to centre the panel on for the given location
    /// setting, read from the mouse pointer and the holzBar icon as they are now.
    private func getAnchorX(for shelfLocation: HolzBarShelfLocation, screen: NSScreen) -> CGFloat {
        guard let appState else {
            return screen.frame.maxX
        }

        switch shelfLocation {
        case .dynamic:
            if appState.hidEventManager.isMouseInsideEmptyMenuBarSpace(appState: appState, screen: screen) {
                return getAnchorX(for: .mousePointer, screen: screen)
            }
            return getAnchorX(for: .holzBarIcon, screen: screen)
        case .mousePointer:
            guard let location = MouseHelpers.locationAppKit else {
                return getAnchorX(for: .holzBarIcon, screen: screen)
            }
            return location.x
        case .holzBarIcon:
            guard
                let controlItem = appState.itemManager.itemCache.managedItems.first(matching: .visibleControlItem),
                // Bridging API is more reliable than controlItem.frame in some
                // cases (like if the item is offscreen).
                let itemBounds = Bridging.getWindowBounds(for: controlItem.windowID)
            else {
                // Centring on the screen's right edge puts the panel at the right of the screen.
                return screen.frame.maxX
            }
            return itemBounds.midX
        }
    }

    /// Updates the panel's frame origin for display on the given screen, centred on the
    /// anchor chosen when it opened.
    private func updateOrigin(for screen: NSScreen) {
        let menuBarHeight = screen.getMenuBarHeight() ?? 0
        let originY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

        let lowerBound = screen.frame.minX
        let upperBound = screen.frame.maxX - frame.width

        guard let anchorX, lowerBound <= upperBound else {
            setFrameOrigin(CGPoint(x: upperBound, y: originY))
            return
        }

        setFrameOrigin(CGPoint(x: (anchorX - frame.width / 2).clamped(to: lowerBound...upperBound), y: originY))
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
                await appState.imageCache.updateCache()
            }
        } else {
            // The refresh is its own task, so a timeout ends only the wait: the refresh still
            // lands in the observable caches. Awaiting `.value` does not pass the cancellation on.
            let refresh = Task {
                await appState.itemManager.cacheItemsIfNeeded()
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
        contentView = HolzBarShelfHostingView(
            appState: appState,
            colorManager: colorManager,
            screen: screen,
            section: section
        )

        anchorX = getAnchorX(for: appState.settings.general.shelfLocation, screen: screen)
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

        orderFrontRegardless()
        if acceptsKeyboard {
            makeKey()
        }
        if #available(macOS 27.0, *) {
            let elapsed = (ContinuousClock.now - requestedAt).components
            let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
            Logger.default.notice("holzBar Shelf shown \(milliseconds, privacy: .public) ms after it was requested")
        }
        return true
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
        showGeneration += 1
        contentView = nil
        currentSection = nil
        anchorX = nil
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
        screen: NSScreen,
        section: MenuBarSection.Name
    ) {
        let rootView = HolzBarShelfContentView(
            appState: appState,
            colorManager: colorManager,
            itemManager: appState.itemManager,
            imageCache: appState.imageCache,
            menuBarManager: appState.menuBarManager,
            screen: screen,
            section: section
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
            item.bounds.minX < notch.maxX
        }
        return covered + sectionItems
    }

    private var configuration: MenuBarAppearanceConfigurationV2 {
        appState.appearanceManager.configuration
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

    private var shadowOpacity: CGFloat {
        configuration.current.hasShadow ? 0.5 : 0.33
    }

    var body: some View {
        ZStack {
            content
                .frame(height: contentHeight)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .menuBarItemContainer(appState: appState, colorInfo: colorManager.colorInfo)
                .foregroundStyle(colorManager.colorInfo?.color.brightness ?? 0 > 0.67 ? .black : .white)
                .clipShape(clipShape)
                .shadow(color: .black.opacity(shadowOpacity), radius: 2.5)

            if configuration.current.hasBorder {
                clipShape
                    .inset(by: configuration.current.borderWidth / 2)
                    .stroke(lineWidth: configuration.current.borderWidth)
                    .foregroundStyle(Color(cgColor: configuration.current.borderColor))
            }
        }
        .padding(5)
        .frame(maxWidth: screen.frame.width)
        .fixedSize()
        .onFrameChange(update: $frame)
        .focusable(menuBarManager.shelfPanel.acceptsKeyboard)
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            moveHighlight(by: -1)
        }
        .onKeyPress(.rightArrow) {
            moveHighlight(by: 1)
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
            highlightedWindowID = items.last?.windowID
        }
    }

    /// Moves the highlight to the item on the left (`-1`) or right (`1`).
    private func moveHighlight(by step: Int) -> KeyPress.Result {
        let items = items
        guard !items.isEmpty else {
            return .ignored
        }
        let current = items.firstIndex { $0.windowID == highlightedWindowID } ?? items.count
        let index = min(max(current + step, 0), items.count - 1)
        highlightedWindowID = items[index].windowID
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
            await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: shelfDisplayID)
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
            HStack(spacing: 0) {
                if !ScreenRecordingAccess.isGranted(appState) {
                    // Without Screen Recording the items show their apps' icons (or the
                    // images chosen for them); the hint offers their real pictures.
                    ScreenRecordingHint(feature: .shelf, appState: appState, isCompact: true) {
                        // The Shelf would cover the system prompt.
                        menuBarManager.section(withName: section)?.hide()
                    }
                    .padding(.horizontal, 10)
                }
                itemsScrollView
            }
        }
    }

    @ViewBuilder
    private var itemsScrollView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(items, id: \.windowID) { item in
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
        }
        .environment(\.isScrollEnabled, frame.width == screen.frame.width)
        .defaultScrollAnchor(.trailing)
        .scrollIndicatorsFlash(trigger: scrollIndicatorsFlashTrigger)
        .task {
            scrollIndicatorsFlashTrigger += 1
        }
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
                await itemManager.openItem(item, mouseButton: .left, shelfDisplayID: shelfDisplayID)
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
                await itemManager.openItem(item, mouseButton: .right, shelfDisplayID: shelfDisplayID)
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
            }
        }
        .accessibilityAddTraits(.isButton)
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
