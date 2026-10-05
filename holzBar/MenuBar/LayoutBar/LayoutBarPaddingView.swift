//
//  LayoutBarPaddingView.swift
//  holzBar
//

import Cocoa
import OSLog

/// A Cocoa view that manages the menu bar layout interface.
final class LayoutBarPaddingView: NSView {
    private let container: LayoutBarContainer

    /// The layout view's arranged views.
    var arrangedViews: [LayoutBarItemView] {
        get { container.arrangedViews }
        set { container.arrangedViews = newValue }
    }

    /// Creates a layout bar view with the given app state, section, and spacing.
    ///
    /// - Parameters:
    ///   - appState: The shared app state instance.
    ///   - section: The section whose items are represented.
    init(appState: AppState, section: MenuBarSection.Name) {
        self.container = LayoutBarContainer(appState: appState, section: section)

        super.init(frame: .zero)

        addSubview(container)
        self.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            container.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: 7.5),
            leadingAnchor.constraint(lessThanOrEqualTo: container.leadingAnchor, constant: -7.5),
        ])

        registerForDraggedTypes([.layoutBarItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        container.updateArrangedViewsForDrag(with: sender, phase: .entered)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let sender {
            container.updateArrangedViewsForDrag(with: sender, phase: .exited)
        }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        container.updateArrangedViewsForDrag(with: sender, phase: .updated)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        container.updateArrangedViewsForDrag(with: sender, phase: .ended)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer {
            Task {
                self.container.canSetArrangedViews = true
            }
        }

        guard
            let draggingSource = sender.draggingSource as? LayoutBarItemView,
            let appState = container.appState
        else {
            return false
        }

        if #available(macOS 27.0, *) {
            // On macOS 27 the saved layout decides sections and macOS orders the items within
            // one, so a drop only moves the item's application to this section.
            let item = draggingSource.item
            let itemCache = appState.itemManager.itemCache
            if !item.isControlItem, itemCache.address(for: item.tag)?.section != container.section {
                LayoutBarMoves.setSection(of: item, to: container.section, appState: appState)
            } else {
                // A drop that changes no section changes nothing on the bar, so the row
                // goes back to the order macOS keeps.
                container.canSetArrangedViews = true
                container.setArrangedViews(items: itemCache[container.section])
            }
            return true
        }

        let item = draggingSource.item
        let actionName = String(localized: "Move \(item.displayName)")
        if let index = arrangedViews.firstIndex(of: draggingSource) {
            if arrangedViews.count == 1 {
                // The dragging source is the only view in the layout bar, so it goes next to
                // the section's control item.
                LayoutBarMoves.moveToEnd(of: container.section, item: item, appState: appState, actionName: actionName)
            } else if arrangedViews.indices.contains(index + 1) {
                // we have a view to the right of the dragging source
                let targetItem = arrangedViews[index + 1].item
                LayoutBarMoves.move(item, to: .leftOfItem(targetItem), appState: appState, actionName: actionName)
            } else if arrangedViews.indices.contains(index - 1) {
                // we have a view to the left of the dragging source
                let targetItem = arrangedViews[index - 1].item
                LayoutBarMoves.move(item, to: .rightOfItem(targetItem), appState: appState, actionName: actionName)
            }
        }

        return true
    }
}

// MARK: - LayoutBarMoves

/// Moves items from the Menu Bar Layout pane, by a drop or the keyboard, and registers the
/// inverse of every move on the Settings window's undo manager (THAW-14): before macOS 27
/// a user move back next to the item's former neighbour, on macOS 27 the former section.
/// Undoing registers the inverse again, which is the redo.
@MainActor
enum LayoutBarMoves {
    /// Where an item was before a move: beside its right neighbour, else its left one, else
    /// at the end of its section. Only identifiers, so undo works with whatever the bar
    /// holds then.
    private enum Anchor {
        case leftOf(CGWindowID)
        case rightOf(CGWindowID)
        case endOf(MenuBarSection.Name)
    }

    /// The undo manager of the Settings window, which shows the Layout pane.
    private static func undoManager(_ appState: AppState) -> UndoManager? {
        appState.navigationState.settingsWindow?.undoManager
    }

    // MARK: Before macOS 27

    /// Moves an item to a destination on the bar, as the user asked.
    ///
    /// - Parameter registersUndo: Whether the move registers its inverse; an undo registers
    ///   the redo itself, at once.
    static func move(
        _ item: MenuBarItem,
        to destination: MenuBarItemManager.MoveDestination,
        appState: AppState,
        actionName: String,
        announcement: String? = nil,
        registersUndo: Bool = true
    ) {
        if registersUndo, let anchor = anchor(of: item, appState: appState) {
            registerUndo(windowID: item.windowID, anchor: anchor, appState: appState, actionName: actionName)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            do {
                try await appState.itemManager.move(item: item, to: destination, origin: .user)
                appState.itemManager.removeTemporarilyShownItemFromCache(with: item.tag)
                // The user arranged the item: its section is the one to restore from now on.
                appState.itemManager.saveSectionsSoon()
                if let announcement {
                    LayoutBarItemView.announce(announcement)
                }
            } catch {
                Logger.default.error("Error moving menu bar item: \(error, privacy: .private)")
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }

    /// Moves an item to the end of a section, next to the section's control item.
    static func moveToEnd(
        of section: MenuBarSection.Name,
        item: MenuBarItem,
        appState: AppState,
        actionName: String,
        announcement: String? = nil
    ) {
        // Registered now, while the item is still where it was.
        if let anchor = anchor(of: item, appState: appState) {
            registerUndo(windowID: item.windowID, anchor: anchor, appState: appState, actionName: actionName)
        }
        Task {
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard let destination = endDestination(of: section, in: items) else {
                Logger.default.error("No control item to move next to")
                return
            }
            move(item, to: destination, appState: appState, actionName: actionName, announcement: announcement, registersUndo: false)
        }
    }

    /// The place at the end of a section: left of its control item (right of the hidden
    /// section's control item for the visible section).
    private static func endDestination(of section: MenuBarSection.Name, in items: [MenuBarItem]) -> MenuBarItemManager.MoveDestination? {
        switch section {
        case .visible:
            items.first(matching: .hiddenControlItem).map { .rightOfItem($0) }
        case .hidden:
            items.first(matching: .hiddenControlItem).map { .leftOfItem($0) }
        case .alwaysHidden:
            items.first(matching: .alwaysHiddenControlItem).map { .leftOfItem($0) }
        }
    }

    /// Where the item is now, read from the item cache, whose sections list the items from
    /// left to right.
    private static func anchor(of item: MenuBarItem, appState: AppState) -> Anchor? {
        let cache = appState.itemManager.itemCache
        guard let address = cache.address(for: item.tag) else {
            return nil
        }
        let items = cache[address.section]
        if items.indices.contains(address.index + 1) {
            return .leftOf(items[address.index + 1].windowID)
        }
        if items.indices.contains(address.index - 1) {
            return .rightOf(items[address.index - 1].windowID)
        }
        return .endOf(address.section)
    }

    private static func registerUndo(windowID: CGWindowID, anchor: Anchor, appState: AppState, actionName: String) {
        guard let undoManager = undoManager(appState) else {
            return
        }
        undoManager.registerUndo(withTarget: appState) { appState in
            MainActor.assumeIsolated {
                LayoutBarMoves.moveBack(windowID: windowID, to: anchor, appState: appState, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Puts an item back where the anchor says.
    ///
    /// The redo, back to where the item is now, is registered at once: only while the undo
    /// manager is undoing does a registration become the redo.
    private static func moveBack(windowID: CGWindowID, to anchor: Anchor, appState: AppState, actionName: String) {
        if
            let item = appState.itemManager.itemCache.managedItems.first(where: { $0.windowID == windowID }),
            let current = self.anchor(of: item, appState: appState)
        {
            registerUndo(windowID: windowID, anchor: current, appState: appState, actionName: actionName)
        }
        Task {
            let items = await MenuBarItem.getMenuBarItems(option: .activeSpace)
            guard let item = items.first(where: { $0.windowID == windowID }) else {
                return
            }
            let destination: MenuBarItemManager.MoveDestination? = switch anchor {
            case .leftOf(let neighbour):
                items.first { $0.windowID == neighbour }.map { .leftOfItem($0) }
            case .rightOf(let neighbour):
                items.first { $0.windowID == neighbour }.map { .rightOfItem($0) }
            case .endOf(let section):
                endDestination(of: section, in: items)
            }
            guard let destination else {
                return
            }
            move(item, to: destination, appState: appState, actionName: actionName, registersUndo: false)
        }
    }

    // MARK: Sections

    /// Moves an item to another section: on macOS 27 its application, before next to the
    /// section's control item.
    static func setSection(of item: MenuBarItem, to section: MenuBarSection.Name, appState: AppState) {
        let actionName = String(localized: "Change Section")
        let announcement = String(localized: "\(item.displayName) moved to \(section.displayString)")
        if #available(macOS 27.0, *) {
            guard let bundleID = item.sourceApplication?.bundleIdentifier else {
                NSSound.beep()
                return
            }
            setSection27(section, for: bundleID, appState: appState, actionName: actionName)
            LayoutBarItemView.announce(announcement)
            return
        }
        moveToEnd(of: section, item: item, appState: appState, actionName: actionName, announcement: announcement)
    }

    /// Sets an application's section on macOS 27 and registers the former one for undo.
    @available(macOS 27.0, *)
    private static func setSection27(_ section: MenuBarSection.Name, for bundleID: String, appState: AppState, actionName: String) {
        let layout = Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:]
        // An application missing from the layout is visible.
        let former = layout[bundleID].flatMap(MacOS27Section.init(rawValue:)) ?? .visible
        if let undoManager = undoManager(appState) {
            let formerName: MenuBarSection.Name = switch former {
            case .visible: .visible
            case .hidden: .hidden
            case .alwaysHidden: .alwaysHidden
            }
            undoManager.registerUndo(withTarget: appState) { appState in
                MainActor.assumeIsolated {
                    LayoutBarMoves.setSection27(formerName, for: bundleID, appState: appState, actionName: actionName)
                }
            }
            undoManager.setActionName(actionName)
        }
        appState.concealer27.setSection(MacOS27Section(section), for: bundleID)
    }
}
