//
//  DockBadgeItems.swift
//  holzBar
//

import AppKit

/// The menu bar items of Dock badges: one status item per chosen app outside a group, showing the
/// app's own icon with a bubble that holds the badge the Dock shows on it, and one per group, showing
/// its first two apps' icons overlapped with one bubble that holds the sum of their badges.
///
/// An item is a status item of holzBar's own, created the way a widget's is: its autosave name
/// (``DockBadgeItemName``) is registered with ``OwnStatusItemWindows`` and set as the button's
/// accessibility identifier, so that holzBar finds it among the menu bar's items on every macOS.
/// The bubble is a ``CountBadgeView`` in the Dock's red over the icon's top trailing corner,
/// hidden while the badge is zero or absent. Every item has one length, measured once from the
/// widest bubble ("99+") and the icon, so a changing count never moves a neighbour; the bubble
/// grows toward the icon's middle. The tooltip and VoiceOver carry the real count or the whole
/// label; nothing is announced when it changes. A click opens the app, found through the item's
/// own autosave name; a click on a group's item opens its menu (``DockBadgeGroupMenu``), built from
/// the badges in memory, in which choosing an app opens it. Every item also has a picture that holzBar draws of it (the icon and, when
/// shown, the bubble), kept in memory and handed out through the closure the owner gives, for the
/// Shelf, the Layout pane and the search, which cannot capture an item of holzBar's own. Where
/// macOS 27 does not draw the section an item is in, the item collapses to no width, as a widget
/// does. At a count of zero an item follows the zero mode (``DockBadgeZeroMode``): dimmed to half
/// strength without a bubble, or collapsed to no width in its place until the count is above zero,
/// instantly and without animation. The class holds no timer, no observer and no task: ``DockBadges`` tells it what to show.
/// App names and badge texts stay in memory and are never logged.
@MainActor
final class DockBadgeItems {
    /// One item: an app's, or a group's.
    private final class Entry {
        let kind: DockBadgeItemKind
        let statusItem: NSStatusItem
        let autosaveName: String
        /// The app's name, or the group's.
        var name: String
        /// The bundle identifiers of the apps the item shows: the app's own, or the group's chosen
        /// apps in the group's order.
        var members: [String]
        /// What the item draws: the app's icon, or the first two members' icons overlapped.
        var icon: NSImage?
        /// The same at half strength, for a count of zero in the mode Dim.
        var dimmedIcon: NSImage?
        /// The width of the icon or the pair of icons.
        var iconWidth: CGFloat
        /// The members the icons were drawn from.
        var iconMembers: [String]
        let bubble = CountBadgeView(style: .dockBadge)
        let clickTarget: ClickTarget
        /// What the picture last drawn shows, so that it is drawn again only when that changes.
        var pictureKey: String?
        /// Whether the item is collapsed to no width.
        var isCollapsed = false
        /// Whether the count is zero in the mode Hide.
        var isHiddenAtZero = false
        /// The length the status item has now.
        var appliedLength: CGFloat

        init(
            kind: DockBadgeItemKind,
            statusItem: NSStatusItem,
            name: String,
            members: [String],
            strip: Strip,
            owner: DockBadgeItems
        ) {
            self.kind = kind
            self.statusItem = statusItem
            autosaveName = kind.autosaveName
            self.name = name
            self.members = members
            icon = strip.icon
            dimmedIcon = strip.dimmed
            iconWidth = strip.width
            iconMembers = Array(members.prefix(2))
            appliedLength = DockBadgeItems.length(forIconWidth: strip.width)
            clickTarget = ClickTarget(statusItem: statusItem, owner: owner)
        }

        /// The one length of the item for the icons it draws.
        var fixedLength: CGFloat {
            DockBadgeItems.length(forIconWidth: iconWidth)
        }
    }

    /// What an item draws: the image, its half-strength copy and the width.
    private struct Strip {
        var icon: NSImage?
        var dimmed: NSImage?
        var width: CGFloat
    }

    /// What a click on an item does: opens the app an app's item belongs to, or the menu of a
    /// group's. What it opens comes from the item's own autosave name, a chosen bundle identifier
    /// or a group's identifier, and never from any text the Dock delivered.
    private final class ClickTarget: NSObject {
        private weak var statusItem: NSStatusItem?
        private weak var owner: DockBadgeItems?

        init(statusItem: NSStatusItem, owner: DockBadgeItems) {
            self.statusItem = statusItem
            self.owner = owner
        }

        @objc func clicked(_ sender: Any?) {
            guard let autosaveName = statusItem?.autosaveName else {
                return
            }
            owner?.clicked(autosaveName: autosaveName)
        }
    }

    /// The width of the widest bubble, "99+", measured once (R7).
    private static let widestBubble = CountBadgeView.width(for: "\(DesignTokens.DockBadge.countLimit)+")

    /// The one length of every item that draws icons of the given width: the icons centred with
    /// room on both sides for the bubble's overhang or for the widest bubble, whichever is more.
    /// It depends on the icons only (one icon, or a pair), never on a count (R7).
    private static func length(forIconWidth iconWidth: CGFloat) -> CGFloat {
        let overhang = CGFloat(DesignTokens.DockBadge.bubbleOverhang)
        return iconWidth + 2 * max(overhang, widestBubble - iconWidth - overhang)
    }

    /// The most recent set of items, so that a click routed by holzBar (from the Shelf, the
    /// search or a hotkey) can open a group's menu.
    private static weak var active: DockBadgeItems?

    /// The items by autosave name.
    private var entries = [String: Entry]()

    /// The badge of each chosen app as last told, for a group's menu.
    private var labels = [String: DockBadgeLabel]()

    /// Where the items stand now, as ``DockBadges`` last told.
    private var visibility = DockBadgeVisibility.Inputs()

    /// What an item shows at a count of zero.
    private var zeroMode = DockBadgeZeroMode.dim

    /// Told whenever an item's picture is drawn (with the picture) or the item goes (with `nil`).
    private let pictureChanged: (String, NSImage?) -> Void

    /// - Parameter pictureChanged: Called with an item's autosave name and its new picture, or
    ///   `nil` when the item is no longer in the menu bar.
    init(pictureChanged: @escaping (String, NSImage?) -> Void) {
        self.pictureChanged = pictureChanged
        Self.active = self
    }

    /// Shows the given items and takes away the items that are no longer wanted (an app that was
    /// switched off, or put into a group, forgets its place in the menu bar). Each item shows the
    /// badge of its app, or the sum of its group's, none when it has no entry.
    ///
    /// - Parameters:
    ///   - kinds: The items to show, from ``DockBadgeItemList``.
    ///   - apps: The bundle identifiers of the chosen apps.
    ///   - groups: The groups of the chosen apps.
    ///   - labels: The badge of each app by bundle identifier; an app without one has none, which
    ///     is the case of an app that left the Dock.
    ///   - zeroMode: What an item shows while its count is zero.
    func update(
        kinds: [DockBadgeItemKind],
        apps: [String],
        groups: [DockBadgeGroup],
        labels: [String: DockBadgeLabel],
        zeroMode: DockBadgeZeroMode
    ) {
        self.zeroMode = zeroMode
        self.labels = labels
        let wanted = Set(kinds.map(\.autosaveName))
        for name in entries.keys where !wanted.contains(name) {
            remove(name, keepingPosition: false)
        }
        for kind in kinds {
            let entry: Entry
            switch kind {
            case .app(let bundleID):
                entry = entries[kind.autosaveName] ?? makeEntry(for: kind, name: nil, members: [bundleID])
                show(labels[bundleID] ?? .none, on: entry)
            case .group(let id):
                guard let group = groups.first(where: { $0.id == id }) else {
                    continue
                }
                let members = DockBadgeItemList.members(of: group, in: groups, apps: apps)
                entry = entries[kind.autosaveName] ?? makeEntry(for: kind, name: group.name, members: members)
                refresh(group: entry, name: group.name, members: members)
                show(DockBadgeSum.of(members.map { labels[$0] ?? .none }), on: entry)
            }
        }
    }

    /// Collapses the items that stand in a section the bar does not draw (macOS 27 only) and gives
    /// the others their length again.
    func apply(visibility: DockBadgeVisibility.Inputs) {
        guard visibility != self.visibility else {
            return
        }
        self.visibility = visibility
        for entry in entries.values {
            applyLength(of: entry)
        }
    }

    /// Takes every item out of the menu bar. With `keepingPosition` the place macOS remembered
    /// for each stays, so the items come back where they were.
    func removeAll(keepingPosition: Bool) {
        for name in Array(entries.keys) {
            remove(name, keepingPosition: keepingPosition)
        }
    }

    // MARK: Items

    private func makeEntry(for kind: DockBadgeItemKind, name groupName: String?, members: [String]) -> Entry {
        let autosaveName = kind.autosaveName
        let strip = Self.strip(for: kind, members: members)
        let statusItem = NSStatusBar.system.statusItem(withLength: Self.length(forIconWidth: strip.width))
        statusItem.autosaveName = autosaveName
        // On macOS 26, holzBar recognises its own items' windows by their frames.
        OwnStatusItemWindows.register(statusItem, forAutosaveName: autosaveName)
        let name: String
        if let groupName {
            name = groupName
        } else if case .app(let bundleID) = kind {
            name = BuiltInItemActions.applicationName(forBundleID: bundleID) ?? bundleID
        } else {
            name = autosaveName
        }
        let entry = Entry(kind: kind, statusItem: statusItem, name: name, members: members, strip: strip, owner: self)
        entries[autosaveName] = entry
        applyLength(of: entry)
        guard let button = statusItem.button else {
            return entry
        }
        // On macOS 27, holzBar finds its own items through Accessibility by this identifier; a
        // plain status item reports an empty one, and so it would not be listed.
        button.setAccessibilityIdentifier(autosaveName)
        button.setAccessibilityLabel(name)
        OwnStatusItemNames.set(name, forAutosaveName: autosaveName)
        button.image = entry.icon
        button.imagePosition = .imageOnly
        // A click in the Dock acts when the button is released, and so does this one.
        button.target = entry.clickTarget
        button.action = #selector(ClickTarget.clicked(_:))
        button.sendAction(on: [.leftMouseUp])
        button.addSubview(entry.bubble)
        entry.bubble.isHidden = true
        return entry
    }

    /// Brings a group's item in line with the group: its name (the label for VoiceOver and for
    /// holzBar) and the icons of its first two members, with the length they need.
    private func refresh(group entry: Entry, name: String, members: [String]) {
        entry.members = members
        if entry.name != name {
            entry.name = name
            entry.statusItem.button?.setAccessibilityLabel(name)
            OwnStatusItemNames.set(name, forAutosaveName: entry.autosaveName)
        }
        let firstTwo = Array(members.prefix(2))
        guard firstTwo != entry.iconMembers else {
            return
        }
        let strip = Self.strip(for: entry.kind, members: members)
        entry.iconMembers = firstTwo
        entry.icon = strip.icon
        entry.dimmedIcon = strip.dimmed
        entry.iconWidth = strip.width
        entry.pictureKey = nil
        applyLength(of: entry)
    }

    /// What an item draws: an app's icon, or a group's first two members' icons overlapped (the
    /// first behind, the second in front, ``DesignTokens/DockBadge/groupIconOverlap`` to its
    /// right); a group with one app draws that app's icon alone, as an app's item does.
    private static func strip(for kind: DockBadgeItemKind, members: [String]) -> Strip {
        let size = CGFloat(DesignTokens.DockBadge.iconSize)
        let icon: NSImage?
        var width = size
        switch kind {
        case .app(let bundleID):
            icon = Self.icon(forBundleID: bundleID)
        case .group:
            let icons = members.prefix(2).map { Self.icon(forBundleID: $0) }
            if icons.count >= 2 {
                icon = pair(back: icons[0], front: icons[1])
                width = size + CGFloat(DesignTokens.DockBadge.groupIconOverlap)
            } else {
                icon = icons.first.flatMap { $0 }
            }
        }
        return Strip(icon: icon, dimmed: Self.dimmed(icon), width: width)
    }

    /// Two icons overlapped: the back one at the leading edge, the front one
    /// ``DesignTokens/DockBadge/groupIconOverlap`` to its right. The pair is a template only when
    /// both are stand-in symbols of apps that are not installed.
    private static func pair(back: NSImage?, front: NSImage?) -> NSImage {
        let size = CGFloat(DesignTokens.DockBadge.iconSize)
        let step = CGFloat(DesignTokens.DockBadge.groupIconOverlap)
        let image = NSImage(size: NSSize(width: size + step, height: size), flipped: false) { _ in
            back?.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
            front?.draw(in: CGRect(x: step, y: 0, width: size, height: size))
            return true
        }
        image.isTemplate = (back?.isTemplate ?? true) && (front?.isTemplate ?? true)
        return image
    }

    /// The app's own icon at the item's icon size, in full colour: this is the one coloured item
    /// of holzBar, so the image is never a template. A symbol stands in for an app that is not
    /// installed.
    private static func icon(forBundleID bundleID: String) -> NSImage? {
        let size = NSSize(width: DesignTokens.DockBadge.iconSize, height: DesignTokens.DockBadge.iconSize)
        guard let url = BuiltInItemActions.applicationURL(forBundleID: bundleID) else {
            let placeholder = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            placeholder?.size = size
            placeholder?.isTemplate = true
            return placeholder
        }
        let image = NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false))
        image.size = size
        image.isTemplate = false
        return image
    }

    /// The icon at half strength (``DesignTokens/DockBadge/dimAlpha``), a template when the icon
    /// is one.
    private static func dimmed(_ icon: NSImage?) -> NSImage? {
        guard let icon else {
            return nil
        }
        let alpha = CGFloat(DesignTokens.DockBadge.dimAlpha)
        let image = NSImage(size: icon.size, flipped: false) { bounds in
            icon.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: alpha)
            return true
        }
        image.isTemplate = icon.isTemplate
        return image
    }

    /// Handles a click that holzBar itself routes to one of its Dock badges items, from the
    /// Shelf, the search, a group or a hotkey: it does what a click on the item does, opening the
    /// app of an app's item or the menu of a group's. Returns whether the item is a Dock badges
    /// item; the other mouse buttons do nothing, as the item has no secondary menu.
    static func handlesOpen(of item: MenuBarItem, mouseButton: CGMouseButton) -> Bool {
        guard item.tag.namespace == .holzBar else {
            return false
        }
        if let bundleID = DockBadgeItemName.bundleID(fromAutosaveName: item.tag.title) {
            if mouseButton == .left {
                open(bundleID)
            }
            return true
        }
        if DockBadgeItemName.groupID(fromAutosaveName: item.tag.title) != nil {
            if mouseButton == .left {
                active?.showMenu(ofItemNamed: item.tag.title)
            }
            return true
        }
        return false
    }

    /// A click on an item's own button: opens the app of an app's item, the menu of a group's.
    private func clicked(autosaveName: String) {
        if let bundleID = DockBadgeItemName.bundleID(fromAutosaveName: autosaveName) {
            Self.open(bundleID)
        } else {
            showMenu(ofItemNamed: autosaveName)
        }
    }

    /// Shows the menu of a group's item, built now from the badges in memory: under the item while
    /// it is in the bar, and where the pointer is while it is not (concealed, collapsed, or the
    /// click came from the Shelf).
    private func showMenu(ofItemNamed name: String) {
        guard let entry = entries[name], case .group = entry.kind, !entry.members.isEmpty else {
            return
        }
        let menu = DockBadgeGroupMenu.menu(title: entry.name, members: entry.members, labels: labels)
        if !entry.isCollapsed,
            let frame = entry.statusItem.button?.window?.frame,
            NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) {
            entry.statusItem.showMenu(menu)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// Opens the app, or brings it forward when it runs, as a click in the Dock does. An app that
    /// is not installed makes the Mac beep.
    static func open(_ bundleID: String) {
        guard let url = BuiltInItemActions.applicationURL(forBundleID: bundleID) else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    private func remove(_ name: String, keepingPosition: Bool) {
        guard let entry = entries.removeValue(forKey: name) else {
            return
        }
        // Removing a status item deletes its preferred position. Cache and restore it, as the
        // widgets and the control items do.
        let position = ControlItemDefaults[.preferredPosition, name]
        entry.bubble.removeFromSuperview()
        NSStatusBar.system.removeStatusItem(entry.statusItem)
        pictureChanged(name, nil)
        OwnStatusItemWindows.unregister(autosaveName: name)
        OwnStatusItemNames.set(nil, forAutosaveName: name)
        if keepingPosition {
            ControlItemDefaults[.preferredPosition, name] = position
        } else {
            ControlItemDefaults[.preferredPosition, name] = nil
            ControlItemDefaults[.visible, name] = nil
            ControlItemDefaults[.visibleCC, name] = nil
        }
    }

    // MARK: Bubble

    /// Shows the label: the bubble with its text (hidden at zero), the icon at half strength at
    /// zero in the mode Dim, the item's width (none at zero in the mode Hide), the tooltip and the
    /// VoiceOver value. Nothing is posted to VoiceOver, so a changing count is read only when the
    /// item is focused.
    private func show(_ label: DockBadgeLabel, on entry: Entry) {
        let text = label.bubbleText
        let isDimmed = label.isZero && zeroMode == .dim
        entry.isHiddenAtZero = label.isZero && zeroMode == .hide
        applyLength(of: entry)
        if let text {
            if entry.bubble.text != text {
                entry.bubble.text = text
            }
            entry.bubble.isHidden = false
        } else {
            entry.bubble.isHidden = true
        }
        guard let button = entry.statusItem.button else {
            return
        }
        let icon = isDimmed ? entry.dimmedIcon : entry.icon
        if button.image !== icon {
            button.image = icon
        }
        let value = label.fullText ?? String(localized: "No badge")
        let tooltip = String(localized: "\(entry.name): \(value)")
        if button.toolTip != tooltip {
            button.toolTip = tooltip
        }
        if button.accessibilityValue() as? String != value {
            button.setAccessibilityValue(value)
        }
        if let text {
            position(entry.bubble, text: text, of: entry, on: button)
        }
        updatePicture(of: entry, bubbleText: text, isDimmed: isDimmed)
    }

    // MARK: Length

    /// Sets the status item's length: the fixed one, or none while the item is collapsed (in a
    /// section macOS 27 does not draw, or at zero in the mode Hide). As
    /// `ControlItem.updateStatusItemVisibility` collapses a divider, the item's window is made one
    /// point wide as well. The item keeps its element while collapsed, so it stays in the item
    /// list, the Shelf and the search; its picture is the one holzBar draws itself.
    private func applyLength(of entry: Entry) {
        let isCollapsed = entry.isHiddenAtZero || visibility.collapsed.contains(entry.autosaveName)
        let length = isCollapsed ? 0 : entry.fixedLength
        guard length != entry.appliedLength else {
            return
        }
        entry.isCollapsed = isCollapsed
        entry.appliedLength = length
        entry.statusItem.length = length
        guard isCollapsed, let window = entry.statusItem.button?.window else {
            return
        }
        var size = window.frame.size
        size.width = 1
        window.setContentSize(size)
    }

    // MARK: Picture

    /// Draws the picture of the item again when what it shows changed: the icon (at half strength
    /// when it is dimmed) and, when there is a bubble, the bubble as the item has it. An item
    /// collapsed at zero keeps the picture of a dimmed one, for the Shelf and the Layout pane.
    private func updatePicture(of entry: Entry, bubbleText: String?, isDimmed: Bool) {
        let key = "\(bubbleText ?? "")|\(isDimmed)"
        guard entry.pictureKey != key else {
            return
        }
        entry.pictureKey = key
        var bubble: (image: NSImage, size: CGSize)?
        if bubbleText != nil {
            let bounds = entry.bubble.bounds
            if let rep = entry.bubble.bitmapImageRepForCachingDisplay(in: bounds) {
                entry.bubble.cacheDisplay(in: bounds, to: rep)
                let image = NSImage(size: bounds.size)
                image.addRepresentation(rep)
                bubble = (image, bounds.size)
            }
        }
        let picture = Self.picture(
            icon: isDimmed ? entry.dimmedIcon : entry.icon,
            iconWidth: entry.iconWidth,
            bubble: bubble
        )
        pictureChanged(entry.autosaveName, picture)
    }

    /// The picture of an item at the height of a menu bar item: the icon or the pair of icons in the
    /// middle and the bubble in its place on the icon's top trailing corner, kept inside the picture.
    private static func picture(icon: NSImage?, iconWidth: CGFloat, bubble: (image: NSImage, size: CGSize)?) -> NSImage {
        let height = ItemIconStore.drawnHeight
        let length = Self.length(forIconWidth: iconWidth)
        let iconSize = CGFloat(DesignTokens.DockBadge.iconSize)
        let iconFrame = CGRect(
            x: (length - iconWidth) / 2,
            y: (height - iconSize) / 2,
            width: iconWidth,
            height: iconSize
        )
        let bubbleRect = bubble.map {
            Self.bubbleFrame(width: $0.size.width, iconWidth: iconWidth, barHeight: height, isFlipped: false)
        }
        let image = NSImage(size: NSSize(width: length, height: height), flipped: false) { _ in
            icon?.draw(in: iconFrame)
            if let bubble, let bubbleRect {
                bubble.image.draw(in: bubbleRect)
            }
            return true
        }
        // The stand-in symbol of an app that is not installed is a template; with a bubble the
        // picture keeps its colour.
        image.isTemplate = (icon?.isTemplate ?? false) && bubble == nil
        return image
    }

    /// Places the bubble on the icon's top trailing corner (see
    /// ``bubbleFrame(width:iconWidth:barHeight:isFlipped:)``); the icon sits in the middle of the
    /// item, so the place follows from the item's fixed length and the bar's height and not from
    /// how the button has laid itself out.
    private func position(_ bubble: CountBadgeView, text: String, of entry: Entry, on button: NSStatusBarButton) {
        let barHeight = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
        let width = min(CountBadgeView.width(for: text), entry.fixedLength)
        let frame = Self.bubbleFrame(width: width, iconWidth: entry.iconWidth, barHeight: barHeight, isFlipped: button.isFlipped)
        if bubble.frame != frame {
            bubble.frame = frame
        }
    }

    /// Where the bubble sits in an item of the bar's height whose icons are `iconWidth` wide: its
    /// trailing edge `bubbleOverhang` beyond the icons' trailing edge and its top `bubbleRise`
    /// above the icons' top, growing toward the icons' middle, and never above the top of the item.
    /// A text wider than the item is cut to the item.
    private static func bubbleFrame(width: CGFloat, iconWidth: CGFloat, barHeight: CGFloat, isFlipped: Bool) -> CGRect {
        let icon = CGFloat(DesignTokens.DockBadge.iconSize)
        let height = CountBadgeView.height
        let iconTrailing = (length(forIconWidth: iconWidth) + iconWidth) / 2
        let x = max(iconTrailing + CGFloat(DesignTokens.DockBadge.bubbleOverhang) - width, 0)
        let iconBottom = (barHeight - icon) / 2
        let rise = CGFloat(DesignTokens.DockBadge.bubbleRise)
        let y = if isFlipped {
            max(iconBottom - rise, 0)
        } else {
            min(iconBottom + icon + rise - height, barHeight - height)
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
