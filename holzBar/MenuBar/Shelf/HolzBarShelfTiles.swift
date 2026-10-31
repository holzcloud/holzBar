//
//  HolzBarShelfTiles.swift
//  holzBar
//

import Observation
import OSLog
import SwiftUI

// MARK: - HolzBarShelfClosedAppList

/// The applications that are not running and have a hidden item remembered, which the holzBar
/// Shelf lists dimmed while the setting is on.
///
/// It is read once each time the Shelf opens, and only with the setting on: the saved sections,
/// the running applications and the icons of the few applications that are listed.
struct HolzBarShelfClosedAppList {
    struct Entry {
        let app: ShelfContents.ClosedApp
        let url: URL
        let icon: NSImage
    }

    var hidden = [Entry]()
    var alwaysHidden = [Entry]()

    static let none = HolzBarShelfClosedAppList()

    /// Reads the list from the saved sections and the running applications.
    static func read() -> HolzBarShelfClosedAppList {
        let usesMacOS27Layout: Bool
        if #available(macOS 27.0, *) {
            usesMacOS27Layout = true
        } else {
            usesMacOS27Layout = false
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let remembered = ShelfClosedApps.bundleIdentifiers(
            usesMacOS27Layout: usesMacOS27Layout,
            macOS27Layout: Defaults.dictionary(forKey: .macOS27Layout) as? [String: Int] ?? [:],
            itemSections: Defaults.dictionary(forKey: .itemSections) as? [String: Int] ?? [:],
            running: running,
            ownBundleIdentifier: Constants.bundleIdentifier
        )
        return HolzBarShelfClosedAppList(
            hidden: entries(for: remembered.hidden),
            alwaysHidden: entries(for: remembered.alwaysHidden)
        )
    }

    /// The installed applications among the identifiers; one that is gone from the Mac is left out.
    private static func entries(for bundleIdentifiers: [String]) -> [Entry] {
        let entries: [Entry] = bundleIdentifiers.compactMap { bundleIdentifier in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                return nil
            }
            var name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") {
                name.removeLast(4)
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 18, height: 18)
            return Entry(app: ShelfContents.ClosedApp(bundleID: bundleIdentifier, name: name), url: url, icon: icon)
        }
        return entries.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    /// The entry of an application, from either section.
    func entry(forBundleIdentifier bundleIdentifier: String) -> Entry? {
        (hidden + alwaysHidden).first { $0.app.bundleID == bundleIdentifier }
    }
}

// MARK: - HolzBarShelfTileRegistry

/// The views of the tiles, so a drag can read where each tile is on the screen.
///
/// The frames are read when the pointer moves, never stored: a tile that scrolled or moved is
/// where its view is. The views are held weakly.
@MainActor
final class HolzBarShelfTileRegistry {
    private struct Entry {
        weak var view: NSView?
    }

    private var entries = [String: Entry]()

    func register(_ view: NSView, id: String) {
        entries[id] = Entry(view: view)
    }

    /// The frame of the tile on the screen, in AppKit's coordinates; `nil` when its view is gone
    /// or not in a window.
    func screenFrame(of id: String) -> CGRect? {
        guard let view = entries[id]?.view, let window = view.window else {
            return nil
        }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// Puts a view behind a tile that tells the registry where the tile is.
struct HolzBarShelfFrameReporter: NSViewRepresentable {
    let id: String
    let registry: HolzBarShelfTileRegistry

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        registry.register(view, id: id)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        registry.register(nsView, id: id)
    }
}

// MARK: - Drag

/// What the Shelf shows while a tile is dragged.
@MainActor
@Observable
final class HolzBarShelfDragModel {
    /// The tile being dragged.
    var draggedID: String?
    /// What releasing it now would do.
    var outcome = ShelfDrop.Outcome.none
}

/// The steps of a drag that a tile reports.
struct HolzBarShelfDragActions {
    /// The picture that follows the pointer.
    let image: NSImage?
    /// Asked once when the press has moved far enough to be a drag; `false` refuses the drag.
    let canBegin: () -> Bool
    let began: () -> Void
    let moved: () -> Void
    let ended: () -> Void
}

/// How a tile shows that a drag would drop on it.
enum HolzBarShelfDropIndication {
    /// A mark before the tile (left of it, or above it in a column).
    case before
    /// A mark after the tile.
    case after
    /// The whole tile: the drop goes into its section.
    case onto
}

private extension View {
    /// Draws the mark of a drop on the tile.
    func dropIndication(_ indication: HolzBarShelfDropIndication?, axis: ShelfDrop.Axis) -> some View {
        overlay {
            if let indication {
                switch indication {
                case .onto:
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                case .before, .after:
                    let isBefore = indication == .before
                    switch axis {
                    case .horizontal:
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: 2)
                            .frame(maxWidth: .infinity, alignment: isBefore ? .leading : .trailing)
                    case .vertical:
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(height: 2)
                            .frame(maxHeight: .infinity, alignment: isBefore ? .top : .bottom)
                    }
                }
            }
        }
    }

    /// Draws the keyboard highlight of the tile.
    func keyboardHighlight(_ isHighlighted: Bool) -> some View {
        background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.2))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    }
            }
        }
    }
}

// MARK: - Actions

/// What a tile does when it is opened, by a click or the keyboard.
@MainActor
enum HolzBarShelfActions {
    /// Closes the Shelf and opens the item's menu, as a click on the item in the menu bar would.
    static func open(
        _ item: MenuBarItem,
        mouseButton: CGMouseButton,
        section: MenuBarSection.Name,
        itemManager: MenuBarItemManager?,
        menuBarManager: MenuBarManager?
    ) {
        guard let itemManager, let menuBarManager else {
            return
        }
        let shelfDisplayID = menuBarManager.shelfPanel.screen?.displayID
        menuBarManager.section(withName: section)?.hide()
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            await itemManager.openItem(item, mouseButton: mouseButton, shelfDisplayID: shelfDisplayID, origin: .click)
        }
    }

    /// Closes the Shelf and opens a system item the user hid: the clock, Control Center, Wi-Fi
    /// or the battery. macOS 27 only; the item is lifted for a moment and put away again.
    static func openSystemItem(
        _ item: SystemItem27,
        section: MenuBarSection.Name,
        appState: AppState,
        menuBarManager: MenuBarManager?
    ) {
        guard #available(macOS 27.0, *), let menuBarManager else {
            return
        }
        let shelfDisplayID = menuBarManager.shelfPanel.screen?.displayID
        menuBarManager.section(withName: section)?.hide()
        Task {
            try? await Task.sleep(for: .milliseconds(25))
            await SystemItemClickBridge27.openFromShelf(item, shelfDisplayID: shelfDisplayID, appState: appState)
        }
    }

    /// Closes the Shelf and launches an application that is not running.
    static func launch(
        _ entry: HolzBarShelfClosedAppList.Entry,
        section: MenuBarSection.Name,
        menuBarManager: MenuBarManager?
    ) {
        menuBarManager?.section(withName: section)?.hide()
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: entry.url, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                Logger.default.error("Could not open an application from the holzBar Shelf - \(error, privacy: .private)")
            }
        }
    }
}

// MARK: - HolzBarShelfItemView

struct HolzBarShelfItemView: View {
    var imageCache: MenuBarItemImageCache
    var itemManager: MenuBarItemManager
    var menuBarManager: MenuBarManager
    var registry: HolzBarShelfTileRegistry

    let item: MenuBarItem
    let section: MenuBarSection.Name
    let tileID: String
    /// Whether the arrows of the keyboard highlight the item.
    var isHighlighted = false
    /// Whether the item is left out of the matches of a search.
    var isDimmed = false
    var dropIndication: HolzBarShelfDropIndication?
    var axis = ShelfDrop.Axis.horizontal
    /// The steps of a drag, `nil` for an item that cannot be dragged.
    var drag: HolzBarShelfDragActions?

    private var leftClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager, item, section] in
            HolzBarShelfActions.open(item, mouseButton: .left, section: section, itemManager: itemManager, menuBarManager: menuBarManager)
        }
    }

    private var rightClickAction: () -> Void {
        return { [weak itemManager, weak menuBarManager, item, section] in
            HolzBarShelfActions.open(item, mouseButton: .right, section: section, itemManager: itemManager, menuBarManager: menuBarManager)
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
        .opacity(isDimmed ? 0.35 : 1)
        .background(HolzBarShelfFrameReporter(id: tileID, registry: registry))
        .overlay {
            HolzBarShelfClickView(
                toolTip: item.displayName,
                leftClickAction: leftClickAction,
                rightClickAction: rightClickAction,
                drag: drag
            )
        }
        .keyboardHighlight(isHighlighted)
        .dropIndication(dropIndication, axis: axis)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityLabel(item.displayName)
        .accessibilityAction(.default, leftClickAction)
        .accessibilityAction(named: "Open", leftClickAction)
        .accessibilityAction(named: "Open Menu", rightClickAction)
    }
}

// MARK: - HolzBarShelfFoldView

/// The tile that folds the always-hidden items: "+3" while they are folded, a minus while open.
struct HolzBarShelfFoldView: View {
    var registry: HolzBarShelfTileRegistry

    let count: Int
    let isOpen: Bool
    let tileID: String
    var isHighlighted = false
    var dropIndication: HolzBarShelfDropIndication?
    let toggle: () -> Void

    var body: some View {
        Group {
            if isOpen {
                Image(systemName: "minus")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            } else {
                Text(verbatim: "+\(count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.18)))
        .padding(.horizontal, 3)
        .contentShape(Rectangle())
        .background(HolzBarShelfFrameReporter(id: tileID, registry: registry))
        .overlay {
            HolzBarShelfClickView(
                toolTip: isOpen ? String(localized: "Fold the always-hidden items") : String(localized: "Show the always-hidden items"),
                leftClickAction: toggle,
                rightClickAction: nil,
                drag: nil
            )
        }
        .keyboardHighlight(isHighlighted)
        .dropIndication(dropIndication, axis: .horizontal)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityLabel(Text("Always-hidden items"))
        .accessibilityValue(isOpen ? Text("Open") : Text("Folded"))
        .accessibilityAction(.default, toggle)
    }
}

// MARK: - HolzBarShelfClosedAppView

/// An application that is not running, dimmed; a click launches it.
struct HolzBarShelfClosedAppView: View {
    var registry: HolzBarShelfTileRegistry

    let entry: HolzBarShelfClosedAppList.Entry
    let tileID: String
    var isHighlighted = false
    var isDimmed = false
    var dropIndication: HolzBarShelfDropIndication?
    let launch: () -> Void

    var body: some View {
        Image(nsImage: entry.icon)
            .accessibilityHidden(true)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .opacity(isDimmed ? 0.2 : 0.45)
            .background(HolzBarShelfFrameReporter(id: tileID, registry: registry))
            .overlay {
                HolzBarShelfClickView(
                    toolTip: String(localized: "\(entry.app.name) is not running. Click to open it."),
                    leftClickAction: launch,
                    rightClickAction: nil,
                    drag: nil
                )
            }
            .keyboardHighlight(isHighlighted)
            .dropIndication(dropIndication, axis: .horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            .accessibilityLabel(entry.app.name)
            .accessibilityHint(Text("Not running"))
            .accessibilityAction(.default, launch)
    }
}

// MARK: - HolzBarShelfSystemItemView

/// A system item the user hid, as a symbol tile: macOS draws no picture of a concealed item. A
/// click lifts the item for a moment and opens it where macOS draws it. The tile cannot be
/// dragged and accepts no drop.
struct HolzBarShelfSystemItemView: View {
    var registry: HolzBarShelfTileRegistry

    let symbolName: String
    let name: String
    let tileID: String
    var isHighlighted = false
    var isDimmed = false
    var dropIndication: HolzBarShelfDropIndication?
    let open: () -> Void

    var body: some View {
        Image(systemName: symbolName)
            .renderingMode(.template)
            .imageScale(.large)
            .accessibilityHidden(true)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .opacity(isDimmed ? 0.35 : 1)
            .background(HolzBarShelfFrameReporter(id: tileID, registry: registry))
            .overlay {
                HolzBarShelfClickView(
                    toolTip: name,
                    leftClickAction: open,
                    rightClickAction: nil,
                    drag: nil
                )
            }
            .keyboardHighlight(isHighlighted)
            .dropIndication(dropIndication, axis: .horizontal)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isHighlighted ? .isSelected : [])
            .accessibilityLabel(name)
            .accessibilityHint(Text("Opens the item"))
            .accessibilityAction(.default, open)
    }
}

// MARK: - HolzBarShelfDividerView

/// The thin line between the always-hidden items and the rest.
struct HolzBarShelfDividerView: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.3))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }
}

// MARK: - HolzBarShelfFindView

/// Shows what was typed to find an item: a magnifier, and the text once there is some.
struct HolzBarShelfFindView: View {
    let query: String
    /// Whether the query matches anything.
    let hasMatches: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
            if !query.isEmpty {
                Text(verbatim: query)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.15)))
        .opacity(query.isEmpty || hasMatches ? 1 : 0.55)
        .padding(.horizontal, 4)
        .help("Type to find an item")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Find items by typing"))
        .accessibilityValue(Text(verbatim: query))
    }
}

// MARK: - HolzBarShelfClickView

/// Takes the clicks of a tile and, for an item, the start of a drag.
///
/// A click is a press and release within half a second and 5 points; a press that moves
/// further than that is a drag, which starts a dragging session when the tile can be dragged.
struct HolzBarShelfClickView: NSViewRepresentable {
    private final class Represented: NSView, NSDraggingSource {
        var leftClickAction: () -> Void
        var rightClickAction: (() -> Void)?
        var drag: HolzBarShelfDragActions?

        private var lastLeftMouseDownDate = Date.now
        private var lastRightMouseDownDate = Date.now

        private var lastLeftMouseDownLocation = CGPoint.zero
        private var lastRightMouseDownLocation = CGPoint.zero

        /// Whether a dragging session started from this press.
        private var isDragging = false

        /// A tile that can be dragged does not move the Shelf's window when it is dragged.
        override var mouseDownCanMoveWindow: Bool {
            drag == nil
        }

        init(
            toolTip: String,
            leftClickAction: @escaping () -> Void,
            rightClickAction: (() -> Void)?,
            drag: HolzBarShelfDragActions?
        ) {
            self.leftClickAction = leftClickAction
            self.rightClickAction = rightClickAction
            self.drag = drag
            super.init(frame: .zero)
            self.toolTip = toolTip
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func mouseDown(with event: NSEvent) {
            super.mouseDown(with: event)
            lastLeftMouseDownDate = .now
            lastLeftMouseDownLocation = NSEvent.mouseLocation
            isDragging = false
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
                let rightClickAction,
                Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
                lastRightMouseDownLocation.distance(to: NSEvent.mouseLocation) < 5
            else {
                return
            }
            rightClickAction()
        }

        override func mouseDragged(with event: NSEvent) {
            super.mouseDragged(with: event)
            guard
                let drag,
                !isDragging,
                lastLeftMouseDownLocation.distance(to: NSEvent.mouseLocation) >= 5
            else {
                return
            }
            // Asked once for each press: a refused drag is not asked again as the pointer moves.
            isDragging = true
            guard drag.canBegin() else {
                return
            }

            // The data does not matter, but a dragging session needs a pasteboard type.
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setData(Data(), forType: .holzBarShelfTile)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            var frame = bounds
            if let image = drag.image {
                frame = CGRect(
                    x: bounds.midX - image.size.width / 2,
                    y: bounds.midY - image.size.height / 2,
                    width: image.size.width,
                    height: image.size.height
                )
            }
            draggingItem.setDraggingFrame(frame, contents: drag.image)
            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        // MARK: NSDraggingSource

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .move
        }

        func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
            // The drop is worked out from the pointer, not by a destination, so the picture
            // never flies back.
            session.animatesToStartingPositionsOnCancelOrFail = false
            drag?.began()
        }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            drag?.moved()
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            isDragging = false
            drag?.ended()
        }
    }

    let toolTip: String
    let leftClickAction: () -> Void
    let rightClickAction: (() -> Void)?
    let drag: HolzBarShelfDragActions?

    func makeNSView(context: Context) -> NSView {
        Represented(
            toolTip: toolTip,
            leftClickAction: leftClickAction,
            rightClickAction: rightClickAction,
            drag: drag
        )
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // The steps of a drag read the Shelf as it is now; the view keeps the latest.
        guard let view = nsView as? Represented else {
            return
        }
        view.leftClickAction = leftClickAction
        view.rightClickAction = rightClickAction
        view.drag = drag
        view.toolTip = toolTip
    }
}

extension NSPasteboard.PasteboardType {
    /// The type of a tile dragged in the holzBar Shelf. Its data is empty: the drag only needs a type.
    static let holzBarShelfTile = Self("\(Constants.bundleIdentifier).shelf-tile")
}
