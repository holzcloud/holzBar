//
//  ControlItem.swift
//  holzBar
//

import Cocoa
import Observation

// MARK: - ControlItem

/// A status item that controls a section in the menu bar.
@MainActor
@Observable
final class ControlItem {
    /// An identifier for a control item.
    nonisolated enum Identifier: String, CaseIterable {
        /// The identifier for the control item for the visible section.
        case visible = "holzBar.ControlItem.Visible"
        /// The identifier for the control item for the hidden section.
        case hidden = "holzBar.ControlItem.Hidden"
        /// The identifier for the control item for the always-hidden section.
        case alwaysHidden = "holzBar.ControlItem.AlwaysHidden"

        /// A tag for the control item with this identifier.
        var tag: MenuBarItemTag {
            switch self {
            case .visible: .visibleControlItem
            case .hidden: .hiddenControlItem
            case .alwaysHidden: .alwaysHiddenControlItem
            }
        }

        /// Returns the length associated with this identifier and
        /// the given hiding state.
        func length(for state: HidingState) -> CGFloat {
            switch self {
            case .visible:
                Lengths.standard
            case .hidden, .alwaysHidden:
                switch state {
                case .showSection:
                    Lengths.standard
                case .hideSection:
                    // macOS 27 discards status items wider than the status area, so the
                    // section is concealed by `Concealer27` instead of pushed off screen.
                    if #available(macOS 27.0, *) { Lengths.standard } else { Lengths.expanded }
                }
            }
        }
    }

    /// A hiding state for a control item.
    nonisolated enum HidingState {
        case showSection
        case hideSection
    }

    /// A namespace for control item lengths.
    private enum Lengths {
        static let standard: CGFloat = NSStatusItem.variableLength
        static let expanded: CGFloat = 10_000
    }

    /// Storage for a control item's underlying status item.
    private final class StatusItemStorage {
        let statusItem: NSStatusItem
        let constraint: NSLayoutConstraint?

        /// Creates a new storage instance.
        @MainActor
        init(controlItem: ControlItem) {
            ControlItemDefaults.preflightSetup(for: controlItem)

            self.statusItem = NSStatusBar.system.statusItem(withLength: 0)
            self.statusItem.autosaveName = controlItem.identifier.rawValue

            if let button = statusItem.button {
                // This could break in a new macOS release, but we need this constraint in order to
                // be able to hide the status item when the `ShowSectionDividers` setting is disabled.
                // A previous implementation used `statusItem.isVisible`, which was more robust, but
                // would completely remove the status item. With the current set of features, we use
                // the control item positions to determine the items in each section, so we need the
                // status item to be present if its section is enabled. The new solution is to remove
                // a constraint from the item's content view prevents it from having a length of zero.
                // Then, we set the length. FIXME: Find a replacement for this.
                if
                    let constraints = button.window?.contentView?.constraintsAffectingLayout(for: .horizontal),
                    let constraint = constraints.first(where: Predicates.controlItemConstraint(button: button))
                {
                    assert(constraints.filter(Predicates.controlItemConstraint(button: button)).count == 1)
                    self.constraint = constraint
                } else {
                    self.constraint = nil
                }

                // On macOS 27, holzBar finds its own items through Accessibility by this identifier.
                button.setAccessibilityIdentifier(controlItem.identifier.rawValue)
                button.target = controlItem
                button.action = #selector(controlItem.performAction)
                button.sendAction(on: [.leftMouseDown, .rightMouseUp])
            } else {
                self.constraint = nil
            }
        }

        deinit {
            // The status bar belongs to the main actor; the storage can be released anywhere.
            let statusItem = statusItem
            Task { @MainActor in
                StatusItemStorage.remove(statusItem)
            }
        }

        /// Removes the status item from the status bar.
        private static func remove(_ statusItem: NSStatusItem) {
            // Removing the status item has the unwanted side effect of
            // deleting the preferred position. Cache and restore it.
            let autosaveName = statusItem.autosaveName as String
            let cached = ControlItemDefaults[.preferredPosition, autosaveName]
            NSStatusBar.system.removeStatusItem(statusItem)
            ControlItemDefaults[.preferredPosition, autosaveName] = cached
        }
    }

    /// The control item's hiding state.
    var state = HidingState.hideSection {
        didSet {
            updateStatusItem()
        }
    }

    /// The control item's window.
    private(set) var window: NSWindow?

    /// The control item's frame.
    private(set) var frame: CGRect?

    /// The control item's screen.
    private(set) var screen: NSScreen?

    /// The control item's frame, if it is onscreen.
    private(set) var onScreenFrame: CGRect?

    /// The control item's identifier.
    let identifier: Identifier

    /// Lazy storage for the control item's underlying status item.
    @ObservationIgnored private lazy var storage = StatusItemStorage(controlItem: self)

    /// The shared app state.
    @ObservationIgnored private weak var appState: AppState?

    /// Observers of the settings that decide the item's look and presence.
    @ObservationIgnored private var observers = [ObservationLoop]()

    /// Key-value observers of the status item and its button.
    @ObservationIgnored private var statusItemObservations = [NSKeyValueObservation]()

    /// Key-value observers of the item's window and screen.
    @ObservationIgnored private var windowObservations = [NSKeyValueObservation]()

    /// Key-value observer of the screen's frame.
    @ObservationIgnored private var screenObservation: NSKeyValueObservation?

    /// The control item's underlying status item.
    private var statusItem: NSStatusItem {
        storage.statusItem
    }

    /// A horizontal constraint for the control item's content view.
    private var constraint: NSLayoutConstraint? {
        storage.constraint
    }

    /// A Boolean value that indicates whether the control item serves as
    /// a divider between sections.
    var isSectionDivider: Bool {
        identifier != .visible
    }

    /// A Boolean value that indicates whether the control item is currently
    /// displayed in the menu bar.
    var isAddedToMenuBar: Bool {
        statusItem.isVisible
    }

    /// The corresponding section name for the control item.
    var sectionName: MenuBarSection.Name {
        switch identifier {
        case .visible: .visible
        case .hidden: .hidden
        case .alwaysHidden: .alwaysHidden
        }
    }

    /// Creates a control item with the given identifier.
    init(identifier: Identifier) {
        self.identifier = identifier
    }

    /// Performs the initial setup of the control item.
    func performSetup(with appState: AppState) {
        self.appState = appState
        configureObservers()
    }

    /// Configures the internal observers for the control item.
    private func configureObservers() {
        updateStatusItem()

        statusItemObservations.append(
            statusItem.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in
                    self?.statusItemVisibilityDidChange()
                }
            }
        )

        if let button = statusItem.button {
            statusItemObservations.append(
                button.observe(\.window, options: [.initial, .new]) { [weak self] button, _ in
                    Task { @MainActor in
                        self?.windowDidChange(button.window)
                    }
                }
            )
        }

        guard let appState else {
            return
        }

        observers.append(
            ObservationLoop.observe { appState.isDraggingMenuBarItem } onChange: { [weak self] isDragging in
                if isDragging {
                    self?.updateStatusItem()
                }
            }
        )

        let general = appState.settings.general
        let advanced = appState.settings.advanced

        if identifier == .visible {
            observers.append(
                ObservationLoop.observe { general.showHolzBarIcon } onChange: { [weak self] _ in
                    self?.updateMenuBarPresence()
                }
            )
            observers.append(
                ObservationLoop.observe {
                    (general.holzBarIcon, general.customHolzBarIconIsTemplate)
                } onChange: { [weak self] _ in
                    self?.updateStatusItem()
                }
            )
        }

        if identifier == .alwaysHidden {
            observers.append(
                ObservationLoop.observe { advanced.enableAlwaysHiddenSection } onChange: { [weak self] _ in
                    self?.updateMenuBarPresence()
                }
            )
        }

        if isSectionDivider {
            observers.append(
                ObservationLoop.observe { advanced.sectionDividerStyle } onChange: { [weak self] _ in
                    self?.updateStatusItem()
                }
            )
        }
    }

    /// Follows the status item's visibility: the section's hotkey works only while the
    /// item is in the menu bar, and the item is put back where it has to be.
    private func statusItemVisibilityDidChange() {
        let isVisible = statusItem.isVisible
        if
            let menuBarManager = appState?.menuBarManager,
            let section = menuBarManager.section(withName: sectionName),
            let hotkey = section.hotkey
        {
            if isVisible {
                hotkey.enable()
            } else {
                hotkey.disable()
            }
        }
        updateMenuBarPresence()
    }

    /// Adds the item to the menu bar or removes it, as its settings say.
    ///
    /// The hidden section's divider must always be in the menu bar, but it can still
    /// be dragged out of it with Command held down. Nothing brought it back, and the
    /// hidden section was gone for good (jordanbaird/Ice#619).
    private func updateMenuBarPresence() {
        guard let appState else {
            return
        }
        switch identifier {
        case .visible:
            if appState.settings.general.showHolzBarIcon {
                addToMenuBar()
            } else {
                removeFromMenuBar()
            }
        case .hidden:
            if !statusItem.isVisible {
                addToMenuBar()
            }
        case .alwaysHidden:
            if appState.settings.advanced.enableAlwaysHiddenSection {
                addToMenuBar()
            } else {
                removeFromMenuBar()
            }
        }
    }

    /// Records the item's new window and follows its frame and screen.
    private func windowDidChange(_ newWindow: NSWindow?) {
        window = newWindow
        OwnStatusItemWindows.set(newWindow?.windowNumber, for: self)
        windowObservations.removeAll()
        guard let newWindow else {
            return
        }
        windowObservations = [
            newWindow.observe(\.frame, options: [.initial, .new]) { [weak self] window, _ in
                Task { @MainActor in
                    guard let self, self.window === window, frame != window.frame else {
                        return
                    }
                    frame = window.frame
                    updateOnScreenFrame()
                }
            },
            newWindow.observe(\.screen, options: [.initial, .new]) { [weak self] window, _ in
                Task { @MainActor in
                    guard let self, self.window === window else {
                        return
                    }
                    screenDidChange(window.screen)
                }
            },
        ]
    }

    /// Records the item's new screen and follows its frame.
    private func screenDidChange(_ newScreen: NSScreen?) {
        if screen !== newScreen {
            screen = newScreen
        }
        screenObservation = newScreen?.observe(\.frame, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.updateOnScreenFrame()
            }
        }
        updateOnScreenFrame()
    }

    /// Updates ``onScreenFrame`` from the item's frame and its screen's frame.
    private func updateOnScreenFrame() {
        guard let frame, let screen else {
            return
        }
        let newValue: CGRect? = screen.frame.intersects(frame) ? frame : nil
        if onScreenFrame != newValue {
            onScreenFrame = newValue
        }
    }

    /// Updates the appearance of the status item using the current hiding state.
    private func updateStatusItem() {
        guard
            let appState,
            let button = statusItem.button
        else {
            return
        }

        button.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
        button.title = ""
        button.image = nil

        switch identifier {
        case .visible:
            updateStatusItemVisibility(true)
            button.appearsDisabled = false

            let icon = appState.settings.general.holzBarIcon

            // We can usually just create the image directly from the icon.
            var image = switch state {
            case .showSection: icon.visible.nsImage(for: appState)
            case .hideSection: icon.hidden.nsImage(for: appState)
            }

            if
                case .custom = icon.name,
                let originalImage = image
            {
                // Custom icons need to be resized to fit inside the button.
                let originalWidth = originalImage.size.width
                let originalHeight = originalImage.size.height
                let ratio = max(originalWidth / 25, originalHeight / 17)
                let newSize = CGSize(width: originalWidth / ratio, height: originalHeight / ratio)
                image = originalImage.resized(to: newSize)
            }

            button.image = image
        case .hidden, .alwaysHidden:
            if #available(macOS 27.0, *) {
                // holzBar is signed locally, so MenuBarAgent drops its items whenever anything is
                // concealed (measured on macOS 27.0). A divider is therefore never drawn, yet a
                // standard-width status item still holds 18 points of the bar, which reads as a
                // gap between the neighbouring icons. Sections come from the saved layout on 27,
                // so the dividers only have to stay in the bar, not to take up room in it.
                updateStatusItemVisibility(false)
                button.appearsDisabled = true
                button.isHighlighted = false
                return
            }
            switch state {
            case .showSection:
                switch appState.settings.advanced.sectionDividerStyle {
                case .noDivider:
                    updateStatusItemVisibility(false)
                    button.appearsDisabled = true
                    button.isHighlighted = false

                    if appState.isDraggingMenuBarItem && appState.settings.advanced.showAllSectionsOnUserDrag {
                        // We still want a subtle marker between sections.
                        button.title = "|"
                    }
                case .chevron:
                    updateStatusItemVisibility(true)
                    button.appearsDisabled = false

                    button.image = switch identifier {
                    case .hidden:
                        ControlItemImage.builtin(.chevronLarge).nsImage(for: appState)
                    case .alwaysHidden:
                        ControlItemImage.builtin(.chevronSmall).nsImage(for: appState)
                    case .visible: nil
                    }
                }
            case .hideSection:
                updateStatusItemVisibility(true)
                button.appearsDisabled = true
                button.isHighlighted = false
            }
        }
    }

    /// Updates the visibility of the status item.
    ///
    /// The hidden and always-hidden control items must always be present in
    /// the menu bar, as we use their positions to determine the items in each
    /// section. Setting `statusItem.isVisible` to `false` completely removes
    /// the item. Instead, we toggle the width constraint on the item's content
    /// view, update the item's length, then adjust the content size of the
    /// item's window if needed.
    private func updateStatusItemVisibility(_ isVisible: Bool) {
        guard let appState else {
            return
        }

        if isVisible {
            constraint?.isActive = true
            statusItem.length = identifier.length(for: state)
        } else {
            let showOnDrag = appState.settings.advanced.showAllSectionsOnUserDrag
            let isDragging = appState.isDraggingMenuBarItem

            let shouldShow = showOnDrag && isDragging

            constraint?.isActive = false
            statusItem.length = shouldShow ? 3 : 0

            if let window {
                let size = withMutableCopy(of: window.frame.size) { $0.width = shouldShow ? 3 : 1 }
                window.setContentSize(size)
            }
        }
    }

    /// Adds the control item to the menu bar.
    private func addToMenuBar() {
        guard !isAddedToMenuBar else {
            return
        }
        statusItem.isVisible = true
    }

    /// Removes the control item from the menu bar.
    private func removeFromMenuBar() {
        guard isAddedToMenuBar else {
            return
        }
        // Setting `statusItem.isVisible` to `false` has the unwanted side
        // effect of deleting the preferred position. Cache and restore it.
        let autosaveName = statusItem.autosaveName as String
        let cached = ControlItemDefaults[.preferredPosition, autosaveName]
        statusItem.isVisible = false
        ControlItemDefaults[.preferredPosition, autosaveName] = cached
    }

    /// Performs the control item's action.
    @objc private func performAction() {
        guard
            let menuBarManager = appState?.menuBarManager,
            let event = NSApp.currentEvent
        else {
            return
        }

        switch event.type {
        case .leftMouseDown:
            let modifierFlags = NSEvent.modifierFlags

            // Running this from a Task seems to improve the visual
            // responsiveness of the status item's button.
            Task {
                if modifierFlags == .control {
                    showMenu()
                    return
                }

                if
                    modifierFlags == .option,
                    let section = menuBarManager.section(withName: .alwaysHidden),
                    section.isEnabled
                {
                    section.toggle()
                    return
                }

                if
                    let section = menuBarManager.section(withName: sectionName),
                    section.isEnabled
                {
                    section.toggle()
                }
            }
        case .rightMouseUp:
            showMenu()
        default:
            return
        }
    }

    /// Creates a menu to show under the control item.
    private func createMenu(with appState: AppState) -> NSMenu {
        func hotkey(withAction action: HotkeyAction) -> Hotkey? {
            appState.settings.hotkeys.hotkey(withAction: action)
        }

        let menu = NSMenu(title: "holzBar")

        let settingsItem = NSMenuItem(
            title: "holzBar Settings…",
            action: #selector(AppDelegate.openSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let searchItem = NSMenuItem(
            title: "Search Menu Bar Items",
            action: #selector(showSearchPanel),
            keyEquivalent: ""
        )
        if
            let hotkey = hotkey(withAction: .searchMenuBarItems),
            let keyCombination = hotkey.keyCombination
        {
            searchItem.keyEquivalent = keyCombination.key.keyEquivalent
            searchItem.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
        }
        searchItem.target = self
        menu.addItem(searchItem)

        menu.addItem(.separator())

        // Add items to toggle the hidden and always-hidden sections.
        for name: MenuBarSection.Name in [.hidden, .alwaysHidden] {
            guard
                let section = appState.menuBarManager.section(withName: name),
                section.isEnabled
            else {
                continue
            }
            let item = NSMenuItem(
                title: "\(section.isHidden ? "Show" : "Hide") \(name.displayString) Section",
                action: #selector(toggleMenuBarSection),
                keyEquivalent: ""
            )
            if
                let hotkey = section.hotkey,
                let keyCombination = hotkey.keyCombination
            {
                item.keyEquivalent = keyCombination.key.keyEquivalent
                item.keyEquivalentModifierMask = keyCombination.modifiers.nsEventFlags
            }
            item.target = self
            item.representedObject = section
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let howToUpdateItem = NSMenuItem(
            title: "How to Update…",
            action: #selector(showHowToUpdate),
            keyEquivalent: ""
        )
        howToUpdateItem.target = self
        menu.addItem(howToUpdateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit holzBar",
            action: #selector(NSApp.terminate),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    /// Shows the control item's menu.
    private func showMenu() {
        guard let appState else {
            return
        }
        let menu = createMenu(with: appState)
        statusItem.showMenu(menu)
    }

    /// Toggles the menu bar section associated with the given menu item.
    @objc private func toggleMenuBarSection(for menuItem: NSMenuItem) {
        guard let section = menuItem.representedObject as? MenuBarSection else {
            return
        }
        section.toggle()
    }

    /// Opens the menu bar search panel.
    @objc private func showSearchPanel() {
        appState?.menuBarManager.searchPanel.show()
    }

    /// Opens the releases page in the browser. Its notes carry the update
    /// command, `brew update && brew upgrade --cask holzbar`. holzBar itself
    /// makes no request: it never connects to the network.
    @objc private func showHowToUpdate() {
        NSWorkspace.shared.open(Constants.releasesURL)
    }
}

// MARK: - ControlItemDefaults

/// Proxy getters and setters for a control item's stored
/// UserDefaults values.
enum ControlItemDefaults {
    /// Accesses the value associated with the specified key
    /// and autosave name.
    static subscript<Value>(key: Key<Value>, autosaveName: String) -> Value? {
        get {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.object(forKey: stringKey) as? Value
        }
        set {
            let stringKey = key.stringKey(for: autosaveName)
            return UserDefaults.standard.set(newValue, forKey: stringKey)
        }
    }

    /// Migrates the given control item defaults key from an old
    /// autosave name to a new autosave name.
    static func migrate<Value>(key: Key<Value>, from oldAutosaveName: String, to newAutosaveName: String) {
        guard newAutosaveName != oldAutosaveName else {
            return
        }
        Self[key, newAutosaveName] = Self[key, oldAutosaveName]
        Self[key, oldAutosaveName] = nil
    }

    /// Performs some initial required setup work before the
    /// creation of a control item.
    fileprivate static func preflightSetup(for controlItem: ControlItem) {
        let autosaveName = controlItem.identifier.rawValue

        // Visible and hidden control items should be added before
        // existing items in the status bar.
        if ControlItemDefaults[.preferredPosition, autosaveName] == nil {
            switch controlItem.identifier {
            case .visible:
                ControlItemDefaults[.preferredPosition, autosaveName] = 0
            case .hidden:
                ControlItemDefaults[.preferredPosition, autosaveName] = 1
            case .alwaysHidden:
                break
            }
        }

        // The control item should be visible by default. We change
        // this after finishing setup, if needed.
        if ControlItemDefaults[.visible, autosaveName] == nil {
            ControlItemDefaults[.visible, autosaveName] = true
        }
        if
            #available(macOS 26.0, *),
            ControlItemDefaults[.visibleCC, autosaveName] == nil
        {
            ControlItemDefaults[.visibleCC, autosaveName] = true
        }
    }
}

// MARK: - ControlItemDefaults.Key

extension ControlItemDefaults {
    /// Keys used to look up UserDefaults values for control items.
    struct Key<Value> {
        /// The raw value of the key.
        let rawValue: String

        /// Returns the full string key for the given autosave name.
        func stringKey(for autosaveName: String) -> String {
            "NSStatusItem \(rawValue) \(autosaveName)"
        }
    }
}

// MARK: ControlItemDefaults.Key<CGFloat>
extension ControlItemDefaults.Key<CGFloat> {
    /// String key: "NSStatusItem Preferred Position autosaveName"
    static let preferredPosition = Self(rawValue: "Preferred Position")
}

// MARK: ControlItemDefaults.Key<Bool>
extension ControlItemDefaults.Key<Bool> {
    /// String key: "NSStatusItem Visible autosaveName"
    static let visible = Self(rawValue: "Visible")

    /// String key: "NSStatusItem VisibleCC autosaveName"
    static let visibleCC = Self(rawValue: "VisibleCC")
}
