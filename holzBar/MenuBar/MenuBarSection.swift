//
//  MenuBarSection.swift
//  holzBar
//

import SwiftUI

/// A representation of a section in a menu bar.
@MainActor
final class MenuBarSection {
    /// The name of a menu bar section.
    nonisolated enum Name: CaseIterable {
        case visible
        case hidden
        case alwaysHidden

        /// A string to show in the interface, in the user's language.
        var displayString: String {
            switch self {
            case .visible: String(localized: "Visible")
            case .hidden: String(localized: "Hidden")
            case .alwaysHidden: String(localized: "Always-Hidden")
            }
        }

        /// A string to use for logging purposes.
        var logString: String {
            switch self {
            case .visible: "visible section"
            case .hidden: "hidden section"
            case .alwaysHidden: "always-hidden section"
            }
        }

        /// The section's name in ``RevealOwnership``.
        var ownershipSection: RevealOwnership.Section {
            switch self {
            case .visible: .visible
            case .hidden: .hidden
            case .alwaysHidden: .alwaysHidden
            }
        }

        /// Localized string key representation.
        var localized: LocalizedStringKey {
            switch self {
            case .visible: "Visible"
            case .hidden: "Hidden"
            case .alwaysHidden: "Always-Hidden"
            }
        }
    }

    /// The name of the section.
    let name: Name

    /// The control item that manages the section.
    let controlItem: ControlItem

    /// The shared app state.
    private weak var appState: AppState?

    /// A timer that manages rehiding the section.
    private var rehideTimer: Timer?

    /// An event monitor that handles starting the rehide timer when the mouse
    /// is outside of the menu bar.
    private var rehideMonitor: EventMonitor?

    /// A Boolean value that indicates whether the holzBar Shelf should be used.
    private var useShelf: Bool {
        appState?.settings.general.usesShelf ?? false
    }

    /// A weak reference to the menu bar manager.
    private weak var menuBarManager: MenuBarManager? {
        appState?.menuBarManager
    }

    /// The best screen to show the holzBar Shelf on.
    /// Uses the screen under the mouse so the Shelf appears on the correct
    /// display when using multiple monitors (e.g. external monitor).
    private weak var screenForShelf: NSScreen? {
        guard appState != nil else {
            return nil
        }
        return NSScreen.screenWithMouse ?? NSScreen.main
    }

    /// A Boolean value that indicates whether the section is hidden.
    var isHidden: Bool {
        if useShelf {
            if controlItem.state == .showSection {
                return false
            }
            switch name {
            case .visible, .hidden:
                return menuBarManager?.shelfPanel.currentSection != .hidden
            case .alwaysHidden:
                return menuBarManager?.shelfPanel.currentSection != .alwaysHidden
            }
        }
        switch name {
        case .visible, .hidden:
            if menuBarManager?.shelfPanel.currentSection == .hidden {
                return false
            }
            return controlItem.state == .hideSection
        case .alwaysHidden:
            if menuBarManager?.shelfPanel.currentSection == .alwaysHidden {
                return false
            }
            return controlItem.state == .hideSection
        }
    }

    /// A Boolean value that indicates whether the section is enabled.
    var isEnabled: Bool {
        if case .visible = name {
            // The visible section should always be enabled.
            return true
        }
        return controlItem.isAddedToMenuBar
    }

    /// The hotkey to toggle the section.
    var hotkey: Hotkey? {
        guard let hotkeys = appState?.settings.hotkeys else {
            return nil
        }
        return switch name {
        case .visible: nil
        case .hidden: hotkeys.hotkey(withAction: .toggleHiddenSection)
        case .alwaysHidden: hotkeys.hotkey(withAction: .toggleAlwaysHiddenSection)
        }
    }

    /// Creates a section with the given name and control item.
    init(name: Name, controlItem: ControlItem) {
        self.name = name
        self.controlItem = controlItem
    }

    /// Creates a section with the given name.
    convenience init(name: Name) {
        let controlItem = switch name {
        case .visible:
            ControlItem(identifier: .visible)
        case .hidden:
            ControlItem(identifier: .hidden)
        case .alwaysHidden:
            ControlItem(identifier: .alwaysHidden)
        }
        self.init(name: name, controlItem: controlItem)
    }

    /// Performs the initial setup of the section.
    func performSetup(with appState: AppState) {
        self.appState = appState
        controlItem.performSetup(with: appState)
    }

    /// Shows the section.
    ///
    /// - Parameters:
    ///   - bypassingLock: Whether the user's lock for the hidden items is not asked:
    ///     for the safety rules and the items the user chose, which show by themselves.
    ///   - origin: What shows the section. Only what a trigger showed may that trigger hide
    ///     again (see ``RevealOwnership``); a user's request while the section is already
    ///     shown takes the reveal over.
    ///   - onShown: Called with the reveal's token once the section is really shown: at once,
    ///     after Touch ID, or once the Shelf is on screen; and at once with the takeover's
    ///     token when the section is already shown and the origin is the user's. Not called
    ///     when nothing is shown (the lock refused, the section is off). A trigger that hides
    ///     again later starts its timer here, so the timer also survives the lock (D-08).
    func show(
        bypassingLock: Bool = false,
        origin: RevealOwnership.Origin = .other,
        onShown: ((RevealOwnership.Token) -> Void)? = nil
    ) {
        guard let menuBarManager else {
            return
        }

        if !bypassingLock, let lock = appState?.hiddenItemsLock, lock.requiresAuthentication {
            lock.authenticate { [weak self] in
                self?.show(bypassingLock: true, origin: origin, onShown: onShown)
            }
            return
        }

        // Shown another way, the hidden section no longer hides after a moment, also
        // when it is already shown; the peek's own show keeps its timer, also the one that
        // waited for Touch ID (D-08). Showing the always-hidden section, which an item
        // change does briefly, leaves the hidden section's timer running. A show other than
        // a change reveal ends the change reveal's wait (D-09).
        if name != .alwaysHidden, origin != .peek {
            menuBarManager.temporaryShowTask?.cancel()
        }
        if origin != .changeReveal {
            menuBarManager.changeRevealTask?.cancel()
        }

        guard isHidden else {
            // Already shown: a user's request makes the reveal theirs, so an automatic
            // trigger (show on hover) no longer hides it.
            if !origin.isAutomatic {
                if let token = menuBarManager.revealOwnership.takeOver(by: origin) {
                    onShown?(token)
                } else if let onShown {
                    // Shown without a record (a Command-drag in progress): the request owns
                    // it from now on, with nothing it expanded.
                    onShown(menuBarManager.revealOwnership.didShow(origin, expanded: []))
                }
            }
            return
        }

        guard controlItem.isAddedToMenuBar else {
            // The section is disabled.
            // TODO: Can we use isEnabled for this check?
            return
        }

        if useShelf {
            // Make sure hidden and always-hidden control items are collapsed.
            // Still update the visible control item (holzBar icon) state to show
            // its alternate icon.
            for section in menuBarManager.sections {
                switch section.name {
                case .visible:
                    section.controlItem.state = .showSection
                case .hidden, .alwaysHidden:
                    section.controlItem.state = .hideSection
                }
            }

            if let screen = screenForShelf {
                // The Shelf shows one section: the hidden one, or the always-hidden one.
                let shelfSection: RevealOwnership.Section = name == .alwaysHidden ? .alwaysHidden : .hidden
                let token = menuBarManager.revealOwnership.didShow(origin, expanded: [shelfSection])
                Task {
                    let shown = switch name {
                    case .visible, .hidden:
                        await menuBarManager.shelfPanel.show(section: .hidden, on: screen)
                    case .alwaysHidden:
                        await menuBarManager.shelfPanel.show(section: .alwaysHidden, on: screen)
                    }
                    // A show cut short by a close leaves the section hidden, and its
                    // rehide checks would keep running with nothing left to hide.
                    if shown {
                        armRehide()
                        if menuBarManager.revealOwnership.isCurrent(token) {
                            onShown?(token)
                        }
                    } else if menuBarManager.revealOwnership.isCurrent(token) {
                        menuBarManager.revealOwnership.didHide([shelfSection])
                    }
                }
            }

            updateConcealment27()
            return // We're done.
        }

        // If we made it here, we're not using the holzBar Shelf.
        // Make sure it's closed.
        menuBarManager.shelfPanel.close()

        let token: RevealOwnership.Token
        switch name {
        case .visible, .hidden:
            for section in menuBarManager.sections where section.name != .alwaysHidden {
                section.controlItem.state = .showSection
            }
            token = menuBarManager.revealOwnership.didShow(origin, expanded: [.hidden])
        case .alwaysHidden:
            // Showing the always-hidden section shows the hidden one too; the rehide
            // collapses it again only when this show opened it.
            let hiddenWasHidden = menuBarManager.section(withName: .hidden)?.isHidden ?? false
            for section in menuBarManager.sections {
                section.controlItem.state = .showSection
            }
            token = menuBarManager.revealOwnership.didShow(
                origin,
                expanded: hiddenWasHidden ? [.alwaysHidden, .hidden] : [.alwaysHidden]
            )
        }

        armRehide()
        updateConcealment27()
        onShown?(token)
    }

    /// Hides the section.
    ///
    /// - Parameter isUserRequest: Whether the user asked for it directly (a click on holzBar's
    ///   icon, a section hotkey, Zen mode). Everything else, such as rehiding, is refused while
    ///   the display under the pointer is set to always show everything.
    func hide(isUserRequest: Bool = false) {
        guard let menuBarManager, !isHidden else {
            return
        }
        guard isUserRequest || useShelf || menuBarManager.displayBehavior.allowsHiding else {
            return
        }

        // Hiding the always-hidden section alone can leave the hidden section shown, so
        // its timers keep running.
        if name != .alwaysHidden {
            menuBarManager.temporaryShowTask?.cancel()
            menuBarManager.changeRevealTask?.cancel()
        }
        menuBarManager.shelfPanel.close() // Make sure the holzBar Shelf is always closed.
        menuBarManager.showOnHoverAllowed = true

        switch name {
        case _ where useShelf, .visible, .hidden:
            for section in menuBarManager.sections {
                section.controlItem.state = .hideSection
                // Every section is hidden now, so no other section's rehide keeps running
                // (the always-hidden one's, when its rehide hid the hidden section).
                section.stopRehideChecks()
            }
            menuBarManager.revealOwnership.didHide(Set(RevealOwnership.Section.allCases))
        case .alwaysHidden:
            controlItem.state = .hideSection
            menuBarManager.revealOwnership.didHide([.alwaysHidden])
        }

        stopRehideChecks()
        updateConcealment27()
    }

    /// Toggles the visibility of the section.
    ///
    /// - Parameters:
    ///   - isUserRequest: Whether the user asked for it directly (see ``hide(isUserRequest:)``).
    ///   - origin: What shows the section (see ``show(bypassingLock:origin:onShown:)``).
    func toggle(isUserRequest: Bool = false, origin: RevealOwnership.Origin = .other) {
        if isHidden { show(origin: origin) } else { hide(isUserRequest: isUserRequest) }
    }

    /// The section's name in ``RevealOwnership``.
    private var ownershipSection: RevealOwnership.Section {
        name.ownershipSection
    }

    /// Lets the macOS 27 concealer follow the new state of the sections.
    private func updateConcealment27() {
        if #available(macOS 27.0, *) {
            appState?.concealer27.update()
        }
    }

    /// Whether a menu, popover or panel of an app with an item in the hidden or always-hidden
    /// section is open, so that no hide pulls the item away under it.
    ///
    /// Reads the window list once: ask only when a hide is about to happen, never per pointer
    /// move. holzBar's own windows (the Shelf, the Notch hub) and the items' own windows in the
    /// bar never count.
    var hasOpenItemMenu: Bool {
        guard let itemCache = appState?.itemManager.itemCache else {
            return false
        }
        let shownItems = itemCache[.hidden] + itemCache[.alwaysHidden]
        var shownOwners = Set(shownItems.map { $0.sourcePID ?? $0.ownerPID })
        shownOwners.remove(ProcessInfo.processInfo.processIdentifier)
        guard !shownOwners.isEmpty else {
            return false
        }
        let allItems = itemCache.managedItems
        let itemWindows = Set(allItems.map(\.windowID))
        // The tallest menu bar: of every display, and of every item's own window in it.
        let barHeight = max(
            NSScreen.screens.reduce(NSStatusBar.system.thickness) { height, screen in
                max(height, screen.frame.maxY - screen.visibleFrame.maxY)
            },
            allItems.reduce(0) { max($0, $1.bounds.height) }
        )
        return WindowInfo.createWindows(option: .onScreen).contains { window in
            !itemWindows.contains(window.windowID) && InterfaceWindowRule.isOpenMenu(
                layer: window.layer,
                height: window.bounds.height,
                ownerPID: window.ownerPID,
                shownOwners: shownOwners,
                barHeight: barHeight
            )
        }
    }

    /// Whether the pointer is on the open holzBar Shelf.
    private var isPointerOnOpenShelf: Bool {
        guard let appState, appState.menuBarManager.shelfPanel.isVisible else {
            // The hit test alone also matches the frame of a closed panel.
            return false
        }
        return appState.hidEventManager.isMouseInsideShelf(appState: appState)
    }

    /// Starts running checks to determine when to rehide the section (the timed rehide
    /// strategy): one interval after the pointer last moved below the menu bar.
    func armRehide() {
        rehideTimer?.invalidate()
        rehideTimer = nil
        rehideMonitor?.stop()

        guard
            let appState,
            appState.settings.general.autoRehide,
            case .timed = appState.settings.general.rehideStrategy
        else {
            return
        }

        rehideMonitor = EventMonitor.universal(for: .mouseMoved) { [weak self] event in
            guard
                let self,
                let screen = NSScreen.screenWithMouse ?? NSScreen.main
            else {
                return event
            }
            if NSEvent.mouseLocation.y < screen.visibleFrame.maxY {
                if rehideTimer == nil {
                    let timer = Timer.scheduledTimer(
                        withTimeInterval: appState.settings.general.rehideInterval,
                        repeats: false
                    ) { [weak self] timer in
                        guard let self else {
                            return
                        }
                        let timerID = ObjectIdentifier(timer)
                        // Timers call their block on the main run loop, outside the main actor.
                        Task { @MainActor in
                            // A timer replaced or stopped meanwhile has nothing left to do.
                            guard let current = self.rehideTimer, ObjectIdentifier(current) == timerID else {
                                return
                            }
                            // The next pointer move below the bar starts a full interval
                            // again, also after a refused hide (no polling).
                            self.rehideTimer = nil
                            self.rehideNow()
                        }
                    }
                    rehideTimer = timer
                }
            } else {
                rehideTimer?.invalidate()
                rehideTimer = nil
            }
            return event
        }

        rehideMonitor?.start()
    }

    /// The timed rehide: hides what the section's show expanded, unless the pointer is in
    /// the menu bar or on the open Shelf, or a menu of a hidden item's app is open; then it
    /// waits for the next pointer move below the bar.
    private func rehideNow() {
        guard let menuBarManager else {
            return
        }
        guard !isHidden else {
            stopRehideChecks()
            return
        }
        guard
            let screen = NSScreen.screenWithMouse ?? NSScreen.main,
            NSEvent.mouseLocation.y < screen.visibleFrame.maxY,
            !isPointerOnOpenShelf,
            !hasOpenItemMenu
        else {
            return
        }
        // Showing the always-hidden section also opened the hidden one when it was hidden:
        // collapse both. A hidden section the user had shown before keeps its own rehide.
        let sections = menuBarManager.revealOwnership.sectionsToHide(rehiding: ownershipSection)
        if sections.contains(.hidden), let hidden = menuBarManager.section(withName: .hidden) {
            hidden.hide()
        } else {
            hide()
        }
    }

    /// Stops running checks to determine when to rehide the section.
    private func stopRehideChecks() {
        rehideTimer?.invalidate()
        rehideMonitor?.stop()
        rehideTimer = nil
        rehideMonitor = nil
    }
}
