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
/// The bubble is a ``CountBadgeView`` over the icon's top trailing corner, hidden while the badge
/// is zero or absent. The class holds no timer, no observer and no task: ``DockBadges`` tells it
/// what to show. App names and badge texts stay in memory and are never logged.
@MainActor
final class DockBadgeItems {
    /// One app's item.
    private final class Entry {
        let statusItem: NSStatusItem
        let bubble = CountBadgeView()

        init(statusItem: NSStatusItem) {
            self.statusItem = statusItem
        }
    }

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
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = autosaveName
        // On macOS 26, holzBar recognises its own items' windows by their frames.
        OwnStatusItemWindows.register(statusItem, forAutosaveName: autosaveName)
        let entry = Entry(statusItem: statusItem)
        entries[bundleID] = entry
        guard let button = statusItem.button else {
            return entry
        }
        // On macOS 27, holzBar finds its own items through Accessibility by this identifier; a
        // plain status item reports an empty one, and so it would not be listed.
        button.setAccessibilityIdentifier(autosaveName)
        let name = BuiltInItemActions.applicationName(forBundleID: bundleID) ?? bundleID
        button.setAccessibilityLabel(name)
        OwnStatusItemNames.set(name, forAutosaveName: autosaveName)
        if let icon = BuiltInItemActions.applicationIcon(forBundleID: bundleID) {
            button.image = icon
        } else {
            let image = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
        }
        button.addSubview(entry.bubble)
        entry.bubble.isHidden = true
        return entry
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

    private func show(_ label: DockBadgeLabel, on entry: Entry) {
        let text = Self.text(of: label)
        if entry.bubble.text != text {
            entry.bubble.text = text
        }
        entry.bubble.isHidden = label.isZero
        entry.bubble.frame.size.width = CountBadgeView.width(for: text)
        position(entry.bubble, on: entry.statusItem.button)
    }

    /// The text in the bubble: the number, or the mark as the Dock shows it.
    private static func text(of label: DockBadgeLabel) -> String {
        switch label {
        case .none: ""
        case .count(let number): String(number)
        case .mark(let text): text
        }
    }

    /// Places the bubble at the top trailing corner of the drawn icon, overlapping it and kept
    /// inside the button.
    private func position(_ bubble: CountBadgeView, on button: NSStatusBarButton?) {
        guard let button else {
            return
        }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let width = bubble.frame.width
        let height = CountBadgeView.height
        let x = max(min(imageRect.maxX - width + 2, button.bounds.maxX - width), button.bounds.minX)
        let y = if button.isFlipped {
            max(imageRect.minY - 1, button.bounds.minY)
        } else {
            min(imageRect.maxY - height + 1, button.bounds.maxY - height)
        }
        bubble.frame = CGRect(x: x, y: y, width: width, height: height)
    }
}
