//
//  MenuBarManager.swift
//  holzBar
//

import Observation
import OSLog
import SwiftUI

/// Manager for the state of the menu bar.
@MainActor
@Observable
final class MenuBarManager {
    /// Information for the menu bar's average color.
    private(set) var averageColorInfo: MenuBarAverageColorInfo?

    /// A Boolean value that indicates whether the menu bar is either always hidden
    /// by the system, or automatically hidden and shown by the system based on the
    /// location of the mouse.
    private(set) var isMenuBarHiddenBySystem = false

    /// A Boolean value that indicates whether the menu bar is hidden by the system
    /// according to a value stored in UserDefaults.
    private(set) var isMenuBarHiddenBySystemUserDefaults = false

    /// A Boolean value that indicates whether the "ShowOnHover" feature is allowed.
    var showOnHoverAllowed = true

    /// Logger for the menu bar manager.
    @ObservationIgnored private let logger = Logger(category: "MenuBarManager")

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    /// Observers of other models.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// Key-value observers of the system.
    @ObservationIgnored private var keyValueObservations = [NSKeyValueObservation]()

    /// Updates the average colour while the Settings window is visible.
    @ObservationIgnored private var averageColorTask: Task<Void, Never>?

    /// A Boolean value that indicates whether the application menus are hidden.
    @ObservationIgnored private var isHidingApplicationMenus = false

    /// The panel that contains the holzBar Shelf interface.
    let shelfPanel = HolzBarShelfPanel()

    /// Whether the search panel was created before the setup, which then sets it up.
    @ObservationIgnored private var searchPanelNeedsSetup = false

    /// The panel that contains the menu bar search interface, created and set up the
    /// first time it is used.
    @ObservationIgnored private(set) lazy var searchPanel: MenuBarSearchPanel = {
        let panel = MenuBarSearchPanel()
        if let appState = self.appState {
            panel.performSetup(with: appState)
        } else {
            self.searchPanelNeedsSetup = true
        }
        return panel
    }()

    /// The panel that contains a portable version of the menu bar
    /// appearance editor interface
    let appearanceEditorPanel = MenuBarAppearanceEditorPanel()

    /// The managed sections in the menu bar.
    let sections = [
        MenuBarSection(name: .visible),
        MenuBarSection(name: .hidden),
        MenuBarSection(name: .alwaysHidden),
    ]

    /// A Boolean value that indicates whether at least one of the manager's
    /// sections is visible.
    var hasVisibleSection: Bool {
        sections.contains { !$0.isHidden }
    }

    /// Performs the initial setup of the menu bar manager.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
        shelfPanel.performSetup(with: appState)
        if searchPanelNeedsSetup {
            searchPanelNeedsSetup = false
            searchPanel.performSetup(with: appState)
        }
        appearanceEditorPanel.performSetup(with: appState)
        for section in sections {
            section.performSetup(with: appState)
        }
    }

    /// Configures the internal observers for the manager.
    private func configureObservers() {
        keyValueObservations.append(
            NSApp.observe(\.currentSystemPresentationOptions, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }
                    let options = NSApp.currentSystemPresentationOptions
                    let hidden = options.contains(.hideMenuBar) || options.contains(.autoHideMenuBar)
                    if isMenuBarHiddenBySystem != hidden {
                        isMenuBarHiddenBySystem = hidden
                    }
                }
            }
        )

        if
            let hiddenSection = section(withName: .alwaysHidden),
            let window = hiddenSection.controlItem.window
        {
            keyValueObservations.append(
                window.observe(\.frame, options: [.initial, .new]) { [weak self] window, _ in
                    Task { @MainActor in
                        self?.menuBarWindowFrameDidChange(originY: window.frame.origin.y)
                    }
                }
            )
        }

        // Handle the `focusedApp` rehide strategy.
        keyValueObservations.append(
            NSWorkspace.shared.observe(\.frontmostApplication, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.frontmostApplicationDidChange()
                }
            }
        )

        // The average colour is shown only in Settings, so it is updated every
        // 5 seconds only while the Settings window is visible (and once when it shows).
        if let navigationState = appState?.navigationState {
            observers.append(
                ObservationLoop.observe { navigationState.isSettingsPresented } onChange: { [weak self] isVisible in
                    self?.updateAverageColorTimer(isSettingsVisible: isVisible)
                }
            )
            updateAverageColorTimer(isSettingsVisible: navigationState.isSettingsPresented)
        }

        // Hide application menus when a section is shown (if applicable).
        observers.append(
            ObservationLoop.observe { [sections] in
                sections.map(\.controlItem.state)
            } onChange: { [weak self] _ in
                self?.sectionStatesDidChange()
            }
        )
    }

    /// The last origin of the always-hidden divider's window, so that only a move counts.
    @ObservationIgnored private var lastMenuBarWindowOriginY: CGFloat?

    /// Reads the system's menu bar hiding default again when the divider's window moves.
    private func menuBarWindowFrameDidChange(originY: CGFloat) {
        guard originY != lastMenuBarWindowOriginY else {
            return
        }
        lastMenuBarWindowOriginY = originY
        guard let isMenuBarHidden = Defaults.globalDomain["_HIHideMenuBar"] as? Bool else {
            return
        }
        if isMenuBarHiddenBySystemUserDefaults != isMenuBarHidden {
            isMenuBarHiddenBySystemUserDefaults = isMenuBarHidden
        }
    }

    /// Rehides the hidden section when the focused application changes, with the
    /// `focusedApp` rehide strategy.
    private func frontmostApplicationDidChange() {
        if
            let appState,
            case .focusedApp = appState.settings.general.rehideStrategy,
            let hiddenSection = section(withName: .hidden),
            let screen = appState.hidEventManager.bestScreen(appState: appState),
            !appState.hidEventManager.isMouseInsideMenuBar(appState: appState, screen: screen)
        {
            Task {
                try await Task.sleep(for: .seconds(0.1))
                hiddenSection.hide()
            }
        }
    }

    /// Starts or stops the 5 s average colour update with the Settings window's visibility.
    private func updateAverageColorTimer(isSettingsVisible: Bool) {
        averageColorTask?.cancel()
        averageColorTask = nil
        guard isSettingsVisible else {
            return
        }
        averageColorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateAverageColorInfo()
                try? await Task.sleep(for: .seconds(5), tolerance: .seconds(1))
            }
        }
    }

    /// Hides or shows the application menus after a section was shown or hidden.
    private func sectionStatesDidChange() {
        guard let appState else {
            return
        }

        // macOS 27 folds the items that do not fit behind its own overflow button,
        // so shown items never cover the application menus. Activating holzBar there only
        // took keyboard focus from the frontmost application (measured).
        if #available(macOS 27.0, *) {
            return
        }

        // Don't continue if:
        //   * The "HideApplicationMenus" setting isn't enabled.
        //   * Using the holzBar Shelf.
        //   * The menu bar is hidden by the system.
        //   * The active space is fullscreen.
        //   * The settings window is visible.
        guard
            appState.settings.advanced.hideApplicationMenus,
            !appState.settings.general.usesShelf,
            !isMenuBarHiddenBySystem,
            !appState.activeSpace.isFullscreen,
            !appState.navigationState.isSettingsPresented
        else {
            return
        }

        if sections.contains(where: { $0.controlItem.state == .showSection }) {
            guard let screen = NSScreen.main else {
                return
            }

            // Get the application menu frame for the display.
            guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
                return
            }

            Task {
                // Get all items.
                var items = await MenuBarItem.getMenuBarItems(on: screen.displayID, option: .activeSpace)

                // Filter the items down according to the currently enabled/shown sections.
                if
                    let alwaysHiddenSection = self.section(withName: .alwaysHidden),
                    alwaysHiddenSection.isEnabled
                {
                    if alwaysHiddenSection.controlItem.state == .hideSection {
                        if let alwaysHiddenControlItem = items.firstIndex(matching: .alwaysHiddenControlItem).map({ items.remove(at: $0) }) {
                            items.trimPrefix { $0.bounds.maxX <= alwaysHiddenControlItem.bounds.minX }
                        }
                    }
                } else {
                    if let hiddenControlItem = items.firstIndex(matching: .hiddenControlItem).map({ items.remove(at: $0) }) {
                        // Only while the hidden section is hidden are its items off
                        // the screen. Shown, they are the very items that may cover
                        // the application menus, and dropping them meant the menus
                        // were only ever hidden with the always-hidden section on
                        // (jordanbaird/Ice#434).
                        if self.section(withName: .hidden)?.controlItem.state == .hideSection {
                            items.trimPrefix { $0.bounds.maxX <= hiddenControlItem.bounds.minX }
                        }
                    }
                }

                // Get the leftmost item on the screen.
                guard let leftmostItem = items.min(by: { $0.bounds.minX < $1.bounds.minX }) else {
                    return
                }

                // If the minX of the item is less than or equal to the maxX of the
                // application menu frame, activate the app to hide the menu.
                if leftmostItem.bounds.minX <= applicationMenuFrame.maxX {
                    self.hideApplicationMenus()
                }
            }
        } else if isHidingApplicationMenus {
            showApplicationMenus()
        }
    }

    /// Updates the ``averageColorInfo`` property with the current average color
    /// of the menu bar.
    func updateAverageColorInfo() {
        guard
            let settingsWindow = appState?.navigationState.settingsWindow,
            settingsWindow.isVisible,
            let screen = settingsWindow.screen
        else {
            return
        }

        if #available(macOS 27.0, *) {
            let info = MenuBarAverageColorInfo(color: HolzBarShelfColorManager.flatColor27(), source: .menuBarWindow)
            if averageColorInfo != info {
                averageColorInfo = info
            }
            return
        }

        // Nothing captures the screen before Screen Recording is granted; the previous
        // colour stays.
        guard ScreenCapture.cachedCheckPermissions() else {
            return
        }

        let windows = WindowInfo.createWindows(option: .onScreen)
        let displayID = screen.displayID

        guard
            let menuBarWindow = WindowInfo.menuBarWindow(from: windows, for: displayID),
            let wallpaperWindow = WindowInfo.wallpaperWindow(from: windows, for: displayID)
        else {
            return
        }

        guard
            let image = ScreenCapture.captureWindows(
                with: [menuBarWindow.windowID, wallpaperWindow.windowID],
                screenBounds: withMutableCopy(of: wallpaperWindow.bounds) { $0.size.height = 1 },
                option: .nominalResolution
            ),
            let color = image.averageColor(option: .ignoreAlpha)
        else {
            return
        }

        let info = MenuBarAverageColorInfo(color: color, source: .menuBarWindow)

        if averageColorInfo != info {
            averageColorInfo = info
        }
    }

    /// Returns a Boolean value that indicates whether the given display
    /// has a valid menu bar.
    func hasValidMenuBar(in windows: [WindowInfo], for display: CGDirectDisplayID) -> Bool {
        guard
            let window = WindowInfo.menuBarWindow(from: windows, for: display),
            let element = AXHelpers.element(at: window.bounds.origin)
        else {
            return false
        }
        return AXHelpers.role(for: element) == kAXMenuBarRole
    }

    /// Shows the secondary context menu.
    func showSecondaryContextMenu(at point: CGPoint) {
        let menu = NSMenu(title: "holzBar")

        let editAppearanceItem = NSMenuItem(
            title: "Edit Menu Bar Appearance…",
            action: #selector(showAppearanceEditorPanel),
            keyEquivalent: ""
        )
        editAppearanceItem.target = self
        menu.addItem(editAppearanceItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "holzBar Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        menu.addItem(settingsItem)

        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// Hides the application menus.
    func hideApplicationMenus() {
        guard let appState else {
            logger.error("Error hiding application menus: Missing app state")
            return
        }
        logger.info("Hiding application menus")
        appState.activate(withPolicy: .regular)
        isHidingApplicationMenus = true
    }

    /// Shows the application menus.
    func showApplicationMenus() {
        guard let appState else {
            logger.error("Error showing application menus: Missing app state")
            return
        }
        logger.info("Showing application menus")
        appState.deactivate(withPolicy: .accessory)
        isHidingApplicationMenus = false
    }

    /// Toggles the visibility of the application menus.
    func toggleApplicationMenus() {
        if isHidingApplicationMenus {
            showApplicationMenus()
        } else {
            hideApplicationMenus()
        }
    }

    /// Shows the appearance editor panel.
    @objc private func showAppearanceEditorPanel() {
        guard let screen = MenuBarAppearanceEditorPanel.defaultScreen else {
            return
        }
        appearanceEditorPanel.show(on: screen)
    }

    /// Returns the menu bar section with the given name.
    func section(withName name: MenuBarSection.Name) -> MenuBarSection? {
        sections.first { $0.name == name }
    }

    /// Returns the control item for the menu bar section with the given name.
    func controlItem(withName name: MenuBarSection.Name) -> ControlItem? {
        section(withName: name)?.controlItem
    }
}

// MARK: - MenuBarAverageColorInfo

/// Information for the average color of the menu bar.
struct MenuBarAverageColorInfo: Hashable {
    /// Sources used to compute the average color of the menu bar.
    enum Source: Hashable {
        case menuBarWindow
        case desktopWallpaper
    }

    /// The average color of the menu bar
    var color: CGColor

    /// The source used to compute the color.
    var source: Source

    /// The brightness of the menu bar's color.
    var brightness: CGFloat { color.brightness ?? 0 }

    /// A Boolean value that indicates whether the menu bar has a
    /// bright color.
    ///
    /// This value is `true` if ``brightness`` is above `0.67`. At
    /// the time of writing, if this value is `true`, the menu bar
    /// draws its items with a darker appearance.
    var isBright: Bool { brightness > 0.67 }
}
