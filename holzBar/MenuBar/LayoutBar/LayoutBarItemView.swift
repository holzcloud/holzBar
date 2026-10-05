//
//  LayoutBarItemView.swift
//  holzBar
//

import Cocoa
import SwiftUI

// MARK: - LayoutBarItemView

/// A view that displays an image in a menu bar layout view.
final class LayoutBarItemView: NSView {
    private weak var appState: AppState?

    /// Observes the item's image.
    private var imageObserver: ObservationLoop?

    /// The item that the view represents.
    let item: MenuBarItem

    /// Temporary information that the item view retains when it is moved outside
    /// of a layout view.
    ///
    /// When the item view is dragged outside of a layout view, this property is set
    /// to hold the layout view's container view, as well as the index of the item
    /// view in relation to the container's other items. Upon being inserted into a
    /// new layout view, these values are removed. If the item is dropped outside of
    /// a layout view, these values are used to reinsert the item view in its original
    /// layout view.
    var oldContainerInfo: (container: LayoutBarContainer, index: Int)?

    /// A Boolean value that indicates whether the item view is currently inside a container.
    var hasContainer = false

    /// The container the view is dragged from, which stops setting its arranged views
    /// until the dragging session ends.
    private(set) weak var dragSourceContainer: LayoutBarContainer?

    /// The image displayed inside the view: the item's chosen image, its picture or its
    /// app's icon (`ItemIconStore`).
    private var displayImage: NSImage? {
        didSet {
            setFrameSize(displayImage?.size ?? .zero)
            needsDisplay = true
            (superview as? LayoutBarContainer)?.arrangedViewDidResize()
        }
    }

    /// A Boolean value that indicates whether the item view is a dragging placeholder.
    ///
    /// If this value is `true`, the item view does not draw its image.
    var isDraggingPlaceholder = false {
        didSet {
            needsDisplay = true
        }
    }

    /// The process whose responsiveness decides whether the item can be moved: the app
    /// the item belongs to, not Control Center, which owns every item window on macOS 26.
    private var responsivenessPID: pid_t {
        item.sourcePID ?? item.ownerPID
    }

    /// A Boolean value that indicates whether the view is enabled.
    var isEnabled = true {
        didSet {
            needsDisplay = true
        }
    }

    /// Creates a view that displays the given menu bar item.
    init(appState: AppState, item: MenuBarItem) {
        self.item = item
        self.appState = appState

        // set the frame to the full item frame size; the image will be centered when displayed
        super.init(frame: CGRect(origin: .zero, size: item.bounds.size))
        unregisterDraggedTypes()

        self.toolTip = item.displayName
        // VoiceOver reads every item as a button with its name and section, and offers the
        // moves as actions (see Accessibility below).
        setAccessibilityElement(true)
        self.isEnabled = item.isMovable
        if #available(macOS 27.0, *) {
            // macOS 27 hides whole apps, so an item is placed by its app.
            if !item.isMovable {
                self.toolTip = String(localized: "macOS 27 doesn't let apps hide this system item.")
            } else if item.sourceApplication?.bundleIdentifier == nil {
                self.isEnabled = false
                self.toolTip = String(localized: "macOS 27 hides whole apps, and holzBar can't tell which app this item belongs to.")
            }
        }

        configureObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureObservers() {
        guard let appState else {
            return
        }
        let iconStore = appState.itemIconStore
        let item = item
        if let image = iconStore.image(for: item) {
            displayImage = image
        }
        imageObserver = ObservationLoop.observe { iconStore.image(for: item) } onChange: { [weak self] image in
            guard let self, let image else {
                return
            }
            displayImage = image
        }
    }

    /// Provides an alert to display when the item view is disabled.
    func provideAlertForDisabledItem() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = String(localized: "Menu bar item is not movable.")
        alert.informativeText = String(localized: "macOS prohibits \u{201C}\(item.displayName)\u{201D} from being moved.")
        return alert
    }

    /// Provides an alert to display when a menu bar item is unresponsive.
    func provideAlertForUnresponsiveItem() -> NSAlert {
        let alert = provideAlertForDisabledItem()
        alert.informativeText = String(localized: "\(item.displayName) is unresponsive. Until it is restarted, it cannot be moved. Movement of other menu bar items may also be affected until this is resolved.")
        return alert
    }

    /// Shows the alert as a sheet on the view's window, unless a sheet is already there.
    ///
    /// A drag reports many events, so this shows one sheet per drag, not a stack of them.
    private func showSheet(_ alert: NSAlert) {
        guard let window, window.attachedSheet == nil else {
            return
        }
        alert.beginSheetModal(for: window, completionHandler: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        if !isDraggingPlaceholder {
            displayImage?.draw(
                in: bounds,
                from: .zero,
                operation: .sourceOver,
                fraction: isEnabled ? 1.0 : 0.67
            )
            if Bridging.isProcessUnresponsive(responsivenessPID) {
                let warningImage = NSImage.warning
                let width: CGFloat = 15
                let scale = width / warningImage.size.width
                let size = CGSize(
                    width: width,
                    height: warningImage.size.height * scale
                )
                warningImage.draw(
                    in: CGRect(
                        x: bounds.maxX - size.width,
                        y: bounds.minY,
                        width: size.width,
                        height: size.height
                    )
                )
            }
        }
    }

    // MARK: Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        makeContextMenu()
    }

    /// The item's menu: its hotkey and the other settings of the item.
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu(title: item.displayName)
        let hotkeyItem = NSMenuItem(
            title: String(localized: "Set Hotkey…"),
            action: #selector(showHotkeyPopover),
            keyEquivalent: ""
        )
        hotkeyItem.target = self
        menu.addItem(hotkeyItem)
        if let iconStore = appState?.itemIconStore, !item.isControlItem {
            menu.addItem(.separator())
            let choice = iconStore.choice(for: item)
            let chooseImageItem = NSMenuItem(
                title: String(localized: "Choose Image…"),
                action: #selector(chooseImage),
                keyEquivalent: ""
            )
            let useAppIconItem = NSMenuItem(
                title: String(localized: "Use App Icon"),
                action: #selector(useAppIcon),
                keyEquivalent: ""
            )
            useAppIconItem.state = choice == .appIcon ? .on : .off
            useAppIconItem.isEnabled = item.sourceApplication != nil
            let resetImageItem = NSMenuItem(
                title: String(localized: "Reset Image"),
                action: #selector(resetImage),
                keyEquivalent: ""
            )
            resetImageItem.isEnabled = choice != nil
            for menuItem in [chooseImageItem, useAppIconItem, resetImageItem] {
                menuItem.target = self
                menu.addItem(menuItem)
            }
            menu.autoenablesItems = false
            menu.addItem(.separator())
        }
        if let watcher = appState?.itemChangeWatcher, !item.isControlItem {
            let changeItem = NSMenuItem(
                title: String(localized: "Show When It Changes"),
                action: #selector(toggleRevealOnChange),
                keyEquivalent: ""
            )
            changeItem.state = watcher.isRevealedOnChange(item) ? .on : .off
            changeItem.target = self
            menu.addItem(changeItem)
        }
        return menu
    }

    /// Lets the user choose an image for the item.
    @objc private func chooseImage() {
        appState?.itemIconStore.chooseImage(for: item)
    }

    /// Shows the app's icon for the item.
    @objc private func useAppIcon() {
        appState?.itemIconStore.useAppIcon(for: item)
    }

    /// Goes back to the item's own picture.
    @objc private func resetImage() {
        appState?.itemIconStore.reset(for: item)
    }

    /// Marks or unmarks the item "Show When It Changes".
    @objc private func toggleRevealOnChange() {
        guard let watcher = appState?.itemChangeWatcher else {
            return
        }
        watcher.setRevealedOnChange(!watcher.isRevealedOnChange(item), for: item)
    }

    /// Opens the item's menu below it, from the keyboard or VoiceOver.
    private func showContextMenu() {
        makeContextMenu().popUp(positioning: nil, at: CGPoint(x: 0, y: -4), in: self)
    }

    // MARK: Keyboard

    /// The section whose row shows the item.
    private var section: MenuBarSection.Name? {
        (superview as? LayoutBarContainer)?.section
    }

    /// Whether items keep an order within their section (before macOS 27).
    private static var itemsKeepOrder: Bool {
        if #available(macOS 27.0, *) {
            false
        } else {
            true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override var canBecomeKeyView: Bool { true }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = Int(event.keyCode)
        let modifiers = Modifiers(nsEventFlags: event.modifierFlags)
        // Undo and redo, which the Edit menu would do: holzBar hides its main menu.
        if keyCode == KeyCode.z.rawValue, modifiers == .command || modifiers == [.command, .shift] {
            let undoManager = appState?.navigationState.settingsWindow?.undoManager
            if modifiers == .command {
                undoManager?.undo()
            } else {
                undoManager?.redo()
            }
            return
        }
        guard let command = LayoutKeys.command(keyCode: keyCode, modifiers: modifiers, itemsKeepOrder: Self.itemsKeepOrder) else {
            super.keyDown(with: event)
            return
        }
        perform(command)
    }

    /// Performs what a key in the Layout pane asks for.
    private func perform(_ command: LayoutKeys.Command) {
        switch command {
        case .focus:
            LayoutBarRouter.shared.moveFocus(from: self, command: command)
        case .moveWithinSection(let step):
            moveWithinSection(by: step)
        case .moveToSection(let target):
            guard
                let appState,
                let section,
                let index = MenuBarSection.Name.allCases.firstIndex(of: section)
            else {
                return
            }
            let sectionCount = appState.settings.advanced.enableAlwaysHiddenSection ? 3 : 2
            guard
                let targetIndex = LayoutKeys.sectionIndex(for: target, from: index, sectionCount: sectionCount)
            else {
                NSSound.beep()
                return
            }
            move(to: MenuBarSection.Name.allCases[targetIndex])
        case .openMenu:
            showContextMenu()
        case .refused:
            NSSound.beep()
            Self.announce(String(localized: "macOS orders the items within each section."))
        }
    }

    /// Whether the item can be moved; otherwise beeps and says why.
    private func checkMovable() -> Bool {
        guard isEnabled, !Bridging.isProcessUnresponsive(responsivenessPID) else {
            NSSound.beep()
            Self.announce(toolTip ?? String(localized: "Menu bar item is not movable."))
            return false
        }
        return true
    }

    /// Moves the item one place left (`-1`) or right (`1`) within its section.
    private func moveWithinSection(by step: Int) {
        guard
            checkMovable(),
            let appState,
            let container = superview as? LayoutBarContainer,
            let index = container.arrangedViews.firstIndex(of: self),
            container.arrangedViews.indices.contains(index + step)
        else {
            NSSound.beep()
            return
        }
        let neighbour = container.arrangedViews[index + step].item
        let destination: MenuBarItemManager.MoveDestination = step < 0 ? .leftOfItem(neighbour) : .rightOfItem(neighbour)
        let announcement = step < 0
            ? String(localized: "\(item.displayName) moved left")
            : String(localized: "\(item.displayName) moved right")
        LayoutBarMoves.move(
            item,
            to: destination,
            appState: appState,
            actionName: String(localized: "Move \(item.displayName)"),
            announcement: announcement
        )
    }

    /// Moves the item to another section.
    private func move(to section: MenuBarSection.Name) {
        guard checkMovable(), let appState else {
            return
        }
        LayoutBarMoves.setSection(of: item, to: section, appState: appState)
    }

    /// Asks VoiceOver to read a message.
    static func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    // MARK: Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? {
        .button
    }

    override func accessibilityLabel() -> String? {
        guard let section else {
            return item.displayName
        }
        return String(localized: "\(item.displayName), \(section.displayString)")
    }

    override func accessibilityHelp() -> String? {
        isEnabled ? nil : toolTip
    }

    override func accessibilityPerformPress() -> Bool {
        showContextMenu()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = [NSAccessibilityCustomAction]()
        if isEnabled, let section, let appState {
            let moves: [(MenuBarSection.Name, String, Selector)] = [
                (.visible, String(localized: "Move to Visible"), #selector(accessibilityMoveToVisible)),
                (.hidden, String(localized: "Move to Hidden"), #selector(accessibilityMoveToHidden)),
                (.alwaysHidden, String(localized: "Move to Always Hidden"), #selector(accessibilityMoveToAlwaysHidden)),
            ]
            for (name, title, selector) in moves where name != section {
                if name == .alwaysHidden, !appState.settings.advanced.enableAlwaysHiddenSection {
                    continue
                }
                actions.append(NSAccessibilityCustomAction(name: title, target: self, selector: selector))
            }
            if Self.itemsKeepOrder {
                actions.append(NSAccessibilityCustomAction(name: String(localized: "Move Left"), target: self, selector: #selector(accessibilityMoveLeft)))
                actions.append(NSAccessibilityCustomAction(name: String(localized: "Move Right"), target: self, selector: #selector(accessibilityMoveRight)))
            }
        }
        actions.append(NSAccessibilityCustomAction(name: String(localized: "Set Hotkey…"), target: self, selector: #selector(accessibilitySetHotkey)))
        return actions
    }

    @objc private func accessibilityMoveToVisible() -> Bool {
        move(to: .visible)
        return true
    }

    @objc private func accessibilityMoveToHidden() -> Bool {
        move(to: .hidden)
        return true
    }

    @objc private func accessibilityMoveToAlwaysHidden() -> Bool {
        move(to: .alwaysHidden)
        return true
    }

    @objc private func accessibilityMoveLeft() -> Bool {
        moveWithinSection(by: -1)
        return true
    }

    @objc private func accessibilityMoveRight() -> Bool {
        moveWithinSection(by: 1)
        return true
    }

    @objc private func accessibilitySetHotkey() -> Bool {
        showHotkeyPopover()
        return true
    }

    /// Shows a recorder for the hotkey that opens the item's menu.
    @objc private func showHotkeyPopover() {
        guard let appState else {
            return
        }
        let key = appState.itemManager.identityKey(for: item)
        let hotkey = appState.settings.hotkeys.hotkey(for: .openItem(key))
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ItemHotkeyView(hotkey: hotkey, itemName: item.displayName)
        )
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)

        guard isEnabled else {
            showSheet(provideAlertForDisabledItem())
            return
        }

        guard !Bridging.isProcessUnresponsive(responsivenessPID) else {
            showSheet(provideAlertForUnresponsiveItem())
            return
        }

        // Data doesn't matter, but we do need to set the type.
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(Data(), forType: .layoutBarItem)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(bounds, contents: displayImage)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }
}

// MARK: LayoutBarItemView: NSDraggingSource
extension LayoutBarItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // make sure the container doesn't update its arranged views and that items
        // aren't arranged during a dragging session
        if let container = superview as? LayoutBarContainer {
            container.canSetArrangedViews = false
            dragSourceContainer = container
        }

        // prevent the dragging image from animating back to its original location
        session.animatesToStartingPositionsOnCancelOrFail = false

        // A profile bound to a display or a Space waits until the drop.
        appState?.profiles.isLayoutDragInProgress = true

        // async to prevent the view from disappearing before the dragging image appears
        Task {
            self.isDraggingPlaceholder = true
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let sourceContainer = dragSourceContainer
        defer {
            // always remove container info at the end of a session
            oldContainerInfo = nil
            appState?.profiles.isLayoutDragInProgress = false
            // The source row follows the item cache again: after a drop that moves the item
            // the move's cache change updates the rows. A drag that moved nothing (dropped
            // outside every row, cancelled, or refused by the row) puts them back to the
            // cache now, which may also have changed during the drag.
            dragSourceContainer = nil
            sourceContainer?.canSetArrangedViews = true
            if operation.isEmpty {
                LayoutBarRouter.shared.showItemCache()
            }
        }

        // since the session's `animatesToStartingPositionsOnCancelOrFail` property was
        // set to false when the session began (above), there is no delay between the user
        // releasing the dragging item and this method being called; thus, `isDraggingPlaceholder`
        // only needs to be updated here; if we ever decide we want animation, it may also
        // need to be updated inside `performDragOperation(_:)` on `LayoutBarPaddingView`
        isDraggingPlaceholder = false

        // if the drop occurs outside of a container, reinsert the view into its original
        // container at its original index
        if !hasContainer {
            // The row stays as it was during the drag, unless it was rebuilt meanwhile.
            guard
                let (container, index) = oldContainerInfo,
                !container.arrangedViews.contains(where: { $0.item.tag == item.tag })
            else {
                return
            }
            container.shouldAnimateNextLayoutPass = false
            container.arrangedViews.insert(self, at: min(index, container.arrangedViews.count))
        }
    }
}

extension LayoutBarItemView: NSAccessibilityLayoutItem { }

// MARK: - ItemHotkeyView

/// The hotkey recorder for opening one item's menu.
private struct ItemHotkeyView: View {
    let hotkey: Hotkey
    let itemName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open \u{201C}\(itemName)\u{201D} with a hotkey")
                .font(.headline)
            HotkeyRecorder(hotkey: hotkey) {
                Text("Hotkey")
            }
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: Layout Bar Item Pasteboard Type
extension NSPasteboard.PasteboardType {
    static let layoutBarItem = Self("\(Constants.bundleIdentifier).layout-bar-item")
}
