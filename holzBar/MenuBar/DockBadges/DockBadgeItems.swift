//
//  DockBadgeItems.swift
//  holzBar
//

import AppKit

/// The menu bar items of Dock badges: one status item per chosen app, showing the app's own icon
/// with a bubble that holds the badge the Dock shows on it.
///
/// An item is a status item of holzBar's own, created the way a widget's is: its autosave name
/// (``DockBadgeItemName``) is registered with ``OwnStatusItemWindows`` and set as the button's
/// accessibility identifier, so that holzBar finds it among the menu bar's items on every macOS.
/// The bubble is a ``CountBadgeView`` in the Dock's red over the icon's top trailing corner,
/// hidden while the badge is zero or absent. Every item has one length, measured once from the
/// widest bubble ("99+") and the icon, so a changing count never moves a neighbour; the bubble
/// grows toward the icon's middle. The tooltip and VoiceOver carry the real count or the whole
/// label; nothing is announced when it changes. A click opens the app, found through the item's
/// own autosave name. The class holds no timer, no observer and no task: ``DockBadges`` tells it
/// what to show. App names and badge texts stay in memory and are never logged.
@MainActor
final class DockBadgeItems {
    /// One app's item.
    private final class Entry {
        let statusItem: NSStatusItem
        let name: String
        let bubble = CountBadgeView(style: .dockBadge)
        let clickTarget: ClickTarget

        init(statusItem: NSStatusItem, name: String) {
            self.statusItem = statusItem
            self.name = name
            clickTarget = ClickTarget(statusItem: statusItem)
        }
    }

    /// What a click on an item does: opens the app the item belongs to. The app comes from the
    /// item's own autosave name, a chosen bundle identifier, and never from any text the Dock
    /// delivered.
    private final class ClickTarget: NSObject {
        private weak var statusItem: NSStatusItem?

        init(statusItem: NSStatusItem) {
            self.statusItem = statusItem
        }

        @objc func clicked(_ sender: Any?) {
            guard
                let autosaveName = statusItem?.autosaveName,
                let bundleID = DockBadgeItemName.bundleID(fromAutosaveName: autosaveName)
            else {
                return
            }
            DockBadgeItems.open(bundleID)
        }
    }

    /// The one length of every item: the icon centred with room on both sides for the bubble's
    /// overhang or for the widest bubble, whichever is more. Measured once, never again (R7).
    private static let itemLength: CGFloat = {
        let icon = CGFloat(DesignTokens.DockBadge.iconSize)
        let overhang = CGFloat(DesignTokens.DockBadge.bubbleOverhang)
        let widest = CountBadgeView.width(for: "\(DesignTokens.DockBadge.countLimit)+")
        return icon + 2 * max(overhang, widest - icon - overhang)
    }()

    /// The items by bundle identifier.
    private var entries = [String: Entry]()

    /// Shows one item for each of the apps and takes away the items of apps that are no longer in
    /// the list (an app that was switched off forgets its place in the menu bar). Each item shows
    /// the label of its app, none when it has no entry.
    ///
    /// - Parameters:
    ///   - apps: The bundle identifiers of the chosen apps.
    ///   - labels: The badge of each app by bundle identifier; an app without one has none, which
    ///     is the case of an app that left the Dock.
    func update(apps: [String], labels: [String: DockBadgeLabel]) {
        let wanted = Set(apps)
        for bundleID in entries.keys where !wanted.contains(bundleID) {
            remove(bundleID, keepingPosition: false)
        }
        for bundleID in apps {
            let entry = entries[bundleID] ?? makeEntry(for: bundleID)
            show(labels[bundleID] ?? .none, on: entry)
        }
    }

    /// Takes every item out of the menu bar. With `keepingPosition` the place macOS remembered
    /// for each stays, so the items come back where they were.
    func removeAll(keepingPosition: Bool) {
        for bundleID in Array(entries.keys) {
            remove(bundleID, keepingPosition: keepingPosition)
        }
    }

    // MARK: Items

    private func makeEntry(for bundleID: String) -> Entry {
        let autosaveName = DockBadgeItemName.app(bundleID)
        let statusItem = NSStatusBar.system.statusItem(withLength: Self.itemLength)
        statusItem.autosaveName = autosaveName
        // On macOS 26, holzBar recognises its own items' windows by their frames.
        OwnStatusItemWindows.register(statusItem, forAutosaveName: autosaveName)
        let name = BuiltInItemActions.applicationName(forBundleID: bundleID) ?? bundleID
        let entry = Entry(statusItem: statusItem, name: name)
        entries[bundleID] = entry
        guard let button = statusItem.button else {
            return entry
        }
        // On macOS 27, holzBar finds its own items through Accessibility by this identifier; a
        // plain status item reports an empty one, and so it would not be listed.
        button.setAccessibilityIdentifier(autosaveName)
        button.setAccessibilityLabel(name)
        OwnStatusItemNames.set(name, forAutosaveName: autosaveName)
        button.image = Self.icon(forBundleID: bundleID)
        button.imagePosition = .imageOnly
        // A click in the Dock acts when the button is released, and so does this one.
        button.target = entry.clickTarget
        button.action = #selector(ClickTarget.clicked(_:))
        button.sendAction(on: [.leftMouseUp])
        button.addSubview(entry.bubble)
        entry.bubble.isHidden = true
        return entry
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

    /// Handles a click that holzBar itself routes to one of its Dock badges items, from the
    /// Shelf, the search, a group or a hotkey: it opens the app as a click on the item does.
    /// Returns whether the item is a Dock badges item; the other mouse buttons do nothing, as
    /// the item has no secondary menu.
    static func handlesOpen(of item: MenuBarItem, mouseButton: CGMouseButton) -> Bool {
        guard
            item.tag.namespace == .holzBar,
            let bundleID = DockBadgeItemName.bundleID(fromAutosaveName: item.tag.title)
        else {
            return false
        }
        if mouseButton == .left {
            open(bundleID)
        }
        return true
    }

    /// Opens the app, or brings it forward when it runs, as a click in the Dock does. An app that
    /// is not installed makes the Mac beep.
    private static func open(_ bundleID: String) {
        guard let url = BuiltInItemActions.applicationURL(forBundleID: bundleID) else {
            NSSound.beep()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    private func remove(_ bundleID: String, keepingPosition: Bool) {
        guard let entry = entries.removeValue(forKey: bundleID) else {
            return
        }
        let name = DockBadgeItemName.app(bundleID)
        // Removing a status item deletes its preferred position. Cache and restore it, as the
        // widgets and the control items do.
        let position = ControlItemDefaults[.preferredPosition, name]
        entry.bubble.removeFromSuperview()
        NSStatusBar.system.removeStatusItem(entry.statusItem)
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

    /// Shows the label: the bubble with its text (hidden at zero), the tooltip and the VoiceOver
    /// value. Nothing is posted to VoiceOver, so a changing count is read only when the item is
    /// focused.
    private func show(_ label: DockBadgeLabel, on entry: Entry) {
        let text = label.bubbleText
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
        let value = label.fullText ?? String(localized: "No badge")
        let tooltip = String(localized: "\(entry.name): \(value)")
        if button.toolTip != tooltip {
            button.toolTip = tooltip
        }
        if button.accessibilityValue() as? String != value {
            button.setAccessibilityValue(value)
        }
        if let text {
            position(entry.bubble, text: text, on: button)
        }
    }

    /// Places the bubble on the icon's top trailing corner: its trailing edge `bubbleOverhang`
    /// beyond the icon's trailing edge and its top `bubbleRise` above the icon's top, growing
    /// toward the icon's middle. The icon sits in the middle of the item, so the place follows
    /// from the item's fixed length and the bar's height and not from how the button has laid
    /// itself out; a text wider than the item is cut to the item.
    private func position(_ bubble: CountBadgeView, text: String, on button: NSStatusBarButton) {
        let icon = CGFloat(DesignTokens.DockBadge.iconSize)
        let barHeight = button.bounds.height > 0 ? button.bounds.height : NSStatusBar.system.thickness
        let width = min(CountBadgeView.width(for: text), Self.itemLength)
        let height = CountBadgeView.height
        let iconTrailing = (Self.itemLength + icon) / 2
        let x = max(iconTrailing + CGFloat(DesignTokens.DockBadge.bubbleOverhang) - width, 0)
        let iconBottom = (barHeight - icon) / 2
        let rise = CGFloat(DesignTokens.DockBadge.bubbleRise)
        let y = if button.isFlipped {
            iconBottom - rise
        } else {
            iconBottom + icon + rise - height
        }
        let frame = CGRect(x: x, y: y, width: width, height: height)
        if bubble.frame != frame {
            bubble.frame = frame
        }
    }
}
